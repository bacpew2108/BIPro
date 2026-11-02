// WP F-AGG (đợt 3): SUMX, AVERAGEX, MINX, MAXX (có context transition), CONCATENATEX, PERCENTILEX.INC, RANKX.
// Đáp án: fagg_expected.py (Python stdlib). Đơn vị currency là Int64 đã nhân 10^4.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FAggIteratorTests {

    // MARK: SUMX và AVERAGEX

    @Test func sumxCotTienTrenBangVatLyKhongMaterialize() throws {
        let env = FAggEnv.minibank()
        #expect(try env.value("SUMX ( Fact_Trans, Fact_Trans[amount] )") == .currency(1_254_298_000))
        // Lặp bảng vật lý qua iterateArgument: không dòng nào được materialize.
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func sumxCoBoLocNam2023() throws {
        let env = FAggEnv.minibank()
        let nam2023 = try env.filter("Dim_Date", "year", [.integer(2023)])
        #expect(try env.value("SUMX ( Fact_Trans, Fact_Trans[amount] )", filter: nam2023) == .currency(566_230_700))
    }

    @Test func sumxConTransitionQuaMeasureTrenDimAccount() throws {
        let env = FAggEnv.minibank()
        // Mỗi tài khoản (1..5) có 8, 8, 8, 8, 7 giao dịch. Dòng BLANK ảo của Dim_Account (FK 99 mồ côi) thấy được
        // và được lặp, với 1 giao dịch: 8 + 8 + 8 + 8 + 7 + 1 = 40 [SUY ĐOÁN: khớp §3.3 và quan sát MiniBankExpected].
        #expect(try env.value("SUMX ( Dim_Account, [Trans Count] )") == .integer(40))
    }

    @Test func sumxConTransitionQuaValuesKhoaTaiKhoan() throws {
        let env = FAggEnv.minibank()
        // VALUES có sáu khoá (gồm 99): 40 giao dịch.
        #expect(try env.value("SUMX ( VALUES ( Fact_Trans[account_key] ), [Trans Count] )") == .integer(40))
    }

    @Test func sumxMeasureTrenFactTransMoiDongLaMotGiaoDich() throws {
        let env = FAggEnv.minibank()
        // Mỗi dòng fact được transition thành đúng dòng đó, nên tổng Trans Amount là tổng cột amount.
        #expect(try env.value("SUMX ( Fact_Trans, [Trans Amount] )") == .currency(1_254_298_000))
    }

    @Test func averagexConTransitionVaCurrency() throws {
        let env = FAggEnv.minibank()
        // (8 + 8 + 8 + 8 + 7 + 1) / 6 = 20/3.
        #expect(try env.value("AVERAGEX ( Dim_Account, [Trans Count] )") == .double(40.0 / 6.0))
        #expect(try env.value("AVERAGEX ( Fact_Trans, Fact_Trans[amount] )") == .currency(31_357_450))
    }

    @Test func sumxAverageXTrenKhoNhoBoQuaBlank() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("SUMX ( Kho, Kho[so] )") == .integer(21))
        #expect(try env.value("AVERAGEX ( Kho, Kho[so] )") == .double(4.2))
        #expect(try env.value("SUMX ( Kho, Kho[tien] )") == .currency(155_000))
        #expect(try env.value("AVERAGEX ( Kho, Kho[tien] )") == .currency(31_000))
        #expect(try env.value("SUMX ( Kho, Kho[thuc] )") == .double(7.5))
    }

    // MARK: MINX và MAXX

    @Test func minxMaxxTrenKhoVaMiniBank() throws {
        let kho = FAggEnv.kho()
        #expect(try kho.value("MINX ( Kho, Kho[so] )") == .integer(1))
        #expect(try kho.value("MAXX ( Kho, Kho[so] )") == .integer(7))
        #expect(try kho.value("MINX ( Kho, Kho[thuc] )") == .double(-3.0))
        let env = FAggEnv.minibank()
        // Dim_Account gồm 5 dòng thật (8, 8, 8, 8, 7) và dòng BLANK ảo (1).
        #expect(try env.value("MINX ( Dim_Account, [Trans Count] )") == .integer(1))
        #expect(try env.value("MAXX ( Dim_Account, [Trans Count] )") == .integer(8))
    }

    @Test func minxBangRongLaBlank() throws {
        let env = FAggEnv.kho()
        let khong = try env.filter("Kho", "so", [.integer(99)])
        #expect(try env.value("MINX ( Kho, Kho[so] )", filter: khong) == .blank)
    }

    // MARK: CONCATENATEX

    @Test func concatenatexThuTuLapVaDelimiter() throws {
        let env = FAggEnv.minibank()
        #expect(try env.value("CONCATENATEX ( Dim_Account, Dim_Account[branch_city], \", \" )")
            == .string("Hà Nội, Đà Nẵng, TP. Hồ Chí Minh, Hà Nội, Đà Nẵng"))
    }

    @Test func concatenatexOrderDescTheoKhoa() throws {
        let env = FAggEnv.minibank()
        #expect(try env.value("CONCATENATEX ( Dim_Account, Dim_Account[branch_city], \", \", Dim_Account[account_key], DESC )")
            == .string("Đà Nẵng, Hà Nội, TP. Hồ Chí Minh, Đà Nẵng, Hà Nội"))
    }

    @Test func concatenatexBoQuaBlankTrenFactTrans() throws {
        let env = FAggEnv.minibank()
        // Đáp án Python: 39 vùng (dòng FK 99 là BLANK, bị bỏ qua), sắp theo trans_key giảm dần.
        let dapAn = "Miền Bắc|Miền Bắc|Unknown|Miền Trung|Miền Bắc|Miền Bắc|Miền Trung|Unknown|Miền Trung|Unknown|Miền Bắc|Miền Trung|Miền Trung|Miền Bắc|Miền Bắc|Miền Trung|Miền Trung|Unknown|Miền Trung|Miền Trung|Miền Trung|Unknown|Miền Trung|Unknown|Miền Bắc|Miền Bắc|Miền Trung|Miền Bắc|Miền Bắc|Miền Bắc|Miền Bắc|Miền Bắc|Miền Trung|Miền Trung|Miền Trung|Miền Bắc|Miền Trung|Miền Bắc|Unknown"
        #expect(try env.value("CONCATENATEX ( Fact_Trans, Fact_Trans[client_region], \"|\", Fact_Trans[trans_key], DESC )")
            == .string(dapAn))
    }

    @Test func concatenatexKhoNhoBlankVaOrderAscDesc() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("CONCATENATEX ( Kho, Kho[so], \",\" )") == .string("5,3,5,1,7"))
        #expect(try env.value("CONCATENATEX ( Kho, Kho[nhom], \" | \" )") == .string("a | b | a | c | b"))
        // Sắp theo thực giảm dần: 4,0(c), 2,5(a), 2,0(b), 1,5(a), 0,5(BLANK bỏ), -3,0(b).
        #expect(try env.value("CONCATENATEX ( Kho, Kho[nhom], \" | \", Kho[thuc], DESC )") == .string("c | a | b | a | b"))
        #expect(try env.value("CONCATENATEX ( Kho, Kho[nhom], \" | \", Kho[thuc], ASC )") == .string("b | a | b | a | c"))
    }

    @Test func concatenatexBangRongLaChuoiRong() throws {
        let env = FAggEnv.kho()
        let khong = try env.filter("Kho", "so", [.integer(99)])
        #expect(try env.value("CONCATENATEX ( Kho, Kho[nhom], \",\" )", filter: khong) == .string(""))
    }

    // MARK: PERCENTILEX.INC

    @Test func percentilexIncTrungVi() throws {
        let env = FAggEnv.minibank()
        // trans_key là 1..40: k = 0,5 cho (rank 19,5) → 20,5.
        #expect(try env.value("PERCENTILEX.INC ( Fact_Trans, Fact_Trans[trans_key], 0.5 )") == .double(20.5))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func percentilexIncK25VaDesc() throws {
        let env = FAggEnv.minibank()
        // k = 0,25: rank 9,75 → 10 + 0,75 = 10,75. DESC: sắp giảm, cùng công thức → 30,25.
        #expect(try env.value("PERCENTILEX.INC ( Fact_Trans, Fact_Trans[trans_key], 0.25 )") == .double(10.75))
        #expect(try env.value("PERCENTILEX.INC ( Fact_Trans, Fact_Trans[trans_key], 0.25, DESC )") == .double(30.25))
    }

    @Test func percentilexIncKhoNhoNoiSuyVaBlank() throws {
        let env = FAggEnv.kho()
        // thuc sắp tăng: -3; 0,5; 1,5; 2,0; 2,5; 4,0. k = 0,5: 1,5 + 0,5·0,5 = 1,75. k = 0,25: 0,5 + 0,25·1 = 0,75.
        #expect(try env.value("PERCENTILEX.INC ( Kho, Kho[thuc], 0.5 )") == .double(1.75))
        #expect(try env.value("PERCENTILEX.INC ( Kho, Kho[thuc], 0.25 )") == .double(0.75))
        // so không BLANK: {1, 3, 5, 5, 7}, k = 0,5 → 5.
        #expect(try env.value("PERCENTILEX.INC ( Kho, Kho[so], 0.5 )") == .double(5.0))
    }

    @Test func percentilexIncKRaNgoaiKhoangBaoLoi() throws {
        let env = FAggEnv.kho()
        #expect(fAggKindOf { try env.value("PERCENTILEX.INC ( Kho, Kho[so], 1.5 )") } == .runtime)
    }

    // MARK: RANKX

    @Test func rankxGiaTriTrungDenseVaSkip() throws {
        let env = FAggEnv.kho()
        // so = {5, BLANK, 3, 5, 1, 7}. Giá trị 3 có hai giá trị hơn (5, 5, 7): SKIP 4, DENSE 3.
        #expect(try env.value("RANKX ( Kho, Kho[so], 3, DESC, SKIP )") == .integer(4))
        #expect(try env.value("RANKX ( Kho, Kho[so], 3, DESC, DENSE )") == .integer(3))
        // Giá trị 5 (hoà với một dòng 5): chỉ 7 hơn, nên cả hai cách cho 2.
        #expect(try env.value("RANKX ( Kho, Kho[so], 5, DESC, SKIP )") == .integer(2))
        #expect(try env.value("RANKX ( Kho, Kho[so], 5, DESC, DENSE )") == .integer(2))
    }

    @Test func rankxAscVaMacDinh() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("RANKX ( Kho, Kho[so], 5, ASC, SKIP )") == .integer(3))
        #expect(try env.value("RANKX ( Kho, Kho[so], 5, ASC, DENSE )") == .integer(3))
        #expect(try env.value("RANKX ( Kho, Kho[so], 3, ASC, SKIP )") == .integer(2))
        // Mặc định: DESC và SKIP. Giá trị 3 có hai giá trị hơn nên ra 4.
        #expect(try env.value("RANKX ( Kho, Kho[so], 3 )") == .integer(4))
    }

    @Test func rankxValueBlankChoBlank() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("RANKX ( Kho, Kho[so], BLANK ( ) )") == .blank)
    }

    @Test func rankxTrongSumxLaySoThuHangTheoDong() throws {
        let env = FAggEnv.kho()
        // Dòng BLANK cho BLANK và bị SUMX bỏ qua. Thứ hạng SKIP theo dòng: 2, _, 4, 2, 5, 1 → tổng 14.
        #expect(try env.value("SUMX ( Kho, RANKX ( Kho, Kho[so], , DESC, SKIP ) )") == .integer(14))
        // DENSE theo dòng: 2, _, 3, 2, 4, 1 → tổng 12.
        #expect(try env.value("SUMX ( Kho, RANKX ( Kho, Kho[so], , DESC, DENSE ) )") == .integer(12))
    }

    @Test func rankxHoaNhauTrenDimAccountMiniBank() throws {
        let env = FAggEnv.minibank()
        // Số giao dịch: 8, 8, 8, 8, 7 và dòng BLANK ảo 1. SKIP: 1,1,1,1,5,6 → 15. DENSE: 1,1,1,1,2,3 → 9.
        #expect(try env.value("SUMX ( Dim_Account, RANKX ( Dim_Account, [Trans Count], , DESC, SKIP ) )") == .integer(15))
        #expect(try env.value("SUMX ( Dim_Account, RANKX ( Dim_Account, [Trans Count], , DESC, DENSE ) )") == .integer(9))
    }
}
