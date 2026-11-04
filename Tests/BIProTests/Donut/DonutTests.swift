import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite struct DonutTests {

    // MARK: - 1. Slices: góc đầu, khít góc, bỏ qua âm/0/NaN, highlights
    @Test func donutSlicesProperties() {
        let values: [Double] = [40.0, -15.0, 0.0, 60.0, Double.nan]
        let highlights: [Double] = [20.0, 5.0, 0.0, 90.0, 10.0]

        let slices = DonutLayout.slices(values: values, highlights: highlights)

        // Bỏ qua giá trị âm (-15), 0, NaN -> Chỉ còn 2 lát: 40 và 60
        #expect(slices.count == 2)

        // Tổng fraction = 1
        let totalFraction = slices.reduce(0.0) { $0 + $1.fraction }
        #expect(abs(totalFraction - 1.0) < 1e-9)

        // Góc đầu = -π/2
        #expect(abs(slices[0].startAngle - (-Double.pi / 2.0)) < 1e-9)

        // Lát liền kề khít góc
        #expect(abs(slices[0].endAngle - slices[1].startAngle) < 1e-9)

        // Góc kết thúc của lát cuối = góc đầu + 2π
        #expect(abs(slices[1].endAngle - (-Double.pi / 2.0 + 2.0 * Double.pi)) < 1e-9)

        // Fraction từng lát
        #expect(abs(slices[0].fraction - 0.40) < 1e-9)
        #expect(abs(slices[1].fraction - 0.60) < 1e-9)

        // Highlights đúng tỉ lệ (20/40 = 0.5) và lớn nhất 1 (90/60 = 1.5 -> capped tại 1.0)
        #expect(slices[0].highlightFraction != nil)
        #expect(abs(slices[0].highlightFraction! - 0.50) < 1e-9)

        #expect(slices[1].highlightFraction != nil)
        #expect(abs(slices[1].highlightFraction! - 1.0) < 1e-9)
    }

    // MARK: - 2. PercentText: ít nhất 5 ca, gồm 94.8%, 1.81%, 0.48%
    @Test func donutPercentTextCases() {
        #expect(DonutLayout.percentText(0.948) == "94.8%")
        #expect(DonutLayout.percentText(0.0181) == "1.81%")
        #expect(DonutLayout.percentText(0.0048) == "0.48%")
        #expect(DonutLayout.percentText(0.50) == "50.0%")
        #expect(DonutLayout.percentText(0.025) == "2.50%")
        #expect(DonutLayout.percentText(1.0) == "100.0%")
    }

    // MARK: - 3. Số ở giữa từ mẫu donutPurpose: precision = 1 và .auto
    @Test func donutCenterTextFromSample() {
        guard case .categorical(let data) = DataViewSamples.donutPurpose else {
            Issue.record("donutPurpose không phải categorical")
            return
        }

        // Khi precision = 1: $103.3M
        var formatWithPrecision = VisualFormat()
        formatWithPrecision.dataLabels.displayUnits = .auto
        formatWithPrecision.dataLabels.precision = 1
        let textPrecision1 = DonutLayout.centerText(data: data, format: formatWithPrecision)
        #expect(textPrecision1 == "$103.3M")

        // Khi precision = nil (.auto): $103M (theo formatString "\\$#,0")
        var formatAuto = VisualFormat()
        formatAuto.dataLabels.displayUnits = .auto
        formatAuto.dataLabels.precision = nil
        let textAuto = DonutLayout.centerText(data: data, format: formatAuto)
        #expect(textAuto == "$103M")
    }

    // MARK: - 4. Thứ tự ưu tiên màu của một lát
    @Test func donutColorPrecedence() {
        let theme = ReportTheme.fallback
        let catLevel = FieldInfo(queryRef: "Dim_Loan.purpose", displayName: "Mục đích", role: "Category", isMeasure: false)
        let catKey = CategoryKey(values: [.string("Mua nhà")])
        let measure = FieldInfo(queryRef: "Fact_Loan.Amount", displayName: "Giá trị", role: "Y", isMeasure: true)

        // 1. fillColor ưu tiên cao nhất
        var cellWithFill = DataCell(.double(100), fillColor: "#FF0000")
        var format = VisualFormat()
        format.dataPoint.defaultFill = .string("#0000FF")
        format.dataPoint.fillByMeasure[measure.queryRef] = .string("#00FF00")
        format.dataPoint.fillByValue[ScopedValue(column: catLevel.queryRef, value: .string("Mua nhà"))] = .string("#FFFF00")

        let lit1 = DonutLayout.resolveColorLiteral(
            cell: cellWithFill,
            categoryKey: catKey,
            categoryLevels: [catLevel],
            measure: measure,
            format: format
        )
        #expect(lit1 == .string("#FF0000"))

        // 2. Không có cell.fillColor -> dùng fillByValue
        cellWithFill.fillColor = nil
        let lit2 = DonutLayout.resolveColorLiteral(
            cell: cellWithFill,
            categoryKey: catKey,
            categoryLevels: [catLevel],
            measure: measure,
            format: format
        )
        #expect(lit2 == .string("#FFFF00"))

        // 3. Không có fillByValue -> dùng fillByMeasure
        format.dataPoint.fillByValue.removeAll()
        let lit3 = DonutLayout.resolveColorLiteral(
            cell: cellWithFill,
            categoryKey: catKey,
            categoryLevels: [catLevel],
            measure: measure,
            format: format
        )
        #expect(lit3 == .string("#00FF00"))

        // 4. Không có fillByMeasure -> dùng defaultFill
        format.dataPoint.fillByMeasure.removeAll()
        let lit4 = DonutLayout.resolveColorLiteral(
            cell: cellWithFill,
            categoryKey: catKey,
            categoryLevels: [catLevel],
            measure: measure,
            format: format
        )
        #expect(lit4 == .string("#0000FF"))

        // 5. Không có defaultFill -> fallback theme.dataColor
        format.dataPoint.defaultFill = nil
        let lit5 = DonutLayout.resolveColorLiteral(
            cell: cellWithFill,
            categoryKey: catKey,
            categoryLevels: [catLevel],
            measure: measure,
            format: format
        )
        #expect(lit5 == nil)
        let col5 = DonutLayout.resolveColor(
            cell: cellWithFill,
            categoryIndex: 2,
            categoryKey: catKey,
            categoryLevels: [catLevel],
            measure: measure,
            format: format,
            theme: theme
        )
        #expect(col5 == theme.dataColor(2))
    }
}
