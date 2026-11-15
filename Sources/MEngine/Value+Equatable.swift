// Phase F (T049): so sánh cấu trúc của MValue (cho test và golden). Khác với toán tử `=` của M (xem Operators.swift).

import ColumnStore

extension MValue: Equatable {
    public static func == (lhs: MValue, rhs: MValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.logical(let a), .logical(let b)): a == b
        case (.number(let a), .number(let b)): a == b || (a.isNaN && b.isNaN)
        case (.currency(let a), .currency(let b)): a == b
        case (.text(let a), .text(let b)): a == b
        case (.date(let a), .date(let b)), (.time(let a), .time(let b)), (.dateTime(let a), .dateTime(let b)), (.duration(let a), .duration(let b)): a == b
        case (.list(let a), .list(let b)): a == b
        case (.record(let a), .record(let b)): a == b
        case (.table(let a), .table(let b)): MTables.identical(a, b)
        case (.function(let a), .function(let b)): a.name == b.name && a.parameters == b.parameters
        case (.type(let a), .type(let b)): a == b
        case (.error(let a), .error(let b)): a == b
        default: false
        }
    }
}

extension MField: Equatable {
    public static func == (lhs: MField, rhs: MField) -> Bool { lhs.name == rhs.name && lhs.value == rhs.value }
}
