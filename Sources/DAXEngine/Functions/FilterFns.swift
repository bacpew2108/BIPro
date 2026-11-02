// Hàm bộ lọc (F-KIT đợt 2, F-FILTER đợt 3). Đợt 2 cài: REMOVEFILTERS và KEEPFILTERS. Đợt 3 cài: ALL, ALLSELECTED,
// ALLNOBLANKROW, ALLEXCEPT, TREATAS, USERELATIONSHIP, CROSSFILTER. Chữ ký do lead khai báo ở đợt 0.
// ALLSELECTED và TREATAS là hai hàm khó nhất (architecture.md §4.5, §4.1).
//
// CALCULATE của CORE xử lý REMOVEFILTERS, ALL, ALLEXCEPT, ALLSELECTED và KEEPFILTERS theo tên trước khi gọi thân
// `.modifier` (xem Functions/Calculate.swift). Thân ở đây là bản cài đầy đủ cho đường gọi trực tiếp (CallFrame) và
// cho bộ hàm thay thế trong test; kết quả khớp với đường của CORE. USERELATIONSHIP và CROSSFILTER là `.modifier`,
// CALCULATE gọi thân của chúng.
//
// [SUY ĐOÁN] KEEPFILTERS ngoài CALCULATE trên vị ngữ nhiều cột, hoặc trên đối số bảng, báo .runtime: ContextModifier
//   chưa có dạng bộ lọc theo bảng và dạng tuple. Trong CALCULATE, CORE xử lý các dạng này.
// [SUY ĐOÁN] ALL(T) và ALL(T[c]) lấy R(T) và VALUES(T[c]) khi không có bộ lọc nào. Dòng BLANK ảo của T có mặt khi có
//   dòng fact không khớp (đồng bộ với VALUES), nên ALL(T) có thể nhiều hơn số dòng thật đúng 1.
// [SUY ĐOÁN] ALLSELECTED(T) và ALLSELECTED(T[c]) ở dạng bảng chỉ thay bộ lọc của chính các cột đó bằng shadow gần nhất;
//   bộ lọc từ bảng trên shadow được ghép thêm. Dạng sửa đổi trong CALCULATE (FC) chưa đọc bộ lọc bảng của shadow.
// [SUY ĐOÁN] ALLEXCEPT(T, c…) dạng bảng: R(T) khi bỏ mọi bộ lọc trên cột của T trừ các cột giữ lại.
// [SUY ĐOÁN] TREATAS nhiều cột áp lên bộ lọc: CALCULATE (CORE) chưa nhận bảng nhiều cột, nên phần tuple → dòng nằm ở
//   `treatasRowFilter`, và ghép vào ngữ cảnh bằng `applying(rows:keep:)`. Cần CORE gọi hàm này trong addTable (xem báo cáo).
// [SUY ĐOÁN] USERELATIONSHIP và CROSSFILTER tra quan hệ theo cặp cột trong `FilterContext.relationships` (cần `bound(to:)`).
import ColumnStore

/// Các cột được tham chiếu trực tiếp trong biểu thức (không đi vào thân measure). Mirror của CORE.
fileprivate func fkReferencedColumns(_ expr: BoundExpr) -> Set<ColumnID> {
    var out = Set<ColumnID>()
    func walk(_ e: BoundExpr) {
        switch e {
        case .column(let column):
            out.insert(column)
        case .unary(_, let operand):
            walk(operand)
        case .binary(_, let left, let right):
            walk(left)
            walk(right)
        case .call(_, let args):
            for arg in args {
                if let arg { walk(arg) }
            }
        case .varBlock(_, let values, let body):
            for value in values { walk(value) }
            walk(body)
        case .tableConstructor(_, let rows):
            for row in rows {
                for item in row { walk(item) }
            }
        default:
            break
        }
    }
    walk(expr)
    return out
}

/// Biểu thức là bảng (tham chiếu bảng, biến bảng, hoặc hàm trả bảng). Dùng để loại trước khi đọc cột.
fileprivate func fkIsTableExpression(_ expr: BoundExpr, _ evaluator: Evaluator) throws(DAXError) -> Bool {
    switch expr {
    case .table:
        return true
    case .variable(let slot):
        if case .scalar = try evaluator.lookupVariable(slot) { return false }
        return true
    case .call(let fid, _):
        if case .table = try evaluator.specification(fid).impl { return true }
        return false
    default:
        return false
    }
}

// MARK: - Tiện ích dùng chung cho các hàm F-FILTER (cùng module; Information.swift cũng dùng)

/// Đối số bảng hoặc cột đã phân giải.
enum FFTarget: Sendable {
    case column(ColumnID)
    case table(TableID)
}

/// Phân giải đối số bảng hoặc cột: tham chiếu cột, tên bảng, hoặc biến giữ RowSet. Lỗi với các dạng khác.
func ffTarget(_ expr: BoundExpr?, _ evaluator: Evaluator) throws(DAXError) -> FFTarget {
    guard let expr else { throw DAXError(.arity, "đối số bị bỏ trống") }
    switch expr {
    case .column(let column):
        return .column(column)
    case .table(let table):
        return .table(table)
    case .variable(let slot):
        if case .rows(let table, _) = try evaluator.lookupVariable(slot) { return .table(table) }
        throw DAXError(.typeMismatch, "cần một bảng hoặc một cột")
    default:
        throw DAXError(.typeMismatch, "cần một bảng hoặc một cột")
    }
}

/// Bảng vật lý của đối số (tên bảng hoặc biến giữ RowSet). nil nếu là dạng khác (cột, bảng ảo, biểu thức).
func ffPhysicalTable(_ expr: BoundExpr, _ evaluator: Evaluator) throws(DAXError) -> TableID? {
    switch expr {
    case .table(let table):
        return table
    case .variable(let slot):
        if case .rows(let table, _) = try evaluator.lookupVariable(slot) { return table }
        return nil
    default:
        return nil
    }
}

/// Đối số phải là một tham chiếu cột.
func ffColumnArgument(_ expr: BoundExpr?) throws(DAXError) -> ColumnID {
    guard let expr else { throw DAXError(.arity, "đối số bị bỏ trống") }
    guard case .column(let column) = expr else { throw DAXError(.expectedColumnRef, "cần một tham chiếu cột") }
    return column
}

/// Mọi đối số phải là cột (theo thứ tự).
func ffColumnArguments(_ exprs: [BoundExpr]) throws(DAXError) -> [ColumnID] {
    var out: [ColumnID] = []
    for expr in exprs {
        out.append(try ffColumnArgument(expr))
    }
    return out
}

/// Các cột của một bảng trong model. Lỗi nếu bảng không có trong model.
func ffSchemaColumns(_ table: TableID, _ store: ColumnStore) throws(DAXError) -> [ColumnID] {
    guard let meta = store.schema.table(table) else {
        throw DAXError(.runtime, "không có bảng \(table) trong model")
    }
    return meta.columns.map(\.id)
}

/// Bảng vật lý của một tập cột (theo thứ tự xuất hiện), không trùng.
func ffDistinctTables(_ columns: [ColumnID]) -> [TableID] {
    var out: [TableID] = []
    for column in columns where !out.contains(column.table) {
        out.append(column.table)
    }
    return out
}

/// Đổi lỗi của ColumnStore sang DAXError (giống `Evaluator.runtimeCall`, dùng khi không có evaluator).
func ffCall<T>(_ body: () throws -> T) throws(DAXError) -> T {
    do {
        return try body()
    } catch let error as DAXError {
        throw error
    } catch {
        throw DAXError(.runtime, "lỗi kho cột: \(error)")
    }
}

/// Bộ lọc theo cột đã resolve ALLSELECTED: thay bộ lọc của các cột bằng shadow gần nhất, và ghép bộ lọc bảng của shadow
/// trên các bảng liên quan. Không đụng bộ lọc của cột/bảng khác.
func ffResolveAllSelected(_ filter: FilterContext, columns: [ColumnID], tables: [TableID]) -> FilterContext {
    var out = filter.applying([.allSelected(columns: columns)])
    for table in tables {
        if let shadow = filter.shadows.nearestRowFilter(on: table) {
            out = out.applying(rows: RowsFilter(table: table, rows: shadow.rows, removedColumns: shadow.removedColumns),
                               keep: true)
        }
    }
    return out
}

/// Tập giá trị hoặc tuple của một tập cột, theo từng bảng rồi crossjoin giữa các bảng. Dùng cho ALL(cột…) và
/// ALLSELECTED(cột…). Một cột của một bảng dùng `visibleValues` (có thứ tự sắp của cột); nhiều cột thì quét dòng thấy được.
func ffColumnsTable(_ columns: [ColumnID], filter: FilterContext, store: ColumnStore) throws(DAXError) -> TableValue {
    var out = TableValue(columns: [], rows: [[]], lineage: [])
    for table in ffDistinctTables(columns) {
        let group = columns.filter { $0.table == table }
        let names = group.map { store.schema.column($0)?.name ?? "\($0)" }
        let part: TableValue
        if group.count == 1, let column = group.first {
            let values = try filter.visibleValues(of: column, in: store)
            part = TableValue(columns: names, rows: values.map { [$0] }, lineage: [column])
        } else {
            let rows = try filter.visibleRows(in: store, table: table, overrides: [])
            let datas = try ffCall { () throws -> [ColumnData] in try group.map { try store.column($0) } }
            var tuples: [[Value]] = []
            tuples.reserveCapacity(rows.count)
            rows.forEach { r in
                tuples.append(datas.map { Value(stored: $0.value(at: r)) })
            }
            part = TableValue(columns: names, rows: tuples, lineage: group).distinct()
        }
        out = out.crossJoined(with: part)
    }
    return out
}

/// Chuyển `Value` sang kiểu lưu của cột đích (sao chép từ `FilterContext.storedValue`, vì hàm đó là fileprivate).
func ffStoredValue(_ value: Value, as type: DAXType) -> StoredValue {
    switch (value, type) {
    case (.blank, _):
        return .blank
    case (.integer(let i), .double):
        return .double(Double(i))
    case (.integer(let i), .currency):
        return .currency(i &* 10_000)
    case (.integer(let i), .dateTime):
        return .dateTime(Double(i))
    case (.integer(let i), _):
        return .integer(i)
    case (.double(let d), .integer):
        if d == d.rounded(), abs(d) < 9.0e18 { return .integer(Int64(d)) }
        return .double(d)
    case (.double(let d), .currency):
        return .currency(Int64((d * 10_000).rounded()))
    case (.double(let d), .dateTime):
        return .dateTime(d)
    case (.double(let d), _):
        return .double(d)
    case (.currency(let c), .double):
        return .double(Double(c) / 10_000)
    case (.currency(let c), .integer):
        return c % 10_000 == 0 ? .integer(c / 10_000) : .currency(c)
    case (.currency(let c), _):
        return .currency(c)
    case (.string(let s), _):
        return .string(s)
    case (.boolean(let b), _):
        return .boolean(b)
    case (.dateTime(let d), _):
        return .dateTime(d)
    }
}

/// Mã của một giá trị trên cột mã hoá. Chuỗi khớp không phân biệt hoa thường khi khớp đúng thất bại.
private func ffCodeOf(_ value: Value, index: ColumnIndex, type: DAXType, lowered: [String: Int]) -> Int? {
    let stored = ffStoredValue(value, as: type)
    if let code = index.code(of: stored) { return code }
    if case .string(let s) = stored { return lowered[s.lowercased()] }
    return nil
}

// MARK: - Họ hàm

public enum FilterFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "ALL", params: [.tableOrColumn("tableOrColumnName", repeats: true)], impl: .table(allBody)),
        FunctionSpec(name: "ALLSELECTED", params: [.tableOrColumn("tableOrColumnName", optional: true, repeats: true)],
                     impl: .table(allSelectedBody)),
        FunctionSpec(name: "ALLNOBLANKROW", params: [.table("tableName")], impl: .table(allNoBlankRowBody)),
        FunctionSpec(name: "ALLEXCEPT", params: [.table("tableName"), .column("columnName", repeats: true)],
                     impl: .table(allExceptBody)),
        FunctionSpec(name: "REMOVEFILTERS", params: [.tableOrColumn("tableOrColumnName", optional: true, repeats: true)],
                     impl: .modifier(removeFiltersBody)),
        FunctionSpec(name: "KEEPFILTERS", params: [.filter("filter")], impl: .modifier(keepFiltersBody)),
        FunctionSpec(name: "TREATAS", params: [.table("expression"), .column("column", repeats: true)],
                     impl: .table(treatasBody)),
        FunctionSpec(name: "USERELATIONSHIP", params: [.column("columnName1"), .column("columnName2")],
                     impl: .modifier(useRelationshipBody)),
        FunctionSpec(name: "CROSSFILTER", params: [.column("columnName1"), .column("columnName2"),
                                                   .keyword("crossFilterType", ["ONEWAY", "BOTH", "NONE"])],
                     impl: .modifier(crossFilterBody)),
    ]

    // MARK: Bảng vật lý dưới dạng RowSet (không materialize)

    /// Các hàm bảng trên một bảng vật lý dưới dạng RowSet: ALL(T), ALLSELECTED(T), ALLNOBLANKROW(T), ALLEXCEPT(T, c…).
    /// Trả nil nếu lời gọi không thuộc dạng này (ví dụ ALL(cột…), biểu thức bảng, bảng ảo); khi đó dùng đường `table`.
    /// CORE nên gọi hàm này trong `iterateExpr` cho lời gọi `.call` để lặp không vật chất hoá (architecture.md §7.1).
    public static func physicalRows(_ name: String, args: [BoundExpr?], ctx: EvalContext,
                                    evaluator: Evaluator) throws(DAXError) -> (table: TableID, rows: RowSet)? {
        let present = args.compactMap { $0 }
        let store = evaluator.store
        switch name {
        case "ALL":
            guard present.count == 1, let table = try ffPhysicalTable(present[0], evaluator) else { return nil }
            return (table, try FilterContext.empty.visibleRows(in: store, table: table, overrides: []))
        case "ALLSELECTED":
            guard present.count == 1, let table = try ffPhysicalTable(present[0], evaluator) else { return nil }
            let columns = try ffSchemaColumns(table, store)
            let filter = ffResolveAllSelected(ctx.filter, columns: columns, tables: [table])
            return (table, try filter.visibleRows(in: store, table: table, overrides: []))
        case "ALLNOBLANKROW":
            guard present.count == 1, let table = try ffPhysicalTable(present[0], evaluator) else { return nil }
            let rowCount = try ffCall { try store.rowCount(table) }
            let all = try FilterContext.empty.visibleRows(in: store, table: table, overrides: [])
            return (table, all.intersection(RowSet.all(rowCount: rowCount)))
        case "ALLEXCEPT":
            guard let first = present.first, let table = try ffPhysicalTable(first, evaluator) else { return nil }
            let kept = try ffColumnArguments(Array(present.dropFirst()))
            if let stray = kept.first(where: { $0.table != table }) {
                throw DAXError(.typeMismatch, "ALLEXCEPT chỉ nhận cột của bảng đầu, không phải \(stray)")
            }
            let keptSet = Set(kept)
            let removed = try ffSchemaColumns(table, store).filter { !keptSet.contains($0) }
            return (table, try ctx.filter.removingColumns(removed).visibleRows(in: store, table: table, overrides: []))
        default:
            return nil
        }
    }

    // MARK: ALL

    /// ALL(T): mọi dòng thấy được khi bỏ mọi bộ lọc. ALL(cột…): mọi tổ hợp giá trị khi bỏ mọi bộ lọc (kể cả BLANK
    /// khi có dòng BLANK thật hoặc dòng BLANK ảo).
    private static let allBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let evaluator = try fkEvaluator(frame)
        if let physical = try physicalRows("ALL", args: frame.args, ctx: frame.ctx, evaluator: evaluator) {
            return try evaluator.materialize(physical.table, physical.rows)
        }
        let present = frame.args.compactMap { $0 }
        guard !present.isEmpty else {
            throw DAXError(.arity, "ALL cần ít nhất một bảng hoặc một cột")
        }
        let columns = try ffColumnArguments(present)
        return try ffColumnsTable(columns, filter: .empty, store: evaluator.store)
    }

    // MARK: ALLSELECTED

    /// ALLSELECTED(T): các dòng của T theo shadow gần nhất. ALLSELECTED(cột…): các tổ hợp giá trị theo shadow gần nhất.
    /// Không đối số là trạng thái, không phải bảng: chỉ dùng trong CALCULATE (CORE xử lý theo tên).
    private static let allSelectedBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let present = frame.args.compactMap { $0 }
        guard !present.isEmpty else {
            throw DAXError(.typeMismatch, "ALLSELECTED() không dùng được như bảng; chỉ dùng làm bộ sửa đổi trong CALCULATE")
        }
        let evaluator = try fkEvaluator(frame)
        if let physical = try physicalRows("ALLSELECTED", args: frame.args, ctx: frame.ctx, evaluator: evaluator) {
            return try evaluator.materialize(physical.table, physical.rows)
        }
        let columns = try ffColumnArguments(present)
        let filter = ffResolveAllSelected(frame.ctx.filter, columns: columns, tables: ffDistinctTables(columns))
        return try ffColumnsTable(columns, filter: filter, store: evaluator.store)
    }

    // MARK: ALLNOBLANKROW

    /// ALLNOBLANKROW(T): mọi dòng thật của T (bỏ dòng BLANK ảo), bỏ qua bộ lọc.
    private static let allNoBlankRowBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let evaluator = try fkEvaluator(frame)
        if let physical = try physicalRows("ALLNOBLANKROW", args: frame.args, ctx: frame.ctx, evaluator: evaluator) {
            return try evaluator.materialize(physical.table, physical.rows)
        }
        throw DAXError(.typeMismatch, "ALLNOBLANKROW cần một bảng")
    }

    // MARK: ALLEXCEPT

    /// ALLEXCEPT(T, c…) dạng bảng: dòng của T khi bỏ bộ lọc trên mọi cột của T trừ các cột giữ lại.
    private static let allExceptBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let present = frame.args.compactMap { $0 }
        guard !present.isEmpty else {
            throw DAXError(.arity, "ALLEXCEPT cần ít nhất một bảng")
        }
        let evaluator = try fkEvaluator(frame)
        guard let physical = try physicalRows("ALLEXCEPT", args: frame.args, ctx: frame.ctx, evaluator: evaluator) else {
            throw DAXError(.typeMismatch, "đối số đầu của ALLEXCEPT phải là bảng")
        }
        return try evaluator.materialize(physical.table, physical.rows)
    }

    // MARK: REMOVEFILTERS

    /// Không đối số: xoá mọi bộ lọc. Cột: xoá bộ lọc trên cột (chiếu bộ lọc bảng). Bảng: xoá expanded table.
    private static let removeFiltersBody: FunctionSpec.ModifierBody = { (frame: CallFrame) throws(DAXError) -> [ContextModifier] in
        let present = frame.args.compactMap { $0 }
        if present.isEmpty { return [.removeAll] }
        let evaluator = try fkEvaluator(frame)
        var out: [ContextModifier] = []
        for arg in present {
            switch arg {
            case .column(let column):
                out.append(.removeColumns([column]))
            case .table(let table):
                out.append(.removeExpandedTable(table))
            case .variable(let slot):
                switch try evaluator.lookupVariable(slot) {
                case .rows(let table, _):
                    out.append(.removeExpandedTable(table))
                case .table(let value):
                    out.append(.removeColumns(value.lineage.compactMap { $0 }))
                case .scalar:
                    throw DAXError(.expectedColumnRef, "REMOVEFILTERS cần một cột hoặc một bảng")
                }
            default:
                throw DAXError(.expectedColumnRef, "REMOVEFILTERS cần một cột hoặc một bảng")
            }
        }
        return out
    }

    // MARK: KEEPFILTERS

    /// Vị ngữ trên đúng một cột: giữ các giá trị thấy được (trong ngữ cảnh gọi) mà vị ngữ đúng, rồi giao với bộ lọc
    /// hiện có (`keep: true`). Không ghi đè bộ lọc cũ.
    private static let keepFiltersBody: FunctionSpec.ModifierBody = { (frame: CallFrame) throws(DAXError) -> [ContextModifier] in
        guard let predicate = fkArg(frame, 0) else {
            throw DAXError(.arity, "KEEPFILTERS cần đúng một đối số bộ lọc")
        }
        let evaluator = try fkEvaluator(frame)
        let store = evaluator.store
        if try fkIsTableExpression(predicate, evaluator) {
            throw DAXError(.runtime, "KEEPFILTERS ngoài CALCULATE chưa hỗ trợ bộ lọc theo bảng")
        }
        let columns = fkReferencedColumns(predicate)
        guard columns.count == 1, let column = columns.first else {
            throw DAXError(.runtime, "KEEPFILTERS ngoài CALCULATE chỉ nhận vị ngữ trên đúng một cột")
        }
        let name = store.schema.column(column)?.name ?? ""
        let candidates = try frame.ctx.filter.visibleValues(of: column, in: store)
        var kept: [Value] = []
        for value in candidates {
            let single = TableValue(columns: [name], rows: [[value]], lineage: [column])
            var holds = false
            try evaluator.iterate(single, in: frame.ctx) { (inner: EvalContext) throws(DAXError) in
                holds = try evaluator.scalar(predicate, in: inner).asLogical()
            }
            if holds { kept.append(value) }
        }
        return [.filter(FilterItem(column: column, values: kept), keep: true)]
    }

    // MARK: TREATAS

    /// TREATAS(bảng, c1…cN): bảng nguồn có N cột, lấy tuple theo vị trí và gán lineage cho các cột đích. Bảng kết quả
    /// là tập tuple khác nhau (không kiểm tra cột đích có giá trị đó hay không; kiểm khi áp làm bộ lọc).
    private static let treatasBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard fkArg(frame, 0) != nil else {
            throw DAXError(.arity, "TREATAS cần bảng nguồn và ít nhất một cột đích")
        }
        let evaluator = try fkEvaluator(frame)
        let store = evaluator.store
        let source = try frame.table(0)
        let targets = try ffColumnArguments(frame.args.dropFirst().compactMap { $0 })
        guard !targets.isEmpty else {
            throw DAXError(.arity, "TREATAS cần ít nhất một cột đích")
        }
        guard targets.count == source.columns.count else {
            throw DAXError(.arity, "TREATAS: bảng nguồn có \(source.columns.count) cột, còn \(targets.count) cột đích")
        }
        let names = targets.map { store.schema.column($0)?.name ?? "\($0)" }
        if targets.count == 1 {
            return TableValue(columns: names, rows: source.rows.map { [$0[0]] }, lineage: targets).distinct()
        }
        return TableValue(columns: names, rows: source.rows, lineage: targets).distinct()
    }

    /// TREATAS nhiều cột thành bộ lọc theo bảng: tuple (cột theo thứ tự `targets`) → tập dòng của bảng đích khớp
    /// đúng tuple đó. Dòng BLANK thật (mã 0) khớp giá trị BLANK; dòng BLANK ảo khớp tuple toàn BLANK.
    /// Tuple có giá trị không tồn tại trong cột đích thì bỏ. Kết quả dùng với `applying(rows:keep:)`.
    static func treatasRowFilter(tuples: TableValue, targets: [ColumnID], store: ColumnStore) throws(DAXError) -> RowsFilter {
        guard let table = targets.first?.table, targets.allSatisfy({ $0.table == table }) else {
            throw DAXError(.runtime, "TREATAS nhiều cột cần các cột đích cùng một bảng")
        }
        guard tuples.columns.count == targets.count else {
            throw DAXError(.arity, "TREATAS: số cột bảng (\(tuples.columns.count)) khác số cột đích (\(targets.count))")
        }
        let rowCount = try ffCall { try store.rowCount(table) }
        var indexes: [ColumnIndex] = []
        var types: [DAXType] = []
        var lowered: [[String: Int]] = []
        for column in targets {
            let index = try ffCall { try store.index(column) }
            guard index.column.isEncoded else {
                throw DAXError(.runtime, "TREATAS trên cột dense \(column) chưa được hỗ trợ")
            }
            var map: [String: Int] = [:]
            for code in stride(from: 1, through: index.column.dictionaryCount, by: 1) {
                if case .string(let s)? = index.column.dictionaryValue(code: code), map[s.lowercased()] == nil {
                    map[s.lowercased()] = code
                }
            }
            indexes.append(index)
            types.append(store.schema.column(column)?.type ?? .string)
            lowered.append(map)
        }
        var wanted = Set<[Int]>()
        for row in tuples.rows {
            var key: [Int] = []
            key.reserveCapacity(targets.count)
            var matchable = true
            for k in targets.indices {
                guard let code = ffCodeOf(row[k], index: indexes[k], type: types[k], lowered: lowered[k]) else {
                    matchable = false
                    break
                }
                key.append(code)
            }
            if matchable { wanted.insert(key) }
        }
        var matched: [UInt32] = []
        if !wanted.isEmpty {
            // Quét mọi dòng thật và dòng BLANK ảo (chỉ số rowCount, mọi mã bằng 0).
            for r in 0...rowCount {
                let key = indexes.map { $0.column.code(atRow: r) ?? 0 }
                if wanted.contains(key) { matched.append(UInt32(r)) }
            }
        }
        return RowsFilter(table: table, rows: RowSet(universe: rowCount + 1, sortedRows: matched))
    }

    // MARK: USERELATIONSHIP và CROSSFILTER

    /// Quan hệ có cặp cột (nhiều, một) đúng theo thứ tự hoặc đảo ngược. Lỗi nếu lược đồ chưa gắn hoặc không có quan hệ.
    static func relationshipID(_ a: ColumnID, _ b: ColumnID, in ctx: EvalContext) throws(DAXError) -> RelationshipID {
        let relationships = ctx.filter.relationships
        guard !relationships.isEmpty else {
            throw DAXError(.runtime, "USERELATIONSHIP và CROSSFILTER cần lược đồ quan hệ (ngữ cảnh gốc gọi bound(to:))")
        }
        guard let found = relationships.first(where: {
            ($0.manyColumn == a && $0.oneColumn == b) || ($0.manyColumn == b && $0.oneColumn == a)
        }) else {
            throw DAXError(.runtime, "không có quan hệ giữa \(a) và \(b) trong model")
        }
        return found.id
    }

    private static let useRelationshipBody: FunctionSpec.ModifierBody = { (frame: CallFrame) throws(DAXError) -> [ContextModifier] in
        let a = try frame.column(0)
        let b = try frame.column(1)
        return [.useRelationship(try relationshipID(a, b, in: frame.ctx))]
    }

    private static let crossFilterBody: FunctionSpec.ModifierBody = { (frame: CallFrame) throws(DAXError) -> [ContextModifier] in
        let a = try frame.column(0)
        let b = try frame.column(1)
        let id = try relationshipID(a, b, in: frame.ctx)
        let mode: CrossFilterMode
        switch frame.keyword(2) ?? "" {
        case "ONEWAY": mode = .oneDirection
        case "BOTH": mode = .bothDirections
        case "NONE": mode = CrossFilterMode.none
        default:
            throw DAXError(.typeMismatch, "CROSSFILTER cần ONEWAY, BOTH hoặc NONE")
        }
        return [.crossFilter(id, mode)]
    }
}
