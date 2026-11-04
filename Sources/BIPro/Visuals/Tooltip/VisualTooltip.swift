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
    /// Thứ tự: các cấp Category (và Series nếu có) của điểm, rồi measure role "Y"/"Values", rồi các "Tooltips" theo thứ tự trong visual.
    /// Giá trị theo định dạng của measure, không đổi đơn vị (qua `NumberDisplay.plain`).
    static func rows(for point: DataPointID, in data: CategoricalData) -> [TooltipRow] {
        var rows: [TooltipRow] = []

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

    init(rows: [TooltipRow]) {
        self.rows = rows
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Mũi nhọn nhỏ ở cạnh trái (như tooltip-bar.png)
            TooltipPointerShape()
                .fill(Color.white)
                .frame(width: 7, height: 12)
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: -1, y: 0)

            // Khung nội dung
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 16) {
                        // Tên trường căn phải
                        Text(row.name)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(hex: "#252423") ?? .primary)
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
        }
    }
}
