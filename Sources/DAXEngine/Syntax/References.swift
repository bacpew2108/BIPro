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

/// Đối tượng đổi tên trong biểu thức DAX (Wave 3C / T020 Cascade Rename).
public enum DAXRenameTarget: Sendable, Hashable {
    case table(old: String, new: String)
    case column(table: String, old: String, new: String, ownerTable: String? = nil, hasMeasureWithOldName: Bool = false)
    case measure(table: String, old: String, new: String)
}

extension DAXEngine {
    /// Định dạng tên bảng hợp lệ trong DAX: tên chứa khoảng trắng hoặc ký tự đặc biệt bọc `'...'` với `''`.
    public static func formatTableIdentifier(_ name: String) -> String {
        let needsQuotes = name.isEmpty
            || name.first?.isNumber == true
            || name.contains { !($0.isLetter || $0.isNumber || $0 == "_") }
        if !needsQuotes { return name }
        return "'" + name.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// Định dạng tên cột/measure trong ngoặc vuông `[...]` với `]]`.
    public static func formatBracketIdentifier(_ name: String) -> String {
        "[" + name.replacingOccurrences(of: "]", with: "]]") + "]"
    }

    /// Viết lại tham chiếu trong `expression` dựa trên dãy token từ `DAXLexer.tokenize` (KHÔNG đụng chuỗi `"..."` hay chú thích).
    public static func rewriteReferences(in expression: String, target: DAXRenameTarget) -> String {
        let normalized = expression.replacingOccurrences(of: "\r\n", with: "\n")
        guard let tokens = try? DAXLexer.tokenize(normalized) else { return expression }
        var edits: [(start: Int, end: Int, replacement: String)] = []

        switch target {
        case .table(let old, let new):
            guard old.caseInsensitiveCompare(new) != .orderedSame else { return expression }
            let formatted = formatTableIdentifier(new)
            for (index, token) in tokens.enumerated() {
                let next = index + 1 < tokens.count ? tokens[index + 1] : nil
                switch token.kind {
                case .quoted(let name) where name.caseInsensitiveCompare(old) == .orderedSame:
                    edits.append((token.range.start, token.range.end, formatted))
                case .identifier(let word) where word.caseInsensitiveCompare(old) == .orderedSame:
                    // Không đổi tên lời gọi hàm `Word(...)`
                    if let next, case .symbol("(") = next.kind { continue }
                    edits.append((token.range.start, token.range.end, formatted))
                default:
                    continue
                }
            }

        case .column(let table, let old, let new, let ownerTable, let hasMeasureWithOldName):
            guard old.caseInsensitiveCompare(new) != .orderedSame else { return expression }
            let formatted = formatBracketIdentifier(new)
            for (index, token) in tokens.enumerated() {
                guard case .bracket(let name) = token.kind, name.caseInsensitiveCompare(old) == .orderedSame else { continue }
                var precedingTable: String?
                if index > 0 {
                    switch tokens[index - 1].kind {
                    case .quoted(let q): precedingTable = q
                    case .identifier(let w) where tokens[index - 1].range.end == token.range.start: precedingTable = w
                    default: break
                    }
                }
                let matches: Bool
                if let pt = precedingTable {
                    matches = pt.caseInsensitiveCompare(table) == .orderedSame
                } else {
                    matches = (ownerTable?.caseInsensitiveCompare(table) == .orderedSame) && !hasMeasureWithOldName
                }
                if matches {
                    edits.append((token.range.start, token.range.end, formatted))
                }
            }

        case .measure(let table, let old, let new):
            guard old.caseInsensitiveCompare(new) != .orderedSame else { return expression }
            let formatted = formatBracketIdentifier(new)
            for (index, token) in tokens.enumerated() {
                guard case .bracket(let name) = token.kind, name.caseInsensitiveCompare(old) == .orderedSame else { continue }
                var precedingTable: String?
                if index > 0 {
                    switch tokens[index - 1].kind {
                    case .quoted(let q): precedingTable = q
                    case .identifier(let w) where tokens[index - 1].range.end == token.range.start: precedingTable = w
                    default: break
                    }
                }
                if precedingTable == nil || precedingTable?.caseInsensitiveCompare(table) == .orderedSame {
                    edits.append((token.range.start, token.range.end, formatted))
                }
            }
        }

        guard !edits.isEmpty else { return expression }
        var utf16 = Array(normalized.utf16)
        for edit in edits.sorted(by: { $0.start > $1.start }) {
            guard edit.start >= 0, edit.end <= utf16.count, edit.start <= edit.end else { continue }
            utf16.replaceSubrange(edit.start..<edit.end, with: Array(edit.replacement.utf16))
        }
        return String(decoding: utf16, as: UTF16.self)
    }

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
