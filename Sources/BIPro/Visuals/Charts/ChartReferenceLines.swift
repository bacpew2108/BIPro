import Charts
import Foundation
import PBIXKit
import SwiftUI

/// Đường tham chiếu Analytics tính sẵn toạ độ Y để vẽ trực tiếp trên Swift Charts (`CartesianChart` / `ComboChart`).
struct ResolvedReferenceLine: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let value: Double
    let colorHex: String?
    let style: AnalyticsLineStyle
    let opacity: Double
}

enum ChartReferenceLines {
    /// Giải toàn bộ `constantLines` (`y1AxisReferenceLine`) và `dynamicLines` (`referenceLine` Average/Min/Max)
    /// thành danh sách đường tham chiếu có giá trị số thực từ tập dữ liệu đang vẽ.
    static func resolve(format: AnalyticsFormat, values: [Double]) -> [ResolvedReferenceLine] {
        var out: [ResolvedReferenceLine] = []
        for line in format.constantLines where line.show {
            let hex: String? = {
                if case .string(let s) = line.color { return s }
                return nil
            }()
            out.append(ResolvedReferenceLine(
                id: "const-\(line.id)",
                label: line.displayName,
                value: line.value,
                colorHex: hex,
                style: line.style,
                opacity: max(0.1, min(1.0, 1.0 - line.transparency / 100.0))
            ))
        }
        let finite = values.filter(\.isFinite)
        if !finite.isEmpty {
            for line in format.dynamicLines where line.show {
                let y: Double
                switch line.kind {
                case .average: y = finite.reduce(0, +) / Double(finite.count)
                case .min: y = finite.min() ?? 0
                case .max: y = finite.max() ?? 0
                }
                let hex: String? = {
                    if case .string(let s) = line.color { return s }
                    return nil
                }()
                out.append(ResolvedReferenceLine(
                    id: "dyn-\(line.id)",
                    label: line.displayName,
                    value: y,
                    colorHex: hex,
                    style: line.style,
                    opacity: 0.9
                ))
            }
        }
        return out
    }

    static func strokeStyle(_ style: AnalyticsLineStyle) -> StrokeStyle {
        switch style {
        case .solid: StrokeStyle(lineWidth: 1.4)
        case .dashed: StrokeStyle(lineWidth: 1.4, dash: [5, 3])
        case .dotted: StrokeStyle(lineWidth: 1.4, dash: [2, 2])
        }
    }

    @ChartContentBuilder
    static func chartMarks(lines: [ResolvedReferenceLine], theme: ReportTheme) -> some ChartContent {
        ForEach(lines) { line in
            let color = (line.colorHex.flatMap(Color.init(hex:)) ?? theme.dataColor(1)).opacity(line.opacity)
            RuleMark(y: .value(line.label, line.value))
                .foregroundStyle(color)
                .lineStyle(strokeStyle(line.style))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text("\(line.label): \(NumberDisplay.text(DataCell(.double(line.value))))")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(color)
                        .padding(.horizontal, 3)
                        .background(Color.white.opacity(0.85))
                }
        }
    }
}
