import DAXEngine
import Foundation
import SwiftUI

// Biểu đồ ruy-băng (VM-D15 mục 4, hình mẫu Desktop): cột xếp chồng theo từng danh mục, trong mỗi cột series lớn nhất nằm trên cùng
// (xếp lại theo thứ hạng ở mỗi danh mục); giữa hai cột liền nhau, mỗi series có một dải màu cùng tông nhạt hơn, nối cạnh trên với cạnh
// trên và cạnh dưới với cạnh dưới bằng đường cong chữ S; dải có viền trắng mảnh.

struct RibbonSegment: Hashable, Sendable {
    var category: Int
    var series: Int
    var value: Double
    var y0: Double
    var y1: Double
}

struct RibbonLink: Hashable, Sendable {
    var series: Int
    var from: RibbonSegment
    var to: RibbonSegment
}

enum RibbonLayout {
    /// `values[c][s]`: giá trị của series `s` ở danh mục `c`. Mỗi cột xếp từ nhỏ đến lớn (lớn nhất trên cùng); giá trị trống,
    /// không dương hoặc không hữu hạn không có đoạn.
    static func columns(values: [[Double?]]) -> [[RibbonSegment]] {
        values.enumerated().map { category, row in
            let ranked = row.enumerated().compactMap { series, value -> (series: Int, value: Double)? in
                guard let value, value > 0, value.isFinite else { return nil }
                return (series, value)
            }.sorted { $0.value != $1.value ? $0.value < $1.value : $0.series < $1.series }
            var base = 0.0
            return ranked.map { item in
                defer { base += item.value }
                return RibbonSegment(category: category, series: item.series, value: item.value, y0: base, y1: base + item.value)
            }
        }
    }

    /// Dải nối giữa hai cột liền nhau cho mỗi series có mặt ở cả hai.
    static func links(columns: [[RibbonSegment]]) -> [RibbonLink] {
        guard columns.count > 1 else { return [] }
        return (0..<(columns.count - 1)).flatMap { index in
            columns[index].compactMap { left in
                columns[index + 1].first { $0.series == left.series }.map { RibbonLink(series: left.series, from: left, to: $0) }
            }
        }
    }

    /// Chiều cao cột cao nhất (miền trục Y).
    static func maxTotal(columns: [[RibbonSegment]]) -> Double { columns.map { $0.last?.y1 ?? 0 }.max() ?? 0 }
}

struct RibbonChartView: View {
    let data: CategoricalData
    let context: VisualRenderContext
    let interactive: Bool

    init(data: CategoricalData, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.context = context
        self.interactive = interactive
    }

    /// Mỗi phần tử là một series vẽ được: giá trị Series nếu có, không thì từng measure Y.
    private struct SeriesInfo {
        var name: String
        var measure: Int
        var series: Int
        var color: Color
    }

    private var seriesInfo: [SeriesInfo] {
        let yMeasures = data.measureIndices(role: "Y")
        guard let first = yMeasures.first else { return [] }
        if data.seriesField != nil, !data.series.isEmpty {
            return data.series.indices.map { s in
                let cell = data.cell(measure: first, series: s, category: 0)
                let color = ChartColorResolver.resolveColor(cell: cell, categoryLevels: data.categoryLevels, seriesValue: data.series[s],
                                                            seriesField: data.seriesField, seriesIndex: s, hasSeries: true,
                                                            measure: data.measures[first], format: context.format, theme: context.theme)
                return SeriesInfo(name: data.seriesField?.text(data.series[s]) ?? data.series[s].asText(), measure: first, series: s, color: color)
            }
        }
        return yMeasures.enumerated().map { order, m in
            SeriesInfo(name: data.measures[m].displayName, measure: m, series: 0, color: context.theme.dataColor(order))
        }
    }

    private struct Slot {
        var segment: RibbonSegment
        var rect: CGRect
        var id: DataPointID
    }

    var body: some View {
        let infos = seriesInfo
        let columns = RibbonLayout.columns(values: data.categories.indices.map { c in
            infos.map { chartNumber(data.cell(measure: $0.measure, series: $0.series, category: c)) }
        })
        if infos.isEmpty || RibbonLayout.maxTotal(columns: columns) <= 0 {
            ZStack { Color.clear; Text(bi("Không có dữ liệu", "No data")).font(.system(size: 11)).foregroundColor(.secondary) }
        } else {
            VStack(spacing: 4) {
                GeometryReader { geo in plot(columns, infos: infos, size: geo.size) }
                ChartLegendView(items: infos.enumerated().map { LegendItem(id: "s\($0.offset)", name: $0.element.name, color: $0.element.color) },
                                position: context.format.legend.position, fontSize: context.format.legend.fontSize)
                    .padding(.horizontal, 6).padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func plot(_ columns: [[RibbonSegment]], infos: [SeriesInfo], size: CGSize) -> some View {
        let fontSize = ReportUnits.pixels(fromPoints: context.format.categoryAxis.fontSize ?? ChartDefaults.axisFontSize)
        let formatString = data.measures[infos[0].measure].formatString
        let scale = ValueAxisScale(low: 0, high: RibbonLayout.maxTotal(columns: columns), format: context.format, formatString: formatString)
        let labelRoom = fontSize * 2
        let left = scale.labelWidth(fontSize: fontSize)
        let plot = CGRect(x: left, y: 6, width: Swift.max(1, size.width - left - 6), height: Swift.max(1, size.height - 6 - labelRoom))
        let slotWidth = plot.width / CGFloat(Swift.max(1, columns.count))
        let columnWidth = slotWidth * 0.42
        let x: (Int) -> CGFloat = { plot.minX + slotWidth * (CGFloat($0) + 0.5) }
        let rect: (RibbonSegment) -> CGRect = { segment in
            let top = plot.minY + scale.y(segment.y1, height: plot.height)
            let bottom = plot.minY + scale.y(segment.y0, height: plot.height)
            return CGRect(x: x(segment.category) - columnWidth / 2, y: top, width: columnWidth, height: Swift.max(0.5, bottom - top))
        }
        let slots = columns.flatMap { $0 }.map { Slot(segment: $0, rect: rect($0), id: chartPointID(data: data, category: $0, series: infos[$0.series].series)) }
        let names = chartCategoryNames(data)
        let nameStride = ChartLabelDensity.stride(footprint: CGFloat((names.map(\.count).max() ?? 1)) * fontSize * 0.6 + 6, slot: slotWidth)
        let content = ZStack(alignment: .topLeading) {
            ValueAxisGrid(scale: scale, plot: plot, fontSize: fontSize)
            ForEach(Array(RibbonLayout.links(columns: columns).enumerated()), id: \.offset) { _, link in
                ribbon(link, rect(link.from), rect(link.to))
                    .fill(infos[link.series].color.opacity(0.62))
                    .overlay { ribbon(link, rect(link.from), rect(link.to)).stroke(Color.white, lineWidth: 0.8) }
            }
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                Rectangle().fill(infos[slot.segment.series].color)
                    .opacity(context.selection.isEmpty || context.selection.contains(slot.id) ? 1.0 : 0.4)
                    .frame(width: slot.rect.width, height: slot.rect.height)
                    .position(x: slot.rect.midX, y: slot.rect.midY)
            }
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                if index % nameStride == 0 {
                    Text(name).font(.system(size: fontSize)).foregroundColor(Color(hex: "#605E5C") ?? .secondary).lineLimit(1)
                        .frame(width: slotWidth * CGFloat(nameStride))
                        .position(x: x(index) + slotWidth * CGFloat(nameStride - 1) / 2, y: plot.maxY + labelRoom * 0.5)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()   // miền trục do người dùng đặt (Lớn nhất) có thể nhỏ hơn dữ liệu: không vẽ ra ngoài khung
        .contentShape(Rectangle())
        // Cột trước, rồi dải: trỏ vào dải thì lấy điểm của series đó ở cột bên trái dải (VM-D16: tooltip theo dải).
        let links = RibbonLayout.links(columns: columns)
        let pointAt: (CGPoint) -> DataPointID? = { location in
            if let slot = slots.first(where: { $0.rect.contains(location) }) { return slot.id }
            guard let link = links.first(where: { ribbon($0, rect($0.from), rect($0.to)).contains(location) }) else { return nil }
            return chartPointID(data: data, category: link.from, series: infos[link.series].series)
        }
        if interactive {
            content
                .onTapGesture { location in
                    context.actions.select(pointAt(location), NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control))
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): context.actions.hover(pointAt(location), location)
                    case .ended: context.actions.hover(nil, .zero)
                    }
                }
        } else {
            content
        }
    }

    /// Dải từ cột trái sang cột phải: cạnh trên và cạnh dưới nối bằng đường cong chữ S.
    private func ribbon(_ link: RibbonLink, _ left: CGRect, _ right: CGRect) -> Path {
        Path { path in
            let x0 = left.maxX, x1 = right.minX, mid = (x0 + x1) / 2
            path.move(to: CGPoint(x: x0, y: left.minY))
            path.addCurve(to: CGPoint(x: x1, y: right.minY), control1: CGPoint(x: mid, y: left.minY), control2: CGPoint(x: mid, y: right.minY))
            path.addLine(to: CGPoint(x: x1, y: right.maxY))
            path.addCurve(to: CGPoint(x: x0, y: left.maxY), control1: CGPoint(x: mid, y: right.maxY), control2: CGPoint(x: mid, y: left.maxY))
            path.closeSubpath()
        }
    }
}

private func chartPointID(data: CategoricalData, category segment: RibbonSegment, series: Int) -> DataPointID {
    chartPointID(data: data, category: segment.category, series: data.seriesField != nil ? series : nil)
}
