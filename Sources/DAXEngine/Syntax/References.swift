// Phase E (R6): tên mà một biểu thức DAX nhắc tới, đọc bằng lexer (không dùng regex để chuỗi và chú thích không bị tính).

/// Một chỗ biểu thức nhắc tới cột hoặc measure: `Bảng[Tên]` (có `table`) hoặc `[Tên]` (không có).
public struct DAXNameReference: Sendable, Hashable {
    public let table: String?
    public let name: String

    public init(table: String?, name: String) {
        self.table = table
        self.name = name
    }
}

extension DAXEngine {
    /// Các tham chiếu `Bảng[Tên]` và `[Tên]` trong `expression`, theo thứ tự xuất hiện. Văn bản không phân tích được
    /// (chuỗi hở, ký tự lạ) thì trả rỗng: người gọi coi là không có tham chiếu và nên kiểm cú pháp riêng.
    public static func references(in expression: String) -> [DAXNameReference] {
        guard let tokens = try? DAXLexer.tokenize(expression) else { return [] }
        var found: [DAXNameReference] = []
        for (index, token) in tokens.enumerated() {
            guard case .bracket(let name) = token.kind else { continue }
            var table: String?
            if index > 0 {
                switch tokens[index - 1].kind {
                case .quoted(let quoted): table = quoted
                case .identifier(let word) where tokens[index - 1].range.end == token.range.start: table = word
                default: break
                }
            }
            found.append(DAXNameReference(table: table, name: name))
        }
        return found
    }
}

extension DAXEngine {
    /// Tên bảng mà `expression` nhắc tới như một bảng (T116, tìm cột/bảng tính toán phụ thuộc): `'Bảng'` có nháy hoặc tên trần, không đứng
    /// trước `(` (hàm) và không sát `[` (đó là `Bảng[Cột]`, đã có ở `references`). Chữ thường. Thận trọng: từ khoá như `TRUE`, `VAR` cũng có
    /// trong kết quả; người gọi chỉ so với tên bảng có thật. Văn bản không phân tích được thì trả nil.
    public static func tableNames(in expression: String) -> Set<String>? {
        guard let tokens = try? DAXLexer.tokenize(expression) else { return nil }
        var found = Set<String>()
        for (index, token) in tokens.enumerated() {
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            let isQuoted: Bool = if case .quoted = token.kind { true } else { false }
            if let next, case .bracket = next.kind, isQuoted || next.range.start == token.range.end { continue }
            switch token.kind {
            case .quoted(let name):
                found.insert(name.lowercased())
            case .identifier(let word):
                if let next, case .symbol("(") = next.kind { continue }
                found.insert(word.lowercased())
            default:
                continue
            }
        }
        return found
    }
}
