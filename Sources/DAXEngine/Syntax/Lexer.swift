// Lexer (LANG, đợt 1a). Chuyển văn bản DAX thành dãy token có vị trí (architecture.md §5.1).
//
// Quy ước vị trí:
// - `start` và `end` là offset UTF-16 của văn bản (khớp với NSTextView).
// - `line` và `column` đếm từ 1. `column` là số đơn vị UTF-16 từ đầu dòng, cộng 1.
// - Tab được tính là ĐÚNG 1 cột (không mở rộng theo bội số 4 hay 8). Đây là quy ước của đề bài đợt 1a.
//   Chưa đối chiếu với vị trí Power BI báo lỗi: thư mục observe/ chưa có file .error.txt (xem O3d).
// - `\r` là khoảng trắng; `\n` xuống dòng.
// - Token EOF đặt ngay sau token thật cuối cùng (bỏ qua khoảng trắng và chú thích). Nhờ vậy lỗi
//   "thiếu ')'" trỏ vào đúng chỗ còn thiếu, không trỏ xuống dòng trống cuối văn bản.

/// Một token của DAX.
struct DAXToken: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        /// Số. `isInteger` là false khi có dấu thập phân hoặc số mũ (1e6 là số thực).
        case number(Double, isInteger: Bool)
        /// Chuỗi "...". `""` đã đổi thành `"`.
        case string(String)
        /// Tên trong nháy đơn 'Tên bảng'. `''` đã đổi thành `'`.
        case quoted(String)
        /// Tên trong ngoặc vuông [cột]. `]]` đã đổi thành `]`. Cột ảo có dạng [@c].
        case bracket(String)
        /// Từ trần: tên bảng, hàm, VAR, từ khoá (DESC, NOT, IN…). Từ khoá do parser nhận diện.
        case identifier(String)
        /// Toán tử và dấu câu: + - * / ^ & = == <> < > <= >= && || ! ( ) { } , ;
        case symbol(String)
        /// Kết thúc văn bản.
        case eof
    }

    let kind: Kind
    let range: SourceRange
}

/// Lexer của DAX. Không giữ trạng thái giữa các lần gọi.
enum DAXLexer {
    /// Tách văn bản thành token. Luôn kết thúc bằng một token `.eof`.
    static func tokenize(_ text: String) throws(DAXError) -> [DAXToken] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var scanner = DAXScanner(scalars: Array(normalized.unicodeScalars))
        return try scanner.run()
    }
}

/// Bộ quét theo đơn vị Unicode scalar, nhưng đếm offset và cột theo UTF-16.
private struct DAXScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    /// Offset UTF-16 của vị trí hiện tại.
    private var offset = 0
    private var line = 1
    /// Offset UTF-16 của đầu dòng hiện tại.
    private var lineStart = 0
    /// Vị trí cuối của token thật gần nhất (dùng cho token EOF).
    private var lastEnd = (offset: 0, line: 1, column: 1)
    private var tokens: [DAXToken] = []

    private static let twoCharSymbols: Set<String> = ["==", "<>", "<=", ">=", "&&", "||"]
    private static let oneCharSymbols: Set<Unicode.Scalar> = [
        "+", "-", "*", "/", "^", "&", "=", "<", ">", "!", "(", ")", "{", "}", ",", ";",
    ]

    init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    private var atEnd: Bool { index >= scalars.count }

    private var currentColumn: Int { offset - lineStart + 1 }

    private func peek(_ k: Int = 0) -> Unicode.Scalar? {
        let j = index + k
        return j < scalars.count ? scalars[j] : nil
    }

    /// Đi qua một scalar và cập nhật offset, dòng, đầu dòng.
    private mutating func advance() {
        let s = scalars[index]
        offset += s.utf16.count
        if s == "\n" {
            line += 1
            lineStart = offset
        }
        index += 1
    }

    mutating func run() throws(DAXError) -> [DAXToken] {
        while true {
            try skipTrivia()
            if atEnd { break }
            try scanToken()
        }
        let eof = SourceRange(start: lastEnd.offset, end: lastEnd.offset,
                              line: lastEnd.line, column: lastEnd.column)
        tokens.append(DAXToken(kind: .eof, range: eof))
        return tokens
    }

    /// Bỏ qua khoảng trắng và chú thích: `//`, `--` đến cuối dòng, và `/* ... */`.
    private mutating func skipTrivia() throws(DAXError) {
        while let c = peek() {
            if (c == "/" && peek(1) == "/") || (c == "-" && peek(1) == "-") {
                while let d = peek(), d != "\n" { advance() }
                continue
            }
            if c == "/" && peek(1) == "*" {
                let start = startRange()
                advance()
                advance()
                var closed = false
                while !atEnd {
                    if peek() == "*" && peek(1) == "/" {
                        advance()
                        advance()
                        closed = true
                        break
                    }
                    advance()
                }
                if !closed {
                    throw DAXError(.syntax, "chú thích /* chưa được đóng", range: start)
                }
                continue
            }
            if isWhitespace(c) {
                advance()
                continue
            }
            break
        }
    }

    private mutating func scanToken() throws(DAXError) {
        let start = offset
        let line0 = line
        let column0 = currentColumn
        let begin = startRange()
        guard let c = peek() else { return }

        let kind: DAXToken.Kind
        if c == "\"" {
            kind = .string(try scanDelimited(close: "\"", opening: begin, what: "chuỗi"))
        } else if c == "'" {
            kind = .quoted(try scanDelimited(close: "'", opening: begin, what: "tên bảng trong nháy đơn"))
        } else if c == "[" {
            kind = .bracket(try scanDelimited(close: "]", opening: begin, what: "tên trong ngoặc vuông"))
        } else if isDigit(c) || (c == "." && peek(1).map(isDigit) == true) {
            kind = scanNumber()
        } else if isIdentifierStart(c) {
            kind = .identifier(scanIdentifier())
        } else if let symbol = scanSymbol() {
            kind = .symbol(symbol)
        } else {
            throw DAXError(.syntax, "ký tự không hợp lệ '\(String(c))'", range: begin)
        }

        let range = SourceRange(start: start, end: offset, line: line0, column: column0)
        tokens.append(DAXToken(kind: kind, range: range))
        lastEnd = (offset, line, currentColumn)
    }

    private func startRange() -> SourceRange {
        SourceRange(start: offset, end: offset, line: line, column: currentColumn)
    }

    /// Đọc chuỗi giữa hai dấu `close`. Lặp đôi `close` thì ra một ký tự `close`.
    /// Dùng cho "...", '...' và [...], đúng quy tắc escape của DAX.
    private mutating func scanDelimited(close: Unicode.Scalar, opening: SourceRange,
                                        what: String) throws(DAXError) -> String {
        advance()
        var out = String.UnicodeScalarView()
        while true {
            guard let c = peek() else {
                throw DAXError(.syntax, "\(what) chưa được đóng", range: opening)
            }
            if c == close {
                if peek(1) == close {
                    out.append(close)
                    advance()
                    advance()
                    continue
                }
                advance()
                break
            }
            out.append(c)
            advance()
        }
        return String(out)
    }

    /// Số: chữ số, phần thập phân (cần chữ số sau dấu chấm), số mũ e/E với dấu tuỳ chọn.
    private mutating func scanNumber() -> DAXToken.Kind {
        var text = ""
        var isInteger = true
        if peek() == "." {
            text.append("0")
        }
        while let c = peek(), isDigit(c) {
            text.unicodeScalars.append(c)
            advance()
        }
        if peek() == ".", let d = peek(1), isDigit(d) {
            isInteger = false
            text.append(".")
            advance()
            while let c = peek(), isDigit(c) {
                text.unicodeScalars.append(c)
                advance()
            }
        }
        if let e = peek(), e == "e" || e == "E" {
            let signed = peek(1) == "+" || peek(1) == "-"
            let digitAt = signed ? 2 : 1
            if let d = peek(digitAt), isDigit(d) {
                isInteger = false
                text.append("e")
                advance()
                if signed, let sign = peek() {
                    text.unicodeScalars.append(sign)
                    advance()
                }
                while let c = peek(), isDigit(c) {
                    text.unicodeScalars.append(c)
                    advance()
                }
            }
        }
        return .number(Double(text) ?? 0, isInteger: isInteger)
    }

    /// Định danh: chữ cái (kể cả tiếng Việt), chữ số, gạch dưới. Có thể có dấu chấm giữa hai phần
    /// (PERCENTILEX.INC). Dấu chấm chỉ được nối khi sau nó là chữ cái hoặc gạch dưới.
    private mutating func scanIdentifier() -> String {
        var out = String.UnicodeScalarView()
        while let c = peek() {
            if isIdentifierPart(c) {
                out.append(c)
                advance()
            } else if c == ".", let n = peek(1), isIdentifierStart(n) {
                out.append(c)
                advance()
            } else {
                break
            }
        }
        return String(out)
    }

    private mutating func scanSymbol() -> String? {
        if let c = peek(), let d = peek(1) {
            let pair = String(c) + String(d)
            if DAXScanner.twoCharSymbols.contains(pair) {
                advance()
                advance()
                return pair
            }
        }
        if let c = peek(), DAXScanner.oneCharSymbols.contains(c) {
            advance()
            return String(c)
        }
        return nil
    }

    private func isWhitespace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r" || c.properties.isWhitespace
    }

    private func isDigit(_ c: Unicode.Scalar) -> Bool {
        c.value >= 48 && c.value <= 57
    }

    private func isIdentifierStart(_ c: Unicode.Scalar) -> Bool {
        c == "_" || c.properties.isAlphabetic
    }

    private func isIdentifierPart(_ c: Unicode.Scalar) -> Bool {
        isIdentifierStart(c) || isDigit(c)
    }
}
