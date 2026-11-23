import DAXEngine
import Foundation
import SwiftUI

// Biểu đồ thác nước (VM-D15 mục 4, hình mẫu Desktop): mỗi danh mục là một cột trôi từ mức cộng dồn trước đó; giá trị dương tô màu
// "tăng" (`good` của theme), âm tô "giảm" (`bad`), thêm cột "Total" cuối cùng từ 0 đến tổng (màu dữ liệu đầu). Vạch nối mảnh giữa
// các cột, chú giải Increase, Decrease, Total ở đáy. Ô Breakdown của Desktop chưa vẽ.

struct WaterfallBar: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case increase, decrease, total }
    /// Chỉ số danh mục trong dữ liệu; -1 cho cột Total.
    var index: Int
    var category: String
    var kind: Kind
    var value: Double
    /// Hai đầu của cột trên trục Y (`start` là mức trước, `end` là mức sau).
    var start: Double
    var end: Double
    /// Phần tử Breakdown của cột chênh lệch (chỉ số trong `CategoricalData.series`); nil với cột danh mục.
    var breakdown: Int? = nil

    var low: Double { Swift.min(start, end) }
    var high: Double { Swift.max(start, end) }
}

enum WaterfallLayout {
    /// Các cột theo thứ tự dữ liệu rồi cột Total. Ô trống không có cột (Desktop bỏ danh mục không có giá trị).
    static func bars(values: [Double?], names: [String], totalName: String = "Total") -> [WaterfallBar] {
        var bars: [WaterfallBar] = []
        var running = 0.0
        for (index, value) in values.enumerated() {
            guard let value, value.isFinite else { continue }
            bars.append(WaterfallBar(index: index, category: index < names.count ? names[index] : "", kind: value >= 0 ? .increase : .decrease,
                                     value: value, start: running, end: running + value))
            running += value
        }
        guard !bars.isEmpty else { return [] }
        bars.append(WaterfallBar(index: -1, category: totalName, kind: .total, value: running, start: 0, end: running))
        return bars
    }
}

extension WaterfallLayout {
    /// Có ô Breakdown (VM-D16 mục 3, Desktop): mỗi danh mục là một cột Total (từ 0 đến tổng các phần tử), rồi các cột chênh lệch của từng
    /// phần tử Breakdown giữa danh mục này và danh mục kế, trôi từ tổng danh mục này xuống đúng tổng danh mục kế; chênh lệch xếp
    /// giảm dần. Danh mục cuối chỉ có cột Total. `values[c][b]`: danh mục `c`, phần tử `b`; ô trống tính 0 ở chênh lệch.
    static func bars(values: [[Double?]], categoryNames: [String], breakdownNames: [String]) -> [WaterfallBar] {
        let totals = values.map { $0.reduce(0.0) { $0 + ($1 ?? 0) } }
        var bars: [WaterfallBar] = []
        for category in values.indices {
            let name = category < categoryNames.count ? categoryNames[category] : ""
            bars.append(WaterfallBar(index: category, category: name, kind: .total, value: totals[category], start: 0, end: totals[category]))
            guard category + 1 < values.count else { continue }
            let changes = breakdownNames.indices.map { b -> (b: Int, delta: Double) in
                let next = b < values[category + 1].count ? values[category + 1][b] ?? 0 : 0
                let current = b < values[category].count ? values[category][b] ?? 0 : 0
                return (b, next - current)
            }.sorted { $0.delta != $1.delta ? $0.delta > $1.delta : $0.b < $1.b }
            var running = totals[category]
            for change in changes {
                bars.append(WaterfallBar(index: category, category: breakdownNames[change.b], kind: change.delta >= 0 ? .increase : .decrease,
                                         value: change.delta, start: running, end: running + change.delta, breakdown: change.b))
                running += change.delta
            }
        }
        return bars
    }
}

struct WaterfallChartView: View {
    let data: CategoricalData
    let context: VisualRenderContext
    let interactive: Bool

    init(data: CategoricalData, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.context = context
        self.interactive = interactive
    }

    private var measureIndex: Int { data.measureIndices(role: "Y").first ?? 0 }

    private var hasBreakdown: Bool { data.seriesField != nil && !data.series.isEmpty }

    private var bars: [WaterfallBar] {
        guard measureIndex < data.measures.count else { return [] }
        if hasBreakdown {
            let grid = data.categories.indices.map { c in
                data.series.indices.map { s in chartNumber(data.cell(measure: measureIndex, series: s, category: c)) }
            }
            return WaterfallLayout.bars(values: grid, categoryNames: chartCategoryNames(data),
                                        breakdownNames: data.series.map { data.seriesField?.text($0) ?? $0.asText() })
        }
        let values = data.categories.indices.map { chartNumber(data.cell(measure: measureIndex, series: 0, category: $0)) }
        return WaterfallLayout.bars(values: values, names: chartCategoryNames(data))
    }

    private func color(_ kind: WaterfallBar.Kind) -> Color {
        switch kind {
        case .increase: context.theme.goodColor
        case .decrease: context.theme.badColor
        case .total: context.theme.dataColor(0)
        }
    }

    private var legend: [LegendItem] {
        [LegendItem(id: "inc", name: "Increase", color: color(.increase)), LegendItem(id: "dec", name: "Decrease", color: color(.decrease)),
         LegendItem(id: "tot", name: "Total", color: color(.total))]
            + (hasBreakdown ? [LegendItem(id: "oth", name: "Other", color: context.theme.neutralColor)] : [])
    }

    private struct Slot {
        var bar: WaterfallBar
        var rect: CGRect
        var id: DataPointID?
    }

    var body: some View {
        let bars = bars
        if bars.isEmpty {
            ZStack { Color.clear; Text(bi("Không có dữ liệu", "No data")).font(.system(size: 11)).foregroundColor(.secondary) }
        } else {
            VStack(spacing: 4) {
                GeometryReader { geo in plot(bars, size: geo.size) }
                ChartLegendView(items: legend, position: "BottomLeft", fontSize: context.format.legend.fontSize)
                    .padding(.horizontal, 6).padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func plot(_ bars: [WaterfallBar], size: CGSize) -> some View {
        let fontSize = ReportUnits.pixels(fromPoints: context.format.categoryAxis.fontSize ?? ChartDefaults.axisFontSize)
        let formatString = data.measures[measureIndex].formatString
        let scale = ValueAxisScale(low: Swift.min(0, bars.map(\.low).min() ?? 0), high: Swift.max(0, bars.map(\.high).max() ?? 1),
                                   format: context.format, formatString: formatString)
        let labelRoom = fontSize * 2.2
        let left = scale.labelWidth(fontSize: fontSize)
        let plot = CGRect(x: left, y: 6, width: Swift.max(1, size.width - left - 6), height: Swift.max(1, size.height - 6 - labelRoom))
        let slotWidth = plot.width / CGFloat(bars.count)
        let barWidth = slotWidth * 0.72
        let slots: [Slot] = bars.enumerated().map { order, bar in
            let top = plot.minY + scale.y(bar.high, height: plot.height)
            let bottom = plot.minY + scale.y(bar.low, height: plot.height)
            let rect = CGRect(x: plot.minX + slotWidth * (CGFloat(order) + 0.5) - barWidth / 2, y: top, width: barWidth,
                              height: Swift.max(1, bottom - top))
            return Slot(bar: bar, rect: rect, id: bar.index >= 0 ? chartPointID(data: data, category: bar.index, series: bar.breakdown) : nil)
        }
        // Nhãn danh mục xoay khi hẹp, như biểu đồ cột.
        let longest = bars.map { $0.category.count }.max() ?? 0
        let flatFootprint = CGFloat(longest) * fontSize * 0.6 + 4
        let rotate = flatFootprint > slotWidth
        // Desktop không bỏ nhãn: xoay -45° và thu nhỏ chữ cho vừa (VM-D16 mục 4, 73 danh mục đều có nhãn).
        let labelFont = rotate ? Swift.max(6, Swift.min(fontSize, slotWidth * 1.1)) : fontSize
        let labelStride = ChartLabelDensity.stride(footprint: rotate ? labelFont * 0.85 : flatFootprint, slot: slotWidth)
        let content = ZStack(alignment: .topLeading) {
            ValueAxisGrid(scale: scale, plot: plot, fontSize: fontSize)
            ForEach(Array(slots.enumerated()), id: \.offset) { order, slot in
                if order + 1 < slots.count {
                    let level = plot.minY + scale.y(slot.bar.end, height: plot.height)
                    Path { path in
                        path.move(to: CGPoint(x: slot.rect.maxX, y: level))
                        path.addLine(to: CGPoint(x: slots[order + 1].rect.minX, y: level))
                    }
                    .stroke(Color.gray.opacity(0.55), lineWidth: 0.8)
                }
                Rectangle().fill(color(slot.bar.kind))
                    .opacity(slot.id.map { context.selection.isEmpty || context.selection.contains($0) ? 1.0 : 0.4 } ?? 1.0)
                    .frame(width: slot.rect.width, height: slot.rect.height)
                    .position(x: slot.rect.midX, y: slot.rect.midY)
                if order % labelStride == 0 || order == slots.count - 1 && labelStride == 1 {
                    categoryLabel(slot.bar.category, fontSize: labelFont, rotate: rotate, slotWidth: slotWidth)
                        .position(x: slot.rect.midX, y: plot.maxY + labelRoom * (rotate ? 0.5 : 0.4) + (rotate ? 4 : 0))
                }
                if context.format.dataLabels.show == true {
                    Text(NumberDisplay.text(DataCell(.double(slot.bar.value), formatString: formatString),
                                            units: context.format.dataLabels.displayUnits, precision: context.format.dataLabels.precision,
                                            reference: scale.upper))
                        .font(.system(size: fontSize)).foregroundColor(context.theme.foregroundColor).lineLimit(1)
                        .position(x: slot.rect.midX, y: slot.rect.minY - fontSize)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()   // miền trục do người dùng đặt (Lớn nhất) có thể nhỏ hơn dữ liệu: không vẽ ra ngoài khung
        .contentShape(Rectangle())
        if interactive {
            content
                .onTapGesture { location in
                    context.actions.select(slots.first { hit($0, location, plot: plot) }?.id,
                                           NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control))
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): context.actions.hover(slots.first { hit($0, location, plot: plot) }?.id, location)
                    case .ended: context.actions.hover(nil, .zero)
                    }
                }
        } else {
            content
        }
    }

    private func hit(_ slot: Slot, _ location: CGPoint, plot: CGRect) -> Bool {
        slot.rect.insetBy(dx: -(slot.rect.width * 0.15), dy: 0).contains(CGPoint(x: location.x, y: Swift.min(Swift.max(location.y, slot.rect.minY), slot.rect.maxY)))
            && location.y >= plot.minY && location.y <= plot.maxY
    }

    @ViewBuilder
    private func categoryLabel(_ text: String, fontSize: CGFloat, rotate: Bool, slotWidth: CGFloat) -> some View {
        let label = Text(text).font(.system(size: fontSize)).foregroundColor(Color(hex: "#605E5C") ?? .secondary).lineLimit(1)
        if rotate {
            label.fixedSize().rotationEffect(.degrees(-45))
        } else {
            label.frame(width: slotWidth)
        }
    }
}
