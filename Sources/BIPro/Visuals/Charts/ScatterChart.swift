import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

struct ScatterLayout: Sendable {
    struct Bubble: Identifiable, Sendable {
        var id: Int
        var point: ScatterPoint
        var xNorm: Double
        var yNorm: Double
        var radius: CGFloat
        var colorIndex: Int
    }

    let xTicks: [Double]
    let xLabels: [String]
    let xDomain: ClosedRange<Double>
    let yTicks: [Double]
    let yLabels: [String]
    let yDomain: ClosedRange<Double>
    let is1D: Bool
    let bubbles: [Bubble]

    init(data: ScatterData, format: VisualFormat) {
        let is1D = (data.yField == nil)
        self.is1D = is1D

        let xs = data.points.map(\.x).filter(\.isFinite)
        let ys = data.points.map(\.y).filter(\.isFinite)

        let rawXMin = xs.min() ?? 0
        let rawXMax = xs.max() ?? 1
        let xSpan = max(abs(rawXMax - rawXMin), abs(rawXMax) * 0.1, 1.0)
        let xTicks = ChartAxis.niceTicks(min: rawXMin - xSpan * 0.05, max: rawXMax + xSpan * 0.05, targetCount: 5)
        self.xTicks = xTicks
        self.xLabels = ChartAxis.labels(ticks: xTicks, units: format.valueAxis.displayUnits, precision: format.valueAxis.precision,
                                        formatString: data.xField?.formatString ?? "")
        let xLo = xTicks.first ?? rawXMin
        let xHi = max(xLo + 1e-9, xTicks.last ?? rawXMax)
        self.xDomain = xLo...xHi

        if is1D {
            self.yTicks = []
            self.yLabels = []
            self.yDomain = -1...1
        } else {
            let rawYMin = ys.min() ?? 0
            let rawYMax = ys.max() ?? 1
            let ySpan = max(abs(rawYMax - rawYMin), abs(rawYMax) * 0.1, 1.0)
            let yTicks = ChartAxis.niceTicks(min: rawYMin - ySpan * 0.05, max: rawYMax + ySpan * 0.05, targetCount: 5)
            self.yTicks = yTicks
            self.yLabels = ChartAxis.labels(ticks: yTicks, units: format.valueAxis.displayUnits, precision: format.valueAxis.precision,
                                            formatString: data.yField?.formatString ?? "")
            let yLo = yTicks.first ?? rawYMin
            let yHi = max(yLo + 1e-9, yTicks.last ?? rawYMax)
            self.yDomain = yLo...yHi
        }

        let sizes = data.points.compactMap(\.size).filter { $0.isFinite && $0 >= 0 }
        let minS = sizes.min() ?? 0
        let maxS = sizes.max() ?? 0
        let seriesIndexOf: [Value: Int] = Dictionary(data.series.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

        let yLo = self.yDomain.lowerBound
        let yHi = self.yDomain.upperBound
        self.bubbles = data.points.enumerated().map { idx, pt in
            let xn = min(1, max(0, (pt.x - xLo) / (xHi - xLo)))
            let yn = is1D ? 0.5 : min(1, max(0, (pt.y - yLo) / (yHi - yLo)))
            let r: CGFloat
            if let s = pt.size, s.isFinite, s >= 0, maxS > minS {
                let t = sqrt((s - minS) / (maxS - minS))
                r = CGFloat(4.5 + t * 16.5)
            } else if pt.size != nil {
                r = 8.0
            } else {
                r = 5.5
            }
            let cIdx = pt.seriesValue.flatMap { seriesIndexOf[$0] } ?? 0
            return Bubble(id: idx, point: pt, xNorm: xn, yNorm: yn, radius: r, colorIndex: cIdx)
        }
    }
}

struct ScatterChartView: View {
    let data: ScatterData
    let context: VisualRenderContext
    let interactive: Bool

    @State private var hoveredID: Int? = nil
    @State private var hoverLocation: CGPoint = .zero

    private var layout: ScatterLayout { ScatterLayout(data: data, format: context.format) }

    private var legendItems: [LegendItem] {
        guard let serField = data.seriesField, !data.series.isEmpty else { return [] }
        return data.series.enumerated().map { idx, val in
            LegendItem(id: "s-\(idx)", name: serField.text(val), color: context.theme.dataColor(idx))
        }
    }

    var body: some View {
        let l = layout
        if data.points.isEmpty {
            ZStack {
                Color.clear
                Text(bi("Không có dữ liệu", "No data"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            let showLegend = (context.format.legend.show ?? true) && !legendItems.isEmpty
            VStack(spacing: 4) {
                if showLegend {
                    ChartLegendView(items: legendItems, position: context.format.legend.position ?? "Top",
                                    fontSize: context.format.legend.fontSize)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                }
                plotArea(l)
            }
            .padding(4)
        }
    }

    private func plotArea(_ l: ScatterLayout) -> some View {
        let leftMargin: CGFloat = l.is1D ? 16 : 52
        let bottomMargin: CGFloat = 34
        let topMargin: CGFloat = 12
        let rightMargin: CGFloat = 16
        let labelFont = ReportUnits.pixels(fromPoints: context.format.categoryAxis.fontSize ?? 9)

        return GeometryReader { geo in
            let plotW = max(20, geo.size.width - leftMargin - rightMargin)
            let plotH = max(20, geo.size.height - topMargin - bottomMargin)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let gridColor = Color.gray.opacity(0.20)
                    let axisColor = Color.gray.opacity(0.45)

                    // Vertical gridlines (X ticks)
                    for tick in l.xTicks {
                        let frac = (tick - l.xDomain.lowerBound) / max(1e-9, l.xDomain.upperBound - l.xDomain.lowerBound)
                        let x = leftMargin + CGFloat(frac) * plotW
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: topMargin))
                        p.addLine(to: CGPoint(x: x, y: topMargin + plotH))
                        ctx.stroke(p, with: .color(gridColor), lineWidth: 0.6)
                    }

                    // Horizontal gridlines (Y ticks) or 1D center line
                    if l.is1D {
                        var p = Path()
                        let midY = topMargin + plotH / 2
                        p.move(to: CGPoint(x: leftMargin, y: midY))
                        p.addLine(to: CGPoint(x: leftMargin + plotW, y: midY))
                        ctx.stroke(p, with: .color(axisColor), lineWidth: 0.8)
                    } else {
                        for tick in l.yTicks {
                            let frac = (tick - l.yDomain.lowerBound) / max(1e-9, l.yDomain.upperBound - l.yDomain.lowerBound)
                            let y = topMargin + (1 - CGFloat(frac)) * plotH
                            var p = Path()
                            p.move(to: CGPoint(x: leftMargin, y: y))
                            p.addLine(to: CGPoint(x: leftMargin + plotW, y: y))
                            ctx.stroke(p, with: .color(gridColor), lineWidth: 0.6)
                        }
                    }

                    // Bubbles
                    for b in l.bubbles {
                        let cx = leftMargin + CGFloat(b.xNorm) * plotW
                        let cy = topMargin + (1 - CGFloat(b.yNorm)) * plotH
                        let selected = context.selection.isEmpty || context.selection.contains(b.point.id)
                        let col = context.theme.dataColor(b.colorIndex)
                        let rect = CGRect(x: cx - b.radius, y: cy - b.radius, width: b.radius * 2, height: b.radius * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(col.opacity(selected ? 0.78 : 0.25)))
                        ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(selected ? 1.0 : 0.35)),
                                   lineWidth: hoveredID == b.id ? 2 : 1)
                    }
                }

                // X tick labels
                ForEach(Array(zip(l.xTicks, l.xLabels).enumerated()), id: \.offset) { _, pair in
                    let frac = (pair.0 - l.xDomain.lowerBound) / max(1e-9, l.xDomain.upperBound - l.xDomain.lowerBound)
                    let x = leftMargin + CGFloat(frac) * plotW
                    Text(pair.1)
                        .font(.system(size: labelFont).monospacedDigit())
                        .foregroundStyle(Color(hex: "#605E5C") ?? .secondary)
                        .fixedSize()
                        .position(x: x, y: topMargin + plotH + 10)
                }
                if let xTitle = data.xField?.displayName {
                    Text(xTitle)
                        .font(.system(size: labelFont, weight: .medium))
                        .foregroundStyle(Color(hex: "#252423") ?? .primary)
                        .lineLimit(1)
                        .position(x: leftMargin + plotW / 2, y: topMargin + plotH + 24)
                }

                // Y tick labels
                if !l.is1D {
                    ForEach(Array(zip(l.yTicks, l.yLabels).enumerated()), id: \.offset) { _, pair in
                        let frac = (pair.0 - l.yDomain.lowerBound) / max(1e-9, l.yDomain.upperBound - l.yDomain.lowerBound)
                        let y = topMargin + (1 - CGFloat(frac)) * plotH
                        Text(pair.1)
                            .font(.system(size: labelFont).monospacedDigit())
                            .foregroundStyle(Color(hex: "#605E5C") ?? .secondary)
                            .lineLimit(1)
                            .frame(width: leftMargin - 8, alignment: .trailing)
                            .position(x: (leftMargin - 8) / 2, y: y)
                    }
                }

                // Hover tooltip
                if interactive, let hid = hoveredID, hid < l.bubbles.count {
                    let pt = l.bubbles[hid].point
                    tooltipCard(for: pt)
                        .fixedSize()
                        .position(
                            x: min(max(90, hoverLocation.x + (hoverLocation.x > geo.size.width * 0.6 ? -90 : 90)), geo.size.width - 90),
                            y: min(max(36, hoverLocation.y - 24), geo.size.height - 36)
                        )
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                guard interactive else { return }
                let hit = nearestBubble(at: loc, layout: l, left: leftMargin, top: topMargin, plotW: plotW, plotH: plotH)
                let additive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
                context.actions.select(hit?.point.id, additive)
            }
            .onContinuousHover { phase in
                guard interactive else { return }
                switch phase {
                case .active(let loc):
                    hoverLocation = loc
                    hoveredID = nearestBubble(at: loc, layout: l, left: leftMargin, top: topMargin, plotW: plotW, plotH: plotH)?.id
                case .ended:
                    hoveredID = nil
                }
            }
        }
    }

    private func nearestBubble(at loc: CGPoint, layout: ScatterLayout, left: CGFloat, top: CGFloat, plotW: CGFloat, plotH: CGFloat) -> ScatterLayout.Bubble? {
        var best: (bubble: ScatterLayout.Bubble, dist: CGFloat)? = nil
        for b in layout.bubbles {
            let cx = left + CGFloat(b.xNorm) * plotW
            let cy = top + (1 - CGFloat(b.yNorm)) * plotH
            let d = hypot(loc.x - cx, loc.y - cy)
            if d <= max(b.radius + 6, 12), best == nil || d < best!.dist {
                best = (b, d)
            }
        }
        return best?.bubble
    }

    private func tooltipCard(for pt: ScatterPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !pt.categoryLabel.isEmpty {
                Text(pt.categoryLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
            if let ser = data.seriesField, let v = pt.seriesValue {
                Text("\(ser.displayName): \(ser.text(v))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
            }
            if let xf = data.xField {
                Text("\(xf.displayName): \(NumberDisplay.plain(pt.xCell))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
            }
            if let yf = data.yField {
                Text("\(yf.displayName): \(NumberDisplay.plain(pt.yCell))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
            }
            if let sf = data.sizeField, let sc = pt.sizeCell {
                Text("\(sf.displayName): \(NumberDisplay.plain(sc))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
            }
            ForEach(Array(pt.tooltips.enumerated()), id: \.offset) { _, tip in
                Text("\(tip.label): \(NumberDisplay.plain(tip.cell))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#333333") ?? Color.black.opacity(0.85)))
    }
}
