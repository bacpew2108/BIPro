// Phase F (T005): kiểu dùng chung của bộ phân tích và bộ chạy M. Parser: Parser.swift (T048), bộ chạy: Evaluator.swift (T049).
// Xem contracts/m-engine.md.

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

/// Môi trường tên → giá trị (các bước đã đánh giá, hàm thư viện).
public struct MEnvironment: Sendable {
    public var bindings: [String: MValue]

    public init(bindings: [String: MValue] = [:]) {
        self.bindings = bindings
    }
}

public enum MLibrary {
    /// Tên đầy đủ ("Table.SelectRows") → hàm. Gộp các nhóm; tên trùng giữa nhóm là lỗi lập trình (test `MLibraryTests` bắt).
    public static let functions: [String: MFunction] = {
        var table: [String: MFunction] = [:]
        for function in all { table[function.name] = function }
        return table
    }()

    static let all: [MFunction] = TableColumnsLibrary.functions + TableRowsLibrary.functions
        + ValueLibrary.functions + JoinGroupLibrary.functions + JsonLibrary.functions + BinaryLibrary.functions
}
