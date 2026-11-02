// SUM và COUNTROWS (F-KIT lõi, đợt 2). Đáp án: MiniBankExpected và script Python độc lập.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FKCoreAggregationTests {

    // MARK: SUM trên MiniBank

    @Test func sumCotTienTeTongMiniBank() throws {
        let env = FKCoreEnv()
        // Tổng amount của 40 dòng, nhân 10^4 (currency giữ Int64).
        #expect(try env.value("SUM ( Fact_Trans[amount] )") == .currency(1_254_298_000))
    }

    @Test func sumCoBoLocNam() throws {
        let env = FKCoreEnv()
        let nam2023 = try env.filter("Dim_Date", "year", [.integer(2023)])
        #expect(try env.value("SUM ( Fact_Trans[amount] )", filter: nam2023) == .currency(566_230_700))
    }

    @Test func sumKhongCoDongThayDuocLaBlank() throws {
        let env = FKCoreEnv()
        // Giá trị không có trong dictionary: không dòng nào thấy được, SUM là BLANK.
        let khong = try env.filter("Dim_Account", "card_type", [.string("Không có")])
        #expect(try env.value("SUM ( Fact_Trans[amount] )", filter: khong) == .blank)
    }

    @Test func sumKhongMaterializeBangVatLy() throws {
        let env = FKCoreEnv()
        _ = try env.value("SUM ( Fact_Trans[amount] )")
        #expect(env.evaluator.materializedRowCount == 0)
    }

    // MARK: SUM trên kho nhỏ: BLANK, số thực, tràn, văn bản

    @Test func sumBoQuaBlankSoNguyen() throws {
        let model = FKCoreEnv.thu(FKCoreThu.store())
        // 1 + BLANK + 3 = 4, kiểu số nguyên giữ Int64.
        #expect(try model.value("SUM ( Thu[x] )") == .integer(4))
    }

    @Test func sumBoQuaBlankCurrency() throws {
        let model = FKCoreEnv.thu(FKCoreThu.store())
        // 1,0 + BLANK + 2,5 = 3,5, giữ Int64 đã nhân 10^4.
        #expect(try model.value("SUM ( Thu[tien] )") == .currency(35_000))
    }

    @Test func sumSoThucCongNeumaier() throws {
        // Cộng ngây thơ 1e16 + 1 - 1e16 cho 0; cộng bù sai số cho 1.
        let model = FKCoreEnv.thu(FKCoreThu.store())
        #expect(try model.value("SUM ( Thu[d] )") == .double(1.0))
    }

    @Test func sumTranInt64BaoLoi() throws {
        let model = FKCoreEnv.thu(FKCoreThu.store())
        #expect(fkKindOf { try model.value("SUM ( Thu[big] )") } == .runtime)
    }

    @Test func sumCotVanBanBaoLoiKieu() throws {
        let model = FKCoreEnv.thu(FKCoreThu.store())
        #expect(fkKindOf { try model.value("SUM ( Thu[chu] )") } == .typeMismatch)
    }

    @Test func sumVoiBoLocKhongDongNaoLaBlank() throws {
        let model = FKCoreEnv.thu(FKCoreThu.store())
        let khong = try model.filter("Thu", "x", [.integer(99)])
        #expect(try model.value("SUM ( Thu[x] )", filter: khong) == .blank)
    }

    @Test func sumVoiBoLocMotDong() throws {
        let model = FKCoreEnv.thu(FKCoreThu.store())
        let mot = try model.filter("Thu", "x", [.integer(1)])
        #expect(try model.value("SUM ( Thu[x] )", filter: mot) == .integer(1))
    }

    // MARK: COUNTROWS

    @Test func countRowsBang() throws {
        let env = FKCoreEnv()
        #expect(try env.count("COUNTROWS ( Fact_Trans )") == 40)
        // Dim_Client không có khoá mồ côi từ fact, nên không có dòng BLANK ảo (6 dòng thật).
        #expect(try env.count("COUNTROWS ( Dim_Client )") == 6)
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func countRowsCoBoLoc() throws {
        let env = FKCoreEnv()
        let nam2024 = try env.filter("Dim_Date", "year", [.integer(2024)])
        #expect(try env.count("COUNTROWS ( Fact_Trans )", filter: nam2024) == 20)
    }

    @Test func countRowsBlankFkDemMotDong() throws {
        let env = FKCoreEnv()
        let khongKhop = try env.filter("Dim_Account", "branch_city", [.blank])
        #expect(try env.count("COUNTROWS ( Fact_Trans )", filter: khongKhop) == 1)
    }

    @Test func countRowsTrenBangKho() throws {
        let model = FKCoreEnv.thu(FKCoreThu.store())
        #expect(try model.count("COUNTROWS ( Thu )") == 3)
    }
}
