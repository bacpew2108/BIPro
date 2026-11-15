// Phase F (T049): kiểu của M: đổi biểu thức kiểu thành giá trị kiểu, kiểm giá trị thuộc kiểu, hằng `Int64.Type`...

extension MType {
    static let primitiveKinds: [String: Kind] = [
        "any": .any, "anynonnull": .anynonnull, "none": .none, "null": .null, "logical": .logical, "number": .number,
        "text": .text, "date": .date, "datetime": .datetime, "datetimezone": .datetimezone, "time": .time,
        "duration": .duration, "binary": .binary, "list": .list, "record": .record, "table": .table,
        "function": .function, "type": .type,
    ]

    /// Hằng kiểu của thư viện (`Int64.Type`, `Currency.Type`, ...).
    static let libraryConstants: [String: MType] = [
        "Any.Type": MType(.any), "Number.Type": MType(.number), "Int64.Type": MType(.int64), "Int32.Type": MType(.int32),
        "Int16.Type": MType(.int16), "Int8.Type": MType(.int8), "Double.Type": MType(.double), "Decimal.Type": MType(.decimal),
        "Currency.Type": MType(.currency), "Percentage.Type": MType(.percentage), "Text.Type": MType(.text),
        "Logical.Type": MType(.logical), "Date.Type": MType(.date), "DateTime.Type": MType(.datetime),
        "DateTimeZone.Type": MType(.datetimezone), "Time.Type": MType(.time), "Duration.Type": MType(.duration),
        "Binary.Type": MType(.binary), "List.Type": MType(.list), "Record.Type": MType(.record), "Table.Type": MType(.table),
        "Function.Type": MType(.function), "Type.Type": MType(.type), "None.Type": MType(.none), "Null.Type": MType(.null),
    ]

    static func resolve(_ expression: MTypeExpr) throws -> MType {
        switch expression {
        case .primitive(let name):
            if let constant = libraryConstants[name] { return constant }   // `Int64.Type` đứng ở vị trí kiểu
            guard let kind = primitiveKinds[name] else { throw MError.expression("Kiểu '\(name)' không tồn tại") }
            return MType(kind)
        case .nullable(let inner): return try resolve(inner).nullable
        case .list(let item): return MType(.list, listItem: [try resolve(item)])
        case .record(let fields): return MType(.record, fields: try resolveFields(fields))
        case .table(let fields): return MType(.table, fields: try resolveFields(fields))
        case .function: return MType(.function)
        }
    }

    private static func resolveFields(_ fields: [MTypeFieldExpr]) throws -> [MTypeField] {
        try fields.map { MTypeField(name: $0.name, type: try $0.type.map(resolve) ?? MType(.any), isOptional: $0.isOptional) }
    }

    /// Giá trị `value` có thuộc kiểu này không (kiểm nông: kiểu phần tử và cột chỉ kiểm tên khi nêu).
    func accepts(_ value: MValue) -> Bool {
        if case .null = value { return isNullable }
        switch kind {
        case .any: return true
        case .anynonnull: return true
        case .none, .null: return false
        case .number, .double, .decimal, .percentage:
            if case .number = value { return true }
            if case .currency = value { return true }
            return false
        case .currency:
            if case .currency = value { return true }
            if case .number = value { return true }
            return false
        case .int64, .int32, .int16, .int8:
            guard case .number(let d) = value, d == d.rounded() else { return false }
            let limit: Double = switch kind { case .int8: 127; case .int16: 32_767; case .int32: 2_147_483_647; default: 9.2e18 }
            return abs(d) <= limit
        case .text: if case .text = value { return true } else { return false }
        case .logical: if case .logical = value { return true } else { return false }
        case .date: if case .date = value { return true } else { return false }
        case .datetime, .datetimezone: if case .dateTime = value { return true } else { return false }
        case .time: if case .time = value { return true } else { return false }
        case .duration: if case .duration = value { return true } else { return false }
        case .binary: return false
        case .function: if case .function = value { return true } else { return false }
        case .type: if case .type = value { return true } else { return false }
        case .list:
            guard case .list(let items) = value else { return false }
            guard let item = listItem.first else { return true }
            return items.allSatisfy { item.accepts($0) }
        case .record:
            guard case .record(let fieldValues) = value else { return false }
            return fields.allSatisfy { f in f.isOptional || fieldValues.contains { $0.name == f.name } }
        case .table:
            guard case .table(let table) = value else { return false }
            return fields.allSatisfy { f in f.isOptional || table.index(ofColumn: f.name) != nil }
        }
    }
}

import ColumnStore

extension MValue {
    /// Tên kiểu dùng trong thông báo lỗi.
    var kindName: String {
        switch self {
        case .null: "null"
        case .logical: "logical"
        case .number, .currency: "number"
        case .text: "text"
        case .date: "date"
        case .time: "time"
        case .dateTime: "datetime"
        case .duration: "duration"
        case .list: "list"
        case .record: "record"
        case .table: "table"
        case .function: "function"
        case .type: "type"
        case .error: "error"
        }
    }
}
