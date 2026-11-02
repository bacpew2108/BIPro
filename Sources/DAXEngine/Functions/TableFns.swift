// Hàm bảng (F-KIT đợt 2, F-TABLE đợt 3). Đợt 2 cài: FILTER, VALUES, RELATED. Đợt 3 cài thêm: DISTINCT,
// SUMMARIZE, ADDCOLUMNS, CROSSJOIN, TOPN, RELATEDTABLE. Chữ ký do lead khai báo ở đợt 0, không đổi.
//
// - FILTER: nguồn vật lý (T hoặc biến giữ RowSet) được lặp qua `iterateArgument`, không materialize nguồn;
//   chỉ các dòng khớp được vật chất hoá làm kết quả. Nguồn ảo được vật chất hoá rồi lọc theo chỉ số dòng.
//   Vị ngữ đánh giá trong row context của từng dòng.
// - VALUES(cột): giá trị thấy được theo `FilterContext.visibleValues` (có thể có BLANK từ dòng BLANK ảo).
//   VALUES(bảng): bản sao DISTINCT của bảng thấy được, giữ lineage.
// - RELATED(cột): đi theo quan hệ many→one từ khung row gần nhất (chỉ quan hệ active), qua `relationshipIndex` của REL.
//   Không khớp (kể cả FK BLANK) cho BLANK.
// - DISTINCT(cột) giống VALUES(cột). DISTINCT(bảng): bỏ dòng trùng, giữ thứ tự xuất hiện, giữ lineage. Với nguồn vật lý,
//   chỉ các dòng đầu tiên của mỗi nhóm trùng được vật chất hoá.
// - SUMMARIZE(bảng, cột nhóm…[, "tên", biểu thức]…): lặp nguồn, lấy bộ giá trị nhóm (cột cùng bảng hoặc cột bảng liên
//   quan qua RELATED), bỏ trùng theo thứ tự xuất hiện. Không materialize nguồn. Cột kết quả mang lineage của cột nhóm.
//   Cặp tên/biểu thức (nếu có) được tính trong bộ lọc của từng nhóm (không lặp dòng để tổng hợp).
// - ADDCOLUMNS(bảng, "tên", biểu thức…): mỗi dòng nguồn được đánh giá trong row context của chính dòng đó.
//   Dòng đầu ra có đủ cột của nguồn (giữ lineage) và các cột mới (lineage nil).
// - CROSSJOIN(bảng1, bảng2…): tích Descartes, nối cột và lineage.
// - TOPN(n, bảng, biểu thức sắp xếp…, [ASC|DESC]): sắp xếp rồi lấy n dòng; các dòng bằng giá trị của dòng thứ n đều giữ.
// - RELATEDTABLE(bảng): context transition từ mọi khung row hiện tại, rồi lấy các dòng thấy được của bảng đích.
//   Không có row context thì như bảng đích thường.
//
// [SUY ĐOÁN] RELATED dùng quan hệ active, bỏ qua USERELATIONSHIP. Khi có nhiều đường, lấy đường BFS đầu tiên.
// [SUY ĐOÁN] RELATED từ khung bảng ảo chỉ đi một bước, tra dòng bên một bằng so sánh giá trị (không phân biệt
//   hoa thường khác với chỉ mục REL).
// [SUY ĐOÁN] DISTINCT(cột) và VALUES(cột) cùng cho ra BLANK từ dòng BLANK ảo khi có fact không khớp đang thấy.
// [SUY ĐOÁN] SUMMARIZE với nhóm gồm cột bảng liên quan: fact không khớp cho nhóm BLANK (một dòng BLANK).
// [SUY ĐOÁN] SUMMARIZE(bảng) không cột nhóm: một dòng rỗng nếu nguồn có dòng thấy được, không thì không dòng.
// [SUY ĐOÁN] Tên cột SUMMARIZE dạng "Bảng[cột]" (kể cả cột cùng bảng). Tên cột DISTINCT/VALUES giữ kiểu cũ là tên trần.
// [SUY ĐOÁN] TOPN không có biểu thức sắp xếp báo lỗi. Từ khoá ASC/DESC áp chung cho mọi biểu thức sắp xếp; mặc định ASC.
//   Giá trị BLANK đứng trước khi sắp tăng dần. Với giá trị bằng nhau tại ngưỡng thì giữ mọi dòng (quy tắc DAX).
// [SUY ĐOÁN] RELATEDTABLE từ phía nhiều tới phía một chỉ biến đổi ngữ cảnh rồi lấy bảng đích, nên trả toàn bộ bảng
//   đích (không chỉ dòng liên quan), như hành vi thường gặp của DAX. Chưa đối chiếu oracle.
// [SUY ĐOÁN] CROSSJOIN vật chất hoá từng đầu vào đúng một lần (không theo từng cặp). Đầu vào là bảng nhỏ trong MiniBank.
import ColumnStore

// MARK: - Tiện ích dùng chung cho các hàm F-KIT và F-TABLE (cùng module)

/// Evaluator của CORE, để đọc khung row, biến và bảng vật lý. Lỗi nếu evaluator thuộc loại khác.
func fkEvaluator(_ frame: CallFrame) throws(DAXError) -> Evaluator {
    guard let evaluator = frame.eval as? Evaluator else {
        throw DAXError(.runtime, "hàm này cần Evaluator của CORE")
    }
    return evaluator
}

/// Đối số thứ `i`, nil nếu thiếu hoặc bỏ trống.
func fkArg(_ frame: CallFrame, _ i: Int) -> BoundExpr? {
    guard i >= 0, i < frame.args.count else { return nil }
    return frame.args[i]
}

/// Nguồn vật lý: bảng `T` hoặc biến giữ RowSet. nil nếu là bảng ảo (hoặc biểu thức khác).
func fkPhysicalSource(_ expr: BoundExpr, _ evaluator: Evaluator,
                      _ ctx: EvalContext) throws(DAXError) -> (table: TableID, rows: RowSet)? {
    switch expr {
    case .table(let id):
        let rows = try evaluator.visibleRows(of: id, in: ctx)
        return (table: id, rows: rows)
    case .variable(let slot):
        if case .rows(let id, let rows) = try evaluator.lookupVariable(slot) {
            return (table: id, rows: rows)
        }
        return nil
    case .call(let fid, let args):
        let spec = try evaluator.specification(fid)
        if spec.name == "KEEPFILTERS", let inner = args.first ?? nil {
            return try fkPhysicalSource(inner, evaluator, ctx)
        }
        return nil
    default:
        return nil
    }
}

/// FILTER(args[0], args[1]) khi nguồn là bảng vật lý: lặp nguồn qua `iterateArgument` và giữ các dòng có vị ngữ
/// đúng. Không materialize nguồn. Trả nil nếu nguồn là bảng ảo (khi đó để đường chung xử lý).
func fkFilterMatches(args: [BoundExpr?], evaluator: Evaluator,
                     ctx: EvalContext) throws(DAXError) -> (table: TableID, rows: RowSet)? {
    guard args.count == 2, let source = args[0], let predicate = args[1] else { return nil }
    guard let physical = try fkPhysicalSource(source, evaluator, ctx) else { return nil }
    var matches: [UInt32] = []
    let frame = CallFrame(args: args, ctx: ctx, eval: evaluator)
    try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
        guard let r = inner.row?.row else { return }
        if try evaluator.scalar(predicate, in: inner).asLogical() {
            matches.append(UInt32(r))
        }
    }
    let rowCount = try evaluator.runtimeCall { try evaluator.store.rowCount(physical.table) }
    return (table: physical.table, rows: RowSet(universe: rowCount + 1, sortedRows: matches))
}

/// Đường many→one ngắn nhất (BFS) từ `from` tới `to` qua quan hệ active. nil nếu không có. Rỗng nếu from == to.
func fkManyToOnePath(from: TableID, to: TableID, schema: ModelSchema) -> [RelationshipSchema]? {
    var queue: [(table: TableID, path: [RelationshipSchema])] = [(table: from, path: [])]
    var seen: Set<TableID> = [from]
    var head = 0
    while head < queue.count {
        let node = queue[head]
        head += 1
        if node.table == to { return node.path }
        for relationship in schema.relationships
        where relationship.isActive && relationship.manyColumn.table == node.table
            && !seen.contains(relationship.oneColumn.table) {
            seen.insert(relationship.oneColumn.table)
            queue.append((table: relationship.oneColumn.table, path: node.path + [relationship]))
        }
    }
    return nil
}

/// RELATED(cột) trong ngữ cảnh `ctx` (cần row context). Dùng chung cho RELATED và các hàm F-TABLE cần cột liên quan.
/// Thứ tự: cột trong chính một khung đang mở; rồi đi theo quan hệ many→one từ khung gần nhất.
func fkRelatedValue(_ column: ColumnID, _ evaluator: Evaluator, _ ctx: EvalContext) throws(DAXError) -> Value {
    guard ctx.row != nil else {
        throw DAXError(.runtime, "RELATED cần row context")
    }
    let store = evaluator.store
    let frames = evaluator.rowStack

    // 1. Cột thuộc chính một khung đang mở: đọc trực tiếp, như tham chiếu cột thường.
    for khung in frames.reversed() {
        switch khung {
        case .base(let table, let r) where table == column.table:
            let data = try evaluator.runtimeCall { try store.column(column) }
            return Value(stored: data.value(at: r))
        case .virtual(let tv, let i):
            if let index = tv.lineageIndex(of: column) {
                return tv.rows[i][index]
            }
            let tName = store.schema.table(column.table)?.name ?? ""
            let cName = store.schema.column(column)?.name ?? ""
            let q1 = "'\(tName)'[\(cName)]".lowercased()
            let q2 = "\(tName)[\(cName)]".lowercased()
            let bName = "[\(cName)]".lowercased()
            if let index = tv.columns.firstIndex(where: {
                let col = $0.lowercased()
                return col == q1 || col == q2 || col == bName
            }) {
                return tv.rows[i][index]
            }
        default:
            continue
        }
    }

    // 2. Đi theo quan hệ many→one từ khung row, khung gần nhất trước.
    for khung in frames.reversed() {
        switch khung {
        case .base(let table, let r):
            guard let path = fkManyToOnePath(from: table, to: column.table, schema: store.schema) else {
                continue
            }
            var row = r
            var blank = false
            for relationship in path {
                let index = try evaluator.runtimeCall { try store.relationshipIndex(relationship) }
                if row >= index.manyRowCount {
                    blank = true
                    break
                }
                let one = Int(index.fkToPK[row])
                if one >= index.oneRowCount {
                    blank = true
                    break
                }
                row = one
            }
            if blank { return .blank }
            let data = try evaluator.runtimeCall { try store.column(column) }
            return Value(stored: data.value(at: row))
        case .virtual(let tv, let i):
            for relationship in store.schema.relationships
            where relationship.isActive && relationship.oneColumn.table == column.table {
                guard let index = tv.lineageIndex(of: relationship.manyColumn) else { continue }
                let key = tv.rows[i][index]
                if case .blank = key { return .blank }
                let oneData = try evaluator.runtimeCall { try store.column(relationship.oneColumn) }
                let targetData = try evaluator.runtimeCall { try store.column(column) }
                for r in 0..<oneData.rowCount where Value(stored: oneData.value(at: r)) == key {
                    return Value(stored: targetData.value(at: r))
                }
                return .blank
            }
        }
    }
    let name = store.schema.table(column.table)?.name ?? "\(column.table)"
    throw DAXError(.runtime, "RELATED: không có quan hệ many→one từ bảng hiện tại tới \(name)")
}

/// Vật chất hoá đúng các dòng `ordered` (theo thứ tự cho trước, không trùng) của bảng vật lý. Chỉ các dòng này
/// được tính vào `materializedRowCount`. Dòng BLANK ảo (chỉ số = số dòng) được đọc thành BLANK.
func fkMaterializeOrdered(_ table: TableID, _ ordered: [Int],
                          _ evaluator: Evaluator) throws(DAXError) -> TableValue {
    let rowCount = try evaluator.runtimeCall { try evaluator.store.rowCount(table) }
    let ascending = ordered.sorted()
    let rowSet = RowSet(universe: rowCount + 1, sortedRows: ascending.map { UInt32($0) })
    let materialized = try evaluator.materialize(table, rowSet)
    var position: [Int: Int] = [:]
    for (k, r) in ascending.enumerated() {
        position[r] = k
    }
    var rows: [[Value]] = []
    rows.reserveCapacity(ordered.count)
    for r in ordered {
        guard let k = position[r], k < materialized.rows.count else {
            throw DAXError(.runtime, "vật chất hoá: dòng \(r) không có trong kết quả")
        }
        rows.append(materialized.rows[k])
    }
    return TableValue(columns: materialized.columns, rows: rows, lineage: materialized.lineage)
}

/// Tên cột dạng `Bảng[cột]` theo lược đồ, dùng cho cột của SUMMARIZE.
func fkQualifiedName(_ column: ColumnID, _ evaluator: Evaluator) -> String {
    let schema = evaluator.store.schema
    let table = schema.table(column.table)?.name ?? "\(column.table)"
    let name = schema.column(column)?.name ?? "\(column.index)"
    return "\(table)[\(name)]"
}

/// Cặp (tên, biểu thức) của ADDCOLUMNS/SUMMARIZE, bắt đầu từ đối số `from`. Tên phải là chuỗi.
func fkNamedPairs(_ frame: CallFrame, from: Int) throws(DAXError) -> [(name: String, expr: BoundExpr)] {
    var out: [(name: String, expr: BoundExpr)] = []
    var i = from
    while i < frame.args.count {
        guard i + 1 < frame.args.count, let expr = frame.args[i + 1] else {
            throw DAXError(.arity, "\(frame.args.count) đối số: cần cặp tên và biểu thức")
        }
        let name = try frame.scalar(i)
        guard case .string(let text) = name else {
            throw DAXError(.typeMismatch, "tên cột phải là chuỗi")
        }
        out.append((name: text, expr: expr))
        i += 2
    }
    return out
}

/// Số n của TOPN: làm tròn xuống, BLANK là 0, số âm là 0.
func fkTopCount(_ value: Value) throws(DAXError) -> Int {
    let d: Double
    switch value {
    case .blank: return 0
    case .integer(let x): return max(0, Int(clamping: x))
    case .currency(let c): d = Double(c) / 10_000
    case .double(let x): d = x
    default: throw DAXError(.typeMismatch, "n của TOPN phải là số")
    }
    guard d.isFinite else { throw DAXError(.runtime, "n của TOPN không hữu hạn") }
    return max(0, Int(min(max(d.rounded(.down), -1e15), 1e15)))
}

/// So sánh hai giá trị để sắp xếp: BLANK đứng trước; còn lại dùng toán tử `<` của DAX.
func fkLess(_ a: Value, _ b: Value) throws(DAXError) -> Bool {
    switch (a, b) {
    case (.blank, .blank): return false
    default:
        // BLANK so như phép so sánh DAX (BLANK là 0 với số): TOPN(1, {1, BLANK(), -1}, [Value], ASC) = -1 (quan sát O18b).
        if case .boolean(let v) = try Value.compare(.less, a, b) { return v }
        return false
    }
}

/// So sánh khoá sắp xếp: -1, 0, 1. Hai giá trị không thể so thứ tự (ví dụ 1 và 1.0 khác kiểu) coi là bằng nhau.
func fkCompareKeys(_ a: [Value], _ b: [Value], desc: Bool) throws(DAXError) -> Int {
    for k in 0..<min(a.count, b.count) {
        let lt = try fkLess(a[k], b[k])
        let gt = try fkLess(b[k], a[k])
        if !lt && !gt { continue }
        let aFirst = desc ? gt : lt
        return aFirst ? -1 : 1
    }
    return 0
}

func fkCompareMultiKeys(_ a: [Value], _ b: [Value], descs: [Bool]) throws(DAXError) -> Int {
    for k in 0..<min(a.count, b.count) {
        let lt = try fkLess(a[k], b[k])
        let gt = try fkLess(b[k], a[k])
        if !lt && !gt { continue }
        let desc = k < descs.count ? descs[k] : false
        let aFirst = desc ? gt : lt
        return aFirst ? -1 : 1
    }
    return 0
}

// MARK: - Họ hàm

public enum TableFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "FILTER", params: [.table("table"), .lazy("filter")], impl: .table(filterBody)),
        FunctionSpec(name: "VALUES", params: [.tableOrColumn("tableOrColumnName")], impl: .table(valuesBody)),
        FunctionSpec(name: "DISTINCT", params: [.tableOrColumn("tableOrColumnName")], impl: .table(distinctBody)),
        FunctionSpec(name: "SUMMARIZE",
                     params: [.table("table"), .tableOrColumn("groupBy", optional: true, repeats: true),
                              .scalar("name", optional: true, repeats: true),
                              .lazy("expression", optional: true, repeats: true)],
                     impl: .table(summarizeBody)),
        FunctionSpec(name: "ADDCOLUMNS",
                     params: [.table("table"), .scalar("name", repeats: true), .lazy("expression", repeats: true)],
                     impl: .table(addColumnsBody)),
        FunctionSpec(name: "CROSSJOIN", params: [.table("table1"), .table("table2", repeats: true)],
                     impl: .table(crossJoinBody)),
        FunctionSpec(name: "TOPN",
                     params: [.scalar("n_value"), .table("table"),
                              .lazy("orderBy_expression", optional: true, repeats: true),
                              .keyword("order", ["ASC", "DESC"], optional: true)],
                     impl: .table(topNBody)),
        FunctionSpec(name: "RELATED", params: [.column("columnName")], impl: .scalar(relatedBody)),
        FunctionSpec(name: "RELATEDTABLE", params: [.table("tableName")], impl: .table(relatedTableBody)),
    ]

    // MARK: FILTER

    private static let filterBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard let sourceExpr = fkArg(frame, 0), let predicate = fkArg(frame, 1) else {
            throw DAXError(.arity, "FILTER cần bảng và vị ngữ")
        }
        let evaluator = try fkEvaluator(frame)
        if let physical = try fkFilterMatches(args: frame.args, evaluator: evaluator, ctx: frame.ctx) {
            return try evaluator.materialize(physical.table, physical.rows)
        }
        // Nguồn ảo: vật chất hoá nguồn (đã là bảng ảo), rồi giữ các dòng có vị ngữ đúng.
        let source = try frame.table(0)
        var kept: [Int] = []
        try evaluator.iterate(source, in: frame.ctx) { (inner: EvalContext) throws(DAXError) in
            guard let i = inner.row?.row else { return }
            if try evaluator.scalar(predicate, in: inner).asLogical() {
                kept.append(i)
            }
        }
        return TableValue(columns: source.columns, rows: kept.map { source.rows[$0] }, lineage: source.lineage)
    }

    // MARK: VALUES

    private static let valuesBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard let expr = fkArg(frame, 0) else {
            throw DAXError(.arity, "VALUES cần một đối số")
        }
        if case .column(let column) = expr {
            let evaluator = try fkEvaluator(frame)
            let store = evaluator.store
            let values = try frame.ctx.filter.visibleValues(of: column, in: store)
            let name = store.schema.column(column)?.name ?? ""
            return TableValue.values(of: column, name: name, values: values)
        }
        return try frame.table(0).distinct()
    }

    // MARK: DISTINCT

    private static let distinctBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard let expr = fkArg(frame, 0) else {
            throw DAXError(.arity, "DISTINCT cần một đối số")
        }
        let evaluator = try fkEvaluator(frame)
        if case .column(let column) = expr {
            // Giống VALUES(cột).
            let values = try frame.ctx.filter.visibleValues(of: column, in: evaluator.store)
            let name = evaluator.store.schema.column(column)?.name ?? ""
            return TableValue.values(of: column, name: name, values: values)
        }
        guard let physical = try fkPhysicalSource(expr, evaluator, frame.ctx) else {
            return try frame.table(0).distinct()
        }
        // Nguồn vật lý: đọc giá trị từng dòng từ cột, chỉ vật chất hoá dòng đầu tiên của mỗi nhóm trùng.
        let columns = evaluator.store.schema.table(physical.table)?.columns.map(\.id) ?? []
        var datas: [ColumnData] = []
        for column in columns {
            datas.append(try evaluator.columnData(column))
        }
        var seen = Set<[Value]>()
        var firsts: [Int] = []
        physical.rows.forEach { r in
            let key = datas.map { Value(stored: $0.value(at: r)) }
            if seen.insert(key).inserted {
                firsts.append(r)
            }
        }
        return try fkMaterializeOrdered(physical.table, firsts, evaluator)
    }

    // MARK: SUMMARIZE

    private static let summarizeBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard fkArg(frame, 0) != nil else {
            throw DAXError(.arity, "SUMMARIZE cần một bảng")
        }
        let evaluator = try fkEvaluator(frame)
        var groups: [(expr: BoundExpr, name: String, lineage: ColumnID?)] = []
        var extensions: [(name: String, expr: BoundExpr)] = []
        var i = 1
        while i < frame.args.count {
            guard let arg = frame.args[i] else {
                throw DAXError(.arity, "SUMMARIZE: đối số \(i + 1) bị bỏ trống")
            }
            switch arg {
            case .column(let column):
                groups.append((expr: arg, name: fkQualifiedName(column, evaluator), lineage: column))
                i += 1
            case .virtualColumn(let name):
                groups.append((expr: arg, name: name, lineage: nil))
                i += 1
            case .literal(.string(let name)):
                guard i + 1 < frame.args.count, let expr = frame.args[i + 1] else {
                    throw DAXError(.arity, "SUMMARIZE: tên \(name) thiếu biểu thức")
                }
                extensions.append((name: name, expr: expr))
                i += 2
            default:
                throw DAXError(.typeMismatch, "SUMMARIZE: nhóm phải là cột của bảng hoặc bảng liên quan")
            }
        }

        // Bộ giá trị nhóm theo thứ tự xuất hiện, bỏ trùng. Nguồn được lặp, không materialize.
        var keys: [[Value]] = []
        var seen = Set<[Value]>()
        try frame.iterateArgument(0) { (inner: EvalContext) throws(DAXError) in
            var key: [Value] = []
            key.reserveCapacity(groups.count)
            for g in groups {
                switch g.expr {
                case .column(let column):
                    key.append(try fkRelatedValue(column, evaluator, inner))
                default:
                    key.append(try evaluator.scalar(g.expr, in: inner))
                }
            }
            if seen.insert(key).inserted {
                keys.append(key)
            }
        }

        var names = groups.map(\.name)
        var lineage: [ColumnID?] = groups.map(\.lineage)
        var rows: [[Value]] = []
        rows.reserveCapacity(keys.count)
        for key in keys {
            var values = key
            if !extensions.isEmpty {
                var filter = frame.ctx.filter
                if frame.ctx.row != nil {
                    filter = try evaluator.transitioned(filter)
                }
                for (k, g) in groups.enumerated() {
                    if let col = g.lineage {
                        filter = filter.applying(FilterItem(column: col, values: [key[k]]), keep: false)
                    }
                }
                for extension_ in extensions {
                    values.append(try evaluator.scalar(extension_.expr, in: EvalContext(filter: filter, row: nil)))
                }
            }
            rows.append(values)
        }
        for extension_ in extensions {
            names.append(extension_.name)
            lineage.append(nil)
        }
        return TableValue(columns: names, rows: rows, lineage: lineage)
    }

    // MARK: ADDCOLUMNS

    private static let addColumnsBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard let sourceExpr = fkArg(frame, 0) else {
            throw DAXError(.arity, "ADDCOLUMNS cần một bảng")
        }
        let evaluator = try fkEvaluator(frame)
        let pairs = try fkNamedPairs(frame, from: 1)
        var perRow: [[Value]] = []
        let visit: (EvalContext) throws(DAXError) -> Void = { (inner: EvalContext) throws(DAXError) in
            var values: [Value] = []
            values.reserveCapacity(pairs.count)
            for pair in pairs {
                values.append(try evaluator.scalar(pair.expr, in: inner))
            }
            perRow.append(values)
        }
        let base: TableValue
        if let physical = try fkPhysicalSource(sourceExpr, evaluator, frame.ctx) {
            // Lặp dòng vật lý qua RowSet; chỉ dòng đầu ra được vật chất hoá.
            try frame.iterateArgument(0, visit)
            base = try evaluator.materialize(physical.table, physical.rows)
        } else {
            let source = try frame.table(0)
            try frame.iterate(source, visit)
            base = source
        }
        guard perRow.count == base.rows.count else {
            throw DAXError(.runtime, "ADDCOLUMNS: số dòng lặp và số dòng nguồn không khớp")
        }
        var rows: [[Value]] = []
        rows.reserveCapacity(base.rows.count)
        for (i, row) in base.rows.enumerated() {
            rows.append(row + perRow[i])
        }
        return TableValue(columns: base.columns + pairs.map(\.name), rows: rows,
                          lineage: base.lineage + pairs.map { _ in nil as ColumnID? })
    }

    // MARK: CROSSJOIN

    private static let crossJoinBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard frame.args.count >= 2 else {
            throw DAXError(.arity, "CROSSJOIN cần ít nhất hai bảng")
        }
        var result = try frame.table(0)
        for i in 1..<frame.args.count {
            result = result.crossJoined(with: try frame.table(i))
        }
        return result
    }

    // MARK: TOPN

    private static let topNBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard let sourceExpr = fkArg(frame, 1) else {
            throw DAXError(.arity, "TOPN cần n và một bảng")
        }
        let evaluator = try fkEvaluator(frame)
        let n = try fkTopCount(try frame.scalar(0))
        var orderSpecs: [(expr: BoundExpr, desc: Bool)] = []
        var i = 2
        while i < frame.args.count {
            guard let arg = frame.args[i] else {
                i += 1
                continue
            }
            var isDir = false
            var dirDesc = false
            switch arg {
            case .keyword(let word):
                isDir = true
                dirDesc = (word == "DESC")
            case .literal(.integer(let v)):
                isDir = true
                dirDesc = (v == 0) // trong DAX: 0 = DESC, 1 = ASC
            case .literal(.boolean(let b)):
                isDir = true
                dirDesc = !b
            default:
                break
            }

            if isDir && !orderSpecs.isEmpty {
                orderSpecs[orderSpecs.count - 1].desc = dirDesc
            } else {
                orderSpecs.append((expr: arg, desc: false))
            }
            i += 1
        }
        guard !orderSpecs.isEmpty else {
            throw DAXError(.arity, "TOPN cần ít nhất một biểu thức sắp xếp")
        }

        // Khoá sắp xếp của từng dòng nguồn; `index` là dòng vật lý, hoặc chỉ số dòng của bảng ảo.
        var entries: [(index: Int, keys: [Value])] = []
        let visit: (EvalContext) throws(DAXError) -> Void = { (inner: EvalContext) throws(DAXError) in
            guard let index = inner.row?.row else { return }
            var keys: [Value] = []
            keys.reserveCapacity(orderSpecs.count)
            for spec in orderSpecs {
                keys.append(try evaluator.scalar(spec.expr, in: inner))
            }
            entries.append((index: index, keys: keys))
        }
        let physicalSource: (table: TableID, rows: RowSet)?
        let virtualSource: TableValue?
        if let physical = try fkPhysicalSource(sourceExpr, evaluator, frame.ctx) {
            physicalSource = physical
            virtualSource = nil
            try frame.iterateArgument(1, visit)
        } else {
            let source = try frame.table(1)
            physicalSource = nil
            virtualSource = source
            try frame.iterate(source, visit)
        }

        // Sắp xếp ổn định theo khoá, rồi theo vị trí gốc để kết quả xác định.
        var failure: DAXError?
        let descs = orderSpecs.map(\.desc)
        var order = Array(entries.indices)
        order.sort { (a: Int, b: Int) -> Bool in
            do throws(DAXError) {
                let c = try fkCompareMultiKeys(entries[a].keys, entries[b].keys, descs: descs)
                if c != 0 { return c < 0 }
                return a < b
            } catch {
                failure = failure ?? error
                return a < b
            }
        }
        if let failure { throw failure }

        // Lấy n dòng đầu; các dòng sau đó có khoá bằng khoá dòng thứ n cũng được giữ.
        var chosen: [Int] = []
        if n > 0 && !order.isEmpty {
            if order.count <= n {
                chosen = order
            } else {
                let threshold = entries[order[n - 1]].keys
                for (position, entry) in order.enumerated() {
                    if position < n {
                        chosen.append(entry)
                    } else if try fkCompareMultiKeys(entries[entry].keys, threshold, descs: descs) == 0 {
                        chosen.append(entry)
                    } else {
                        break
                    }
                }
            }
        }

        if let physical = physicalSource {
            return try fkMaterializeOrdered(physical.table, chosen.map { entries[$0].index }, evaluator)
        }
        guard let source = virtualSource else {
            throw DAXError(.runtime, "TOPN: thiếu nguồn")
        }
        return TableValue(columns: source.columns, rows: chosen.map { source.rows[entries[$0].index] },
                          lineage: source.lineage)
    }

    // MARK: RELATED

    private static let relatedBody: FunctionSpec.ScalarBody = { (frame: CallFrame) throws(DAXError) -> Value in
        let column = try frame.column(0)
        let evaluator = try fkEvaluator(frame)
        guard frame.ctx.row != nil else {
            throw DAXError(.runtime, "RELATED cần row context")
        }
        return try fkRelatedValue(column, evaluator, frame.ctx)
    }

    // MARK: RELATEDTABLE

    private static let relatedTableBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        guard let expr = fkArg(frame, 0) else {
            throw DAXError(.arity, "RELATEDTABLE cần một bảng")
        }
        let evaluator = try fkEvaluator(frame)
        var ctx = frame.ctx
        // Context transition từ mọi khung row hiện tại (như CALCULATE), rồi lấy bảng đích trong bộ lọc đó.
        if ctx.row != nil {
            ctx.filter = try evaluator.transitioned(ctx.filter)
        }
        return try evaluator.table(expr, in: ctx)
    }
}
