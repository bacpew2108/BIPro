import PBIXKit
import Foundation
import ColumnStore

/// [SUY ĐOÁN] Bộ phân tích CSV dạng luồng hỗ trợ ngoặc kép RFC 4180, xuống dòng LF/CRLF/CR,
/// phát hiện BOM và tự dò dấu phân cách.
enum CSVParser {
    struct DetectionResult {
        let encoding: String.Encoding
        let bomLength: Int
    }

    /// [SUY ĐOÁN] Tự dò mã hoá từ BOM hoặc nội dung mẫu UTF-8 / Windows-1252
    static func detectEncoding(url: URL, preferred: String.Encoding?) throws -> DetectionResult {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw SourceError.unreadable(lt("Không thể mở file: \(url.lastPathComponent)", "Couldn't open the file: \(url.lastPathComponent)"))
        }
        defer { try? handle.close() }

        let headerData = (try? handle.read(upToCount: 4)) ?? Data()

        // Kiểm tra BOM
        if headerData.count >= 3 && headerData[0] == 0xEF && headerData[1] == 0xBB && headerData[2] == 0xBF {
            return DetectionResult(encoding: preferred ?? .utf8, bomLength: 3)
        }
        if headerData.count >= 2 && headerData[0] == 0xFF && headerData[1] == 0xFE {
            return DetectionResult(encoding: preferred ?? .utf16LittleEndian, bomLength: 2)
        }
        if headerData.count >= 2 && headerData[0] == 0xFE && headerData[1] == 0xFF {
            return DetectionResult(encoding: preferred ?? .utf16BigEndian, bomLength: 2)
        }

        if let preferred = preferred {
            return DetectionResult(encoding: preferred, bomLength: 0)
        }

        // Tự dò: đọc mẫu 8KB để thử UTF-8
        try? handle.seek(toOffset: 0)
        let sampleData = (try? handle.read(upToCount: 8192)) ?? Data()
        if sampleData.isEmpty {
            return DetectionResult(encoding: .utf8, bomLength: 0)
        }
        // Mẫu có thể cắt giữa một ký tự nhiều byte: chỉ xét phần ký tự đủ (lỗi T096).
        if String(data: sampleData.prefix(utf8CompleteLength(sampleData)), encoding: .utf8) != nil {
            return DetectionResult(encoding: .utf8, bomLength: 0)
        } else {
            return DetectionResult(encoding: .windowsCP1252, bomLength: 0)
        }
    }

    /// [SUY ĐOÁN] Tự dò dấu phân cách trong {",", ";", "\t", "|"}
    static func detectDelimiter(url: URL, encoding: String.Encoding, bomLength: Int) throws -> Character {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ","
        }
        defer { try? handle.close() }

        try? handle.seek(toOffset: UInt64(bomLength))
        let sampleData = (try? handle.read(upToCount: 8192)) ?? Data()
        guard let sampleText = String(data: sampleData, encoding: encoding), !sampleText.isEmpty else {
            return ","
        }

        let candidates: [Character] = [",", ";", "\t", "|"]
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0, "|": 0]

        // Đếm ký tự nằm ngoài ngoặc kép
        var inQuotes = false
        var sampleChars = 0
        for char in sampleText {
            if char == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if counts[char] != nil {
                    counts[char]! += 1
                }
            }
            sampleChars += 1
            if sampleChars >= 4096 { break }
        }

        var bestDelimiter: Character = ","
        var maxCount = 0
        for cand in candidates {
            if let c = counts[cand], c > maxCount {
                maxCount = c
                bestDelimiter = cand
            }
        }
        return bestDelimiter
    }

    /// Đọc các hàng CSV theo luồng.
    /// Trả về mảng các dòng (mỗi dòng là mảng các ô `String?`, trong đó ô trống unquoted là `nil`, quoted "" là `""`).
    static func readRows(
        url: URL,
        delimiter: Character,
        encoding: String.Encoding,
        bomLength: Int,
        limit: Int?,
        progress: SourceProgress?,
        chunkSize: Int = 65536
    ) async throws -> [[String?]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw SourceError.unreadable(lt("Không thể đọc file: \(url.lastPathComponent)", "Couldn't read the file: \(url.lastPathComponent)"))
        }
        defer { try? handle.close() }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if fileSize == 0 {
            throw SourceError.empty
        }

        try? handle.seek(toOffset: UInt64(bomLength))
        var totalBytesRead: Int64 = Int64(bomLength)
        progress?(0.0)

        var rows: [[String?]] = []
        var currentRow: [String?] = []
        var currentField = ""
        var isQuoted = false
        var inQuotes = false
        var hasSeenCharInField = false

        var leftoverData = Data()

        func finishField() {
            if isQuoted {
                currentRow.append(currentField)
            } else if hasSeenCharInField {
                currentRow.append(currentField)
            } else {
                currentRow.append(nil)
            }
            currentField = ""
            isQuoted = false
            hasSeenCharInField = false
        }

        func finishRow() {
            finishField()
            // Bỏ qua dòng trống cuối cùng nếu không có ô nào được điền
            if currentRow.count == 1 && currentRow[0] == nil {
                currentRow = []
                return
            }
            rows.append(currentRow)
            currentRow = []
        }

        // Trạng thái giữ qua các khối (lỗi T096: `""` và CR LF rơi đúng ranh giới khối).
        var quotePending = false   // trong ngoặc kép, vừa gặp `"`: ký tự sau quyết định là `""` hay đóng ngoặc
        var skipNextIfLF = false

        /// Xử lý một ký tự; trả `true` khi đủ `limit` dòng.
        func consume(_ c: Character) -> Bool {
            if skipNextIfLF {
                skipNextIfLF = false
                if c == "\n" { return false }
            }
            if quotePending {
                quotePending = false
                if c == "\"" {
                    currentField.append("\"")
                    return false
                }
                inQuotes = false
            }
            if inQuotes {
                if c == "\"" { quotePending = true } else { currentField.append(c) }
                return false
            }
            if c == "\"" {
                isQuoted = true
                inQuotes = true
            } else if c == delimiter {
                finishField()
            } else if c == "\r\n" || c == "\n" || c == "\r" {
                if c == "\r" { skipNextIfLF = true }
                finishRow()
                if let limit, rows.count >= limit { return true }
            } else {
                hasSeenCharInField = true
                currentField.append(c)
            }
            return false
        }

        var reachedLimit = false
        while !reachedLimit {
            if Task.isCancelled {
                throw SourceError.cancelled
            }
            let nextChunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
            let atEnd = nextChunk.isEmpty
            totalBytesRead += Int64(nextChunk.count)
            if fileSize > 0, !atEnd {
                progress?(min(0.99, Double(totalBytesRead) / Double(fileSize)))
            }
            var data = leftoverData
            data.append(nextChunk)
            let (text, used) = decode(data, encoding: encoding, final: atEnd)
            leftoverData = Data(data.dropFirst(used))
            for c in text where consume(c) {
                reachedLimit = true
                break
            }
            if atEnd { break }
        }

        // Kết thúc ô / dòng cuối nếu có
        if hasSeenCharInField || isQuoted || !currentRow.isEmpty {
            finishRow()
        }

        progress?(1.0)
        return rows
    }

    /// Số byte đầu của `data` gồm các ký tự UTF-8 đủ: bỏ chuỗi byte còn dở ở cuối (tối đa 3 byte).
    static func utf8CompleteLength(_ data: Data) -> Int {
        let bytes = [UInt8](data.suffix(4))
        let base = data.count - bytes.count
        for back in 1...max(bytes.count, 1) where back <= bytes.count {
            let b = bytes[bytes.count - back]
            if b & 0xC0 == 0x80 { continue }            // byte nối, lùi tiếp
            let need = b & 0x80 == 0 ? 1 : b & 0xE0 == 0xC0 ? 2 : b & 0xF0 == 0xE0 ? 3 : b & 0xF8 == 0xF0 ? 4 : 1
            return back < need ? base + bytes.count - back : data.count
        }
        return data.count
    }

    /// Giải mã phần đủ ký tự của `data`; trả chữ và số byte đã dùng. Byte hỏng thành U+FFFD (không bỏ phần sau, lỗi T096).
    /// `final`: cuối tệp, giải mã hết.
    static func decode(_ data: Data, encoding: String.Encoding, final: Bool) -> (String, Int) {
        switch encoding {
        case .utf8:
            let used = final ? data.count : utf8CompleteLength(data)
            return (String(decoding: data.prefix(used), as: UTF8.self), used)
        case .utf16LittleEndian, .utf16BigEndian, .utf16:
            var used = data.count & ~1
            let big = encoding == .utf16BigEndian
            func unit(_ i: Int) -> UInt16 {
                let a = UInt16(data[data.startIndex + i]), b = UInt16(data[data.startIndex + i + 1])
                return big ? a << 8 | b : b << 8 | a
            }
            if !final, used >= 2, (0xD800...0xDBFF).contains(unit(used - 2)) { used -= 2 }   // cặp surrogate dở
            let units = stride(from: 0, to: used, by: 2).map(unit)
            return (String(decoding: units, as: UTF16.self), final ? data.count : used)
        default:
            let text = String(data: data, encoding: encoding) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return (text, data.count)
        }
    }
}
