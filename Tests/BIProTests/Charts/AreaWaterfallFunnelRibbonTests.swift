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

    /// T038 (bấm thử app): tích cột ngày vào biểu đồ cột xếp chồng mới (chỉ có trục X, chưa có Y) làm app sập (`roleYIndices[0]` khi
    /// rỗng). Mọi loại biểu đồ trục với danh mục mà chưa có measure phải dựng được, không có cột/điểm nào.
    @Test func coTrucXMaChuaCoYKhongSap() {
        let data = CategoricalData(categoryLevels: [FieldInfo(queryRef: "T.Year", displayName: "Year", role: "Category", formatString: nil, isMeasure: false)],
                                   categories: ["2025", "2026"].map { CategoryKey(values: [.string($0)]) },
                                   seriesField: nil, series: [], measures: [], values: [], highlights: nil, isReduced: false)
        let kinds: [CartesianKind] = [.clusteredBar, .clusteredColumn, .stackedColumn, .hundredPercentStackedColumn, .line, .comboClustered,
                                      .comboStacked, .area, .stackedArea, .hundredPercentStackedArea]
        for kind in kinds {
            let layout = PreparedChartLayout(data: data, kind: kind, context: VisualRenderContext())
            #expect(layout.bars.isEmpty, "\(kind)")
        }
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

    /// VM-D19: Desktop giữ `axisType` Scalar khi đổi đường sang thanh; thanh cũng vẽ trục ngày liên tục (nhãn năm tại tháng đầu năm).
    @Test func thanhCoTrucNgayLienTucChiGhiNhanNam() {
        let months = [DateDisplay.serial(year: 2013, month: 11, day: 1), DateDisplay.serial(year: 2013, month: 12, day: 1),
                      DateDisplay.serial(year: 2014, month: 1, day: 1), DateDisplay.serial(year: 2014, month: 2, day: 1)]
        let level = FieldInfo(queryRef: "Dim_Date.month_start", displayName: "Tháng", role: "Category", formatString: "mmm yyyy", isMeasure: false)
        let measure = FieldInfo(queryRef: "Fact.Amount", displayName: "Amount", role: "Y", formatString: nil, isMeasure: true)
        let data = CategoricalData(categoryLevels: [level], categories: months.map { CategoryKey(values: [.dateTime($0)]) }, seriesField: nil, series: [],
                                   measures: [measure], values: [[[1.0, 2, 3, 4].map { DataCell(.double($0)) }]], highlights: nil, isReduced: false)
        var format = VisualFormat()
        format.categoryAxis.axisType = "Scalar"
        let scalar = PreparedChartLayout(data: data, kind: .clusteredBar, context: VisualRenderContext(format: format))
        #expect(scalar.isScalarAxis)
        #expect(scalar.scalarXLabels.values.sorted() == ["2013", "2014"], "chỉ ghi nhãn năm, một lần mỗi năm")
        #expect(scalar.scalarXTicks.count == 2)
        let plain = PreparedChartLayout(data: data, kind: .clusteredBar, context: VisualRenderContext())
        #expect(!plain.isScalarAxis)
    }

    /// VM-D19: Desktop làm tròn bước vạch lên theo 1, 2, 5 (số đo trên cột "Tiền vào/ra" max 0,96 tỉ và "Rủi ro thấu chi" max ≈140).
    @Test func vachTrucLamTronLenTheoMotHaiNamNhuDesktop() {
        let primary = ChartAxis.primaryTargetCount
        #expect(ChartAxis.niceTicks(min: 0, max: 0.96e9, targetCount: primary) == [0, 0.5e9, 1e9])
        #expect(ChartAxis.niceTicks(min: 0, max: 190, targetCount: primary) == [0, 50, 100, 150, 200])
        #expect(ChartAxis.niceTicks(min: 0, max: 36.8e3, targetCount: 4) == [0, 20e3, 40e3], "trục phụ")
        #expect(ChartAxis.niceTicks(min: 0, max: 30e6, targetCount: 4) == [0, 10e6, 20e6, 30e6], "chia đúng thì giữ bước")
        #expect(ChartAxis.labels(ticks: [0, 0.5e9, 1e9], formatString: "\\$#,0") == ["$0.0bn", "$0.5bn", "$1.0bn"])
    }

    /// VM-D19: vạch theo chiều cao vùng vẽ, số đo trên Desktop (visual 660×380): cột "Tiền vào/ra", "Rủi ro thấu chi" (trục chính và phụ), Pareto.
    @Test func vachTrucTheoChieuCaoVungVeNhuDesktop() {
        let primary = ChartAxis.minSpacingPrimary, secondary = ChartAxis.minSpacingSecondary
        let inflow = ChartAxis.fittingTicks(min: 0, max: 0.96e9, plotHeight: 233, minSpacing: primary)
        #expect(inflow.ticks == [0, 0.5e9, 1e9] && inflow.upper == 1e9, "bước 0,2 tỉ chỉ cách 46,6 nên bị bỏ")
        let overdraft = ChartAxis.fittingTicks(min: 0, max: 190, plotHeight: 190, minSpacing: primary)
        #expect(overdraft.ticks == [0, 50, 100, 150, 200], "bước 50 cách 47,5 thì giữ")
        let line = ChartAxis.fittingTicks(min: 0, max: 36.8e3, plotHeight: 190, minSpacing: secondary)
        #expect(line.ticks == [0, 20e3, 40e3], "trục phụ thưa hơn: bước 10K chỉ cách 47,5")
        let pareto = ChartAxis.fittingTicks(min: 0, max: 5.9e3, plotHeight: 97, minSpacing: primary)
        #expect(pareto.ticks == [0, 5e3] && pareto.upper == 5.9e3, "5,9K không kéo lên 10K: miền giữ đúng dữ liệu, chỉ có 0K và 5K")
        let cumulative = ChartAxis.fittingTicks(min: 0, max: 1, plotHeight: 97, minSpacing: secondary)
        #expect(cumulative.ticks == [0, 1], "trục phải Pareto chỉ 0% và 100%")
        // Vùng vẽ cao hơn thì nhiều vạch hơn.
        let tall = ChartAxis.fittingTicks(min: 0, max: 0.96e9, plotHeight: 440, minSpacing: primary)
        #expect(tall.ticks == [0, 0.2e9, 0.4e9, 0.6e9, 0.8e9, 1e9])
        let negative = ChartAxis.fittingTicks(min: -20, max: 30, plotHeight: 260, minSpacing: primary)
        #expect(negative.ticks == [-20, -10, 0, 10, 20, 30])
        #expect(ChartAxis.fittingTicks(min: 0, max: 0, plotHeight: 200, minSpacing: primary).ticks == [0, 1], "không có miền thì như bản cũ")
    }

    /// VM-D19: đường không bắt đầu từ 0 khi nhỏ nhất ≥ 1/3 lớn nhất (số đo trên Desktop).
    @Test func duongKhongBatDauTuKhongKhiDuLieuNamXaKhong() {
        #expect(ChartAxis.floatingLow(values: [18.3e6, 30e6, 49.7e6]) != nil, "Dòng tiền ròng 18M…50M: bắt đầu $10M")
        #expect(ChartAxis.floatingLow(values: [128e6, 211e6]) == 128e6)
        #expect(ChartAxis.floatingLow(values: [0.25, 1.0]) == nil, "Pareto lũy kế 0,25…1: bắt đầu từ 0")
        #expect(ChartAxis.floatingLow(values: [6.5e3, 44e3]) == nil)
        #expect(ChartAxis.floatingLow(values: [-3, 10]) == nil)
        // Năm 2018 của D1 Q1.1: dữ liệu 128M…211M, dải dự báo xuống ≈90M, lên ≈240M → $50M…$250M.
        let line = ChartAxis.fittingTicks(min: 90e6, max: 240e6, plotHeight: 258, minSpacing: ChartAxis.minSpacingPrimary, floating: true)
        #expect(line.ticks == [50e6, 100e6, 150e6, 200e6, 250e6] && line.lower == 50e6 && line.upper == 250e6)
        // "Dòng tiền ròng" (18,3M…49,7M, visual cao 380): miền $10M…$50M, nhãn $20M và $40M.
        let net = ChartAxis.fittingTicks(min: 18.3e6, max: 49.7e6, plotHeight: 233, minSpacing: ChartAxis.minSpacingPrimary, floating: true)
        #expect(net.lower == 10e6 && net.upper == 50e6 && net.ticks == [20e6, 40e6])
        // "số dư BQ/TK" của 2018: ≈30,7K…45,5K → $30K…$50K, bước 5K (Desktop ghi 30K, 35K, 40K, 45K, 50K).
        let balance = ChartAxis.fittingTicks(min: 30.7e3, max: 45.5e3, plotHeight: 190, minSpacing: ChartAxis.minSpacingPrimary, floating: true)
        #expect(balance.ticks == [30e3, 35e3, 40e3, 45e3, 50e3])
    }

    /// VM-D21: trục phụ chỉ hiện khi miền khác miền trục chính (D3 "TB 3 tháng" cùng miền 0…600 thì không có trục phải; Maximum 300 ở trục chính thì hiện).
    @Test func trucPhuChiHienKhiMienKhacTrucChinh() {
        func layout(y2: [Double], maxY: Double? = nil) -> PreparedChartLayout {
            let level = FieldInfo(queryRef: "d.m", displayName: "m", role: "Category", formatString: nil, isMeasure: false)
            let y = FieldInfo(queryRef: "f.c", displayName: "c", role: "Y", formatString: "#,0", isMeasure: true)
            let y2f = FieldInfo(queryRef: "f.ma", displayName: "ma", role: "Y2", formatString: "#,0", isMeasure: true)
            let cats = ["a", "b", "c"].map { CategoryKey(values: [.string($0)]) }
            let data = CategoricalData(categoryLevels: [level], categories: cats, seriesField: nil, series: [], measures: [y, y2f],
                                       values: [[[300.0, 500, 552].map { DataCell(.double($0)) }], [y2.map { DataCell(.double($0)) }]],
                                       highlights: nil, isReduced: false)
            var format = VisualFormat()
            format.valueAxis.end = maxY
            return PreparedChartLayout(data: data, kind: .comboClustered, context: VisualRenderContext(format: format, visualSize: CGSize(width: 616, height: 380)))
        }
        let same = layout(y2: [150, 400, 518])
        #expect(same.columnYTicks == [0, 200, 400, 600])
        #expect(!same.hasSecondaryAxis, "cùng miền 0…600: một trục")
        #expect(layout(y2: [150, 400, 518], maxY: 300).hasSecondaryAxis, "trục chính 0…300 khác 0…600: hiện trục phải")
        #expect(layout(y2: [0.1, 0.2, 0.3]).hasSecondaryAxis)
    }

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

