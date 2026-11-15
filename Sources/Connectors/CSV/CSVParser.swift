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
            throw SourceError.unreadable("Không thể mở file: \(url.lastPathComponent)")
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
        if String(data: sampleData, encoding: .utf8) != nil {
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
        progress: SourceProgress?
    ) async throws -> [[String?]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw SourceError.unreadable("Không thể đọc file: \(url.lastPathComponent)")
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

        let chunkSize = 65536
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

        while true {
            if Task.isCancelled {
                throw SourceError.cancelled
            }

            let nextChunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
            if nextChunk.isEmpty {
                break
            }
            totalBytesRead += Int64(nextChunk.count)
            if fileSize > 0 {
                let p = min(0.99, Double(totalBytesRead) / Double(fileSize))
                progress?(p)
            }

            var fullChunk = leftoverData
            fullChunk.append(nextChunk)

            // Tìm ranh giới giải mã hợp lệ cho chunk
            var text: String?
            var validLength = fullChunk.count
            while validLength > 0 {
                let sub = fullChunk.prefix(validLength)
                if let str = String(data: sub, encoding: encoding) {
                    text = str
                    break
                }
                validLength -= 1
            }

            if let text = text {
                leftoverData = fullChunk.dropFirst(validLength)
                var skipNextIfLF = false

                var i = text.startIndex
                while i < text.endIndex {
                    let c = text[i]

                    if skipNextIfLF {
                        skipNextIfLF = false
                        if c == "\n" {
                            i = text.index(after: i)
                            continue
                        }
                    }

                    if inQuotes {
                        if c == "\"" {
                            let nextIdx = text.index(after: i)
                            if nextIdx < text.endIndex && text[nextIdx] == "\"" {
                                currentField.append("\"")
                                i = nextIdx
                            } else {
                                inQuotes = false
                            }
                        } else {
                            currentField.append(c)
                        }
                    } else {
                        if c == "\"" {
                            isQuoted = true
                            inQuotes = true
                        } else if c == delimiter {
                            finishField()
                        } else if c == "\r\n" || c == "\n" || c == "\r" {
                            if c == "\r" {
                                let nextIdx = text.index(after: i)
                                if nextIdx == text.endIndex {
                                    skipNextIfLF = true
                                }
                            }
                            finishRow()
                            if let limit = limit, rows.count >= limit {
                                break
                            }
                        } else {
                            hasSeenCharInField = true
                            currentField.append(c)
                        }
                    }

                    i = text.index(after: i)
                }

                if let limit = limit, rows.count >= limit {
                    break
                }
            } else {
                leftoverData = fullChunk
                if nextChunk.count < chunkSize {
                    break
                }
            }
        }

        // Xử lý dữ liệu còn lại ở cuối file nếu chưa kết thúc bằng newline
        if !leftoverData.isEmpty {
            if let text = String(data: leftoverData, encoding: encoding) {
                for c in text {
                    if inQuotes {
                        if c == "\"" { inQuotes = false } else { currentField.append(c) }
                    } else {
                        if c == "\"" {
                            isQuoted = true
                            inQuotes = true
                        } else if c == delimiter {
                            finishField()
                        } else if c == "\r\n" || c == "\r" || c == "\n" {
                            finishRow()
                        } else {
                            hasSeenCharInField = true
                            currentField.append(c)
                        }
                    }
                }
            }
        }

        // Kết thúc ô / dòng cuối nếu có
        if hasSeenCharInField || isQuoted || !currentRow.isEmpty {
            finishRow()
        }

        progress?(1.0)
        return rows
    }
}
