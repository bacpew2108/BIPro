import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

// MARK: - Treemap Data Structures

struct TreemapTile: Identifiable, Hashable, Sendable {
    var id: String
    var pointID: DataPointID
    var categoryValues: [Value]
    var label: String
    var parentLabel: String?
    var value: Double
    var rect: CGRect
    var headerRect: CGRect?
    var isGroupHeader: Bool
    var level: Int
    var color: Color
    var opacity: Double
    var highlightFraction: Double?
    var formattedValue: String

    init(
        id: String,
        pointID: DataPointID = DataPointID([:]),
        categoryValues: [Value] = [],
        label: String = "",
        parentLabel: String? = nil,
        value: Double = 0.0,
        rect: CGRect = .zero,
        headerRect: CGRect? = nil,
        isGroupHeader: Bool = false,
        level: Int = 0,
        color: Color = .blue,
        opacity: Double = 1.0,
        highlightFraction: Double? = nil,
        formattedValue: String = ""
    ) {
        self.id = id
        self.pointID = pointID
        self.categoryValues = categoryValues
        self.label = label
        self.parentLabel = parentLabel
        self.value = value
        self.rect = rect
        self.headerRect = headerRect
        self.isGroupHeader = isGroupHeader
        self.level = level
        self.color = color
        self.opacity = opacity
        self.highlightFraction = highlightFraction
        self.formattedValue = formattedValue
    }
}

// MARK: - Treemap Layout

enum TreemapLayout {
    /// Thuật toán squarified treemap (Bruls, Huizing, van Wijk).
    /// - Trả về cùng thứ tự đầu vào; mỗi giá trị 0 hoặc âm cho ô rỗng (`CGRect.zero`).
    /// - Tổng diện tích các ô bằng diện tích `rect`.
    static func squarify(values: [Double], in rect: CGRect) -> [CGRect] {
        guard rect.width > 0, rect.height > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        var positiveItems: [(origIndex: Int, value: Double)] = []
        for (i, v) in values.enumerated() {
            if v > 0 && v.isFinite {
                positiveItems.append((origIndex: i, value: v))
            }
        }

        guard !positiveItems.isEmpty else {
            return Array(repeating: .zero, count: values.count)
        }

        let totalValue = positiveItems.reduce(0.0) { $0 + $1.value }
        guard totalValue > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        // Sắp xếp giảm dần theo giá trị
        positiveItems.sort { $0.value > $1.value }

        let totalArea = Double(rect.width * rect.height)
        let itemAreas: [(origIndex: Int, area: Double)] = positiveItems.map {
            ($0.origIndex, ($0.value / totalValue) * totalArea)
        }

        var result = Array(repeating: CGRect.zero, count: values.count)
        var remainingRect = rect

        func worst(row: [Double], side: Double) -> Double {
            guard !row.isEmpty, side > 0 else { return Double.greatestFiniteMagnitude }
            let s = row.reduce(0.0, +)
            guard s > 0 else { return Double.greatestFiniteMagnitude }
            let s2 = s * s
            let side2 = side * side
            var maxRatio = 0.0
            for a in row {
                guard a > 0 else { continue }
                let r1 = (side2 * a) / s2
                let r2 = s2 / (side2 * a)
                maxRatio = max(maxRatio, max(r1, r2))
            }
            return maxRatio
        }

        func layoutRow(_ row: [(origIndex: Int, area: Double)], in rRect: inout CGRect) {
            guard !row.isEmpty else { return }
            let s = row.reduce(0.0) { $0 + $1.area }
            guard s > 0 else { return }

            let isWidthShorter = rRect.width <= rRect.height
            let side = isWidthShorter ? Double(rRect.width) : Double(rRect.height)
            guard side > 0 else { return }

            let depth = s / side

            if isWidthShorter {
                // Hàng chiếm chiều ngang w, có chiều cao depth
                var curX = Double(rRect.minX)
                let curY = Double(rRect.minY)
                for item in row {
                    let itemWidth = (item.area / s) * side
                    result[item.origIndex] = CGRect(
                        x: curX,
                        y: curY,
                        width: itemWidth,
                        height: depth
                    )
                    curX += itemWidth
                }
                rRect = CGRect(
                    x: rRect.minX,
                    y: rRect.minY + CGFloat(depth),
                    width: rRect.width,
                    height: max(0, rRect.height - CGFloat(depth))
                )
            } else {
                // Hàng chiếm chiều dọc h, có chiều rộng depth
                let curX = Double(rRect.minX)
                var curY = Double(rRect.minY)
                for item in row {
                    let itemHeight = (item.area / s) * side
                    result[item.origIndex] = CGRect(
                        x: curX,
                        y: curY,
                        width: depth,
                        height: itemHeight
                    )
                    curY += itemHeight
                }
                rRect = CGRect(
                    x: rRect.minX + CGFloat(depth),
                    y: rRect.minY,
                    width: max(0, rRect.width - CGFloat(depth)),
                    height: rRect.height
                )
            }
        }

        var currentRow: [(origIndex: Int, area: Double)] = []
        for item in itemAreas {
            if currentRow.isEmpty {
                currentRow.append(item)
                continue
            }

            let side = Double(min(remainingRect.width, remainingRect.height))
            let curRowAreas = currentRow.map(\.area)
            let prevWorst = worst(row: curRowAreas, side: side)
            let nextWorst = worst(row: curRowAreas + [item.area], side: side)

            if nextWorst <= prevWorst {
                currentRow.append(item)
            } else {
                layoutRow(currentRow, in: &remainingRect)
                currentRow = [item]
            }
        }

        if !currentRow.isEmpty {
            layoutRow(currentRow, in: &remainingRect)
        }

        return result
    }

    /// Tạo các ô TreemapTile (hỗ trợ cả 1 cấp Group và 2 cấp Group).
    static func tiles(data: CategoricalData, in rect: CGRect, format: VisualFormat = VisualFormat(), theme: ReportTheme = .fallback) -> [TreemapTile] {
        guard rect.width > 0, rect.height > 0 else { return [] }

        let valMeasureIndices = data.measureIndices(role: "Values")
        let mIdx = valMeasureIndices.first ?? (data.measureIndices(role: "Y").first ?? 0)
        guard mIdx < data.measures.count else { return [] }

        let numCats = data.categories.count
        guard numCats > 0 else { return [] }

        let groupLevelCount = data.categoryLevels.count

        if groupLevelCount <= 1 {
            // MARK: 1 Cấp Group
            var rawValues: [Double] = []
            for c in 0..<numCats {
                let cell = data.cell(measure: mIdx, series: 0, category: c)
                let v = NumberDisplay.numericValue(cell.value) ?? 0.0
                rawValues.append(v)
            }

            let rects = squarify(values: rawValues, in: rect)
            var tiles: [TreemapTile] = []

            for c in 0..<numCats {
                let r = rects[c]
                guard r.width > 0, r.height > 0 else { continue }
                let cell = data.cell(measure: mIdx, series: 0, category: c)
                let val = rawValues[c]

                var ptDict: [String: Value] = [:]
                if let lvl = data.categoryLevels.first, c < data.categories.count, !data.categories[c].values.isEmpty {
                    ptDict[lvl.queryRef] = data.categories[c].values[0]
                }
                let ptID = DataPointID(ptDict)

                let catVal = c < data.categories.count && !data.categories[c].values.isEmpty ? data.categories[c].values[0] : .blank
                let label = data.categoryLevels.text(catVal, at: 0)

                let color = theme.dataColor(c)
                let fmtVal = NumberDisplay.text(cell, units: format.dataLabels.displayUnits, precision: format.dataLabels.precision)

                var hlFrac: Double? = nil
                if let hlGrid = data.highlights, mIdx < hlGrid.count, !hlGrid[mIdx].isEmpty, c < hlGrid[mIdx][0].count {
                    if let hlVal = NumberDisplay.numericValue(hlGrid[mIdx][0][c].value), val > 0 {
                        hlFrac = min(1.0, max(0.0, hlVal / val))
                    }
                }

                tiles.append(TreemapTile(
                    id: "tile-\(c)",
                    pointID: ptID,
                    categoryValues: [catVal],
                    label: label,
                    value: val,
                    rect: r,
                    level: 0,
                    color: color,
                    highlightFraction: hlFrac,
                    formattedValue: fmtVal
                ))
            }
            return tiles
        } else {
            // MARK: 2 Cấp Group
            struct GroupAgg {
                var parentValue: Value
                var parentIndex: Int
                var childIndices: [Int]
                var totalValue: Double
            }

            var groupMap: [Value: GroupAgg] = [:]
            var parentOrder: [Value] = []

            for c in 0..<numCats {
                let catKey = data.categories[c]
                let parentVal = !catKey.values.isEmpty ? catKey.values[0] : .blank
                let cell = data.cell(measure: mIdx, series: 0, category: c)
                let v = max(0.0, NumberDisplay.numericValue(cell.value) ?? 0.0)

                if var existing = groupMap[parentVal] {
                    existing.childIndices.append(c)
                    existing.totalValue += v
                    groupMap[parentVal] = existing
                } else {
                    let newAgg = GroupAgg(
                        parentValue: parentVal,
                        parentIndex: parentOrder.count,
                        childIndices: [c],
                        totalValue: v
                    )
                    groupMap[parentVal] = newAgg
                    parentOrder.append(parentVal)
                }
            }

            let parentValues = parentOrder.map { groupMap[$0]?.totalValue ?? 0.0 }
            let parentRects = squarify(values: parentValues, in: rect)

            var tiles: [TreemapTile] = []

            for (pIdx, pVal) in parentOrder.enumerated() {
                guard let agg = groupMap[pVal] else { continue }
                let pRect = parentRects[pIdx]
                guard pRect.width > 0, pRect.height > 0 else { continue }

                let parentColor = theme.dataColor(pIdx)
                let parentLabel = pVal.asText()

                // Header bar cho ô cha nếu đủ rộng
                let headerHeight: CGFloat = (pRect.height >= 40 && pRect.width >= 40) ? 20.0 : 0.0
                let headerRect = CGRect(x: pRect.minX, y: pRect.minY, width: pRect.width, height: headerHeight)

                // Thêm ô cha vào danh sách tiles (để vẽ nền/header)
                tiles.append(TreemapTile(
                    id: "parent-\(pIdx)",
                    categoryValues: [pVal],
                    label: parentLabel,
                    value: agg.totalValue,
                    rect: pRect,
                    headerRect: headerHeight > 0 ? headerRect : nil,
                    isGroupHeader: true,
                    level: 0,
                    color: parentColor,
                    formattedValue: NumberDisplay.decimal(agg.totalValue, precision: 0)
                ))

                // Vùng còn lại cho các ô con
                let childAreaRect = CGRect(
                    x: pRect.minX,
                    y: pRect.minY + headerHeight,
                    width: pRect.width,
                    height: max(0, pRect.height - headerHeight)
                )

                if childAreaRect.width > 0 && childAreaRect.height > 0 {
                    let childVals = agg.childIndices.map { c -> Double in
                        let cell = data.cell(measure: mIdx, series: 0, category: c)
                        return max(0.0, NumberDisplay.numericValue(cell.value) ?? 0.0)
                    }
                    let childRects = squarify(values: childVals, in: childAreaRect)

                    for (localIdx, cIdx) in agg.childIndices.enumerated() {
                        let cRect = childRects[localIdx]
                        guard cRect.width > 0, cRect.height > 0 else { continue }

                        let cell = data.cell(measure: mIdx, series: 0, category: cIdx)
                        let catKey = data.categories[cIdx]

                        var ptDict: [String: Value] = [:]
                        for (lvlIdx, lvl) in data.categoryLevels.enumerated() {
                            if lvlIdx < catKey.values.count {
                                ptDict[lvl.queryRef] = catKey.values[lvlIdx]
                            }
                        }
                        let ptID = DataPointID(ptDict)

                        let childLabel = catKey.values.count > 1 ? catKey.values[1].asText() : catKey.values.first?.asText() ?? ""
                        let cVal = childVals[localIdx]
                        let fmtVal = NumberDisplay.text(cell, units: format.dataLabels.displayUnits, precision: format.dataLabels.precision)

                        var hlFrac: Double? = nil
                        if let hlGrid = data.highlights, mIdx < hlGrid.count, !hlGrid[mIdx].isEmpty, cIdx < hlGrid[mIdx][0].count {
                            if let hlVal = NumberDisplay.numericValue(hlGrid[mIdx][0][cIdx].value), cVal > 0 {
                                hlFrac = min(1.0, max(0.0, hlVal / cVal))
                            }
                        }

                        tiles.append(TreemapTile(
                            id: "child-\(cIdx)",
                            pointID: ptID,
                            categoryValues: catKey.values,
                            label: childLabel,
                            parentLabel: parentLabel,
                            value: cVal,
                            rect: cRect,
                            level: 1,
                            color: parentColor, // Ô con cùng màu với nhóm cha
                            highlightFraction: hlFrac,
                            formattedValue: fmtVal
                        ))
                    }
                }
            }

            return tiles
        }
    }

    /// Tính độ sáng tương đối để chọn màu chữ trắng hay tối.
    static func textColor(for color: Color) -> Color {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let lum = 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
        return lum > 0.5 ? (Color(hex: "#252423") ?? .black) : .white
    }
}

// MARK: - Right Click Interception

private struct TreemapRightClickDetector: NSViewRepresentable {
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

// MARK: - TreemapView

struct TreemapView: View {
    let data: CategoricalData
    let context: VisualRenderContext
    let interactive: Bool

    init(data: CategoricalData, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.context = context
        self.interactive = interactive
    }

    var body: some View {
        GeometryReader { geo in
            let tiles = TreemapLayout.tiles(
                data: data,
                in: CGRect(origin: .zero, size: geo.size),
                format: context.format,
                theme: context.theme
            )

            if tiles.isEmpty {
                ZStack {
                    Color.clear
                    Text("Không có dữ liệu")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                treemapBody(tiles: tiles, in: geo.size)
            }
        }
    }

    @ViewBuilder
    private func treemapBody(tiles: [TreemapTile], in size: CGSize) -> some View {
        let content = ZStack(alignment: .topLeading) {
            // Vẽ các ô
            ForEach(tiles) { tile in
                drawTile(tile)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()

        if interactive {
            content
                .overlay {
                    TreemapRightClickDetector { loc in
                        let ptID = findTile(at: loc, in: tiles)?.pointID
                        context.actions.contextMenu(ptID, loc)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    let tile = findTile(at: loc, in: tiles)
                    let isAdditive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
                    context.actions.select(tile?.pointID, isAdditive)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        let tile = findTile(at: loc, in: tiles)
                        context.actions.hover(tile?.pointID, loc)
                    case .ended:
                        context.actions.hover(nil, .zero)
                    }
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private func drawTile(_ tile: TreemapTile) -> some View {
        let r = tile.rect
        // Khe trắng 1px
        let insetRect = r.insetBy(dx: 0.5, dy: 0.5)

        let isSelected = context.selection.isEmpty || context.selection.contains(tile.pointID)
        let opacity = isSelected ? 1.0 : 0.40

        if tile.isGroupHeader {
            // Header của nhóm cha trong 2 cấp
            if let hRect = tile.headerRect {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(tile.color.opacity(0.85))
                    Text(tile.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TreemapLayout.textColor(for: tile.color))
                        .padding(.leading, 4)
                        .padding(.top, 2)
                        .lineLimit(1)
                }
                .frame(width: hRect.width, height: hRect.height)
                .position(x: hRect.midX, y: hRect.midY)
            }
        } else {
            // Ô lá (hoặc ô cấp 1)
            let txtColor = TreemapLayout.textColor(for: tile.color)
            let hasHighlights = (data.highlights != nil)

            ZStack(alignment: .topLeading) {
                // Nền ô
                Rectangle()
                    .fill(tile.color.opacity(hasHighlights ? 0.40 : opacity))

                // [SUY ĐOÁN] Tô sáng chéo: phần tô sáng màu đậm ở góc dưới trái, diện tích tỉ lệ highlight / giá trị
                if let hlFrac = tile.highlightFraction, hlFrac > 0 {
                    let sideScale = sqrt(hlFrac)
                    let hlW = insetRect.width * CGFloat(sideScale)
                    let hlH = insetRect.height * CGFloat(sideScale)
                    Rectangle()
                        .fill(tile.color)
                        .frame(width: hlW, height: hlH)
                        .position(x: hlW / 2.0, y: insetRect.height - hlH / 2.0)
                }

                // Chữ trong ô khi đủ lớn
                if insetRect.width >= 35 && insetRect.height >= 25 {
                    VStack(alignment: .leading) {
                        Text(tile.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(txtColor)
                            .lineLimit(1)
                        Spacer()
                        if !tile.formattedValue.isEmpty && insetRect.height >= 38 {
                            Text(tile.formattedValue)
                                .font(.system(size: 11))
                                .foregroundColor(txtColor.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: insetRect.width, height: insetRect.height)
            .position(x: insetRect.midX, y: insetRect.midY)
        }
    }

    private func findTile(at loc: CGPoint, in tiles: [TreemapTile]) -> TreemapTile? {
        let interactiveTiles = tiles.filter { !$0.isGroupHeader }
        for t in interactiveTiles.reversed() {
            if t.rect.contains(loc) {
                return t
            }
        }
        return nil
    }
}
