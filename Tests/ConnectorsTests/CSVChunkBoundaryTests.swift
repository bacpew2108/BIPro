import Testing
import Foundation
@testable import Connectors

/// Lỗi tìm được ở `/code-review` T096: ranh giới khối đọc (64 KB) rơi giữa ký tự UTF-8 nhiều byte, giữa `""` trong ô có ngoặc kép,
/// giữa CR và LF; byte hỏng giữa tệp. Test ép khối rất nhỏ để mọi ranh giới đều rơi vào chỗ khó. Giá trị mong đợi viết tay.
@Suite struct CSVChunkBoundaryTests {
    private func write(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("csvb-\(UUID().uuidString).csv")
        try Data(bytes).write(to: url)
        return url
    }

    private func rows(_ text: String, chunk: Int) async throws -> [[String?]] {
        let url = try write(Array(text.utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        return try await CSVParser.readRows(url: url, delimiter: ",", encoding: .utf8, bomLength: 0, limit: nil, progress: nil, chunkSize: chunk)
    }

    @Test func multiByteAndEscapedQuotesAcrossEveryChunkSize() async throws {
        let text = "Tên,Ghi chú\r\nHà Nội,\"He said \"\"hi\"\"\"\r\nĐà Nẵng,\"a\r\nb\"\n"
        let expected: [[String?]] = [["Tên", "Ghi chú"], ["Hà Nội", "He said \"hi\""], ["Đà Nẵng", "a\r\nb"]]
        for chunk in 1...12 {
            #expect(try await rows(text, chunk: chunk) == expected, "khối \(chunk) byte")
        }
    }

    @Test func utf8DetectedWhenSampleEndsInsideCharacter() throws {
        // 8191 byte ASCII rồi "à" (2 byte): mẫu 8 KB cắt giữa ký tự.
        let url = try write(Array(String(repeating: "a", count: 8191).utf8) + Array("à\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try CSVParser.detectEncoding(url: url, preferred: nil).encoding == .utf8)
    }

    @Test func strayInvalidByteKeepsTheRestOfTheFile() async throws {
        var bytes = Array("a,b\n".utf8)
        bytes += Array("x,y".utf8) + [0xE9] + Array("\n".utf8)
        for i in 0..<50 { bytes += Array("r\(i),Đ\n".utf8) }
        let url = try write(bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        let out = try await CSVParser.readRows(url: url, delimiter: ",", encoding: .utf8, bomLength: 0, limit: nil, progress: nil, chunkSize: 16)
        #expect(out.count == 52)
        #expect(out[1] == ["x", "y\u{FFFD}"])
        #expect(out.last == ["r49", "Đ"])
    }
}
