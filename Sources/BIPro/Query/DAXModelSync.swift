// Wave 4C (T011): Phân tích các khối `DEFINE MEASURE Table[Name] = <expr>` từ DAX Query View
// để cập nhật trực tiếp vào mô hình (Update model) trong 1 bước hoàn tác ⌘Z.
import Foundation
import PBIXKit

struct DAXDefinedMeasure: Identifiable, Equatable, Sendable {
    enum ChangeKind: Equatable, Sendable {
        case create
        case update(oldExpression: String)
    }

    var id: String { "\(table)[\(name)]" }
    let table: String
    let name: String
    let expression: String
    let kind: ChangeKind
}

enum DAXModelSync {
    /// Trích tất cả định nghĩa `MEASURE Table[Name] = <expression>` nằm trong khối `DEFINE` của kịch bản DAX.
    static func extractMeasures(from script: String, existingModel: ModelMetadata) -> [DAXDefinedMeasure] {
        let normalized = script.replacingOccurrences(of: "\r\n", with: "\n")
        // Tìm khối trước `EVALUATE` (nếu có) và sau `DEFINE`
        let upperChars = Array(normalized.uppercased())
        let rawChars = Array(normalized)
        let n = rawChars.count

        // Quét theo ranh giới không nằm trong chuỗi "...", nháy '...', ngoặc [...], hay comment
        var keywordPositions: [(word: String, start: Int, end: Int)] = []
        var i = 0
        var parenDepth = 0
        while i < n {
            let c = rawChars[i]
            if (c == "-" && i + 1 < n && rawChars[i + 1] == "-") || (c == "/" && i + 1 < n && rawChars[i + 1] == "/") {
                while i < n && rawChars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/" && i + 1 < n && rawChars[i + 1] == "*" {
                i += 2
                while i + 1 < n && !(rawChars[i] == "*" && rawChars[i + 1] == "/") { i += 1 }
                i = min(n, i + 2)
                continue
            }
            if c == "\"" {
                i += 1
                while i < n {
                    if rawChars[i] == "\"" {
                        if i + 1 < n && rawChars[i + 1] == "\"" { i += 2; continue }
                        i += 1; break
                    }
                    i += 1
                }
                continue
            }
            if c == "'" {
                i += 1
                while i < n {
                    if rawChars[i] == "'" {
                        if i + 1 < n && rawChars[i + 1] == "'" { i += 2; continue }
                        i += 1; break
                    }
                    i += 1
                }
                continue
            }
            if c == "[" {
                i += 1
                while i < n {
                    if rawChars[i] == "]" {
                        if i + 1 < n && rawChars[i + 1] == "]" { i += 2; continue }
                        i += 1; break
                    }
                    i += 1
                }
                continue
            }
            if c == "(" { parenDepth += 1; i += 1; continue }
            if c == ")" { parenDepth = max(0, parenDepth - 1); i += 1; continue }
            if parenDepth == 0 && (c.isLetter || c == "_") {
                let start = i
                while i < n && (rawChars[i].isLetter || rawChars[i].isNumber || rawChars[i] == "_") { i += 1 }
                let word = String(upperChars[start..<i])
                if ["DEFINE", "MEASURE", "EVALUATE", "TABLE", "COLUMN"].contains(word) {
                    keywordPositions.append((word, start, i))
                }
                continue
            }
            i += 1
        }

        guard let defineIdx = keywordPositions.firstIndex(where: { $0.word == "DEFINE" }) else { return [] }
        var results: [DAXDefinedMeasure] = []

        for kIdx in (defineIdx + 1)..<keywordPositions.count {
            let kw = keywordPositions[kIdx]
            if kw.word == "EVALUATE" { break }
            guard kw.word == "MEASURE" else { continue }
            let bodyEnd = (kIdx + 1 < keywordPositions.count) ? keywordPositions[kIdx + 1].start : n
            let slice = String(rawChars[kw.end..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = parseMeasureHeaderAndBody(slice) else { continue }
            guard let tableMatch = existingModel.userTables.first(where: { $0.name.caseInsensitiveCompare(parsed.table) == .orderedSame }) else {
                continue
            }
            let existing = existingModel.measures.first {
                $0.tableName.caseInsensitiveCompare(tableMatch.name) == .orderedSame
                    && $0.name.caseInsensitiveCompare(parsed.name) == .orderedSame
            }
            if let existing {
                if existing.expression.trimmingCharacters(in: .whitespacesAndNewlines) != parsed.expression {
                    results.append(DAXDefinedMeasure(table: tableMatch.name, name: existing.name,
                                                     expression: parsed.expression, kind: .update(oldExpression: existing.expression)))
                }
            } else {
                results.append(DAXDefinedMeasure(table: tableMatch.name, name: parsed.name,
                                                 expression: parsed.expression, kind: .create))
            }
        }
        return results
    }

    private static func parseMeasureHeaderAndBody(_ text: String) -> (table: String, name: String, expression: String)? {
        let chars = Array(text)
        var i = 0
        while i < chars.count && chars[i].isWhitespace { i += 1 }
        guard i < chars.count else { return nil }

        let tableName: String
        if chars[i] == "'" {
            i += 1
            var buf = ""
            while i < chars.count {
                if chars[i] == "'" {
                    if i + 1 < chars.count && chars[i + 1] == "'" { buf.append("'"); i += 2; continue }
                    i += 1; break
                }
                buf.append(chars[i]); i += 1
            }
            tableName = buf
        } else {
            let start = i
            while i < chars.count && chars[i] != "[" && !chars[i].isWhitespace { i += 1 }
            tableName = String(chars[start..<i])
        }
        while i < chars.count && chars[i].isWhitespace { i += 1 }
        guard i < chars.count && chars[i] == "[" else { return nil }
        i += 1
        var measureName = ""
        while i < chars.count {
            if chars[i] == "]" {
                if i + 1 < chars.count && chars[i + 1] == "]" { measureName.append("]"); i += 2; continue }
                i += 1; break
            }
            measureName.append(chars[i]); i += 1
        }
        while i < chars.count && chars[i].isWhitespace { i += 1 }
        guard i < chars.count && chars[i] == "=" else { return nil }
        i += 1
        let expr = String(chars[i...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tableName.isEmpty, !measureName.isEmpty, !expr.isEmpty else { return nil }
        return (tableName, measureName, expr)
    }
}
