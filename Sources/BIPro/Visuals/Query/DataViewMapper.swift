// Gói Q (Phase C, lead): QueryResult (các bảng EVALUATE theo khuôn DAXQueryBuilder) → DataView cho renderer.
//
// Tên cột kết quả của engine: cột nhóm `Bảng[cột]`, cột measure `[Tên]` (giống Copy của DAX Query View).
// Thứ tự bảng theo từng khuôn (DAXQueryBuilder.build):
//   card, slicer, chart một trục, donut, treemap, shape map → bảng thân là bảng CUỐI;
//   line trục liên tục → [ROW đếm, thân]; chart hai trục → [secondary, thân]; 100% → [ROW đếm, secondary, thân];
//   matrix → [GROUPBY min/max?, secondary?, thân].
import DAXEngine
import Foundation

enum DataViewMapper {
    static func map(_ result: QueryResult, spec: VisualQuerySpec) -> DataView {
        guard let body = result.tables.last else { return .empty(reason: biN("Không có dữ liệu", "No data")) }
        switch spec.shape {
        case .card: return card(body, spec: spec)
        case .slicer: return slicer(body, spec: spec)
        case .matrix: return matrix(result, spec: spec)
        case .chart, .hundredPercent:
            if spec.secondary.isEmpty { return categorical(body, spec: spec, series: nil) }
            let secondary = result.tables.count >= 2 ? result.tables[result.tables.count - 2] : nil
            return categorical(body, spec: spec, series: secondary)
        case .donut, .treemap, .shapeMap:
            return categorical(body, spec: spec, series: nil)
        case .table:
            return flatTable(result, spec: spec)
        case .scatter:
            return scatter(body, spec: spec)
        case .gauge:
            return gauge(body, spec: spec)
        case .kpi:
            return kpi(body, spec: spec)
        case .multiRowCard:
            return multiRowCard(body, spec: spec)
        }
    }

    // MARK: - Cột

    static func columnName(_ c: QueryColumn) -> String { "\(c.table)[\(c.column)]" }

    private struct Index {
        let byName: [String: Int]
        init(_ table: ResultTable) {
            byName = Dictionary(table.columns.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        }
        subscript(_ name: String) -> Int? { byName[name] }
        func column(_ c: QueryColumn) -> Int? { byName[DataViewMapper.columnName(c)] }
        func result(_ name: String) -> Int? { byName["[\(name)]"] }
    }

    /// Measure hiển thị (không phải cột định dạng động hay thuộc tính lấy từ measure).
    private static func visibleMeasures(_ spec: VisualQuerySpec) -> [QueryMeasure] {
        (spec.measures + spec.scopedMeasures).filter {
            switch $0.purpose { case .value, .tooltip: true; default: false }
        }
    }

    /// Ô của measure `m` ở dòng `row`, kèm định dạng động và thuộc tính lấy từ measure.
    private static func cell(_ m: QueryMeasure, row: [Value], index: Index, spec: VisualQuerySpec) -> DataCell {
        guard let i = index.result(m.resultName), i < row.count else { return .blank }
        var cell = DataCell(row[i], formatString: m.field.formatString)
        for other in spec.measures + spec.scopedMeasures {
            guard let j = index.result(other.resultName), j < row.count, case .string(let text) = row[j] else { continue }
            switch other.purpose {
            case .formatString(let of) where of == m.field.queryRef:
                cell.formatString = text
            case .formatting(let p) where p.target == nil || p.target == m.field.queryRef:
                switch p.property {
                case "fill": cell.fillColor = text
                case "color", "fontColor": cell.fontColor = text
                case "backColor": cell.backColor = text
                case "icon": cell.icon = text
                default: break
                }
            default:
                continue
            }
        }
        return cell
    }

    private static func isTrue(_ v: Value?) -> Bool { if case .boolean(true)? = v { true } else { false } }

    // MARK: - Card

    private static func card(_ body: ResultTable, spec: VisualQuerySpec) -> DataView {
        let index = Index(body)
        guard let row = body.rows.first else { return .empty(reason: biN("Không có dữ liệu", "No data")) }
        // Giá trị của card là measure ở Values; measure màu/icon chỉ để định dạng.
        guard let m = spec.measures.first(where: { if case .value = $0.purpose { true } else { false } }) else {
            return .empty(reason: biN("Card không có giá trị", "The card has no value"))
        }
        return .single(SingleValueData(measure: m.field, cell: cell(m, row: row, index: index, spec: spec)))
    }

    // MARK: - Slicer

    private static func slicer(_ body: ResultTable, spec: VisualQuerySpec) -> DataView {
        let index = Index(body)
        guard let g = spec.primary.first, let i = index.column(g.column) else { return .empty(reason: biN("Slicer không có cột", "The slicer has no column")) }
        let format = g.field.formatString
        if spec.drillLevels.count >= 2, let flag = index.result("IsDM1Total"), let grand = index.result("IsGrandTotalRowTotal"),
           let child = index.column(spec.drillLevels[1].column) {
            // Hàng IsDM1Total = TRUE là nút cấp gốc; FALSE là cấp con của nút đang mở.
            var roots: [SlicerNode] = []
            var position: [Value: Int] = [:]
            let childFormat = spec.drillLevels[1].field.formatString
            for row in body.rows where !isTrue(row[grand]) {
                if isTrue(row[flag]) {
                    position[row[i]] = roots.count
                    roots.append(SlicerNode(row[i], formatString: format))
                } else if let at = position[row[i]] {
                    roots[at].children.append(SlicerNode(row[child], formatString: childFormat))
                }
            }
            return .slicer(SlicerData(levels: spec.drillLevels.map(\.field), roots: roots))
        }
        let levelFields = spec.drillLevels.count >= 2 ? spec.drillLevels.map(\.field) : spec.primary.map(\.field)
        return .slicer(SlicerData(levels: levelFields,
                                  roots: body.rows.map { SlicerNode($0[i], formatString: format) }))
    }

    // MARK: - Categorical

    private static func categorical(_ body: ResultTable, spec: VisualQuerySpec, series secondary: ResultTable?) -> DataView {
        let index = Index(body)
        var rows = body.rows
        // Donut: bỏ dòng tổng (IsGrandTotalRowTotal = TRUE).
        if let t = index.result("IsGrandTotalRowTotal") { rows = rows.filter { !isTrue($0[t]) } }

        let levelIdx = spec.primary.map { index.column($0.column) }
        var categories: [CategoryKey] = []
        var categoryOf: [CategoryKey: Int] = [:]
        for row in rows {
            let key = CategoryKey(values: levelIdx.map { $0.map { row[$0] } ?? .blank })
            if categoryOf[key] == nil { categoryOf[key] = categories.count; categories.append(key) }
        }

        // Series: từ bảng secondary (thứ tự hiển thị), ánh xạ qua [ColumnIndex].
        var series: [Value] = []
        let columnIndex = index.result("ColumnIndex")
        if let secondary, let g = spec.secondary.first, let s = Index(secondary).column(g.column) {
            series = secondary.rows.map { $0[s] }
        }
        let seriesCount = max(1, series.count)
        let measures = visibleMeasures(spec)
        let scopedRefs = Set(spec.scopedMeasures.map(\.resultName))
        var values: [[[DataCell]]] = measures.map { m in
            Array(repeating: Array(repeating: .blank, count: categories.count), count: scopedRefs.contains(m.resultName) ? 1 : seriesCount)
        }
        for row in rows {
            let key = CategoryKey(values: levelIdx.map { $0.map { row[$0] } ?? .blank })
            guard let c = categoryOf[key] else { continue }
            var s = 0
            if let ci = columnIndex, case .integer(let n) = row[ci] { s = Int(n) }
            for (m, measure) in measures.enumerated() {
                let target = values[m].count == 1 ? 0 : s
                guard target < values[m].count else { continue }
                let value = cell(measure, row: row, index: index, spec: spec)
                // Measure không chia series (Y2 của combo có Series) lặp lại ở mọi dòng series: giữ giá trị đầu khác BLANK.
                if values[m][target][c].value == .blank { values[m][target][c] = value }
            }
        }
        // Tô sáng chéo: cột song sinh của từng measure, cùng kích thước với `values`.
        var highlights: [[[DataCell]]]?
        if spec.highlight != nil {
            var h: [[[DataCell]]] = values.map { $0.map { $0.map { _ in DataCell.blank } } }
            for row in rows {
                let key = CategoryKey(values: levelIdx.map { $0.map { row[$0] } ?? .blank })
                guard let c = categoryOf[key] else { continue }
                var s = 0
                if let ci = columnIndex, case .integer(let n) = row[ci] { s = Int(n) }
                for (m, measure) in measures.enumerated() {
                    guard let name = DAXQueryBuilder.highlightName(measure), let j = index.result(name), j < row.count else { continue }
                    let target = h[m].count == 1 ? 0 : s
                    guard target < h[m].count else { continue }
                    if h[m][target][c].value == .blank {
                        h[m][target][c] = DataCell(row[j], formatString: measure.field.formatString)
                    }
                }
            }
            highlights = h
        }
        let reduced: Bool = {
            switch spec.reduction {
            case .top(let n): return body.rows.count >= n
            case .sample(let n): return body.rows.count >= n
            default: return false
            }
        }()
        return .categorical(CategoricalData(
            categoryLevels: spec.primary.map(\.field), categories: categories,
            seriesField: spec.secondary.first?.field, series: series,
            measures: measures.map(\.field), values: values, highlights: highlights, isReduced: reduced))
    }

    // MARK: - Matrix

    private static func matrix(_ result: QueryResult, spec: VisualQuerySpec) -> DataView {
        guard let body = result.tables.last else { return .empty(reason: biN("Không có dữ liệu", "No data")) }
        let index = Index(body)
        let rowIdx = spec.primary.map { index.column($0.column) }
        let rowTotal = index.result("IsGrandTotalRowTotal")
        let measures = visibleMeasures(spec)

        // Tiêu đề cột: từ bảng secondary (thứ tự hiển thị, có cờ tổng).
        var columns: [MatrixHeader] = []
        if !spec.secondary.isEmpty, result.tables.count >= 2 {
            let secondary = result.tables[result.tables.count - 2]
            let si = Index(secondary)
            let colIdx = spec.secondary.map { si.column($0.column) }
            let colTotal = si.result("IsGrandTotalColumnTotal")
            // Nhiều cấp mở: cờ `IsDM2Total`, `IsDM4Total`… cho từng cấp con. Dòng thuộc cấp sâu nhất có cờ FALSE (VM C2 b5-1, b5-2).
            let depth = spec.matrixColumnDepth
            let flags = (0..<depth).map { si.result(VisualQuerySpec.columnFlagName($0)) }
            let levelIdx = (0..<(depth >= 2 ? depth : 0)).map { j in si.column(spec.drillLevels[j].column) }
            let canExpand = spec.drillLevels.count >= 2
            columns = secondary.rows.map { r in
                if let t = colTotal, isTrue(r[t]) { return MatrixHeader(path: [], level: -1, isGrandTotal: true) }
                if depth >= 2 {
                    var level = 0
                    for j in 1..<depth { if let f = flags[j], !isTrue(r[f]) { level = j } }
                    let path = (0...level).map { j in levelIdx[j].map { r[$0] } ?? .blank }
                    return MatrixHeader(path: path, level: level, hasChildren: level + 1 < spec.drillLevels.count,
                                        isExpanded: spec.expandedPaths.contains(path))
                }
                let path = colIdx.map { $0.map { r[$0] } ?? .blank }
                return MatrixHeader(path: path, level: 0, hasChildren: canExpand, isExpanded: false)
            }
        }
        let columnCount = max(1, columns.count)

        // Tiêu đề hàng theo thứ tự thân; dòng tổng chung (đứng đầu trong truy vấn) chuyển xuống cuối như Power BI vẽ.
        let rowDepth = spec.matrixRowDepth
        let rowFlags = (0..<rowDepth).map { index.result(VisualQuerySpec.rowFlagName($0)) }
        let rowLevelIdx = (0..<(rowDepth >= 2 ? rowDepth : 0)).map { j in index.column(spec.rowDrillLevels[j].column) }
        let canExpandRows = spec.rowDrillLevels.count >= 2

        var headers: [MatrixHeader] = []
        var rowOf: [[Value]: Int] = [:]
        var totalRow: Int?
        var cells: [[[DataCell]]] = []
        for r in body.rows {
            let isTotal = rowTotal.map { isTrue(r[$0]) } ?? false
            let header: MatrixHeader
            let key: [Value]
            if isTotal {
                header = MatrixHeader(path: [], level: -1, isGrandTotal: true)
                key = [Value.string("\u{0}total")]
            } else if rowDepth >= 2 {
                var level = 0
                for j in 1..<rowDepth { if let f = rowFlags[j], !isTrue(r[f]) { level = j } }
                let path = (0...level).map { j in rowLevelIdx[j].map { r[$0] } ?? .blank }
                header = MatrixHeader(path: path, level: level, hasChildren: level + 1 < spec.rowDrillLevels.count,
                                      isExpanded: spec.rowExpandedPaths.contains(path))
                key = [Value.integer(Int64(level))] + path
            } else {
                let path = rowIdx.map { $0.map { r[$0] } ?? .blank }
                header = MatrixHeader(path: path, level: 0, hasChildren: canExpandRows, isExpanded: false)
                key = path
            }
            let i: Int
            if let existing = rowOf[key] { i = existing } else {
                i = headers.count
                rowOf[key] = i
                headers.append(header)
                cells.append(Array(repeating: Array(repeating: .blank, count: measures.count), count: columnCount))
                if isTotal { totalRow = i }
            }
            var c = 0
            if let ci = index.result("ColumnIndex"), case .integer(let n) = r[ci] { c = Int(n) }
            guard c < columnCount else { continue }
            for (m, measure) in measures.enumerated() { cells[i][c][m] = cell(measure, row: r, index: index, spec: spec) }
        }
        if let t = totalRow {
            headers.append(headers.remove(at: t))
            cells.append(cells.remove(at: t))
        }
        // Cột tổng (cờ ASC nên đã ở cuối trong secondary).
        let outRowLevels = rowDepth >= 2 ? spec.rowDrillLevels.prefix(rowDepth).map(\.field) : spec.primary.map(\.field)
        return .matrix(MatrixData(rowLevels: outRowLevels, columnLevels: (spec.matrixColumnDepth >= 2 ? spec.drillLevels.prefix(spec.matrixColumnDepth).map(\.field) : spec.secondary.map(\.field)),
                                  measures: measures.map(\.field), rows: headers, columns: columns, cells: cells,
                                  isReduced: false))
    }

    // MARK: - Table (tableEx)

    private static func flatTable(_ result: QueryResult, spec: VisualQuerySpec) -> DataView {
        guard let body = result.tables.last else { return .empty(reason: biN("Không có dữ liệu", "No data")) }
        let index = Index(body)
        let measures = visibleMeasures(spec)
        let ordered = spec.orderedFields.isEmpty ? (spec.primary.map(\.field) + measures.map(\.field)) : spec.orderedFields
        guard !ordered.isEmpty else { return .empty(reason: biN("Bảng chưa có trường nào", "The table has no fields yet")) }

        let groupByRef = Dictionary(spec.primary.map { ($0.field.queryRef, $0) }, uniquingKeysWith: { a, _ in a })
        let measureByRef = Dictionary(measures.map { ($0.field.queryRef, $0) }, uniquingKeysWith: { a, _ in a })

        let rows: [[DataCell]] = body.rows.map { row in
            ordered.map { field in
                if !field.isMeasure, let g = groupByRef[field.queryRef], let colIdx = index.column(g.column), colIdx < row.count {
                    return DataCell(row[colIdx], formatString: field.formatString)
                }
                if let m = measureByRef[field.queryRef] {
                    return cell(m, row: row, index: index, spec: spec)
                }
                return .blank
            }
        }

        var totals: [DataCell]? = nil
        if result.tables.count >= 2, let totalTable = result.tables.first, let totalRow = totalTable.rows.first, !measures.isEmpty {
            let tIndex = Index(totalTable)
            totals = ordered.map { field in
                if field.isMeasure, let m = measureByRef[field.queryRef] {
                    return cell(m, row: totalRow, index: tIndex, spec: spec)
                }
                return .blank
            }
        }

        let reduced: Bool = { if case .top(let n) = spec.reduction { body.rows.count >= n } else { false } }()
        return .table(TableDataView(columns: ordered, rows: rows, totals: totals, isReduced: reduced))
    }

    // MARK: - Scatter (scatterChart)

    private static func scatter(_ body: ResultTable, spec: VisualQuerySpec) -> DataView {
        let index = Index(body)
        let measures = visibleMeasures(spec)
        let xM = measures.first { $0.field.role == "X" }
        let yM = measures.first { $0.field.role == "Y" }
        let sizeM = measures.first { $0.field.role == "Size" }
        let tooltipMs = measures.filter { $0.field.role == "Tooltips" }
        guard xM != nil || yM != nil else { return .empty(reason: biN("Biểu đồ phân tán cần trục X hoặc Y", "A scatter chart needs an X or Y axis")) }

        let catGroup = spec.primary.first
        let serGroup = spec.secondary.first
        let catIdx = catGroup.flatMap { index.column($0.column) }
        let serIdx = serGroup.flatMap { index.column($0.column) }

        var seriesList: [Value] = []
        var seenSeries = Set<Value>()
        var points: [ScatterPoint] = []

        for row in body.rows {
            let xCell = xM.map { cell($0, row: row, index: index, spec: spec) } ?? .blank
            let yCell = yM.map { cell($0, row: row, index: index, spec: spec) } ?? .blank
            let xVal = NumberDisplay.numericValue(xCell.value)
            let yVal = NumberDisplay.numericValue(yCell.value)
            if xM != nil && xVal == nil && (yM == nil || yVal == nil) { continue }
            if yM != nil && yVal == nil && (xM == nil || xVal == nil) { continue }

            let sizeCell = sizeM.map { cell($0, row: row, index: index, spec: spec) }
            let sizeVal = sizeCell.flatMap { NumberDisplay.numericValue($0.value) }

            var ptDict: [String: Value] = [:]
            var catLabel = ""
            if let catGroup, let cIdx = catIdx, cIdx < row.count {
                let v = row[cIdx]
                ptDict[catGroup.field.queryRef] = v
                catLabel = catGroup.field.text(v)
            }
            var serVal: Value? = nil
            if let serGroup, let sIdx = serIdx, sIdx < row.count {
                let v = row[sIdx]
                serVal = v
                ptDict[serGroup.field.queryRef] = v
                if seenSeries.insert(v).inserted { seriesList.append(v) }
            }
            let tooltips = tooltipMs.map { tm in
                ScatterTooltipItem(label: tm.field.displayName, cell: cell(tm, row: row, index: index, spec: spec))
            }
            points.append(ScatterPoint(
                id: DataPointID(ptDict),
                categoryLabel: catLabel,
                seriesValue: serVal,
                x: xVal ?? 0,
                y: yVal ?? 0,
                size: sizeVal,
                xCell: xCell,
                yCell: yCell,
                sizeCell: sizeCell,
                tooltips: tooltips
            ))
        }

        let reduced: Bool = { if case .top(let n) = spec.reduction { body.rows.count >= n } else { false } }()
        return .scatter(ScatterData(
            categoryField: catGroup?.field,
            seriesField: serGroup?.field,
            series: seriesList,
            xField: xM?.field,
            yField: yM?.field,
            sizeField: sizeM?.field,
            points: points,
            isReduced: reduced
        ))
    }

    // MARK: - Gauge (gauge)

    private static func gauge(_ body: ResultTable, spec: VisualQuerySpec) -> DataView {
        let index = Index(body)
        guard let row = body.rows.first else { return .empty(reason: biN("Không có dữ liệu", "No data")) }
        let measures = visibleMeasures(spec)
        guard let yM = measures.first(where: { $0.field.role == "Y" }) ?? measures.first(where: { $0.purpose == .value }) else {
            return .empty(reason: biN("Đồng hồ đo cần giá trị", "A gauge needs a value"))
        }
        let minM = measures.first { $0.field.role == "MinValue" }
        let maxM = measures.first { $0.field.role == "MaxValue" }
        let targetM = measures.first { $0.field.role == "TargetValue" }
        return .gauge(GaugeData(
            valueField: yM.field,
            value: cell(yM, row: row, index: index, spec: spec),
            min: minM.map { cell($0, row: row, index: index, spec: spec) },
            max: maxM.map { cell($0, row: row, index: index, spec: spec) },
            target: targetM.map { cell($0, row: row, index: index, spec: spec) }
        ))
    }

    // MARK: - KPI (kpi)

    private static func kpi(_ body: ResultTable, spec: VisualQuerySpec) -> DataView {
        let index = Index(body)
        let measures = visibleMeasures(spec)
        guard let indM = measures.first(where: { $0.field.role == "Indicator" }) ?? measures.first(where: { $0.purpose == .value }) else {
            return .empty(reason: biN("KPI cần chỉ số (Indicator)", "A KPI needs an indicator"))
        }
        let goalM = measures.first { $0.field.role == "Goal" }
        let trendGroup = spec.primary.first
        let trendIdx = trendGroup.flatMap { index.column($0.column) }

        var trendPoints: [KPITrendPoint] = []
        var lastValueCell: DataCell = .blank
        var lastGoalCell: DataCell? = nil

        for row in body.rows {
            let vCell = cell(indM, row: row, index: index, spec: spec)
            let gCell = goalM.map { cell($0, row: row, index: index, spec: spec) }
            if vCell.value != .blank {
                lastValueCell = vCell
                if let gCell { lastGoalCell = gCell }
            }
            if let trendGroup, let tIdx = trendIdx, tIdx < row.count, let num = NumberDisplay.numericValue(vCell.value) {
                trendPoints.append(KPITrendPoint(label: trendGroup.field.text(row[tIdx]), value: num))
            }
        }
        if lastValueCell.value == .blank, let lastRow = body.rows.last {
            lastValueCell = cell(indM, row: lastRow, index: index, spec: spec)
            lastGoalCell = goalM.map { cell($0, row: lastRow, index: index, spec: spec) }
        }
        return .kpi(KPIData(
            indicatorField: indM.field,
            trendField: trendGroup?.field,
            goalField: goalM?.field,
            latestValue: lastValueCell,
            goalValue: lastGoalCell,
            trendPoints: trendPoints
        ))
    }

    // MARK: - Multi-row Card (multiRowCard)

    private static func multiRowCard(_ body: ResultTable, spec: VisualQuerySpec) -> DataView {
        let index = Index(body)
        let measures = visibleMeasures(spec)
        let ordered = spec.orderedFields.isEmpty ? (spec.primary.map(\.field) + measures.map(\.field)) : spec.orderedFields
        guard !ordered.isEmpty else { return .empty(reason: biN("Thẻ nhiều hàng chưa có trường nào", "The multi-row card has no fields yet")) }

        let groupByRef = Dictionary(spec.primary.map { ($0.field.queryRef, $0) }, uniquingKeysWith: { a, _ in a })
        let measureByRef = Dictionary(measures.map { ($0.field.queryRef, $0) }, uniquingKeysWith: { a, _ in a })

        let rows: [[DataCell]] = body.rows.map { row in
            ordered.map { field in
                if !field.isMeasure, let g = groupByRef[field.queryRef], let colIdx = index.column(g.column), colIdx < row.count {
                    return DataCell(row[colIdx], formatString: field.formatString)
                }
                if let m = measureByRef[field.queryRef] {
                    return cell(m, row: row, index: index, spec: spec)
                }
                return .blank
            }
        }
        let reduced: Bool = { if case .top(let n) = spec.reduction { body.rows.count >= n } else { false } }()
        return .multiRowCard(MultiRowCardData(fields: ordered, rows: rows, isReduced: reduced))
    }
}
