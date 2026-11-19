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

    /// Dạng Power BI sinh cho "contains" (C2 A1): SEARCH("east", col, 1, 0) >= 1.
    @Test func searchTraViTriHoacNotFound() {
        let find = { (a: String, b: String, extra: [Value]) in fkChay("SEARCH", [fkLit(.string(a)), fkLit(.string(b))] + extra.map(fkLit)) }
        #expect(find("EAST", "Northeast", [.integer(1), .integer(0)]) == .success(.integer(6)))
        #expect(find("south", "Midwest", [.integer(1), .integer(0)]) == .success(.integer(0)), "không thấy trả not_found_value")
        #expect(find("n*st", "Northeast", [.integer(1), .integer(0)]) == .success(.integer(1)), "ký tự đại diện *")
        #expect(find("o?th", "Northeast", [.integer(1), .integer(0)]) == .success(.integer(2)), "ký tự đại diện ?")
        #expect(find("e", "Northeast", [.integer(6)]) == .success(.integer(6)), "bắt đầu tìm từ start_num")
        if case .failure = find("x", "abc", []) {} else { Issue.record("không thấy và thiếu not_found_value phải là lỗi") }
        // T061 (review): ký tự viết hoa dài hơn (U+FB00 "ﬀ" → "FF", "ŉ" → "ʼN") không làm lệch vị trí trong chuỗi gốc.
        #expect(find("x", "\u{FB00}x", []) == .success(.integer(2)))
        #expect(find("x", "\u{149}\u{149}x", []) == .success(.integer(3)))
        #expect(find("?x", "\u{FB00}x", []) == .success(.integer(1)))
    }

    /// T061 (review): đối số đúng 2^63 không làm sập tiến trình (tràn khi đổi sang Int).
    @Test func doiSoCucLonKhongSap() {
        if case .success(let v) = fkChay("LEFT", [fkLit(.string("abc")), fkLit(.double(9_223_372_036_854_775_808))]) {
            #expect(v == .string("abc"))
        }
        _ = fkChay("REPT", [fkLit(.string("")), fkLit(.double(9_223_372_036_854_775_808))])
    }
}
