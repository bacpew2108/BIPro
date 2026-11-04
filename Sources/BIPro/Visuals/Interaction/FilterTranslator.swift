import DAXEngine
import Foundation

enum FilterScope: Hashable, Sendable {
    case visual
    case page
    case report
}

/// Điều kiện tĩnh của report/page/visual trên MỘT cột, đã dịch sang vị từ DAX.
struct StaticFilter: Hashable, Sendable {
    var column: QueryColumn
    var predicate: String
    var scope: FilterScope

    init(column: QueryColumn, predicate: String, scope: FilterScope) {
        self.column = column
        self.predicate = predicate
        self.scope = scope
    }
}

struct InteractionTarget: Hashable, Sendable {
    var visualID: String
    var visualType: String

    init(visualID: String, visualType: String) {
        self.visualID = visualID
        self.visualType = visualType
    }
}

struct AssembledFilters: Hashable, Sendable {
    var filters: [QueryFilter] // theo thứ tự __DS0FilterTable, __DS0FilterTable2, …
    var highlight: QueryFilter? // __H0FilterTable; nil khi không tô sáng

    init(filters: [QueryFilter], highlight: QueryFilter? = nil) {
        self.filters = filters
        self.highlight = highlight
    }
}

enum FilterTranslator {
    /// Dịch giá trị runtime sang literal DAX.
    static func literal(_ value: Value) -> String {
        switch value {
        case .integer(let i):
            return String(i)
        case .string(let s):
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        case .boolean(let b):
            return b ? "TRUE" : "FALSE"
        case .blank:
            return "BLANK()"
        case .double(let d):
            guard d.isFinite else { return String(d) }
            if d == d.rounded() && abs(d) < 1e15 {
                return String(Int64(d))
            }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 15
            if let s = formatter.string(from: NSNumber(value: d)), !s.contains("e") && !s.contains("E") {
                return s
            }
            return String(d)
        case .currency(let n):
            let dec = Decimal(n) / Decimal(10000)
            return NSDecimalNumber(decimal: dec).stringValue
        case .dateTime(let d):
            guard d.isFinite else { return String(d) }
            let ms = ((d - 25_569) * 86_400_000).rounded()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            let date = Date(timeIntervalSince1970: ms / 1000)
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let y = c.year ?? 0
            let m = c.month ?? 0
            let day = c.day ?? 0
            let h = c.hour ?? 0
            let mi = c.minute ?? 0
            let s = c.second ?? 0
            if h == 0 && mi == 0 && s == 0 {
                return "DATE(\(y), \(m), \(day))"
            } else {
                return "DATETIME(\(y), \(m), \(day), \(h), \(mi), \(s))"
            }
        }
    }

    /// So sánh hai giá trị Value theo quy tắc Power BI:
    /// [SUY ĐOÁN] Power BI có thể giữ thứ tự chọn; hai file mẫu đều tăng dần nên chưa phân biệt được.
    /// BLANK đứng đầu, số theo số, chuỗi theo từ điển, số đứng trước chuỗi.
    static func valuePrecedes(_ a: Value, _ b: Value) -> Bool {
        func group(_ v: Value) -> Int {
            switch v {
            case .blank: return 0
            case .integer, .double, .currency, .dateTime: return 1
            case .boolean: return 2
            case .string: return 3
            }
        }

        let gA = group(a)
        let gB = group(b)
        if gA != gB { return gA < gB }

        switch (a, b) {
        case (.blank, .blank):
            return false
        case (.boolean(let x), .boolean(let y)):
            return !x && y
        case (.string(let x), .string(let y)):
            return x < y
        default:
            // Nhóm số
            func toDouble(_ v: Value) -> Double {
                switch v {
                case .integer(let i): return Double(i)
                case .double(let d): return d
                case .currency(let c): return Double(c) / 10000.0
                case .dateTime(let d): return d
                default: return 0
                }
            }
            let numA = toDouble(a)
            let numB = toDouble(b)
            if numA != numB {
                return numA < numB
            }
            func subTypeOrder(_ v: Value) -> Int {
                switch v {
                case .integer: return 0
                case .double: return 1
                case .currency: return 2
                case .dateTime: return 3
                default: return 4
                }
            }
            return subTypeOrder(a) < subTypeOrder(b)
        }
    }

    /// So sánh hai tuple [Value] theo từng phần tử.
    static func tuplePrecedes(_ a: [Value], _ b: [Value]) -> Bool {
        let count = min(a.count, b.count)
        for i in 0..<count {
            if a[i] != b[i] {
                return valuePrecedes(a[i], b[i])
            }
        }
        return a.count < b.count
    }

    /// Lồng AND hai ngôi cho danh sách các vị từ.
    static func combineAnd(_ predicates: [String]) -> String {
        guard let first = predicates.first else { return "" }
        return predicates.dropFirst().reduce(first) { "AND(\($0), \($1))" }
    }

    /// Tạo danh sách bộ lọc hoàn chỉnh cho một visual.
    static func assemble(
        for target: InteractionTarget,
        staticFilters: [StaticFilter],
        state: FilterState
    ) -> AssembledFilters {
        // Đích là slicer: chỉ nhận bộ lọc tĩnh (report/page/visual): không nhận lựa chọn của slicer khác,
        // lọc chéo hay drillthrough, và đương nhiên không tự lọc chính nó. // [SUY ĐOÁN]
        if target.visualType == "slicer" {
            var result: [QueryFilter] = []
            for scope in [FilterScope.visual, .page, .report] {
                for sf in staticFilters where sf.scope == scope {
                    result.append(QueryFilter(tableExpression: "FILTER(KEEPFILTERS(VALUES(\(sf.column.dax))), \(sf.predicate))"))
                }
            }
            return AssembledFilters(filters: result, highlight: nil)
        }

        // 1. Nhóm drillthrough
        var drillthroughFilters: [QueryFilter] = []
        for cv in state.drillthrough where !cv.values.isEmpty {
            let sorted = Array(Set(cv.values)).sorted(by: valuePrecedes)
            let literals = sorted.map(literal).joined(separator: ", ")
            drillthroughFilters.append(QueryFilter(tableExpression: "TREATAS({\(literals)}, \(cv.column.dax))"))
        }

        // 2. Lọc chéo và tô sáng chéo
        var crossFilterTable: QueryFilter?
        var highlightFilter: QueryFilter?

        if let sourceID = state.selection.sourceVisualID,
           let sourceType = state.selection.sourceVisualType,
           !state.selection.points.isEmpty,
           !state.selection.columns.isEmpty {
            let source = InteractionTarget(visualID: sourceID, visualType: sourceType)
            let effect = InteractionRules.effect(of: source, on: target, overrides: state.overrides)

            if effect != .none {
                let treatasExpr: String
                let cols = state.selection.columns
                if cols.count == 1 {
                    let col = cols[0]
                    let rawValues = state.selection.points.compactMap { $0.values[col.queryRef] }
                    let sorted = Array(Set(rawValues)).sorted(by: valuePrecedes)
                    let literals = sorted.map(literal).joined(separator: ", ")
                    treatasExpr = "TREATAS({\(literals)}, \(col.column.dax))"
                } else {
                    // [SUY ĐOÁN] dạng nhiều cột chưa quan sát
                    var tupleSet = Set<[Value]>()
                    for pt in state.selection.points {
                        let t = cols.map { pt.values[$0.queryRef] ?? .blank }
                        tupleSet.insert(t)
                    }
                    let sortedTuples = Array(tupleSet).sorted(by: tuplePrecedes)
                    let tupleStrings = sortedTuples.map { "(" + $0.map(literal).joined(separator: ", ") + ")" }
                    let colList = cols.map(\.column.dax).joined(separator: ", ")
                    treatasExpr = "TREATAS({\(tupleStrings.joined(separator: ", "))}, \(colList))"
                }

                if effect == .filter {
                    crossFilterTable = QueryFilter(tableExpression: treatasExpr)
                } else if effect == .highlight {
                    highlightFilter = QueryFilter(tableExpression: treatasExpr)
                }
            }
        }

        // 3. Drill down của visual này
        let drillDownCVs = (state.drillFilters[target.visualID] ?? []).filter { !$0.values.isEmpty }
        var drillDownPredicates: [QueryColumn: String] = [:]
        for cv in drillDownCVs {
            let sorted = Array(Set(cv.values)).sorted(by: valuePrecedes)
            let literals = sorted.map(literal).joined(separator: ", ")
            drillDownPredicates[cv.column] = "\(cv.column.dax) IN {\(literals)}"
        }

        // 4. Phân tích slicer
        var orderedSlicerIDs: [String] = []
        for id in state.slicerOrder {
            if state.slicers[id] != nil && !orderedSlicerIDs.contains(id) {
                orderedSlicerIDs.append(id)
            }
        }
        for id in state.slicers.keys {
            if !orderedSlicerIDs.contains(id) {
                orderedSlicerIDs.append(id)
            }
        }
        // Slicer không tự lọc chính nó
        orderedSlicerIDs.removeAll { $0 == target.visualID }

        struct SlicerPlan {
            var slicerID: String
            var columns: [QueryColumn] // các cột dùng
            var isHierarchical: Bool
            var predicate: String
            var tableExpressionUnmerged: String
        }

        var plans: [SlicerPlan] = []
        for id in orderedSlicerIDs {
            guard let slicer = state.slicers[id], !slicer.selection.isEmpty, !slicer.columns.isEmpty else {
                continue
            }
            let maxLen = slicer.selection.paths.map(\.count).max() ?? 0
            guard maxLen > 0 else { continue }

            if maxLen == 1 {
                // Slicer, mọi đường dẫn chọn dài 1
                let c0 = slicer.columns[0]
                let rawValues = slicer.selection.paths.compactMap(\.first)
                let sorted = Array(Set(rawValues)).sorted(by: valuePrecedes)
                let literals = sorted.map(literal).joined(separator: ", ")
                let pred = "\(c0.dax) IN {\(literals)}"
                let unmerged = "FILTER(KEEPFILTERS(VALUES(\(c0.dax))), \(pred))"
                plans.append(SlicerPlan(slicerID: id, columns: [c0], isHierarchical: false, predicate: pred, tableExpressionUnmerged: unmerged))
            } else {
                // Slicer phân cấp có đường dẫn dài >= 2
                let c0 = slicer.columns[0]
                let baseTable = c0.table
                // [SUY ĐOÁN] Các cột khác bảng với c0: bỏ cột thừa
                let cols = Array(slicer.columns.prefix(maxLen).filter { $0.table == baseTable })
                guard !cols.isEmpty else { continue }

                // Gom nhóm theo độ dài đường dẫn
                let lengths = Array(Set(slicer.selection.paths.map(\.count))).sorted()
                var groupPreds: [String] = []
                for n in lengths {
                    let pathsOfLen = slicer.selection.paths.filter { $0.count == n }
                    if n == 1 {
                        let rawVals = pathsOfLen.compactMap(\.first)
                        let sortedVals = Array(Set(rawVals)).sorted(by: valuePrecedes)
                        let lits = sortedVals.map(literal).joined(separator: ", ")
                        groupPreds.append("\(cols[0].dax) IN {\(lits)}")
                    } else {
                        var tupleSet = Set<[Value]>()
                        for p in pathsOfLen {
                            tupleSet.insert(Array(p.prefix(n)))
                        }
                        let sortedTuples = Array(tupleSet).sorted(by: tuplePrecedes)
                        let tupleStrings = sortedTuples.map { "(" + $0.map(literal).joined(separator: ", ") + ")" }
                        let tupleList = tupleStrings.joined(separator: ", ")
                        let colList = cols.prefix(n).map(\.dax).joined(separator: ", ")
                        groupPreds.append("(\(colList)) IN {\(tupleList)}")
                    }
                }

                let slicerPred = groupPreds.dropFirst().reduce(groupPreds[0]) { "OR(\($0), \($1))" }
                let colListAll = cols.map(\.dax).joined(separator: ", ")
                let unmerged = "FILTER(KEEPFILTERS(SUMMARIZE(VALUES('\(baseTable)'), \(colListAll))), \(slicerPred))"
                plans.append(SlicerPlan(slicerID: id, columns: cols, isHierarchical: true, predicate: slicerPred, tableExpressionUnmerged: unmerged))
            }
        }

        // 5. Kết hợp với StaticFilter:
        // Cần xác định staticFilter nào bị gộp, vào bảng nào, ở vị trí nào.
        // Duyệt staticFilters theo thứ tự đầu vào:
        var mergedStaticIndices = Set<Int>()
        var staticReplacements: [Int: QueryFilter] = [:]
        var mergedPlanIDs = Set<String>()
        var mergedDrillColumns = Set<QueryColumn>()

        // Ưu tiên gộp slicer trước
        for plan in plans {
            // Tìm tất cả static filters khớp với các cột của plan
            let matchedIndices = staticFilters.indices.filter { idx in
                !mergedStaticIndices.contains(idx) && plan.columns.contains(staticFilters[idx].column)
            }
            if let firstIdx = matchedIndices.first {
                mergedPlanIDs.insert(plan.slicerID)
                for idx in matchedIndices {
                    mergedStaticIndices.insert(idx)
                }

                let c0 = plan.columns[0]
                let staticPredicates = matchedIndices.map { staticFilters[$0].predicate }
                let combinedStatic = combineAnd(staticPredicates)

                // Kiểm tra xem có drill down nào trên các cột này không
                var drillPred: String?
                for col in plan.columns {
                    if let dp = drillDownPredicates[col], !mergedDrillColumns.contains(col) {
                        drillPred = dp
                        mergedDrillColumns.insert(col)
                        break
                    }
                }

                let tableExpr: String
                if plan.isHierarchical {
                    // slicer3-quy.dax: AND(<vị từ tĩnh>, <vị từ slicer>)
                    var inner = "AND(\(combinedStatic), \(plan.predicate))"
                    if let drillPred {
                        inner = "AND(\(drillPred), \(inner))"
                    }
                    let colList = plan.columns.map(\.dax).joined(separator: ", ")
                    tableExpr = "FILTER(KEEPFILTERS(SUMMARIZE(VALUES('\(c0.table)'), \(colList))), \(inner))"
                } else {
                    // slicer1-card.dax: AND(c0 IN {…}, <vị từ tĩnh>)
                    var inner = "AND(\(plan.predicate), \(combinedStatic))"
                    if let drillPred {
                        inner = "AND(\(drillPred), \(inner))"
                    }
                    tableExpr = "FILTER(KEEPFILTERS(VALUES(\(c0.dax))), \(inner))"
                }
                staticReplacements[firstIdx] = QueryFilter(tableExpression: tableExpr)
            }
        }

        // Gộp drill down còn lại vào static filters nếu có
        for (col, drillPred) in drillDownPredicates where !mergedDrillColumns.contains(col) {
            if let idx = staticFilters.indices.first(where: { !mergedStaticIndices.contains($0) && staticFilters[$0].column == col }) {
                mergedStaticIndices.insert(idx)
                mergedDrillColumns.insert(col)
                let sf = staticFilters[idx]
                // drill-down-2016.dax: AND(c0 IN {…}, <vị từ tĩnh>)
                let tableExpr = "FILTER(KEEPFILTERS(VALUES(\(col.dax))), AND(\(drillPred), \(sf.predicate)))"
                staticReplacements[idx] = QueryFilter(tableExpression: tableExpr)
            }
        }

        // Tạo danh sách bộ lọc theo 4 nhóm:
        // [QUAN SÁT: bộ lọc visual và tương tác đứng trước bộ lọc report (C1.md §2.2); thứ tự giữa các nhóm còn lại là SUY ĐOÁN]:
        // 1. bộ lọc tĩnh cấp visual (kể cả bảng đã gộp slicer/drill và drill down chưa gộp)
        var visualFilters: [QueryFilter] = []
        for idx in staticFilters.indices where staticFilters[idx].scope == .visual {
            if let replaced = staticReplacements[idx] {
                visualFilters.append(replaced)
            } else if !mergedStaticIndices.contains(idx) {
                let sf = staticFilters[idx]
                visualFilters.append(QueryFilter(tableExpression: "FILTER(KEEPFILTERS(VALUES(\(sf.column.dax))), \(sf.predicate))"))
            }
        }
        // Thêm drill down visual chưa gộp
        for (col, drillPred) in drillDownPredicates where !mergedDrillColumns.contains(col) {
            visualFilters.append(QueryFilter(tableExpression: "FILTER(KEEPFILTERS(VALUES(\(col.dax))), \(drillPred))"))
        }

        // 2. Nhóm tương tác: drillthrough, rồi lọc chéo, rồi các slicer chưa gộp (theo slicerOrder)
        var interactiveFilters: [QueryFilter] = []
        interactiveFilters.append(contentsOf: drillthroughFilters)
        if let crossFilterTable {
            interactiveFilters.append(crossFilterTable)
        }
        for plan in plans where !mergedPlanIDs.contains(plan.slicerID) {
            interactiveFilters.append(QueryFilter(tableExpression: plan.tableExpressionUnmerged))
        }

        // 3. Bộ lọc tĩnh cấp page (kể cả bảng đã gộp slicer)
        var pageFilters: [QueryFilter] = []
        for idx in staticFilters.indices where staticFilters[idx].scope == .page {
            if let replaced = staticReplacements[idx] {
                pageFilters.append(replaced)
            } else if !mergedStaticIndices.contains(idx) {
                let sf = staticFilters[idx]
                pageFilters.append(QueryFilter(tableExpression: "FILTER(KEEPFILTERS(VALUES(\(sf.column.dax))), \(sf.predicate))"))
            }
        }

        // 4. Bộ lọc tĩnh cấp report (kể cả bảng đã gộp slicer/drill)
        var reportFilters: [QueryFilter] = []
        for idx in staticFilters.indices where staticFilters[idx].scope == .report {
            if let replaced = staticReplacements[idx] {
                reportFilters.append(replaced)
            } else if !mergedStaticIndices.contains(idx) {
                let sf = staticFilters[idx]
                reportFilters.append(QueryFilter(tableExpression: "FILTER(KEEPFILTERS(VALUES(\(sf.column.dax))), \(sf.predicate))"))
            }
        }

        let allFilters = visualFilters + interactiveFilters + pageFilters + reportFilters
        return AssembledFilters(filters: allFilters, highlight: highlightFilter)
    }
}
