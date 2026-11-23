import PBIXKit
// Phase F (T048): bộ phân tích cú pháp M (đệ quy xuống, ưu tiên toán tử theo tài liệu công khai của ngôn ngữ).
//
// Thứ tự ưu tiên (thấp → cao): or, and, is, as, = <>, < > <= >=, + - &, * /, meta (chưa hỗ trợ), một ngôi, postfix.
// `each`, `if`, `let`, `try`, `error`, hàm `(…) =>` chỉ đứng ở vị trí biểu thức, không làm toán hạng của toán tử hai ngôi.

public enum MParser {
    public static func parse(_ source: String) throws -> MExpression {
        var parser = Parser(tokens: try MLexer.tokenize(source), source: Array(source.unicodeScalars))
        let expression = try parser.parseExpression()
        guard case .eof = parser.current.kind else { throw parser.unexpected() }
        return expression
    }

    /// Phân tích một biểu thức kiểu độc lập (cho `type …` trong Advanced Editor, test).
    public static func parseType(_ source: String) throws -> MTypeExpr {
        var parser = Parser(tokens: try MLexer.tokenize(source), source: Array(source.unicodeScalars))
        let type = try parser.parseType()
        guard case .eof = parser.current.kind else { throw parser.unexpected() }
        return type
    }
}

private struct Parser {
    let tokens: [MToken]
    let source: [Unicode.Scalar]
    var position = 0

    init(tokens: [MToken], source: [Unicode.Scalar]) {
        self.tokens = tokens
        self.source = source
    }

    var current: MToken { tokens[position] }
    func peek(_ offset: Int = 1) -> MToken { tokens[min(position + offset, tokens.count - 1)] }

    mutating func advance() { if position < tokens.count - 1 { position += 1 } }

    func fail(_ message: String, at token: MToken? = nil) -> MSyntaxError {
        let t = token ?? current
        return MSyntaxError(line: t.line, column: t.column, message: message)
    }

    func unexpected() -> MSyntaxError {
        switch current.kind {
        case .eof: fail(lt("Biểu thức M kết thúc đột ngột", "The M expression ended unexpectedly"))
        case .symbol(let s): fail(lt("Cú pháp M: không mong đợi '\(s)'", "M syntax: unexpected '\(s)'"))
        case .keyword(let k): fail(lt("Cú pháp M: không mong đợi '\(k)'", "M syntax: unexpected '\(k)'"))
        case .identifier(let n), .quotedIdentifier(let n): fail(lt("Cú pháp M: không mong đợi '\(n)'", "M syntax: unexpected '\(n)'"))
        case .number: fail(lt("Cú pháp M: không mong đợi số", "M syntax: unexpected number"))
        case .text: fail(lt("Cú pháp M: không mong đợi chuỗi", "M syntax: unexpected string"))
        }
    }

    func isSymbol(_ s: String) -> Bool { if case .symbol(let v) = current.kind { v == s } else { false } }
    func isKeyword(_ k: String) -> Bool { if case .keyword(let v) = current.kind { v == k } else { false } }

    mutating func accept(symbol s: String) -> Bool {
        if isSymbol(s) { advance(); return true }
        return false
    }

    mutating func accept(keyword k: String) -> Bool {
        if isKeyword(k) { advance(); return true }
        return false
    }

    mutating func expect(symbol s: String) throws {
        guard accept(symbol: s) else { throw unexpected() }
    }

    mutating func expect(keyword k: String) throws {
        guard accept(keyword: k) else { throw unexpected() }
    }

    // MARK: Biểu thức

    mutating func parseExpression() throws -> MExpression {
        switch current.kind {
        case .keyword("let"): return try parseLet()
        case .keyword("if"): return try parseIf()
        case .keyword("each"):
            advance()
            return .function([MParameter(name: "_")], returnType: nil, body: try parseExpression())
        case .keyword("try"):
            advance()
            let protected = try parseExpression()
            if accept(keyword: "otherwise") { return .tryOtherwise(protected, otherwise: try parseExpression()) }
            return .tryOtherwise(protected, otherwise: nil)
        case .keyword("error"):
            advance()
            return .error(try parseExpression())
        case .symbol("("):
            if let function = try tryParseFunction() { return function }
            return try parseLogicalOr()
        default:
            return try parseLogicalOr()
        }
    }

    mutating func parseLet() throws -> MExpression {
        try expect(keyword: "let")
        var bindings: [MBinding] = []
        repeat {
            let name = try parseVariableName()
            try expect(symbol: "=")
            bindings.append(MBinding(name: name, value: try parseExpression()))
        } while accept(symbol: ",")
        try expect(keyword: "in")
        return .letIn(bindings, try parseExpression())
    }

    mutating func parseIf() throws -> MExpression {
        try expect(keyword: "if")
        let condition = try parseExpression()
        try expect(keyword: "then")
        let whenTrue = try parseExpression()
        try expect(keyword: "else")
        return .ifThenElse(condition, whenTrue, try parseExpression())
    }

    /// Tên biến trong `let`: định danh thường hoặc `#"…"`.
    mutating func parseVariableName() throws -> String {
        switch current.kind {
        case .identifier(let n), .quotedIdentifier(let n): advance(); return n
        default: throw unexpected()
        }
    }

    /// `(a, b as number) as number => body`; trả `nil` (và giữ nguyên vị trí) nếu không phải hàm.
    mutating func tryParseFunction() throws -> MExpression? {
        let saved = position
        guard accept(symbol: "(") else { return nil }
        var parameters: [MParameter] = []
        if !isSymbol(")") {
            repeat {
                var optional = false
                if case .identifier("optional") = current.kind, case .identifier = peek().kind { advance(); optional = true }
                guard case .identifier(let name) = current.kind else { position = saved; return nil }
                advance()
                var type: MTypeExpr?
                if accept(keyword: "as") {
                    guard let parsed = try? parseNullablePrimitiveOrType() else { position = saved; return nil }
                    type = parsed
                }
                parameters.append(MParameter(name: name, isOptional: optional, type: type))
            } while accept(symbol: ",")
        }
        guard accept(symbol: ")") else { position = saved; return nil }
        var returnType: MTypeExpr?
        if accept(keyword: "as") {
            guard let parsed = try? parseNullablePrimitiveOrType() else { position = saved; return nil }
            returnType = parsed
        }
        guard accept(symbol: "=>") else { position = saved; return nil }
        return .function(parameters, returnType: returnType, body: try parseExpression())
    }

    mutating func parseLogicalOr() throws -> MExpression {
        var left = try parseLogicalAnd()
        while accept(keyword: "or") { left = .binary(.or, left, try parseLogicalAnd()) }
        return left
    }

    mutating func parseLogicalAnd() throws -> MExpression {
        var left = try parseIs()
        while accept(keyword: "and") { left = .binary(.and, left, try parseIs()) }
        return left
    }

    mutating func parseIs() throws -> MExpression {
        var left = try parseAs()
        while accept(keyword: "is") { left = .isType(left, try parseNullablePrimitiveOrType()) }
        return left
    }

    mutating func parseAs() throws -> MExpression {
        var left = try parseEquality()
        while accept(keyword: "as") { left = .asType(left, try parseNullablePrimitiveOrType()) }
        return left
    }

    mutating func parseEquality() throws -> MExpression {
        var left = try parseRelational()
        while true {
            if accept(symbol: "=") { left = .binary(.equal, left, try parseRelational()) }
            else if accept(symbol: "<>") { left = .binary(.notEqual, left, try parseRelational()) }
            else { return left }
        }
    }

    mutating func parseRelational() throws -> MExpression {
        var left = try parseAdditive()
        while true {
            if accept(symbol: "<=") { left = .binary(.lessOrEqual, left, try parseAdditive()) }
            else if accept(symbol: ">=") { left = .binary(.greaterOrEqual, left, try parseAdditive()) }
            else if accept(symbol: "<") { left = .binary(.less, left, try parseAdditive()) }
            else if accept(symbol: ">") { left = .binary(.greater, left, try parseAdditive()) }
            else { return left }
        }
    }

    mutating func parseAdditive() throws -> MExpression {
        var left = try parseMultiplicative()
        while true {
            if accept(symbol: "+") { left = .binary(.add, left, try parseMultiplicative()) }
            else if accept(symbol: "-") { left = .binary(.subtract, left, try parseMultiplicative()) }
            else if accept(symbol: "&") { left = .binary(.concat, left, try parseMultiplicative()) }
            else { return left }
        }
    }

    mutating func parseMultiplicative() throws -> MExpression {
        var left = try parseMetadata()
        while true {
            if accept(symbol: "*") { left = .binary(.multiply, left, try parseMetadata()) }
            else if accept(symbol: "/") { left = .binary(.divide, left, try parseMetadata()) }
            else { return left }
        }
    }

    mutating func parseMetadata() throws -> MExpression {
        var left = try parseUnary()
        while accept(keyword: "meta") { left = .binary(.meta, left, try parseUnary()) }
        return left
    }

    mutating func parseUnary() throws -> MExpression {
        if accept(symbol: "-") { return .unary(.negate, try parseUnary()) }
        if accept(symbol: "+") { return .unary(.plus, try parseUnary()) }
        if accept(keyword: "not") { return .unary(.not, try parseUnary()) }
        if isKeyword("type") {
            advance()
            return .type(try parseType())
        }
        return try parsePostfix()
    }

    // MARK: Primary và hậu tố

    mutating func parsePostfix() throws -> MExpression {
        var expression = try parsePrimary()
        while true {
            if isSymbol("(") {
                let line = current.line
                advance()
                var arguments: [MExpression] = []
                if !isSymbol(")") {
                    repeat { arguments.append(try parseExpression()) } while accept(symbol: ",")
                }
                try expect(symbol: ")")
                expression = .invoke(expression, arguments, line: line)
            } else if isSymbol("{") {
                advance()
                let index = try parseExpression()
                try expect(symbol: "}")
                expression = .itemAccess(expression, index, optional: accept(symbol: "?"))
            } else if isSymbol("[") {
                advance()
                let name = try parseFieldName()
                try expect(symbol: "]")
                expression = .fieldAccess(expression, name, optional: accept(symbol: "?"))
            } else {
                return expression
            }
        }
    }

    mutating func parsePrimary() throws -> MExpression {
        let token = current
        switch token.kind {
        case .number(let v): advance(); return .number(v)
        case .text(let s): advance(); return .text(s)
        case .keyword("true"): advance(); return .logical(true)
        case .keyword("false"): advance(); return .logical(false)
        case .keyword("null"): advance(); return .null
        case .identifier(let name), .quotedIdentifier(let name):
            advance()
            return .identifier(name, line: token.line)
        case .keyword(let k) where k.hasPrefix("#") && k != "#sections" && k != "#shared":
            advance()
            return .identifier(k, line: token.line)
        case .symbol("@"):
            advance()
            guard case .identifier(let name) = current.kind else { throw unexpected() }
            let line = current.line
            advance()
            return .identifier(name, line: line)
        case .symbol("("):
            advance()
            let inner = try parseExpression()
            try expect(symbol: ")")
            return inner
        case .symbol("{"):
            return try parseList()
        case .symbol("["):
            return try parseRecordOrImplicitField()
        default:
            throw unexpected()
        }
    }

    mutating func parseList() throws -> MExpression {
        try expect(symbol: "{")
        var items: [MExpression] = []
        if !isSymbol("}") {
            repeat {
                let first = try parseExpression()
                if accept(symbol: "..") { items.append(.range(first, try parseExpression())) } else { items.append(first) }
            } while accept(symbol: ",")
        }
        try expect(symbol: "}")
        return .list(items)
    }

    /// `[a = 1, b = 2]` hoặc `[Name]` (truy cập trường ngầm của `_`).
    mutating func parseRecordOrImplicitField() throws -> MExpression {
        try expect(symbol: "[")
        if accept(symbol: "]") { return .record([]) }
        let name = try parseFieldName()
        if accept(symbol: "]") {
            return .fieldAccess(.identifier("_", line: current.line), name, optional: accept(symbol: "?"))
        }
        var bindings: [MBinding] = []
        var currentName = name
        while true {
            try expect(symbol: "=")
            bindings.append(MBinding(name: currentName, value: try parseExpression()))
            if accept(symbol: ",") { currentName = try parseFieldName() } else { break }
        }
        try expect(symbol: "]")
        return .record(bindings)
    }

    /// Tên trường: `#"…"`, hoặc dãy từ có khoảng trắng (`Order Date`) lấy nguyên văn từ nguồn.
    mutating func parseFieldName() throws -> String {
        if case .quotedIdentifier(let name) = current.kind { advance(); return name }
        guard let first = nameToken(current) else { throw unexpected() }
        var end = first.end
        advance()
        while let next = nameToken(current) {
            end = next.end
            advance()
        }
        return String(String.UnicodeScalarView(source[first.start..<end]))
    }

    private func nameToken(_ token: MToken) -> MToken? {
        switch token.kind {
        case .identifier, .number: token
        case .keyword(let k) where !k.hasPrefix("#") && !["and", "or", "in", "then", "else", "is", "as", "otherwise"].contains(k): token
        default: nil
        }
    }

    // MARK: Kiểu

    /// Sau `as`/`is`: `nullable? kiểu-nguyên-thuỷ`, hoặc kiểu phức.
    mutating func parseNullablePrimitiveOrType() throws -> MTypeExpr {
        try parseType()
    }

    mutating func parseType() throws -> MTypeExpr {
        if case .identifier("nullable") = current.kind {
            advance()
            return .nullable(try parseType())
        }
        if isSymbol("{") {
            advance()
            let item = try parseType()
            try expect(symbol: "}")
            return .list(item)
        }
        if isSymbol("[") { return .record(try parseFieldTypes()) }
        if isSymbol("(") {
            advance()
            let inner = try parseType()
            try expect(symbol: ")")
            return inner
        }
        switch current.kind {
        case .identifier(let name):
            advance()
            if name == "table", isSymbol("[") { return .table(try parseFieldTypes()) }
            if name == "function" { return .function }
            return .primitive(name)
        case .keyword("null"):
            advance()
            return .primitive("null")
        default:
            throw unexpected()
        }
    }

    mutating func parseFieldTypes() throws -> [MTypeFieldExpr] {
        try expect(symbol: "[")
        var fields: [MTypeFieldExpr] = []
        if !isSymbol("]") {
            repeat {
                var optional = false
                if case .identifier("optional") = current.kind, nameToken(peek()) != nil || isQuoted(peek()) { advance(); optional = true }
                let name = try parseFieldName()
                var type: MTypeExpr?
                if accept(symbol: "=") { type = try parseType() }
                fields.append(MTypeFieldExpr(name: name, type: type, isOptional: optional))
            } while accept(symbol: ",")
        }
        try expect(symbol: "]")
        return fields
    }

    private func isQuoted(_ token: MToken) -> Bool { if case .quotedIdentifier = token.kind { true } else { false } }
}
