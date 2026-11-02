import Foundation
import PBIXKit

/// Tra cứu measure khi rê chuột trong editor DAX theo quan sát Power BI (O14).
enum MeasureHover {
    /// Tìm measure tương ứng với token `[tên]` (có thể đi kèm tên bảng `'Bảng'[tên]` hoặc `Bảng[tên]`)
    /// chứa vị trí con trỏ `utf16Offset`.
    /// - Trả về measure nếu trùng tên (không phân biệt hoa thường) và đúng bảng (nếu có tên bảng).
    /// - Trả về nil nếu là cột (không thuộc measures), sai bảng, hoặc nằm trong chuỗi/comment.
    static func lookup(text: String, utf16Offset: Int, measures: [ModelMetadata.Measure]) -> ModelMetadata.Measure? {
        lookupToken(text: text, utf16Offset: utf16Offset, measures: measures)?.measure
    }

    /// Trả về measure và range UTF-16 đầy đủ của token (bao gồm cả tên bảng nếu có) để hiển thị tooltip.
    static func lookupToken(
        text: String,
        utf16Offset: Int,
        measures: [ModelMetadata.Measure]
    ) -> (measure: ModelMetadata.Measure, range: NSRange)? {
        let ns = text as NSString
        let length = ns.length
        guard length > 0, utf16Offset >= 0, utf16Offset < length else { return nil }

        // Bước 1: Đánh dấu các vùng chuỗi "..." và comment // hoặc --
        var isMasked = [Bool](repeating: false, count: length)
        var i = 0
        while i < length {
            let c = ns.character(at: i)
            if c == 34 { // "\"" (chuỗi)
                isMasked[i] = true
                i += 1
                while i < length {
                    let sc = ns.character(at: i)
                    isMasked[i] = true
                    if sc == 34 {
                        if i + 1 < length && ns.character(at: i + 1) == 34 {
                            // Escape quote ""
                            isMasked[i + 1] = true
                            i += 2
                            continue
                        } else {
                            i += 1
                            break
                        }
                    }
                    i += 1
                }
                continue
            }
            if i + 1 < length {
                let next = ns.character(at: i + 1)
                if (c == 47 && next == 47) || (c == 45 && next == 45) { // "//" hoặc "--" (comment dòng)
                    isMasked[i] = true
                    isMasked[i + 1] = true
                    i += 2
                    while i < length {
                        let cc = ns.character(at: i)
                        if cc == 10 { // "\n"
                            break
                        }
                        isMasked[i] = true
                        i += 1
                    }
                    continue
                }
            }
            i += 1
        }

        // Bỏ qua nếu con trỏ nằm trong chuỗi hoặc comment
        if isMasked[utf16Offset] { return nil }

        // Bước 2: Tìm token [tên] chứa utf16Offset
        let bracketStart: Int
        let bracketEnd: Int

        let currentChar = ns.character(at: utf16Offset)
        if currentChar == 93 { // "]"
            bracketEnd = utf16Offset
            var p = utf16Offset - 1
            var foundStart: Int? = nil
            while p >= 0 {
                let ch = ns.character(at: p)
                if ch == 10 || ch == 93 || isMasked[p] { break }
                if ch == 91 { // "["
                    foundStart = p
                    break
                }
                p -= 1
            }
            guard let s = foundStart else { return nil }
            bracketStart = s
        } else {
            var p = utf16Offset
            var foundStart: Int? = nil
            while p >= 0 {
                let ch = ns.character(at: p)
                if ch == 10 || isMasked[p] { break }
                if ch == 93 && p != utf16Offset { break }
                if ch == 91 { // "["
                    foundStart = p
                    break
                }
                p -= 1
            }
            guard let s = foundStart else { return nil }
            bracketStart = s

            var q = bracketStart + 1
            var foundEnd: Int? = nil
            while q < length {
                let ch = ns.character(at: q)
                if ch == 10 || ch == 91 || isMasked[q] { break }
                if ch == 93 { // "]"
                    foundEnd = q
                    break
                }
                q += 1
            }
            guard let e = foundEnd, utf16Offset <= e else { return nil }
            bracketEnd = e
        }

        guard bracketEnd > bracketStart + 1 else { return nil }
        let nameRange = NSRange(location: bracketStart + 1, length: bracketEnd - bracketStart - 1)
        let measureName = ns.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
        guard !measureName.isEmpty else { return nil }

        // Bước 3: Tìm tên bảng đứng ngay trước `[` nếu có
        var tableName: String? = nil
        var tokenFullStart = bracketStart

        if bracketStart > 0 {
            let prevChar = ns.character(at: bracketStart - 1)
            if prevChar == 39 { // "'" - Dạng 'Tên Bảng'[tên]
                var tp = bracketStart - 2
                var foundOpenQuote = false
                while tp >= 0 {
                    let tc = ns.character(at: tp)
                    if tc == 10 || isMasked[tp] { break }
                    if tc == 39 {
                        if tp > 0 && ns.character(at: tp - 1) == 39 {
                            tp -= 2
                            continue
                        } else {
                            foundOpenQuote = true
                            break
                        }
                    }
                    tp -= 1
                }
                if foundOpenQuote {
                    let rawTable = ns.substring(with: NSRange(location: tp + 1, length: bracketStart - 1 - tp - 1))
                    tableName = rawTable.replacingOccurrences(of: "''", with: "'")
                    tokenFullStart = tp
                }
            } else if isIdentifierChar(prevChar) { // Dạng Ten_Bang[tên]
                var tp = bracketStart - 1
                while tp >= 0 {
                    let tc = ns.character(at: tp)
                    if !isIdentifierChar(tc) { break }
                    tp -= 1
                }
                let idStart = tp + 1
                tableName = ns.substring(with: NSRange(location: idStart, length: bracketStart - idStart))
                tokenFullStart = idStart
            }
        }

        // Bước 4: So khớp với danh sách measures
        let fullRange = NSRange(location: tokenFullStart, length: bracketEnd - tokenFullStart + 1)
        if let tableName {
            guard let measure = measures.first(where: {
                $0.name.caseInsensitiveCompare(measureName) == .orderedSame &&
                $0.tableName.caseInsensitiveCompare(tableName) == .orderedSame
            }) else {
                return nil
            }
            return (measure, fullRange)
        } else {
            guard let measure = measures.first(where: {
                $0.name.caseInsensitiveCompare(measureName) == .orderedSame
            }) else {
                return nil
            }
            return (measure, fullRange)
        }
    }

    private static func isIdentifierChar(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
    }
}
