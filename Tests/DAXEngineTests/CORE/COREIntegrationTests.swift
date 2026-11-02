// Kiểm tra tích hợp CORE (đợt 3): TREATAS hai cột trong CALCULATE (architecture.md §4.1, §5.4), và lặp
// ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT trên bảng vật lý không vật chất hoá (§7.1).
// Đáp án lấy từ core_oracle.py (Python 3 stdlib, đọc MiniBankData.swift), không dùng Swift để tính.
// Đơn vị currency là Int64 nhân 10^4: 1254298000 là 125429,8000 hiển thị.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

/// Các tuple (city, state_name) của Dim_District dùng trong test TREATAS hai cột. Hai tuple khớp hai dòng.
private let districtTuples = """
{ ( "Hà Nội", "Thành phố Hà Nội" ), ( "TP. Hồ Chí Minh", "Thành phố Hồ Chí Minh" ) }
"""

@Suite struct COREIntegrationTests {

    // MARK: TREATAS hai cột trong CALCULATE

    @Test func treatasHaiCotTrongCalculateLocDimDistrict() throws {
        // Đáp án Python: 2 dòng Dim_District khớp hai tuple.
        let env = CoreEnvironment()
        let expr = """
        CALCULATE (
            COUNTROWS ( Dim_District ),
            TREATAS ( \(districtTuples), Dim_District[city], Dim_District[state_name] )
        )
        """
        #expect(try evaluateText(expr, in: env) == .integer(2))
    }

    @Test func treatasSummarizeHaiCotTrongCalculate() throws {
        // Nguồn là SUMMARIZE hai cột của chính Dim_District: mọi tuple đều khớp, đáp án Python 3 dòng.
        let env = CoreEnvironment()
        let expr = """
        CALCULATE (
            COUNTROWS ( Dim_District ),
            TREATAS (
                SUMMARIZE ( Dim_District, Dim_District[city], Dim_District[state_name] ),
                Dim_District[city],
                Dim_District[state_name]
            )
        )
        """
        #expect(try evaluateText(expr, in: env) == .integer(3))
    }

    @Test func treatasHaiCotGhiDeCotCuaNguCanhNgoai() throws {
        // Ngữ cảnh ngoài lọc city = Đà Nẵng. TREATAS (không KEEPFILTERS) ghi đè city và state_name: vẫn 2 dòng.
        let env = CoreEnvironment()
        let expr = """
        CALCULATE (
            CALCULATE (
                COUNTROWS ( Dim_District ),
                TREATAS ( \(districtTuples), Dim_District[city], Dim_District[state_name] )
            ),
            Dim_District[city] = "Đà Nẵng"
        )
        """
        #expect(try evaluateText(expr, in: env) == .integer(2))
    }

    @Test func treatasHaiCotKeepFiltersGiaoVoiNguCanhNgoai() throws {
        // KEEPFILTERS giao tập dòng TREATAS với city = TP. Hồ Chí Minh (1 dòng), và với Đà Nẵng (0 dòng).
        let env = CoreEnvironment()
        let hcm = """
        CALCULATE (
            CALCULATE (
                COUNTROWS ( Dim_District ),
                KEEPFILTERS ( TREATAS ( \(districtTuples), Dim_District[city], Dim_District[state_name] ) )
            ),
            Dim_District[city] = "TP. Hồ Chí Minh"
        )
        """
        #expect(try evaluateText(hcm, in: env) == .integer(1))
        let danang = """
        CALCULATE (
            CALCULATE (
                COUNTROWS ( Dim_District ),
                KEEPFILTERS ( TREATAS ( \(districtTuples), Dim_District[city], Dim_District[state_name] ) )
            ),
            Dim_District[city] = "Đà Nẵng"
        )
        """
        #expect(try evaluateText(danang, in: env) == .integer(0))
    }

    @Test func treatasHaiCotKhongQuanHeKhongDoiTransAmount() throws {
        // Dim_District không có quan hệ với Fact_Trans: bộ lọc tuple không đổi Trans Amount (đáp án Python: tổng đủ 40 dòng).
        let env = CoreEnvironment()
        let expr = "CALCULATE ( [Trans Amount], TREATAS ( \(districtTuples), Dim_District[city], Dim_District[state_name] ) )"
        #expect(try evaluateText(expr, in: env) == .currency(1_254_298_000))
    }

    @Test func treatasHaiCotTuBangKhacNhauBaoLoi() throws {
        // Các cột đích thuộc hai bảng khác nhau: CALCULATE báo .runtime (không ghép được thành một bộ lọc theo bảng).
        let env = CoreEnvironment()
        let expr = "CALCULATE ( COUNTROWS ( Dim_District ), TREATAS ( { ( \"Hà Nội\", 1 ) }, Dim_District[city], Fact_Trans[amount] ) )"
        do {
            _ = try evaluateText(expr, in: env)
            Issue.record("phải báo lỗi khi cột đích thuộc hai bảng")
        } catch let error as DAXError {
            #expect(error.kind == .runtime)
        }
    }

    // MARK: Lặp không vật chất hoá (ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT)

    @Test func sumxAllFactTransKhongVatChatHoa() throws {
        // Đáp án Python: tổng 1254298000 trên 40 dòng; lặp trên RowSet nên không materialize dòng nào.
        let env = CoreEnvironment()
        let value = try evaluateText("SUMX ( ALL ( Fact_Trans ), Fact_Trans[amount] )", in: env)
        #expect(value == .currency(1_254_298_000))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func countRowsALLVaALLNOBLANKROWKhongVatChatHoa() throws {
        // Đáp án Python: 40 dòng Fact_Trans; Dim_Account 5 dòng thật, 6 khi tính BLANK ảo (FK 99), ALLNOBLANKROW còn 5.
        let env = CoreEnvironment()
        #expect(try evaluateText("COUNTROWS ( ALL ( Fact_Trans ) )", in: env) == .integer(40))
        #expect(try evaluateText("COUNTROWS ( ALL ( Dim_Account ) )", in: env) == .integer(6))
        #expect(try evaluateText("COUNTROWS ( ALLNOBLANKROW ( Dim_Account ) )", in: env) == .integer(5))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func allExceptVaALLSelectedKhongVatChatHoa() throws {
        // ALLEXCEPT bỏ bộ lọc branch_city, giữ card_type: 6 dòng (kể cả BLANK ảo), đáp án Python.
        let env = CoreEnvironment()
        let allExcept = """
        CALCULATE (
            COUNTROWS ( ALLEXCEPT ( Dim_Account, Dim_Account[card_type] ) ),
            Dim_Account[branch_city] = "Đà Nẵng"
        )
        """
        #expect(try evaluateText(allExcept, in: env) == .integer(6))
        // ALLSELECTED(Fact_Trans) không có shadow, giữ slicer năm 2024: 20 giao dịch, tổng 688067300 (đáp án Python).
        let selected = "CALCULATE ( SUMX ( ALLSELECTED ( Fact_Trans ), Fact_Trans[amount] ), Dim_Date[year] = 2024 )"
        #expect(try evaluateText(selected, in: env) == .currency(688_067_300))
        #expect(env.evaluator.materializedRowCount == 0)
    }
}
