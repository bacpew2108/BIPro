// Lọc theo giá trị trên cột dense của MiniBank (FC, đợt 3): Dim_Date[full_date] là cột dense.
// Mọi con số lấy từ FCDenseExpected.swift, sinh bằng Python stdlib (scratchpad/fc3b/fc_dense_oracle.py).
// Cột mã hoá (year, date_key, balance_after) không đổi, và kết quả trên cột dense phải bằng biến thể mã hoá.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

/// Số ngày của Dim_Date thấy được trong ngữ cảnh.
private func soNgay(_ ctx: FilterContext, _ store: ColumnStore) throws -> Int {
    try ctx.visibleRows(in: store, table: MiniBank.Tables.dimDate, overrides: []).count
}

/// Số giao dịch của Fact_Trans thấy được trong ngữ cảnh.
private func soGiaoDich(_ ctx: FilterContext, _ store: ColumnStore) throws -> Int {
    try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: []).count
}

/// Tổng amount (currency ×10^4) của giao dịch thấy được.
private func tongAmount(_ ctx: FilterContext, _ store: ColumnStore) throws -> Int64 {
    let rows = try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: [])
    let data = try store.column(MiniBank.Columns.FactTrans.amount)
    var tong: Int64 = 0
    rows.forEach { row in
        if case .currency(let v) = data.value(at: row) { tong += v }
    }
    return tong
}

/// Bộ lọc full_date theo danh sách serial.
private func ngayFilter(_ serials: [Double]) -> FilterItem {
    FilterItem(column: MiniBank.Columns.DimDate.fullDate, values: serials.map { .dateTime($0) })
}

/// Các serial liên tiếp từ ngày đầu, dài `count` ngày.
private func khoangLienTiep(_ dau: Double, _ count: Int) -> [Double] {
    (0..<count).map { dau + Double($0) }
}

private let cotNam = MiniBank.Columns.DimDate.year
private let cotDateKey = MiniBank.Columns.DimDate.dateKey
private let cotAmount = MiniBank.Columns.FactTrans.amount
private let cotBalance = MiniBank.Columns.FactTrans.balanceAfter

/// Các kịch bản lọc full_date trên MiniBank, đáp án ở FCDenseExpected.
struct FCDenseKichBan: Sendable, CustomTestStringConvertible {
    let ten: String
    let ngay: [Double]
    let dim: Int
    let fact: Int
    let sum: Int64

    var testDescription: String { ten }
}

private let kichBan: [FCDenseKichBan] = [
    FCDenseKichBan(ten: "một ngày", ngay: [FCDenseSerial.d20240213], dim: FCDenseExpected.D1Dim,
            fact: FCDenseExpected.D1Fact, sum: FCDenseExpected.D1Sum),
    FCDenseKichBan(ten: "khoảng tháng 1/2024", ngay: khoangLienTiep(FCDenseSerial.d20240101, 31),
            dim: FCDenseExpected.R_JANDim, fact: FCDenseExpected.R_JANFact, sum: FCDenseExpected.R_JANSum),
    FCDenseKichBan(ten: "khoảng quý 1/2024", ngay: khoangLienTiep(FCDenseSerial.d20240101, 91),
            dim: FCDenseExpected.R_Q1Dim, fact: FCDenseExpected.R_Q1Fact, sum: FCDenseExpected.R_Q1Sum),
    FCDenseKichBan(ten: "tập ngày rời rạc",
            ngay: [FCDenseSerial.d20230110, FCDenseSerial.d20241225, FCDenseSerial.d20230805, FCDenseSerial.d20300101],
            dim: FCDenseExpected.SETDim, fact: FCDenseExpected.SETFact, sum: FCDenseExpected.SETSum),
    FCDenseKichBan(ten: "ngày không có giao dịch", ngay: [FCDenseSerial.d20230101],
            dim: FCDenseExpected.NODATADim, fact: FCDenseExpected.NODATAFact, sum: FCDenseExpected.NODATASum),
    FCDenseKichBan(ten: "toàn bộ Dim_Date", ngay: khoangLienTiep(FCDenseSerial.d20230101, 731),
            dim: FCDenseExpected.ALLDim, fact: FCDenseExpected.ALLFact, sum: FCDenseExpected.ALLSum),
]

@Suite struct FCDenseFilterTests {

    private let store = MiniBank.makeStore()

    // MARK: Lọc theo giá trị trên full_date (cột dense)

    @Test(arguments: kichBan)
    func locTheoGiaTriTrenCotDenseKhopDapAn(_ kb: FCDenseKichBan) throws {
        let ctx = FilterContext().applying([.filter(ngayFilter(kb.ngay), keep: false)])
        #expect(try soNgay(ctx, store) == kb.dim, "Dim_Date (\(kb.ten))")
        #expect(try soGiaoDich(ctx, store) == kb.fact, "Fact_Trans (\(kb.ten))")
        #expect(try tongAmount(ctx, store) == kb.sum, "tổng amount (\(kb.ten))")
    }

    @Test func locBlankTrenCotDenseKhongConDong() throws {
        // full_date không có BLANK và Dim_Date không có dòng BLANK ảo (mọi FK của Fact_Trans đều khớp ngày).
        let ctx = FilterContext().applying([.filter(FilterItem(column: MiniBank.Columns.DimDate.fullDate, values: [.blank]),
                                                    keep: false)])
        #expect(try soNgay(ctx, store) == 0)
        #expect(try soGiaoDich(ctx, store) == 0)
    }

    @Test func ngayTrenCotDenseKetHopCotMaHoaHaiDieuKien() throws {
        // Khoảng tháng 1/2024 và năm 2024 (mã hoá): giữ nguyên tháng 1. Với năm 2023 thì rỗng.
        let thang1 = FilterContext().applying([.filter(ngayFilter(khoangLienTiep(FCDenseSerial.d20240101, 31)), keep: false)])
        let nam2024 = thang1.applying([.filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false)])
        #expect(try soNgay(nam2024, store) == FCDenseExpected.R_JAN_AND_2024Dim)
        #expect(try soGiaoDich(nam2024, store) == FCDenseExpected.R_JAN_AND_2024Fact)
        let nam2023 = thang1.applying([.filter(FilterItem(column: cotNam, values: [.integer(2023)]), keep: false)])
        #expect(try soNgay(nam2023, store) == FCDenseExpected.R_JAN_AND_2023Dim)
        #expect(try soGiaoDich(nam2023, store) == FCDenseExpected.R_JAN_AND_2023Fact)
    }

    @Test func keepFiltersGiaoTrenCotDense() throws {
        // KEEPFILTERS: quý 1/2024 giao {24/01/2024, 01/06/2024, 10/01/2023} = {24/01/2024}.
        let quy1 = FilterContext().applying([.filter(ngayFilter(khoangLienTiep(FCDenseSerial.d20240101, 91)), keep: false)])
        let giao = quy1.applying([.filter(ngayFilter([FCDenseSerial.d20240124, FCDenseSerial.d20240601,
                                                      FCDenseSerial.d20230110]), keep: true)])
        #expect(try soNgay(giao, store) == FCDenseExpected.R_Q1_KEEP_KEEPDim)
        #expect(try soGiaoDich(giao, store) == FCDenseExpected.R_Q1_KEEP_KEEPFact)
        #expect(try tongAmount(giao, store) == FCDenseExpected.R_Q1_KEEP_KEEPSum)
    }

    @Test func ghiDeTrenCotDense() throws {
        // CALCULATE không KEEPFILTERS: lọc một ngày rồi lọc tập ngày, chỉ tập ngày còn lại.
        let mot = FilterContext().applying([.filter(ngayFilter([FCDenseSerial.d20240213]), keep: false)])
        let ghi = mot.applying([.filter(ngayFilter([FCDenseSerial.d20230110, FCDenseSerial.d20241225,
                                                    FCDenseSerial.d20230805, FCDenseSerial.d20300101]), keep: false)])
        #expect(ghi.values(for: MiniBank.Columns.DimDate.fullDate)?.count == 4, "chỉ còn một mục cho full_date")
        #expect(try soGiaoDich(ghi, store) == FCDenseExpected.SETFact)
        #expect(try soNgay(ghi, store) == FCDenseExpected.SETDim)
    }

    @Test func boLocDenseBangRemoveColumns() throws {
        // Sau REMOVEFILTERS(Dim_Date[full_date]) không còn lọc nào: toàn bộ giao dịch.
        let mot = FilterContext().applying([.filter(ngayFilter([FCDenseSerial.d20240213]), keep: false)])
        let bo = mot.applying([.removeColumns([MiniBank.Columns.DimDate.fullDate])])
        #expect(bo.values(for: MiniBank.Columns.DimDate.fullDate) == nil)
        #expect(!bo.isFiltered(MiniBank.Columns.DimDate.fullDate))
        #expect(try soGiaoDich(bo, store) == FCDenseExpected.ALLFact)
    }

    @Test func valuesTrenCotDenseTrongNguCanhLoc() throws {
        // VALUES(full_date) trong quý 1/2024: đúng 91 ngày, không có BLANK.
        let quy1 = FilterContext().applying([.filter(ngayFilter(khoangLienTiep(FCDenseSerial.d20240101, 91)), keep: false)])
        let values = try quy1.visibleValues(of: MiniBank.Columns.DimDate.fullDate, in: store)
        #expect(values.count == 91)
        #expect(!values.contains(.blank))
    }

    // MARK: Cột dense Fact_Trans[amount] (currency)

    @Test func locTheoGiaTriTrenAmountDense() throws {
        let ctx = FilterContext().applying([.filter(FilterItem(column: cotAmount,
                                                               values: [.currency(32_613_500), .currency(-2_031_000)]),
                                                    keep: false)])
        #expect(try soGiaoDich(ctx, store) == FCDenseExpected.amountPairFact)
        #expect(try tongAmount(ctx, store) == FCDenseExpected.amountPairSum)
    }

    @Test func amountDenseSoDoubleKhopCurrency() throws {
        // -203.1 đổi sang currency (×10^4) là -2031000: đúng một giao dịch.
        let ctx = FilterContext().applying([.filter(FilterItem(column: cotAmount, values: [.double(-203.1)]),
                                                    keep: false)])
        #expect(try soGiaoDich(ctx, store) == FCDenseExpected.amount203Fact)
    }

    @Test func amountDenseBlankRongKhiKhongCoBlank() throws {
        let ctx = FilterContext().applying([.filter(FilterItem(column: cotAmount, values: [.blank]), keep: false)])
        #expect(try soGiaoDich(ctx, store) == 0, "amount không có BLANK")
    }

    // MARK: Tương đương với biến thể mã hoá

    @Test func ketQuaDenseBangBienThaiMaHoa() throws {
        let encoded = ColumnStore(source: FCEncodedDateSource(base: MiniBank.makeSource()))
        for kb in kichBan {
            let ctx = FilterContext().applying([.filter(ngayFilter(kb.ngay), keep: false)])
            let ngayDense = try soNgay(ctx, store)
            let ngayMaHoa = try soNgay(ctx, encoded)
            #expect(ngayDense == ngayMaHoa, "Dim_Date (\(kb.ten)) dense và mã hoá lệch")
            let giaoDense = try soGiaoDich(ctx, store)
            let giaoMaHoa = try soGiaoDich(ctx, encoded)
            #expect(giaoDense == giaoMaHoa, "Fact_Trans (\(kb.ten)) dense và mã hoá lệch")
        }
    }

    // MARK: Cột mã hoá không hồi quy

    @Test func locCotMaHoaVanDung() throws {
        // Năm 2024 có 20 giao dịch (đếm tay từ transDateKey). date_key 20240213: đúng 1 giao dịch.
        let nam = FilterContext().applying([.filter(FilterItem(column: cotNam, values: [.integer(2024)]), keep: false)])
        #expect(try soGiaoDich(nam, store) == FCExpected.rowsFilterFact2024Trans)
        let ngayKey = FilterContext().applying([.filter(FilterItem(column: cotDateKey, values: [.integer(20240213)]),
                                                        keep: false)])
        #expect(try soGiaoDich(ngayKey, store) == 1)
        // balance_after = -2031000 chỉ có ở giao dịch 33 (đếm tay).
        let balance = FilterContext().applying([.filter(FilterItem(column: cotBalance, values: [.currency(-2_031_000)]),
                                                        keep: false)])
        #expect(try soGiaoDich(balance, store) == 1)
    }

    // MARK: Engine: measure với CALCULATE và bộ lọc trên cột dense

    @Test func measureVoiBoLocNgayDense() async throws {
        let measures: [ModelMeasureInput] = [
            ModelMeasureInput(table: "Fact_Trans", name: "Trans Count", expression: "COUNTROWS ( Fact_Trans )"),
            ModelMeasureInput(table: "Fact_Trans", name: "Trans Amount", expression: "SUM ( Fact_Trans[amount] )"),
            ModelMeasureInput(table: "Fact_Trans", name: "Mot Ngay",
                              expression: "CALCULATE ( [Trans Count], Dim_Date[full_date] = DATE ( 2024, 2, 13 ) )"),
            ModelMeasureInput(table: "Fact_Trans", name: "Thang Mot",
                              expression: """
                              CALCULATE ( [Trans Amount], Dim_Date[full_date] >= DATE ( 2024, 1, 1 ) && Dim_Date[full_date] <= DATE ( 2024, 1, 31 ) )
                              """),
        ]
        let engine = DAXEngine(store: MiniBank.makeStore(), catalog: Catalog(schema: MiniBank.schema, measures: measures))
        let mot = try await engine.evaluate(measure: "Mot Ngay", table: "Fact_Trans", filters: [])
        #expect(mot == .integer(Int64(FCDenseExpected.D1Fact)))
        let thang = try await engine.evaluate(measure: "Thang Mot", table: "Fact_Trans", filters: [])
        #expect(thang == .currency(FCDenseExpected.R_JANSum))
        // Bộ lọc ngoài (không CALCULATE) cũng đi qua cột dense.
        let ngoai = try await engine.evaluate(measure: "Trans Count", table: "Fact_Trans",
                                              filters: [ngayFilter([FCDenseSerial.d20240213])])
        #expect(ngoai == .integer(Int64(FCDenseExpected.D1Fact)))
    }
}
