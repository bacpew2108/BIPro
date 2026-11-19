// specs/011, T061 (review): giải nén Deflate dữ liệu cụt hoặc rỗng báo lỗi, không lặp mãi (M Enter Data hỏng trong .pbix).
import Foundation
import Testing
@testable import MEngine

@Suite struct BinaryInflateTests {
    @Test func duLieuDuDocLaiDung() throws {
        let text = Data(String(repeating: "Hà Nội, Đà Nẵng; ", count: 200).utf8)
        #expect(try MBinary.inflate(MBinary.deflate(text)) == text)
    }

    @Test func duLieuCutHoacRongBaoLoi() {
        let full = MBinary.deflate(Data(String(repeating: "abcdefghij", count: 500).utf8))
        for broken in [Data(), full.prefix(full.count / 2), full.prefix(1)] {
            #expect(throws: (any Error).self) { _ = try MBinary.inflate(Data(broken)) }
        }
    }
}
