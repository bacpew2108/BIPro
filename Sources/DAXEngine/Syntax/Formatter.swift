// Wave 4C (T002): Bộ định dạng DAX thuần Swift bảo toàn tuyệt đối chuỗi literal "...",
// tên bảng '...', ngoặc vuông [...] và chú thích (--, //, /* */).
import Foundation

extension DAXEngine {
    /// Định dạng văn bản DAX theo khuôn chuẩn Power BI (thụt lề 4 khoảng trắng cho khối
    /// DEFINE / MEASURE / VAR / RETURN / EVALUATE / ORDER BY và lời gọi hàm lồng nhiều đối số).
    public static func format(_ text: String) -> String {
        DAXFormatter.format(text)
    }
}

private enum DAXFormatter {
    private enum Piece {
        case comment(String, isLine: Bool)
        case word(String)
        case quoted(String)
        case bracket(String)
        case string(String)
        case number(String)
        case symbol(String)
    }

    private static let blockStarters: Set<String> = [
        "DEFINE", "EVALUATE", "ORDER", "START",
    ]
    private static let indentedStarters: Set<String> = [
        "MEASURE", "VAR", "RETURN", "TABLE", "COLUMN",
    ]
    private static let binaryOps: Set<String> = [
        "=", "==", "<>", "<=", ">=", "<", ">", "&&", "||", "+", "-", "*", "/", "^", "&",
    ]
    private static let multiLineFunctions: Set<String> = [
        "CALCULATE", "CALCULATETABLE", "SUMMARIZECOLUMNS", "SUMMARIZE", "ADDCOLUMNS",
        "SELECTCOLUMNS", "FILTER", "IF", "SWITCH", "SUMX", "AVERAGEX", "MINX", "MAXX",
        "COUNTX", "COUNTAX", "RANKX", "TOPN", "WINDOW", "OFFSET", "INDEX", "GENERATE",
        "GENERATEALL", "DATATABLE", "UNION", "INTERSECT", "EXCEPT",
    ]

    static func format(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let pieces = scan(normalized)
        guard !pieces.isEmpty else { return input }

        var out = ""
        var indent = 0
        var inDefine = false
        var parenStack: [(multiline: Bool, baseIndent: Int)] = []
        var prev: Piece? = nil
        var prevWasUnaryMinus = false

        func pad(_ level: Int) -> String { String(repeating: "    ", count: max(0, level)) }
        func appendNewline(_ level: Int) {
            while out.last == " " { out.removeLast() }
            if !out.isEmpty, out.last != "\n" { out.append("\n") }
            out.append(pad(level))
        }
        func needsSpaceBefore(_ next: Piece, after prev: Piece?) -> Bool {
            guard let prev else { return false }
            if prevWasUnaryMinus { return false }
            if out.isEmpty || out.last == "\n" || out.last == " " { return false }
            switch (prev, next) {
            case (.symbol("("), _), (_, .symbol(")")), (_, .symbol(",")), (_, .symbol(";")),
                 (.symbol("{"), _), (_, .symbol("}")), (.symbol("!"), _):
                return false
            case (.word, .symbol("(")):
                return false
            case (.word, .bracket), (.quoted, .bracket):
                return false
            case (.symbol("."), _), (_, .symbol(".")):
                return false
            default:
                return true
            }
        }

        var i = 0
        while i < pieces.count {
            let p = pieces[i]
            let next: Piece? = i + 1 < pieces.count ? pieces[i + 1] : nil
            switch p {
            case .comment(let raw, let isLine):
                if isLine {
                    if !out.isEmpty, out.last != "\n" { out.append(" ") }
                    out.append(raw)
                    appendNewline(indent)
                } else {
                    if needsSpaceBefore(p, after: prev) { out.append(" ") }
                    out.append(raw)
                }
                prev = p

            case .word(let w):
                let upper = w.uppercased()
                if parenStack.isEmpty && blockStarters.contains(upper) {
                    if upper == "ORDER", case .word(let n) = next, n.uppercased() == "BY" {
                        if !out.isEmpty { appendNewline(0) }
                        out.append("ORDER BY")
                        indent = 1
                        appendNewline(indent)
                        prev = .word("BY")
                        i += 2
                        continue
                    }
                    if upper == "START", case .word(let n) = next, n.uppercased() == "AT" {
                        if !out.isEmpty { appendNewline(0) }
                        out.append("START AT")
                        indent = 1
                        appendNewline(indent)
                        prev = .word("AT")
                        i += 2
                        continue
                    }
                    if upper == "DEFINE" {
                        inDefine = true
                        indent = 0
                        if !out.isEmpty { appendNewline(0) }
                        out.append("DEFINE")
                        prev = p
                        i += 1
                        continue
                    }
                    if upper == "EVALUATE" {
                        inDefine = false
                        indent = 0
                        if !out.isEmpty {
                            while out.last == " " { out.removeLast() }
                            if !out.hasSuffix("\n\n") {
                                out.append(out.last == "\n" ? "\n" : "\n\n")
                            }
                        }
                        out.append("EVALUATE")
                        indent = 1
                        appendNewline(indent)
                        prev = p
                        i += 1
                        continue
                    }
                }
                if parenStack.isEmpty && indentedStarters.contains(upper) {
                    let base = inDefine ? 1 : 0
                    if upper == "MEASURE" || upper == "TABLE" || upper == "COLUMN" {
                        indent = base
                        appendNewline(indent)
                        out.append(upper)
                        prev = p
                        i += 1
                        continue
                    }
                    if upper == "VAR" || upper == "RETURN" {
                        let varLevel = inDefine ? 2 : 0
                        indent = varLevel
                        appendNewline(indent)
                        out.append(upper)
                        prev = p
                        i += 1
                        continue
                    }
                }
                if needsSpaceBefore(p, after: prev) { out.append(" ") }
                out.append(w)
                prev = p

            case .symbol("("):
                var makeMultiline = false
                if case .word(let fn) = prev, multiLineFunctions.contains(fn.uppercased()) {
                    makeMultiline = hasMultipleArgsOrNested(pieces: pieces, openIndex: i)
                }
                out.append("(")
                let base = indent
                parenStack.append((multiline: makeMultiline, baseIndent: base))
                if makeMultiline {
                    indent = base + 1
                    appendNewline(indent)
                }
                prev = p

            case .symbol(")"):
                if let top = parenStack.popLast() {
                    indent = top.baseIndent
                    if top.multiline {
                        appendNewline(indent)
                    }
                }
                out.append(")")
                prev = p

            case .symbol(","):
                out.append(",")
                if let top = parenStack.last, top.multiline {
                    appendNewline(indent)
                } else {
                    out.append(" ")
                }
                prev = p

            case .symbol(let s):
                if binaryOps.contains(s) {
                    // Toán tử đơn ngôi `-` sau `(`, `,`, toán tử khác không thêm khoảng trắng sau nó
                    let isUnaryMinus = s == "-" && isUnaryContext(prev)
                    if isUnaryMinus {
                        if needsSpaceBefore(p, after: prev) { out.append(" ") }
                        out.append("-")
                        prevWasUnaryMinus = true
                    } else {
                        prevWasUnaryMinus = false
                        if !out.isEmpty, out.last != " ", out.last != "\n" { out.append(" ") }
                        out.append(s)
                        out.append(" ")
                    }
                } else {
                    prevWasUnaryMinus = false
                    if needsSpaceBefore(p, after: prev) { out.append(" ") }
                    out.append(s)
                }
                prev = p

            case .quoted(let raw), .bracket(let raw), .string(let raw), .number(let raw):
                if needsSpaceBefore(p, after: prev) { out.append(" ") }
                prevWasUnaryMinus = false
                out.append(raw)
                prev = p
            }
            i += 1
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func isUnaryContext(_ prev: Piece?) -> Bool {
        guard let prev else { return true }
        switch prev {
        case .symbol(let s) where s != ")" && s != "}": return true
        case .word(let w) where ["RETURN", "EVALUATE", "IN", "NOT", "AND", "OR"].contains(w.uppercased()): return true
        default: return false
        }
    }

    private static func hasMultipleArgsOrNested(pieces: [Piece], openIndex: Int) -> Bool {
        var depth = 0
        var commas = 0
        var nestedParen = false
        var j = openIndex
        while j < pieces.count {
            if case .symbol(let s) = pieces[j] {
                if s == "(" {
                    depth += 1
                    if depth >= 2 { nestedParen = true }
                } else if s == ")" {
                    depth -= 1
                    if depth == 0 { break }
                } else if s == "," && depth == 1 {
                    commas += 1
                }
            }
            j += 1
        }
        return commas >= 1 || nestedParen
    }

    private static func scan(_ text: String) -> [Piece] {
        let chars = Array(text)
        var i = 0
        var out: [Piece] = []
        let twoChar: Set<String> = ["==", "<>", "<=", ">=", "&&", "||"]

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            // Line comments: -- or //
            if (c == "-" && i + 1 < chars.count && chars[i + 1] == "-")
                || (c == "/" && i + 1 < chars.count && chars[i + 1] == "/") {
                let start = i
                while i < chars.count && chars[i] != "\n" { i += 1 }
                out.append(.comment(String(chars[start..<i]), isLine: true))
                continue
            }
            // Block comment: /* ... */
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(chars.count, i + 2)
                out.append(.comment(String(chars[start..<i]), isLine: false))
                continue
            }
            // String literal "..." (with "" escape)
            if c == "\"" {
                let start = i
                i += 1
                while i < chars.count {
                    if chars[i] == "\"" {
                        if i + 1 < chars.count && chars[i + 1] == "\"" { i += 2; continue }
                        i += 1
                        break
                    }
                    i += 1
                }
                out.append(.string(String(chars[start..<i])))
                continue
            }
            // Single-quoted table '...' (with '' escape)
            if c == "'" {
                let start = i
                i += 1
                while i < chars.count {
                    if chars[i] == "'" {
                        if i + 1 < chars.count && chars[i + 1] == "'" { i += 2; continue }
                        i += 1
                        break
                    }
                    i += 1
                }
                out.append(.quoted(String(chars[start..<i])))
                continue
            }
            // Bracket [...] (with ]] escape)
            if c == "[" {
                let start = i
                i += 1
                while i < chars.count {
                    if chars[i] == "]" {
                        if i + 1 < chars.count && chars[i + 1] == "]" { i += 2; continue }
                        i += 1
                        break
                    }
                    i += 1
                }
                out.append(.bracket(String(chars[start..<i])))
                continue
            }
            // Number
            if c.isNumber {
                let start = i
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") { i += 1 }
                if i < chars.count && (chars[i] == "e" || chars[i] == "E") {
                    i += 1
                    if i < chars.count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
                    while i < chars.count && chars[i].isNumber { i += 1 }
                }
                out.append(.number(String(chars[start..<i])))
                continue
            }
            // Identifier / keyword (including dotted like STDEV.S / VAR.S)
            if c.isLetter || c == "_" {
                let start = i
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == ".") { i += 1 }
                out.append(.word(String(chars[start..<i])))
                continue
            }
            // Two-char operator
            if i + 1 < chars.count {
                let pair = String([c, chars[i + 1]])
                if twoChar.contains(pair) {
                    out.append(.symbol(pair))
                    i += 2
                    continue
                }
            }
            out.append(.symbol(String(c)))
            i += 1
        }
        return out
    }
}
