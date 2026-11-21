import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

struct KPILayout: Equatable, Sendable {
    enum Status: Equatable, Sendable { case good, bad, neutral }

    let status: Status
    let deltaPercent: Double?

    init(data: KPIData) {
        if let latest = NumberDisplay.numericValue(data.latestValue.value),
           let goal = data.goalValue.flatMap({ NumberDisplay.numericValue($0.value) }) {
            self.status = latest >= goal ? .good : .bad
            self.deltaPercent = abs(goal) > 1e-12 ? ((latest - goal) / abs(goal)) * 100.0 : nil
        } else {
            self.status = .neutral
            self.deltaPercent = nil
        }
    }
}

struct KPIVisualView: View {
    let data: KPIData
    let context: VisualRenderContext

    private var layout: KPILayout { KPILayout(data: data) }

    var body: some View {
        let l = layout
        let statusColor: Color = switch l.status {
        case .good: Color(hex: "#107C10") ?? .green
        case .bad: Color(hex: "#D13438") ?? .red
        case .neutral: context.theme.dataColor(0)
        }
        let valueStr = data.latestValue.value == .blank
            ? "(Trống)"
            : NumberDisplay.text(data.latestValue, units: context.format.dataLabels.displayUnits, precision: context.format.dataLabels.precision)

        GeometryReader { geo in
            ZStack {
                // Sparkline area in background (VM-V11A desktop-batch2-visuals.png)
                if data.trendPoints.count >= 2 {
                    Canvas { ctx, size in
                        let vals = data.trendPoints.map(\.value)
                        let lo = vals.min() ?? 0
                        let hi = vals.max() ?? 1
                        let span = max(1e-9, hi - lo)
                        let topY = size.height * 0.42
                        let botY = size.height - 4
                        let chartH = max(10, botY - topY)

                        var area = Path()
                        var line = Path()
                        for (idx, pt) in data.trendPoints.enumerated() {
                            let x = size.width * CGFloat(idx) / CGFloat(max(1, data.trendPoints.count - 1))
                            let y = botY - CGFloat((pt.value - lo) / span) * chartH
                            if idx == 0 {
                                area.move(to: CGPoint(x: x, y: botY))
                                area.addLine(to: CGPoint(x: x, y: y))
                                line.move(to: CGPoint(x: x, y: y))
                            } else {
                                area.addLine(to: CGPoint(x: x, y: y))
                                line.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        area.addLine(to: CGPoint(x: size.width, y: botY))
                        area.closeSubpath()
                        ctx.fill(area, with: .color(statusColor.opacity(0.18)))
                        ctx.stroke(line, with: .color(statusColor.opacity(0.45)), lineWidth: 1.8)
                    }
                }

                VStack(spacing: 4) {
                    Text(valueStr)
                        .font(.system(size: min(40, max(18, geo.size.height * 0.24)), weight: .bold))
                        .foregroundStyle(l.status == .neutral ? (Color(hex: "#252423") ?? .primary) : statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)

                    if let goalCell = data.goalValue, goalCell.value != .blank {
                        let goalStr = NumberDisplay.text(goalCell, units: context.format.dataLabels.displayUnits,
                                                         precision: context.format.dataLabels.precision)
                        HStack(spacing: 4) {
                            Text("\(bi("Mục tiêu", "Goal")): \(goalStr)")
                                .foregroundStyle(Color(hex: "#605E5C") ?? .secondary)
                            if let pct = l.deltaPercent {
                                let sign = pct >= 0 ? "+" : ""
                                Text("(\(sign)\(NumberDisplay.decimal(pct, precision: 1))%)")
                                    .foregroundStyle(statusColor)
                                    .fontWeight(.semibold)
                            }
                        }
                        .font(.system(size: min(13, max(10, geo.size.height * 0.08))))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    } else if let lastTrend = data.trendPoints.last {
                        Text(lastTrend.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#605E5C") ?? .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
