import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

struct GeoMapPoint: Identifiable, Sendable {
    let id: Int
    let pointID: DataPointID
    let label: String
    let lat: Double
    let lon: Double
    let value: Double
    let cell: DataCell
    let seriesIndex: Int
    let radius: CGFloat
}

struct GeoMapLayout: Sendable {
    let points: [GeoMapPoint]
    let minLon: Double
    let maxLon: Double
    let minLat: Double
    let maxLat: Double
    let unmatchedCount: Int

    init(data: CategoricalData) {
        let sizeIdx = data.measureIndices(role: "Size").first
            ?? data.measureIndices(role: "Y").first
            ?? data.measureIndices(role: "Values").first
            ?? data.measures.indices.first
        let hasSeries = data.seriesField != nil && !data.series.isEmpty
        let seriesLimit = hasSeries ? data.series.count : 1

        struct RawPt {
            var pointID: DataPointID
            var label: String
            var coord: OfflineGeoAtlas.Coordinate
            var value: Double
            var cell: DataCell
            var seriesIndex: Int
        }
        var matched: [RawPt] = []
        var unmatched = 0

        for (cIdx, catKey) in data.categories.enumerated() {
            let label = catKey.values.enumerated().map { data.categoryLevels.text($1, at: $0) }.joined(separator: " ")
            guard let coord = OfflineGeoAtlas.lookup(label) else {
                unmatched += 1
                continue
            }
            for sIdx in 0..<seriesLimit {
                let cell = sizeIdx.map { data.cell(measure: $0, series: sIdx, category: cIdx) } ?? .blank
                let val = NumberDisplay.numericValue(cell.value) ?? 1.0
                if sizeIdx != nil && cell.value == .blank { continue }

                var dict: [String: Value] = [:]
                for (lIdx, lvl) in data.categoryLevels.enumerated() where lIdx < catKey.values.count {
                    dict[lvl.queryRef] = catKey.values[lIdx]
                }
                if let sf = data.seriesField, sIdx < data.series.count {
                    dict[sf.queryRef] = data.series[sIdx]
                }
                matched.append(RawPt(pointID: DataPointID(dict), label: label, coord: coord, value: val, cell: cell, seriesIndex: sIdx))
            }
        }

        self.unmatchedCount = unmatched
        let vals = matched.map { abs($0.value) }
        let minV = vals.min() ?? 0
        let maxV = vals.max() ?? 1

        let lons = matched.map(\.coord.lon)
        let lats = matched.map(\.coord.lat)
        let rawMinLon = lons.min() ?? -125
        let rawMaxLon = lons.max() ?? -66
        let rawMinLat = lats.min() ?? 24
        let rawMaxLat = lats.max() ?? 50
        let lonPad = max(8.0, (rawMaxLon - rawMinLon) * 0.16)
        let latPad = max(5.0, (rawMaxLat - rawMinLat) * 0.16)
        self.minLon = max(-180, rawMinLon - lonPad)
        self.maxLon = min(180, rawMaxLon + lonPad)
        self.minLat = max(-85, rawMinLat - latPad)
        self.maxLat = min(85, rawMaxLat + latPad)

        self.points = matched.enumerated().map { idx, raw in
            let r: CGFloat
            if sizeIdx != nil && maxV > minV {
                let t = sqrt((abs(raw.value) - minV) / (maxV - minV))
                r = CGFloat(6 + t * 18)
            } else {
                r = 9
            }
            return GeoMapPoint(id: idx, pointID: raw.pointID, label: raw.label, lat: raw.coord.lat, lon: raw.coord.lon,
                               value: raw.value, cell: raw.cell, seriesIndex: raw.seriesIndex, radius: r)
        }
    }

    func normalized(_ pt: GeoMapPoint) -> CGPoint {
        let x = (pt.lon - minLon) / max(1e-6, maxLon - minLon)
        let y = 1.0 - (pt.lat - minLat) / max(1e-6, maxLat - minLat)
        return CGPoint(x: x, y: y)
    }
}

/// Bản đồ bong bóng (`map`) & bản đồ tô màu vùng (`filledMap`) hoạt động 100% ngoại tuyến (Hiến pháp IV).
struct GeoMapView: View {
    let data: CategoricalData
    let isFilled: Bool
    let topoMap: TopoMap?
    let context: VisualRenderContext
    let interactive: Bool

    @State private var hoveredID: Int? = nil
    @State private var hoverLoc: CGPoint = .zero

    private var shouldUseUSTopo: Bool {
        guard isFilled, let topoMap, !data.categories.isEmpty else { return false }
        let matched = data.categories.count - ShapeMapLayout.unmatchedCount(data: data, in: topoMap)
        return matched * 2 >= data.categories.count
    }

    var body: some View {
        if shouldUseUSTopo, let topoMap {
            ShapeMapView(data: data, map: topoMap, context: context, interactive: interactive)
        } else {
            offlineCanvas
        }
    }

    private var offlineCanvas: some View {
        let layout = GeoMapLayout(data: data)
        let hasSeries = data.seriesField != nil && !data.series.isEmpty
        let legendItems: [LegendItem] = hasSeries
            ? data.series.enumerated().map { idx, v in
                LegendItem(id: "s-\(idx)", name: data.seriesField?.text(v) ?? v.asText(), color: context.theme.dataColor(idx))
            }
            : []

        return VStack(spacing: 4) {
            if !legendItems.isEmpty && (context.format.legend.show ?? true) {
                ChartLegendView(items: legendItems, position: "Top", fontSize: context.format.legend.fontSize)
                    .padding(.horizontal, 8)
            }
            if layout.points.isEmpty {
                ZStack {
                    Color(hex: "#F0F4F8") ?? Color.gray.opacity(0.08)
                    Text(bi("Bản đồ ngoại tuyến: chưa nhận diện được địa danh", "Offline map: no recognized geographic locations"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                GeometryReader { geo in
                    let pad: CGFloat = 18
                    let w = max(20, geo.size.width - pad * 2)
                    let h = max(20, geo.size.height - pad * 2)

                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, size in
                            // Ocean / map paper background
                            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#EEF4FA") ?? Color.blue.opacity(0.05)))

                            // Subtle lat/lon graticule grid
                            let gridColor = Color.black.opacity(0.06)
                            for i in 1...4 {
                                let gx = size.width * CGFloat(i) / 5
                                var vp = Path(); vp.move(to: CGPoint(x: gx, y: 0)); vp.addLine(to: CGPoint(x: gx, y: size.height))
                                ctx.stroke(vp, with: .color(gridColor), lineWidth: 0.6)
                                let gy = size.height * CGFloat(i) / 5
                                var hp = Path(); hp.move(to: CGPoint(x: 0, y: gy)); hp.addLine(to: CGPoint(x: size.width, y: gy))
                                ctx.stroke(hp, with: .color(gridColor), lineWidth: 0.6)
                            }

                            // Points / filled region badges
                            for pt in layout.points {
                                let norm = layout.normalized(pt)
                                let cx = pad + norm.x * w
                                let cy = pad + norm.y * h
                                let selected = context.selection.isEmpty || context.selection.contains(pt.pointID)
                                let color = context.theme.dataColor(pt.seriesIndex)
                                if isFilled {
                                    let r = max(12, pt.radius * 1.15)
                                    let rect = CGRect(x: cx - r, y: cy - r * 0.72, width: r * 2, height: r * 1.44)
                                    let shape = Path(roundedRect: rect, cornerRadius: 5)
                                    ctx.fill(shape, with: .color(color.opacity(selected ? 0.72 : 0.25)))
                                    ctx.stroke(shape, with: .color(color.opacity(selected ? 1.0 : 0.4)), lineWidth: hoveredID == pt.id ? 2 : 1)
                                } else {
                                    let rect = CGRect(x: cx - pt.radius, y: cy - pt.radius, width: pt.radius * 2, height: pt.radius * 2)
                                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(selected ? 0.70 : 0.22)))
                                    ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(selected ? 1.0 : 0.35)), lineWidth: hoveredID == pt.id ? 2 : 1.2)
                                }
                            }
                        }

                        // Compact location labels (when <= 20 points)
                        if layout.points.count <= 20 {
                            ForEach(layout.points) { pt in
                                let norm = layout.normalized(pt)
                                let cx = pad + norm.x * w
                                let cy = pad + norm.y * h
                                Text(pt.label)
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(Color(hex: "#252423") ?? .primary)
                                    .lineLimit(1)
                                    .position(x: cx, y: cy + pt.radius + 7)
                                    .allowsHitTesting(false)
                            }
                        }

                        // Offline badge (subtle, bottom-right)
                        Text(bi("Ngoại tuyến", "Offline"))
                            .font(.system(size: 8))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.7), in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(5)
                            .allowsHitTesting(false)

                        // Hover tooltip
                        if interactive, let hid = hoveredID, hid < layout.points.count {
                            let pt = layout.points[hid]
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pt.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                if pt.cell.value != .blank {
                                    Text(NumberDisplay.plain(pt.cell)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#333333") ?? .black))
                            .fixedSize()
                            .position(x: min(max(60, hoverLoc.x), geo.size.width - 60), y: max(24, hoverLoc.y - 24))
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard interactive else { return }
                        let hit = nearestPoint(at: loc, layout: layout, pad: pad, w: w, h: h)
                        let additive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
                        context.actions.select(hit?.pointID, additive)
                    }
                    .onContinuousHover { phase in
                        guard interactive else { return }
                        switch phase {
                        case .active(let loc):
                            hoverLoc = loc
                            hoveredID = nearestPoint(at: loc, layout: layout, pad: pad, w: w, h: h)?.id
                        case .ended:
                            hoveredID = nil
                        }
                    }
                }
            }
        }
        .padding(4)
    }

    private func nearestPoint(at loc: CGPoint, layout: GeoMapLayout, pad: CGFloat, w: CGFloat, h: CGFloat) -> GeoMapPoint? {
        var best: (pt: GeoMapPoint, dist: CGFloat)? = nil
        for pt in layout.points {
            let norm = layout.normalized(pt)
            let cx = pad + norm.x * w
            let cy = pad + norm.y * h
            let d = hypot(loc.x - cx, loc.y - cy)
            if d <= max(pt.radius + 6, 14), best == nil || d < best!.dist {
                best = (pt, d)
            }
        }
        return best?.pt
    }
}
