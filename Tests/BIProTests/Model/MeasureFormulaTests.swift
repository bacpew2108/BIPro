import Testing
@testable import BIPro

/// Phase E (T014): thanh công thức của measure có dạng `Tên = biểu thức` như Desktop.
@Suite struct MeasureFormulaTests {
    @Test func tachTenVaBieuThuc() {
        let parsed = MeasureFormula.parse("Total Sales = SUM(Fact[amount])")
        #expect(parsed == MeasureFormula.Parts(name: "Total Sales", expression: "SUM(Fact[amount])"))
    }

    @Test func dauBangTrongBieuThucKhongTachNhamTenKiNhay() {
        #expect(MeasureFormula.parse("M = IF(a = 1, 2, 3)") == MeasureFormula.Parts(name: "M", expression: "IF(a = 1, 2, 3)"))
        #expect(MeasureFormula.parse("[M] = 1") == MeasureFormula.Parts(name: "M", expression: "1"))
        #expect(MeasureFormula.parse("'A = B' = 1") == MeasureFormula.Parts(name: "A = B", expression: "1"))
    }

    @Test func nhieuDongGiuNguyenBieuThuc() {
        let text = "M =\nVAR x = 1\nRETURN x"
        #expect(MeasureFormula.parse(text) == MeasureFormula.Parts(name: "M", expression: "VAR x = 1\nRETURN x"))
    }

    @Test func thieuTenHoacDauBang() {
        #expect(MeasureFormula.parse("SUM(a)") == nil)
        #expect(MeasureFormula.parse("= 1") == nil)
        #expect(MeasureFormula.parse("   ") == nil)
        #expect(MeasureFormula.parse("M =")?.expression == "")
    }

    @Test func dinhDangLaiTheoDesktop() {
        #expect(MeasureFormula.format(name: "Total Sales", expression: "SUM(a)") == "Total Sales = SUM(a)")
        #expect(MeasureFormula.format(name: "M", expression: "VAR x = 1\nRETURN x") == "M =\nVAR x = 1\nRETURN x")
    }
}
