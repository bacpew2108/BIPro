// SUMMARIZECOLUMNS (QRY, đợt 2), architecture.md §6 và §8.2 (bước 1–5). Không đăng ký trong registry hàm:
// QueryExecutor nhận dạng lời gọi ở đầu EVALUATE, bind đối số bằng hàm `plan` ở đây, rồi gọi `evaluate`.
//
// Quy tắc đã làm:
// - Đối số: cột nhóm (`T[c]`), rồi bảng bộ lọc (biểu thức bảng), rồi cặp ("tên", biểu thức).
//   IGNORE(biểu thức) đánh dấu biểu thức không tham gia kiểm tra BLANK của dòng.
// - Bảng bộ lọc được đánh giá trong ngữ cảnh gốc. Nếu bảng có cột khoá (isKey) của một bảng gốc thì lọc theo
//   tập dòng của bảng gốc khớp theo khoá; nếu không thì lọc từng cột lineage theo tập giá trị xuất hiện
//   (ghi đè; lần thứ hai trên cùng bảng/cột thì giao).
// - Đẩy shadow sau khi áp bộ lọc bảng, rồi mọi ô đều đi từ ngữ cảnh shadow đó (ALLSELECTED thấy bộ lọc trước nhóm).
// - Tổ hợp nhóm: các cột cùng bảng auto-exist (tổ hợp phân biệt của dòng thấy được của bảng đó);
//   khác bảng thì crossjoin.
// - Ô của mỗi tổ hợp: lọc từng cột nhóm theo giá trị của tổ hợp (ghi đè), đánh giá từng biểu thức.
// - Bỏ dòng khi mọi biểu thức không IGNORE đều BLANK. Không có biểu thức thì chỉ trả tổ hợp nhóm.
//
// [SUY ĐOÁN] Bảng bộ lọc không có cột khoá thì chỉ chiếu thành tập giá trị từng cột, nên tương quan giữa các cột bị
// mất (quá rộng). Có cột khoá thì khớp đúng theo dòng gốc, và các trường hợp còn lại báo lỗi của FC khi gặp cột dense.
// [SUY ĐOÁN] Cột nhóm khác bảng: crossjoin, không lọc theo quan hệ (theo §8.2 bước 3).
// [SUY ĐOÁN] Dòng có mọi biểu thức IGNORE thì được giữ (không có gì để kiểm tra BLANK).
// [SUY ĐOÁN] Thứ tự dòng: theo giá trị cột nhóm (so sánh không phân biệt hoa thường), chưa theo collation của model.

import ColumnStore

public enum SummarizeColumns {
    /// Một cặp ("tên", biểu thức) đã bind.
    struct Measure: Sendable {
        let name: String
        let expr: BoundExpr
        /// Biểu thức bọc trong IGNORE: không tham gia kiểm tra dòng BLANK.
        let ignore: Bool
    }

    /// Kế hoạch đã bind của một lời gọi SUMMARIZECOLUMNS.
    struct Plan: Sendable {
        let groupColumns: [ColumnID]
        let filterTables: [BoundExpr]
        /// Cùng độ dài với `filterTables`: `true` khi bảng bộ lọc được bọc trong KEEPFILTERS (giao, không ghi đè).
        let filterKeep: [Bool]
        let measures: [Measure]

        /// Áp một phép biến đổi lên mọi biểu thức con (dùng để thay VAR/TABLE trước khi đánh giá).
        func mapExpressions(_ transform: (BoundExpr) -> BoundExpr) -> Plan {
            Plan(groupColumns: groupColumns,
                 filterTables: filterTables.map(transform),
                 filterKeep: filterKeep,
                 measures: measures.map { Measure(name: $0.name, expr: transform($0.expr), ignore: $0.ignore) })
        }
    }

    // MARK: - Bind

    /// Bind các đối số của SUMMARIZECOLUMNS. Đối số bỏ trống là lỗi.
    static func plan(args: [Expr?], range: SourceRange, scope: inout BindScope) throws(DAXError) -> Plan {
        var groups: [ColumnID] = []
        var filters: [BoundExpr] = []
        var keeps: [Bool] = []
        var measures: [Measure] = []
        var i = 0

        // Phần cột nhóm và bảng bộ lọc: đi tới khi gặp chuỗi (tên của cặp đầu tiên).
        while i < args.count, !isNameArgument(args[i]) {
            guard let arg = args[i] else {
                throw DAXError(.arity, "SUMMARIZECOLUMNS: đối số \(i + 1) bị bỏ trống", range: range)
            }
            if case .columnRef = arg {
                let bound = try scope.bind(arg)
                guard case .column(let column) = bound else {
                    throw DAXError(.expectedColumnRef, "SUMMARIZECOLUMNS: đối số \(i + 1) phải là cột", range: arg.range)
                }
                groups.append(column)
            } else if case .call(let name, let inner, _) = arg, name.uppercased() == "KEEPFILTERS",
                      inner.count == 1, let table = inner[0] {
                // KEEPFILTERS(bảng bộ lọc): bảng được giao với ngữ cảnh hiện có thay vì ghi đè (dạng bộ lọc cấp
                // report mà Power BI sinh ra; golden G3 dùng dạng này).
                filters.append(try scope.bind(table))
                keeps.append(true)
            } else {
                filters.append(try scope.bind(arg))
                keeps.append(false)
            }
            i += 1
        }

        // Phần cặp ("tên", biểu thức).
        while i < args.count {
            guard let nameArg = args[i], case .string(let name, _) = nameArg else {
                throw DAXError(.syntax, "SUMMARIZECOLUMNS: đối số \(i + 1) phải là tên (chuỗi)",
                               range: args[i]?.range ?? range)
            }
            guard i + 1 < args.count, let exprArg = args[i + 1] else {
                throw DAXError(.arity, "SUMMARIZECOLUMNS: thiếu biểu thức cho \"\(name)\"", range: nameArg.range)
            }
            if case .call(let fname, let inner, _) = exprArg, fname.uppercased() == "IGNORE",
               inner.count == 1, let innerArg = inner[0] {
                measures.append(Measure(name: name, expr: try scope.bind(innerArg), ignore: true))
            } else {
                measures.append(Measure(name: name, expr: try scope.bind(exprArg), ignore: false))
            }
            i += 2
        }
        return Plan(groupColumns: groups, filterTables: filters, filterKeep: keeps, measures: measures)
    }

    private static func isNameArgument(_ arg: Expr?) -> Bool {
        guard let arg else { return false }
        if case .string = arg { return true }
        return false
    }

    // MARK: - Đánh giá

    /// Đánh giá kế hoạch, trả các dòng giá trị (cột nhóm trước, rồi biểu thức theo thứ tự).
    static func evaluate(_ plan: Plan, base: EvalContext, store: ColumnStore,
                         evaluator: any Evaluating) throws(DAXError) -> [[Value]] {
        try QueryExecutor.checkCancelled()
        let filtered = try applyFilterTables(plan.filterTables, keep: plan.filterKeep, base: base.filter,
                                             store: store, evaluator: evaluator)
        // Shadow: mọi ô đi từ ngữ cảnh này, nên ALLSELECTED trong biểu thức thấy bộ lọc trước khi nhóm.
        let cellBase = filtered.pushingShadow()
        let combos = try groupCombinations(plan.groupColumns, filter: filtered, store: store)

        var out: [[Value]] = []
        for combo in combos {
            try QueryExecutor.checkCancelled()
            var cell = cellBase
            for (k, column) in plan.groupColumns.enumerated() {
                cell = cell.applying(FilterItem(column: column, values: [combo[k]]), keep: false)
            }
            var values: [Value] = []
            values.reserveCapacity(plan.measures.count)
            for measure in plan.measures {
                values.append(try evaluator.scalar(measure.expr, in: EvalContext(filter: cell, row: nil)))
            }
            if keepRow(values, plan.measures) {
                out.append(combo + values)
            }
        }
        // Bật lại shadow: cellBase.poppingShadow() trả đúng `filtered` (kiểm trong test).
        return out
    }

    /// Áp các bảng bộ lọc lên ngữ cảnh gốc. Với mỗi bảng gốc của lineage:
    /// - nếu bảng bộ lọc có cột khoá (isKey) của bảng đó: lọc theo tập dòng của bảng, khớp theo khoá;
    /// - nếu không: lọc từng cột lineage theo tập giá trị (chỉ được với cột mã hoá; cột dense báo lỗi của FC).
    /// `keep[i]` = true: bảng thứ i được giao với bộ lọc hiện có (KEEPFILTERS), không ghi đè.
    private static func applyFilterTables(_ tables: [BoundExpr], keep: [Bool], base: FilterContext, store: ColumnStore,
                                          evaluator: any Evaluating) throws(DAXError) -> FilterContext {
        var ctx = base
        var touchedTables = Set<TableID>()
        var touchedColumns = Set<ColumnID>()
        for (position, expr) in tables.enumerated() {
            let keepThis = position < keep.count && keep[position]
            let table = try evaluator.table(expr, in: EvalContext(filter: base, row: nil))
            var order: [TableID] = []
            var byTable: [TableID: [Int]] = [:]
            for (i, lineage) in table.lineage.enumerated() {
                guard let column = lineage else { continue }
                if byTable[column.table] == nil {
                    order.append(column.table)
                    byTable[column.table] = []
                }
                byTable[column.table, default: []].append(i)
            }
            guard !order.isEmpty else {
                throw DAXError(.runtime, "bảng bộ lọc của SUMMARIZECOLUMNS phải có ít nhất một cột gốc (chưa hỗ trợ bảng không có lineage)")
            }
            for table0 in order {
                let indices = byTable[table0] ?? []
                let keyIndex = indices.first { i in
                    guard let column = table.lineage[i] else { return false }
                    return store.schema.column(column)?.isKey == true
                }
                if let keyIndex, let keyColumn = table.lineage[keyIndex] {
                    var keyValues = Set<Value>()
                    for row in table.rows {
                        keyValues.insert(row[keyIndex])
                    }
                    let rowCount = try QueryExecutor.guarded { try store.rowCount(table0) }
                    let keyData = try QueryExecutor.guarded { try store.column(keyColumn) }
                    var sorted: [UInt32] = []
                    for r in 0..<rowCount where keyValues.contains(Value(stored: keyData.value(at: r))) {
                        sorted.append(UInt32(r))
                    }
                    let rows = RowSet(universe: rowCount + 1, sortedRows: sorted)
                    ctx = ctx.applying(rows: RowsFilter(table: table0, rows: rows),
                                       keep: keepThis || touchedTables.contains(table0))
                    touchedTables.insert(table0)
                } else {
                    for i in indices {
                        guard let column = table.lineage[i] else { continue }
                        var seen = Set<Value>()
                        var values: [Value] = []
                        for row in table.rows where seen.insert(row[i]).inserted {
                            values.append(row[i])
                        }
                        ctx = ctx.applying(FilterItem(column: column, values: values),
                                           keep: keepThis || touchedColumns.contains(column))
                        touchedColumns.insert(column)
                    }
                }
            }
        }
        return ctx
    }

    /// Tổ hợp giá trị nhóm. Mỗi bảng cho tổ hợp phân biệt của dòng thấy được (auto-exist); các bảng được crossjoin.
    static func groupCombinations(_ groups: [ColumnID], filter: FilterContext,
                                  store: ColumnStore) throws(DAXError) -> [[Value]] {
        guard !groups.isEmpty else { return [[]] }

        var tables: [TableID] = []
        var positions: [TableID: [Int]] = [:]
        for (k, column) in groups.enumerated() {
            if positions[column.table] == nil {
                tables.append(column.table)
                positions[column.table] = []
            }
            positions[column.table, default: []].append(k)
        }

        var perTable: [[[Value]]] = []
        for table in tables {
            let slots = positions[table] ?? []
            let columns = slots.map { groups[$0] }
            let rowSet = try filter.visibleRows(in: store, table: table, overrides: [])
            let rowCount = try QueryExecutor.guarded { try store.rowCount(table) }
            var datas: [ColumnData] = []
            for column in columns {
                datas.append(try QueryExecutor.guarded { try store.column(column) })
            }

            var seen = Set<[Value]>()
            var tuples: [[Value]] = []
            for (n, raw) in rowSet.rows.enumerated() {
                if n & 4095 == 0 { try QueryExecutor.checkCancelled() }
                let row = Int(raw)
                var tuple: [Value] = []
                tuple.reserveCapacity(datas.count)
                for data in datas {
                    // Blank row ảo nằm ở chỉ số rowCount: mọi cột là BLANK.
                    tuple.append(row >= rowCount ? .blank : Value(stored: data.value(at: row)))
                }
                if seen.insert(tuple).inserted {
                    tuples.append(tuple)
                }
            }
            tuples.sort { QueryExecutor.compareTuples($0, $1) < 0 }
            perTable.append(tuples)
        }

        var combos: [[Value]] = [Array(repeating: .blank, count: groups.count)]
        for (ti, table) in tables.enumerated() {
            try QueryExecutor.checkCancelled()
            let slots = positions[table] ?? []
            var next: [[Value]] = []
            next.reserveCapacity(combos.count * perTable[ti].count)
            for base in combos {
                for tuple in perTable[ti] {
                    var combo = base
                    for (j, slot) in slots.enumerated() {
                        combo[slot] = tuple[j]
                    }
                    next.append(combo)
                }
            }
            combos = next
        }
        return combos
    }

    /// Giữ dòng nếu có ít nhất một biểu thức không IGNORE khác BLANK; không có biểu thức nào thì giữ.
    static func keepRow(_ values: [Value], _ measures: [Measure]) -> Bool {
        var checked = false
        for (value, measure) in zip(values, measures) where !measure.ignore {
            checked = true
            if !value.isBlank { return true }
        }
        return !checked
    }
}
