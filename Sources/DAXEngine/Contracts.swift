// Contract của target DAXEngine (Phase B, đợt 0). Lead sở hữu; đóng băng sau đợt 0.
// Muốn đổi thì gửi yêu cầu cho lead, tối đa một lần mỗi đợt (docs/PHASE_B_PLAN.md §3.2).
// Chi tiết ngữ nghĩa: docs/phase-b-research/architecture.md §4–5 và §8.3.

import ColumnStore

// MARK: - Lỗi và vị trí

/// Vị trí trong văn bản truy vấn. `start`/`end` là offset UTF-16; `line`/`column` đếm từ 1.
/// Cách đếm cột với tab được chốt theo kết quả O3 (docs/phase-b-oracle/CHECKLIST.md).
public struct SourceRange: Sendable, Hashable {
    public let start: Int
    public let end: Int
    public let line: Int
    public let column: Int

    public init(start: Int, end: Int, line: Int, column: Int) {
        self.start = start
        self.end = end
        self.line = line
        self.column = column
    }
}

/// Lỗi DAX. `Kind` đóng băng; chi tiết nằm trong `message`.
public struct DAXError: Error, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case syntax, unknownName, unsupportedFunction, arity, typeMismatch, expectedColumnRef
        case circularDependency, ambiguousPath, multipleValues, runtime, cancelled
    }

    public let kind: Kind
    public let message: String
    public let range: SourceRange?

    public init(_ kind: Kind, _ message: String, range: SourceRange? = nil) {
        self.kind = kind
        self.message = message
        self.range = range
    }

    /// Hàm chưa được cài đặt (dùng cho stub của đợt 0).
    public static func unsupported(_ name: String) -> DAXError {
        DAXError(.unsupportedFunction, "\(name) chưa được hỗ trợ")
    }
}

// MARK: - Giá trị runtime

/// Giá trị DAX lúc chạy. Cùng hình dạng với `ColumnStore.StoredValue`.
public enum Value: Sendable, Hashable {
    case blank
    case integer(Int64)
    case double(Double)
    case currency(Int64)
    case string(String)
    case boolean(Bool)
    case dateTime(Double)

    public init(stored: StoredValue) {
        switch stored {
        case .blank: self = .blank
        case .integer(let v): self = .integer(v)
        case .double(let v): self = .double(v)
        case .currency(let v): self = .currency(v)
        case .string(let v): self = .string(v)
        case .boolean(let v): self = .boolean(v)
        case .dateTime(let v): self = .dateTime(v)
        }
    }
}

public struct MeasureID: Hashable, Sendable {
    public let raw: Int32
    public init(raw: Int32) { self.raw = raw }
}

public struct FunctionID: Hashable, Sendable {
    public let raw: Int32
    public init(raw: Int32) { self.raw = raw }
}

// MARK: - Biểu thức đã bind

public enum UnaryOp: String, Sendable, Hashable {
    case negate = "-", plus = "+", not = "NOT"
}

public enum BinaryOp: String, Sendable, Hashable {
    case add = "+", subtract = "-", multiply = "*", divide = "/", power = "^", concat = "&"
    case equal = "=", strictEqual = "==", notEqual = "<>", less = "<", greater = ">"
    case lessEqual = "<=", greaterEqual = ">=", and = "&&", or = "||", inSet = "IN"
}

/// Biểu thức sau khi bind. `nil` trong đối số nghĩa là đối số bỏ trống (`RANKX(…, , DESC)`).
public indirect enum BoundExpr: Sendable {
    case literal(Value)
    case column(ColumnID)                         // cần row context
    case virtualColumn(name: String)              // cột ảo [@c] của bảng đang lặp
    case table(TableID)
    case measure(MeasureID)
    case variable(slot: Int)
    case call(FunctionID, [BoundExpr?])
    case unary(UnaryOp, BoundExpr)
    case binary(BinaryOp, BoundExpr, BoundExpr)
    case varBlock(slots: [Int], values: [BoundExpr], body: BoundExpr)
    case tableConstructor(columns: Int, rows: [[BoundExpr]])
    case keyword(String)                          // DESC, DENSE, YEAR, MONTH…
}

// MARK: - Khai báo hàm

public enum ParamKind: Sendable, Hashable {
    case scalar                  // đánh giá sẵn thành Value (eager)
    case lazyScalar              // hàm tự gọi frame.scalar(i, in:) (IF, SWITCH, thân iterator)
    case table                   // biểu thức bảng
    case columnRef               // phải là tham chiếu cột (ALL, VALUES, TREATAS đích, USERELATIONSHIP)
    case tableOrColumnRef        // bảng hoặc cột
    case columnOrScalar          // MIN/MAX: cột hoặc giá trị
    case filter                  // đối số bộ lọc của CALCULATE
    case keyword([String])       // ASC/DESC, DENSE/SKIP, DAY/MONTH/YEAR…
}

public struct Param: Sendable, Hashable {
    public let name: String
    public let kind: ParamKind
    public let optional: Bool
    public let repeats: Bool

    public init(name: String, kind: ParamKind, optional: Bool = false, repeats: Bool = false) {
        self.name = name
        self.kind = kind
        self.optional = optional
        self.repeats = repeats
    }

    public static func scalar(_ name: String, optional: Bool = false, repeats: Bool = false) -> Param {
        Param(name: name, kind: .scalar, optional: optional, repeats: repeats)
    }

    public static func lazy(_ name: String, optional: Bool = false, repeats: Bool = false) -> Param {
        Param(name: name, kind: .lazyScalar, optional: optional, repeats: repeats)
    }

    public static func table(_ name: String, optional: Bool = false, repeats: Bool = false) -> Param {
        Param(name: name, kind: .table, optional: optional, repeats: repeats)
    }

    public static func column(_ name: String, optional: Bool = false, repeats: Bool = false) -> Param {
        Param(name: name, kind: .columnRef, optional: optional, repeats: repeats)
    }

    public static func tableOrColumn(_ name: String, optional: Bool = false, repeats: Bool = false) -> Param {
        Param(name: name, kind: .tableOrColumnRef, optional: optional, repeats: repeats)
    }

    public static func columnOrScalar(_ name: String, optional: Bool = false, repeats: Bool = false) -> Param {
        Param(name: name, kind: .columnOrScalar, optional: optional, repeats: repeats)
    }

    public static func filter(_ name: String, optional: Bool = false, repeats: Bool = false) -> Param {
        Param(name: name, kind: .filter, optional: optional, repeats: repeats)
    }

    public static func keyword(_ name: String, _ words: [String], optional: Bool = false) -> Param {
        Param(name: name, kind: .keyword(words), optional: optional, repeats: false)
    }
}

/// Đối số đã bind và ngữ cảnh gọi, đưa cho thân hàm.
public struct CallFrame: Sendable {
    public let args: [BoundExpr?]
    public let ctx: EvalContext
    public let eval: any Evaluating

    public init(args: [BoundExpr?], ctx: EvalContext, eval: any Evaluating) {
        self.args = args
        self.ctx = ctx
        self.eval = eval
    }

    public func isBlankArgument(_ i: Int) -> Bool {
        guard i >= 0, i < args.count else { return true }
        return args[i] == nil
    }

    public func scalar(_ i: Int) throws(DAXError) -> Value {
        try scalar(i, in: ctx)
    }

    public func scalar(_ i: Int, in ctx: EvalContext) throws(DAXError) -> Value {
        guard let expr = argument(i) else { throw DAXError(.arity, "đối số \(i + 1) bị bỏ trống") }
        return try eval.scalar(expr, in: ctx)
    }

    public func table(_ i: Int) throws(DAXError) -> TableValue {
        guard let expr = argument(i) else { throw DAXError(.arity, "đối số \(i + 1) bị bỏ trống") }
        return try eval.table(expr, in: ctx)
    }

    public func column(_ i: Int) throws(DAXError) -> ColumnID {
        guard let expr = argument(i) else { throw DAXError(.arity, "đối số \(i + 1) bị bỏ trống") }
        return try eval.column(expr, in: ctx)
    }

    public func keyword(_ i: Int) -> String? {
        guard let expr = argument(i), case .keyword(let word) = expr else { return nil }
        return word
    }

    /// Đẩy row frame và shadow cho từng dòng của `table`, rồi gọi `body`.
    public func iterate(_ table: TableValue, _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError) {
        try eval.iterate(table, in: ctx, body)
    }

    private func argument(_ i: Int) -> BoundExpr? {
        guard i >= 0, i < args.count else { return nil }
        return args[i]
    }
}

public enum ImplKind: Sendable { case scalar, table, modifier }

public struct FunctionSpec: Sendable {
    public typealias ScalarBody = @Sendable (CallFrame) throws(DAXError) -> Value
    public typealias TableBody = @Sendable (CallFrame) throws(DAXError) -> TableValue
    public typealias ModifierBody = @Sendable (CallFrame) throws(DAXError) -> [ContextModifier]

    public enum Impl: Sendable {
        case scalar(ScalarBody)
        case table(TableBody)
        case modifier(ModifierBody)
    }

    /// Tên viết hoa, ví dụ `SUMX`. `PERCENTILEX.INC` giữ nguyên dấu chấm.
    public let name: String
    public let params: [Param]
    public let impl: Impl

    public init(name: String, params: [Param], impl: Impl) {
        self.name = name
        self.params = params
        self.impl = impl
    }

    /// Chữ ký có thân báo chưa hỗ trợ. Đợt 0 dùng cho mọi hàm; mỗi agent thay bằng thân thật.
    public static func pending(_ name: String, _ params: [Param], _ kind: ImplKind) -> FunctionSpec {
        let impl: Impl
        switch kind {
        case .scalar:
            impl = .scalar { (_: CallFrame) throws(DAXError) -> Value in throw DAXError.unsupported(name) }
        case .table:
            impl = .table { (_: CallFrame) throws(DAXError) -> TableValue in throw DAXError.unsupported(name) }
        case .modifier:
            impl = .modifier { (_: CallFrame) throws(DAXError) -> [ContextModifier] in throw DAXError.unsupported(name) }
        }
        return FunctionSpec(name: name, params: params, impl: impl)
    }
}

/// Mỗi họ hàm là một enum không có case, với mảng tĩnh `functions`. Không có đăng ký động.
public protocol FunctionFamily {
    static var functions: [FunctionSpec] { get }
}

// MARK: - Ngữ cảnh

public struct RowContext: Sendable, Hashable {
    public let table: TableID
    public let row: Int

    public init(table: TableID, row: Int) {
        self.table = table
        self.row = row
    }
}

public struct EvalContext: Sendable {
    public var filter: FilterContext
    public var row: RowContext?

    public init(filter: FilterContext = .empty, row: RowContext? = nil) {
        self.filter = filter
        self.row = row
    }
}

/// Một mục bộ lọc theo cột: các giá trị được phép.
public struct FilterItem: Sendable, Hashable {
    public let column: ColumnID
    public let values: [Value]

    public init(column: ColumnID, values: [Value]) {
        self.column = column
        self.values = values
    }
}

public enum CrossFilterMode: String, Sendable, Hashable {
    case oneDirection, bothDirections, none
}

/// Thay đổi ngữ cảnh do một hàm bộ sửa đổi (CALCULATE, REMOVEFILTERS, USERELATIONSHIP…) tạo ra.
public enum ContextModifier: Sendable {
    case filter(FilterItem, keep: Bool)
    case removeColumns([ColumnID])
    case removeExpandedTable(TableID)
    case removeAll
    case allSelected(columns: [ColumnID]?)        // nil = ALLSELECTED()
    case useRelationship(RelationshipID)
    case crossFilter(RelationshipID, CrossFilterMode)
}

/// Dịch vụ đánh giá mà `CallFrame` gọi xuống. `Evaluator` (CORE) là bản cài đặt duy nhất.
public protocol Evaluating: Sendable {
    func scalar(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> Value
    func table(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> TableValue
    func column(_ expr: BoundExpr, in ctx: EvalContext) throws(DAXError) -> ColumnID
    func iterate(_ table: TableValue, in ctx: EvalContext,
                 _ body: (EvalContext) throws(DAXError) -> Void) throws(DAXError)
}

// MARK: - Kết quả truy vấn

public struct ResultTable: Sendable, Hashable {
    public let columns: [String]
    public let rows: [[Value]]
    /// `true` khi số dòng vượt giới hạn hiển thị và bị cắt.
    public let isTruncated: Bool

    public init(columns: [String], rows: [[Value]], isTruncated: Bool = false) {
        self.columns = columns
        self.rows = rows
        self.isTruncated = isTruncated
    }
}

public struct QueryResult: Sendable, Hashable {
    /// Mỗi EVALUATE một bảng kết quả, theo thứ tự xuất hiện.
    public let tables: [ResultTable]
    public let elapsedNanoseconds: UInt64

    public init(tables: [ResultTable], elapsedNanoseconds: UInt64) {
        self.tables = tables
        self.elapsedNanoseconds = elapsedNanoseconds
    }
}
