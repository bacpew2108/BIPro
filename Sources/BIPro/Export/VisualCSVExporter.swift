import DAXEngine
import Foundation

/// Lỗi khi xuất báo cáo hoặc dữ liệu visual.
enum ExportError: LocalizedError, Equatable, Sendable {
    case noData(reason: String)
    case noVisiblePages
    case renderFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noData(let reason): reason
        case .noVisiblePages: biN("Báo cáo không có trang hiển thị nào để xuất.", "The report has no visible pages to export.")
        case .renderFailed(let message): message
        case .writeFailed(let message): message
        }
    }
}

/// Xuất dữ liệu tóm tắt đang hiển thị của visual (`DataView`) ra CSV chuẩn RFC 4180 + UTF-8 BOM (`0xEF 0xBB 0xBF`).
/// Bảo đảm khớp 100% với bảng kết quả DAX đang hiển thị (tuân theo mọi bộ lọc/slicer/lọc chéo/drill hiện hành).
enum VisualCSVExporter {
    static let utf8BOM = Data([0xEF, 0xBB, 0xBF])

    /// Chuyển `DataView` thành các dòng bảng `(headers, rows)` (hàm thuần, dễ test và dùng lại).
    static func tabularRows(from view: DataView) throws -> (headers: [String], rows: [[String]]) {
        switch view {
        case .empty(let reason):
            throw ExportError.noData(reason: reason.isEmpty ? biN("Visual không có dữ liệu để xuất.", "The visual has no data to export.") : reason)

        case .single(let single):
            let header = single.measure.displayName
            let val = formattedCell(single.cell)
            return ([header], [[val]])

        case .categorical(let data):
            return categoricalTable(data)

        case .matrix(let matrix):
            return matrixTable(matrix)

        case .slicer(let slicer):
            return slicerTable(slicer)

        case .table(let table):
            return flatTable(table)

        case .scatter(let scatter):
            return scatterTable(scatter)

        case .gauge(let gauge):
            return gaugeTable(gauge)

        case .kpi(let kpi):
            return kpiTable(kpi)

        case .multiRowCard(let card):
            return multiRowCardTable(card)
        }
    }

    /// Xuất `DataView` ra dữ liệu CSV UTF-8 BOM, xuống dòng `\r\n` chuẩn RFC 4180.
    static func export(_ view: DataView) throws -> Data {
        let (headers, rows) = try tabularRows(from: view)
        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append(headers.map(escapeCSV).joined(separator: ","))
        for row in rows {
            lines.append(row.map(escapeCSV).joined(separator: ","))
        }
        let body = lines.joined(separator: "\r\n") + "\r\n"
        var out = utf8BOM
        out.append(Data(body.utf8))
        return out
    }

    // MARK: - Bảng từng loại DataView

    private static func categoricalTable(_ data: CategoricalData) -> (headers: [String], rows: [[String]]) {
        var headers = data.categoryLevels.map(\.displayName)
        if let seriesField = data.seriesField {
            headers.append(seriesField.displayName)
        }
        headers.append(contentsOf: data.measures.map(\.displayName))

        var rows: [[String]] = []
        let hasSeries = data.seriesField != nil && !data.series.isEmpty
        let categoryCount = max(1, data.categories.count)

        if data.categories.isEmpty && !hasSeries {
            // Visual chỉ có measures, không có Category/Series
            let measureVals = data.measures.indices.map { m in
                formattedCell(data.cell(measure: m, series: 0, category: 0))
            }
            if !measureVals.isEmpty {
                rows.append(measureVals)
            }
            return (headers, rows)
        }

        for c in 0..<categoryCount {
            let catValues: [String] = if c < data.categories.count {
                data.categoryLevels.indices.map { lvl in
                    let val = lvl < data.categories[c].values.count ? data.categories[c].values[lvl] : .blank
                    return data.categoryLevels[lvl].text(val)
                }
            } else {
                []
            }

            if hasSeries {
                for s in 0..<data.series.count {
                    let seriesText = data.seriesField?.text(data.series[s]) ?? data.series[s].asText()
                    var measureVals: [String] = []
                    var anyNonBlank = false
                    for m in data.measures.indices {
                        let sIdx = (m < data.values.count && data.values[m].count == 1) ? 0 : s
                        let cell = data.cell(measure: m, series: sIdx, category: c)
                        if cell.value != .blank { anyNonBlank = true }
                        measureVals.append(formattedCell(cell))
                    }
                    if anyNonBlank || data.measures.isEmpty {
                        rows.append(catValues + [seriesText] + measureVals)
                    }
                }
            } else {
                let measureVals = data.measures.indices.map { m in
                    formattedCell(data.cell(measure: m, series: 0, category: c))
                }
                rows.append(catValues + measureVals)
            }
        }
        return (headers, rows)
    }

    private static func matrixTable(_ matrix: MatrixData) -> (headers: [String], rows: [[String]]) {
        var headers = matrix.rowLevels.map(\.displayName)
        if matrix.columns.isEmpty {
            headers.append(contentsOf: matrix.measures.map(\.displayName))
        } else {
            for col in matrix.columns {
                let colLabel = matrixHeaderLabel(col, levels: matrix.columnLevels)
                if matrix.measures.count == 1 {
                    headers.append(colLabel.isEmpty ? matrix.measures[0].displayName : colLabel)
                } else {
                    for m in matrix.measures {
                        headers.append(colLabel.isEmpty ? m.displayName : "\(colLabel) - \(m.displayName)")
                    }
                }
            }
        }

        var rows: [[String]] = []
        rows.reserveCapacity(matrix.rows.count)
        let colCount = matrix.columns.isEmpty ? 1 : matrix.columns.count
        for (r, rowHeader) in matrix.rows.enumerated() {
            var line: [String] = []
            if !matrix.rowLevels.isEmpty {
                if rowHeader.isGrandTotal {
                    line.append("Total")
                    if matrix.rowLevels.count > 1 {
                        line.append(contentsOf: Array(repeating: "", count: matrix.rowLevels.count - 1))
                    }
                } else {
                    for lvl in matrix.rowLevels.indices {
                        if lvl < rowHeader.path.count {
                            line.append(matrix.rowLevels[lvl].text(rowHeader.path[lvl]))
                        } else {
                            line.append("")
                        }
                    }
                }
            }
            for c in 0..<colCount {
                for m in matrix.measures.indices {
                    line.append(formattedCell(matrix.cell(row: r, column: c, measure: m)))
                }
            }
            rows.append(line)
        }
        return (headers, rows)
    }

    private static func slicerTable(_ slicer: SlicerData) -> (headers: [String], rows: [[String]]) {
        let headers = slicer.levels.isEmpty ? ["Value"] : slicer.levels.map(\.displayName)
        var rows: [[String]] = []

        func walk(_ node: SlicerNode, depth: Int, prefix: [String]) {
            let text: String
            if let fmt = node.formatString {
                text = NumberDisplay.plain(DataCell(node.value, formatString: fmt))
            } else if depth < slicer.levels.count {
                text = slicer.levels[depth].text(node.value)
            } else {
                text = node.value.asText()
            }
            let next = prefix + [text]
            if node.children.isEmpty {
                var padded = next
                while padded.count < headers.count { padded.append("") }
                rows.append(padded)
            } else {
                for child in node.children {
                    walk(child, depth: depth + 1, prefix: next)
                }
            }
        }

        for root in slicer.roots {
            walk(root, depth: 0, prefix: [])
        }
        return (headers, rows)
    }

    private static func flatTable(_ table: TableDataView) -> (headers: [String], rows: [[String]]) {
        let headers = table.columns.map(\.displayName)
        var rows = table.rows.map { row in
            table.columns.indices.map { idx in
                idx < row.count ? formattedCell(row[idx]) : ""
            }
        }
        if let totals = table.totals, !totals.isEmpty {
            var totalRow = table.columns.indices.map { idx in
                idx < totals.count ? formattedCell(totals[idx]) : ""
            }
            if !totalRow.isEmpty && totalRow[0].isEmpty { totalRow[0] = "Total" }
            rows.append(totalRow)
        }
        return (headers, rows)
    }

    private static func scatterTable(_ scatter: ScatterData) -> (headers: [String], rows: [[String]]) {
        var headers: [String] = []
        if let cat = scatter.categoryField { headers.append(cat.displayName) }
        if let ser = scatter.seriesField { headers.append(ser.displayName) }
        if let x = scatter.xField { headers.append(x.displayName) }
        if let y = scatter.yField { headers.append(y.displayName) }
        if let sz = scatter.sizeField { headers.append(sz.displayName) }
        let rows: [[String]] = scatter.points.map { pt in
            var line: [String] = []
            if scatter.categoryField != nil { line.append(pt.categoryLabel) }
            if let ser = scatter.seriesField { line.append(pt.seriesValue.map { ser.text($0) } ?? "") }
            if scatter.xField != nil { line.append(formattedCell(pt.xCell)) }
            if scatter.yField != nil { line.append(formattedCell(pt.yCell)) }
            if scatter.sizeField != nil { line.append(pt.sizeCell.map(formattedCell) ?? "") }
            return line
        }
        return (headers, rows)
    }

    private static func gaugeTable(_ gauge: GaugeData) -> (headers: [String], rows: [[String]]) {
        var headers = [gauge.valueField.displayName]
        var row = [formattedCell(gauge.value)]
        if let min = gauge.min { headers.append("Min"); row.append(formattedCell(min)) }
        if let max = gauge.max { headers.append("Max"); row.append(formattedCell(max)) }
        if let target = gauge.target { headers.append("Target"); row.append(formattedCell(target)) }
        return (headers, [row])
    }

    private static func kpiTable(_ kpi: KPIData) -> (headers: [String], rows: [[String]]) {
        if !kpi.trendPoints.isEmpty {
            let trendHeader = kpi.trendField?.displayName ?? "Trend"
            var headers = [trendHeader, kpi.indicatorField.displayName]
            if let goal = kpi.goalField { headers.append(goal.displayName) }
            let goalText = kpi.goalValue.map(formattedCell) ?? ""
            let rows = kpi.trendPoints.enumerated().map { idx, pt -> [String] in
                var line = [pt.label, formattedCell(DataCell(.double(pt.value), formatString: kpi.indicatorField.formatString))]
                if kpi.goalField != nil { line.append(idx == kpi.trendPoints.count - 1 ? goalText : "") }
                return line
            }
            return (headers, rows)
        }
        var headers = [kpi.indicatorField.displayName]
        var row = [formattedCell(kpi.latestValue)]
        if let goal = kpi.goalField { headers.append(goal.displayName); row.append(kpi.goalValue.map(formattedCell) ?? "") }
        return (headers, [row])
    }

    private static func multiRowCardTable(_ card: MultiRowCardData) -> (headers: [String], rows: [[String]]) {
        let headers = card.fields.map(\.displayName)
        let rows = card.rows.map { row in
            card.fields.indices.map { idx in
                idx < row.count ? formattedCell(row[idx]) : ""
            }
        }
        return (headers, rows)
    }

    private static func matrixHeaderLabel(_ header: MatrixHeader, levels: [FieldInfo]) -> String {
        if header.isGrandTotal { return "Total" }
        return header.path.enumerated().map { idx, value in
            idx < levels.count ? levels[idx].text(value) : value.asText()
        }.joined(separator: " / ")
    }

    /// Xuất giá trị ô dạng văn bản sạch cho Excel/Numbers: ô BLANK thành chuỗi rỗng `""`.
    static func formattedCell(_ cell: DataCell) -> String {
        switch cell.value {
        case .blank:
            return ""
        case .integer(let v):
            return cell.formatString == nil ? String(v) : NumberDisplay.plain(cell)
        case .double(let v):
            if cell.formatString == nil {
                return v.truncatingRemainder(dividingBy: 1) == 0 && abs(v) < 1e15 ? String(Int64(v)) : String(v)
            }
            return NumberDisplay.plain(cell)
        case .currency(let scaled):
            if cell.formatString == nil {
                let d = Double(scaled) / 10_000.0
                return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(d)) : String(d)
            }
            return NumberDisplay.plain(cell)
        case .string(let s):
            return s
        case .boolean(let b):
            return b ? "TRUE" : "FALSE"
        case .dateTime:
            return NumberDisplay.plain(cell)
        }
    }

    /// Chuẩn RFC 4180: bọc ngoặc kép và nhân đôi `"` nếu chứa `,`, `"`, `\r`, hoặc `\n`.
    static func escapeCSV(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
