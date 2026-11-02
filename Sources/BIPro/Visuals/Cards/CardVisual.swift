import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

enum CardVisual {
    /// Văn bản hiển thị của card:
    /// - Giá trị BLANK hiện "(Trống)" như Power BI hiện "(Blank)";
    /// - Số đi qua `NumberDisplay.text` với đơn vị và độ chính xác từ `format.dataLabels`;
    /// - Chuỗi/khác giữ nguyên văn.
    static func text(for data: SingleValueData, format: VisualFormat) -> String {
        if case .blank = data.cell.value {
            return "(Trống)"
        }
        return NumberDisplay.text(
            data.cell,
            units: format.dataLabels.displayUnits,
            precision: format.dataLabels.precision
        )
    }

    /// Màu chữ của giá trị theo thứ tự ưu tiên:
    /// 1. `DataCell.fontColor` (lấy từ measure);
    /// 2. `dataLabels.color` (giải qua theme);
    /// 3. `theme.foregroundColor`.
    static func valueColor(
        for data: SingleValueData,
        format: VisualFormat,
        theme: ReportTheme = .fallback
    ) -> Color {
        if let fontHex = data.cell.fontColor, let c = Color(hex: fontHex) {
            return c
        }
        if let labelColor = theme.color(format.dataLabels.color) {
            return labelColor
        }
        return theme.foregroundColor
    }
}

struct CardVisualView: View {
    let data: SingleValueData
    let context: VisualRenderContext

    init(data: SingleValueData, context: VisualRenderContext) {
        self.data = data
        self.context = context
    }

    var body: some View {
        let valueStr = CardVisual.text(for: data, format: context.format)
        let valueColor = CardVisual.valueColor(for: data, format: context.format, theme: context.theme)
        let valueFontSize = ReportUnits.pixels(fromPoints: context.format.dataLabels.fontSize ?? 27)
        let categoryFontSize = ReportUnits.pixels(fromPoints: context.format.categoryLabels.fontSize ?? 12)
        let categoryColor = context.theme.color(context.format.categoryLabels.color) ?? Color(hex: "#6A7179") ?? .secondary
        let showCategory = context.format.categoryLabels.show ?? true

        VStack(spacing: 4) {
            Text(valueStr)
                .font(.system(
                    size: valueFontSize,
                    weight: context.format.dataLabels.bold == true ? .bold : .medium
                ))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.2)

            if showCategory {
                Text(data.measure.displayName)
                    .font(.system(size: categoryFontSize))
                    .foregroundStyle(categoryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
