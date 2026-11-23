// Phase F (T048): bộ tách từ của ngôn ngữ M.
import PBIXKit
import Foundation

enum MTokenKind: Equatable {
    case identifier(String)      // đã bỏ #"…", có thể chứa dấu chấm (Table.SelectRows)
    case quotedIdentifier(String)
    case keyword(String)         // and as each else error false if in is let meta not null or otherwise then true try type, #table, #date, ...
    case number(Double)
    case text(String)
    case symbol(String)          // ( ) [ ] { } , = <> < > <= >= + - * / & => .. ... ? @ !
    case eof
}

struct MToken {
    let kind: MTokenKind
    let line: Int
    let column: Int
    /// Vị trí (chỉ số scalar) trong nguồn, để cắt nguyên văn tên có khoảng trắng như `[Order Date]`.
    let start: Int
    let end: Int
}

enum MLexer {
    static let keywords: Set<String> = [
        "and", "as", "each", "else", "error", "false", "if", "in", "is", "let", "meta", "not", "null", "or",
        "otherwise", "section", "shared", "then", "true", "try", "type",
        "#binary", "#date", "#datetime", "#datetimezone", "#duration", "#infinity", "#nan", "#sections", "#shared", "#table", "#time",
    ]

    static func tokenize(_ source: String) throws -> [MToken] {
        let chars = Array(source.unicodeScalars)
        var tokens: [MToken] = []
        var i = 0, line = 1, lineStart = 0

        func fail(_ message: String, at index: Int) -> MSyntaxError {
            MSyntaxError(line: line, column: index - lineStart + 1, message: message)
        }
        func isLetter(_ c: Unicode.Scalar) -> Bool { c == "_" || c.properties.isAlphabetic }
        func isDigit(_ c: Unicode.Scalar) -> Bool { c.value >= 48 && c.value <= 57 }
        func isHex(_ c: Unicode.Scalar) -> Bool { isDigit(c) || (c.value >= 65 && c.value <= 70) || (c.value >= 97 && c.value <= 102) }

        /// Đọc chuỗi trong ngoặc kép từ `i` (đang ở dấu `"`); xử lý `""` và `#(…)`.
        func readText() throws -> String {
            let begin = i
            i += 1
            var out = String.UnicodeScalarView()
            while true {
                guard i < chars.count else { throw fail(lt("Chuỗi chưa đóng ngoặc kép", "The string has no closing quote"), at: begin) }
                let c = chars[i]
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { out.append("\""); i += 2; continue }
                    i += 1
                    return String(out)
                }
                if c == "#", i + 1 < chars.count, chars[i + 1] == "(" {
                    var j = i + 2
                    var body = ""
                    while j < chars.count, chars[j] != ")" { body.unicodeScalars.append(chars[j]); j += 1 }
                    guard j < chars.count else { throw fail(lt("Chuỗi thoát #( chưa đóng", "The #( escape sequence isn't closed"), at: i) }
                    for part in body.split(separator: ",") {
                        let name = part.trimmingCharacters(in: .whitespaces)
                        switch name {
                        case "lf": out.append("\n")
                        case "cr": out.append("\r")
                        case "tab": out.append("\t")
                        case "#": out.append("#")
                        default:
                            guard let value = UInt32(name, radix: 16), let scalar = Unicode.Scalar(value) else {
                                throw fail(lt("Chuỗi thoát không hợp lệ: #(\(name))", "Invalid escape sequence: #(\(name))"), at: i)
                            }
                            out.append(scalar)
                        }
                    }
                    i = j + 1
                    continue
                }
                if c == "\n" { line += 1; lineStart = i + 1 }
                out.append(c)
                i += 1
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" { line += 1; i += 1; lineStart = i; continue }
            if c == " " || c == "\t" || c == "\r" || c.properties.isWhitespace { i += 1; continue }
            // Chú thích
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                let begin = i
                i += 2
                while true {
                    guard i + 1 < chars.count else { throw fail(lt("Chú thích /* chưa đóng", "The /* comment isn't closed"), at: begin) }
                    if chars[i] == "*", chars[i + 1] == "/" { i += 2; break }
                    if chars[i] == "\n" { line += 1; lineStart = i + 1 }
                    i += 1
                }
                continue
            }
            let start = i, column = i - lineStart + 1, tokenLine = line
            func add(_ kind: MTokenKind) { tokens.append(MToken(kind: kind, line: tokenLine, column: column, start: start, end: i)) }

            if c == "\"" { let text = try readText(); add(.text(text)); continue }
            if c == "#" {
                if i + 1 < chars.count, chars[i + 1] == "\"" {
                    i += 1
                    let name = try readText()
                    add(.quotedIdentifier(name))
                    continue
                }
                var j = i + 1
                while j < chars.count, isLetter(chars[j]) { j += 1 }
                let word = "#" + String(String.UnicodeScalarView(chars[(i + 1)..<j]))
                guard keywords.contains(word) else { throw fail(lt("Từ khoá không hợp lệ: \(word)", "Invalid keyword: \(word)"), at: i) }
                i = j
                if word == "#nan" { add(.number(.nan)) } else if word == "#infinity" { add(.number(.infinity)) } else { add(.keyword(word)) }
                continue
            }
            if isLetter(c) {
                var j = i + 1
                while j < chars.count {
                    if isLetter(chars[j]) || isDigit(chars[j]) { j += 1; continue }
                    // dấu chấm nối các phần của tên (List.Sum), nhưng không phải `..` hay `...`
                    if chars[j] == ".", j + 1 < chars.count, isLetter(chars[j + 1]) { j += 1; continue }
                    break
                }
                let word = String(String.UnicodeScalarView(chars[i..<j]))
                i = j
                add(keywords.contains(word) ? .keyword(word) : .identifier(word))
                continue
            }
            if isDigit(c) || (c == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var j = i
                if c == "0", j + 1 < chars.count, chars[j + 1] == "x" || chars[j + 1] == "X" {
                    j += 2
                    let digitsStart = j
                    while j < chars.count, isHex(chars[j]) { j += 1 }
                    guard j > digitsStart, let value = UInt64(String(String.UnicodeScalarView(chars[digitsStart..<j])), radix: 16) else {
                        throw fail(lt("Số thập lục phân không hợp lệ", "Invalid hexadecimal number"), at: i)
                    }
                    i = j
                    add(.number(Double(value)))
                    continue
                }
                while j < chars.count, isDigit(chars[j]) { j += 1 }
                if j < chars.count, chars[j] == ".", j + 1 < chars.count, isDigit(chars[j + 1]) {
                    j += 1
                    while j < chars.count, isDigit(chars[j]) { j += 1 }
                }
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                    if k < chars.count, isDigit(chars[k]) {
                        while k < chars.count, isDigit(chars[k]) { k += 1 }
                        j = k
                    }
                }
                guard let value = Double(String(String.UnicodeScalarView(chars[i..<j]))) else { throw fail(lt("Số không hợp lệ", "Invalid number"), at: i) }
                i = j
                add(.number(value))
                continue
            }
            // Ký hiệu nhiều ký tự trước
            let three = i + 2 < chars.count ? String(String.UnicodeScalarView(chars[i...(i + 2)])) : ""
            let two = i + 1 < chars.count ? String(String.UnicodeScalarView(chars[i...(i + 1)])) : ""
            if three == "..." { i += 3; add(.symbol("...")); continue }
            if ["=>", "<>", "<=", ">=", ".."].contains(two) { i += 2; add(.symbol(two)); continue }
            if "()[]{},=<>+-*/&?@!".unicodeScalars.contains(c) { i += 1; add(.symbol(String(c))); continue }
            throw fail(lt("Ký tự không hợp lệ: \(c)", "Invalid character: \(c)"), at: i)
        }
        tokens.append(MToken(kind: .eof, line: line, column: i - lineStart + 1, start: chars.count, end: chars.count))
        return tokens
    }
}
