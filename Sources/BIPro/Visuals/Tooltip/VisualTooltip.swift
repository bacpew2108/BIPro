import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

// MARK: - Tooltip Data Structures

struct TooltipRow: Hashable, Sendable {
    var name: String
    var value: String

    init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

enum VisualTooltip {
    /// Khoá phụ trong `DataPointID` của tooltip vùng dự báo (line chart): `category`, `name`, `y`, `lower`, `upper`, `only`.
    static func forecastKey(_ name: String) -> String { "__forecast." + name }

    private static func forecastRows(_ point: DataPointID, data: CategoricalData) -> [TooltipRow]? {
        guard case .string(let name)? = point.values[forecastKey("name")],
              case .double(let y)? = point.values[forecastKey("y")],
              case .double(let lower)? = point.values[forecastKey("lower")],
              case .double(let upper)? = point.values[forecastKey("upper")] else { return nil }
        let format = data.measures.first { $0.role == "Y" || $0.role == "Values" }?.formatString
        func text(_ v: Double) -> String { NumberDisplay.plain(DataCell(.double(v), formatString: format)) }
        return [TooltipRow(name: name, value: text(y)), TooltipRow(name: "Upper bound", value: text(upper)),
                TooltipRow(name: "Lower bound", value: text(lower))]
    }

    /// Thứ tự: các cấp Category (và Series nếu có) của điểm, rồi measure role "Y"/"Values", rồi các "Tooltips" theo thứ tự trong visual.
    /// Giá trị theo định dạng của measure, không đổi đơn vị (qua `NumberDisplay.plain`).
    static func rows(for point: DataPointID, in data: CategoricalData) -> [TooltipRow] {
        var rows: [TooltipRow] = []

        // Tháng dự báo (chưa có dữ liệu thật): chỉ tên tháng và ba số dự báo.
        if point.values[forecastKey("only")] != nil, let forecast = forecastRows(point, data: data) {
            let level = data.categoryLevels.first?.displayName ?? ""
            if case .string(let category)? = point.values[forecastKey("category")] {
                return [TooltipRow(name: level, value: category)] + forecast
            }
            return forecast
        }

        // 1. Tìm chỉ số danh mục `c` phù hợp với point
        var matchedCatIndex: Int? = nil
        for (cIdx, cat) in data.categories.enumerated() {
            var allMatch = true
            for (lvlIdx, lvl) in data.categoryLevels.enumerated() {
                if lvlIdx < cat.values.count {
                    if let ptVal = point.values[lvl.queryRef] {
                        if ptVal != cat.values[lvlIdx] {
                            allMatch = false
                            break
                        }
                    } else {
                        allMatch = false
                        break
                    }
                }
            }
            if allMatch {
                matchedCatIndex = cIdx
                break
            }
        }

        // Nếu không khớp hoàn toàn, thử tìm danh mục khớp một phần (ví dụ chỉ có 1 trường trong point)
        if matchedCatIndex == nil {
            for (cIdx, cat) in data.categories.enumerated() {
                for (lvlIdx, lvl) in data.categoryLevels.enumerated() {
                    if lvlIdx < cat.values.count, let ptVal = point.values[lvl.queryRef], ptVal == cat.values[lvlIdx] {
                        matchedCatIndex = cIdx
                        break
                    }
                }
                if matchedCatIndex != nil { break }
            }
        }

        guard let cIdx = matchedCatIndex else { return [] }

        // 2. Tìm chỉ số series `s` phù hợp
        var matchedSeriesIndex = 0
        if let sField = data.seriesField {
            if let sVal = point.values[sField.queryRef],
               let sIdx = data.series.firstIndex(of: sVal) {
                matchedSeriesIndex = sIdx
            }
        }

        // 3. Thêm các cấp Category theo `displayName`
        let catKey = data.categories[cIdx]
        for (lvlIdx, lvl) in data.categoryLevels.enumerated() {
            if lvlIdx < catKey.values.count {
                let v = catKey.values[lvlIdx]
                let text = NumberDisplay.plain(DataCell(v, formatString: lvl.formatString))
                rows.append(TooltipRow(name: lvl.displayName, value: text))
            }
        }

        // 4. Thêm Series nếu có
        if let sField = data.seriesField, matchedSeriesIndex < data.series.count {
            let sVal = data.series[matchedSeriesIndex]
            let text = NumberDisplay.plain(DataCell(sVal, formatString: sField.formatString))
            rows.append(TooltipRow(name: sField.displayName, value: text))
        }

        // 5. Thêm measure role "Y" hoặc "Values"
        for (mIdx, m) in data.measures.enumerated() {
            if m.role == "Y" || m.role == "Values" {
                let cell = data.cell(measure: mIdx, series: matchedSeriesIndex, category: cIdx)
                let text = NumberDisplay.plain(cell)
                rows.append(TooltipRow(name: m.displayName, value: text))
            }
        }

        // Điểm neo của dự báo (tháng cuối có dữ liệu): thêm dòng dự báo ngay sau giá trị thật, trước các measure Tooltips.
        if let forecast = forecastRows(point, data: data) { rows += forecast }

        // 6. Thêm các measure role "Tooltips" theo thứ tự trong visual
        for (mIdx, m) in data.measures.enumerated() {
            if m.role == "Tooltips" {
                let cell = data.cell(measure: mIdx, series: matchedSeriesIndex, category: cIdx)
                let text = NumberDisplay.plain(cell)
                rows.append(TooltipRow(name: m.displayName, value: text))
            }
        }

        return rows
    }
}

// MARK: - Tooltip View

private struct TooltipPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Mũi nhọn nhỏ ở cạnh trái chỉ sang trái
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct VisualTooltipView: View {
    let rows: [TooltipRow]
    /// Tooltip nằm bên trái điểm trỏ (gần mép phải visual): mũi nhọn ở cạnh phải.
    var pointerOnRight = false

    init(rows: [TooltipRow], pointerOnRight: Bool = false) {
        self.rows = rows
        self.pointerOnRight = pointerOnRight
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Mũi nhọn nhỏ ở cạnh trái (như tooltip-bar.png)
            if !pointerOnRight {
                TooltipPointerShape()
                    .fill(Color.white)
                    .frame(width: 7, height: 12)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: -1, y: 0)
            }

            // Khung nội dung
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 16) {
                        // Tên trường căn phải
                        Text(row.name)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(hex: "#252423") ?? .primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 90, alignment: .trailing)

                        // Giá trị căn trái, hai cột thẳng hàng
                        Text(row.value)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#252423") ?? .primary)
                            .frame(minWidth: 40, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.14), radius: 6, x: 2, y: 3)
            )
            if pointerOnRight {
                TooltipPointerShape()
                    .fill(Color.white)
                    .frame(width: 7, height: 12)
                    .scaleEffect(x: -1, y: 1)
            }
        }
    }
}
