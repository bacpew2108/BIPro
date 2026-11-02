// AST của DAX sau parse, trước bind. ĐÓNG BĂNG ở đợt 0 (lead). Theo architecture.md §5.2.

public struct VarBinding: Sendable, Hashable {
    public let name: String
    public let value: Expr

    public init(name: String, value: Expr) {
        self.name = name
        self.value = value
    }
}

public indirect enum Expr: Sendable, Hashable {
    case number(Double, isInteger: Bool, SourceRange)
    case string(String, SourceRange)
    case boolean(Bool, SourceRange)
    case columnRef(table: String?, column: String, SourceRange)     // T[c] hoặc [c]
    case bracketRef(name: String, SourceRange)                       // [x]: measure hoặc cột ảo, binder quyết
    case tableRef(String, SourceRange)
    case identifier(String, SourceRange)                             // tên VAR, hoặc từ khoá đối số (DESC, DENSE, YEAR)
    case call(name: String, args: [Expr?], SourceRange)             // nil = đối số bỏ trống
    case unary(UnaryOp, Expr, SourceRange)
    case binary(BinaryOp, Expr, Expr, SourceRange)
    case varBlock(vars: [VarBinding], body: Expr, SourceRange)
    case tableConstructor(rows: [[Expr]], SourceRange)               // {1,2} hoặc {(1,"a"),(2,"b")}
}

public struct OrderItem: Sendable, Hashable {
    public let expr: Expr
    public let ascending: Bool

    public init(expr: Expr, ascending: Bool) {
        self.expr = expr
        self.ascending = ascending
    }
}

public enum Definition: Sendable, Hashable {
    case measure(table: String, name: String, Expr)
    case variable(name: String, Expr)
    case column(table: String, name: String, Expr)
    case table(name: String, Expr)
}

public struct Evaluate: Sendable, Hashable {
    public var table: Expr
    public var orderBy: [OrderItem]
    public var startAt: [Expr]

    public init(table: Expr, orderBy: [OrderItem] = [], startAt: [Expr] = []) {
        self.table = table
        self.orderBy = orderBy
        self.startAt = startAt
    }
}

public struct Query: Sendable, Hashable {
    public var defines: [Definition]
    public var statements: [Evaluate]

    public init(defines: [Definition] = [], statements: [Evaluate] = []) {
        self.defines = defines
        self.statements = statements
    }
}
