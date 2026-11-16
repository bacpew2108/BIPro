// Phase F, T055: truy vấn M như danh sách bước. Tách `let … in` ở mức văn bản (giữ nguyên văn từng biểu thức, như Desktop ghi vào
// `Partition.QueryDefinition`), dựng lại, chèn/xoá/đổi tên bước. Bước phụ thuộc nhau qua tên bước (tham chiếu định danh).

import Foundation

public struct MStep: Sendable, Equatable {
    public var name: String
    public var expression: String

    public init(name: String, expression: String) {
        self.name = name
        self.expression = expression
    }
}

public struct MQuery: Sendable, Equatable {
    public var steps: [MStep]
    /// Tên bước sau `in`.
    public var resultName: String

    public init(steps: [MStep], resultName: String) {
        self.steps = steps
        self.resultName = resultName
    }

    // MARK: Tách và dựng lại

    /// Tách `let … in` thành bước. Văn bản không phải `let` là một bước "Source". Lỗi cú pháp ném `MSyntaxError`.
    public static func parse(_ source: String) throws -> MQuery {
        _ = try MParser.parse(source)
        let tokens = try MLexer.tokenize(source)
        let chars = Array(source.unicodeScalars)
        func text(_ from: Int, _ to: Int) -> String { String(String.UnicodeScalarView(chars[from..<to])).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard case .keyword("let") = tokens[0].kind else {
            return MQuery(steps: [MStep(name: "Source", expression: text(0, chars.count))], resultName: "Source")
        }
        var steps: [MStep] = []
        var i = 1
        while true {
            guard let name = bindingName(tokens[i].kind), case .symbol("=") = tokens[i + 1].kind else {
                throw MSyntaxError(line: tokens[i].line, column: tokens[i].column, message: "Cú pháp M: mong đợi 'tên bước ='")
            }
            let first = i + 2
            var j = first, parens = 0, lets = 0
            scan: while j < tokens.count {
                switch tokens[j].kind {
                case .symbol("("), .symbol("["), .symbol("{"): parens += 1
                case .symbol(")"), .symbol("]"), .symbol("}"): parens -= 1
                case .keyword("let"): lets += 1
                case .keyword("in"): if lets > 0 { lets -= 1 } else if parens == 0 { break scan }
                case .symbol(","): if lets == 0 && parens == 0 { break scan }
                case .eof: break scan
                default: break
                }
                j += 1
            }
            guard j > first else {
                throw MSyntaxError(line: tokens[j].line, column: tokens[j].column, message: "Bước '\(name)' thiếu biểu thức")
            }
            steps.append(MStep(name: name, expression: text(tokens[first].start, tokens[j - 1].end)))
            if case .symbol(",") = tokens[j].kind { i = j + 1; continue }
            i = j + 1   // sau `in`
            break
        }
        var rest = Array(tokens[i...])
        if case .eof = rest.last?.kind { rest.removeLast() }
        if rest.count == 1, let name = bindingName(rest[0].kind) { return MQuery(steps: steps, resultName: name) }
        // `in` theo sau là biểu thức, không phải tên bước: thành bước "Result" (hiếm; Desktop luôn ghi tên bước).
        let result = StepFactory.uniqueName("Result", existing: Set(steps.map(\.name)))
        steps.append(MStep(name: result, expression: text(rest[0].start, rest[rest.count - 1].end)))
        return MQuery(steps: steps, resultName: result)
    }

    private static func bindingName(_ kind: MTokenKind) -> String? {
        switch kind {
        case .identifier(let n), .quotedIdentifier(let n): n
        default: nil
        }
    }

    /// Văn bản M đầy đủ, dạng Desktop ghi.
    public var source: String {
        let body = steps.map { "    \(Self.reference(to: $0.name)) = \($0.expression)" }.joined(separator: ",\n")
        return "let\n\(body)\nin\n    \(Self.reference(to: resultName))"
    }

    /// Cách viết tên bước trong biểu thức: định danh thường thì để trần, còn lại `#"…"` (dấu `"` nhân đôi).
    public static func reference(to name: String) -> String {
        let scalars = Array(name.unicodeScalars)
        let plain = !scalars.isEmpty && !MLexer.keywords.contains(name)
            && (scalars[0] == "_" || scalars[0].properties.isAlphabetic)
            && scalars.allSatisfy { $0 == "_" || $0.properties.isAlphabetic || ($0.value >= 48 && $0.value <= 57) }
        return plain ? name : "#\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: Sửa

    /// Chèn `new` ngay sau bước `index` (bước đầu của `new` đã trỏ vào bước `index`). Bước kế tiếp được nối lại vào bước vừa chèn
    /// (QUAN-SAT VM-F3 mục 2: `Removed Top Rows` đổi tham chiếu sang bước mới); bước xa hơn giữ nguyên.
    public mutating func insert(_ new: [MStep], afterStepAt index: Int) {
        guard !new.isEmpty, steps.indices.contains(index) else { return }
        let previous = steps[index].name
        let last = new[new.count - 1].name
        let wasLast = index == steps.count - 1
        steps.insert(contentsOf: new, at: index + 1)
        let next = index + 1 + new.count
        if next < steps.count {
            steps[next].expression = Self.rewrite(steps[next].expression, from: previous, to: last)
        }
        if wasLast, resultName == previous { resultName = last }
    }

    /// Xoá bước. [SUY ĐOÁN] bước nào đã trỏ vào bước bị xoá thì trỏ về bước đứng trước nó (giữ truy vấn hợp lệ); xoá bước đầu thì không nối lại.
    public mutating func removeStep(at index: Int) {
        guard steps.indices.contains(index) else { return }
        let name = steps[index].name
        let predecessor = index > 0 ? steps[index - 1].name : nil
        steps.remove(at: index)
        if let predecessor {
            for k in index..<steps.count { steps[k].expression = Self.rewrite(steps[k].expression, from: name, to: predecessor) }
        }
        if resultName == name { resultName = predecessor ?? steps.first?.name ?? "" }
    }

    /// Đổi tên bước và mọi tham chiếu ở bước sau và ở `in`.
    public mutating func renameStep(at index: Int, to newName: String) {
        guard steps.indices.contains(index) else { return }
        let old = steps[index].name
        steps[index].name = newName
        for k in (index + 1)..<steps.count where index + 1 < steps.count { steps[k].expression = Self.rewrite(steps[k].expression, from: old, to: newName) }
        if resultName == old { resultName = newName }
    }

    /// Đổi mọi tham chiếu tới truy vấn `old` thành `new` trong biểu thức (đổi tên truy vấn mà truy vấn khác đang dùng).
    public static func renameReference(in expression: String, from old: String, to new: String) -> String {
        rewrite(expression, from: old, to: new)
    }

    /// Thay tham chiếu định danh `old` bằng `new` trong một biểu thức. Tên trường sau `[` không bị đổi.
    static func rewrite(_ expression: String, from old: String, to new: String) -> String {
        guard let tokens = try? MLexer.tokenize(expression) else { return expression }
        let chars = Array(expression.unicodeScalars)
        var out = String.UnicodeScalarView()
        var cursor = 0
        for (k, token) in tokens.enumerated() {
            let name: String
            switch token.kind {
            case .identifier(let n), .quotedIdentifier(let n): name = n
            default: continue
            }
            if case .symbol("[") = k > 0 ? tokens[k - 1].kind : .eof { continue }
            guard name == old else { continue }
            out.append(contentsOf: chars[cursor..<token.start])
            out.append(contentsOf: reference(to: new).unicodeScalars)
            cursor = token.end
        }
        out.append(contentsOf: chars[cursor...])
        return String(out)
    }
}
