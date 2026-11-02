// Parser (LANG, đợt 1a). Đệ quy đi xuống theo bảng ưu tiên của architecture.md §5.2, từ cao xuống thấp:
//   ^  >  dấu một ngôi - +  >  * /  >  + -  >  &  >  so sánh và IN  >  NOT  >  &&  >  ||
// Lũy thừa ^ kết hợp trái. Dấu một ngôi có thể đứng sau ^ (2^-1).
// Đối số bỏ trống cho nil trong `args`: RANKX(a, , DESC) có đối số thứ ba là nil.
// Lỗi cú pháp là DAXError kind .syntax, mang SourceRange của token gây lỗi.

public func parseExpression(_ text: String) throws(DAXError) -> Expr {
    var parser = DAXParser(tokens: try DAXLexer.tokenize(text))
    return try parser.parseWholeExpression()
}

public func parseQuery(_ text: String) throws(DAXError) -> Query {
    var parser = DAXParser(tokens: try DAXLexer.tokenize(text))
    return try parser.parseWholeQuery()
}

extension Expr {
    /// Vị trí của nút trong văn bản gốc.
    public var range: SourceRange {
        switch self {
        case .number(_, _, let r), .string(_, let r), .boolean(_, let r),
             .columnRef(_, _, let r), .bracketRef(_, let r), .tableRef(_, let r),
             .identifier(_, let r), .call(_, _, let r), .unary(_, _, let r),
             .binary(_, _, _, let r), .varBlock(_, _, let r), .tableConstructor(_, let r):
            return r
        }
    }
}

/// Trạng thái của parser đệ quy đi xuống. Dùng một lần cho mỗi văn bản.
struct DAXParser {
    private let tokens: [DAXToken]
    private var pos = 0

    init(tokens: [DAXToken]) {
        self.tokens = tokens
    }

    // MARK: - Điểm vào

    mutating func parseWholeExpression() throws(DAXError) -> Expr {
        if case .eof = current.kind {
            throw DAXError(.syntax, "biểu thức trống", range: current.range)
        }
        let expr = try parseExpr()
        guard case .eof = current.kind else { throw unexpected("kết thúc biểu thức") }
        return expr
    }

    mutating func parseWholeQuery() throws(DAXError) -> Query {
        var query = Query()
        if keyword("DEFINE") {
            _ = next()
            var count = 0
            while true {
                if keyword("MEASURE") {
                    _ = next()
                    query.defines.append(try parseMeasureOrColumnHeader(isColumn: false))
                } else if keyword("COLUMN") {
                    _ = next()
                    query.defines.append(try parseMeasureOrColumnHeader(isColumn: true))
                } else if keyword("VAR") {
                    _ = next()
                    let name = try parseBareName("tên VAR")
                    try expectSymbol("=")
                    query.defines.append(.variable(name: name, try parseExpr()))
                } else if keyword("TABLE") {
                    _ = next()
                    let name = try parseTableName()
                    try expectSymbol("=")
                    query.defines.append(.table(name: name, try parseExpr()))
                } else {
                    break
                }
                count += 1
            }
            if count == 0 {
                throw unexpected("MEASURE, VAR, TABLE hoặc COLUMN sau DEFINE")
            }
        }
        while keyword("EVALUATE") {
            _ = next()
            query.statements.append(try parseEvaluate())
        }
        if query.statements.isEmpty {
            throw unexpected("EVALUATE")
        }
        guard case .eof = current.kind else { throw unexpected("kết thúc truy vấn") }
        return query
    }

    // MARK: - Khai báo và truy vấn

    /// Phần đầu của MEASURE 'T'[m] = ... hoặc COLUMN 'T'[c] = ...
    /// Với MEASURE, tên bảng có thể bỏ trống: MEASURE [m] = ... (khi đó bảng là "").
    private mutating func parseMeasureOrColumnHeader(isColumn: Bool) throws(DAXError) -> Definition {
        var table = ""
        if isColumn || !(isBracketToken(at: 0)) {
            table = try parseTableName()
        }
        guard case .bracket(let name) = current.kind else {
            throw unexpected("[tên] sau tên bảng")
        }
        _ = next()
        try expectSymbol("=")
        let body = try parseExpr()
        if isColumn {
            return .column(table: table, name: name, body)
        }
        return .measure(table: table, name: name, body)
    }

    /// Tên bảng: từ trần hoặc 'trong nháy đơn', có thể theo sau bởi ngoặc vuông (chỉ để kiểm cú pháp).
    private mutating func parseTableName() throws(DAXError) -> String {
        switch current.kind {
        case .identifier(let name), .quoted(let name):
            _ = next()
            return name
        default:
            throw unexpected("tên bảng")
        }
    }

    private mutating func parseBareName(_ what: String) throws(DAXError) -> String {
        guard case .identifier(let name) = current.kind else { throw unexpected(what) }
        _ = next()
        return name
    }

    /// EVALUATE expr [ORDER BY expr [ASC|DESC], ...] [START AT expr, ...]
    private mutating func parseEvaluate() throws(DAXError) -> Evaluate {
        let table = try parseExpr()
        var orderBy: [OrderItem] = []
        if keyword("ORDER") && keyword("BY", at: 1) {
            _ = next()
            _ = next()
            var more = true
            while more {
                let expr = try parseExpr()
                var ascending = true
                if keyword("ASC") {
                    _ = next()
                } else if keyword("DESC") {
                    _ = next()
                    ascending = false
                }
                orderBy.append(OrderItem(expr: expr, ascending: ascending))
                more = isSymbol(",")
                if more { _ = next() }
            }
        }
        var startAt: [Expr] = []
        if keyword("START") && keyword("AT", at: 1) {
            _ = next()
            _ = next()
            var more = true
            while more {
                startAt.append(try parseExpr())
                more = isSymbol(",")
                if more { _ = next() }
            }
        }
        return Evaluate(table: table, orderBy: orderBy, startAt: startAt)
    }

    // MARK: - Biểu thức, từ ưu tiên thấp đến cao

    private mutating func parseExpr() throws(DAXError) -> Expr {
        try parseOr()
    }

    private mutating func parseOr() throws(DAXError) -> Expr {
        var left = try parseAnd()
        while isSymbol("||") {
            _ = next()
            let right = try parseAnd()
            left = .binary(.or, left, right, merge(left.range, right.range))
        }
        return left
    }

    private mutating func parseAnd() throws(DAXError) -> Expr {
        var left = try parseNot()
        while isSymbol("&&") {
            _ = next()
            let right = try parseNot()
            left = .binary(.and, left, right, merge(left.range, right.range))
        }
        return left
    }

    /// NOT ở mức này có ưu tiên thấp hơn so sánh: NOT a = b là NOT (a = b).
    /// NOT(...) có ngoặc là lời gọi hàm, xử lý ở parsePrimary.
    private mutating func parseNot() throws(DAXError) -> Expr {
        if isSymbol("!") || (keyword("NOT") && !isSymbol("(", at: 1)) {
            let start = current
            _ = next()
            let operand = try parseNot()
            return .unary(.not, operand, spanFrom(start))
        }
        return try parseComparison()
    }

    private mutating func parseComparison() throws(DAXError) -> Expr {
        var left = try parseConcat()
        while true {
            if let op = comparisonOperator() {
                _ = next()
                let right = try parseConcat()
                left = .binary(op, left, right, merge(left.range, right.range))
            } else if keyword("IN") {
                _ = next()
                let right = try parseConcat()
                left = .binary(.inSet, left, right, merge(left.range, right.range))
            } else {
                return left
            }
        }
    }

    private func comparisonOperator() -> BinaryOp? {
        guard case .symbol(let s) = current.kind else { return nil }
        switch s {
        case "=": return .equal
        case "==": return .strictEqual
        case "<>": return .notEqual
        case "<": return .less
        case ">": return .greater
        case "<=": return .lessEqual
        case ">=": return .greaterEqual
        default: return nil
        }
    }

    private mutating func parseConcat() throws(DAXError) -> Expr {
        var left = try parseAdditive()
        while isSymbol("&") {
            _ = next()
            let right = try parseAdditive()
            left = .binary(.concat, left, right, merge(left.range, right.range))
        }
        return left
    }

    private mutating func parseAdditive() throws(DAXError) -> Expr {
        var left = try parseMultiplicative()
        while isSymbol("+") || isSymbol("-") {
            let op: BinaryOp = isSymbol("+") ? .add : .subtract
            _ = next()
            let right = try parseMultiplicative()
            left = .binary(op, left, right, merge(left.range, right.range))
        }
        return left
    }

    private mutating func parseMultiplicative() throws(DAXError) -> Expr {
        var left = try parseUnary()
        while isSymbol("*") || isSymbol("/") {
            let op: BinaryOp = isSymbol("*") ? .multiply : .divide
            _ = next()
            let right = try parseUnary()
            left = .binary(op, left, right, merge(left.range, right.range))
        }
        return left
    }

    private mutating func parseUnary() throws(DAXError) -> Expr {
        if isSymbol("-") || isSymbol("+") {
            let start = current
            let op: UnaryOp = isSymbol("-") ? .negate : .plus
            _ = next()
            let operand = try parseUnary()
            return .unary(op, operand, spanFrom(start))
        }
        return try parsePower()
    }

    private mutating func parsePower() throws(DAXError) -> Expr {
        var left = try parsePrimary()
        while isSymbol("^") {
            _ = next()
            let right = try parsePowerOperand()
            left = .binary(.power, left, right, merge(left.range, right.range))
        }
        return left
    }

    /// Vế phải của ^: cho phép dấu một ngôi (2^-1) nhưng không cho nhân hay cộng không ngoặc.
    private mutating func parsePowerOperand() throws(DAXError) -> Expr {
        if isSymbol("-") || isSymbol("+") {
            let start = current
            let op: UnaryOp = isSymbol("-") ? .negate : .plus
            _ = next()
            let operand = try parsePowerOperand()
            return .unary(op, operand, spanFrom(start))
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws(DAXError) -> Expr {
        let start = current
        switch start.kind {
        case .number(let value, let isInteger):
            _ = next()
            return .number(value, isInteger: isInteger, start.range)

        case .string(let text):
            _ = next()
            return .string(text, start.range)

        case .symbol("("):
            _ = next()
            let inner = try parseExpr()
            try expectSymbol(")")
            return inner

        case .symbol("{"):
            return try parseTableConstructor()

        case .bracket(let name):
            _ = next()
            return .bracketRef(name: name, start.range)

        case .quoted(let table):
            _ = next()
            if case .bracket(let column) = current.kind {
                _ = next()
                return .columnRef(table: table, column: column, spanFrom(start))
            }
            return .tableRef(table, start.range)

        case .identifier(let name):
            let upper = name.uppercased()
            // Từ khoá của câu lệnh không thể bắt đầu một biểu thức (thường gặp khi thân measure rỗng).
            if ["DEFINE", "EVALUATE", "MEASURE", "RETURN"].contains(upper) && !isSymbol("(", at: 1) {
                throw unexpected("biểu thức")
            }
            if upper == "VAR" && !isSymbol("(", at: 1) {
                return try parseVarBlock()
            }
            if upper == "NOT" && !isSymbol("(", at: 1) {
                _ = next()
                let operand = try parseComparison()
                return .unary(.not, operand, spanFrom(start))
            }
            _ = next()
            if isSymbol("(") {
                _ = next()
                let args = try parseArguments()
                return .call(name: name, args: args, spanFrom(start))
            }
            if upper == "TRUE" || upper == "FALSE" {
                return .boolean(upper == "TRUE", start.range)
            }
            if case .bracket(let column) = current.kind {
                _ = next()
                return .columnRef(table: name, column: column, spanFrom(start))
            }
            return .identifier(name, start.range)

        case .symbol, .eof:
            throw unexpected("biểu thức")
        }
    }

    /// Đối số của lời gọi hàm, đã qua dấu "(". Đối số trống cho nil. Kết thúc sau ")".
    private mutating func parseArguments() throws(DAXError) -> [Expr?] {
        var args: [Expr?] = []
        if isSymbol(")") {
            _ = next()
            return args
        }
        while true {
            if isSymbol(",") || isSymbol(")") {
                args.append(nil)
            } else {
                args.append(try parseExpr())
            }
            if isSymbol(",") {
                _ = next()
                continue
            }
            try expectSymbol(")")
            return args
        }
    }

    /// VAR a = expr [VAR b = expr ...] RETURN expr. Thân kéo dài đến khi gặp ',' hoặc ')' cùng cấp.
    private mutating func parseVarBlock() throws(DAXError) -> Expr {
        let start = current
        _ = next()
        var vars: [VarBinding] = []
        while true {
            let name = try parseBareName("tên VAR")
            try expectSymbol("=")
            let value = try parseExpr()
            vars.append(VarBinding(name: name, value: value))
            if keyword("VAR") {
                _ = next()
                continue
            }
            if keyword("RETURN") {
                _ = next()
                break
            }
            throw unexpected("VAR hoặc RETURN")
        }
        let body = try parseExpr()
        return .varBlock(vars: vars, body: body, spanFrom(start))
    }

    /// { expr, ... } hoặc { (a, b), (c, d) ... }. Mục bắt đầu bằng '(' được thử là bộ giá trị trước,
    /// nếu không khớp thì quay lại và đọc như một biểu thức (ví dụ {(1) + 2}).
    private mutating func parseTableConstructor() throws(DAXError) -> Expr {
        let start = current
        _ = next()
        var rows: [[Expr]] = []
        if isSymbol("}") {
            _ = next()
            return .tableConstructor(rows: rows, spanFrom(start))
        }
        while true {
            var row: [Expr]?
            if isSymbol("(") {
                let save = pos
                do {
                    row = try parseTuple()
                    if !(isSymbol(",") || isSymbol("}")) {
                        row = nil
                    }
                } catch {
                    row = nil
                }
                if row == nil { pos = save }
            }
            if row == nil {
                row = [try parseExpr()]
            }
            rows.append(row ?? [])
            if isSymbol(",") {
                _ = next()
                continue
            }
            try expectSymbol("}")
            return .tableConstructor(rows: rows, spanFrom(start))
        }
    }

    /// (e1, e2, ...) đọc từ '(' đến ')'.
    private mutating func parseTuple() throws(DAXError) -> [Expr] {
        try expectSymbol("(")
        var items = [try parseExpr()]
        while isSymbol(",") {
            _ = next()
            items.append(try parseExpr())
        }
        try expectSymbol(")")
        return items
    }

    // MARK: - Tiện ích con trỏ

    private var current: DAXToken { tokens[pos] }

    private func token(at offset: Int) -> DAXToken {
        tokens[min(pos + offset, tokens.count - 1)]
    }

    private mutating func next() -> DAXToken {
        let t = tokens[pos]
        if pos < tokens.count - 1 { pos += 1 }
        return t
    }

    private func isSymbol(_ s: String, at offset: Int = 0) -> Bool {
        if case .symbol(let v) = token(at: offset).kind { return v == s }
        return false
    }

    private func keyword(_ word: String, at offset: Int = 0) -> Bool {
        if case .identifier(let v) = token(at: offset).kind { return v.uppercased() == word }
        return false
    }

    private func isBracketToken(at offset: Int) -> Bool {
        if case .bracket = token(at: offset).kind { return true }
        return false
    }

    private mutating func expectSymbol(_ s: String) throws(DAXError) {
        guard isSymbol(s) else { throw unexpected("'\(s)'") }
        _ = next()
    }

    /// Lỗi tại token hiện tại. Khi đã hết văn bản, thông báo nói "thiếu", trỏ về cuối token thật gần nhất.
    private func unexpected(_ expected: String) -> DAXError {
        if case .eof = current.kind {
            return DAXError(.syntax, "thiếu \(expected) ở cuối văn bản", range: current.range)
        }
        return DAXError(.syntax, "không mong đợi \(describe(current)), cần \(expected)", range: current.range)
    }

    private func describe(_ token: DAXToken) -> String {
        switch token.kind {
        case .number: return "số"
        case .string: return "chuỗi"
        case .quoted(let name): return "'\(name)'"
        case .bracket(let name): return "[\(name)]"
        case .identifier(let name): return "'\(name)'"
        case .symbol(let s): return "'\(s)'"
        case .eof: return "cuối văn bản"
        }
    }

    /// Vị trí từ đầu token `start` đến hết token vừa đọc.
    private func spanFrom(_ start: DAXToken) -> SourceRange {
        let end = tokens[max(pos - 1, 0)].range
        return SourceRange(start: start.range.start, end: end.end,
                           line: start.range.line, column: start.range.column)
    }

    private func merge(_ a: SourceRange, _ b: SourceRange) -> SourceRange {
        SourceRange(start: a.start, end: b.end, line: a.line, column: a.column)
    }
}
