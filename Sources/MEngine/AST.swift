// Phase F (T048): cây cú pháp của ngôn ngữ M (tập con ghi ở contracts/m-engine.md). Ngôn ngữ theo tài liệu công khai
// "Power Query M language specification" của Microsoft; mục nào chưa đối chiếu với Desktop ở VM-F3 đánh dấu [SUY ĐOÁN].

public enum MUnaryOp: String, Sendable, Equatable {
    case negate = "-", plus = "+", not = "not"
}

public enum MBinaryOp: String, Sendable, Equatable {
    case or, and
    case equal = "=", notEqual = "<>", less = "<", greater = ">", lessOrEqual = "<=", greaterOrEqual = ">="
    case add = "+", subtract = "-", concat = "&", multiply = "*", divide = "/"
}

/// `name = value` trong `let` hoặc bản ghi.
public struct MBinding: Sendable, Equatable {
    public let name: String
    public let value: MExpression

    public init(name: String, value: MExpression) {
        self.name = name
        self.value = value
    }
}

public struct MParameter: Sendable, Equatable {
    public let name: String
    public let isOptional: Bool
    public let type: MTypeExpr?

    public init(name: String, isOptional: Bool = false, type: MTypeExpr? = nil) {
        self.name = name
        self.isOptional = isOptional
        self.type = type
    }
}

/// Biểu thức kiểu (sau `as`, `is`, `type`).
public indirect enum MTypeExpr: Sendable, Equatable {
    /// `number`, `text`, `table`, `any`, ... (tên kiểu nguyên thuỷ).
    case primitive(String)
    case nullable(MTypeExpr)
    case list(MTypeExpr)
    case record([MTypeFieldExpr])
    case table([MTypeFieldExpr])
    case function
}

public struct MTypeFieldExpr: Sendable, Equatable {
    public let name: String
    public let type: MTypeExpr?
    public let isOptional: Bool

    public init(name: String, type: MTypeExpr?, isOptional: Bool = false) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
    }
}

public indirect enum MExpression: Sendable, Equatable {
    case null
    case logical(Bool)
    case number(Double)
    case text(String)
    /// Tên (đã bỏ `#"…"`). `_` là tham số ngầm của `each`. Dòng để báo "chưa hỗ trợ" kèm vị trí.
    case identifier(String, line: Int)
    /// Phần tử danh sách: `{1, 2, 5..8}`; `range` là `a..b`.
    case list([MExpression])
    case range(MExpression, MExpression)
    case record([MBinding])
    case letIn([MBinding], MExpression)
    case ifThenElse(MExpression, MExpression, MExpression)
    /// `(a, b) => body` hoặc `each body` (một tham số `_`).
    case function([MParameter], returnType: MTypeExpr?, body: MExpression)
    case invoke(MExpression, [MExpression], line: Int)
    /// `x[name]`, `x[name]?`, hoặc `[name]` (= `_[name]`).
    case fieldAccess(MExpression, String, optional: Bool)
    /// `x{index}`, `x{index}?`.
    case itemAccess(MExpression, MExpression, optional: Bool)
    case unary(MUnaryOp, MExpression)
    case binary(MBinaryOp, MExpression, MExpression)
    case isType(MExpression, MTypeExpr)
    case asType(MExpression, MTypeExpr)
    case tryOtherwise(MExpression, otherwise: MExpression?)
    case error(MExpression)
    case type(MTypeExpr)
}
