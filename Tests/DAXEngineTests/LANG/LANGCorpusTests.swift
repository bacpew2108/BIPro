// Test corpus (LANG, đợt 1a): 316 measure của ba file mẫu phải parse được (tiêu chí 316/316).
// Mỗi khối "MEASURE ... = biểu thức" là một biểu thức, tách bằng dòng bắt đầu bằng MEASURE.
// Các file nằm trong fixtures/ cạnh file test này; chỉ đọc.
import Foundation
import Testing
import ColumnStore
@testable import DAXEngine

/// Một khối MEASURE trong file mẫu.
private struct MeasureBlock {
    let file: String
    let index: Int
    /// Toàn bộ khối, từ dòng MEASURE đến trước dòng MEASURE kế tiếp.
    let text: String

    /// Biểu thức: phần sau dấu bằng đầu tiên của khối.
    var expression: String {
        guard let eq = text.firstIndex(of: "=") else { return "" }
        return String(text[text.index(after: eq)...])
    }

    /// Thân chỉ gồm khoảng trắng và dòng chú thích "--".
    var hasEmptyBody: Bool {
        expression
            .components(separatedBy: "\n")
            .allSatisfy { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.isEmpty || t.hasPrefix("--")
            }
    }
}

private enum LANGCorpus {
    static let files: [(name: String, expected: Int)] = [
        ("nhom6-measures.dax", 168),
        ("n2-measures.dax", 23),
        ("n3-measures.dax", 125),
    ]

    static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")
            .appendingPathComponent(name)
    }

    /// Tách file thành các khối MEASURE.
    static func blocks(of name: String) throws -> [MeasureBlock] {
        let text = try String(contentsOf: fixtureURL(name), encoding: .utf8)
        var blocks: [MeasureBlock] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty {
                blocks.append(MeasureBlock(file: name, index: blocks.count, text: current.joined(separator: "\n")))
            }
            current = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("MEASURE") {
                flush()
            }
            if !current.isEmpty || line.hasPrefix("MEASURE") {
                current.append(line)
            }
        }
        flush()
        return blocks
    }

    static func allBlocks() throws -> [MeasureBlock] {
        try files.flatMap { try blocks(of: $0.name) }
    }
}

@Suite struct LANGCorpusTests {
    @Test func soKhoiKhopFile() throws {
        for file in LANGCorpus.files {
            let blocks = try LANGCorpus.blocks(of: file.name)
            #expect(blocks.count == file.expected, "\(file.name): có \(blocks.count) khối, cần \(file.expected)")
        }
        let total = try LANGCorpus.allBlocks().count
        #expect(total == 316)
    }

    /// Mỗi khối có thân là một DEFINE MEASURE hợp lệ, cộng một EVALUATE thành truy vấn hoàn chỉnh.
    /// Khối có thân rỗng (chỉ có chú thích) phải báo lỗi cú pháp, không được nuốt.
    @Test func moiKhoiParseNhuTruyVanDefineMeasure() throws {
        var failures: [String] = []
        for block in try LANGCorpus.allBlocks() {
            let query = "DEFINE\n" + block.text + "\nEVALUATE ROW(\"x\", 1)"
            do {
                let parsed = try parseQuery(query)
                if block.hasEmptyBody {
                    failures.append("\(block.file)#\(block.index): thân rỗng mà vẫn parse được")
                } else if parsed.defines.count != 1 {
                    failures.append("\(block.file)#\(block.index): \(parsed.defines.count) định nghĩa")
                }
            } catch {
                if !block.hasEmptyBody {
                    failures.append("\(block.file)#\(block.index): \(error.message)")
                } else if error.kind != .syntax {
                    failures.append("\(block.file)#\(block.index): lỗi không phải cú pháp")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5).joined(separator: "\n"))")
    }

    /// Biểu thức sau dấu bằng parse được một mình.
    /// Kết quả thật: 312 biểu thức parse được. 4 khối trong n3 có thân rỗng (Measure, Measure 2–4),
    /// không phải biểu thức, nên tiêu chí "316/316" không đạt theo nghĩa đen; báo cáo cho lead.
    @Test func bieuThucParse312Tren316() throws {
        var ok = 0
        var empty = 0
        var failures: [String] = []
        for block in try LANGCorpus.allBlocks() {
            if block.hasEmptyBody {
                empty += 1
                do {
                    _ = try parseExpression(block.expression)
                    failures.append("\(block.file)#\(block.index): thân rỗng mà parse được")
                } catch {
                    if error.kind != .syntax { failures.append("\(block.file)#\(block.index): lỗi không phải cú pháp") }
                }
                continue
            }
            do {
                _ = try parseExpression(block.expression)
                ok += 1
            } catch {
                failures.append("\(block.file)#\(block.index): \(error.message)")
            }
        }
        #expect(ok == 312, "\(ok)/312 biểu thức có thân parse được. \(failures.prefix(5).joined(separator: "\n"))")
        #expect(empty == 4, "có \(empty) khối thân rỗng, cần 4")
    }
}
