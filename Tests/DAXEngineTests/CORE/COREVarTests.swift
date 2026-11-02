// Kiểm tra VAR lồng nhau, VAR trong đối số, và VAR tính lười (CORE, đợt 2), architecture.md §5.4.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct COREVarTests {
    @Test func varTrongDoiSoCalculate() throws {
        let env = CoreEnvironment()
        let value = try evaluateText("CALCULATE ( [Trans Count], VAR y = 2024 RETURN Dim_Date[year] = y )", in: env)
        #expect(value == .integer(20))
    }

    @Test func varLongNhauThayNhauTrongKhoi() throws {
        // b = a + 1 đọc a đã khai báo trước trong cùng khối.
        let env = CoreEnvironment()
        let value = try evaluateText(
            "VAR a = 2023 VAR b = a + 1 RETURN CALCULATE ( [Trans Count], Dim_Date[year] = b )", in: env)
        #expect(value == .integer(20))
    }

    @Test func varBangTrongBieuThucDuocDanhGiaTrongNguCanhCalculate() throws {
        // VAR t nhận bảng trong ngữ cảnh 2024 (20 dòng), nên SUMX cho đúng tổng 2024.
        let env = CoreEnvironment()
        let value = try evaluateText(
            "CALCULATE ( VAR t = Fact_Trans RETURN SUMX ( t, Fact_Trans[amount] ), Dim_Date[year] = 2024 )", in: env)
        #expect(value == .currency(688_067_300))
    }

    @Test func varKhongDungKhongDuocTinh() throws {
        // VAR x = SUM(...) không được dùng: thân SUM không chạy (VAR lười).
        let env = CoreEnvironment()
        let value = try evaluateText("VAR x = SUM ( Fact_Trans[amount] ) RETURN 7", in: env)
        #expect(value == .integer(7))
        #expect(env.counter.value == 0)
    }

    @Test func varDungMotLanKhiDungNhieuLan() throws {
        // x được dùng hai lần nhưng chỉ tính một lần (thân SUM chạy đúng một lần).
        let env = CoreEnvironment()
        let value = try evaluateText("VAR x = SUM ( Fact_Trans[amount] ) RETURN x + x", in: env)
        #expect(value == .currency(2 * MiniBankExpected.totalAmount))
        #expect(env.counter.value == 1)
    }
}
