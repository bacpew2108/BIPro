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
                        ForEach(0..<data.columns.count, id: \.self) { c in
                            columnHeaderCell(colIndex: c, tier: tier)
                                .frame(width: layout.width(forColumn: c), height: layout.headerHeight)
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
        if tier == layout.headerTiers - 1 {
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

    private func columnHeaderCell(colIndex c: Int, tier: Int) -> some View {
        let col = data.columns[c]
        let isTotal = col.isGrandTotal || col.isSubtotal
        // Mỗi tầng chỉ ghi nhãn của cấp tương ứng; tổng chung ghi "Total" ở tầng cuối.
        let label: String
        if col.isGrandTotal {
            label = tier == layout.headerTiers - 1 ? "Total" : ""
        } else if tier < col.path.count {
            label = col.path[tier].asText()
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
        let label = row.isGrandTotal ? "Total" : (row.path.last?.asText() ?? "")
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
        let isTotal = rowHeader.isGrandTotal || rowHeader.isSubtotal || (colHeader?.isGrandTotal == true || colHeader?.isSubtotal == true)

        let pointID = cellPointID(row: r, col: c)
        let isSelected = context.selection.contains(pointID)

        // Tính màu nền: cell.backColor > gradient > white
        let backColor: Color
        if let hex = cell.backColor, let c = Color(hex: hex) {
            backColor = c
        } else if !isTotal,
                  let rule = context.format.gradients.first(where: { $0.property == "backColor" }),
                  let (minVal, maxVal) = gradientMinMax[m] {
            let num = NumberDisplay.numericValue(cell.value)
            backColor = MatrixGradient.color(value: num, min: minVal, max: maxVal, rule: rule, theme: context.theme) ?? .white
        } else {
            backColor = .white
        }

        // Tính màu chữ: cell.fontColor > mặc định
        let fontColor: Color
        if let hex = cell.fontColor, let c = Color(hex: hex) {
            fontColor = c
        } else {
            fontColor = context.theme.foregroundColor
        }

        // Icon từ measure (nếu có SVG data URI)
        let iconImage: NSImage?
        if let iconStr = cell.icon {
            iconImage = MatrixIcon.image(from: iconStr)
        } else {
            iconImage = nil
        }

        let displayText = cell.value == .blank ? "" : NumberDisplay.plain(cell)

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
