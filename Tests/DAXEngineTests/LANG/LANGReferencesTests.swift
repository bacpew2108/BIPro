// Phase E (R6): danh sách tên bảng, cột, measure mà một biểu thức DAX nhắc tới (để chặn xoá và đổi tên khi còn nơi dùng).
import Testing
@testable import DAXEngine

@Suite struct LANGReferencesTests {
    private func refs(_ text: String) -> [String] {
        DAXEngine.references(in: text).map { ($0.table.map { "\($0)." } ?? "") + $0.name }
    }

    @Test func cotCoBangVaMeasureKhongBang() {
        #expect(refs("SUM ( Fact_Loan[loan_amount] ) / [Total Loans]") == ["Fact_Loan.loan_amount", "Total Loans"])
    }

    @Test func tenBangTrongNhayDon() {
        #expect(refs("CALCULATE ( [M], 'Dim Date'[year] = 2020 )") == ["M", "Dim Date.year"])
    }

    @Test func chuoiVaChuThichKhongTinh() {
        #expect(refs(#"IF ( x = "Fact[Hidden]", [Real], 0 ) // [Comment] Foo[Bar]"#) == ["Real"])
        #expect(refs("/* T[a] */ T[b]") == ["T.b"])
    }

    @Test func tenCoDauNgoacVuongKep() {
        #expect(refs("T[a]]b]") == ["T.a]b"])
    }

    @Test func bangTrongNhayVoiDauNhayKep() {
        #expect(refs("'O''Brien'[x]") == ["O'Brien.x"])
    }

    @Test func loiCuPhapKhongNem() {
        #expect(refs("SUM ( T[a]  \"unterminated") == [])
    }
}
