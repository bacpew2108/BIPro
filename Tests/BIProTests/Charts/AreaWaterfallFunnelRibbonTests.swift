// VM-D15 mục 4: bộ vẽ vùng, vùng xếp chồng, thác nước, phễu, ruy-băng (hình mẫu Desktop ở `docs/phase-d-evidence/vm-d15/QUAN-SAT.md`).
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct AreaWaterfallFunnelRibbonTests {

    // MARK: Phễu

    @Test func funnelGiuThuTuDuLieuVaTinhPhanTramSoVoiThanhDau() {
        // Số liệu thật của hình Desktop: Total_Credit_Inflow theo năm, 2018 đứng đầu vì lớn nhất.
        let bars = FunnelLayout.bars(values: [961, 865, 607, 396, 279, 120], names: ["2018", "2017", "2016", "2015", "2014", "2013"])
        #expect(bars.map(\.category) == ["2018", "2017", "2016", "2015", "2014", "2013"])
        #expect(bars[0].fraction == 1)
        #expect(abs(bars[5].percentOfFirst - 120.0 / 961.0) < 1e-9)
        #expect(FunnelLayout.percentText(1) == "100%")
        #expect(FunnelLayout.percentText(bars[5].percentOfFirst) == "12.5%", "Desktop ghi 12.5% dưới thanh cuối")
    }

    @Test func funnelBoQuaOTrongVaSoAm() {
        let bars = FunnelLayout.bars(values: [10, nil, -3, 5], names: ["a", "b", "c", "d"])
        #expect(bars.map(\.category) == ["a", "d"])
        #expect(bars.map(\.fraction) == [1, 0.5])
        #expect(FunnelLayout.bars(values: [nil, nil], names: ["a", "b"]).isEmpty)
    }

    // MARK: Thác nước

    @Test func thacNuocTroiTheoMucCongDonVaCoCotTotal() {
        let bars = WaterfallLayout.bars(values: [100, -30, nil, 20], names: ["A", "B", "C", "D"])
        #expect(bars.map(\.category) == ["A", "B", "D", "Total"], "ô trống không có cột, cột Total ở cuối")
        #expect(bars.map(\.kind) == [.increase, .decrease, .increase, .total])
        #expect(bars[0].start == 0 && bars[0].end == 100)
        #expect(bars[1].start == 100 && bars[1].end == 70 && bars[1].low == 70 && bars[1].high == 100)
        #expect(bars[2].start == 70 && bars[2].end == 90)
        #expect(bars[3].start == 0 && bars[3].end == 90 && bars[3].value == 90)
    }

    /// Số liệu thật của hình Desktop (VM-D16): Total_Credit_Inflow theo vùng, chia nhỏ theo giới tính, vùng xếp giảm dần.
    @Test func thacNuocCoBreakdownLaTotalRoiChenhLechTungPhanTu() {
        let values: [[Double?]] = [[0.82, 0.90], [0.33, 0.33], [0.27, 0.27], [0.15, 0.16]]
        let bars = WaterfallLayout.bars(values: values, categoryNames: ["Northeast", "South", "West", "Midwest"], breakdownNames: ["Female", "Male"])
        #expect(bars.map(\.category) == ["Northeast", "Female", "Male", "South", "Female", "Male", "West", "Male", "Female", "Midwest"],
                "10 cột như Desktop; trong mỗi nhóm chênh lệch xếp giảm dần (Male -0,11 trước Female -0,12)")
        #expect(bars.map(\.kind) == [.total, .decrease, .decrease, .total, .decrease, .decrease, .total, .decrease, .decrease, .total])
        #expect(abs(bars[0].end - 1.72) < 1e-9)
        #expect(abs(bars[1].value - (-0.49)) < 1e-9 && abs(bars[2].value - (-0.57)) < 1e-9)
        #expect(abs(bars[2].end - 0.66) < 1e-9, "trôi đúng đến tổng của South")
        #expect(bars[1].breakdown == 0 && bars[2].breakdown == 1 && bars[0].breakdown == nil)
        // Cột chênh lệch dương là Increase.
        let rising = WaterfallLayout.bars(values: [[1, 1], [3, nil]], categoryNames: ["a", "b"], breakdownNames: ["x", "y"])
        #expect(rising.map(\.kind) == [.total, .increase, .decrease, .total])
        #expect(rising[1].value == 2 && rising[2].value == -1 && rising[3].end == 3)
    }

    @Test func thacNuocKhongCoDuLieuThiKhongVe() {
        #expect(WaterfallLayout.bars(values: [nil, nil], names: ["a", "b"]).isEmpty)
    }

    // MARK: Ruy-băng

    @Test func ruyBangXepSeriesLonNhatLenTrenTheoTungDanhMuc() {
        // Hai danh mục, ba series: thứ hạng đổi ở danh mục 2.
        let columns = RibbonLayout.columns(values: [[10, 30, 20], [40, 5, 25]])
        #expect(columns[0].map(\.series) == [0, 2, 1], "từ dưới lên: nhỏ nhất trước")
        #expect(columns[1].map(\.series) == [1, 2, 0])
        #expect(columns[0].map(\.y1) == [10, 30, 60])
        #expect(RibbonLayout.maxTotal(columns: columns) == 70)
    }

    @Test func ruyBangNoiHaiCotLienTiepChoMoiSeriesCoMatOCaHai() {
        let columns = RibbonLayout.columns(values: [[10, nil, 20], [4, 8, nil]])
        let links = RibbonLayout.links(columns: columns)
        #expect(links.map(\.series) == [0], "chỉ series 0 có ở cả hai cột")
        #expect(links[0].from.value == 10 && links[0].to.value == 4)
        #expect(RibbonLayout.links(columns: [[RibbonSegment(category: 0, series: 0, value: 1, y0: 0, y1: 1)]]).isEmpty)
    }

    @Test func ruyBangBoGiaTriKhongDuong() {
        let columns = RibbonLayout.columns(values: [[0, -2, 5, nil]])
        #expect(columns[0].map(\.series) == [2])
    }

    // MARK: Loại visual

    @Test func cacLoaiMoiNhanRaKieuVeVaThemDuoc() {
        #expect(CartesianKind(visualType: "areaChart") == .area)
        #expect(CartesianKind(visualType: "stackedAreaChart") == .stackedArea)
        #expect(CartesianKind.area.isArea && CartesianKind.stackedArea.isLineLike && !CartesianKind.clusteredColumn.isLineLike)
        for type in ["areaChart", "stackedAreaChart", "ribbonChart", "waterfallChart", "funnel"] {
            #expect(VisualTypes.isSupported(type), Comment(rawValue: type))
            #expect(PBIRNewVisual.defaultSize(for: type) != nil, Comment(rawValue: type))
        }
    }

    @Test func oCuaCacLoaiMoiDungVoiDesktop() {
        func roles(_ type: String) -> [String] { VisualCatalog.wells(for: WellRulesTests.visual(type)).map(\.role) }
        #expect(roles("areaChart") == ["Category", "Y", "Y2", "Series", "Tooltips"])
        #expect(roles("ribbonChart") == ["Category", "Y", "Series", "Tooltips"])
        #expect(roles("waterfallChart") == ["Category", "Breakdown", "Y", "Tooltips"])
        #expect(roles("funnel") == ["Category", "Y", "Tooltips"])
    }

    // MARK: Vùng trong biểu đồ trục

    private func areaData(series: Int) -> CategoricalData {
        let cats = ["2013", "2014", "2015"]
        let field = FieldInfo(queryRef: "Dim_Client.region", displayName: "region", role: "Series", formatString: nil, isMeasure: false)
        let measure = FieldInfo(queryRef: "Fact.Amount", displayName: "Amount", role: "Y", formatString: "#,0", isMeasure: true)
        let rows: [[DataCell]] = (0..<series).map { s in cats.indices.map { DataCell(.double(Double((s + 1) * (10 + $0 * 5))), formatString: "#,0") } }
        return CategoricalData(categoryLevels: [FieldInfo(queryRef: "Dim_Date.year", displayName: "year", role: "Category", formatString: nil, isMeasure: false)],
                               categories: cats.map { CategoryKey(values: [.string($0)]) },
                               seriesField: series > 1 ? field : nil, series: series > 1 ? (0..<series).map { .string("S\($0)") } : [],
                               measures: [measure], values: [rows], highlights: nil, isReduced: false)
    }

    @Test func vungBatDauTuKhongVaVungXepChongCongDonCacLop() {
        let area = PreparedChartLayout(data: areaData(series: 2), kind: .area, context: VisualRenderContext())
        #expect(area.columnYDomain.lowerBound == 0, "vùng luôn bắt đầu từ 0")
        #expect(area.lineSeries.count == 2)
        #expect(area.lineSeries.flatMap(\.points).allSatisfy { $0.base == 0 })

        let stacked = PreparedChartLayout(data: areaData(series: 2), kind: .stackedArea, context: VisualRenderContext())
        let first = stacked.lineSeries[0].points, second = stacked.lineSeries[1].points
        #expect(first.map(\.value) == [10, 15, 20] && first.allSatisfy { $0.base == 0 })
        #expect(second.map(\.base) == first.map(\.value), "lớp trên bắt đầu ở mép trên lớp dưới")
        #expect(second.map(\.value) == [30, 45, 60], "10+20, 15+30, 20+40")
        #expect(stacked.columnYDomain.upperBound >= 60, "miền Y phủ tổng cộng dồn")
    }

    @Test func vungXepChong100ChuanHoaMoiDanhMucVeMot() {
        #expect(CartesianKind(visualType: "hundredPercentStackedAreaChart") == .hundredPercentStackedArea)
        #expect(CartesianKind.hundredPercentStackedArea.isStackedArea && !CartesianKind.area.isStackedArea)
        let layout = PreparedChartLayout(data: areaData(series: 2), kind: .hundredPercentStackedArea, context: VisualRenderContext())
        let first = layout.lineSeries[0].points, second = layout.lineSeries[1].points
        #expect(first.allSatisfy { abs($0.value - 1.0 / 3.0) < 1e-9 && $0.base == 0 }, "lớp dưới chiếm 1/3 ở cả ba danh mục")
        #expect(second.allSatisfy { abs($0.base - 1.0 / 3.0) < 1e-9 && abs($0.value - 1) < 1e-9 })
        #expect(layout.columnYDomain == 0...1 && layout.columnYLabels == ["0%", "20%", "40%", "60%", "80%", "100%"])
    }

    // MARK: Thang log (VM-D17)

    @Test func thangLogDungLuyThuaCuaMuoiVaDonViTheoVachGiua() {
        #expect(ChartAxis.logTicks(low: 0.7e6, high: 210e6) == [1e5, 1e6, 1e7, 1e8, 1e9])
        #expect(ChartAxis.logTicks(low: 10, high: 10) == [10, 100], "luôn có ít nhất hai vạch")
        #expect(ChartAxis.logTicks(low: 0, high: 5) == [1, 10])
        // Hình Desktop (D1 Q1.1 bật Logarithmic scale): $0M, $1M, $10M, $100M, $1,000M.
        let cats = ["a", "b", "c"]
        let measure = FieldInfo(queryRef: "Fact.Amount", displayName: "Amount", role: "Y", formatString: "\\$#,0", isMeasure: true)
        let data = CategoricalData(categoryLevels: [FieldInfo(queryRef: "Dim.c", displayName: "c", role: "Category", formatString: nil, isMeasure: false)],
                                   categories: cats.map { CategoryKey(values: [.string($0)]) }, seriesField: nil, series: [], measures: [measure],
                                   values: [[[0.7e6, 50e6, 210e6].map { DataCell(.double($0), formatString: "\\$#,0") }]], highlights: nil, isReduced: false)
        var format = VisualFormat()
        format.valueAxis.logScale = true
        let log = PreparedChartLayout(data: data, kind: .line, context: VisualRenderContext(format: format))
        #expect(log.useLogScale)
        #expect(log.columnYTicks == [1e5, 1e6, 1e7, 1e8, 1e9])
        #expect(log.columnYLabels == ["$0M", "$1M", "$10M", "$100M", "$1,000M"])
        #expect(log.columnYDomain == 1e5...1e9)
        // Đường xu hướng trên trục log: chỉ hai đầu của hồi quy tuyến tính theo giá trị (đoạn thẳng trên trục log), như Desktop.
        var trendFormat = format
        trendFormat.analytics.trendShow = true
        let withTrend = PreparedChartLayout(data: data, kind: .line, context: VisualRenderContext(format: trendFormat))
        #expect(withTrend.trendPoints.map(\.category) == ["a", "c"])
        let flat = PreparedChartLayout(data: data, kind: .line, context: VisualRenderContext(format: { var f = VisualFormat(); f.analytics.trendShow = true; return f }()))
        #expect(flat.trendPoints.map(\.category) == ["a", "b", "c"], "trục thường vẫn vẽ mọi điểm")
        let linear = PreparedChartLayout(data: data, kind: .line, context: VisualRenderContext())
        #expect(!linear.useLogScale)
        // Cột xếp chồng không đi theo thang log.
        let stacked = PreparedChartLayout(data: data, kind: .stackedColumn, context: VisualRenderContext(format: format))
        #expect(!stacked.useLogScale)
    }

    // MARK: Round range (VM-D18)

    @Test func roundRangeTatLayDungMienDuLieuTrenBieuDoDuong() {
        let cats = ["a", "b", "c"]
        let measure = FieldInfo(queryRef: "Fact.Amount", displayName: "Amount", role: "Y", formatString: "\\$#,0", isMeasure: true)
        let data = CategoricalData(categoryLevels: [FieldInfo(queryRef: "Dim.c", displayName: "c", role: "Category", formatString: nil, isMeasure: false)],
                                   categories: cats.map { CategoryKey(values: [.string($0)]) }, seriesField: nil, series: [], measures: [measure],
                                   values: [[[0.7e6, 120e6, 210e6].map { DataCell(.double($0), formatString: "\\$#,0") }]], highlights: nil, isReduced: false)
        let on = PreparedChartLayout(data: data, kind: .line, context: VisualRenderContext())
        #expect(on.columnYDomain.lowerBound == 0 && on.columnYDomain.upperBound >= 210e6, "làm tròn: từ 0 đến vạch tròn trên dữ liệu")
        var format = VisualFormat()
        format.valueAxis.roundRange = false
        let off = PreparedChartLayout(data: data, kind: .line, context: VisualRenderContext(format: format))
        #expect(off.columnYDomain == 0.7e6...210e6, "đúng miền dữ liệu, như Desktop")
        #expect(off.columnYTicks.allSatisfy { $0 >= 0.7e6 && $0 <= 210e6 } && !off.columnYTicks.isEmpty)
        // Cột không đổi (đáy luôn là 0).
        let column = PreparedChartLayout(data: data, kind: .clusteredColumn, context: VisualRenderContext(format: format))
        #expect(column.columnYDomain.lowerBound == 0)
    }
}

