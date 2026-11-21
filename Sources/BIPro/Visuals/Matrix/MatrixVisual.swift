import AppKit
import DAXEngine
import Foundation
import SwiftUI

struct MatrixVisualView: View {
    let data: MatrixData
    let context: VisualRenderContext
    let scrollable: Bool

    private let layout: MatrixLayout
    private let gradientMinMax: [Int: (min: Double, max: Double)]

    init(data: MatrixData, context: VisualRenderContext, scrollable: Bool = true) {
        self.data = data
        self.context = context
        self.scrollable = scrollable
        let l = MatrixLayout(data: data, format: context.format)
        self.layout = l

        // Tính trước min/max cho từng gradient rule để không tính lại khi cuộn hoặc rê chuột
        var minMaxDict: [Int: (min: Double, max: Double)] = [:]
        for (mIndex, measure) in data.measures.enumerated() {
            if let rule = context.format.gradients.first(where: {
                $0.property == "backColor" && ($0.target == measure.queryRef || $0.target == nil)
            }) {
                if let mm = MatrixGradient.minMax(data: data, measureIndex: mIndex, rule: rule) {
                    minMaxDict[mIndex] = mm
                }
            }
        }
        self.gradientMinMax = minMaxDict
    }

    static func columnMinMax(data: MatrixData, measureIndex m: Int) -> (min: Double, max: Double)? {
        var lo = Double.infinity, hi = -Double.infinity
        for (r, row) in data.rows.enumerated() where !row.isGrandTotal && !row.isSubtotal {
            for c in 0..<data.columnCount {
                if c < data.columns.count && (data.columns[c].isGrandTotal || data.columns[c].isSubtotal) { continue }
                if let v = NumberDisplay.numericValue(data.cell(row: r, column: c, measure: m).value), v.isFinite {
                    if v < lo { lo = v }
                    if v > hi { hi = v }
                }
            }
        }
        return lo.isFinite && hi.isFinite ? (lo, hi) : nil
    }

    var body: some View {
        if scrollable {
            ScrollView([.horizontal, .vertical]) {
                MatrixGridView(
                    data: data,
                    context: context,
                    layout: layout,
                    gradientMinMax: gradientMinMax
                )
                .frame(minWidth: layout.totalWidth, alignment: .topLeading)
            }
            .background(Color.white)
            .overlay(WheelScrollAssist())
        } else {
            MatrixGridView(
                data: data,
                context: context,
                layout: layout,
                gradientMinMax: gradientMinMax
            )
            .frame(width: layout.totalWidth, height: layout.totalHeight, alignment: .topLeading)
            .background(Color.white)
        }
    }
}

// MARK: - Lưới Matrix dùng chung (không bọc ScrollView)

struct MatrixGridView: View {
    let data: MatrixData
    let context: VisualRenderContext
    let layout: MatrixLayout
    let gradientMinMax: [Int: (min: Double, max: Double)]

    var body: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section(header: headerRowView) {
                ForEach(0..<data.rows.count, id: \.self) { r in
                    dataRowView(r)
                }
            }
        }
    }

    // MARK: - Tiêu đề cột (Sticky Section Header)

    private var headerRowView: some View {
        VStack(spacing: 0) {
            ForEach(0..<layout.headerTiers, id: \.self) { tier in
                HStack(spacing: 0) {
                    // Ô góc trên bên trái
                    cornerCell(tier: tier)
                        .frame(width: layout.rowHeaderWidth, height: layout.headerHeight)
                        .background(Color(hex: "#FAFAFA") ?? Color.white)
                        .overlay(cellBorder)

                    // Các ô tiêu đề cột
                    if data.columns.isEmpty {
                        ForEach(0..<data.measures.count, id: \.self) { m in
                            measureHeaderCell(m)
                                .frame(width: layout.width(forColumn: m), height: layout.headerHeight)
                                .background(Color(hex: "#FAFAFA") ?? Color.white)
                                .overlay(cellBorder)
                        }
                    } else {
                        ForEach(Array(headerSegments(tier: tier).enumerated()), id: \.offset) { _, segment in
                            segmentHeaderCell(segment)
                                .frame(width: segment.cols.reduce(0) { $0 + layout.width(forColumn: $1) }, height: layout.headerHeight)
                                .background(Color(hex: "#FAFAFA") ?? Color.white)
                                .overlay(cellBorder)
                        }
                    }
                }
            }
        }
        .background(Color.white)
    }

    private func cornerCell(tier: Int) -> some View {
        let label: String
        // Matrix có cột phân cấp (Vùng › Bang › Chi nhánh): mỗi dòng tiêu đề ghi tên cấp của nó, kể cả khi chưa mở nút
        // (người dùng yêu cầu 2026-11-07; ảnh Power BI q1.6 chưa mở ghi tên trường hàng, b5 ghi tên trường hàng ở dòng cuối).
        // Matrix thường: dòng cuối ghi tên trường hàng.
        let hierarchical = data.columns.contains { $0.hasChildren }
        if hierarchical, tier < data.columnLevels.count {
            label = data.columnLevels[tier].displayName
        } else if tier == layout.headerTiers - 1 {
            label = data.rowLevels.map(\.displayName).joined(separator: ", ")
        } else if tier < data.columnLevels.count {
            label = data.columnLevels[tier].displayName
        } else {
            label = ""
        }

        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: CGFloat(context.format.matrix.rowHeaderFontSize ?? 10), weight: .semibold))
                .foregroundStyle(context.theme.foregroundColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    private func headerSegments(tier: Int) -> [MatrixHeaderSegment] { data.headerSegments(tier: tier, lastTier: layout.headerTiers - 1) }

    private func segmentHeaderCell(_ segment: MatrixHeaderSegment) -> some View {
        let pointID = columnPointID(path: segment.path)
        let isSelected = !segment.path.isEmpty && context.selection.contains(pointID)
        return HStack(spacing: 4) {
            if let toggle = segment.toggle {
                Button(action: { context.actions.drill(.toggle(axis: .columns, path: toggle.path)) }) {
                    Image(systemName: toggle.expanded ? "minus.square" : "plus.square")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
                .buttonStyle(.plain)
            }
            // Power BI căn trái nhãn tiêu đề cột, ngay sau nút +/−.
            Text(segment.label)
                .font(.system(size: CGFloat(context.format.matrix.columnHeaderFontSize ?? 10), weight: segment.bold ? .bold : .semibold))
                .foregroundStyle(context.theme.foregroundColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .overlay(selectionOverlay(isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !segment.path.isEmpty else { return }
            let flags = NSEvent.modifierFlags
            context.actions.select(pointID, flags.contains(.command) || flags.contains(.control))
        }
    }

    private func columnHeaderCell(colIndex c: Int, tier: Int) -> some View {
        let col = data.columns[c]
        let isTotal = col.isGrandTotal || col.isSubtotal
        // Mỗi tầng chỉ ghi nhãn của cấp tương ứng; tổng chung ghi "Total" ở tầng cuối.
        let label: String
        if col.isGrandTotal {
            label = tier == layout.headerTiers - 1 ? "Total" : ""
        } else if tier < col.path.count {
            label = data.columnLevels.text(col.path[tier], at: tier)
        } else {
            label = ""
        }
        let pointID = columnPointID(col: c)
        let isSelected = context.selection.contains(pointID)

        return HStack(spacing: 4) {
            if col.hasChildren && !isTotal && tier == col.level {
                Button(action: {
                    context.actions.drill(.toggle(axis: .columns, path: col.path))
                }) {
                    Image(systemName: col.isExpanded ? "minus.square" : "plus.square")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Text(label)
                .font(.system(
                    size: CGFloat(context.format.matrix.columnHeaderFontSize ?? 10),
                    weight: isTotal ? .bold : .semibold
                ))
                .foregroundStyle(context.theme.foregroundColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .overlay(selectionOverlay(isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            let additive = flags.contains(.command) || flags.contains(.control)
            context.actions.select(pointID, additive)
        }
    }

    private func measureHeaderCell(_ m: Int) -> some View {
        let measure = data.measures[m]
        return HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(measure.displayName)
                .font(.system(size: CGFloat(context.format.matrix.columnHeaderFontSize ?? 10), weight: .semibold))
                .foregroundStyle(context.theme.foregroundColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Hàng dữ liệu

    private func dataRowView(_ r: Int) -> some View {
        let row = data.rows[r]
        let isRowTotal = row.isGrandTotal || row.isSubtotal

        return VStack(spacing: 0) {
            // Đường kẻ phía trên dòng tổng
            if isRowTotal {
                Divider()
                    .background(Color.gray.opacity(0.5))
            }

            HStack(spacing: 0) {
                // Tiêu đề hàng bên trái
                rowHeaderCell(row: row, rowIndex: r)
                    .frame(width: layout.rowHeaderWidth, height: layout.rowHeight)
                    .background(Color.white)
                    .overlay(cellBorder)

                // Các ô giá trị
                let colCount = data.columnCount
                ForEach(0..<colCount, id: \.self) { c in
                    dataCellView(row: r, col: c)
                        .frame(width: layout.width(forColumn: c), height: layout.rowHeight)
                        .overlay(cellBorder)
                }
            }
        }
    }

    private func rowHeaderCell(row: MatrixHeader, rowIndex r: Int) -> some View {
        let isTotal = row.isGrandTotal || row.isSubtotal
        let label = row.isGrandTotal ? "Total" : (row.path.last.map { data.rowLevels.text($0, at: row.path.count - 1) } ?? "")
        let indent = CGFloat(max(0, row.level)) * 16.0
        let pointID = rowPointID(row: r)
        let isSelected = context.selection.contains(pointID)

        return HStack(spacing: 4) {
            if indent > 0 {
                Spacer().frame(width: indent)
            }

            if row.hasChildren && !isTotal {
                Button(action: {
                    context.actions.drill(.toggle(axis: .rows, path: row.path))
                }) {
                    Image(systemName: row.isExpanded ? "minus.square" : "plus.square")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
                .buttonStyle(.plain)
            }

            Text(label)
                .font(.system(
                    size: CGFloat(context.format.matrix.rowHeaderFontSize ?? 10),
                    weight: isTotal ? .bold : .regular
                ))
                .foregroundStyle(context.theme.foregroundColor)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .overlay(selectionOverlay(isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            let additive = flags.contains(.command) || flags.contains(.control)
            context.actions.select(pointID, additive)
        }
    }

    private func dataCellView(row r: Int, col c: Int) -> some View {
        let m = 0
        let cell = data.cell(row: r, column: c, measure: m)
        let rowHeader = data.rows[r]
        let colHeader = !data.columns.isEmpty && c < data.columns.count ? data.columns[c] : nil
        let isTotal = rowHeader.isGrandTotal || rowHeader.isSubtotal || (colHeader.map { $0.isGrandTotal || $0.isSubtotal || $0.isExpanded || ($0.level >= 1 && $0.hasChildren) } ?? false)

        let pointID = cellPointID(row: r, col: c)
        let isSelected = context.selection.contains(pointID)

        // Tính màu nền, màu chữ và thanh dữ liệu theo Conditional Formatting (Rules > Field value > Gradient, Wave 3B / VM-V11B)
        let measureRef = m < data.measures.count ? data.measures[m].queryRef : ""
        let numVal = NumberDisplay.numericValue(cell.value)
        let mm = gradientMinMax[m] ?? MatrixVisualView.columnMinMax(data: data, measureIndex: m)
        let backColor: Color = CellFormatting.evaluateConditionalColor(
            property: "backColor", targetQueryRef: measureRef, numericValue: numVal,
            minVal: mm?.min, maxVal: mm?.max, isTotal: isTotal,
            cellOverrideHex: cell.backColor, format: context.format, theme: context.theme
        ) ?? .white

        let fontColor: Color = CellFormatting.evaluateConditionalColor(
            property: "fontColor", targetQueryRef: measureRef, numericValue: numVal,
            minVal: mm?.min, maxVal: mm?.max, isTotal: isTotal,
            cellOverrideHex: cell.fontColor, format: context.format, theme: context.theme
        ) ?? context.theme.foregroundColor

        let dataBar = mm.flatMap {
            CellFormatting.evaluateDataBar(
                targetQueryRef: measureRef, numericValue: numVal,
                columnMin: $0.min, columnMax: $0.max, isTotal: isTotal,
                format: context.format, theme: context.theme
            )
        }

        // Icon từ measure (nếu có SVG data URI)
        let iconImage: NSImage?
        if let iconStr = cell.icon {
            iconImage = MatrixIcon.image(from: iconStr)
        } else {
            iconImage = nil
        }

        let displayText = (dataBar?.hideText == true || cell.value == .blank) ? "" : NumberDisplay.plain(cell)

        return HStack(spacing: 3) {
            Spacer(minLength: 0)

            if let img = iconImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
            }

            Text(displayText)
                .font(.system(
                    size: CGFloat(context.format.matrix.valuesFontSize ?? 10),
                    weight: isTotal ? .bold : .regular
                ))
                .foregroundStyle(fontColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backColor)
        .overlay(CellFormatting.dataBarOverlay(dataBar))
        .overlay(selectionOverlay(isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            let additive = flags.contains(.command) || flags.contains(.control)
            context.actions.select(pointID, additive)
        }
    }

    // MARK: - Trợ giúp DataPointID và viền

    private var cellBorder: some View {
        Rectangle()
            .stroke(Color(hex: "#E5E7EB") ?? Color.gray.opacity(0.2), lineWidth: 0.5)
    }

    @ViewBuilder
    private func selectionOverlay(_ isSelected: Bool) -> some View {
        if isSelected {
            Rectangle()
                .stroke(Color(hex: "#118DFF") ?? Color.accentColor, lineWidth: 1.5)
        }
    }

    private func cellPointID(row r: Int, col c: Int) -> DataPointID {
        var values: [String: Value] = [:]
        let rowHeader = data.rows[r]
        for (i, val) in rowHeader.path.enumerated() {
            if i < data.rowLevels.count {
                values[data.rowLevels[i].queryRef] = val
            }
        }
        if !data.columns.isEmpty && c < data.columns.count {
            let colHeader = data.columns[c]
            for (j, val) in colHeader.path.enumerated() {
                if j < data.columnLevels.count {
                    values[data.columnLevels[j].queryRef] = val
                }
            }
        }
        return DataPointID(values)
    }

    private func rowPointID(row r: Int) -> DataPointID {
        var values: [String: Value] = [:]
        let rowHeader = data.rows[r]
        for (i, val) in rowHeader.path.enumerated() {
            if i < data.rowLevels.count {
                values[data.rowLevels[i].queryRef] = val
            }
        }
        return DataPointID(values)
    }

    private func columnPointID(path: [Value]) -> DataPointID {
        var values: [String: Value] = [:]
        for (j, val) in path.enumerated() where j < data.columnLevels.count { values[data.columnLevels[j].queryRef] = val }
        return DataPointID(values)
    }

    private func columnPointID(col c: Int) -> DataPointID {
        var values: [String: Value] = [:]
        if !data.columns.isEmpty && c < data.columns.count {
            let colHeader = data.columns[c]
            for (j, val) in colHeader.path.enumerated() {
                if j < data.columnLevels.count {
                    values[data.columnLevels[j].queryRef] = val
                }
            }
        }
        return DataPointID(values)
    }
}


// MARK: - Cuộn bằng con lăn chuột

/// Chuột có con lăn (không có pha cuộn như trackpad) không làm `ScrollView` của matrix cuộn khi trang đang vừa khung
/// (ScrollView ngoài của trang bị tắt). Lớp này nhận mọi sự kiện cuộn, tìm `NSScrollView` nhỏ nhất bên dưới con trỏ rồi
/// tự cuộn: con lăn cuộn dọc, Shift hoặc con lăn ngang cuộn ngang.
private struct WheelScrollAssist: NSViewRepresentable {
    func makeNSView(context: Context) -> AssistView { AssistView() }
    func updateNSView(_ nsView: AssistView, context: Context) {}

    final class AssistView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .scrollWheel else { return nil }
            return self
        }

        override func scrollWheel(with event: NSEvent) {
            guard let scroll = innermostScrollView(at: event.locationInWindow), scroll.documentView != nil else {
                nextResponder?.scrollWheel(with: event)
                return
            }
            // Tốc độ do lớp này quyết định cho cả con lăn lẫn trackpad (như combo "Rủi ro thấu chi"): trang thường thu nhỏ khoảng 40%
            // nên cuộn theo điểm của ScrollView trông chậm. Con lăn: 100 điểm mỗi nấc; trackpad: nhân 2,5.
            let unit: CGFloat = event.hasPreciseScrollingDeltas ? 2.5 : 100
            var dx = event.scrollingDeltaX * unit
            var dy = event.scrollingDeltaY * unit
            if event.modifierFlags.contains(.shift), dx == 0 { dx = dy; dy = 0 }
            let clip = scroll.contentView
            let document = scroll.documentView?.frame ?? .zero
            let maxX = max(0, document.width - clip.bounds.width), maxY = max(0, document.height - clip.bounds.height)
            var origin = clip.bounds.origin
            origin.x = min(max(0, origin.x - dx), maxX)
            origin.y = min(max(0, origin.y - dy), maxY)
            guard origin != clip.bounds.origin else { nextResponder?.scrollWheel(with: event); return }
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
        }

        private func innermostScrollView(at windowPoint: NSPoint) -> NSScrollView? {
            guard let root = window?.contentView else { return nil }
            var best: NSScrollView?
            func visit(_ view: NSView) {
                if let scroll = view as? NSScrollView, !scroll.isHidden {
                    let local = scroll.convert(windowPoint, from: nil)
                    if scroll.bounds.contains(local), isAncestorOrSelf(self, ofOverlap: scroll) {
                        if best == nil || scroll.bounds.width * scroll.bounds.height < best!.bounds.width * best!.bounds.height { best = scroll }
                    }
                }
                view.subviews.forEach(visit)
            }
            visit(root)
            return best
        }

        /// Chỉ nhận `NSScrollView` thuộc cùng visual với lớp này: nằm trong khung của lớp này.
        private func isAncestorOrSelf(_ me: NSView, ofOverlap scroll: NSScrollView) -> Bool {
            let mine = me.convert(me.bounds, to: nil)
            let theirs = scroll.convert(scroll.bounds, to: nil)
            return mine.intersects(theirs) && theirs.width <= mine.width + 1 && theirs.height <= mine.height + 1
        }
    }
}
