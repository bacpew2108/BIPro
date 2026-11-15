// Phase F (T005): chữ ký bộ phân tích và bộ chạy M. Thân hàm là khung: ném "chưa hỗ trợ" cho đến khi cài
// (parser và evaluator do lead làm ở T048, T049). Xem contracts/m-engine.md.

import ColumnStore

public struct MSyntaxError: Error, Equatable, Sendable {
    public let line: Int
    public let column: Int
    public let message: String

    public init(line: Int, column: Int, message: String) {
        self.line = line
        self.column = column
        self.message = message
    }
}

/// Cây cú pháp của một biểu thức M. Khung: T048 thay bằng cây thật.
public struct MExpression: Sendable {
    public let source: String

    public init(source: String) {
        self.source = source
    }
}

public enum MParser {
    public static func parse(_ source: String) throws -> MExpression {
        throw MError.unsupported("MParser.parse")
    }
}

/// Môi trường tên → giá trị (các bước đã đánh giá, hàm thư viện).
public struct MEnvironment: Sendable {
    public var bindings: [String: MValue]

    public init(bindings: [String: MValue] = [:]) {
        self.bindings = bindings
    }
}

public struct MEvaluator: Sendable {
    public let environment: MEnvironment

    public init(environment: MEnvironment) {
        self.environment = environment
    }

    /// `step`: đánh giá đến hết bước này (xem trước ở bước giữa). `rowLimit`: gợi ý cắt sớm (xem trước 1000 dòng).
    public func evaluate(_ expression: MExpression, upTo step: String? = nil, rowLimit: Int? = nil) async throws -> MValue {
        throw MError.unsupported("MEvaluator.evaluate")
    }
}

public enum MLibrary {
    /// Tên đầy đủ ("Table.SelectRows") → hàm. Rỗng cho đến khi gói F-MFUN và lead cài hàm.
    public static var functions: [String: MFunction] { [:] }
}
