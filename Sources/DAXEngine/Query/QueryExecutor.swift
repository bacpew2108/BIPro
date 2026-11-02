// Thực thi truy vấn (QRY, đợt 2), architecture.md §6. Đầu vào là `Query` đã parse (LANG).
//
// Luồng:
// 1. Lượt 1 của DEFINE: MEASURE và COLUMN được đưa vào catalog (để VAR, TABLE và EVALUATE đều thấy).
// 2. Tạo evaluator từ catalog đã có DEFINE (`makeEvaluator`, do lead/CORE cung cấp).
// 3. Lượt 2 của DEFINE theo thứ tự: VAR vô hướng được tính một lần trong ngữ cảnh gốc rồi thay bằng literal;
//    VAR bảng và TABLE được thay bằng biểu thức đã bind (lười, tính lại ở nơi dùng).
// 4. Mỗi EVALUATE: ROW và SUMMARIZECOLUMNS được xử lý tại đây; biểu thức bảng khác đi qua evaluator.
//    Rồi ORDER BY (nhiều cột, ASC/DESC) và START AT. Mỗi EVALUATE cho một ResultTable.
//
// Tên cột kết quả: cột có lineage là "Bảng[cột]"; cột ảo là "[tên]".
//
// [SUY ĐOÁN] BLANK đứng đầu khi ASC; kiểu khác nhau xếp theo thứ tự BLANK < logic < số/ngày < chuỗi.
// [SUY ĐOÁN] So chuỗi không phân biệt hoa thường bằng lowercased(), chưa theo collation của model (chờ O17).
// [SUY ĐOÁN] ORDER BY chỉ nhận cột hoặc [tên cột] có trong kết quả; biểu thức tuỳ ý báo lỗi.
// [SUY ĐOÁN] Với VAR bảng, tham chiếu được thay bằng biểu thức gốc nên được tính lại trong ngữ cảnh nơi dùng,
// khác DAX ở nơi ngữ cảnh đổi (VAR vô hướng thì không ảnh hưởng vì đã thành literal).
// [SUY ĐOÁN] VAR vô hướng được tính ngay khi chuẩn bị, nên lỗi của VAR không dùng tới vẫn bị báo.
// Giới hạn đã biết: DEFINE MEASURE không thấy DEFINE VAR (Binder chỉ tra VAR của phạm vi truy vấn);
// Evaluating không có frame biến, nên các tham chiếu `.variable` còn lại ném lỗi ở evaluator.

import ColumnStore

public enum QueryExecutor {
    /// Tuỳ chọn thực thi. Mặc định không cắt dòng; cắt là việc của UI, chỉ bật khi có giới hạn cấu hình.
    public struct Options: Sendable, Hashable {
        /// Số dòng tối đa của mỗi bảng kết quả. nil (mặc định): không cắt.
        public var rowLimit: Int?

        public init(rowLimit: Int? = nil) {
            self.rowLimit = rowLimit
        }
    }

    /// Tạo evaluator từ catalog đã gồm DEFINE MEASURE/COLUMN của truy vấn.
    public typealias EvaluatorFactory = @Sendable (Catalog) -> any Evaluating

    /// Chạy một truy vấn đã parse. Huỷ bằng Task.cancel(): ném DAXError kind .cancelled ở vòng lặp kế tiếp.
    /// - Parameters:
    ///   - model: catalog của model (lược đồ và measure của model).
    ///   - store: kho cột của model (dùng cho bộ lọc, auto-exist và đọc cột).
    ///   - makeEvaluator: tạo evaluator từ catalog có DEFINE; CORE cung cấp bản cài đặt.
    public static func execute(_ query: Query, model: Catalog, store: ColumnStore,
                               makeEvaluator: EvaluatorFactory,
                               options: Options = Options()) async throws(DAXError) -> QueryResult {
        let started = ContinuousClock.now
        try checkCancelled()
        let prepared = try prepare(query, model: model, store: store, makeEvaluator: makeEvaluator)
        var tables: [ResultTable] = []
        for statement in prepared.statements {
            try checkCancelled()
            tables.append(try run(statement, prepared: prepared, store: store, options: options))
        }
        return QueryResult(tables: tables, elapsedNanoseconds: elapsed(since: started))
    }

    // MARK: - Chuẩn bị

    /// Truy vấn đã bind, sẵn sàng đánh giá.
    struct PreparedQuery {
        let evaluator: any Evaluating
        let base: EvalContext
        let statements: [PreparedStatement]
    }

    /// Một EVALUATE đã bind. ORDER BY giữ dạng Expr vì chỉ resolve được khi biết tên cột kết quả.
    struct PreparedStatement {
        enum Source {
            case table(BoundExpr)
            case row([(name: String, expr: BoundExpr)])
            case summarize(SummarizeColumns.Plan)
        }

        let source: Source
        let orderBy: [(expr: Expr, ascending: Bool)]
        let startAt: [BoundExpr]
    }

    static func prepare(_ query: Query, model: Catalog, store: ColumnStore,
                        makeEvaluator: EvaluatorFactory) throws(DAXError) -> PreparedQuery {
        var scope = BindScope(catalog: model, nextSlot: 0)

        // Lượt 1: MEASURE và COLUMN, không phụ thuộc thứ tự khai báo.
        for definition in query.defines {
            switch definition {
            case .measure(let table, let name, let body):
                scope.catalog.defineMeasure(table: table, name: name, body: body)
            case .column(let table, let name, let body):
                scope.catalog.defineColumn(table: table, name: name, body: body)
            case .variable, .table:
                break
            }
        }

        let evaluator = makeEvaluator(scope.catalog)
        let base = EvalContext(filter: FilterContext.empty.bound(to: model.schema), row: nil)

        // Lượt 2: VAR và TABLE theo thứ tự. env thay `.variable(slot)` bằng giá trị hoặc biểu thức bảng.
        var env: [Int: BoundExpr] = [:]
        var tableSlots = Set<Int>()
        for definition in query.defines {
            switch definition {
            case .variable(let name, let expr):
                let value = substitute(try scope.bind(expr), env)
                let slot = scope.allocateSlot()
                scope.registerVariable(name: name, slot: slot)
                if isTable(value, tableSlots) {
                    tableSlots.insert(slot)
                    env[slot] = value
                } else {
                    env[slot] = .literal(try evaluator.scalar(value, in: base))
                }
            case .table(let name, let expr):
                let value = substitute(try scope.bind(expr), env)
                let slot = scope.allocateSlot()
                scope.registerTable(name: name, slot: slot)
                tableSlots.insert(slot)
                env[slot] = value
            case .measure, .column:
                break
            }
        }

        // EVALUATE: ROW và SUMMARIZECOLUMNS được bind tại đây, các dạng còn lại qua Binder.
        var statements: [PreparedStatement] = []
        for evaluate in query.statements {
            let source: PreparedStatement.Source
            if case .call(let name, let args, let range) = evaluate.table, name.uppercased() == "ROW" {
                let pairs = try bindRowPairs(args, range: range, scope: &scope)
                var mapped: [(name: String, expr: BoundExpr)] = []
                for pair in pairs {
                    mapped.append((name: pair.name, expr: substitute(pair.expr, env)))
                }
                source = .row(mapped)
            } else if case .call(let name, let args, let range) = evaluate.table,
                      name.uppercased() == "SUMMARIZECOLUMNS" {
                let plan = try SummarizeColumns.plan(args: args, range: range, scope: &scope)
                source = .summarize(plan.mapExpressions { substitute($0, env) })
            } else {
                source = .table(substitute(try scope.bind(evaluate.table), env))
            }

            var startAt: [BoundExpr] = []
            for expr in evaluate.startAt {
                startAt.append(substitute(try scope.bind(expr), env))
            }
            var orderBy: [(expr: Expr, ascending: Bool)] = []
            for item in evaluate.orderBy {
                orderBy.append((expr: item.expr, ascending: item.ascending))
            }
            statements.append(PreparedStatement(source: source, orderBy: orderBy, startAt: startAt))
        }
        return PreparedQuery(evaluator: evaluator, base: base, statements: statements)
    }

    /// ROW("tên", biểu thức, …): cặp tên và biểu thức.
    static func bindRowPairs(_ args: [Expr?], range: SourceRange,
                             scope: inout BindScope) throws(DAXError) -> [(name: String, expr: BoundExpr)] {
        guard !args.isEmpty, args.count % 2 == 0 else {
            throw DAXError(.arity, "ROW cần các cặp (tên, biểu thức)", range: range)
        }
        var out: [(name: String, expr: BoundExpr)] = []
        var i = 0
        while i < args.count {
            guard let nameArg = args[i], case .string(let name, _) = nameArg else {
                throw DAXError(.syntax, "ROW: tên cột phải là chuỗi", range: args[i]?.range ?? range)
            }
            guard let exprArg = args[i + 1] else {
                throw DAXError(.arity, "ROW: thiếu biểu thức cho \"\(name)\"", range: nameArg.range)
            }
            out.append((name: name, expr: try scope.bind(exprArg)))
            i += 2
        }
        return out
    }

    // MARK: - Thay VAR và TABLE

    /// Thay `.variable(slot)` có trong env. Các biến cục bộ của VAR trong biểu thức không nằm trong env.
    static func substitute(_ expr: BoundExpr, _ env: [Int: BoundExpr]) -> BoundExpr {
        if env.isEmpty { return expr }
        switch expr {
        case .variable(let slot):
            return env[slot] ?? expr
        case .call(let function, let args):
            return .call(function, args.map { arg in arg.map { substitute($0, env) } })
        case .unary(let op, let operand):
            return .unary(op, substitute(operand, env))
        case .binary(let op, let left, let right):
            return .binary(op, substitute(left, env), substitute(right, env))
        case .varBlock(let slots, let values, let body):
            return .varBlock(slots: slots, values: values.map { substitute($0, env) }, body: substitute(body, env))
        case .tableConstructor(let columns, let rows):
            return .tableConstructor(columns: columns, rows: rows.map { row in row.map { substitute($0, env) } })
        default:
            return expr
        }
    }

    /// Biểu thức có giá trị bảng hay không (để chọn cách thay VAR).
    static func isTable(_ expr: BoundExpr, _ tableSlots: Set<Int>) -> Bool {
        switch expr {
        case .table, .tableConstructor:
            return true
        case .variable(let slot):
            return tableSlots.contains(slot)
        case .call(let function, _):
            let index = Int(function.raw)
            guard FunctionRegistry.all.indices.contains(index) else { return false }
            if case .table(_) = FunctionRegistry.all[index].impl { return true }
            return false
        case .varBlock(_, _, let body):
            return isTable(body, tableSlots)
        default:
            return false
        }
    }

    // MARK: - Chạy một EVALUATE

    static func run(_ statement: PreparedStatement, prepared: PreparedQuery, store: ColumnStore,
                    options: Options) throws(DAXError) -> ResultTable {
        var headers: [String] = []
        var rows: [[Value]] = []
        switch statement.source {
        case .table(let expr):
            let table = try prepared.evaluator.table(expr, in: prepared.base)
            for index in table.columns.indices {
                headers.append(header(lineage: table.lineage[index], name: table.columns[index], schema: store.schema))
            }
            rows = table.rows
        case .row(let pairs):
            var values: [Value] = []
            for pair in pairs {
                values.append(try prepared.evaluator.scalar(pair.expr, in: prepared.base))
            }
            headers = pairs.map { "[\($0.name)]" }
            rows = [values]
        case .summarize(let plan):
            rows = try SummarizeColumns.evaluate(plan, base: prepared.base, store: store,
                                                 evaluator: prepared.evaluator)
            for column in plan.groupColumns {
                headers.append(header(for: column, schema: store.schema))
            }
            for measure in plan.measures {
                headers.append("[\(measure.name)]")
            }
        }

        let keys = try resolveOrder(statement.orderBy, headers: headers)
        if !keys.isEmpty {
            try checkCancelled()
            rows = sortRows(rows, keys)
        }
        if !statement.startAt.isEmpty {
            guard !keys.isEmpty else {
                throw DAXError(.syntax, "START AT cần có ORDER BY")
            }
            guard statement.startAt.count == keys.count else {
                throw DAXError(.arity, "START AT có \(statement.startAt.count) giá trị nhưng ORDER BY có \(keys.count) cột")
            }
            var start: [Value] = []
            for expr in statement.startAt {
                start.append(try prepared.evaluator.scalar(expr, in: prepared.base))
            }
            try checkCancelled()
            let from = rows.firstIndex { compareToStart($0, start, keys) >= 0 } ?? rows.count
            rows = Array(rows[from...])
        }

        var truncated = false
        if let limit = options.rowLimit, rows.count > limit {
            rows = Array(rows.prefix(max(0, limit)))
            truncated = true
        }
        return ResultTable(columns: headers, rows: rows, isTruncated: truncated)
    }

    // MARK: - Tên cột

    /// "Bảng[cột]" cho cột gốc của model.
    static func header(for column: ColumnID, schema: ModelSchema) -> String {
        let table = schema.table(column.table)?.name ?? "T\(column.table.raw)"
        let name = schema.column(column)?.name ?? "C\(column.index)"
        return "\(table)[\(name)]"
    }

    static func header(lineage: ColumnID?, name: String, schema: ModelSchema) -> String {
        if let lineage {
            return header(for: lineage, schema: schema)
        }
        return name.hasPrefix("[") ? name : "[\(name)]"
    }

    // MARK: - ORDER BY và START AT

    /// Ánh xạ mỗi mục ORDER BY sang chỉ số cột của kết quả.
    static func resolveOrder(_ items: [(expr: Expr, ascending: Bool)],
                             headers: [String]) throws(DAXError) -> [(index: Int, ascending: Bool)] {
        let lowered = headers.map { $0.lowercased() }
        var keys: [(index: Int, ascending: Bool)] = []
        for item in items {
            let key = try headerKey(item.expr)
            guard let index = matchHeader(key, lowered) else {
                throw DAXError(.unknownName,
                               "ORDER BY: không có cột \(key) trong kết quả (biểu thức tuỳ ý chưa hỗ trợ)",
                               range: item.expr.range)
            }
            keys.append((index: index, ascending: item.ascending))
        }
        return keys
    }

    static func headerKey(_ expr: Expr) throws(DAXError) -> String {
        switch expr {
        case .columnRef(let table, let column, _):
            if let table {
                return "\(table)[\(column)]".lowercased()
            }
            return "[\(column)]".lowercased()
        case .bracketRef(let name, _):
            return "[\(name)]".lowercased()
        default:
            throw DAXError(.unsupportedFunction, "ORDER BY chỉ nhận cột hoặc [tên cột] của kết quả", range: expr.range)
        }
    }

    /// Khớp đúng tên trước; nếu khoá không có bảng thì khớp theo đuôi "[tên]".
    static func matchHeader(_ key: String, _ lowered: [String]) -> Int? {
        if let exact = lowered.firstIndex(of: key) {
            return exact
        }
        if key.hasPrefix("[") {
            return lowered.firstIndex { $0.hasSuffix(key) }
        }
        return nil
    }

    static func sortRows(_ rows: [[Value]], _ keys: [(index: Int, ascending: Bool)]) -> [[Value]] {
        let order = rows.indices.sorted { i, j in
            let c = compareByKeys(rows[i], rows[j], keys)
            return c != 0 ? c < 0 : i < j
        }
        return order.map { rows[$0] }
    }

    static func compareByKeys(_ a: [Value], _ b: [Value], _ keys: [(index: Int, ascending: Bool)]) -> Int {
        for key in keys {
            var c = compareValues(a[key.index], b[key.index])
            if !key.ascending { c = -c }
            if c != 0 { return c }
        }
        return 0
    }

    /// So một dòng với bộ giá trị START AT theo chiều của ORDER BY.
    static func compareToStart(_ row: [Value], _ start: [Value], _ keys: [(index: Int, ascending: Bool)]) -> Int {
        for (k, key) in keys.enumerated() {
            var c = compareValues(row[key.index], start[k])
            if !key.ascending { c = -c }
            if c != 0 { return c }
        }
        return 0
    }

    // MARK: - So sánh giá trị (thứ tự sắp)

    /// Thứ tự kiểu: logic < số/ngày giờ < chuỗi. BLANK so như giá trị rỗng của kiểu bên kia (0, FALSE, ""),
    /// nên ORDER BY [Value] của {1, BLANK(), -1} cho -1, BLANK, 1 (quan sát O18a, buổi 2). Bằng nhau thì BLANK
    /// đứng ngay trước: {1, 0, BLANK(), -1} cho -1, BLANK, 0, 1 (quan sát O19, buổi 3). Trả âm, 0, dương.
    static func compareValues(_ a: Value, _ b: Value) -> Int {
        switch (a, b) {
        case (.blank, .blank):
            return 0
        case (.blank, _):
            let c = compareValues(blankStandIn(for: b), b)
            return c == 0 ? -1 : c
        case (_, .blank):
            let c = compareValues(a, blankStandIn(for: a))
            return c == 0 ? 1 : c
        default:
            break
        }
        let ra = typeRank(a), rb = typeRank(b)
        if ra != rb { return ra < rb ? -1 : 1 }
        switch (a, b) {
        case (.boolean(let x), .boolean(let y)):
            return x == y ? 0 : (x ? 1 : -1)
        case (.string(let x), .string(let y)):
            let lx = x.lowercased(), ly = y.lowercased()
            return lx == ly ? 0 : (lx < ly ? -1 : 1)
        case (.blank, .blank):
            return 0
        default:
            let x = numericKey(a), y = numericKey(b)
            // NaN đứng trước mọi số và bằng nhau, để thứ tự là toàn phần.
            if x.isNaN || y.isNaN {
                if x.isNaN && y.isNaN { return 0 }
                return x.isNaN ? -1 : 1
            }
            return x == y ? 0 : (x < y ? -1 : 1)
        }
    }

    static func compareTuples(_ a: [Value], _ b: [Value]) -> Int {
        for (x, y) in zip(a, b) {
            let c = compareValues(x, y)
            if c != 0 { return c }
        }
        return 0
    }

    /// Giá trị rỗng cùng kiểu dùng thay BLANK khi sắp xếp.
    private static func blankStandIn(for value: Value) -> Value {
        switch value {
        case .boolean: return .boolean(false)
        case .string: return .string("")
        case .currency: return .currency(0)
        case .dateTime: return .dateTime(0)
        case .double: return .double(0)
        default: return .integer(0)
        }
    }

    private static func typeRank(_ value: Value) -> Int {
        switch value {
        case .blank: return 0
        case .boolean: return 1
        case .integer, .double, .currency, .dateTime: return 2
        case .string: return 3
        }
    }

    private static func numericKey(_ value: Value) -> Double {
        switch value {
        case .integer(let v): return Double(v)
        case .double(let v): return v
        case .currency(let v): return Double(v) / 10_000
        case .dateTime(let v): return v
        case .blank, .boolean, .string: return 0
        }
    }

    // MARK: - Tiện ích

    /// Huỷ: ném `.cancelled` khi Task hiện tại đã bị huỷ.
    static func checkCancelled() throws(DAXError) {
        if Task.isCancelled {
            throw DAXError(.cancelled, "đã huỷ")
        }
    }

    /// Chuyển lỗi không phải DAXError (từ ColumnStore) thành DAXError.
    static func guarded<T>(_ body: () throws -> T) throws(DAXError) -> T {
        do {
            return try body()
        } catch let error as DAXError {
            throw error
        } catch {
            throw DAXError(.runtime, "\(error)")
        }
    }

    static func elapsed(since start: ContinuousClock.Instant) -> UInt64 {
        let parts = start.duration(to: ContinuousClock.now).components
        let seconds = UInt64(max(0, parts.seconds))
        let nanos = UInt64(max(0, parts.attoseconds / 1_000_000_000))
        return seconds * 1_000_000_000 + nanos
    }
}
