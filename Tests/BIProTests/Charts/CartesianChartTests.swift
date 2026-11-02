import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite struct CartesianChartTests {
    
    // MARK: - 1. niceTicks và labels
    
    @Test func niceTicksVaLabels6Ca() {
        // Ca 1: (0…30M, $#,0) → ["$0M","$10M","$20M","$30M"]
        let ticks1 = ChartAxis.niceTicks(min: 0, max: 30_000_000, targetCount: 4)
        #expect(ticks1 == [0, 10_000_000, 20_000_000, 30_000_000])
        let labels1 = ChartAxis.labels(ticks: ticks1, units: .auto, precision: nil, formatString: "$#,0")
        #expect(labels1 == ["$0M", "$10M", "$20M", "$30M"])
        
        // Ca 2: (0…1bn bước 0.5bn) → ["$0.0bn","$0.5bn","$1.0bn"]
        let ticks2 = ChartAxis.niceTicks(min: 0, max: 1_000_000_000, targetCount: 3)
        #expect(ticks2 == [0, 500_000_000, 1_000_000_000])
        let labels2 = ChartAxis.labels(ticks: ticks2, units: .auto, precision: nil, formatString: "$#,0")
        #expect(labels2 == ["$0.0bn", "$0.5bn", "$1.0bn"])
        
        // Ca 3: định dạng 0% → ["0%","5%","10%","15%"]
        let ticks3 = ChartAxis.niceTicks(min: 0, max: 0.15, targetCount: 4)
        #expect(ticks3 == [0.0, 0.05, 0.10, 0.15])
        let labels3 = ChartAxis.labels(ticks: ticks3, units: .auto, precision: nil, formatString: "0%")
        #expect(labels3 == ["0%", "5%", "10%", "15%"])
        
        // Ca 4: Số âm đến số dương, bước 10
        let ticks4 = ChartAxis.niceTicks(min: -20, max: 30, targetCount: 6)
        #expect(ticks4 == [-20.0, -10.0, 0.0, 10.0, 20.0, 30.0])
        let labels4 = ChartAxis.labels(ticks: ticks4, units: .none, precision: nil, formatString: "#,0")
        #expect(labels4 == ["-20", "-10", "0", "10", "20", "30"])
        
        // Ca 5: Đơn vị ngàn (thousands / K)
        let ticks5 = ChartAxis.niceTicks(min: 0, max: 50_000, targetCount: 6)
        #expect(ticks5 == [0.0, 10_000.0, 20_000.0, 30_000.0, 40_000.0, 50_000.0])
        let labels5 = ChartAxis.labels(ticks: ticks5, units: .thousands, precision: nil, formatString: "$#,0")
        #expect(labels5 == ["$0K", "$10K", "$20K", "$30K", "$40K", "$50K"])
        
        // Ca 6: Precision cố định (precision: 2)
        let ticks6 = [0.0, 10_000_000.0, 20_000_000.0]
        let labels6 = ChartAxis.labels(ticks: ticks6, units: .millions, precision: 2, formatString: "$#,0")
        #expect(labels6 == ["$0.00M", "$10.00M", "$20.00M"])
        
        // Ca 7: Phần trăm có số lẻ
        let ticks7 = [0.0, 0.025, 0.050]
        let labels7 = ChartAxis.labels(ticks: ticks7, formatString: "0.0%")
        #expect(labels7 == ["0.0%", "2.5%", "5.0%"])
    }
    
    // MARK: - 2. StackLayout
    
    @Test func stackLayoutChongDuongAmVaChuanHoa100() {
        // Chồng dương/âm không chuẩn hoá
        let rawValues: [Double?] = [10.0, -5.0, 20.0, -15.0]
        let segs = StackLayout.segments(values: rawValues, isNormalized: false)
        #expect(segs.count == 4)
        
        #expect(segs[0].y0 == 0.0 && segs[0].y1 == 10.0 && !segs[0].isBlank)
        #expect(segs[1].y0 == 0.0 && segs[1].y1 == -5.0 && !segs[1].isBlank)
        #expect(segs[2].y0 == 10.0 && segs[2].y1 == 30.0 && !segs[2].isBlank)
        #expect(segs[3].y0 == -5.0 && segs[3].y1 == -20.0 && !segs[3].isBlank)
        
        // Chuẩn hoá 100% với cột có BLANK
        let normValues: [Double?] = [10.0, nil, 30.0, -10.0, -10.0]
        let segsNorm = StackLayout.segments(values: normValues, isNormalized: true)
        #expect(segsNorm.count == 5)
        
        // Dương: tổng 40 → 10/40 = 0.25, 30/40 = 0.75
        #expect(abs(segsNorm[0].y0 - 0.0) < 1e-9)
        #expect(abs(segsNorm[0].y1 - 0.25) < 1e-9)
        #expect(!segsNorm[0].isBlank)
        
        // BLANK
        #expect(segsNorm[1].isBlank)
        #expect(segsNorm[1].y0 == 0.0 && segsNorm[1].y1 == 0.0)
        
        // Dương tiếp theo
        #expect(abs(segsNorm[2].y0 - 0.25) < 1e-9)
        #expect(abs(segsNorm[2].y1 - 1.0) < 1e-9)
        #expect(!segsNorm[2].isBlank)
        
        // Âm: tổng -20 → -10/20 = -0.5, -10/20 = -0.5
        #expect(abs(segsNorm[3].y0 - 0.0) < 1e-9)
        #expect(abs(segsNorm[3].y1 - -0.5) < 1e-9)
        #expect(!segsNorm[3].isBlank)
        
        #expect(abs(segsNorm[4].y0 - -0.5) < 1e-9)
        #expect(abs(segsNorm[4].y1 - -1.0) < 1e-9)
        #expect(!segsNorm[4].isBlank)
    }
    
    // MARK: - 3. TrendLine.linearFit
    
    @Test func trendLineFit() {
        // Điểm thẳng hàng
        let linePoints: [(x: Double, y: Double)] = [(1.0, 2.0), (2.0, 4.0), (3.0, 6.0)]
        let fit = TrendLine.linearFit(linePoints)
        #expect(fit != nil)
        if let f = fit {
            #expect(abs(f.slope - 2.0) < 1e-9)
            #expect(abs(f.intercept - 0.0) < 1e-9)
        }
        
        // 1 điểm → nil
        #expect(TrendLine.linearFit([(1.0, 2.0)]) == nil)
        
        // Dữ liệu lineMonthlyAmount → slope > 0
        guard case .categorical(let d) = DataViewSamples.lineMonthlyAmount else {
            Issue.record("DataViewSamples.lineMonthlyAmount không phải categorical")
            return
        }
        var monthlyPoints: [(x: Double, y: Double)] = []
        for (i, _) in d.categories.enumerated() {
            let cell = d.cell(measure: 0, series: 0, category: i)
            if let val = NumberDisplay.numericValue(cell.value) {
                monthlyPoints.append((x: Double(i), y: val))
            }
        }
        #expect(monthlyPoints.count == 72)
        let monthlyFit = TrendLine.linearFit(monthlyPoints)
        #expect(monthlyFit != nil)
        #expect((monthlyFit?.slope ?? 0) > 0)
    }
    
    // MARK: - 4. CartesianKind(visualType:)
    
    @Test func cartesianKindVisualTypes() {
        #expect(CartesianKind(visualType: "clusteredBarChart") == .clusteredBar)
        #expect(CartesianKind(visualType: "clusteredColumnChart") == .clusteredColumn)
        #expect(CartesianKind(visualType: "stackedColumnChart") == .stackedColumn)
        #expect(CartesianKind(visualType: "hundredPercentStackedColumnChart") == .hundredPercentStackedColumn)
        #expect(CartesianKind(visualType: "lineChart") == .line)
        #expect(CartesianKind(visualType: "lineClusteredColumnComboChart") == .comboClustered)
        #expect(CartesianKind(visualType: "lineStackedColumnComboChart") == .comboStacked)
        
        // Chuỗi lạ → nil
        #expect(CartesianKind(visualType: "pieChart") == nil)
        #expect(CartesianKind(visualType: "unknownVisual") == nil)
    }
    
    // MARK: - 5. Thứ tự ưu tiên màu
    
    @Test func thuTuUuTienMau() {
        let theme = ReportTheme.fallback
        var format = VisualFormat()
        let measure = FieldInfo(queryRef: "Fact.Amt", displayName: "Amt", role: "Y", formatString: nil, isMeasure: true)
        let seriesField = FieldInfo(queryRef: "Dim.Series", displayName: "Series", role: "Series", formatString: nil, isMeasure: false)
        let seriesValue = Value.string("Tier1")
        
        // 1. DataCell.fillColor có ưu tiên cao nhất
        let cell1 = DataCell(.double(10), fillColor: "#111111")
        format.dataPoint.defaultFill = .string("#555555")
        format.dataPoint.fillByMeasure["Fact.Amt"] = .string("#444444")
        format.dataPoint.fillByValue[ScopedValue(column: "Dim.Series", value: .string("Tier1"))] = .string("#333333")
        let lit1 = ChartColorResolver.resolveLiteral(
            cell: cell1,
            seriesValue: seriesValue,
            seriesField: seriesField,
            measure: measure,
            format: format
        )
        #expect(lit1 == .string("#111111"))
        
        // 2. Không có cell.fillColor → format.dataPoint.fillByValue
        let cell2 = DataCell(.double(10), fillColor: nil)
        let lit2 = ChartColorResolver.resolveLiteral(
            cell: cell2,
            seriesValue: seriesValue,
            seriesField: seriesField,
            measure: measure,
            format: format
        )
        #expect(lit2 == .string("#333333"))
        
        // 3. Không khớp fillByValue → format.dataPoint.fillByMeasure[queryRef]
        var format3 = format
        format3.dataPoint.fillByValue = [:]
        let lit3 = ChartColorResolver.resolveLiteral(
            cell: cell2,
            seriesValue: seriesValue,
            seriesField: seriesField,
            measure: measure,
            format: format3
        )
        #expect(lit3 == .string("#444444"))
        
        // 4. Không có fillByMeasure → defaultFill
        var format4 = format3
        format4.dataPoint.fillByMeasure = [:]
        let lit4 = ChartColorResolver.resolveLiteral(
            cell: cell2,
            seriesValue: seriesValue,
            seriesField: seriesField,
            measure: measure,
            format: format4
        )
        #expect(lit4 == .string("#555555"))
        
        // 5. Không có gì ghi đè → mặc định theme.dataColor(i)
        var format5 = format4
        format5.dataPoint.defaultFill = nil
        let colSeries = ChartColorResolver.resolveColor(
            cell: cell2,
            seriesValue: seriesValue,
            seriesField: seriesField,
            seriesIndex: 1,
            hasSeries: true,
            measure: measure,
            measureIndex: 0,
            format: format5,
            theme: theme
        )
        #expect(colSeries == theme.dataColor(1))
        
        let colMeasure = ChartColorResolver.resolveColor(
            cell: cell2,
            seriesValue: nil,
            seriesField: nil,
            seriesIndex: 0,
            hasSeries: false,
            measure: measure,
            measureIndex: 2,
            format: format5,
            theme: theme
        )
        #expect(colMeasure == theme.dataColor(2))
    }
    
    // MARK: - 6. Combo secondaryScale
    
    @Test func comboSecondaryScale() {
        let scaled1 = ComboChart.secondaryScale(value: 100, y2Min: 0, y2Max: 200, targetMin: 0, targetMax: 30_000_000)
        #expect(abs(scaled1 - 15_000_000) < 1e-6)
        
        let scaled2 = ComboChart.secondaryScale(value: 0, y2Range: 0...200, targetRange: 0...30_000_000)
        #expect(abs(scaled2 - 0) < 1e-6)
        
        let scaled3 = ComboChart.secondaryScale(value: 200, y2Range: 0...200, targetRange: 0...30_000_000)
        #expect(abs(scaled3 - 30_000_000) < 1e-6)
    }
    
    // MARK: - 7. Xuất ảnh ImageRenderer (640×380) ra PNG
    
    @MainActor
    @Test func xuatAnhMoiMau() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = fileURL
            .deletingLastPathComponent() // Charts
            .deletingLastPathComponent() // BIProTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let outDir = repoRoot.appendingPathComponent("build/c-out/visuals")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        
        let targetSize = CGSize(width: 640, height: 380)
        
        func renderToPNG(view: some View) -> Data? {
            let renderer = ImageRenderer(content: view.frame(width: targetSize.width, height: targetSize.height))
            renderer.proposedSize = ProposedViewSize(targetSize)
            renderer.scale = 2.0
            if let cgImage = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                return rep.representation(using: .png, properties: [:])
            }
            if let nsImage = renderer.nsImage,
               let tiff = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                return rep.representation(using: .png, properties: [:])
            }
            return nil
        }
        
        // 1. comboLoansByYear (lineClusteredColumnCombo)
        guard case .categorical(let comboData) = DataViewSamples.comboLoansByYear else {
            Issue.record("comboLoansByYear không phải categorical")
            return
        }
        let view1 = CartesianChartView(
            data: comboData,
            kind: .comboClustered,
            context: VisualRenderContext(),
            interactive: false
        )
        let png1 = renderToPNG(view: view1)
        #expect(png1 != nil && !png1!.isEmpty)
        if let png1 = png1 {
            try png1.write(to: outDir.appendingPathComponent("comboLoansByYear.png"))
        }
        
        // 2. barNPLByAge (clusteredBar)
        guard case .categorical(let barData) = DataViewSamples.barNPLByAge else {
            Issue.record("barNPLByAge không phải categorical")
            return
        }
        var barFormat = VisualFormat()
        barFormat.dataLabels.show = true
        let view2 = CartesianChartView(
            data: barData,
            kind: .clusteredBar,
            context: VisualRenderContext(format: barFormat),
            interactive: false
        )
        let png2 = renderToPNG(view: view2)
        #expect(png2 != nil && !png2!.isEmpty)
        if let png2 = png2 {
            try png2.write(to: outDir.appendingPathComponent("barNPLByAge.png"))
        }
        
        // 3. lineMonthlyAmount (lineChart)
        guard case .categorical(let lineData) = DataViewSamples.lineMonthlyAmount else {
            Issue.record("lineMonthlyAmount không phải categorical")
            return
        }
        var lineFormat = VisualFormat()
        lineFormat.categoryAxis.axisType = "Scalar"
        lineFormat.analytics.trendShow = true
        let view3 = CartesianChartView(
            data: lineData,
            kind: .line,
            context: VisualRenderContext(format: lineFormat),
            interactive: false
        )
        let png3 = renderToPNG(view: view3)
        #expect(png3 != nil && !png3!.isEmpty)
        if let png3 = png3 {
            try png3.write(to: outDir.appendingPathComponent("lineMonthlyAmount.png"))
        }
        
        // 4. stackedComplaintsByChannel (lineStackedColumnCombo)
        guard case .categorical(let stackedData) = DataViewSamples.stackedComplaintsByChannel else {
            Issue.record("stackedComplaintsByChannel không phải categorical")
            return
        }
        let view4 = CartesianChartView(
            data: stackedData,
            kind: .comboStacked,
            context: VisualRenderContext(),
            interactive: false
        )
        let png4 = renderToPNG(view: view4)
        #expect(png4 != nil && !png4!.isEmpty)
        if let png4 = png4 {
            try png4.write(to: outDir.appendingPathComponent("stackedComplaintsByChannel.png"))
        }
        
        // 5. percentStackedStatus (hundredPercentStackedColumn)
        guard case .categorical(let pctData) = DataViewSamples.percentStackedStatus else {
            Issue.record("percentStackedStatus không phải categorical")
            return
        }
        var pctFormat = VisualFormat()
        pctFormat.dataLabels.show = true
        pctFormat.dataPoint.fillByValue[ScopedValue(column: "Dim_Loan_Profile.status_vn", value: .string("Đã tất toán"))] = .string("#81B29A")
        pctFormat.dataPoint.fillByValue[ScopedValue(column: "Dim_Loan_Profile.status_vn", value: .string("Đang chạy – tốt"))] = .string("#2E7D32")
        pctFormat.dataPoint.fillByValue[ScopedValue(column: "Dim_Loan_Profile.status_vn", value: .string("Đang chạy – nợ xấu"))] = .string("#E65100")
        pctFormat.dataPoint.fillByValue[ScopedValue(column: "Dim_Loan_Profile.status_vn", value: .string("Kết thúc – nợ xấu"))] = .string("#C0392B")
        let view5 = CartesianChartView(
            data: pctData,
            kind: .hundredPercentStackedColumn,
            context: VisualRenderContext(format: pctFormat),
            interactive: false
        )
        let png5 = renderToPNG(view: view5)
        #expect(png5 != nil && !png5!.isEmpty)
        if let png5 = png5 {
            try png5.write(to: outDir.appendingPathComponent("percentStackedStatus.png"))
        }
        
        // 6. barNPLByAge có highlights giả lập
        guard case .categorical(var barHighlightsData) = DataViewSamples.barNPLByAge else {
            Issue.record("barNPLByAge không phải categorical")
            return
        }
        // Giả lập tô sáng: chỉ danh mục index 2 ("35-49") được chọn
        var simulatedHighlights = barHighlightsData.values
        for m in simulatedHighlights.indices {
            for s in simulatedHighlights[m].indices {
                for c in simulatedHighlights[m][s].indices {
                    if c != 2 {
                        simulatedHighlights[m][s][c] = .blank
                    }
                }
            }
        }
        barHighlightsData.highlights = simulatedHighlights
        
        let view6 = CartesianChartView(
            data: barHighlightsData,
            kind: .clusteredBar,
            context: VisualRenderContext(format: barFormat),
            interactive: false
        )
        let png6 = renderToPNG(view: view6)
        #expect(png6 != nil && !png6!.isEmpty)
        if let png6 = png6 {
            try png6.write(to: outDir.appendingPathComponent("barNPLByAgeWithHighlights.png"))
        }
    }
}
