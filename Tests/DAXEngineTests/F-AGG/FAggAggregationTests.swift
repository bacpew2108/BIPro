// WP F-AGG (đợt 3): AVERAGE, COUNT, DISTINCTCOUNT, MIN và MAX (dạng cột và dạng hai giá trị).
// Đáp án: fagg_expected.py (Python stdlib). Đơn vị currency là Int64 đã nhân 10^4.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FAggAggregationTests {

    // MARK: AVERAGE

    @Test func averageCotTienTeMiniBankLaCurrency() throws {
        let env = FAggEnv.minibank()
        // 1 254 298 000 / 40 = 31 357 450 (đơn vị ×10^4): kết quả là currency.
        #expect(try env.value("AVERAGE ( Fact_Trans[amount] )") == .currency(31_357_450))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func averageSoSoNguyenRaSoThuc() throws {
        let env = FAggEnv.kho()
        // (5 + 3 + 5 + 1 + 7) / 5 = 4,2. BLANK không vào mẫu.
        #expect(try env.value("AVERAGE ( Kho[so] )") == .double(4.2))
    }

    @Test func averageCurrencyBoQuaBlank() throws {
        let env = FAggEnv.kho()
        // (1,0 + 2,5 + 2,5 - 0,5 + 10,0) / 5 = 3,1 = 31 000 đơn vị ×10^4.
        #expect(try env.value("AVERAGE ( Kho[tien] )") == .currency(31_000))
    }

    @Test func averageKhongCoDongLaBlank() throws {
        let env = FAggEnv.kho()
        let khong = try env.filter("Kho", "so", [.integer(99)])
        #expect(try env.value("AVERAGE ( Kho[so] )", filter: khong) == .blank)
    }

    @Test func averageCotChuoiBaoLoiKieu() throws {
        let env = FAggEnv.kho()
        #expect(fAggKindOf { try env.value("AVERAGE ( Kho[nhom] )") } == .typeMismatch)
    }

    // MARK: COUNT

    @Test func countBoQuaBlankTrenMiniBank() throws {
        let env = FAggEnv.minibank()
        // client_region có 40 dòng, một dòng BLANK (FK 99), nên COUNT = 39.
        #expect(try env.value("COUNT ( Fact_Trans[client_region] )") == .integer(39))
        #expect(try env.value("COUNT ( Fact_Trans[trans_key] )") == .integer(40))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func countBlankTrongKhoNhoVaTrongBoLocRong() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("COUNT ( Kho[so] )") == .integer(5))
        #expect(try env.value("COUNT ( Kho[nhom] )") == .integer(5))
        // Không có dòng nào: COUNT là BLANK, không phải 0 (Golden Power BI (buổi 1): đếm trên tập rỗng cho BLANK).
        let khong = try env.filter("Kho", "so", [.integer(99)])
        #expect(try env.value("COUNT ( Kho[so] )", filter: khong) == .blank)
    }

    @Test func countDongFkBlankKhongKhopBiBoQua() throws {
        let env = FAggEnv.minibank()
        // Chỉ dòng FK 99 thấy được (branch_city = BLANK): client_region của dòng đó là BLANK, nên COUNT là BLANK.
        let khongKhop = try env.filter("Dim_Account", "branch_city", [.blank])
        #expect(try env.value("COUNT ( Fact_Trans[client_region] )", filter: khongKhop) == .blank)
        #expect(try env.value("COUNT ( Fact_Trans[trans_key] )", filter: khongKhop) == .integer(1))
    }

    // MARK: DISTINCTCOUNT

    @Test func distinctCountSoKhoaTaiKhoanMiniBank() throws {
        let env = FAggEnv.minibank()
        // Sáu khoá: 1, 2, 3, 4, 5 và 99 (FK không khớp).
        #expect(try env.value("DISTINCTCOUNT ( Fact_Trans[account_key] )") == .integer(6))
    }

    @Test func distinctCountTinhBlankLaMotGiaTri() throws {
        let env = FAggEnv.minibank()
        // Ba vùng (Unknown, Miền Bắc, Miền Trung) cộng một BLANK = 4 [SUY ĐOÁN: BLANK được tính].
        #expect(try env.value("DISTINCTCOUNT ( Fact_Trans[client_region] )") == .integer(4))
        // Chỉ dòng FK 99 thấy được và vùng của nó là BLANK: còn đúng một giá trị.
        let khongKhop = try env.filter("Dim_Account", "branch_city", [.blank])
        #expect(try env.value("DISTINCTCOUNT ( Fact_Trans[client_region] )", filter: khongKhop) == .integer(1))
    }

    @Test func distinctCountKhoNhoVaBoLocRong() throws {
        let env = FAggEnv.kho()
        // so: {5, 3, 1, 7} và BLANK = 5. nhom: {a, b, c} và BLANK = 4.
        #expect(try env.value("DISTINCTCOUNT ( Kho[so] )") == .integer(5))
        #expect(try env.value("DISTINCTCOUNT ( Kho[nhom] )") == .integer(4))
        let khong = try env.filter("Kho", "so", [.integer(99)])
        // Không có dòng: BLANK (Golden Power BI (buổi 1): đếm trên tập rỗng cho BLANK, Active Accounts ở năm không có giao dịch).
        #expect(try env.value("DISTINCTCOUNT ( Kho[so] )", filter: khong) == .blank)
    }

    // MARK: MIN và MAX dạng cột

    @Test func minMaxCotTienMiniBank() throws {
        let env = FAggEnv.minibank()
        #expect(try env.value("MIN ( Fact_Trans[amount] )") == .currency(-9_505_400))
        #expect(try env.value("MAX ( Fact_Trans[amount] )") == .currency(69_748_700))
        #expect(try env.value("MIN ( Fact_Trans[date_key] )") == .integer(20_230_110))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func minMaxCotTienCoBoLocNam2024() throws {
        let env = FAggEnv.minibank()
        let nam2024 = try env.filter("Dim_Date", "year", [.integer(2024)])
        #expect(try env.value("MIN ( Fact_Trans[amount] )", filter: nam2024) == .currency(-8_926_400))
        #expect(try env.value("MAX ( Fact_Trans[amount] )", filter: nam2024) == .currency(64_000_000))
    }

    @Test func minMaxKhoNhoCoBlankVaSoAm() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("MIN ( Kho[so] )") == .integer(1))
        #expect(try env.value("MAX ( Kho[so] )") == .integer(7))
        #expect(try env.value("MIN ( Kho[tien] )") == .currency(-5_000))
        #expect(try env.value("MAX ( Kho[tien] )") == .currency(100_000))
        #expect(try env.value("MIN ( Kho[thuc] )") == .double(-3.0))
        #expect(try env.value("MAX ( Kho[thuc] )") == .double(4.0))
    }

    @Test func minMaxCotChuoiTheoThuTuSapXep() throws {
        let env = FAggEnv.kho()
        // Chuỗi so theo thứ tự không phân biệt hoa thường: a < b < c (BLANK bị bỏ qua).
        #expect(try env.value("MIN ( Kho[nhom] )") == .string("a"))
        #expect(try env.value("MAX ( Kho[nhom] )") == .string("c"))
    }

    @Test func minMaxCotKhongCoDongLaBlank() throws {
        let env = FAggEnv.kho()
        let khong = try env.filter("Kho", "so", [.integer(99)])
        #expect(try env.value("MIN ( Kho[so] )", filter: khong) == .blank)
        #expect(try env.value("MAX ( Kho[so] )", filter: khong) == .blank)
    }

    // MARK: MIN và MAX dạng hai giá trị vô hướng

    @Test func minMaxHaiGiaTriVoHuong() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("MIN ( 3, 5 )") == .integer(3))
        #expect(try env.value("MAX ( 2.5, 1 )") == .double(2.5))
        // [SUY ĐOÁN] Vế BLANK bị bỏ qua.
        #expect(try env.value("MIN ( BLANK ( ), 5 )") == .integer(5))
        #expect(try env.value("MAX ( BLANK ( ), BLANK ( ) )") == .blank)
    }

    @Test func minColumnVoiHaiDoiSoBaoLoiSoLuong() throws {
        let env = FAggEnv.kho()
        #expect(fAggKindOf { try env.value("MIN ( Kho[so], 3 )") } == .arity)
    }
}
