// Kiểm tra context transition và row context trên MiniBank (CORE, đợt 2), architecture.md §4.2–4.3.
// Đáp án tính từ MiniBankExpected (Python stdlib) hoặc suy ra trực tiếp từ dữ liệu MiniBank:
// - Fact_Trans có 40 dòng, tổng amount = 1254298000 (currency ×10^4); 2023 và 2024 mỗi năm 20 dòng.
// - 6 khoá tài khoản trong Fact_Trans (1…5 và 99, 99 thành dòng BLANK của Dim_Account).
// [SUY ĐOÁN] Dòng BLANK ảo của Dim_Account được tính là một giá trị trong VALUES(Dim_Account[branch_city]).
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct COREContextTransitionTests {
    @Test func measureTrongSumxTheoKhoaTaiKhoanCHoDungTongTien() throws {
        let env = CoreEnvironment()
        let value = try evaluateText("SUMX ( VALUES ( Fact_Trans[account_key] ), [Trans Amount] )", in: env)
        #expect(value == .currency(MiniBankExpected.totalAmount))
    }

    @Test func measureTrongAverageXTheoKhoaTaiKhoan() throws {
        // 40 giao dịch chia đều cho 6 khoá tài khoản (gồm 99): trung bình 40/6.
        let env = CoreEnvironment()
        let value = try evaluateText("AVERAGEX ( VALUES ( Fact_Trans[account_key] ), [Trans Count] )", in: env)
        guard case .double(let d) = value else {
            Issue.record("kỳ vọng số thực, được \(value)")
            return
        }
        #expect(abs(d - 40.0 / 6.0) < 1e-9)
    }

    @Test func measureTrongSumxTheoNamKetQuaDung() throws {
        // Mỗi năm có 20 giao dịch: 20 + 20 = 40.
        let env = CoreEnvironment()
        let value = try evaluateText("SUMX ( VALUES ( Dim_Date[year] ), [Trans Count] )", in: env)
        #expect(value == .integer(40))
    }

    @Test func measureTrongSumxTrenBangVatLyKhongMaterialize() throws {
        // Lặp trên 40 dòng Fact_Trans: mỗi dòng là một context transition trên trans_key (không trùng).
        let env = CoreEnvironment()
        let value = try evaluateText("SUMX ( Fact_Trans, [Trans Amount] )", in: env)
        #expect(value == .currency(MiniBankExpected.totalAmount))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func sumxLongNhauGiuDongNgoaiVaTrong() throws {
        // Ngoài: năm (20 dòng mỗi năm); trong: 40 dòng fact. Tổng = 40·2023 + 40·2024 = 40·4047.
        let env = CoreEnvironment()
        let value = try evaluateText("SUMX ( VALUES ( Dim_Date[year] ), SUMX ( Fact_Trans, Dim_Date[year] ) )", in: env)
        #expect(value == .integer(161_880))
    }

    @Test func transitionTheoGiaTriDimCoDongBlank() throws {
        // Giá trị BLANK của branch_city trỏ tới dòng BLANK ảo của Dim_Account (FK 99: 1 giao dịch).
        let env = CoreEnvironment()
        let value = try evaluateText("SUMX ( VALUES ( Dim_Account[branch_city] ), [Trans Count] )", in: env)
        #expect(value == .integer(40))
    }
}
