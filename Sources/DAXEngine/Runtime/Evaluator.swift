// Evaluator (CORE, đợt 2), architecture.md §4.2, §4.3, §5.4, §7.4.
//
// Thiết kế:
// - `Evaluator` là một phiên đánh giá tuần tự (class). Ngăn xếp row context và VAR nằm trong phiên,
//   vì `EvalContext` của contract chỉ giữ một RowContext. Mỗi luồng dùng Evaluator riêng; ColumnStore và
//   EngineCache dùng chung được.
// - `ctx.row != nil` là dấu hiệu "có row context". Khi có, mọi khung trên ngăn xếp row được dùng.
//   Khi `ctx.row == nil` (ngữ cảnh mới, không kế thừa row), tham chiếu cột rơi về giá trị đơn của bộ lọc.
// - Bảng vật lý không được materialize khi lặp: `iterateExpr` lặp trên RowSet của R(T) (xem `iteratePhysical`).
//   `table(_:in:)` của bảng vật lý vẫn materialize, nên chỉ dùng cho bảng nhỏ hoặc khi bắt buộc.
// - Measure: context transition biến mọi khung row thành bộ lọc, rồi tra cache theo (measure, vân tay, băm dòng ảo).
// - VAR tính lười, đúng một lần, trong môi trường lúc khai báo (ngăn xếp row và VAR của thời điểm đó).
//
// [SUY ĐOÁN] Một khung row của bảng vật lý là dòng r của T. Context transition cho dòng đó là tập dòng
//   có cùng giá trị ở mọi cột của T (mọi dòng trùng đều thấy). Tìm bằng posting list của cột mã có ít dòng nhất.
// [SUY ĐOÁN] Tham chiếu cột không có row context: nếu bộ lọc có đúng một giá trị thì trả giá trị đó, không có
//   thì trả BLANK, nhiều giá trị thì báo lỗi. Đây là hành vi quan sát thường gặp, chưa đối chiếu oracle.
// [SUY ĐOÁN] Tên sentinel `virtualTable` (raw = -1) chỉ dùng làm dấu row context cho khung bảng ảo.
import ColumnStore

/// Khung row đang lặp. Bảng vật lý chỉ lưu (bảng, dòng); bảng ảo lưu cả bảng để tra lineage.
enum RowFrame: Sendable {
    case base(TableID, Int)
    case virtual(TableValue, Int)
}

/// Giá trị của một VAR. Bảng vật lý giữ dưới dạng RowSet, không materialize.
enum VarValue: Sendable {
    case scalar(Value)
    case table(TableValue)
    case rows(TableID, RowSet)
}

/// Một khối VAR…RETURN đang có hiệu lực. `values[i]` là kết quả đã tính (nil nếu chưa tính).
final class VarBlock {
    let slots: [Int]
    let exprs: [BoundExpr]
    let ctx: EvalContext
    let rowsAtEntry: [RowFrame]
    let varsBelow: [VarBlock]
    var values: [VarValue?]

    init(slots: [Int], exprs: [BoundExpr], ctx: EvalContext, rowsAtEntry: [RowFrame], varsBelow: [VarBlock]) {
        self.slots = slots
        self.exprs = exprs
        self.ctx = ctx
        self.rowsAtEntry = rowsAtEntry
        self.varsBelow = varsBelow
        self.values = [VarValue?](repeating: nil, count: slots.count)
    }
}

public final class Evaluator: Evaluating, @unchecked Sendable {
    /// Mã TableID dùng làm dấu row context cho khung bảng ảo (không phải bảng thật).
    static let virtualTable = TableID(raw: -1)

    public let store: ColumnStore
    public let catalog: Catalog
    public let cache: EngineCache
    /// Bảng hàm, cùng thứ tự với `FunctionRegistry.all` (Binder ghi chỉ số vào FunctionID).
    public let functions: [FunctionSpec]

    var rowStack: [RowFrame] = []
    var varStack: [VarBlock] = []
    public var currentGroupStack: [TableValue] = []
    /// Tổng số dòng đã materialize thành TableValue trong phiên (dùng để kiểm tra "không materialize khi lặp").
    public private(set) var materializedRowCount = 0
    private var boundMeasures: [MeasureID: BoundExpr] = [:]
    /// Measure đang được đánh giá trong phiên. DAX cấm chu trình measure, bất kể ngữ cảnh.
    private var measuresInProgress: Set<MeasureID> = []
    private var columnCache: [ColumnID: ColumnData] = [:]

    /// `functions` mặc định là bảng của registry. Test có thể thay thân hàm bằng cách giữ nguyên thứ tự.
    public init(store: ColumnStore, catalog: Catalog, cache: EngineCache = EngineCache(),
                functions: [FunctionSpec] = FunctionRegistry.all) {
        self.store = store
        self.catalog = catalog
        self.cache = cache
        self.functions = functions
    }

    /// Evaluator không có dữ liệu, giữ tương thích với contract đợt 0 (`Evaluator()`). Mọi tham chiếu bảng hoặc cột báo lỗi.
    public convenience init() {
        let schema = ModelSchema(culture: "en-US", tables: [], relationships: [])
        let store = ColumnStore(source: InMemoryColumnSource(schema: schema, rowCounts: [:], columns: [:]))
        self.init(store: store, catalog: Catalog(schema: schema))
    }

    // MARK: - Evaluating

    public func scalar(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> Value {
        switch expr {
        case .literal(let value):
            return value
        case .column(let id):
            return try columnValue(id, ctx)
        case .virtualColumn(let name):
            return try virtualColumnValue(name, ctx)
        case .table:
            throw DAXError(.typeMismatch, "biểu thức bảng không dùng được như giá trị")
        case .measure(let id):
            return try measureValue(id, ctx)
        case .variable(let slot):
            guard case .scalar(let value) = try lookupVariable(slot) else {
                throw DAXError(.typeMismatch, "biến bảng không dùng được như giá trị")
            }
            return value
        case .call(let fid, let args):
            let spec = try specification(fid)
            switch spec.impl {
            case .scalar(let body):
                return try body(CallFrame(args: args, ctx: ctx, eval: self))
            case .table:
                throw DAXError(.typeMismatch, "\(spec.name) trả về bảng, không dùng như giá trị")
            case .modifier:
                throw DAXError(.typeMismatch, "\(spec.name) chỉ dùng làm bộ sửa đổi trong CALCULATE")
            }
        case .unary(let op, let operand):
            return try Value.unary(op, try scalar(operand, in: ctx))
        case .binary(let op, let left, let right):
            return try binaryValue(op, left, right, ctx)
        case .varBlock(let slots, let values, let body):
            return try withBlock(slots, values, ctx) { () throws(DAXError) -> Value in
                try scalar(body, in: ctx)
            }
        case .tableConstructor:
            throw DAXError(.typeMismatch, "{…} không dùng được như giá trị")
        case .keyword(let word):
            throw DAXError(.typeMismatch, "từ khoá \(word) không phải giá trị")
        case .tuple:
            throw DAXError(.typeMismatch, "bộ giá trị (tuple) không dùng được như giá trị")
        case .summarize:
            throw DAXError(.typeMismatch, "biểu thức bảng SUMMARIZECOLUMNS không dùng được như giá trị")
        }
    }

    public func table(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> TableValue {
        switch expr {
        case .table(let id):
            return try materialize(id, try visibleRows(of: id, in: ctx))
        case .summarize(let plan):
            return try SummarizeColumns.evaluateTable(plan, in: ctx, evaluator: self, store: store)
        case .variable(let slot):
            switch try lookupVariable(slot) {
            case .table(let value): return value
            case .rows(let id, let rows): return try materialize(id, rows)
            case .scalar: throw DAXError(.typeMismatch, "biến vô hướng không dùng được như bảng")
            }
        case .varBlock(let slots, let values, let body):
            return try withBlock(slots, values, ctx) { () throws(DAXError) -> TableValue in
                try table(body, in: ctx)
            }
        case .call(let fid, let args):
            let spec = try specification(fid)
            if spec.name == "KEEPFILTERS", let inner = args.first ?? nil {
                return try table(inner, in: ctx)
            }
            guard case .table(let body) = spec.impl else {
                throw DAXError(.typeMismatch, "\(spec.name) không trả về bảng")
            }
            return try body(CallFrame(args: args, ctx: ctx, eval: self))
        case .tableConstructor(let columns, let rows):
            var out: [[Value]] = []
            out.reserveCapacity(rows.count)
            for row in rows {
                var values: [Value] = []
                for item in row {
                    values.append(try scalar(item, in: ctx))
                }
                out.append(values)
            }
            let names = columns == 1 ? ["[Value]"] : (1...max(columns, 1)).map { "[Value\($0)]" }
            return TableValue(columns: names, rows: out)
        default:
            throw DAXError(.typeMismatch, "biểu thức không phải biểu thức bảng")
        }
    }

    public func column(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> ColumnID {
        guard case .column(let id) = expr else {
            throw DAXError(.expectedColumnRef, "cần một tham chiếu cột")
        }
        return id
    }

    public func iterate(_ table: TableValue, in ctx: EvalContext,
                        _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError) {
        let shadowed = ctx.filter.pushingShadow()
        for i in 0..<table.rows.count {
            try checkCancelled()
            rowStack.append(.virtual(table, i))
            defer { rowStack.removeLast() }
            try body(EvalContext(filter: shadowed, row: RowContext(table: Evaluator.virtualTable, row: i)))
        }
    }

    // MARK: - API cho hàm và cho engine

    /// Lặp trên biểu thức bảng `expr`. Bảng vật lý (`T` hoặc biến giữ RowSet) lặp trên tập dòng, không materialize.
    public func iterateExpr(_ expr: BoundExpr, in ctx: EvalContext,
                            _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError) {
        switch expr {
        case .table(let id):
            try iteratePhysical(id, try visibleRows(of: id, in: ctx), ctx, body)
        case .variable(let slot):
            switch try lookupVariable(slot) {
            case .rows(let id, let rows): try iteratePhysical(id, rows, ctx, body)
            case .table(let value): try iterate(value, in: ctx, body)
            case .scalar: throw DAXError(.typeMismatch, "biến vô hướng không lặp được")
            }
        case .varBlock(let slots, let values, let inner):
            try withBlock(slots, values, ctx) { () throws(DAXError) in
                try iterateExpr(inner, in: ctx, body)
            }
        case .call(let fid, let args):
            let spec = try specification(fid)
            if spec.name == "KEEPFILTERS", let inner = args.first ?? nil {
                try iterateExpr(inner, in: ctx, body)
                return
            }
            // ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT trên bảng vật lý: lặp trên RowSet, không materialize.
            if let physical = try physicalCall(fid, args, ctx) {
                try iteratePhysical(physical.table, physical.rows, ctx, body)
            } else {
                try iterate(try table(expr, in: ctx), in: ctx, body)
            }
        default:
            try iterate(try table(expr, in: ctx), in: ctx, body)
        }
    }

    /// Lời gọi hàm bảng của F-FILTER dạng bảng vật lý (ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT): tên bảng và RowSet.
    /// Nil nếu lời gọi không thuộc dạng này; khi đó đường `table(_:in:)` xử lý.
    private func physicalCall(_ fid: FunctionID, _ args: [BoundExpr?],
                              _ ctx: EvalContext) throws(DAXError) -> (table: TableID, rows: RowSet)? {
        let spec = try specification(fid)
        return try FilterFunctions.physicalRows(spec.name, args: args, ctx: ctx, evaluator: self)
    }

    /// R(T): dòng của T còn thấy được trong ngữ cảnh (có cache theo vân tay).
    public func visibleRows(of table: TableID, in ctx: EvalContext) throws(DAXError) -> RowSet {
        let key = RowSetCacheKey.visible(table, fingerprint: ctx.filter.fingerprint)
        if let hit = cache.rowSets.rows(for: key) { return hit }
        let rows = try ctx.filter.visibleRows(in: store, table: table, overrides: [])
        cache.rowSets.store(rows, for: key)
        return rows
    }

    /// Chạy một lời gọi tới ColumnStore và đổi lỗi thành DAXError.
    func runtimeCall<T>(_ body: () throws -> T) throws(DAXError) -> T {
        do {
            return try body()
        } catch let error as DAXError {
            throw error
        } catch {
            throw DAXError(.runtime, "lỗi kho cột: \(error)")
        }
    }

    /// Kiểm huỷ hợp tác: ném `.cancelled` khi Task hiện tại bị huỷ (giới hạn thời gian của measures-run, hoặc người gọi huỷ).
    /// Gọi trong mọi vòng lặp dài của đường nóng. Khi không có Task huỷ thì chỉ là một lần đọc cờ.
    @inline(__always)
    func checkCancelled() throws(DAXError) {
        if Task.isCancelled { throw DAXError(.cancelled, "đã huỷ") }
    }

    func specification(_ fid: FunctionID) throws(DAXError) -> FunctionSpec {
        let index = Int(fid.raw)
        guard index >= 0, index < functions.count else {
            throw DAXError(.unknownName, "hàm #\(fid.raw) không có trong bảng hàm")
        }
        return functions[index]
    }

    /// Dữ liệu cột (cache trong phiên).
    func columnData(_ id: ColumnID) throws(DAXError) -> ColumnData {
        if let cached = columnCache[id] { return cached }
        let data = try runtimeCall { try store.column(id) }
        columnCache[id] = data
        return data
    }

    func columnIndex(_ id: ColumnID) throws(DAXError) -> ColumnIndex {
        try runtimeCall { try store.index(id) }
    }

    /// Khối VAR…RETURN: đẩy khung, chạy `body`, bỏ khung.
    func withBlock<T>(_ slots: [Int], _ exprs: [BoundExpr], _ ctx: EvalContext,
                      _ body: () throws(DAXError) -> T) throws(DAXError) -> T {
        let block = VarBlock(slots: slots, exprs: exprs, ctx: ctx, rowsAtEntry: rowStack, varsBelow: varStack)
        varStack.append(block)
        defer { varStack.removeLast() }
        return try body()
    }

    // MARK: - Biến

    func lookupVariable(_ slot: Int) throws(DAXError) -> VarValue {
        guard let block = varStack.last(where: { $0.slots.contains(slot) }),
              let index = block.slots.firstIndex(of: slot) else {
            throw DAXError(.runtime, "biến slot \(slot) không có trong phạm vi hiện tại")
        }
        if let value = block.values[index] { return value }
        let value = try evaluateCell(of: block, index: index)
        block.values[index] = value
        return value
    }

    /// Tính một VAR trong môi trường lúc khai báo: ngăn xếp row, ngăn xếp VAR (gồm khối này), ngữ cảnh khối.
    private func evaluateCell(of block: VarBlock, index: Int) throws(DAXError) -> VarValue {
        let savedRows = rowStack
        let savedVars = varStack
        rowStack = block.rowsAtEntry
        varStack = block.varsBelow + [block]
        defer {
            rowStack = savedRows
            varStack = savedVars
        }
        return try cellValue(block.exprs[index], block.ctx)
    }

    private func cellValue(_ expr: BoundExpr, _ ctx: EvalContext) throws(DAXError) -> VarValue {
        switch expr {
        case .table(let id):
            return .rows(id, try visibleRows(of: id, in: ctx))
        case .summarize(let plan):
            return .table(try SummarizeColumns.evaluateTable(plan, in: ctx, evaluator: self, store: store))
        case .variable(let slot):
            return try lookupVariable(slot)
        case .varBlock(let slots, let values, let body):
            return try withBlock(slots, values, ctx) { () throws(DAXError) -> VarValue in
                try cellValue(body, ctx)
            }
        case .tableConstructor:
            return .table(try table(expr, in: ctx))
        case .call(let fid, _):
            if case .table = try specification(fid).impl {
                return .table(try table(expr, in: ctx))
            }
            return .scalar(try scalar(expr, in: ctx))
        default:
            return .scalar(try scalar(expr, in: ctx))
        }
    }

    // MARK: - Cột

    private func columnValue(_ id: ColumnID, _ ctx: EvalContext) throws(DAXError) -> Value {
        if ctx.row != nil {
            for frame in rowStack.reversed() {
                switch frame {
                case .base(let table, let row) where table == id.table:
                    return Value(stored: try columnData(id).value(at: row))
                case .virtual(let value, let row):
                    if let index = value.lineageIndex(of: id) {
                        return value.rows[row][index]
                    }
                default:
                    continue
                }
            }
        }
        // Không có khung row chứa cột: lấy giá trị đơn của bộ lọc.
        let values = try ctx.filter.visibleValues(of: id, in: store)
        if values.count == 1 { return values[0] }
        if values.isEmpty { return .blank }
        throw DAXError(.multipleValues, "không xác định được một giá trị của cột \(id) (có \(values.count) giá trị)")
    }

    private func virtualColumnValue(_ name: String, _ ctx: EvalContext) throws(DAXError) -> Value {
        // So tên không phân biệt hoa thường và bỏ ngoặc vuông: bảng hằng {…} đặt tên cột là "[Value]".
        func bare(_ s: String) -> String {
            s.hasPrefix("[") && s.hasSuffix("]") && s.count >= 2 ? String(s.dropFirst().dropLast()).lowercased() : s.lowercased()
        }
        let key = bare(name)
        if ctx.row != nil {
            for frame in rowStack.reversed() {
                if case .virtual(let value, let row) = frame,
                   let index = value.columns.firstIndex(where: { bare($0) == key }) {
                    return value.rows[row][index]
                }
            }
        }
        throw DAXError(.unknownName, "không tìm thấy cột ảo [\(name)] trong row context")
    }

    // MARK: - Measure

    private func measureValue(_ id: MeasureID, _ ctx: EvalContext) throws(DAXError) -> Value {
        try checkCancelled()
        let body = try boundBody(id)
        var filter = ctx.filter
        var digest = 0
        if ctx.row != nil {
            filter = try transitioned(ctx.filter)
            digest = virtualRowsDigest()
        }
        let key = MeasureCacheKey(measure: id.raw, filterFingerprint: filter.fingerprint,
                                  virtualRowsDigest: digest)
        if let hit = cache.measures.value(for: key) { return hit }
        guard measuresInProgress.insert(id).inserted else {
            throw DAXError(.circularDependency, "measure \(id.raw) tham chiếu vòng tới chính nó")
        }
        defer { measuresInProgress.remove(id) }
        let value = try scalar(body, in: EvalContext(filter: filter, row: ctx.row))
        cache.measures.store(value, for: key)
        return value
    }

    private func boundBody(_ id: MeasureID) throws(DAXError) -> BoundExpr {
        if let bound = boundMeasures[id] { return bound }
        let bound = try Binder.bindMeasure(id, catalog: catalog)
        boundMeasures[id] = bound
        return bound
    }

    /// Băm các dòng của mọi khung bảng ảo (dòng ảo không có lineage không được transition nên phải vào khoá).
    private func virtualRowsDigest() -> Int {
        var hasher = Hasher()
        var any = false
        for frame in rowStack {
            if case .virtual(let value, let row) = frame {
                hasher.combine(value)
                hasher.combine(row)
                any = true
            }
        }
        return any ? hasher.finalize() : 0
    }

    /// Context transition (§4.3): mỗi khung row, từ ngoài vào trong, thành bộ lọc. Mỗi cột/bảng của dòng
    /// ghi đè bộ lọc cũ trên cùng cột/bảng (như đối số bộ lọc của CALCULATE).
    func transitioned(_ filter: FilterContext) throws(DAXError) -> FilterContext {
        var out = filter
        for frame in rowStack {
            switch frame {
            case .base(let table, let row):
                let rows = try transitionRows(table, row)
                out = out.applying(rows: RowsFilter(table: table, rows: rows), keep: false)
            case .virtual(let value, let row):
                for item in value.rowFilterItems(row: row) {
                    out = out.applying(item, keep: false)
                }
            }
        }
        return out
    }

    /// Các dòng của T có cùng giá trị ở mọi cột với dòng `row`. Dùng posting list của cột mã ít dòng nhất.
    private func transitionRows(_ table: TableID, _ row: Int) throws(DAXError) -> RowSet {
        let key = RowSetCacheKey.transition(table, row: row)
        if let hit = cache.rowSets.rows(for: key) { return hit }
        let rows = try computeTransitionRows(table, row)
        cache.rowSets.store(rows, for: key)
        return rows
    }

    private func computeTransitionRows(_ table: TableID, _ row: Int) throws(DAXError) -> RowSet {
        guard let schemaTable = store.schema.table(table) else {
            throw DAXError(.runtime, "không có bảng \(table) trong model")
        }
        let rowCount = try runtimeCall { try store.rowCount(table) }
        let universe = rowCount + 1
        if row >= rowCount {
            // Dòng BLANK ảo của quan hệ: chính là dòng `rowCount`, để lan truyền tới các dòng fact không khớp khoá.
            return RowSet(universe: universe, sortedRows: [UInt32(rowCount)])
        }
        var encoded: [(data: ColumnData, index: ColumnIndex)] = []
        var dense: [ColumnData] = []
        for column in schemaTable.columns {
            let data = try columnData(column.id)
            if data.isEncoded {
                encoded.append((data, try columnIndex(column.id)))
            } else {
                dense.append(data)
            }
        }
        if encoded.isEmpty && dense.isEmpty {
            return RowSet(universe: universe, sortedRows: [UInt32(row)])
        }
        var candidates: ArraySlice<UInt32>
        if encoded.isEmpty {
            // Bảng chỉ có cột dense: quét mọi dòng (chậm, hiếm gặp).
            candidates = ArraySlice((0..<rowCount).map { UInt32($0) })
        } else {
            var best: ArraySlice<UInt32> = []
            var bestCount = Int.max
            for entry in encoded {
                let code = entry.data.code(atRow: row) ?? 0
                let slice = entry.index.postings(forCode: code) ?? []
                if slice.count < bestCount {
                    best = slice
                    bestCount = slice.count
                }
            }
            candidates = best
        }
        let baseCodes = encoded.map { $0.data.code(atRow: row) ?? 0 }
        let baseDense = dense.map { $0.value(at: row) }
        var matches: [UInt32] = []
        var scanned = 0
        for candidate in candidates {
            scanned &+= 1
            if scanned & 0xFFF == 0 { try checkCancelled() }
            let r = Int(candidate)
            var same = true
            for (k, entry) in encoded.enumerated() where same {
                if (entry.data.code(atRow: r) ?? 0) != baseCodes[k] { same = false }
            }
            for (k, data) in dense.enumerated() where same {
                if data.value(at: r) != baseDense[k] { same = false }
            }
            if same { matches.append(candidate) }
        }
        return RowSet(universe: universe, sortedRows: matches)
    }

    // MARK: - Vật chất hoá và lặp

    /// Đọc các dòng của T thành bảng ảo (chỉ cho bảng nhỏ hoặc khi bắt buộc).
    func materialize(_ table: TableID, _ rows: RowSet) throws(DAXError) -> TableValue {
        guard let schemaTable = store.schema.table(table) else {
            throw DAXError(.runtime, "không có bảng \(table) trong model")
        }
        var datas: [ColumnData] = []
        for column in schemaTable.columns {
            datas.append(try columnData(column.id))
        }
        var out: [[Value]] = []
        out.reserveCapacity(rows.count)
        var cancelled = false
        rows.forEach { r in
            if cancelled { return }
            if out.count & 0xFFF == 0 && Task.isCancelled {
                cancelled = true
                return
            }
            out.append(datas.map { Value(stored: $0.value(at: r)) })
        }
        if cancelled { throw DAXError(.cancelled, "đã huỷ") }
        materializedRowCount += out.count
        return TableValue(columns: schemaTable.columns.map(\.name), rows: out,
                          lineage: schemaTable.columns.map { $0.id })
    }

    /// Lặp trên tập dòng của bảng vật lý. Shadow được đẩy một lần lúc bắt đầu, mỗi dòng có khung row riêng.
    func iteratePhysical(_ table: TableID, _ rows: RowSet, _ ctx: EvalContext,
                         _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError) {
        let shadowed = ctx.filter.pushingShadow()
        var failure: DAXError?
        rows.forEach { r in
            guard failure == nil else { return }
            if Task.isCancelled {
                failure = DAXError(.cancelled, "đã huỷ")
                return
            }
            rowStack.append(.base(table, r))
            defer { rowStack.removeLast() }
            do throws(DAXError) {
                try body(EvalContext(filter: shadowed, row: RowContext(table: table, row: r)))
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
    }

    // MARK: - Toán tử

    private func binaryValue(_ op: BinaryOp, _ left: BoundExpr, _ right: BoundExpr,
                             _ ctx: EvalContext) throws(DAXError) -> Value {
        switch op {
        case .inSet:
            if case .tableConstructor(_, let rows) = left, rows.count == 1 {
                var lhsTuple: [Value] = []
                for item in rows[0] {
                    lhsTuple.append(try scalar(item, in: ctx))
                }
                for candidate in try setTuples(right, ctx) {
                    if try tupleEqual(lhsTuple, candidate) {
                        return .boolean(true)
                    }
                }
                return .boolean(false)
            }
            if case .tuple(let items) = left {
                var lhsTuple: [Value] = []
                for item in items {
                    lhsTuple.append(try scalar(item, in: ctx))
                }
                for candidate in try setTuples(right, ctx) {
                    if try tupleEqual(lhsTuple, candidate) {
                        return .boolean(true)
                    }
                }
                return .boolean(false)
            }
            let lhs = try scalar(left, in: ctx)
            for candidate in try setValues(right, ctx) {
                if case .boolean(true) = try Value.compare(.equal, lhs, candidate) {
                    return .boolean(true)
                }
            }
            return .boolean(false)
        case .concat:
            return Value.concatenate(try scalar(left, in: ctx), try scalar(right, in: ctx))
        case .and, .or:
            return try Value.logical(op, try scalar(left, in: ctx), try scalar(right, in: ctx))
        case .equal, .strictEqual, .notEqual, .less, .greater, .lessEqual, .greaterEqual:
            return try Value.compare(op, try scalar(left, in: ctx), try scalar(right, in: ctx))
        case .add, .subtract, .multiply, .divide, .power:
            return try Value.arithmetic(op, try scalar(left, in: ctx), try scalar(right, in: ctx))
        }
    }

    /// Vế phải của IN: danh sách {…} (cột đầu) hoặc bảng khác (cột đầu).
    private func setValues(_ expr: BoundExpr, _ ctx: EvalContext) throws(DAXError) -> [Value] {
        var out: [Value] = []
        if case .tableConstructor(_, let rows) = expr {
            for row in rows {
                if let first = row.first {
                    out.append(try scalar(first, in: ctx))
                }
            }
            return out
        }
        for row in try table(expr, in: ctx).rows {
            if let first = row.first { out.append(first) }
        }
        return out
    }

    private func setTuples(_ expr: BoundExpr, _ ctx: EvalContext) throws(DAXError) -> [[Value]] {
        var out: [[Value]] = []
        if case .tableConstructor(_, let rows) = expr {
            for row in rows {
                var r: [Value] = []
                for item in row {
                    r.append(try scalar(item, in: ctx))
                }
                out.append(r)
            }
            return out
        }
        return try table(expr, in: ctx).rows
    }

    private func tupleEqual(_ a: [Value], _ b: [Value]) throws(DAXError) -> Bool {
        guard a.count == b.count else { return false }
        for (v1, v2) in zip(a, b) {
            if case .boolean(true) = try Value.compare(.equal, v1, v2) {
                continue
            }
            return false
        }
        return true
    }
}

// MARK: - Tiện ích cho hàm

public extension CallFrame {
    /// ColumnStore của phiên đánh giá (nil nếu `eval` không phải Evaluator).
    var store: ColumnStore? { (eval as? Evaluator)?.store }

    /// Lặp trên đối số bảng thứ `i` mà không materialize bảng vật lý. Bảng ảo lặp như `iterate`.
    func iterateArgument(_ i: Int, _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError) {
        guard i >= 0, i < args.count, let expr = args[i] else {
            throw DAXError(.arity, "đối số \(i + 1) bị bỏ trống")
        }
        guard let evaluator = eval as? Evaluator else {
            throw DAXError(.runtime, "evaluator không phải Evaluator của CORE")
        }
        try evaluator.iterateExpr(expr, in: ctx, body)
    }
}
