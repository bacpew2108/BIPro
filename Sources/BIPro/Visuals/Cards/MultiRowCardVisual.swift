import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

struct MultiRowCardView: View {
    let data: MultiRowCardData
    let context: VisualRenderContext
    let scrollable: Bool

    init(data: MultiRowCardData, context: VisualRenderContext, scrollable: Bool = true) {
        self.data = data
        self.context = context
        self.scrollable = scrollable
    }

    var body: some View {
        let accent = context.theme.dataColor(0)
        let valueFont = ReportUnits.pixels(fromPoints: context.format.dataLabels.fontSize ?? 13)
        let labelFont = ReportUnits.pixels(fromPoints: context.format.categoryLabels.fontSize ?? 9)

        if data.fields.isEmpty || data.rows.isEmpty {
            ZStack {
                Color.clear
                Text(bi("Không có dữ liệu", "No data"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            let content = LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(data.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(accent)
                            .frame(width: 3)

                        FlowOrGridRow(fields: data.fields, row: row, valueFont: valueFont, labelFont: labelFont)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.black.opacity(0.06)).frame(height: 0.5)
                    }
                }
            }
            .padding(6)

            if scrollable {
                ScrollView(.vertical) {
                    content
                }
                .background(Color.white)
            } else {
                content.background(Color.white)
            }
        }
    }
}

private struct FlowOrGridRow: View {
    let fields: [FieldInfo]
    let row: [DataCell]
    let valueFont: CGFloat
    let labelFont: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(fields.enumerated()), id: \.offset) { idx, field in
                let cell = idx < row.count ? row[idx] : .blank
                let text = TableVisualView.cellText(cell, field: field)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.isEmpty ? biN("(Trống)", "(Blank)") : text)
                        .font(.system(size: valueFont, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(hex: "#252423") ?? .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(field.displayName)
                        .font(.system(size: labelFont))
                        .foregroundStyle(Color(hex: "#605E5C") ?? .secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 64, alignment: .leading)
            }
        }
    }
}
