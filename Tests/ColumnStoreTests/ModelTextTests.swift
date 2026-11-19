// T022: chuỗi vào kho như Desktop (VM-F12): bỏ khoảng trắng cuối, gộp hoa thường giữ cách viết gặp trước, không chuẩn hoá Unicode.
import ColumnStore
import Testing

struct ModelTextTests {
    @Test func nhuKhoDesktop() {
        let nfc = "H\u{E0} N\u{1ED9}i", nfd = "Ha\u{300} No\u{323}\u{302}i"
        let input: [String?] = ["  khoảng trắng   giữa  ", " 12 ", "abc", "ABC", nil, "", nfc, nfd, "Abc ", "tab\tgiữa"]
        let out = ModelText.normalize(input)
        #expect(out[0] == "  khoảng trắng   giữa" && out[1] == " 12")
        #expect(out[2] == "abc" && out[3] == "abc" && out[8] == "abc")
        #expect(out[4] == nil && out[5] == "")
        // NFC và NFD vẫn là hai giá trị khác nhau.
        #expect(out[6].map { Array($0.utf16) } == Array(nfc.utf16) && out[7].map { Array($0.utf16) } == Array(nfd.utf16))
        #expect(out[9] == "tab\tgiữa")
        // Chữ có dấu khác hoa thường: hai giá trị (VM-F12, MID-2-3 dòng 1 và 3).
        #expect(ModelText.normalize(["à N", "À N"]) == ["à N", "À N"])
    }

    @Test func cotKhongPhaiChuGiuNguyen() {
        let ints = ColumnBuilder.integers([1, nil, 3])
        #expect(ModelText.normalize(ints).value(at: 2) == .integer(3))
        let strings = ModelText.normalize(ColumnBuilder.strings(["x", "X "]))
        #expect(strings.value(at: 1) == .string("x"))
    }
}
