import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

struct TableVisualView: View {
    let data: TableDataView
    let context: VisualRenderContext
    let scrollable: Bool

    @State private var sortColumn: Int? = nil
    @State private var sortAscending: Bool = true

    init(data: TableDataView, context: VisualRenderContext, scrollable: Bool = true) {
        self.data = data
        self.context = context
        self.scrollable = scrollable
    }

    private var sortedRowIndices: [Int] {
        let base = Array(data.rows.indices)
        guard let col = sortColumn, col < data.columns.count else { return base }
        return base.sorted { lhs, rhs in
            let a = col < data.rows[lhs].count ? data.rows[lhs][col].value : .blank
            let b = col < data.rows[rhs].count ? data.rows[rhs][col].value : .blank
            if a == b { return lhs < rhs }
            return sortAscending ? FilterTranslator.valuePrecedes(a, b) : FilterTranslator.valuePrecedes(b, a)
        }
    }

    private var columnWidths: [CGFloat] {
        let fontSize = ReportUnits.pixels(fromPoints: context.format.matrix.valuesFontSize ?? 10)
        let charW = fontSize * 0.62
        return data.columns.enumerated().map { idx, col in
            var maxChars = max(6, col.displayName.count + 2)
            for row in data.rows.prefix(60) where idx < row.count {
                let text = Self.cellText(row[idx], field: col)
                if text.count > maxChars { maxChars = text.count }
            }
            if let totals = data.totals, idx < totals.count {
                let text = Self.cellText(totals[idx], field: col)
                if text.count > maxChars { maxChars = text.count }
            }
            return min(240, max(72, CGFloat(maxChars) * charW + 20))
        }
    }

    static func cellText(_ cell: DataCell, field: FieldInfo) -> String {
        switch cell.value {
        case .blank: return ""
        case .string(let s): return s
        default:
            if cell.formatString != nil || field.formatString != nil {
                var copy = cell
                if copy.formatString == nil { copy.formatString = field.formatString }
                return NumberDisplay.plain(copy)
            }
            return field.text(cell.value)
        }
    }

    static func isRightAligned(_ cell: DataCell, field: FieldInfo) -> Bool {
        if field.isMeasure { return true }
        switch cell.value {
        case .integer, .double, .currency: return true
        default: return false
        }
    }

    private func pointID(forRow rowIndex: Int) -> DataPointID? {
        guard rowIndex < data.rows.count else { return nil }
        let row = data.rows[rowIndex]
        var dict: [String: Value] = [:]
        for (idx, col) in data.columns.enumerated() where !col.isMeasure && idx < row.count {
            dict[col.queryRef] = row[idx].value
        }
        return dict.isEmpty ? nil : DataPointID(dict)
    }

    var body: some View {
        let widths = columnWidths
        let totalW = widths.reduce(0, +)
        if data.columns.isEmpty {
            ZStack {
                Color.white
                Text(bi("Thêm trường để vẽ bảng", "Add fields to display table"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else if scrollable {
            ScrollView([.horizontal, .vertical]) {
                tableGrid(widths: widths)
                    .frame(minWidth: totalW, alignment: .topLeading)
            }
            .background(Color.white)
        } else {
            tableGrid(widths: widths)
                .frame(minWidth: totalW, alignment: .topLeading)
                .background(Color.white)
        }
    }

    private func tableGrid(widths: [CGFloat]) -> some View {
        let headerFont = ReportUnits.pixels(fromPoints: context.format.matrix.columnHeaderFontSize ?? 10)
        let valueFont = ReportUnits.pixels(fromPoints: context.format.matrix.valuesFontSize ?? 10)
        let rowPad = CGFloat(context.format.matrix.rowPadding ?? 4)
        let rowHeight = max(22, valueFont + rowPad * 2 + 6)
        let headerHeight = max(26, headerFont + 14)
        let accent = context.theme.dataColor(0)
        let indices = sortedRowIndices

        return VStack(spacing: 0) {
            headerRow(widths: widths, fontSize: headerFont, height: headerHeight, accent: accent)
            ForEach(Array(indices.enumerated()), id: \.element) { displayIdx, rowIndex in
                dataRow(displayIdx: displayIdx, rowIndex: rowIndex, widths: widths, fontSize: valueFont, height: rowHeight, accent: accent)
            }
            if let totals = data.totals, !totals.isEmpty {
                totalRow(totals: totals, widths: widths, fontSize: valueFont, height: rowHeight + 2, accent: accent)
            }
        }
    }

    private func headerRow(widths: [CGFloat], fontSize: CGFloat, height: CGFloat, accent: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(data.columns.enumerated()), id: \.offset) { idx, col in
                let sampleCell = data.rows.first.flatMap { idx < $0.count ? $0[idx] : nil } ?? .blank
                let right = Self.isRightAligned(sampleCell, field: col)
                Button {
                    if sortColumn == idx { sortAscending.toggle() } else { sortColumn = idx; sortAscending = true }
                } label: {
                    HStack(spacing: 4) {
                        if right { Spacer(minLength: 0) }
                        Text(col.displayName)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(Color(hex: "#252423") ?? .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if sortColumn == idx {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(accent)
                        }
                        if !right { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: widths[idx], height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!scrollable)
            }
        }
        .background(Color(hex: "#FAFAFA") ?? Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(accent).frame(height: 1.5)
        }
    }

    private func dataRow(displayIdx: Int, rowIndex: Int, widths: [CGFloat], fontSize: CGFloat, height: CGFloat, accent: Color) -> some View {
        let row = data.rows[rowIndex]
        let pt = pointID(forRow: rowIndex)
        let isSelected = pt.map { context.selection.contains($0) } ?? false
        let isDimmed = !context.selection.isEmpty && !isSelected
        let stripe: Color = displayIdx % 2 == 1 ? (Color(hex: "#F8F9FA") ?? Color.white) : Color.white
        let rowBg: Color = isSelected ? accent.opacity(0.14) : stripe

        return HStack(spacing: 0) {
            ForEach(Array(data.columns.enumerated()), id: \.offset) { cIdx, col in
                dataCellView(row: row, colIndex: cIdx, col: col, width: widths[cIdx], fontSize: fontSize, height: height)
            }
        }
        .background(rowBg)
        .opacity(isDimmed ? 0.45 : 1.0)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard scrollable, let pt else { return }
            let additive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
            context.actions.select(pt, additive)
        }
    }

    private func dataCellView(row: [DataCell], colIndex: Int, col: FieldInfo, width: CGFloat, fontSize: CGFloat, height: CGFloat) -> some View {
        let cell = colIndex < row.count ? row[colIndex] : .blank
        let text = Self.cellText(cell, field: col)
        let right = Self.isRightAligned(cell, field: col)
        let fg: Color = cell.fontColor.flatMap { Color(hex: $0) } ?? (Color(hex: "#252423") ?? .primary)
        let bg: Color = cell.backColor.flatMap { Color(hex: $0) } ?? Color.clear
        return Text(text)
            .font(.system(size: fontSize).monospacedDigit())
            .foregroundStyle(fg)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
            .padding(.horizontal, 8)
            .frame(width: width, height: height)
            .background(bg)
    }

    private func totalRow(totals: [DataCell], widths: [CGFloat], fontSize: CGFloat, height: CGFloat, accent: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(data.columns.enumerated()), id: \.offset) { cIdx, col in
                let cell = cIdx < totals.count ? totals[cIdx] : .blank
                let rawText = Self.cellText(cell, field: col)
                let text = (cIdx == 0 && rawText.isEmpty) ? "Total" : rawText
                let right = cIdx > 0 && Self.isRightAligned(cell, field: col)
                Text(text)
                    .font(.system(size: fontSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(hex: "#252423") ?? .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
                    .padding(.horizontal, 8)
                    .frame(width: widths[cIdx], height: height)
            }
        }
        .background(Color(hex: "#F3F4F6") ?? Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(accent.opacity(0.7)).frame(height: 1)
        }
    }
}
