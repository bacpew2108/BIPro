import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

/// Bộ đánh giá Định dạng có điều kiện (Conditional Formatting — Wave 3B / VM-V11B) dùng chung cho `TableVisualView` và `MatrixVisualView`.
/// Hỗ trợ đủ 4 kiểu: Rules (`Conditional`), Gradient (`FillRule`), Field value (`Measure`), và Data Bars (`columnFormatting.dataBars`).
enum CellFormatting {
    static func resolveColor(_ literal: ReportLiteral, theme: ReportTheme) -> Color? {
        if case .string(let s) = literal {
            switch s {
            case "maxColor": return theme.dataColor(0)
            case "minColor": return theme.badColor
            case "foreground": return theme.foregroundColor
            case "background": return theme.background.flatMap(Color.init(hex:)) ?? .white
            default: break
            }
        }
        return theme.color(literal)
    }

    static func evaluateConditionalColor(
        property: String,
        targetQueryRef: String,
        numericValue: Double?,
        minVal: Double?,
        maxVal: Double?,
        isTotal: Bool,
        cellOverrideHex: String?,
        format: VisualFormat,
        theme: ReportTheme
    ) -> Color? {
        // 1. Rules (`Conditional.Cases`, VM-V11B)
        if let num = numericValue,
           let rule = format.conditionalRules.first(where: { $0.property == property && ($0.target == nil || $0.target == targetQueryRef) }) {
            let applies = (rule.matchingOption == 2) || (rule.matchingOption == 1 && !isTotal) || (rule.matchingOption == 3 && isTotal)
            if applies {
                for c in rule.cases {
                    var ok = true
                    if let op = c.minOp, let rawMin = c.minValue {
                        let threshold: Double
                        if c.minIsPercent, let lo = minVal, let hi = maxVal {
                            threshold = lo + (hi - lo) * rawMin / 100.0
                        } else {
                            threshold = rawMin
                        }
                        if !op.matches(num, threshold) { ok = false }
                    }
                    if ok, let op = c.maxOp, let rawMax = c.maxValue {
                        let threshold: Double
                        if c.maxIsPercent, let lo = minVal, let hi = maxVal {
                            threshold = lo + (hi - lo) * rawMax / 100.0
                        } else {
                            threshold = rawMax
                        }
                        if !op.matches(num, threshold) { ok = false }
                    }
                    if ok, let color = resolveColor(c.color, theme: theme) {
                        return color
                    }
                }
            }
        }

        // 2. Field value (measure màu trực tiếp)
        if let hex = cellOverrideHex, let color = Color(hex: hex) {
            return color
        }

        // 3. Gradient (`FillRule` linearGradient2/3)
        if !isTotal,
           let rule = format.gradients.first(where: { $0.property == property && ($0.target == nil || $0.target == targetQueryRef) }),
           let lo = minVal, let hi = maxVal {
            return MatrixGradient.color(value: numericValue, min: lo, max: hi, rule: rule, theme: theme)
        }
        return nil
    }

    struct DataBarGeometry {
        let fraction: Double        // 0...1 độ rộng thanh
        let zeroPosition: Double    // 0...1 vị trí trục 0
        let isPositive: Bool
        let fillColor: Color
        let axisColor: Color
        let hideText: Bool
    }

    static func evaluateDataBar(
        targetQueryRef: String,
        numericValue: Double?,
        columnMin: Double,
        columnMax: Double,
        isTotal: Bool,
        format: VisualFormat,
        theme: ReportTheme
    ) -> DataBarGeometry? {
        guard let num = numericValue, num.isFinite,
              let rule = format.dataBars.first(where: { $0.target == targetQueryRef }) else { return nil }
        let applies = (rule.totalMatchingOption == 2) || (rule.totalMatchingOption == 1 && !isTotal)
        guard applies else { return nil }
        let lo = min(rule.minValue ?? min(0, columnMin), 0)
        let hi = max(rule.maxValue ?? max(0, columnMax), 0)
        let span = hi - lo
        guard span > 1e-12 else { return nil }
        let zeroPos = (0 - lo) / span
        let clamped = max(lo, min(hi, num))
        let frac = abs(clamped) / span
        let posColor = resolveColor(rule.positiveColor, theme: theme) ?? theme.dataColor(0)
        let negColor = resolveColor(rule.negativeColor, theme: theme) ?? theme.badColor
        let axisColor = resolveColor(rule.axisColor, theme: theme) ?? theme.foregroundColor.opacity(0.4)
        return DataBarGeometry(
            fraction: frac,
            zeroPosition: zeroPos,
            isPositive: clamped >= 0,
            fillColor: (clamped >= 0 ? posColor : negColor).opacity(0.32),
            axisColor: axisColor,
            hideText: rule.hideText
        )
    }

    @ViewBuilder
    static func dataBarOverlay(_ bar: DataBarGeometry?) -> some View {
        if let bar {
            GeometryReader { geo in
                let w = max(0, geo.size.width - 8)
                let zeroX = 4 + CGFloat(bar.zeroPosition) * w
                let barW = max(1, CGFloat(bar.fraction) * w)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(bar.fillColor)
                        .frame(width: barW, height: max(4, geo.size.height - 6))
                        .offset(x: bar.isPositive ? zeroX : max(4, zeroX - barW))
                    if bar.zeroPosition > 0.001 && bar.zeroPosition < 0.999 {
                        Rectangle()
                            .fill(bar.axisColor.opacity(0.45))
                            .frame(width: 1, height: geo.size.height)
                            .offset(x: zeroX)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .allowsHitTesting(false)
        }
    }
}
