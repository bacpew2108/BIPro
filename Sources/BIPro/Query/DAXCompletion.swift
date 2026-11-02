import Foundation
import DAXEngine
import PBIXKit

public enum CompletionItemKind: Sendable, Hashable {
    case function
    case table
    case column
    case measure
    case keyword
}

public struct CompletionItem: Sendable, Hashable {
    public let kind: CompletionItemKind
    public let label: String
    public let insertText: String
    public let detail: String?

    public init(kind: CompletionItemKind, label: String, insertText: String, detail: String? = nil) {
        self.kind = kind
        self.label = label
        self.insertText = insertText
        self.detail = detail
    }
}

public struct CompletionModel: Sendable {
    public static let defaultFunctions: [String] = {
        var list = FunctionRegistry.all.map(\.name)
        if !list.contains("SUMMARIZECOLUMNS") {
            list.insert("SUMMARIZECOLUMNS", at: 0)
        }
        if !list.contains("ROW") {
            list.append("ROW")
        }
        return list
    }()

    public var functions: [String]
    public var tables: [String]
    public var columnsByTable: [String: [String]]
    public var measuresByTable: [String: [ModelMetadata.Measure]]
    public var keywords: [String]

    public init(
        functions: [String] = CompletionModel.defaultFunctions,
        tables: [String] = [],
        columnsByTable: [String: [String]] = [:],
        measuresByTable: [String: [ModelMetadata.Measure]] = [:],
        keywords: [String] = [
            "EVALUATE", "DEFINE", "MEASURE", "VAR", "TABLE", "COLUMN",
            "RETURN", "ORDER BY", "ASC", "DESC", "START AT", "IN",
            "NOT", "TRUE", "FALSE"
        ]
    ) {
        self.functions = functions
        self.tables = tables
        self.columnsByTable = columnsByTable
        self.measuresByTable = measuresByTable
        self.keywords = keywords
    }
}

public struct CompletionResult: Sendable, Hashable {
    public let replaceRange: NSRange
    public let items: [CompletionItem]

    public init(replaceRange: NSRange, items: [CompletionItem]) {
        self.replaceRange = replaceRange
        self.items = items
    }
}

public enum DAXCompletion {
    /// Tính toán danh sách gợi ý tự hoàn thành tại con trỏ `cursor` (UTF-16 offset).
    /// Trả về `nil` nếu ở trong chuỗi `"..."` hoặc comment `//`, `--`.
    public static func suggestions(text: String, cursor: Int, model: CompletionModel) -> CompletionResult? {
        let ns = text as NSString
        let length = ns.length
        guard cursor >= 0, cursor <= length else { return nil }

        // Kiểm tra xem con trỏ có nằm trong chuỗi hoặc comment không
        if isInsideStringOrComment(ns: ns, length: length, cursor: cursor) {
            return nil
        }

        let hasClosingBracketAfterCursor = (cursor < length && ns.character(at: cursor) == 93) // "]"
        let hasClosingQuoteAfterCursor = (cursor < length && ns.character(at: cursor) == 39)   // "'"

        // 1. Kiểm tra xem có đang ở trong [...] trên dòng hiện tại không
        if let bracketPos = findOpeningBracketBeforeCursor(ns: ns, cursor: cursor) {
            let partial = ns.substring(with: NSRange(location: bracketPos + 1, length: cursor - (bracketPos + 1)))
            let replaceRange = NSRange(location: bracketPos + 1, length: cursor - (bracketPos + 1))

            // Kiểm tra xem trước [ có tên bảng không (ví dụ 'Bảng'[ hoặc Bảng[)
            if let tableName = findTableBeforeBracket(ns: ns, bracketPos: bracketPos, tables: model.tables) {
                // Ngữ cảnh A: Sau 'Bảng'[ hoặc Bảng[ -> chỉ cột và measure của bảng đó
                return suggestionsForTableMembers(
                    tableName: tableName,
                    partial: partial,
                    replaceRange: replaceRange,
                    hasClosingBracket: hasClosingBracketAfterCursor,
                    model: model
                )
            } else {
                // Ngữ cảnh B: Sau [ không có bảng đứng trước -> mọi measure, rồi cột mọi bảng (Bảng[cột])
                return suggestionsForBracketWithoutTable(
                    partial: partial,
                    replaceRange: replaceRange,
                    hasClosingBracket: hasClosingBracketAfterCursor,
                    model: model
                )
            }
        }

        // 2. Kiểm tra xem có đang ở ngay sau dấu ' mở trên dòng hiện tại không
        if let quotePos = findOpeningQuoteBeforeCursor(ns: ns, cursor: cursor) {
            // Ngữ cảnh C: Ngay sau dấu ' mở -> tên bảng, insertText là "Tên bảng'"
            let partial = ns.substring(with: NSRange(location: quotePos + 1, length: cursor - (quotePos + 1)))
            let replaceRange = NSRange(location: quotePos + 1, length: cursor - (quotePos + 1))
            return suggestionsForTableQuotes(
                partial: partial,
                replaceRange: replaceRange,
                hasClosingQuote: hasClosingQuoteAfterCursor,
                model: model
            )
        }

        // 3. Ngữ cảnh D: Đang gõ một định danh thường (chữ, số, _ ; không ở trong chuỗi hoặc comment)
        return suggestionsForGeneralIdentifier(
            ns: ns,
            cursor: cursor,
            model: model
        )
    }

    // MARK: - Kiểm tra chuỗi / comment

    private static func isInsideStringOrComment(ns: NSString, length: Int, cursor: Int) -> Bool {
        var i = 0
        while i < length {
            let c = ns.character(at: i)

            // Chuỗi: "..." (hỗ trợ escape "")
            if c == 34 { // "\""
                let openQuote = i
                i += 1
                var closed = false
                while i < length {
                    let sc = ns.character(at: i)
                    if sc == 34 {
                        if i + 1 < length && ns.character(at: i + 1) == 34 {
                            i += 2
                            continue
                        } else {
                            closed = true
                            let closeQuote = i
                            i += 1
                            if cursor > openQuote && cursor <= closeQuote {
                                return true
                            }
                            break
                        }
                    }
                    i += 1
                }
                if !closed {
                    // Chuỗi chưa đóng
                    if cursor > openQuote { return true }
                }
                continue
            }

            // Comment dòng: // hoặc --
            if i + 1 < length {
                let next = ns.character(at: i + 1)
                if (c == 47 && next == 47) || (c == 45 && next == 45) { // "//" hoặc "--"
                    let commentStart = i
                    i += 2
                    while i < length && ns.character(at: i) != 10 { // "\n"
                        i += 1
                    }
                    let commentEnd = i
                    if cursor > commentStart && cursor <= commentEnd {
                        return true
                    }
                    continue
                }
            }

            i += 1
        }
        return false
    }

    // MARK: - Tìm vị trí mở [ hoặc '

    private static func findOpeningBracketBeforeCursor(ns: NSString, cursor: Int) -> Int? {
        var p = cursor - 1
        while p >= 0 {
            let c = ns.character(at: p)
            if c == 10 || c == 93 { // "\n" hoặc "]"
                return nil
            }
            if c == 91 { // "["
                return p
            }
            p -= 1
        }
        return nil
    }

    private static func findOpeningQuoteBeforeCursor(ns: NSString, cursor: Int) -> Int? {
        var p = cursor - 1
        while p >= 0 {
            let c = ns.character(at: p)
            if c == 10 || c == 91 || c == 93 { // "\n", "[", "]"
                return nil
            }
            if c == 39 { // "'"
                // Đảm bảo dấu ' này không phải là dấu đóng của một cặp '...' trước đó
                // Đếm tổng số dấu ' từ đầu dòng đến p
                var lineStart = p
                while lineStart > 0 && ns.character(at: lineStart - 1) != 10 {
                    lineStart -= 1
                }
                var quoteCount = 0
                for k in lineStart...p {
                    if ns.character(at: k) == 39 {
                        quoteCount += 1
                    }
                }
                // Nếu số dấu nháy lẻ thì dấu này là dấu mở!
                if quoteCount % 2 == 1 {
                    return p
                } else {
                    return nil
                }
            }
            p -= 1
        }
        return nil
    }

    private static func findTableBeforeBracket(ns: NSString, bracketPos: Int, tables: [String]) -> String? {
        var p = bracketPos - 1
        // Bỏ qua khoảng trắng giữa bảng và [ nếu có
        while p >= 0 && (ns.character(at: p) == 32 || ns.character(at: p) == 9) {
            p -= 1
        }
        guard p >= 0 else { return nil }

        // Trường hợp 1: 'Tên bảng'[
        if ns.character(at: p) == 39 { // "'"
            let closeQuote = p
            var openQuote: Int? = nil
            var q = closeQuote - 1
            while q >= 0 {
                let ch = ns.character(at: q)
                if ch == 10 { break }
                if ch == 39 {
                    openQuote = q
                    break
                }
                q -= 1
            }
            if let open = openQuote {
                return ns.substring(with: NSRange(location: open + 1, length: closeQuote - (open + 1)))
            }
            return nil
        }

        // Trường hợp 2: TênBảng[
        let wordEnd = p + 1
        var q = p
        while q >= 0 {
            let ch = ns.character(at: q)
            let isLetter = (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
            let isDigit = (ch >= 48 && ch <= 57)
            let isUnderscore = (ch == 95)
            if isLetter || isDigit || isUnderscore {
                q -= 1
            } else {
                break
            }
        }
        let wordStart = q + 1
        if wordStart < wordEnd {
            let word = ns.substring(with: NSRange(location: wordStart, length: wordEnd - wordStart))
            // Chỉ coi là bảng nếu khớp một bảng trong model hoặc chạm trực tiếp vào bracket
            if let matched = tables.first(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                return matched
            }
            if wordEnd == bracketPos {
                return word
            }
        }

        return nil
    }

    // MARK: - Ngữ cảnh A: Cột và measure của bảng cụ thể

    private static func suggestionsForTableMembers(
        tableName: String,
        partial: String,
        replaceRange: NSRange,
        hasClosingBracket: Bool,
        model: CompletionModel
    ) -> CompletionResult {
        let cols = model.columnsByTable.first(where: { $0.key.caseInsensitiveCompare(tableName) == .orderedSame })?.value ?? []
        let measures = model.measuresByTable.first(where: { $0.key.caseInsensitiveCompare(tableName) == .orderedSame })?.value ?? []

        var candidates: [(item: CompletionItem, isPrefix: Bool)] = []
        let trimmedPartial = partial.lowercased()

        for m in measures {
            let name = m.name
            let (matches, isPrefix) = matchString(name, query: trimmedPartial)
            if matches {
                let insert = hasClosingBracket ? name : "\(name)]"
                let detail = m.expression.isEmpty ? tableName : m.expression
                let item = CompletionItem(kind: .measure, label: name, insertText: insert, detail: detail)
                candidates.append((item, isPrefix))
            }
        }

        for c in cols {
            let (matches, isPrefix) = matchString(c, query: trimmedPartial)
            if matches {
                let insert = hasClosingBracket ? c : "\(c)]"
                let item = CompletionItem(kind: .column, label: c, insertText: insert, detail: tableName)
                candidates.append((item, isPrefix))
            }
        }

        // Sắp xếp: khớp tiền tố trước, rồi measure trước column, rồi A-Z
        candidates.sort { a, b in
            if a.isPrefix != b.isPrefix { return a.isPrefix && !b.isPrefix }
            let kindA = a.item.kind == .measure ? 0 : 1
            let kindB = b.item.kind == .measure ? 0 : 1
            if kindA != kindB { return kindA < kindB }
            return a.item.label.localizedCaseInsensitiveCompare(b.item.label) == .orderedAscending
        }

        let items = Array(candidates.map(\.item).prefix(50))
        return CompletionResult(replaceRange: replaceRange, items: items)
    }

    // MARK: - Ngữ cảnh B: Mọi measure và cột của mọi bảng sau [

    private static func suggestionsForBracketWithoutTable(
        partial: String,
        replaceRange: NSRange,
        hasClosingBracket: Bool,
        model: CompletionModel
    ) -> CompletionResult {
        let trimmedPartial = partial.lowercased()
        var candidates: [(item: CompletionItem, isPrefix: Bool)] = []

        // 1. Mọi measure
        var seenMeasures = Set<String>()
        for (table, measures) in model.measuresByTable {
            for m in measures {
                if !seenMeasures.insert(m.name).inserted { continue }
                let (matches, isPrefix) = matchString(m.name, query: trimmedPartial)
                if matches {
                    let insert = hasClosingBracket ? m.name : "\(m.name)]"
                    let detail = m.expression.isEmpty ? table : m.expression
                    let item = CompletionItem(kind: .measure, label: m.name, insertText: insert, detail: detail)
                    candidates.append((item, isPrefix))
                }
            }
        }

        // 2. Cột của mọi bảng: label dạng Bảng[cột], insertText là cột]
        for (table, cols) in model.columnsByTable {
            for c in cols {
                let label = "\(table)[\(c)]"
                // Khớp trên tên cột trước hoặc cả label
                let matchCol = matchString(c, query: trimmedPartial)
                let matchFull = matchString(label, query: trimmedPartial)
                let matches = matchCol.matches || matchFull.matches
                let isPrefix = matchCol.isPrefix || matchFull.isPrefix
                if matches {
                    let insert = hasClosingBracket ? c : "\(c)]"
                    let item = CompletionItem(kind: .column, label: label, insertText: insert, detail: table)
                    candidates.append((item, isPrefix))
                }
            }
        }

        // Sắp xếp: khớp tiền tố trước, rồi measure trước column, rồi A-Z
        candidates.sort { a, b in
            if a.isPrefix != b.isPrefix { return a.isPrefix && !b.isPrefix }
            let kindA = a.item.kind == .measure ? 0 : 1
            let kindB = b.item.kind == .measure ? 0 : 1
            if kindA != kindB { return kindA < kindB }
            return a.item.label.localizedCaseInsensitiveCompare(b.item.label) == .orderedAscending
        }

        let items = Array(candidates.map(\.item).prefix(50))
        return CompletionResult(replaceRange: replaceRange, items: items)
    }

    // MARK: - Ngữ cảnh C: Tên bảng sau '

    private static func suggestionsForTableQuotes(
        partial: String,
        replaceRange: NSRange,
        hasClosingQuote: Bool,
        model: CompletionModel
    ) -> CompletionResult {
        let trimmedPartial = partial.lowercased()
        var candidates: [(item: CompletionItem, isPrefix: Bool)] = []

        for t in model.tables {
            let (matches, isPrefix) = matchString(t, query: trimmedPartial)
            if matches {
                let insert = hasClosingQuote ? t : "\(t)'"
                let item = CompletionItem(kind: .table, label: t, insertText: insert, detail: "Table")
                candidates.append((item, isPrefix))
            }
        }

        candidates.sort { a, b in
            if a.isPrefix != b.isPrefix { return a.isPrefix && !b.isPrefix }
            return a.item.label.localizedCaseInsensitiveCompare(b.item.label) == .orderedAscending
        }

        let items = Array(candidates.map(\.item).prefix(50))
        return CompletionResult(replaceRange: replaceRange, items: items)
    }

    // MARK: - Ngữ cảnh D: Định danh thường

    private static func suggestionsForGeneralIdentifier(
        ns: NSString,
        cursor: Int,
        model: CompletionModel
    ) -> CompletionResult? {
        // Tìm từ đang gõ lùi lại từ con trỏ
        var p = cursor - 1
        while p >= 0 {
            let ch = ns.character(at: p)
            let isLetter = (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
            let isDigit = (ch >= 48 && ch <= 57)
            let isUnderscore = (ch == 95)
            if isLetter || isDigit || isUnderscore {
                p -= 1
            } else {
                break
            }
        }
        let wordStart = p + 1
        let partial = ns.substring(with: NSRange(location: wordStart, length: cursor - wordStart))
        let replaceRange = NSRange(location: wordStart, length: cursor - wordStart)
        let trimmedPartial = partial.lowercased()

        var candidates: [(item: CompletionItem, isPrefix: Bool, matchRank: Int)] = []

        // Priority thứ tự: measure (0), function (1), table (2), keyword (3)

        // 1. Measures: dạng [tên]
        var seenMeasures = Set<String>()
        for (table, measures) in model.measuresByTable {
            for m in measures {
                if !seenMeasures.insert(m.name).inserted { continue }
                let (matches, isPrefix) = matchMeasure(name: m.name, query: trimmedPartial)
                if matches {
                    let insert = "[\(m.name)]"
                    let detail = m.expression.isEmpty ? table : m.expression
                    let item = CompletionItem(kind: .measure, label: "[\(m.name)]", insertText: insert, detail: detail)
                    candidates.append((item, isPrefix, 0))
                }
            }
        }

        // 2. Functions: insertText là TÊN(
        for fn in model.functions {
            let (matches, isPrefix) = matchString(fn, query: trimmedPartial)
            if matches {
                let item = CompletionItem(kind: .function, label: fn, insertText: "\(fn)(", detail: "Function")
                candidates.append((item, isPrefix, 1))
            }
        }

        // 3. Tables: có dấu cách thì bọc '...'
        for tbl in model.tables {
            let (matches, isPrefix) = matchString(tbl, query: trimmedPartial)
            if matches {
                let insert = tbl.contains(" ") ? "'\(tbl)'" : tbl
                let item = CompletionItem(kind: .table, label: tbl, insertText: insert, detail: "Table")
                candidates.append((item, isPrefix, 2))
            }
        }

        // 4. Keywords
        for kw in model.keywords {
            let (matches, isPrefix) = matchString(kw, query: trimmedPartial)
            if matches {
                let item = CompletionItem(kind: .keyword, label: kw, insertText: kw, detail: "Keyword")
                candidates.append((item, isPrefix, 3))
            }
        }

        // Sắp xếp:
        // 1. Khớp tiền tố trước (isPrefix == true trước isPrefix == false)
        // 2. Kind theo thứ tự: measure (0), hàm (1), bảng (2), từ khoá (3)
        // 3. A-Z
        candidates.sort { a, b in
            if a.isPrefix != b.isPrefix { return a.isPrefix && !b.isPrefix }
            if a.matchRank != b.matchRank { return a.matchRank < b.matchRank }
            if a.item.label == "SUMMARIZECOLUMNS" && b.item.label != "SUMMARIZECOLUMNS" { return true }
            if b.item.label == "SUMMARIZECOLUMNS" && a.item.label != "SUMMARIZECOLUMNS" { return false }
            return a.item.label.localizedCaseInsensitiveCompare(b.item.label) == .orderedAscending
        }

        let items = Array(candidates.map(\.item).prefix(50))
        return CompletionResult(replaceRange: replaceRange, items: items)
    }

    // MARK: - Tiện ích so khớp chuỗi

    private static func matchString(_ text: String, query: String) -> (matches: Bool, isPrefix: Bool) {
        if query.isEmpty { return (true, true) }
        let lower = text.lowercased()
        if lower.hasPrefix(query) {
            return (true, true)
        }
        if lower.contains(query) {
            return (true, false)
        }
        return (false, false)
    }

    private static func matchMeasure(name: String, query: String) -> (matches: Bool, isPrefix: Bool) {
        if query.isEmpty { return (true, true) }
        let bracketed = "[\(name)]".lowercased()
        let raw = name.lowercased()

        if raw.hasPrefix(query) || bracketed.hasPrefix(query) {
            return (true, true)
        }
        if raw.contains(query) || bracketed.contains(query) {
            return (true, false)
        }
        return (false, false)
    }
}
