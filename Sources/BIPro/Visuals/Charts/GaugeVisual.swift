import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

struct GaugeLayout: Equatable, Sendable {
    let value: Double
    let min: Double
    let max: Double
    let target: Double?
    let fillFraction: Double
    let targetFraction: Double?

    init(data: GaugeData) {
        let v = NumberDisplay.numericValue(data.value.value) ?? 0
        let lo = data.min.flatMap { NumberDisplay.numericValue($0.value) } ?? 0
        // VM-V11A (desktop-batch2-visuals.png): khi MaxValue trống, Power BI Desktop đặt Max = 2 × Value (5,369 → 0K..11K).
        let hi: Double
        if let explicitMax = data.max.flatMap({ NumberDisplay.numericValue($0.value) }) {
            hi = explicitMax
        } else if v > lo {
            hi = lo + 2.0 * (v - lo)
        } else if v < lo {
            hi = lo + abs(lo - v) * 2.0
        } else {
            hi = lo + 1.0
        }
        let safeHi = hi > lo ? hi : lo + 1.0
        let span = safeHi - lo

        self.value = v
        self.min = lo
        self.max = safeHi
        self.target = data.target.flatMap { NumberDisplay.numericValue($0.value) }
        self.fillFraction = Swift.min(1.0, Swift.max(0.0, (v - lo) / span))
        self.targetFraction = self.target.map { Swift.min(1.0, Swift.max(0.0, ($0 - lo) / span)) }
    }
}

struct GaugeVisualView: View {
    let data: GaugeData
    let context: VisualRenderContext

    private var layout: GaugeLayout { GaugeLayout(data: data) }

    var body: some View {
        let l = layout
        let accent = context.theme.dataColor(0)
        let trackColor = Color(hex: "#E6E6E6") ?? Color.gray.opacity(0.25)
        let labelColor = Color(hex: "#605E5C") ?? .secondary
        let valueColor = context.theme.color(context.format.dataLabels.color) ?? (Color(hex: "#252423") ?? .primary)

        let valueText = NumberDisplay.text(
            data.value,
            units: context.format.dataLabels.displayUnits,
            precision: context.format.dataLabels.precision,
            reference: l.max
        )
        let minText = NumberDisplay.text(
            DataCell(.double(l.min), formatString: data.min?.formatString ?? data.valueField.formatString),
            units: context.format.dataLabels.displayUnits,
            precision: 0,
            reference: l.max
        )
        let maxText = NumberDisplay.text(
            DataCell(.double(l.max), formatString: data.max?.formatString ?? data.valueField.formatString),
            units: context.format.dataLabels.displayUnits,
            precision: 0,
            reference: l.max
        )

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = Swift.max(20, Swift.min(w * 0.40, h * 0.62))
            let thickness = Swift.max(10, radius * 0.34)
            let center = CGPoint(x: w / 2, y: h * 0.72)

            ZStack {
                Canvas { ctx, _ in
                    // Background track 180° (π → 2π)
                    var track = Path()
                    track.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    ctx.stroke(track, with: .color(trackColor), style: StrokeStyle(lineWidth: thickness, lineCap: .butt))

                    // Value arc
                    if l.fillFraction > 0 {
                        let endDeg = 180.0 + l.fillFraction * 180.0
                        var fillPath = Path()
                        fillPath.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(endDeg), clockwise: false)
                        ctx.stroke(fillPath, with: .color(accent), style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                    }

                    // Target tick
                    if let tf = l.targetFraction {
                        let rad = (180.0 + tf * 180.0) * .pi / 180.0
                        let rIn = radius - thickness / 2 - 3
                        let rOut = radius + thickness / 2 + 5
                        var tick = Path()
                        tick.move(to: CGPoint(x: center.x + cos(rad) * rIn, y: center.y + sin(rad) * rIn))
                        tick.addLine(to: CGPoint(x: center.x + cos(rad) * rOut, y: center.y + sin(rad) * rOut))
                        ctx.stroke(tick, with: .color(Color(hex: "#252423") ?? .black), lineWidth: 2.2)
                    }
                }

                // Target value label
                if let tf = l.targetFraction, let targetCell = data.target {
                    let rad = (180.0 + tf * 180.0) * .pi / 180.0
                    let rLabel = radius + thickness / 2 + 16
                    let targetStr = NumberDisplay.text(targetCell, units: context.format.dataLabels.displayUnits,
                                                       precision: context.format.dataLabels.precision, reference: l.max)
                    Text(targetStr)
                        .font(.system(size: Swift.max(9, Swift.min(12, radius * 0.14)), weight: .semibold))
                        .foregroundStyle(Color(hex: "#252423") ?? .primary)
                        .fixedSize()
                        .position(x: center.x + cos(rad) * rLabel, y: center.y + sin(rad) * rLabel)
                }

                // Big callout value centered inside arc
                Text(valueText)
                    .font(.system(size: Swift.max(14, Swift.min(34, radius * 0.34)), weight: .semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: radius * 1.35)
                    .position(x: center.x, y: center.y - radius * 0.22)

                // Min & Max labels below arc ends
                Text(minText)
                    .font(.system(size: Swift.max(9, Swift.min(12, radius * 0.14))))
                    .foregroundStyle(labelColor)
                    .fixedSize()
                    .position(x: center.x - radius, y: center.y + 14)

                Text(maxText)
                    .font(.system(size: Swift.max(9, Swift.min(12, radius * 0.14))))
                    .foregroundStyle(labelColor)
                    .fixedSize()
                    .position(x: center.x + radius, y: center.y + 14)
            }
        }
        .padding(4)
    }
}
