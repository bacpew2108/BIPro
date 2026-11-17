// VM-F12 (T018): Desktop lưu được chuỗi có surrogate lẻ (MID("x😀y", 2, 1) cắt giữa emoji). Trước đây một surrogate lẻ
// làm cả trang từ điển chuỗi đọc ra rỗng; nay chỉ đơn vị lẻ thành U+FFFD, các chuỗi khác giữ nguyên.
import Foundation
import Testing
@testable import PBIXKit

struct UTF16LenientTests {
    private func bytes(_ units: [UInt16]) -> Data {
        Data(units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
    }

    @Test func surrogateLeChiThayDonViLe() {
        // "ab\0" + "x" + D83D (lẻ) + "\0" + "😀\0"
        let data = bytes([0x61, 0x62, 0, 0x78, 0xD83D, 0, 0xD83D, 0xDE00, 0])
        #expect(data.utf16LEString().components(separatedBy: "\0") == ["ab", "x\u{FFFD}", "😀", ""])
    }

    @Test func boVanBOMNhuCu() {
        #expect(bytes([0xFEFF, 0x41]).utf16LEString() == "A")
    }
}
