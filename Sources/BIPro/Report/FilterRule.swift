// Gói A (Phase C): bộ lọc Advanced (một hay hai điều kiện nối AND/OR) và Top N của Filters pane.
//
// Văn bản DAX sinh ra là biểu thức logic trên một cột (như `UserFilter.predicate` của Basic), do `DAXQueryBuilder` đặt vào
// `FILTER(KEEPFILTERS(...), <vị từ>)`. [SUY ĐOÁN] Chưa quan sát văn bản truy vấn Power BI sinh cho Advanced và Top N
// (docs/phase-c-oracle/VM-TODO-C2.md), nên kết quả đúng nghĩa nhưng văn bản có thể khác.
import DAXEngine
import Foundation
import PBIXKit

enum ComparisonKind: String, CaseIterable, Hashable, Sendable {
    case isEqual, isNot, lessThan, lessOrEqual, greaterThan, greaterOrEqual
    case contains, doesNotContain, startsWith, doesNotStartWith, isBlank, isNotBlank

    var title: String {
        switch self {
        case .isEqual: "là"
        case .isNot: "không phải"
        case .lessThan: "nhỏ hơn"
        case .lessOrEqual: "nhỏ hơn hoặc bằng"
        case .greaterThan: "lớn hơn"
        case .greaterOrEqual: "lớn hơn hoặc bằng"
        case .contains: "chứa"
        case .doesNotContain: "không chứa"
        case .startsWith: "bắt đầu bằng"
        case .doesNotStartWith: "không bắt đầu bằng"
        case .isBlank: "trống"
        case .isNotBlank: "không trống"
        }
    }

    var needsOperand: Bool { self != .isBlank && self != .isNotBlank }

    /// Phép có trong Power BI: cột chữ có chứa/bắt đầu bằng, cột số có so sánh thứ tự.
    static func available(numeric: Bool) -> [ComparisonKind] {
        numeric
            ? [.lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .isEqual, .isNot, .isBlank, .isNotBlank]
            : [.contains, .doesNotContain, .startsWith, .doesNotStartWith, .isEqual, .isNot, .isBlank, .isNotBlank]
    }
}

struct FilterCondition: Hashable, Sendable {
    var kind: ComparisonKind
    var operand: String

    /// Vị từ DAX trên `column`. nil khi chưa đủ (thiếu toán hạng, hoặc cột số mà toán hạng không phải số).
    func predicate(column: QueryColumn, numeric: Bool) -> String? { predicate(expression: column.dax, numeric: numeric) }

    /// Như trên nhưng trên một biểu thức bất kỳ (cột, hoặc cột kết quả `[ValueFilterDM0]` của bộ lọc theo measure).
    func predicate(expression col: String, numeric: Bool) -> String? {
        guard kind.needsOperand else { return kind == .isBlank ? "ISBLANK(\(col))" : "NOT(ISBLANK(\(col)))" }
        let text = operand.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let literal: String
        if numeric {
            guard let n = Double(text) else { return nil }
            literal = n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        } else {
            literal = "\"" + operand.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        switch kind {
        case .isEqual: return "\(col) = \(literal)"
        case .isNot: return "\(col) <> \(literal)"
        case .lessThan: return "\(col) < \(literal)"
        case .lessOrEqual: return "\(col) <= \(literal)"
        case .greaterThan: return "\(col) > \(literal)"
        case .greaterOrEqual: return "\(col) >= \(literal)"
        case .contains: return "SEARCH(\(literal), \(col), 1, 0) >= 1"
        case .doesNotContain: return "NOT(SEARCH(\(literal), \(col), 1, 0) >= 1)"
        case .startsWith: return "SEARCH(\(literal), \(col), 1, 0) = 1" // [SUY ĐOÁN] "contains" đã khớp Power BI (C2 A1); "starts with" chưa có mẫu
        case .doesNotStartWith: return "NOT(SEARCH(\(literal), \(col), 1, 0) = 1)"
        case .isBlank, .isNotBlank: return nil
        }
    }

    var summary: String { kind.needsOperand ? "\(kind.title) \(operand)" : kind.title }
}

struct TopNRule: Hashable, Sendable {
    var count: Int
    /// `true`: lấy N lớn nhất; `false`: N nhỏ nhất.
    var top: Bool
    var measureTable: String
    var measureName: String

    var measureRef: String { "'\(measureTable.replacingOccurrences(of: "'", with: "''"))'[\(measureName)]" }

    func predicate(column: QueryColumn) -> String? {
        guard count > 0, !measureName.isEmpty else { return nil }
        // Bỏ mục mà measure là BLANK (không có giá trị): nếu không, Bottom N sẽ chọn toàn mục rỗng mà visual không vẽ.
        return "\(column.dax) IN TOPN(\(count), FILTER(ALL(\(column.dax)), NOT(ISBLANK(\(measureRef)))), \(measureRef), \(top ? "DESC" : "ASC"))"
    }

    var summary: String { "\(top ? "Top" : "Bottom") \(count) theo \(measureName)" }
}

enum FilterRule: Hashable, Sendable {
    case advanced(first: FilterCondition, second: FilterCondition?, useOr: Bool, numeric: Bool)
    case topN(TopNRule)

    func predicate(column: QueryColumn) -> String? {
        switch self {
        case .topN(let rule): return rule.predicate(column: column)
        case .advanced: return predicate(expression: column.dax)
        }
    }

    /// Vị từ Advanced trên một biểu thức; Top N không có dạng này (nil).
    func predicate(expression: String) -> String? {
        guard case .advanced(let first, let second, let useOr, let numeric) = self else { return nil }
        guard let a = first.predicate(expression: expression, numeric: numeric) else { return nil }
        guard let second else { return a }
        // Điều kiện thứ hai còn dở thì chưa áp dụng cả bộ lọc, để không lọc nhầm một nửa.
        guard let b = second.predicate(expression: expression, numeric: numeric) else { return nil }
        return "\(useOr ? "OR" : "AND")(\(a), \(b))"
    }

    var summary: String {
        switch self {
        case .topN(let rule):
            return rule.summary
        case .advanced(let first, let second, let useOr, _):
            guard let second else { return first.summary }
            return "\(first.summary) \(useOr ? "hoặc" : "và") \(second.summary)"
        }
    }
}

// MARK: - Đọc từ file (PBIR)

extension FilterRule {
    /// Đọc điều kiện `Where[0].Condition` của bộ lọc Advanced: một so sánh, hoặc hai so sánh nối `And`/`Or`.
    /// nil nếu có dạng khác (nhiều hơn hai điều kiện, cột khác nhau, hàm lạ…).
    static func parseAdvanced(_ condition: JSONValue?) -> FilterRule? {
        guard let condition else { return nil }
        if let and = condition["And"] ?? condition["Or"] {
            guard let a = single(and["Left"]), let b = single(and["Right"]), a.numeric == b.numeric else { return nil }
            return .advanced(first: a.condition, second: b.condition, useOr: condition["Or"] != nil, numeric: a.numeric)
        }
        guard let one = single(condition) else { return nil }
        return .advanced(first: one.condition, second: nil, useOr: false, numeric: one.numeric)
    }

    private static func single(_ json: JSONValue?) -> (condition: FilterCondition, numeric: Bool)? {
        guard let json else { return nil }
        if let inner = json["Not"]?["Expression"] {
            guard let parsed = single(inner), let flipped = negated(parsed.condition.kind) else { return nil }
            return (FilterCondition(kind: flipped, operand: parsed.condition.operand), parsed.numeric)
        }
        if let comparison = json["Comparison"] {
            guard let kind = comparison["ComparisonKind"]?.number.map { Int($0) }, let right = literal(comparison["Right"]) else { return nil }
            let mapped: ComparisonKind
            switch kind {
            case 0: mapped = right.isNull ? .isBlank : .isEqual
            case 1: mapped = .greaterThan
            case 2: mapped = .greaterOrEqual
            case 3: mapped = .lessThan
            case 4: mapped = .lessOrEqual
            default: return nil
            }
            return (FilterCondition(kind: mapped, operand: right.text), right.numeric)
        }
        if let contains = json["Contains"], let right = literal(contains["Right"]) {
            return (FilterCondition(kind: .contains, operand: right.text), false)
        }
        if let starts = json["StartsWith"], let right = literal(starts["Right"]) {
            return (FilterCondition(kind: .startsWith, operand: right.text), false)
        }
        return nil
    }

    private static func negated(_ kind: ComparisonKind) -> ComparisonKind? {
        switch kind {
        case .isEqual: .isNot
        case .isBlank: .isNotBlank
        case .contains: .doesNotContain
        case .startsWith: .doesNotStartWith
        default: nil
        }
    }

    private static func literal(_ json: JSONValue?) -> (text: String, numeric: Bool, isNull: Bool)? {
        guard let raw = json?["Literal"]?["Value"]?.string else { return nil }
        switch ReportLiteral(literal: raw) {
        case .string(let s): return (s, false, false)
        case .number(let n): return (n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n), true, false)
        case .null: return ("", false, true)
        default: return nil
        }
    }
}
