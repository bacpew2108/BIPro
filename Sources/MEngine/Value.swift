// Phase F (T005): giá trị của ngôn ngữ M. Xem specs/010-f-get-data-power-query-t3/data-model.md, contracts/m-engine.md.

import ColumnStore
import Foundation

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
    /// Lỗi `Expression.Error` thông thường.
    public static func expression(_ message: String, detail: String? = nil) -> MError {
        MError(reason: "Expression.Error", message: message, detail: detail)
    }

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
    case type(MType)
    /// Giá trị nhị phân (`Binary.FromText`, `Binary.Decompress`; đợt tồn đọng sau Phase F, T026: M của Enter Data).
    case binary(Data)
    /// Giá trị lỗi nằm trong danh sách/bản ghi (chỉ ném khi truy cập phần tử đó).
    case error(MError)
}

/// Giá trị kiểu của M (`type text`, `Int64.Type`, `type table [A = number]`).
public struct MType: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case any, anynonnull, none, null, logical, number, int64, int32, int16, int8, double, decimal, currency, percentage
        case text, date, datetime, datetimezone, time, duration, binary, list, record, table, function, type
    }

    public var kind: Kind
    public var isNullable: Bool
    /// Trường của `record`/`table` (rỗng nếu không nêu).
    public var fields: [MTypeField]
    /// Kiểu phần tử của `list` (0 hoặc 1 phần tử; mảng để tránh đệ quy trực tiếp).
    public var listItem: [MType]

    public init(_ kind: Kind, isNullable: Bool = false, fields: [MTypeField] = [], listItem: [MType] = []) {
        self.kind = kind
        self.isNullable = isNullable || kind == .any || kind == .null
        self.fields = fields
        self.listItem = listItem
    }

    public var nullable: MType { var copy = self; copy.isNullable = true; return copy }
}

public struct MTypeField: Sendable, Equatable {
    public let name: String
    public let type: MType
    public let isOptional: Bool

    public init(name: String, type: MType, isOptional: Bool = false) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
    }
}

/// Hàm trong thư viện M. `observed == false` nghĩa là ngữ nghĩa chưa quan sát ở Desktop: [SUY ĐOÁN].
public struct MFunction: @unchecked Sendable {
    public let name: String
    public let parameters: [MParameter]
    public let observed: Bool
    /// Nhận đúng `parameters.count` đối số; tham số tuỳ chọn không có thì là `.null`.
    public let implementation: @Sendable ([MValue]) throws -> MValue

    public init(name: String, parameters: [MParameter], observed: Bool,
                implementation: @escaping @Sendable ([MValue]) throws -> MValue) {
        self.name = name
        self.parameters = parameters
        self.observed = observed
        self.implementation = implementation
    }
}

/// Đổi số M sang `Int` an toàn (lỗi T096: `Int(Double)` sập cả app với NaN, ±vô cực hoặc số quá lớn). Báo `Expression.Error` như Power Query
/// ("số nằm ngoài phạm vi") thay vì dừng chương trình. Phần thập phân bị cắt như `Int(_:)`.
public enum MInt {
    public static func from(_ value: Double, _ context: String) throws -> Int {
        guard value.isFinite, abs(value) <= 9_007_199_254_740_992 else {
            throw MError(reason: "Expression.Error", message: "\(context): số \(value) nằm ngoài phạm vi số nguyên")
        }
        return Int(value)
    }
}
