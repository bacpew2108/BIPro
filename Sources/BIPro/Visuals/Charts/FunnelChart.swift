import DAXEngine
import Foundation
import SwiftUI

// Biểu đồ phễu (VM-D15 mục 4, hình mẫu Desktop: `docs/phase-d-evidence/vm-d15/QUAN-SAT.md`): thanh ngang căn giữa, rộng theo giá trị
// so với thanh lớn nhất, nhãn danh mục bên trái, giá trị trắng giữa thanh, "100%" trên thanh đầu và phần trăm của thanh cuối so với
// thanh đầu ở dưới (có vạch ngoặc). Thứ tự là thứ tự của dữ liệu (truy vấn đã sắp giá trị giảm dần khi chưa có `sortDefinition`).

struct FunnelBar: Hashable, Sendable {
    var index: Int
    var category: String
    var value: Double
    /// Độ rộng so với thanh lớn nhất (0...1).
    var fraction: Double
    /// Giá trị so với thanh đầu tiên.
    var percentOfFirst: Double
}

enum FunnelLayout {
    /// Các thanh theo đúng thứ tự dữ liệu; ô trống hoặc số âm bị bỏ (Desktop không vẽ thanh rộng âm).
    static func bars(values: [Double?], names: [String]) -> [FunnelBar] {
        let kept: [(index: Int, value: Double)] = values.enumerated().compactMap { index, value in
            guard let value, value >= 0, value.isFinite else { return nil }
            return (index, value)
        }
        guard let first = kept.first?.value, let top = kept.map(\.value).max() else { return [] }
        return kept.map { item in
            FunnelBar(index: item.index, category: item.index < names.count ? names[item.index] : "", value: item.value,
                      fraction: top > 0 ? item.value / top : 0, percentOfFirst: first > 0 ? item.value / first : 0)
        }
    }

    /// "100%", "12.5%": tối đa một chữ số thập phân, bỏ ".0".
    static func percentText(_ fraction: Double) -> String {
        let percent = fraction * 100
        let rounded = (percent * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))%" : String(format: "%.1f%%", rounded)
    }
}

struct FunnelChartView: View {
    let data: CategoricalData
    let context: VisualRenderContext
    let interactive: Bool

    init(data: CategoricalData, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.context = context
        self.interactive = interactive
    }

    private var measureIndex: Int {
        data.measureIndices(role: "Y").first ?? data.measureIndices(role: "Values").first ?? 0
    }

    private var names: [String] {
        data.categories.map { key in key.values.enumerated().map { data.categoryLevels.text($1, at: $0) }.joined(separator: " ") }
    }

    private var bars: [FunnelBar] {
        guard measureIndex < data.measures.count else { return [] }
        let values = data.categories.indices.map { NumberDisplay.numericValue(data.cell(measure: measureIndex, series: 0, category: $0).value) }
        return FunnelLayout.bars(values: values, names: names)
    }

    private func pointID(_ index: Int) -> DataPointID {
        var dict: [String: Value] = [:]
        if index < data.categories.count {
            for (level, field) in data.categoryLevels.enumerated() where level < data.categories[index].values.count {
                dict[field.queryRef] = data.categories[index].values[level]
            }
        }
        return DataPointID(dict)
    }

    private struct Row {
        var bar: FunnelBar
        var rect: CGRect
        var color: Color
        var opacity: Double
        var label: String
        var id: DataPointID
    }

    private func rows(in size: CGSize, labelWidth: CGFloat) -> (rows: [Row], plot: CGRect) {
        let bars = bars
        guard !bars.isEmpty else { return ([], .zero) }
        let fontSize = ReportUnits.pixels(fromPoints: context.format.categoryLabels.fontSize ?? 9)
        let topPad = fontSize * 2.6
        let plot = CGRect(x: labelWidth, y: 0, width: Swift.max(1, size.width - labelWidth - 6), height: size.height)
        let available = Swift.max(1, size.height - topPad * 2)
        let pitch = Swift.min(38, available / CGFloat(bars.count))
        let barHeight = pitch * 0.86
        let blockHeight = pitch * CGFloat(bars.count)
        let originY = (size.height - blockHeight) / 2
        let mField = data.measures[measureIndex]
        return (bars.enumerated().map { order, bar in
            let width = plot.width * CGFloat(bar.fraction)
            let rect = CGRect(x: plot.minX + (plot.width - width) / 2, y: originY + CGFloat(order) * pitch + (pitch - barHeight) / 2,
                              width: width, height: barHeight)
            let cell = data.cell(measure: measureIndex, series: 0, category: bar.index)
            let key = bar.index < data.categories.count ? data.categories[bar.index] : nil
            let color = ChartColorResolver.resolveColor(cell: cell, categoryKey: key, categoryLevels: data.categoryLevels, measure: mField,
                                                        format: context.format, theme: context.theme)
            let id = pointID(bar.index)
            let opacity = context.selection.isEmpty || context.selection.contains(id) ? 1.0 : 0.4
            let label = NumberDisplay.text(cell, units: context.format.dataLabels.displayUnits, precision: context.format.dataLabels.precision)
            return Row(bar: bar, rect: rect, color: color, opacity: opacity, label: label, id: id)
        }, plot)
    }

    var body: some View {
        GeometryReader { geo in
            let fontSize = ReportUnits.pixels(fromPoints: context.format.categoryLabels.fontSize ?? 9)
            let widest = names.map(\.count).max() ?? 0
            let labelWidth = Swift.min(geo.size.width * 0.3, CGFloat(widest) * fontSize * 0.62 + 10)
            let layout = rows(in: geo.size, labelWidth: labelWidth)
            if layout.rows.isEmpty {
                ZStack { Color.clear; Text("Không có dữ liệu").font(.system(size: 11)).foregroundColor(.secondary) }
            } else {
                canvas(layout.rows, plot: layout.plot, fontSize: fontSize, labelWidth: labelWidth, size: geo.size)
            }
        }
    }

    @ViewBuilder
    private func canvas(_ rows: [Row], plot: CGRect, fontSize: CGFloat, labelWidth: CGFloat, size: CGSize) -> some View {
        let ink = context.theme.foregroundColor
        let muted = Color(hex: "#605E5C") ?? .secondary
        let first = rows[0].rect
        let last = rows[rows.count - 1].rect
        let pitch = rows.count > 1 ? rows[1].rect.minY - rows[0].rect.minY : first.height
        let nameStride = ChartLabelDensity.stride(footprint: fontSize * 1.2, slot: pitch)
        let content = ZStack(alignment: .topLeading) {
            // Vạch ngoặc: "100%" trên thanh đầu, phần trăm của thanh cuối dưới thanh cuối.
            bracket(from: plot.minX, to: plot.maxX, y: first.minY - fontSize * 1.1, text: FunnelLayout.percentText(1), above: true, fontSize: fontSize, color: muted)
            bracket(from: last.minX, to: last.maxX, y: last.maxY + fontSize * 0.7, text: FunnelLayout.percentText(rows[rows.count - 1].bar.percentOfFirst),
                    above: false, fontSize: fontSize, color: muted)
            ForEach(Array(rows.enumerated()), id: \.offset) { order, row in
                Rectangle().fill(row.color).opacity(row.opacity)
                    .frame(width: row.rect.width, height: row.rect.height)
                    .overlay {
                        if row.rect.height >= fontSize * 1.1, row.rect.width > CGFloat(row.label.count) * fontSize * 0.62 + 8 {
                            Text(row.label).font(.system(size: fontSize)).foregroundColor(.white).lineLimit(1)
                        }
                    }
                    .position(x: row.rect.midX, y: row.rect.midY)
                if order % nameStride == 0 {
                    Text(row.bar.category).font(.system(size: fontSize)).foregroundColor(muted).lineLimit(1)
                        .frame(width: labelWidth - 6, alignment: .leading)
                        .position(x: (labelWidth - 6) / 2 + 2, y: row.rect.midY)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .foregroundColor(ink)
        .contentShape(Rectangle())
        if interactive {
            content
                .onTapGesture { location in
                    let hit = rows.first { $0.rect.contains(location) }
                    context.actions.select(hit?.id, NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control))
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): context.actions.hover(rows.first { $0.rect.contains(location) }?.id, location)
                    case .ended: context.actions.hover(nil, .zero)
                    }
                }
        } else {
            content
        }
    }

    private func bracket(from x0: CGFloat, to x1: CGFloat, y: CGFloat, text: String, above: Bool, fontSize: CGFloat, color: Color) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: x0, y: y))
                path.addLine(to: CGPoint(x: x1, y: y))
                let tick: CGFloat = 4
                path.move(to: CGPoint(x: x0, y: y)); path.addLine(to: CGPoint(x: x0, y: y + (above ? tick : -tick)))
                path.move(to: CGPoint(x: x1, y: y)); path.addLine(to: CGPoint(x: x1, y: y + (above ? tick : -tick)))
            }
            .stroke(color.opacity(0.55), lineWidth: 0.8)
            Text(text).font(.system(size: fontSize)).foregroundColor(color)
                .position(x: (x0 + x1) / 2, y: y + (above ? -fontSize * 0.9 : fontSize * 0.9))
        }
    }
}
