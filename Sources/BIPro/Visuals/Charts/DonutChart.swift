import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

// MARK: - Donut Data Structures

struct DonutSlice: Hashable, Sendable {
    var index: Int
    var pointID: DataPointID
    var categoryName: String
    var value: Double
    var fraction: Double
    /// Góc bắt đầu tính theo radian, 12 giờ = -Double.pi / 2, chiều kim đồng hồ.
    var startAngle: Double
    /// Góc kết thúc tính theo radian.
    var endAngle: Double
    /// Phần tô sáng so với chính lát đó (0...1).
    var highlightFraction: Double?
    var color: Color
    var opacity: Double

    init(
        index: Int,
        pointID: DataPointID = DataPointID([:]),
        categoryName: String = "",
        value: Double,
        fraction: Double,
        startAngle: Double,
        endAngle: Double,
        highlightFraction: Double? = nil,
        color: Color = .blue,
        opacity: Double = 1.0
    ) {
        self.index = index
        self.pointID = pointID
        self.categoryName = categoryName
        self.value = value
        self.fraction = fraction
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.highlightFraction = highlightFraction
        self.color = color
        self.opacity = opacity
    }
}

// MARK: - Donut Layout

enum DonutLayout {
    /// Tính danh sách lát tròn từ mảng giá trị và highlights tuỳ chọn.
    /// - Góc bắt đầu 12 giờ (-π/2), chạy theo chiều kim đồng hồ, theo đúng thứ tự dữ liệu.
    /// - Bỏ giá trị âm, 0, NaN, BLANK.
    /// - Mỗi lát có `fraction` và `highlightFraction` (phần tô sáng so với chính lát đó, tối đa 1.0).
    static func slices(values: [Double], highlights: [Double]? = nil) -> [DonutSlice] {
        var validItems: [(origIndex: Int, value: Double, highlight: Double?)] = []
        for (i, v) in values.enumerated() {
            guard v > 0, v.isFinite else { continue }
            let hl = (highlights != nil && i < highlights!.count) ? highlights![i] : nil
            validItems.append((origIndex: i, value: v, highlight: hl))
        }

        let total = validItems.reduce(0.0) { $0 + $1.value }
        guard total > 0 else { return [] }

        var result: [DonutSlice] = []
        var currentAngle = -Double.pi / 2.0
        let fullCircle = 2.0 * Double.pi

        for item in validItems {
            let frac = item.value / total
            let span = frac * fullCircle
            let start = currentAngle
            let end = currentAngle + span
            currentAngle = end

            var hlFrac: Double? = nil
            if let hlVal = item.highlight {
                if hlVal.isFinite && hlVal > 0 {
                    hlFrac = min(1.0, hlVal / item.value)
                } else {
                    hlFrac = 0.0
                }
            }

            result.append(DonutSlice(
                index: item.origIndex,
                value: item.value,
                fraction: frac,
                startAngle: start,
                endAngle: end,
                highlightFraction: hlFrac
            ))
        }

        return result
    }

    /// Định dạng phần trăm của lát donut (0.948 -> "94.8%", 0.0181 -> "1.81%", 0.0048 -> "0.48%").
    /// [SUY ĐOÁN] quy tắc làm tròn: 3 chữ số có nghĩa (>= 10% dùng 1 chữ số thập phân, < 10% dùng 2 chữ số thập phân).
    static func percentText(_ fraction: Double) -> String {
        let p = fraction * 100.0
        guard p.isFinite else { return "" }
        let precision: Int
        if p >= 10.0 {
            precision = 1
        } else {
            precision = 2
        }
        return NumberDisplay.decimal(p, precision: precision) + "%"
    }

    /// Chuỗi hiển thị ở tâm donut: tổng của measure Y qua `NumberDisplay.text(...)`.
    static func centerText(data: CategoricalData, format: VisualFormat) -> String {
        let roleYIndices = data.measureIndices(role: "Y")
        let mIdx = roleYIndices.first ?? (data.measureIndices(role: "Values").first ?? 0)
        guard mIdx < data.measures.count else { return "" }
        let mField = data.measures[mIdx]

        var total = 0.0
        if let hlGrid = data.highlights, mIdx < hlGrid.count {
            for sList in hlGrid[mIdx] {
                for cell in sList {
                    if let v = NumberDisplay.numericValue(cell.value), v > 0 {
                        total += v
                    }
                }
            }
        } else if mIdx < data.values.count {
            for sList in data.values[mIdx] {
                for cell in sList {
                    if let v = NumberDisplay.numericValue(cell.value), v > 0 {
                        total += v
                    }
                }
            }
        }

        let cell = DataCell(.double(total), formatString: mField.formatString)
        return NumberDisplay.text(
            cell,
            units: format.dataLabels.displayUnits,
            precision: format.dataLabels.precision,
            reference: total
        )
    }

    /// Thứ tự ưu tiên màu thuần:
    /// `DataCell.fillColor` > `format.dataPoint.fillByValue` > `format.dataPoint.fillByMeasure` > `defaultFill`.
    static func resolveColorLiteral(
        cell: DataCell,
        categoryKey: CategoryKey? = nil,
        categoryLevels: [FieldInfo] = [],
        measure: FieldInfo? = nil,
        format: VisualFormat
    ) -> ReportLiteral? {
        if let fill = cell.fillColor {
            return .string(fill)
        }
        if let catKey = categoryKey {
            for (level, val) in zip(categoryLevels, catKey.values) {
                let lit = ReportLiteral(daxValue: val)
                let scoped = ScopedValue(column: level.queryRef, value: lit)
                if let matched = format.dataPoint.fillByValue[scoped] {
                    return matched
                }
            }
        }
        if let m = measure, let matched = format.dataPoint.fillByMeasure[m.queryRef] {
            return matched
        }
        if let def = format.dataPoint.defaultFill {
            return def
        }
        return nil
    }

    static func resolveColor(
        cell: DataCell,
        categoryIndex: Int,
        categoryKey: CategoryKey? = nil,
        categoryLevels: [FieldInfo] = [],
        measure: FieldInfo? = nil,
        format: VisualFormat,
        theme: ReportTheme
    ) -> Color {
        if let lit = resolveColorLiteral(
            cell: cell,
            categoryKey: categoryKey,
            categoryLevels: categoryLevels,
            measure: measure,
            format: format
        ), let col = theme.color(lit) {
            return col
        }
        return theme.dataColor(categoryIndex)
    }
}

// MARK: - Donut Arc Shape

private struct DonutArcShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var innerRadiusRatio: CGFloat
    var gapAngle: Double = 0.008 // Khe trắng mảnh giữa các lát

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2.0
        let innerR = outerR * innerRadiusRatio

        let span = endAngle - startAngle
        guard span > gapAngle else { return path }

        let sAngle = Angle(radians: startAngle + gapAngle / 2.0)
        let eAngle = Angle(radians: endAngle - gapAngle / 2.0)

        path.addArc(center: center, radius: outerR, startAngle: sAngle, endAngle: eAngle, clockwise: false)
        path.addArc(center: center, radius: innerR, startAngle: eAngle, endAngle: sAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Right Click Interception

private struct DonutRightClickDetector: NSViewRepresentable {
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

// MARK: - DonutChartView

struct DonutChartView: View {
    let data: CategoricalData
    let context: VisualRenderContext
    let interactive: Bool

    @State private var hoveredSliceIndex: Int? = nil

    init(data: CategoricalData, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.context = context
        self.interactive = interactive
    }

    private var roleYIndex: Int {
        let indices = data.measureIndices(role: "Y")
        return indices.first ?? (data.measureIndices(role: "Values").first ?? 0)
    }

    private var slices: [DonutSlice] {
        guard roleYIndex < data.measures.count else { return [] }
        let mField = data.measures[roleYIndex]

        var rawValues: [Double] = []
        var rawHighlights: [Double]? = (data.highlights != nil) ? [] : nil

        let numCats = data.categories.count
        for cIdx in 0..<numCats {
            let cell = data.cell(measure: roleYIndex, series: 0, category: cIdx)
            let val = NumberDisplay.numericValue(cell.value) ?? 0.0
            rawValues.append(val)

            if rawHighlights != nil {
                if let hlGrid = data.highlights, roleYIndex < hlGrid.count, !hlGrid[roleYIndex].isEmpty, cIdx < hlGrid[roleYIndex][0].count {
                    let hlCell = hlGrid[roleYIndex][0][cIdx]
                    rawHighlights?.append(NumberDisplay.numericValue(hlCell.value) ?? 0.0)
                } else {
                    rawHighlights?.append(0.0)
                }
            }
        }

        let baseSlices = DonutLayout.slices(values: rawValues, highlights: rawHighlights)

        var finalSlices: [DonutSlice] = []
        for s in baseSlices {
            let cIdx = s.index
            let cell = data.cell(measure: roleYIndex, series: 0, category: cIdx)
            let catKey = cIdx < data.categories.count ? data.categories[cIdx] : nil
            let col = DonutLayout.resolveColor(
                cell: cell,
                categoryIndex: cIdx,
                categoryKey: catKey,
                categoryLevels: data.categoryLevels,
                measure: mField,
                format: context.format,
                theme: context.theme
            )

            var ptDict: [String: Value] = [:]
            for (lvlIdx, lvl) in data.categoryLevels.enumerated() {
                if let catKey, lvlIdx < catKey.values.count {
                    ptDict[lvl.queryRef] = catKey.values[lvlIdx]
                }
            }
            let ptID = DataPointID(ptDict)

            var opacity = 1.0
            if !context.selection.isEmpty {
                opacity = context.selection.contains(ptID) ? 1.0 : 0.4
            }

            var catName = ""
            if let catKey {
                catName = catKey.values.enumerated().map { data.categoryLevels.text($1, at: $0) }.joined(separator: " ")
            }

            var slice = s
            slice.pointID = ptID
            slice.categoryName = catName
            slice.color = col
            slice.opacity = opacity
            finalSlices.append(slice)
        }

        return finalSlices
    }

    private var centerString: String {
        DonutLayout.centerText(data: data, format: context.format)
    }

    private var legendItems: [LegendItem] {
        slices.map { s in
            LegendItem(id: "c-\(s.index)", name: s.categoryName, color: s.color)
        }
    }

    var body: some View {
        if slices.isEmpty {
            ZStack {
                Color.clear
                Text("Không có dữ liệu")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else {
            donutContainer
        }
    }

    @ViewBuilder
    private var donutContainer: some View {
        let pos = context.format.legend.position ?? "Bottom"
        let isSide = (pos.contains("Left") || pos.contains("Right"))
        let showLegend = (context.format.legend.show ?? true) && !legendItems.isEmpty

        if showLegend && isSide {
            HStack(spacing: 8) {
                if pos.contains("Left") {
                    ChartLegendView(items: legendItems, position: pos, fontSize: context.format.legend.fontSize)
                        .padding(.leading, 8)
                }
                donutGeometry
                if pos.contains("Right") {
                    ChartLegendView(items: legendItems, position: pos, fontSize: context.format.legend.fontSize)
                        .padding(.trailing, 8)
                }
            }
            .padding(4)
        } else {
            VStack(spacing: 8) {
                if showLegend && !pos.contains("Bottom") {
                    ChartLegendView(items: legendItems, position: pos, fontSize: context.format.legend.fontSize)
                        .padding(.top, 4)
                }
                donutGeometry
                if showLegend && pos.contains("Bottom") {
                    ChartLegendView(items: legendItems, position: pos, fontSize: context.format.legend.fontSize)
                        .padding(.bottom, 4)
                }
            }
            .padding(4)
        }
    }

    private var donutGeometry: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2.0, y: geo.size.height / 2.0)
            let outerRadius = size * 0.38
            let innerRadius = outerRadius * 0.80 // Vòng dày khoảng 1/5 bán kính

            ZStack {
                // Slices
                ForEach(slices, id: \.index) { slice in
                    if data.highlights != nil {
                        // Vòng ngoài: tổng ở opacity 0.4
                        DonutArcShape(
                            startAngle: slice.startAngle,
                            endAngle: slice.endAngle,
                            innerRadiusRatio: 0.80
                        )
                        .fill(slice.color.opacity(0.40))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .position(center)

                        // Vòng trong: cùng độ dày, bán kính nhỏ hơn, phần tô sáng màu đậm
                        if let hlFrac = slice.highlightFraction, hlFrac > 0 {
                            let hlSpan = (slice.endAngle - slice.startAngle) * hlFrac
                            DonutArcShape(
                                startAngle: slice.startAngle,
                                endAngle: slice.startAngle + hlSpan,
                                innerRadiusRatio: 0.75
                            )
                            .fill(slice.color)
                            .frame(width: (innerRadius * 2) * 0.98, height: (innerRadius * 2) * 0.98)
                            .position(center)
                        }
                    } else {
                        // Bình thường
                        DonutArcShape(
                            startAngle: slice.startAngle,
                            endAngle: slice.endAngle,
                            innerRadiusRatio: 0.80
                        )
                        .fill(slice.color.opacity(slice.opacity))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .position(center)
                    }
                }

                // Nhãn ngoài vòng có đường dẫn
                if context.format.dataLabels.show != false {
                    ForEach(slices, id: \.index) { slice in
                        donutLabel(for: slice, center: center, radius: outerRadius, in: geo.size)
                    }
                }

                // Tổng ở giữa vòng
                if !centerString.isEmpty {
                    VStack(spacing: 2) {
                        Text(centerString)
                            .font(.system(size: max(16, min(28, size * 0.08)), weight: .bold))
                            .foregroundColor(Color(hex: "#252423") ?? .primary)
                    }
                    .position(center)
                }
            }
            .contentShape(Rectangle())
            .modifier(DonutEventModifier(
                interactive: interactive,
                center: center,
                outerRadius: outerRadius,
                innerRadius: innerRadius,
                slices: slices,
                context: context
            ))
        }
    }

    @ViewBuilder
    private func donutLabel(for slice: DonutSlice, center: CGPoint, radius: CGFloat, in bounds: CGSize) -> some View {
        let midAngle = (slice.startAngle + slice.endAngle) / 2.0
        let labelDistance = radius + 14.0

        let pt0 = CGPoint(
            x: center.x + cos(midAngle) * radius,
            y: center.y + sin(midAngle) * radius
        )
        let pt1 = CGPoint(
            x: center.x + cos(midAngle) * labelDistance,
            y: center.y + sin(midAngle) * labelDistance
        )
        let isRight = cos(midAngle) >= 0
        let pt2 = CGPoint(
            x: pt1.x + (isRight ? 12 : -12),
            y: pt1.y
        )

        let labelText: String = {
            let style = context.format.dataLabels.labelStyle ?? "Percent of total"
            switch style {
            case "Data value":
                let cell = data.cell(measure: roleYIndex, series: 0, category: slice.index)
                return NumberDisplay.text(cell, units: context.format.dataLabels.displayUnits, precision: context.format.dataLabels.precision)
            case "Category":
                return slice.categoryName
            case "Category, percent of total":
                return "\(slice.categoryName), \(DonutLayout.percentText(slice.fraction))"
            case "Category, data value":
                let cell = data.cell(measure: roleYIndex, series: 0, category: slice.index)
                let valText = NumberDisplay.text(cell, units: context.format.dataLabels.displayUnits, precision: context.format.dataLabels.precision)
                return "\(slice.categoryName), \(valText)"
            default:
                return DonutLayout.percentText(slice.fraction)
            }
        }()

        let fontSize = ReportUnits.pixels(fromPoints: context.format.dataLabels.fontSize ?? 9)
        let fontColor = context.theme.color(context.format.dataLabels.color) ?? (Color(hex: "#252423") ?? .primary)

        ZStack {
            // Đường dẫn
            Path { path in
                path.move(to: pt0)
                path.addLine(to: pt1)
                path.addLine(to: pt2)
            }
            .stroke(Color.gray.opacity(0.4), lineWidth: 0.75)

            // Text
            Text(labelText)
                .font(.system(size: fontSize, weight: context.format.dataLabels.bold == true ? .bold : .regular))
                .foregroundColor(fontColor)
                .position(x: pt2.x + (isRight ? 18 : -18), y: pt2.y)
        }
    }
}

// MARK: - Donut Event Modifier

private struct DonutEventModifier: ViewModifier {
    let interactive: Bool
    let center: CGPoint
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let slices: [DonutSlice]
    let context: VisualRenderContext

    func body(content: Content) -> some View {
        if interactive {
            content
                .overlay {
                    DonutRightClickDetector { loc in
                        let ptID = findSlice(at: loc)?.pointID
                        context.actions.contextMenu(ptID, loc)
                    }
                }
                .onTapGesture { loc in
                    let slice = findSlice(at: loc)
                    let isAdditive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
                    context.actions.select(slice?.pointID, isAdditive)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        let slice = findSlice(at: loc)
                        context.actions.hover(slice?.pointID, loc)
                    case .ended:
                        context.actions.hover(nil, .zero)
                    }
                }
        } else {
            content
        }
    }

    private func findSlice(at loc: CGPoint) -> DonutSlice? {
        let dx = loc.x - center.x
        let dy = loc.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist >= innerRadius * 0.7 && dist <= outerRadius * 1.05 else { return nil }

        var angle = atan2(dy, dx)
        // Normalize angle to start from -pi / 2
        while angle < -Double.pi / 2.0 {
            angle += 2.0 * Double.pi
        }
        while angle >= 3.0 * Double.pi / 2.0 {
            angle -= 2.0 * Double.pi
        }

        for slice in slices {
            if angle >= slice.startAngle && angle <= slice.endAngle {
                return slice
            }
        }
        return nil
    }
}
