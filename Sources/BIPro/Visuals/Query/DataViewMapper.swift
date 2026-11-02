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
        guard let body = result.tables.last else { return .empty(reason: "Không có dữ liệu") }
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
        guard let row = body.rows.first else { return .empty(reason: "Không có dữ liệu") }
        // Giá trị của card là measure ở Values; measure màu/icon chỉ để định dạng.
        guard let m = spec.measures.first(where: { if case .value = $0.purpose { true } else { false } }) else {
            return .empty(reason: "Card không có giá trị")
        }
        return .single(SingleValueData(measure: m.field, cell: cell(m, row: row, index: index, spec: spec)))
    }

    // MARK: - Slicer

    private static func slicer(_ body: ResultTable, spec: VisualQuerySpec) -> DataView {
        let index = Index(body)
        guard let g = spec.primary.first, let i = index.column(g.column) else { return .empty(reason: "Slicer không có cột") }
        return .slicer(SlicerData(levels: spec.primary.map(\.field), roots: body.rows.map { SlicerNode($0[i]) }))
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
            measures: measures.map(\.field), values: values, highlights: nil, isReduced: reduced))
    }

    // MARK: - Matrix

    private static func matrix(_ result: QueryResult, spec: VisualQuerySpec) -> DataView {
        guard let body = result.tables.last else { return .empty(reason: "Không có dữ liệu") }
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
            columns = secondary.rows.map { r in
                if let t = colTotal, isTrue(r[t]) { return MatrixHeader(path: [], level: -1, isGrandTotal: true) }
                return MatrixHeader(path: colIdx.map { $0.map { r[$0] } ?? .blank }, level: 0)
            }
        }
        let columnCount = max(1, columns.count)

        // Tiêu đề hàng theo thứ tự thân; dòng tổng chung (đứng đầu trong truy vấn) chuyển xuống cuối như Power BI vẽ.
        var headers: [MatrixHeader] = []
        var rowOf: [[Value]: Int] = [:]
        var totalRow: Int?
        var cells: [[[DataCell]]] = []
        for r in body.rows {
            let isTotal = rowTotal.map { isTrue(r[$0]) } ?? false
            let path = isTotal ? [] : rowIdx.map { $0.map { r[$0] } ?? .blank }
            let key = isTotal ? [Value.string("\u{0}total")] : path
            let i: Int
            if let existing = rowOf[key] { i = existing } else {
                i = headers.count
                rowOf[key] = i
                headers.append(isTotal ? MatrixHeader(path: [], level: -1, isGrandTotal: true) : MatrixHeader(path: path, level: 0))
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
        return .matrix(MatrixData(rowLevels: spec.primary.map(\.field), columnLevels: spec.secondary.map(\.field),
                                  measures: measures.map(\.field), rows: headers, columns: columns, cells: cells,
                                  isReduced: false))
    }
}
