// Phase F (T005): giá trị của ngôn ngữ M. Xem specs/010-f-get-data-power-query-t3/data-model.md, contracts/m-engine.md.

import ColumnStore

/// Lỗi của M. Là giá trị (ô lỗi, `try … otherwise`), không phải ngoại lệ Swift.
public struct MError: Error, Sendable, Equatable {
    public let reason: String
    public let message: String
    public let detail: String?

    public init(reason: String, message: String, detail: String? = nil) {
        self.reason = reason
        self.message = message
        self.detail = detail
    }

    /// Hàm hoặc cú pháp ngoài phạm vi Phase F: báo thẳng, không trả kết quả đoán (FR-031).
    public static func unsupported(_ name: String, line: Int? = nil) -> MError {
        let where_ = line.map { " (dòng \($0))" } ?? ""
        return MError(reason: "Expression.Unsupported", message: "Chưa hỗ trợ: \(name)\(where_)", detail: name)
    }
}

public struct MField: Sendable {
    public let name: String
    public let value: MValue

    public init(name: String, value: MValue) {
        self.name = name
        self.value = value
    }
}

public enum MValue: Sendable {
    case null
    case logical(Bool)
    case number(Double)
    /// Số thập phân cố định (kiểu tiền tệ / "Fixed decimal"): Int64 nhân 10⁴, như `DAXType.currency`.
    case currency(Int64)
    case text(String)
    /// Số ngày tính từ 1899-12-30, như `StoredValue.dateTime`.
    case date(Double)
    case time(Double)
    case dateTime(Double)
    case duration(Double)
    case list([MValue])
    case record([MField])
    case table(TableData)
    case function(MFunction)
    case error(MError)
}

/// Hàm trong thư viện M. `observed == false` nghĩa là ngữ nghĩa chưa quan sát ở Desktop: [SUY ĐOÁN].
public struct MFunction: @unchecked Sendable {
    public let name: String
    public let parameters: [String]
    public let observed: Bool
    public let implementation: @Sendable ([MValue]) throws -> MValue

    public init(name: String, parameters: [String], observed: Bool,
                implementation: @escaping @Sendable ([MValue]) throws -> MValue) {
        self.name = name
        self.parameters = parameters
        self.observed = observed
        self.implementation = implementation
    }
}
