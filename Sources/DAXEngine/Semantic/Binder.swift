// Binder (LANG, đợt 1a): biến Expr thành BoundExpr, báo lỗi tên và số đối số có vị trí.
// Quy tắc theo architecture.md §5.3:
// - Tra tên không phân biệt hoa thường.
// - [x] không có bảng: measure trước, rồi cột của bảng trong phạm vi tĩnh (row scope); [@c] là cột ảo.
// - T[c]: cột của T; nếu không có thì measure T[m] (DAX cho phép). Cột DEFINE COLUMN bind thành .measure.
// - Tên hàm: raw của FunctionID là chỉ số trong FunctionRegistry.all. Hàm chưa cài vẫn bind được.
// - Kiểm số đối số theo Param (optional, repeats). Cặp value/result và name/expression được kiểm theo cặp.
// - VAR lấy slot riêng trong một lần bind. Slot của DEFINE VAR và DEFINE TABLE do bindQuery cấp.
//
// Hạn chế đã biết (ghi trong báo cáo đợt 1a): chưa phát hiện chu trình measure (circularDependency);
// measure DEFINE tham chiếu VAR của DEFINE chưa có cơ chế frame, Evaluator của đợt 2 quyết định.

import ColumnStore

public enum Binder {
    /// Bind một biểu thức. Slot VAR bắt đầu từ 0.
    public static func bind(_ expr: Expr, catalog: Catalog) throws(DAXError) -> BoundExpr {
        var scope = BindScope(catalog: catalog, nextSlot: 0)
        return try scope.bind(expr)
    }

    /// Bind thân của một measure theo ID trong catalog.
    public static func bindMeasure(_ id: MeasureID, catalog: Catalog) throws(DAXError) -> BoundExpr {
        guard let measure = catalog.measure(id) else {
            throw DAXError(.unknownName, "không có measure với ID \(id.raw)")
        }
        if let error = measure.parseError { throw error }
        guard let body = measure.body else {
            throw DAXError(.syntax, "measure '\(measure.name)' không có biểu thức")
        }
        return try bind(body, catalog: catalog)
    }

    /// Bind một truy vấn: DEFINE VAR và DEFINE TABLE theo thứ tự (mỗi cái thấy các cái trước),
    /// DEFINE MEASURE và COLUMN được đưa vào catalog (thân bind khi cần qua bindMeasure),
    /// rồi bind biểu thức bảng, ORDER BY và START AT của mỗi EVALUATE.
    public static func bindQuery(_ query: Query, catalog: Catalog) throws(DAXError) -> BoundQuery {
        var scope = BindScope(catalog: catalog, nextSlot: 0)
        var definitions: [BoundDefinition] = []
        for definition in query.defines {
            switch definition {
            case .variable(let name, let expr):
                let value = try scope.bind(expr)
                let slot = scope.allocateSlot()
                scope.registerVariable(name: name, slot: slot, virtualColumns: scope.staticVirtualColumns(of: value))
                definitions.append(BoundDefinition(kind: .variable, name: name, slot: slot, value: value))
            case .table(let name, let expr):
                let value = try scope.bind(expr)
                let slot = scope.allocateSlot()
                scope.registerTable(name: name, slot: slot)
                definitions.append(BoundDefinition(kind: .table, name: name, slot: slot, value: value))
            case .measure(let table, let name, let body):
                scope.catalog.defineMeasure(table: table, name: name, body: body)
            case .column(let table, let name, let body):
                scope.catalog.defineColumn(table: table, name: name, body: body)
            }
        }
        var statements: [BoundStatement] = []
        for evaluate in query.statements {
            let table = try scope.bind(evaluate.table)
            var order: [BoundOrderItem] = []
            for item in evaluate.orderBy {
                order.append(BoundOrderItem(expr: try scope.bind(item.expr), ascending: item.ascending))
            }
            var startAt: [BoundExpr] = []
            for expr in evaluate.startAt {
                startAt.append(try scope.bind(expr))
            }
            statements.append(BoundStatement(table: table, orderBy: order, startAt: startAt))
        }
        return BoundQuery(catalog: scope.catalog, definitions: definitions, statements: statements)
    }
}

/// Khai báo DEFINE VAR hoặc DEFINE TABLE đã bind.
public struct BoundDefinition: Sendable {
    public enum Kind: Sendable, Hashable {
        case variable, table
    }

    public let kind: Kind
    public let name: String
    /// Slot trong frame của truy vấn.
    public let slot: Int
    public let value: BoundExpr
}

/// Một mục ORDER BY đã bind.
public struct BoundOrderItem: Sendable {
    public let expr: BoundExpr
    public let ascending: Bool
}

/// Một EVALUATE đã bind.
public struct BoundStatement: Sendable {
    public let table: BoundExpr
    public let orderBy: [BoundOrderItem]
    public let startAt: [BoundExpr]
}

/// Truy vấn đã bind, kèm catalog đã có các khai báo DEFINE.
public struct BoundQuery: Sendable {
    public let catalog: Catalog
    public let definitions: [BoundDefinition]
    public let statements: [BoundStatement]
}

// MARK: - Trạng thái bind của một biểu thức

/// Trạng thái trong một lần bind: VAR đang có hiệu lực, bảng của phạm vi row, và slot.
struct BindScope {
    var catalog: Catalog
    private var nextSlot: Int
    /// VAR đang hiệu lực, tên thường. Phần tử cuối là VAR trong cùng.
    private var variables: [(name: String, slot: Int)] = []
    /// Bảng của các phạm vi row tĩnh (iterator), phần tử cuối là trong cùng.
    private var rowTables: [TableID] = []
    /// Tên cột (chữ thường, không ngoặc) của bảng ảo đang lặp mà suy được tĩnh, vd [Value] của {1, 2}. Trong cùng ở cuối.
    private var virtualScopes: [Set<String>] = []
    /// Bảng nguồn đã biết của slot VAR (để [cột] trong FILTER(tbl, …) tra được bảng).
    private var slotTables: [Int: TableID] = [:]
    /// Cột ảo của slot VAR (bảng ảo).
    private var slotVirtualColumns: [Int: Set<String>] = [:]

    init(catalog: Catalog, nextSlot: Int) {
        self.catalog = catalog
        self.nextSlot = nextSlot
    }

    mutating func allocateSlot() -> Int {
        let slot = nextSlot
        nextSlot += 1
        return slot
    }

    /// Đăng ký DEFINE VAR để các biểu thức sau thấy tên này.
    mutating func registerVariable(name: String, slot: Int, virtualColumns: Set<String>? = nil) {
        variables.append((name.lowercased(), slot))
        catalog.defineVariable(name: name, slot: slot)
        if let virtualColumns {
            slotVirtualColumns[slot] = virtualColumns
        }
    }

    /// Đăng ký DEFINE TABLE. Tra tên bảng sẽ ra slot (BoundExpr.variable), không ra TableID.
    mutating func registerTable(name: String, slot: Int) {
        catalog.defineTable(name: name, slot: slot)
    }

    mutating func bind(_ expr: Expr) throws(DAXError) -> BoundExpr {
        switch expr {
        case .number(let value, let isInteger, _):
            if isInteger && value.magnitude < 9.0e18 {
                return .literal(.integer(Int64(value)))
            }
            return .literal(.double(value))

        case .string(let text, _):
            return .literal(.string(text))

        case .boolean(let flag, _):
            return .literal(.boolean(flag))

        case .columnRef(let table, let column, let range):
            if let table {
                return try bindQualified(table: table, column: column, range: range)
            }
            return try bindBracket(column, range: range)

        case .bracketRef(let name, let range):
            return try bindBracket(name, range: range)

        case .tableRef(let name, let range):
            return try bindTableName(name, range: range)

        case .identifier(let name, let range):
            return try bindIdentifier(name, range: range)

        case .call(let name, let args, let range):
            if name.uppercased() == "SUMMARIZECOLUMNS" {
                return .summarize(try SummarizeColumns.plan(args: args, range: range, scope: &self))
            }
            return try bindCall(name, args: args, range: range)

        case .unary(let op, let operand, _):
            return .unary(op, try bind(operand))

        case .binary(let op, let left, let right, _):
            let l = try bind(left)
            let r = try bind(right)
            return .binary(op, l, r)

        case .varBlock(let vars, let body, _):
            let mark = variables.count
            var slots: [Int] = []
            var values: [BoundExpr] = []
            for v in vars {
                let value = try bind(v.value)
                let slot = allocateSlot()
                if let table = staticTable(of: value) {
                    slotTables[slot] = table
                }
                if let vcols = staticVirtualColumns(of: value) {
                    slotVirtualColumns[slot] = vcols
                }
                variables.append((v.name.lowercased(), slot))
                slots.append(slot)
                values.append(value)
            }
            let boundBody = try bind(body)
            variables.removeLast(variables.count - mark)
            return .varBlock(slots: slots, values: values, body: boundBody)

        case .tableConstructor(let rows, let range):
            let width = rows.first?.count ?? 0
            for row in rows where row.count != width {
                throw DAXError(.arity, "mọi dòng của {…} phải có cùng số cột", range: range)
            }
            var bound: [[BoundExpr]] = []
            for row in rows {
                var boundRow: [BoundExpr] = []
                for item in row {
                    boundRow.append(try bind(item))
                }
                bound.append(boundRow)
            }
            return .tableConstructor(columns: width, rows: bound)
        }
    }

    // MARK: - Tên

    private func lookupVariable(_ name: String) -> Int? {
        let key = name.lowercased()
        return variables.last(where: { $0.name == key })?.slot
    }

    private mutating func bindIdentifier(_ name: String, range: SourceRange) throws(DAXError) -> BoundExpr {
        if let slot = lookupVariable(name) {
            return .variable(slot: slot)
        }
        if let slot = catalog.defineTables[name.lowercased()] {
            return .variable(slot: slot)
        }
        if let table = catalog.modelTable(named: name) {
            return .table(table.id)
        }
        let upper = name.uppercased()
        if BindScope.keywordWords.contains(upper) {
            return .keyword(upper)
        }
        throw DAXError(.unknownName, "không tìm thấy bảng, biến hoặc từ khoá '\(name)'", range: range)
    }

    private func bindTableName(_ name: String, range: SourceRange) throws(DAXError) -> BoundExpr {
        if let slot = catalog.defineTables[name.lowercased()] {
            return .variable(slot: slot)
        }
        if let table = catalog.modelTable(named: name) {
            return .table(table.id)
        }
        throw DAXError(.unknownName, "không tìm thấy bảng '\(name)'", range: range)
    }

    private func bare(_ s: String) -> String {
        s.hasPrefix("[") && s.hasSuffix("]") && s.count >= 2 ? String(s.dropFirst().dropLast()).lowercased() : s.lowercased()
    }

    /// [x] không có bảng: cột ảo của bảng đang lặp, rồi measure, rồi cột của các bảng trong phạm vi row (trong cùng trước).
    private func bindBracket(_ name: String, range: SourceRange) throws(DAXError) -> BoundExpr {
        if name.hasPrefix("@") {
            return .virtualColumn(name: name)
        }
        let bareName = bare(name)
        // Cột của bảng hằng hoặc bảng ảo đang lặp
        if virtualScopes.contains(where: { $0.contains(bareName) }) {
            return .virtualColumn(name: name)
        }
        if let measure = catalog.measure(named: name) {
            return .measure(measure.id)
        }
        for table in rowTables.reversed() {
            if let column = columnID(in: table, named: name) {
                return .column(column)
            }
        }
        throw DAXError(.unknownName, "không tìm thấy measure hoặc cột [\(name)]", range: range)
    }

    /// T[c]: cột của bảng T; nếu không có thì measure hoặc cột DEFINE có tên c (T[m] cho measure).
    private func bindQualified(table: String, column: String, range: SourceRange) throws(DAXError) -> BoundExpr {
        guard let modelTable = catalog.modelTable(named: table) else {
            if let measure = catalog.measure(named: column, table: table) {
                return .measure(measure.id)
            }
            throw DAXError(.unknownName, "không tìm thấy bảng '\(table)'", range: range)
        }
        if let id = columnID(in: modelTable.id, named: column) {
            return .column(id)
        }
        if let measure = catalog.measure(named: column, table: table) {
            // T[m] chỉ hợp lệ khi measure m thuộc đúng bảng T. Power BI báo lỗi "Column 'm' in table 'T' cannot be
            // found or may not be used in this expression" khi m thuộc bảng khác (buổi 2: G6f1, G6f2).
            if measure.table.lowercased() == modelTable.name.lowercased() {
                return .measure(measure.id)
            }
            throw DAXError(.unknownName,
                           "không tìm thấy cột '\(table)'[\(column)]; measure [\(column)] thuộc bảng '\(measure.table)'",
                           range: range)
        }
        throw DAXError(.unknownName, "không tìm thấy cột '\(table)'[\(column)]", range: range)
    }

    private func columnID(in table: TableID, named name: String) -> ColumnID? {
        guard let schemaTable = catalog.schema.table(table) else { return nil }
        let key = name.lowercased()
        return schemaTable.columns.first(where: { $0.name.lowercased() == key })?.id
    }

    // MARK: - Lời gọi hàm

    private mutating func bindCall(_ name: String, args: [Expr?], range: SourceRange) throws(DAXError) -> BoundExpr {
        guard let index = BindScope.functionIndex[name.uppercased()] else {
            throw DAXError(.unknownName, "không nhận ra hàm '\(name)' (chưa hỗ trợ hoặc sai tên)", range: range)
        }
        let spec = FunctionRegistry.all[index]
        let matcher = ArgumentMatcher(spec: spec, args: args)
        let assignment = try matcher.assign(range: range)

        // Cặp table đầu tiên mở phạm vi row cho các đối số sau nó.
        let tableParam = spec.params.firstIndex(where: { $0.kind == .table })
        let scopeArg = tableParam.flatMap { p in assignment.firstIndex(of: p) }

        var bound: [BoundExpr?] = []
        var pushed = false
        var pushedVirtualCount = 0
        for (i, arg) in args.enumerated() {
            guard let arg else {
                bound.append(nil)
                continue
            }
            let param = spec.params[assignment[i]]
            let boundArg: BoundExpr
            if case .keyword(let words) = param.kind {
                guard case .identifier(let word, _) = arg, words.contains(word.uppercased()) else {
                    throw DAXError(.typeMismatch, "đối số \(i + 1) của \(spec.name) phải là một trong: \(words.joined(separator: ", "))",
                                   range: arg.range)
                }
                boundArg = .keyword(word.uppercased())
            } else {
                boundArg = try bind(arg)
                try checkKind(of: param, bound: boundArg, range: arg.range, functionName: spec.name)
            }
            bound.append(boundArg)
            if i == scopeArg, let table = staticTable(of: boundArg) {
                rowTables.append(table)
                pushed = true
            }
            if i == scopeArg, let names = staticVirtualColumns(of: boundArg) {
                virtualScopes.append(names)
                pushedVirtualCount += 1
            }
            if spec.name == "SUBSTITUTEWITHINDEX", i == 2, let names = staticVirtualColumns(of: boundArg) {
                virtualScopes.append(names)
                pushedVirtualCount += 1
            }
        }
        if pushed {
            rowTables.removeLast()
        }
        if pushedVirtualCount > 0 {
            virtualScopes.removeLast(pushedVirtualCount)
        }
        return .call(FunctionID(raw: Int32(index)), bound)
    }

    private func checkKind(of param: Param, bound: BoundExpr, range: SourceRange,
                           functionName: String) throws(DAXError) {
        switch param.kind {
        case .columnRef:
            guard case .column = bound else {
                throw DAXError(.expectedColumnRef, "tham số '\(param.name)' của \(functionName) phải là một cột", range: range)
            }
        case .tableOrColumnRef:
            switch bound {
            case .literal, .measure, .keyword:
                throw DAXError(.typeMismatch, "tham số '\(param.name)' của \(functionName) phải là bảng hoặc cột", range: range)
            default:
                break
            }
        case .table:
            switch bound {
            case .literal, .measure, .keyword:
                throw DAXError(.typeMismatch, "tham số '\(param.name)' của \(functionName) phải là biểu thức bảng", range: range)
            default:
                break
            }
        case .scalar, .lazyScalar, .columnOrScalar, .filter, .keyword:
            break
        }
    }

    /// Bảng nguồn của một biểu thức bảng, nếu suy được một cách tĩnh.
    /// Với lời gọi hàm, lấy đối số của tham số kiểu bảng đầu tiên (vị trí tương ứng).
    private func staticTable(of expr: BoundExpr) -> TableID? {
        switch expr {
        case .table(let id):
            return id
        case .column(let id):
            return id.table
        case .variable(let slot):
            return slotTables[slot]
        case .varBlock(_, _, let body):
            return staticTable(of: body)
        case .call(let fid, let args):
            let index = Int(fid.raw)
            guard index >= 0, index < FunctionRegistry.all.count else { return nil }
            let spec = FunctionRegistry.all[index]
            guard let k = spec.params.firstIndex(where: { $0.kind == .table || $0.kind == .tableOrColumnRef }),
                  k < args.count, let arg = args[k] else { return nil }
            return staticTable(of: arg)
        default:
            return nil
        }
    }

    /// Tên cột của bảng ảo làm nguồn lặp.
    func staticVirtualColumns(of expr: BoundExpr) -> Set<String>? {
        switch expr {
        case .tableConstructor(let columns, _):
            return columns == 1 ? ["value"] : Set((1...max(columns, 1)).map { "value\($0)" })
        case .summarize(let plan):
            var cols = Set<String>()
            for clause in plan.clauses {
                switch clause {
                case .plain(let col):
                    if let cname = catalog.schema.column(col)?.name {
                        cols.insert(cname.lowercased())
                    }
                case .rollup(let levels):
                    for lvl in levels {
                        for col in lvl.columns {
                            if let cname = catalog.schema.column(col)?.name {
                                cols.insert(cname.lowercased())
                            }
                        }
                        cols.insert(bare(lvl.flagName))
                    }
                }
            }
            for m in plan.measures {
                cols.insert(bare(m.name))
            }
            return cols
        case .variable(let slot):
            return slotVirtualColumns[slot]
        case .varBlock(_, _, let body):
            return staticVirtualColumns(of: body)
        case .call(let fid, let args):
            let index = Int(fid.raw)
            guard index >= 0, index < FunctionRegistry.all.count else { return nil }
            let spec = FunctionRegistry.all[index]
            if ["KEEPFILTERS", "FILTER", "CALCULATETABLE", "ALL", "ALLSELECTED"].contains(spec.name),
               let first = args.first, let firstArg = first {
                return staticVirtualColumns(of: firstArg)
            }
            if spec.name == "SUBSTITUTEWITHINDEX", args.count >= 2, let nameExpr = args[1],
               case .literal(.string(let name)) = nameExpr {
                var cols = args[0].flatMap { staticVirtualColumns(of: $0) } ?? Set<String>()
                cols.insert(bare(name))
                return cols
            }
            if spec.name == "ADDCOLUMNS", args.count >= 2 {
                var cols = args[0].flatMap { staticVirtualColumns(of: $0) } ?? Set<String>()
                var i = 1
                while i < args.count {
                    if let a = args[i], case .literal(.string(let name)) = a {
                        cols.insert(bare(name))
                    }
                    i += 2
                }
                return cols
            }
            if spec.name == "GROUPBY", args.count >= 1 {
                var cols = Set<String>()
                var i = 1
                while i < args.count {
                    if let a = args[i] {
                        if case .literal(.string(let name)) = a {
                            cols.insert(bare(name))
                            i += 2
                            continue
                        } else if case .column(let cid) = a {
                            if let cname = catalog.schema.column(cid)?.name {
                                cols.insert(cname.lowercased())
                            }
                        } else if case .virtualColumn(let vname) = a {
                            cols.insert(bare(vname))
                        }
                    }
                    i += 1
                }
                return cols
            }
            if spec.name == "SUMMARIZE", args.count >= 1 {
                var cols = Set<String>()
                var i = 1
                while i < args.count {
                    if let a = args[i] {
                        if case .column(let cid) = a {
                            if let cname = catalog.schema.column(cid)?.name {
                                cols.insert(cname.lowercased())
                            }
                        } else if case .virtualColumn(let vname) = a {
                            cols.insert(bare(vname))
                        } else if case .literal(.string(let name)) = a {
                            cols.insert(bare(name))
                            i += 2
                            continue
                        }
                    }
                    i += 1
                }
                return cols
            }
            guard let k = spec.params.firstIndex(where: { $0.kind == .table || $0.kind == .tableOrColumnRef }),
                  k < args.count, let arg = args[k] else { return nil }
            return staticVirtualColumns(of: arg)
        default:
            return nil
        }
    }

    // MARK: - Dữ liệu tĩnh

    /// Từ khoá đối số (DESC, DENSE, YEAR…) khi tham số không khai báo kiểu keyword.
    static let keywordWords: Set<String> = [
        "ASC", "DESC", "DENSE", "SKIP", "SECOND", "MINUTE", "HOUR", "DAY", "WEEK", "MONTH", "QUARTER", "YEAR", "ALPHABETICAL",
    ]

    /// Tên hàm thường → chỉ số trong FunctionRegistry.all. Trùng tên thì lấy mục đầu tiên.
    static let functionIndex: [String: Int] = {
        var index: [String: Int] = [:]
        for (i, spec) in FunctionRegistry.all.enumerated() where index[spec.name] == nil {
            index[spec.name] = i
        }
        return index
    }()
}

// MARK: - So khớp đối số với tham số

/// Ghép đối số với tham số theo Param. Dùng DP có nhớ để tìm một cách ghép đủ mọi đối số.
/// Với dãy repeats liền nhau, cặp (value, result) và (name, expression) được ghép theo cặp.
final class ArgumentMatcher {
    private enum Unit {
        case single(Int)
        case repeated(Int)
        case pair(Int, Int)
    }

    private static let pairNames: Set<String> = ["value|result", "name|expression", "orderBy|order"]

    private let params: [Param]
    private let args: [Expr?]
    private let units: [Unit]
    private var memo: [Int: Bool] = [:]

    init(spec: FunctionSpec, args: [Expr?]) {
        self.params = spec.params
        self.args = args
        self.units = ArgumentMatcher.makeUnits(spec.params)
    }

    private static func makeUnits(_ params: [Param]) -> [Unit] {
        var out: [Unit] = []
        var i = 0
        while i < params.count {
            let p = params[i]
            if p.repeats, i + 1 < params.count, params[i + 1].repeats,
               pairNames.contains("\(p.name)|\(params[i + 1].name)") {
                out.append(.pair(i, i + 1))
                i += 2
            } else {
                out.append(p.repeats ? .repeated(i) : .single(i))
                i += 1
            }
        }
        return out
    }

    /// Trả về chỉ số tham số cho từng đối số (đối số trống cũng có). Ném .arity nếu không ghép được.
    func assign(range: SourceRange) throws(DAXError) -> [Int] {
        if !feasible(0, 0) {
            throw DAXError(.arity, arityMessage(), range: range)
        }
        var result = [Int](repeating: -1, count: args.count)
        var u = 0
        var a = 0
        while u < units.count {
            switch units[u] {
            case .single(let p):
                if a < args.count, canConsume(params[p], args[a]), feasible(u + 1, a + 1) {
                    result[a] = p
                    a += 1
                }
            case .repeated(let p):
                let k = chooseRepeat(u, a)
                for j in 0..<k { result[a + j] = p }
                a += k
            case .pair(let p, let q):
                let m = choosePairs(u, a)
                for j in 0..<m {
                    result[a + 2 * j] = p
                    result[a + 2 * j + 1] = q
                }
                a += 2 * m
            }
            u += 1
        }
        return result
    }

    private func canConsume(_ param: Param, _ arg: Expr?) -> Bool {
        guard let arg else { return param.optional }
        if case .keyword(let words) = param.kind {
            if case .identifier(let word, _) = arg { return words.contains(word.uppercased()) }
            return false
        }
        // ASC, DESC, DENSE, SKIP không bao giờ là biểu thức; để chúng cho tham số từ khoá.
        if case .identifier(let word, _) = arg, ["ASC", "DESC", "DENSE", "SKIP"].contains(word.uppercased()) {
            return false
        }
        // Nhóm cột lặp (SUMMARIZE, ALL…) dừng trước chuỗi, số, logic: đó là tên hoặc giá trị của cặp
        // (tên, biểu thức) phía sau, không bao giờ là bảng hoặc cột. Nếu không, lần ghép tham lam nuốt
        // "Số GD" làm cột nhóm và báo lỗi groupBy. Tham số không lặp giữ nguyên hành vi (báo typeMismatch).
        if param.repeats, case .tableOrColumnRef = param.kind, ArgumentMatcher.isScalarLiteral(arg) {
            return false
        }
        return true
    }

    /// Chuỗi, số hoặc logic viết thẳng trong mã (không phải bảng, cột hay lời gọi).
    private static func isScalarLiteral(_ arg: Expr) -> Bool {
        switch arg {
        case .string, .number, .boolean:
            return true
        default:
            return false
        }
    }

    private func feasible(_ u: Int, _ a: Int) -> Bool {
        if u == units.count { return a == args.count }
        let key = u * (args.count + 1) + a
        if let cached = memo[key] { return cached }
        var ok = false
        switch units[u] {
        case .single(let p):
            if a < args.count, canConsume(params[p], args[a]), feasible(u + 1, a + 1) {
                ok = true
            } else if params[p].optional, feasible(u + 1, a) {
                ok = true
            }
        case .repeated:
            ok = repeatedFeasible(u, a)
        case .pair:
            ok = pairFeasible(u, a)
        }
        memo[key] = ok
        return ok
    }

    /// Số đối số liên tiếp từ a mà tham số của unit u nhận được.
    private func repeatedRun(_ u: Int, _ a: Int) -> Int {
        guard case .repeated(let p) = units[u] else { return 0 }
        var n = 0
        while a + n < args.count, canConsume(params[p], args[a + n]) { n += 1 }
        return n
    }

    private func repeatedMin(_ u: Int) -> Int {
        guard case .repeated(let p) = units[u] else { return 0 }
        return params[p].optional ? 0 : 1
    }

    private func repeatedFeasible(_ u: Int, _ a: Int) -> Bool {
        chooseRepeatOrNil(u, a) != nil
    }

    /// Chọn k lớn nhất (để ưu tiên ghép nhiều hơn) sao cho phần còn lại vẫn ghép được.
    private func chooseRepeat(_ u: Int, _ a: Int) -> Int {
        chooseRepeatOrNil(u, a) ?? 0
    }

    private func chooseRepeatOrNil(_ u: Int, _ a: Int) -> Int? {
        let maxK = repeatedRun(u, a)
        let minK = repeatedMin(u)
        guard maxK >= minK else { return nil }
        for k in stride(from: maxK, through: minK, by: -1) where feasible(u + 1, a + k) {
            return k
        }
        return nil
    }

    private func pairRun(_ u: Int, _ a: Int) -> Int {
        guard case .pair(let p, let q) = units[u] else { return 0 }
        var m = 0
        while a + 2 * m + 1 < args.count,
              canConsume(params[p], args[a + 2 * m]),
              canConsume(params[q], args[a + 2 * m + 1]) {
            m += 1
        }
        return m
    }

    private func pairMin(_ u: Int) -> Int {
        guard case .pair(let p, let q) = units[u] else { return 0 }
        return (params[p].optional && params[q].optional) ? 0 : 1
    }

    private func pairFeasible(_ u: Int, _ a: Int) -> Bool {
        choosePairsOrNil(u, a) != nil
    }

    private func choosePairs(_ u: Int, _ a: Int) -> Int {
        choosePairsOrNil(u, a) ?? 0
    }

    private func choosePairsOrNil(_ u: Int, _ a: Int) -> Int? {
        let maxM = pairRun(u, a)
        let minM = pairMin(u)
        guard maxM >= minM else { return nil }
        for m in stride(from: maxM, through: minM, by: -1) where feasible(u + 1, a + 2 * m) {
            return m
        }
        return nil
    }

    private func arityMessage() -> String {
        var minimum = 0
        var unbounded = false
        for unit in units {
            switch unit {
            case .single(let p):
                if !params[p].optional { minimum += 1 }
            case .repeated(let p):
                if !params[p].optional { minimum += 1 }
                unbounded = true
            case .pair(let p, let q):
                if !(params[p].optional && params[q].optional) { minimum += 2 }
                unbounded = true
            }
        }
        let expected: String
        if unbounded {
            expected = "ít nhất \(minimum)"
        } else {
            let maximum = params.count
            expected = minimum == maximum ? "\(minimum)" : "từ \(minimum) đến \(maximum)"
        }
        return "hàm có \(args.count) đối số, cần \(expected)"
    }
}
