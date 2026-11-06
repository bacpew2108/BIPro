// Hàm chuỗi thêm cho Advanced filter của Filters pane: CONTAINSSTRING, CONTAINSSTRINGEXACT, LEFT.
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct FKITTextTests {
    @Test func containsStringKhongPhanBietHoaThuong() {
        #expect(fkChay("CONTAINSSTRING", [fkLit(.string("Northeast")), fkLit(.string("EAST"))]) == .success(.boolean(true)))
        #expect(fkChay("CONTAINSSTRING", [fkLit(.string("Midwest")), fkLit(.string("south"))]) == .success(.boolean(false)))
        #expect(fkChay("CONTAINSSTRING", [fkLit(.string("abc")), fkLit(.string(""))]) == .success(.boolean(true)), "find rỗng là TRUE")
        #expect(fkChay("CONTAINSSTRING", [fkLit(.blank), fkLit(.string("x"))]) == .success(.boolean(false)), "BLANK coi như chuỗi rỗng")
    }

    @Test func containsStringExactPhanBietHoaThuong() {
        #expect(fkChay("CONTAINSSTRINGEXACT", [fkLit(.string("Northeast")), fkLit(.string("east"))]) == .success(.boolean(true)))
        #expect(fkChay("CONTAINSSTRINGEXACT", [fkLit(.string("Northeast")), fkLit(.string("EAST"))]) == .success(.boolean(false)))
    }

    @Test func leftLayDauChuoi() {
        #expect(fkChay("LEFT", [fkLit(.string("Midwest")), fkLit(.integer(3))]) == .success(.string("Mid")))
        #expect(fkChay("LEFT", [fkLit(.string("Midwest"))]) == .success(.string("M")), "mặc định 1 ký tự")
        #expect(fkChay("LEFT", [fkLit(.string("ab")), fkLit(.integer(9))]) == .success(.string("ab")))
        if case .failure = fkChay("LEFT", [fkLit(.string("ab")), fkLit(.integer(-1))]) {} else { Issue.record("n âm phải là lỗi") }
    }
}
