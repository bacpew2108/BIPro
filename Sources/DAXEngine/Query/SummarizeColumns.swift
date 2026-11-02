// SUMMARIZECOLUMNS (QRY, đợt 2), architecture.md §6 và §8.2 (bước 1–5).
// Mở rộng Phase C: ROLLUPADDISSUBTOTAL, ROLLUPGROUP, NONVISUAL, và biểu thức bảng.
import ColumnStore

public enum SummarizeColumns {
    /// Một cặp ("tên", biểu thức) đã bind.
    public struct Measure: Sendable {
        public let name: String
        public let expr: BoundExpr
        /// Biểu thức bọc trong IGNORE: không tham gia kiểm tra dòng BLANK.
        public let ignore: Bool

        public init(name: String, expr: BoundExpr, ignore: Bool) {
            self.name = name
            self.expr = expr
            self.ignore = ignore
        }
    }

    /// Một cấp trong ROLLUPADDISSUBTOTAL.
    public struct RollupLevel: Sendable {
        public let columns: [ColumnID]
        public let flagName: String
        public let filter: BoundExpr?

        public init(columns: [ColumnID], flagName: String, filter: BoundExpr? = nil) {
            self.columns = columns
            self.flagName = flagName
            self.filter = filter
        }
    }

    /// Một mệnh đề nhóm trong SUMMARIZECOLUMNS: cột trần hoặc một ROLLUPADDISSUBTOTAL.
    public enum GroupClause: Sendable {
        case plain(ColumnID)
        case rollup([RollupLevel])
    }

    /// Kế hoạch đã bind của một lời gọi SUMMARIZECOLUMNS.
    public struct Plan: Sendable {
        public let clauses: [GroupClause]
        public let filterTables: [BoundExpr]
        /// Cùng độ dài với `filterTables`: `true` khi bảng bộ lọc được bọc trong KEEPFILTERS (giao, không ghi đè).
        public let filterKeep: [Bool]
        public let measures: [Measure]

        public var groupColumns: [ColumnID] {
            var cols: [ColumnID] = []
            for clause in clauses {
                switch clause {
                case .plain(let col):
                    cols.append(col)
                case .rollup(let levels):
                    for lvl in levels {
                        cols.append(contentsOf: lvl.columns)
                    }
                }
            }
            return cols
        }

        public init(clauses: [GroupClause], filterTables: [BoundExpr], filterKeep: [Bool], measures: [Measure]) {
            self.clauses = clauses
            self.filterTables = filterTables
            self.filterKeep = filterKeep
            self.measures = measures
        }

        public init(groupColumns: [ColumnID], filterTables: [BoundExpr], filterKeep: [Bool], measures: [Measure]) {
            self.clauses = groupColumns.map { .plain($0) }
            self.filterTables = filterTables
            self.filterKeep = filterKeep
            self.measures = measures
        }

        /// Áp một phép biến đổi lên mọi biểu thức con (dùng để thay VAR/TABLE trước khi đánh giá).
        public func mapExpressions(_ transform: (BoundExpr) -> BoundExpr) -> Plan {
            let mappedClauses = clauses.map { clause -> GroupClause in
                switch clause {
                case .plain: return clause
                case .rollup(let levels):
                    return .rollup(levels.map { lvl in
                        RollupLevel(columns: lvl.columns, flagName: lvl.flagName, filter: lvl.filter.map(transform))
                    })
                }
            }
            return Plan(clauses: mappedClauses,
                        filterTables: filterTables.map(transform),
                        filterKeep: filterKeep,
                        measures: measures.map { Measure(name: $0.name, expr: transform($0.expr), ignore: $0.ignore) })
        }

        public func resultHeaders(schema: ModelSchema) -> [String] {
            var headers: [String] = []
            for clause in clauses {
                switch clause {
                case .plain(let col):
                    headers.append(QueryExecutor.header(for: col, schema: schema))
                case .rollup(let levels):
                    for lvl in levels {
                        for col in lvl.columns {
                            headers.append(QueryExecutor.header(for: col, schema: schema))
                        }
                        headers.append("[\(lvl.flagName)]")
                    }
                }
            }
            for measure in measures {
                headers.append("[\(measure.name)]")
            }
            return headers
        }

        public func resultLineages() -> [ColumnID?] {
            var lineages: [ColumnID?] = []
            for clause in clauses {
                switch clause {
                case .plain(let col):
                    lineages.append(col)
                case .rollup(let levels):
                    for lvl in levels {
                        for col in lvl.columns {
                            lineages.append(col)
                        }
                        lineages.append(nil)
                    }
                }
            }
            for _ in measures {
                lineages.append(nil)
            }
            return lineages
        }
    }

    // MARK: - Bind

    /// Bind các đối số của SUMMARIZECOLUMNS. Đối số bỏ trống là lỗi.
    static func plan(args: [Expr?], range: SourceRange, scope: inout BindScope) throws(DAXError) -> Plan {
        var clauses: [GroupClause] = []
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
                clauses.append(.plain(column))
            } else if case .call(let name, let inner, _) = arg, name.uppercased() == "ROLLUPADDISSUBTOTAL" {
                let levels = try planRollupLevels(inner, range: arg.range, scope: &scope)
                clauses.append(.rollup(levels))
            } else if case .call(let name, let inner, _) = arg, name.uppercased() == "KEEPFILTERS",
                      inner.count == 1, let table = inner[0] {
                // KEEPFILTERS(bảng bộ lọc): bảng được giao với ngữ cảnh hiện có thay vì ghi đè
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
        return Plan(clauses: clauses, filterTables: filters, filterKeep: keeps, measures: measures)
    }

    private static func planRollupLevels(_ args: [Expr?], range: SourceRange,
                                         scope: inout BindScope) throws(DAXError) -> [RollupLevel] {
        var levels: [RollupLevel] = []
        var i = 0
        while i < args.count {
            guard let arg = args[i] else {
                throw DAXError(.arity, "ROLLUPADDISSUBTOTAL: đối số \(i + 1) bị bỏ trống", range: range)
            }
            var cols: [ColumnID] = []
            if case .columnRef = arg {
                let bound = try scope.bind(arg)
                guard case .column(let col) = bound else {
                    throw DAXError(.expectedColumnRef, "ROLLUPADDISSUBTOTAL: đối số \(i + 1) phải là cột", range: arg.range)
                }
                cols = [col]
                i += 1
            } else if case .call(let rname, let rargs, _) = arg, rname.uppercased() == "ROLLUPGROUP" {
                for rarg in rargs {
                    guard let rarg else {
                        throw DAXError(.arity, "ROLLUPGROUP: đối số bị bỏ trống", range: arg.range)
                    }
                    let bound = try scope.bind(rarg)
                    guard case .column(let col) = bound else {
                        throw DAXError(.expectedColumnRef, "ROLLUPGROUP: đối số phải là cột", range: rarg.range)
                    }
                    cols.append(col)
                }
                i += 1
            } else {
                throw DAXError(.syntax, "ROLLUPADDISSUBTOTAL: đối số \(i + 1) phải là cột hoặc ROLLUPGROUP", range: arg.range)
            }

            guard i < args.count, let nameArg = args[i], case .string(let flagName, _) = nameArg else {
                throw DAXError(.syntax, "ROLLUPADDISSUBTOTAL: thiếu tên cờ cho cấp tổng", range: args[max(0, i - 1)]?.range ?? range)
            }
            i += 1

            // GroupLevelFilter tuỳ chọn: ví dụ NONVISUAL(bảng) hoặc bảng lọc
            var filterExpr: BoundExpr? = nil
            if i < args.count, let next = args[i] {
                if case .columnRef = next {
                    // Tiếp tục cấp kế tiếp
                } else if case .call(let nextName, _, _) = next, nextName.uppercased() == "ROLLUPGROUP" {
                    // Tiếp tục cấp kế tiếp
                } else if case .string = next {
                    // Không phải, là tên của cấp sau
                } else {
                    // Là bộ lọc của cấp này
                    if case .call(let nvName, let nvArgs, _) = next, nvName.uppercased() == "NONVISUAL",
                       nvArgs.count == 1, let innerTable = nvArgs[0] {
                        filterExpr = try scope.bind(innerTable)
                    } else {
                        filterExpr = try scope.bind(next)
                    }
                    i += 1
                }
            }
            levels.append(RollupLevel(columns: cols, flagName: flagName, filter: filterExpr))
        }
        return levels
    }

    private static func isNameArgument(_ arg: Expr?) -> Bool {
        guard let arg else { return false }
        if case .string = arg { return true }
        return false
    }

    // MARK: - Đánh giá

    /// Đánh giá kế hoạch và bọc thành TableValue đầy đủ header và lineage.
    public static func evaluateTable(_ plan: Plan, in ctx: EvalContext,
                                     evaluator: any Evaluating, store: ColumnStore) throws(DAXError) -> TableValue {
        let rows = try evaluate(plan, base: ctx, store: store, evaluator: evaluator)
        return TableValue(columns: plan.resultHeaders(schema: store.schema),
                          rows: rows,
                          lineage: plan.resultLineages())
    }

    /// Đánh giá kế hoạch, trả các dòng giá trị (cột nhóm trước, rồi biểu thức theo thứ tự).
    public static func evaluate(_ plan: Plan, base: EvalContext, store: ColumnStore,
                                evaluator: any Evaluating) throws(DAXError) -> [[Value]] {
        try QueryExecutor.checkCancelled()
        let filtered = try applyFilterTables(plan.filterTables, keep: plan.filterKeep, base: base.filter,
                                             store: store, evaluator: evaluator)
        // Shadow: mọi ô đi từ ngữ cảnh này, nên ALLSELECTED trong biểu thức thấy bộ lọc trước khi nhóm.
        let cellBase = filtered.pushingShadow()

        let hasRollup = plan.clauses.contains {
            if case .rollup = $0 { return true }
            return false
        }
        if !hasRollup {
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
            return out
        }

        struct ClauseCombos {
            let tuples: [[Value]]
            let filters: [[FilterItem]]
        }

        var clauseResults: [ClauseCombos] = []
        for clause in plan.clauses {
            switch clause {
            case .plain(let column):
                let vals = try groupCombinations([column], filter: filtered, store: store)
                var tuples: [[Value]] = []
                var flts: [[FilterItem]] = []
                for v in vals {
                    tuples.append(v)
                    flts.append([FilterItem(column: column, values: [v[0]])])
                }
                clauseResults.append(ClauseCombos(tuples: tuples, filters: flts))

            case .rollup(let levels):
                let allCols = levels.flatMap(\.columns)
                let detailTuples = try groupCombinations(allCols, filter: filtered, store: store)

                var tuples: [[Value]] = []
                var flts: [[FilterItem]] = []

                // State 0: Tổng toàn bộ (Grand Total)
                var state0Tuple: [Value] = []
                for lvl in levels {
                    for _ in lvl.columns { state0Tuple.append(.blank) }
                    state0Tuple.append(.boolean(true))
                }
                tuples.append(state0Tuple)
                flts.append([]) // Không lọc cột nào

                // State s (1...levels.count)
                for s in 1...levels.count {
                    let activeLevels = levels[0..<s]
                    let activeCols = activeLevels.flatMap(\.columns)
                    let currentLevel = levels[s - 1]

                    var candidateTuples = detailTuples
                    // [SUY ĐOÁN] NONVISUAL(bảng) trong ROLLUPADDISSUBTOTAL giới hạn các nhóm cha được mở cấp con
                    if let filterExpr = currentLevel.filter {
                        let filterTable = try evaluator.table(filterExpr, in: EvalContext(filter: filtered, row: nil))
                        candidateTuples = filterCandidateTuples(candidateTuples, allCols: allCols, filterTable: filterTable)
                    }

                    var seenPrefix = Set<[Value]>()
                    for dt in candidateTuples {
                        let prefix = Array(dt.prefix(activeCols.count))
                        if seenPrefix.insert(prefix).inserted {
                            var rowVals: [Value] = []
                            var cellFilterItems: [FilterItem] = []
                            var curOffset = 0
                            for (li, lvl) in levels.enumerated() {
                                if li < s {
                                    let lvlVals = Array(prefix[curOffset..<(curOffset + lvl.columns.count)])
                                    rowVals.append(contentsOf: lvlVals)
                                    rowVals.append(.boolean(false))
                                    for (ci, col) in lvl.columns.enumerated() {
                                        cellFilterItems.append(FilterItem(column: col, values: [lvlVals[ci]]))
                                    }
                                } else {
                                    for _ in lvl.columns { rowVals.append(.blank) }
                                    rowVals.append(.boolean(true))
                                }
                                curOffset += lvl.columns.count
                            }
                            tuples.append(rowVals)
                            flts.append(cellFilterItems)
                        }
                    }
                }
                clauseResults.append(ClauseCombos(tuples: tuples, filters: flts))
            }
        }

        // Tích Descartes giữa các mệnh đề nhóm
        var combinedTuples: [[Value]] = [[]]
        var combinedFilters: [[FilterItem]] = [[]]
        for cRes in clauseResults {
            var nextTuples: [[Value]] = []
            var nextFilters: [[FilterItem]] = []
            for (baseTuple, baseFilter) in zip(combinedTuples, combinedFilters) {
                for (clauseTuple, clauseFilter) in zip(cRes.tuples, cRes.filters) {
                    nextTuples.append(baseTuple + clauseTuple)
                    nextFilters.append(baseFilter + clauseFilter)
                }
            }
            combinedTuples = nextTuples
            combinedFilters = nextFilters
        }

        var out: [[Value]] = []
        for (combo, filterItems) in zip(combinedTuples, combinedFilters) {
            try QueryExecutor.checkCancelled()
            var cell = cellBase
            for item in filterItems {
                cell = cell.applying(item, keep: false)
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
        return out
    }

    /// [SUY ĐOÁN] Lọc candidateTuples theo filterTable khi có NONVISUAL
    private static func filterCandidateTuples(_ tuples: [[Value]], allCols: [ColumnID],
                                              filterTable: TableValue) -> [[Value]] {
        var matchMap: [(allColsIdx: Int, ftIdx: Int)] = []
        for (ai, col) in allCols.enumerated() {
            if let fti = filterTable.lineageIndex(of: col) {
                matchMap.append((ai, fti))
            }
        }
        guard !matchMap.isEmpty else { return tuples }
        var allowedTuples = Set<[Value]>()
        for r in filterTable.rows {
            let key = matchMap.map { r[$0.ftIdx] }
            allowedTuples.insert(key)
        }
        return tuples.filter { dt in
            let key = matchMap.map { dt[$0.allColsIdx] }
            return allowedTuples.contains(key)
        }
    }

    /// Áp các bảng bộ lọc lên ngữ cảnh gốc.
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
                } else if indices.count > 1 {
                    let targets = indices.compactMap { table.lineage[$0] }
                    if targets.count == indices.count {
                        let subTable = table.projecting(indices)
                        let rowFilter = try FilterFunctions.treatasRowFilter(tuples: subTable, targets: targets, store: store)
                        ctx = ctx.applying(rows: rowFilter, keep: keepThis || touchedTables.contains(table0))
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
