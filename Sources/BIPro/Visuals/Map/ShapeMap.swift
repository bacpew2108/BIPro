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

    /// Chú giải các giá trị Series (Legend) ở đáy bản đồ, như Desktop (VM-D15 mục 3): chấm màu dữ liệu của theme và nhãn.
    private var legendHeight: CGFloat { data.series.isEmpty ? 0 : 26 }

    var body: some View {
        VStack(spacing: 0) {
            mapBody
            if !data.series.isEmpty { legend.frame(height: legendHeight) }
        }
    }

    private var legend: some View {
        let size = ReportUnits.pixels(fromPoints: context.format.legend.fontSize ?? 9)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(data.series.enumerated()), id: \.offset) { index, value in
                    HStack(spacing: 4) {
                        Circle().fill(context.theme.dataColor(index)).frame(width: size, height: size)
                        Text(data.seriesField?.text(value) ?? value.asText())
                            .font(.system(size: size))
                            .foregroundStyle(context.theme.foregroundColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var mapBody: some View {
        GeometryReader { geo in
            let fittedMap = getFittedMap(for: geo.size)

            if fittedMap.featurePaths.isEmpty {
                ZStack {
                    Color.clear
                    Text(bi("Không có dữ liệu", "No data"))
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
                            .stroke(strokeColor, lineWidth: 0.6)
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

    private static func number(_ value: Value) -> Double? {
        switch value {
        case .integer(let i): Double(i)
        case .double(let d): d
        case .currency(let c): Double(c) / 10_000
        default: nil
        }
    }

    /// Màu Color saturation mặc định của Desktop: nội suy tuyến tính Min `#F8E5D8` đến Max `#D9ECFB`.
    static func saturationColor(_ value: Double, low: Double, high: Double) -> Color {
        let rgb = saturationRGB(value, low: low, high: high)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static func saturationRGB(_ value: Double, low: Double, high: Double) -> (r: Double, g: Double, b: Double) {
        let t = high > low ? min(1, max(0, (value - low) / (high - low))) : 1
        let (r0, g0, b0) = (0xF8 / 255.0, 0xE5 / 255.0, 0xD8 / 255.0)
        let (r1, g1, b1) = (0xD9 / 255.0, 0xEC / 255.0, 0xFB / 255.0)
        return (r0 + (r1 - r0) * t, g0 + (g1 - g0) * t, b0 + (b1 - b0) * t)
    }

    /// Viền bang: trắng như bản Nhom6 khi file đặt `defaultColors`; không thì xám đậm hơn nền, như Desktop (VM-D15 mục 3).
    private var strokeColor: Color {
        context.format.shapeMap.defaultColor == nil ? Color.black.opacity(0.3) : Color.white.opacity(0.85)
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

        // Bang không có dữ liệu: màu của `defaultColors` nếu file có, không thì xám như Desktop (VM-D15 mục 3).
        // Ô Value ("Color saturation"): thang màu mặc định của Desktop, tuyến tính từ giá trị nhỏ nhất đến lớn nhất của các bang
        // đang vẽ (VM-D15 mục 3: Min #F8E5D8, Max #D9ECFB; mọi bang cùng giá trị thì ra màu Max).
        // Có chú giải Series thì các bang tô theo series (toàn màu đầu ở mẫu Desktop), không theo thang saturation (VM-D16 mục 2).
        let saturationMeasure = data.series.isEmpty ? data.measureIndices(role: "Value").first : nil
        var saturationRange: (low: Double, high: Double)?
        if let m = saturationMeasure {
            let numbers = data.categories.indices.compactMap { Self.number(data.cell(measure: m, series: 0, category: $0).value) }
            if let low = numbers.min(), let high = numbers.max() { saturationRange = (low, high) }
        }
        let defaultThemeColor = context.theme.color(context.format.shapeMap.defaultColor)
            ?? (Color(hex: "#C7C7C7") ?? .gray)
        // Bang có dữ liệu mà chưa có màu riêng: màu dữ liệu đầu của theme (Desktop: bản đồ chỉ có Location ra toàn màu này).
        let matchedDefaultColor = context.theme.dataColor(0)

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

                if resolvedColor == nil, let m = saturationMeasure, let range = saturationRange,
                   let value = Self.number(data.cell(measure: m, series: 0, category: matched.catIndex).value) {
                    resolvedColor = Self.saturationColor(value, low: range.low, high: range.high)
                }
                // Có ô Value mà bang này trống thì như bang không có dữ liệu (xám), như Desktop.
                let blankValue = saturationMeasure.map { Self.number(data.cell(measure: $0, series: 0, category: matched.catIndex).value) == nil } ?? false
                let color = resolvedColor ?? (blankValue ? defaultThemeColor : matchedDefaultColor)
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
