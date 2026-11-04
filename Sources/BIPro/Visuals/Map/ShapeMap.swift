import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

// MARK: - Shape Map Layout & Caching

struct ShapeMapFeaturePath: Sendable {
    var featureID: String
    var featureName: String
    var postal: String
    var path: Path
    var bounds: CGRect

    init(featureID: String, featureName: String, postal: String, path: Path, bounds: CGRect) {
        self.featureID = featureID
        self.featureName = featureName
        self.postal = postal
        self.path = path
        self.bounds = bounds
    }
}

struct ShapeMapFittedMap: Sendable {
    var size: CGSize
    var featurePaths: [ShapeMapFeaturePath]
    var globalBounds: CGRect

    init(size: CGSize, featurePaths: [ShapeMapFeaturePath], globalBounds: CGRect) {
        self.size = size
        self.featurePaths = featurePaths
        self.globalBounds = globalBounds
    }
}

enum ShapeMapLayout {
    /// Khớp tên bang đầy đủ với `name` (không phân biệt hoa thường, bỏ khoảng trắng thừa), nếu không thì khớp mã bang với `postal`.
    static func feature(for category: Value, in map: TopoMap) -> TopoFeature? {
        let rawStr = category.asText().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rawStr.isEmpty else { return nil }

        // 1. Thử khớp tên đầy đủ
        if let match = map.features.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == rawStr
        }) {
            return match
        }

        // 2. Thử khớp mã postal
        if let match = map.features.first(where: {
            $0.postal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == rawStr
        }) {
            return match
        }

        return nil
    }

    /// Đếm số danh mục không khớp với bất kỳ bang nào trong bản đồ.
    static func unmatchedCount(data: CategoricalData, in map: TopoMap) -> Int {
        var count = 0
        for cat in data.categories {
            let catVal = cat.values.first ?? .blank
            if feature(for: catVal, in: map) == nil {
                count += 1
            }
        }
        return count
    }

    /// Vừa khung hình vẽ (giữ tỉ lệ, căn giữa) cho toàn bộ feature trong TopoMap.
    static func fitMap(_ map: TopoMap, in size: CGSize) -> ShapeMapFittedMap {
        guard size.width > 0, size.height > 0 else {
            return ShapeMapFittedMap(size: size, featurePaths: [], globalBounds: .zero)
        }

        // 1. Chiếu mọi điểm của 51 feature và tìm bounding box
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        typealias ProjectedFeature = (feature: TopoFeature, polygons: [[[CGPoint]]])
        var projectedFeatures: [ProjectedFeature] = []
        projectedFeatures.reserveCapacity(map.features.count)

        for f in map.features {
            var fPolys: [[[CGPoint]]] = []
            for poly in f.polygons {
                var polyRings: [[CGPoint]] = []
                for ring in poly {
                    var ringPts: [CGPoint] = []
                    for pt in ring {
                        if let proj = AlbersUSA.project(longitude: pt.longitude, latitude: pt.latitude) {
                            ringPts.append(proj)
                            minX = min(minX, Double(proj.x))
                            maxX = max(maxX, Double(proj.x))
                            minY = min(minY, Double(proj.y))
                            maxY = max(maxY, Double(proj.y))
                        }
                    }
                    if !ringPts.isEmpty {
                        polyRings.append(ringPts)
                    }
                }
                if !polyRings.isEmpty {
                    fPolys.append(polyRings)
                }
            }
            projectedFeatures.append((f, fPolys))
        }

        guard maxX > minX, maxY > minY else {
            return ShapeMapFittedMap(size: size, featurePaths: [], globalBounds: .zero)
        }

        let boxW = maxX - minX
        let boxH = maxY - minY

        let padding: CGFloat = 8.0
        let availW = Double(max(10, size.width - 2 * padding))
        let availH = Double(max(10, size.height - 2 * padding))

        let scale = min(availW / boxW, availH / boxH)
        let offsetX = Double(padding) + (availW - boxW * scale) / 2.0 - minX * scale
        let offsetY = Double(padding) + (availH - boxH * scale) / 2.0 - minY * scale

        // 2. Tạo Path cho từng bang
        var featurePaths: [ShapeMapFeaturePath] = []
        featurePaths.reserveCapacity(projectedFeatures.count)

        for pf in projectedFeatures {
            var path = Path()
            for poly in pf.polygons {
                for ring in poly {
                    guard let first = ring.first else { continue }
                    let startPt = CGPoint(
                        x: CGFloat(Double(first.x) * scale + offsetX),
                        y: CGFloat(Double(first.y) * scale + offsetY)
                    )
                    path.move(to: startPt)
                    for pt in ring.dropFirst() {
                        let screenPt = CGPoint(
                            x: CGFloat(Double(pt.x) * scale + offsetX),
                            y: CGFloat(Double(pt.y) * scale + offsetY)
                        )
                        path.addLine(to: screenPt)
                    }
                    path.closeSubpath()
                }
            }

            let b = path.boundingRect
            featurePaths.append(ShapeMapFeaturePath(
                featureID: pf.feature.id,
                featureName: pf.feature.name,
                postal: pf.feature.postal,
                path: path,
                bounds: b
            ))
        }

        let globalBounds = CGRect(
            x: CGFloat(minX * scale + offsetX),
            y: CGFloat(minY * scale + offsetY),
            width: CGFloat(boxW * scale),
            height: CGFloat(boxH * scale)
        )

        return ShapeMapFittedMap(size: size, featurePaths: featurePaths, globalBounds: globalBounds)
    }
}

// MARK: - Right Click Interception

private struct ShapeMapRightClickDetector: NSViewRepresentable {
    var onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> ClickView {
        let v = ClickView()
        v.appearance = NSAppearance(named: .aqua)
        v.onRightClick = onRightClick
        return v
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.appearance = NSAppearance(named: .aqua)
        nsView.onRightClick = onRightClick
    }

    class ClickView: NSView {
        var onRightClick: ((CGPoint) -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: loc.x, y: bounds.height - loc.y)
            onRightClick?(flipped)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown else {
                return nil
            }
            return self
        }
    }
}

// MARK: - ShapeMapView

struct ShapeMapView: View {
    let data: CategoricalData
    let map: TopoMap
    let context: VisualRenderContext
    let interactive: Bool

    // Cache kết quả fit map theo kích thước
    @State private var cachedFittedMap: ShapeMapFittedMap? = nil
    @State private var lastFittedSize: CGSize = .zero

    init(data: CategoricalData, map: TopoMap, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.map = map
        self.context = context
        self.interactive = interactive
    }

    var body: some View {
        GeometryReader { geo in
            let fittedMap = getFittedMap(for: geo.size)

            if fittedMap.featurePaths.isEmpty {
                ZStack {
                    Color.clear
                    Text("Không có dữ liệu")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                mapCanvas(fittedMap: fittedMap, size: geo.size)
            }
        }
    }

    private func getFittedMap(for size: CGSize) -> ShapeMapFittedMap {
        if let cached = cachedFittedMap,
           abs(cached.size.width - size.width) < 1.0 && abs(cached.size.height - size.height) < 1.0 {
            return cached
        }
        let fitted = ShapeMapLayout.fitMap(map, in: size)
        return fitted
    }

    @ViewBuilder
    private func mapCanvas(fittedMap: ShapeMapFittedMap, size: CGSize) -> some View {
        let stateDrawables = buildStateDrawables(fittedMap: fittedMap)

        let content = ZStack {
            ForEach(stateDrawables, id: \.featureID) { item in
                item.path
                    .fill(item.color.opacity(item.opacity))
                    .overlay {
                        item.path
                            .stroke(Color.white.opacity(0.85), lineWidth: 0.6)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onAppear {
            cachedFittedMap = fittedMap
            lastFittedSize = size
        }
        .onChange(of: size) { _, newSize in
            cachedFittedMap = ShapeMapLayout.fitMap(map, in: newSize)
            lastFittedSize = newSize
        }

        if interactive {
            content
                .overlay {
                    ShapeMapRightClickDetector { loc in
                        let hit = hitTest(at: loc, drawables: stateDrawables)
                        context.actions.contextMenu(hit?.pointID, loc)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    let hit = hitTest(at: loc, drawables: stateDrawables)
                    let isAdditive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
                    context.actions.select(hit?.pointID, isAdditive)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        let hit = hitTest(at: loc, drawables: stateDrawables)
                        context.actions.hover(hit?.pointID, loc)
                    case .ended:
                        context.actions.hover(nil, .zero)
                    }
                }
        } else {
            content
        }
    }

    private struct StateDrawable {
        var featureID: String
        var featureName: String
        var postal: String
        var path: Path
        var bounds: CGRect
        var pointID: DataPointID?
        var color: Color
        var opacity: Double
    }

    private func buildStateDrawables(fittedMap: ShapeMapFittedMap) -> [StateDrawable] {
        // Ánh xạ category -> feature
        var catByFeatureID: [String: (catIndex: Int, pointID: DataPointID)] = [:]

        for (cIdx, cat) in data.categories.enumerated() {
            let catVal = cat.values.first ?? .blank
            if let f = ShapeMapLayout.feature(for: catVal, in: map) {
                var ptDict: [String: Value] = [:]
                for (lvlIdx, lvl) in data.categoryLevels.enumerated() {
                    if lvlIdx < cat.values.count {
                        ptDict[lvl.queryRef] = cat.values[lvlIdx]
                    }
                }
                catByFeatureID[f.id] = (cIdx, DataPointID(ptDict))
            }
        }

        let defaultThemeColor = context.theme.color(context.format.shapeMap.defaultColor)
            ?? (Color(hex: "#81B29A") ?? .teal)

        var result: [StateDrawable] = []

        for fp in fittedMap.featurePaths {
            if let matched = catByFeatureID[fp.featureID] {
                // Bang có dữ liệu: lấy fillColor đầu tiên khác nil trong các ô của danh mục đó (mọi measure)
                var resolvedColor: Color? = nil
                for m in 0..<data.measures.count {
                    let cell = data.cell(measure: m, series: 0, category: matched.catIndex)
                    if let fill = cell.fillColor, let col = Color(hex: fill) {
                        resolvedColor = col
                        break
                    }
                }

                if resolvedColor == nil {
                    // Kiểm tra dataPoint.fillByValue
                    if let lvl = data.categoryLevels.first, matched.catIndex < data.categories.count {
                        let catVal = data.categories[matched.catIndex].values.first ?? .blank
                        let scoped = ScopedValue(column: lvl.queryRef, value: ReportLiteral(daxValue: catVal))
                        if let lit = context.format.dataPoint.fillByValue[scoped] {
                            resolvedColor = context.theme.color(lit)
                        }
                    }
                }

                let color = resolvedColor ?? defaultThemeColor
                var opacity = 1.0
                if !context.selection.isEmpty {
                    opacity = context.selection.contains(matched.pointID) ? 1.0 : 0.40
                }

                result.append(StateDrawable(
                    featureID: fp.featureID,
                    featureName: fp.featureName,
                    postal: fp.postal,
                    path: fp.path,
                    bounds: fp.bounds,
                    pointID: matched.pointID,
                    color: color,
                    opacity: opacity
                ))
            } else {
                // Bang không có dữ liệu: màu mặc định
                result.append(StateDrawable(
                    featureID: fp.featureID,
                    featureName: fp.featureName,
                    postal: fp.postal,
                    path: fp.path,
                    bounds: fp.bounds,
                    pointID: nil,
                    color: defaultThemeColor,
                    opacity: 1.0
                ))
            }
        }

        return result
    }

    private func hitTest(at loc: CGPoint, drawables: [StateDrawable]) -> StateDrawable? {
        for d in drawables {
            if d.bounds.contains(loc) && d.path.contains(loc) {
                return d
            }
        }
        return nil
    }
}
