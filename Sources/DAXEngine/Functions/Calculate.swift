// CALCULATE và CALCULATETABLE (CORE, đợt 2). Đây là đường găng: thay đổi ngữ cảnh qua ContextModifier.
// Thứ tự theo architecture.md §5.4: (1) đánh giá đối số bộ lọc trong ngữ cảnh ban đầu, (2) context transition,
// (3) bộ sửa đổi REMOVEFILTERS/ALL/ALLEXCEPT/ALLSELECTED/USERELATIONSHIP/CROSSFILTER, (4) bộ lọc (ghi đè,
// hoặc giao khi KEEPFILTERS), (5) đánh giá biểu thức. Row context của ngữ cảnh gốc được giữ nguyên.
//
// [SUY ĐOÁN] Bộ lọc dạng vị ngữ trên đúng một cột được tính bằng cách đánh giá vị ngữ trên từng giá trị của cột
//   (ALL(c) khi ghi đè, VALUES(c) khi KEEPFILTERS). Vị ngữ nhiều cột (tuple) báo lỗi: ContextModifier chưa có dạng này.
// [SUY ĐOÁN] Bộ lọc là bảng vật lý (FILTER(T, …)) quét dòng của T và gửi thẳng RowSet tới FilterContext.
// [SUY ĐOÁN] ALL, ALLEXCEPT, REMOVEFILTERS, KEEPFILTERS, ALLSELECTED được CORE xử lý trực tiếp theo tên, để không
//   phụ thuộc bản cài đặt của F-FILTER. USERELATIONSHIP và CROSSFILTER gọi thân `.modifier` đã đăng ký.
// [SUY ĐOÁN] Bảng nhiều cột làm bộ lọc (TREATAS hai cột, SUMMARIZE nhiều cột) khi mọi cột có lineage cùng một bảng:
//   tập tuple đổi thành tập dòng của bảng đích (`FilterFunctions.treatasRowFilter`), rồi ghi đè CHỈ các cột của
//   bảng ảo (`removingColumns`), không ghi đè mọi cột của bảng. Bộ lọc bảng đó được áp như `.rows` với `removedColumns` rỗng.
//   Lan truyền sang bảng khác vẫn dùng tập mã từng cột của FC, nên có thể rộng hơn đáp án (xem FilterContext.swift).
import ColumnStore

public enum CalculateFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "CALCULATE",
                     params: [.lazy("expression"), .filter("filter", optional: true, repeats: true)],
                     impl: .scalar(calculateBody)),
        FunctionSpec(name: "CALCULATETABLE",
                     params: [.table("expression"), .filter("filter", optional: true, repeats: true)],
                     impl: .table(calculateTableBody)),
    ]

    private static let calculateBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let evaluator = try calculateEvaluator(frame)
        guard let expression = frame.args.first ?? nil else {
            throw DAXError(.arity, "CALCULATE cần biểu thức")
        }
        let ctx = try evaluator.calculatedContext(Array(frame.args.dropFirst()), frame.ctx)
        return try evaluator.scalar(expression, in: ctx)
    }

    private static let calculateTableBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let evaluator = try calculateEvaluator(frame)
        guard let expression = frame.args.first ?? nil else {
            throw DAXError(.arity, "CALCULATETABLE cần biểu thức bảng")
        }
        let ctx = try evaluator.calculatedContext(Array(frame.args.dropFirst()), frame.ctx)
        return try evaluator.table(expression, in: ctx)
    }

    private static func calculateEvaluator(_ frame: CallFrame) throws(DAXError) -> Evaluator {
        guard let evaluator = frame.eval as? Evaluator else {
            throw DAXError(.runtime, "CALCULATE cần Evaluator của CORE")
        }
        return evaluator
    }
}

// MARK: - Kế hoạch bộ lọc (bước 1 của §5.4)

/// Một bước bộ lọc của bước 4: mục cột (ghi đè hoặc giao) hoặc tập dòng của một bảng.
enum CalculationFilter: Sendable {
    case item(FilterItem, keep: Bool)
    case rows(RowsFilter, keep: Bool)
    /// Bộ lọc nhiều cột cùng một bảng (TREATAS hai cột): `rows` là tập dòng của bảng đích, `columns` là các cột
    /// mà bộ lọc ghi đè khi `keep` là false.
    case tuples(RowsFilter, columns: [ColumnID], keep: Bool)
}

/// Kết quả đánh giá đối số bộ lọc trong ngữ cảnh ban đầu.
struct CalculationPlan: Sendable {
    var modifiers: [ContextModifier] = []
    var filters: [CalculationFilter] = []
}

/// Một đối số dùng như tham chiếu: cột, bảng (mở rộng), hoặc danh sách cột (từ bảng ảo).
private enum ColumnReference {
    case column(ColumnID)
    case table(TableID)
    case columns([ColumnID])
}

extension Evaluator {
    /// Ngữ cảnh để đánh giá biểu thức của CALCULATE: áp đủ năm bước của §5.4. Row context của `ctx` được giữ.
    func calculatedContext(_ args: [BoundExpr?], _ ctx: EvalContext) throws(DAXError) -> EvalContext {
        var plan = CalculationPlan()
        for arg in args {
            guard let arg else { continue }
            try addArgument(arg, keep: false, ctx, &plan)
        }
        var filter = ctx.filter
        if ctx.row != nil {
            filter = try transitioned(filter)
        }
        filter = filter.applying(plan.modifiers)
        // Bước ghi đè: mỗi đối số không KEEPFILTERS xoá bộ lọc NGOÀI trên các cột của nó. Làm hết trước khi thêm,
        // để hai đối số cùng một cột (MonthIndex > mi − 3, MonthIndex <= mi) giao nhau chứ không ghi đè nhau
        // (golden G5-month, [Complaints MA3]).
        for step in plan.filters {
            switch step {
            case .item(let item, let keep):
                if !keep { filter = filter.removingColumns([item.column]) }
            case .rows(let rows, let keep):
                if !keep { filter = filter.clearingTable(rows.table) }
            case .tuples(_, let columns, let keep):
                // Chỉ các cột của tuple (không xoá bộ lọc của các cột khác trên cùng bảng).
                if !keep { filter = filter.removingColumns(columns) }
            }
        }
        // Bước giao: mọi đối số AND với nhau và với phần còn lại của ngữ cảnh.
        for step in plan.filters {
            switch step {
            case .item(let item, _):
                filter = filter.applying(item, keep: true)
            case .rows(let rows, _), .tuples(let rows, _, _):
                filter = filter.applying(rows: rows, keep: true)
            }
        }
        return EvalContext(filter: filter, row: ctx.row)
    }

    private func addArgument(_ expr: BoundExpr, keep: Bool, _ ctx: EvalContext,
                             _ plan: inout CalculationPlan) throws(DAXError) {
        switch expr {
        case .call(let fid, let args):
            let spec = try specification(fid)
            switch spec.name {
            case "KEEPFILTERS":
                guard args.count == 1, let inner = args[0] else {
                    throw DAXError(.arity, "KEEPFILTERS cần đúng một đối số bộ lọc")
                }
                try addArgument(inner, keep: true, ctx, &plan)
                return
            case "REMOVEFILTERS", "ALL":
                plan.modifiers += try removalModifiers(args, ctx)
                return
            case "ALLEXCEPT":
                plan.modifiers += try allExceptModifiers(args, ctx)
                return
            case "ALLSELECTED":
                plan.modifiers.append(.allSelected(columns: try selectedColumns(args, ctx)))
                return
            default:
                break
            }
            switch spec.impl {
            case .modifier(let body):
                plan.modifiers += try body(CallFrame(args: args, ctx: ctx, eval: self))
            case .table:
                if spec.name == "FILTER", let rows = try physicalFilter(args, ctx) {
                    plan.filters.append(.rows(rows, keep: keep))
                } else {
                    try addTable(try table(expr, in: ctx), keep: keep, &plan)
                }
            case .scalar:
                try addPredicate(expr, keep: keep, ctx, &plan)
            }
        case .table(let id):
            plan.filters.append(.rows(RowsFilter(table: id, rows: try visibleRows(of: id, in: ctx)), keep: keep))
        case .variable(let slot):
            switch try lookupVariable(slot) {
            case .rows(let id, let rows):
                plan.filters.append(.rows(RowsFilter(table: id, rows: rows), keep: keep))
            case .table(let value):
                try addTable(value, keep: keep, &plan)
            case .scalar:
                throw DAXError(.typeMismatch, "biến vô hướng không dùng được làm bộ lọc (cần vị ngữ hoặc bảng)")
            }
        case .varBlock(let slots, let values, let body):
            try withBlock(slots, values, ctx) { () throws(DAXError) in
                try addArgument(body, keep: keep, ctx, &plan)
            }
        case .binary, .unary, .literal:
            try addPredicate(expr, keep: keep, ctx, &plan)
        case .column:
            throw DAXError(.typeMismatch, "đối số bộ lọc là cột: cần một vị ngữ, ví dụ T[c] = giá trị")
        case .measure:
            throw DAXError(.typeMismatch, "đối số bộ lọc là measure: cần một vị ngữ theo cột")
        default:
            throw DAXError(.typeMismatch, "đối số bộ lọc không hợp lệ")
        }
    }

    /// Bảng ảo làm bộ lọc: một cột có lineage thì thành mục cột với các giá trị của bảng.
    private func addTable(_ value: TableValue, keep: Bool, _ plan: inout CalculationPlan) throws(DAXError) {
        if value.columns.count > 1 {
            try addTuples(value, keep: keep, &plan)
            return
        }
        guard value.columns.count == 1 else {
            throw DAXError(.runtime, "bảng làm bộ lọc trong CALCULATE không có cột nào")
        }
        guard let column = value.lineage[0] else {
            throw DAXError(.typeMismatch, "bảng làm bộ lọc không có lineage cho cột")
        }
        let values = value.rows.map { $0[0] }
        plan.filters.append(.item(FilterItem(column: column, values: values), keep: keep))
    }

    /// Bảng nhiều cột làm bộ lọc: mọi cột phải có lineage cùng một bảng (TREATAS hai cột, SUMMARIZE nhiều cột trên
    /// một bảng). Tập tuple → tập dòng của bảng đích qua `FilterFunctions.treatasRowFilter`.
    private func addTuples(_ value: TableValue, keep: Bool, _ plan: inout CalculationPlan) throws(DAXError) {
        let targets = value.lineage.compactMap { $0 }
        guard targets.count == value.columns.count, let table = targets.first?.table,
              targets.allSatisfy({ $0.table == table }) else {
            throw DAXError(.runtime, "bộ lọc nhiều cột trong CALCULATE cần mọi cột có lineage cùng một bảng")
        }
        let rows = try FilterFunctions.treatasRowFilter(tuples: value, targets: targets, store: store)
        plan.filters.append(.tuples(rows, columns: targets, keep: keep))
    }

    /// REMOVEFILTERS(...) và ALL(...): không đối số là xoá hết; cột là xoá cột; bảng là xoá expanded table.
    private func removalModifiers(_ args: [BoundExpr?], _ ctx: EvalContext) throws(DAXError) -> [ContextModifier] {
        let present = args.compactMap { $0 }
        if present.isEmpty { return [.removeAll] }
        var out: [ContextModifier] = []
        for arg in present {
            switch try reference(arg, ctx) {
            case .column(let column): out.append(.removeColumns([column]))
            case .columns(let columns): out.append(.removeColumns(columns))
            case .table(let table): out.append(.removeExpandedTable(table))
            }
        }
        return out
    }

    /// ALLEXCEPT(T, c…): xoá mọi cột của T trừ các cột được giữ.
    private func allExceptModifiers(_ args: [BoundExpr?], _ ctx: EvalContext) throws(DAXError) -> [ContextModifier] {
        let present = args.compactMap { $0 }
        guard let first = present.first else {
            throw DAXError(.arity, "ALLEXCEPT cần ít nhất một bảng")
        }
        guard case .table(let table) = try reference(first, ctx) else {
            throw DAXError(.typeMismatch, "đối số đầu của ALLEXCEPT phải là bảng")
        }
        var kept: Set<ColumnID> = []
        for arg in present.dropFirst() {
            switch try reference(arg, ctx) {
            case .column(let column): kept.insert(column)
            case .columns(let columns): kept.formUnion(columns)
            case .table: throw DAXError(.typeMismatch, "ALLEXCEPT chỉ nhận cột sau bảng đầu")
            }
        }
        let all = try schemaColumns(of: table).filter { !kept.contains($0) }
        return all.isEmpty ? [] : [.removeColumns(all)]
    }

    /// ALLSELECTED(): mọi cột (nil). ALLSELECTED(c…): các cột đó.
    private func selectedColumns(_ args: [BoundExpr?], _ ctx: EvalContext) throws(DAXError) -> [ColumnID]? {
        let present = args.compactMap { $0 }
        if present.isEmpty { return nil }
        var out: [ColumnID] = []
        for arg in present {
            switch try reference(arg, ctx) {
            case .column(let column): out.append(column)
            case .columns(let columns): out += columns
            case .table(let table): out += try schemaColumns(of: table)
            }
        }
        return out
    }

    private func reference(_ expr: BoundExpr, _ ctx: EvalContext) throws(DAXError) -> ColumnReference {
        switch expr {
        case .column(let column):
            return .column(column)
        case .table(let table):
            return .table(table)
        case .variable(let slot):
            switch try lookupVariable(slot) {
            case .rows(let table, _): return .table(table)
            case .table(let value): return .columns(value.lineage.compactMap { $0 })
            case .scalar: throw DAXError(.expectedColumnRef, "cần một cột hoặc bảng")
            }
        default:
            throw DAXError(.expectedColumnRef, "cần một tham chiếu cột hoặc bảng")
        }
    }

    private func schemaColumns(of table: TableID) throws(DAXError) -> [ColumnID] {
        guard let schemaTable = store.schema.table(table) else {
            throw DAXError(.runtime, "không có bảng \(table) trong model")
        }
        return schemaTable.columns.map(\.id)
    }

    /// FILTER(T, vị ngữ) với T là bảng vật lý hoặc biến giữ RowSet: quét dòng, không materialize.
    /// Trả nil nếu không áp dụng được (để đường chung xử lý).
    private func physicalFilter(_ args: [BoundExpr?], _ ctx: EvalContext) throws(DAXError) -> RowsFilter? {
        guard args.count == 2, let source = args[0], let predicate = args[1] else { return nil }
        let table: TableID
        let domain: RowSet
        switch source {
        case .table(let id):
            table = id
            domain = try visibleRows(of: id, in: ctx)
        case .variable(let slot):
            guard case .rows(let id, let rows) = try lookupVariable(slot) else { return nil }
            table = id
            domain = rows
        default:
            return nil
        }
        var matches: [UInt32] = []
        try iteratePhysical(table, domain, ctx) { (inner: EvalContext) throws(DAXError) in
            guard let r = inner.row?.row else { return }
            if try scalar(predicate, in: inner).asLogical() {
                matches.append(UInt32(r))
            }
        }
        let universe = try runtimeCall { try store.rowCount(table) } + 1
        return RowsFilter(table: table, rows: RowSet(universe: universe, sortedRows: matches))
    }

    /// Vị ngữ trên đúng một cột: đánh giá trên từng giá trị của cột, giữ các giá trị cho vị ngữ đúng.
    private func addPredicate(_ expr: BoundExpr, keep: Bool, _ ctx: EvalContext,
                              _ plan: inout CalculationPlan) throws(DAXError) {
        var columns = Set<ColumnID>()
        collectColumns(expr, into: &columns)
        if columns.isEmpty {
            guard try scalar(expr, in: ctx).asLogical() else {
                throw DAXError(.typeMismatch, "bộ lọc không tham chiếu cột và cho FALSE chưa được hỗ trợ")
            }
            return
        }
        guard columns.count == 1, let column = columns.first else {
            throw DAXError(.runtime, "vị ngữ bộ lọc tham chiếu nhiều cột (tuple) chưa được hỗ trợ")
        }
        guard let name = store.schema.column(column)?.name else {
            throw DAXError(.runtime, "không có cột \(column) trong model")
        }
        let inner = EvalContext(filter: ctx.filter,
                                row: ctx.row ?? RowContext(table: Evaluator.virtualTable, row: 0))
        if !keep, let matches = try equalityMatches(expr, column: column, name: name, inner: inner) {
            plan.filters.append(.item(FilterItem(column: column, values: matches), keep: false))
            return
        }
        let candidates: [Value]
        if keep {
            candidates = try ctx.filter.visibleValues(of: column, in: store)
        } else {
            candidates = try allValues(of: column)
        }
        var kept: [Value] = []
        for value in candidates {
            try checkCancelled()
            if try holds(expr, value, column: column, name: name, inner: inner) {
                kept.append(value)
            }
        }
        plan.filters.append(.item(FilterItem(column: column, values: kept), keep: keep))
    }

    /// Vị ngữ đúng với một giá trị của cột, đánh giá với khung row ảo một dòng (giống vòng lặp chung của addPredicate).
    private func holds(_ expr: BoundExpr, _ value: Value, column: ColumnID, name: String,
                       inner: EvalContext) throws(DAXError) -> Bool {
        rowStack.append(.virtual(TableValue(columns: [name], rows: [[value]], lineage: [column]), 0))
        defer { rowStack.removeLast() }
        return try scalar(expr, in: inner).asLogical()
    }

    /// Đường nhanh cho `cột = hằng` khi không KEEPFILTERS (ví dụ `Fact[trans_timestamp] = t` lặp nhiều lần).
    /// Nil nếu không áp dụng được, khi đó đường chung chạy. Điều kiện: vế hằng không tham chiếu cột, measure hay hàm,
    /// và có kiểu đúng bằng kiểu lưu của cột (nguyên, tiền tệ, số thực, ngày; không NaN). Với các kiểu đó, "=" trùng
    /// với bằng theo StoredValue, nên chỉ cần tra chỉ mục cột thay vì đánh giá trên mọi giá trị khác nhau.
    /// BLANK luôn được đánh giá bằng đúng vị ngữ (BLANK = 0 vẫn có thể đúng).
    private func equalityMatches(_ expr: BoundExpr, column: ColumnID, name: String,
                                 inner: EvalContext) throws(DAXError) -> [Value]? {
        guard case .binary(.equal, let left, let right) = expr else { return nil }
        let constant: BoundExpr
        if case .column(let c) = left, c == column {
            constant = right
        } else if case .column(let c) = right, c == column {
            constant = left
        } else {
            return nil
        }
        guard isPlainConstant(constant), let meta = store.schema.column(column) else { return nil }
        let rowCount = try runtimeCall { try store.rowCount(column.table) }
        guard rowCount > 0 else { return nil }
        let x = try scalar(constant, in: inner)
        guard let key = exactStoredKey(x, type: meta.type) else { return nil }
        let index = try columnIndex(column)
        guard storesKind(of: index.column, like: key) else { return nil }
        var kept: [Value] = []
        if index.column.isEncoded {
            if try holds(expr, .blank, column: column, name: name, inner: inner) {
                kept.append(.blank)
            }
            if let code = index.code(of: key), code > 0,
               let rows = index.postings(forCode: code), !rows.isEmpty {
                kept.append(x)
            }
        } else {
            guard index.denseBlankRowCount() == 0 else { return nil }
            if let rows = index.denseRows(matching: [key]), !rows.isEmpty {
                kept.append(x)
            }
        }
        return kept
    }

    /// Biểu thức hằng: literal, biến, toán tử trên hằng. Không tham chiếu cột, measure hay hàm.
    private func isPlainConstant(_ expr: BoundExpr) -> Bool {
        switch expr {
        case .literal, .variable: true
        case .unary(_, let operand): isPlainConstant(operand)
        case .binary(_, let left, let right): isPlainConstant(left) && isPlainConstant(right)
        default: false
        }
    }

    /// Dạng lưu của cột (từ điển hoặc mảng dense) đúng loại với khoá. Nếu khác loại (ví dụ số nguyên lưu trong cột
    /// số thực) thì so sánh DAX có ép kiểu, nên không dùng đường nhanh.
    private func storesKind(of data: ColumnData, like key: StoredValue) -> Bool {
        switch (key, data.payload) {
        case (.integer, .encoded(_, .integers)), (.currency, .encoded(_, .currency)),
             (.double, .encoded(_, .doubles)), (.dateTime, .encoded(_, .dates)):
            true
        case (.integer, .dense(.integers)): data.type == .integer
        case (.currency, .dense(.integers)): data.type == .currency
        case (.double, .dense(.doubles)), (.dateTime, .dense(.dates)): true
        default: false
        }
    }

    /// Giá trị hằng dưới dạng StoredValue nếu cùng kiểu với cột và không NaN; nil nếu khác kiểu.
    private func exactStoredKey(_ x: Value, type: DAXType) -> StoredValue? {
        switch (x, type) {
        case (.integer(let n), .integer): return .integer(n)
        case (.currency(let n), .currency): return .currency(n)
        case (.double(let d), .double) where !d.isNaN: return .double(d)
        case (.dateTime(let d), .dateTime) where !d.isNaN: return .dateTime(d)
        default: return nil
        }
    }

    /// Mọi cột tham chiếu trực tiếp trong biểu thức (không đi vào thân measure).
    private func collectColumns(_ expr: BoundExpr, into set: inout Set<ColumnID>) {
        switch expr {
        case .column(let column):
            set.insert(column)
        case .unary(_, let operand):
            collectColumns(operand, into: &set)
        case .binary(_, let left, let right):
            collectColumns(left, into: &set)
            collectColumns(right, into: &set)
        case .call(_, let args):
            for arg in args {
                if let arg { collectColumns(arg, into: &set) }
            }
        case .varBlock(_, let values, let body):
            for value in values { collectColumns(value, into: &set) }
            collectColumns(body, into: &set)
        case .tableConstructor(_, let rows):
            for row in rows {
                for item in row { collectColumns(item, into: &set) }
            }
        default:
            break
        }
    }

    /// Mọi giá trị khác nhau của cột trong toàn bảng (ALL(c)), luôn gồm BLANK.
    private func allValues(of column: ColumnID) throws(DAXError) -> [Value] {
        let data = try columnData(column)
        if data.isEncoded {
            let index = try columnIndex(column)
            var out: [Value] = []
            for code in 0...data.dictionaryCount {
                if code & 0xFFF == 0 { try checkCancelled() }
                if code == 0 {
                    // BLANK luôn là ứng viên: dòng BLANK ảo của quan hệ có thể khớp mà cột không có dòng BLANK thật.
                    // [SUY ĐOÁN] Thêm BLANK khi không có dòng thật vẫn an toàn: bộ lọc chỉ khớp dòng BLANK nếu có.
                    out.append(.blank)
                } else if let slice = index.postings(forCode: code), !slice.isEmpty,
                          let stored = data.dictionaryValue(code: code) {
                    out.append(Value(stored: stored))
                }
            }
            return out
        }
        let rowCount = try runtimeCall { try store.rowCount(column.table) }
        var seen = Set<Value>()
        var out: [Value] = []
        for r in 0..<rowCount {
            if r & 0xFFF == 0 { try checkCancelled() }
            let value = Value(stored: data.value(at: r))
            if seen.insert(value).inserted { out.append(value) }
        }
        return out
    }
}
