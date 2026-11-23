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
        case .isEqual: biN("là", "is")
        case .isNot: biN("không phải", "is not")
        case .lessThan: biN("nhỏ hơn", "is less than")
        case .lessOrEqual: biN("nhỏ hơn hoặc bằng", "is less than or equal to")
        case .greaterThan: biN("lớn hơn", "is greater than")
        case .greaterOrEqual: biN("lớn hơn hoặc bằng", "is greater than or equal to")
        case .contains: biN("chứa", "contains")
        case .doesNotContain: biN("không chứa", "does not contain")
        case .startsWith: biN("bắt đầu bằng", "starts with")
        case .doesNotStartWith: biN("không bắt đầu bằng", "does not start with")
        case .isBlank: biN("trống", "is blank")
        case .isNotBlank: biN("không trống", "is not blank")
        }
    }

    var needsOperand: Bool { self != .isBlank && self != .isNotBlank }

    /// Phép có trong Power BI: cột chữ có chứa/bắt đầu bằng, cột số/ngày có so sánh thứ tự.
    static func available(numeric: Bool, isDate: Bool = false) -> [ComparisonKind] {
        if isDate {
            return [.greaterThan, .greaterOrEqual, .lessThan, .lessOrEqual, .isEqual, .isNot, .isBlank, .isNotBlank]
        }
        return numeric
            ? [.lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .isEqual, .isNot, .isBlank, .isNotBlank]
            : [.contains, .doesNotContain, .startsWith, .doesNotStartWith, .isEqual, .isNot, .isBlank, .isNotBlank]
    }

    /// Nhãn hiển thị riêng cho cột ngày (sau / từ ngày / trước / đến ngày).
    @MainActor
    func title(isDate: Bool) -> String {
        guard isDate else { return title }
        switch self {
        case .isEqual: return bi("là ngày", "is")
        case .isNot: return bi("không phải ngày", "is not")
        case .greaterThan: return bi("sau ngày", "is after")
        case .greaterOrEqual: return bi("từ ngày trở đi", "is on or after")
        case .lessThan: return bi("trước ngày", "is before")
        case .lessOrEqual: return bi("đến ngày trở về trước", "is on or before")
        case .isBlank: return bi("trống", "is blank")
        case .isNotBlank: return bi("không trống", "is not blank")
        default: return title
        }
    }
}

struct FilterCondition: Hashable, Sendable {
    var kind: ComparisonKind
    var operand: String

    /// Vị từ DAX trên `column`. nil khi chưa đủ (thiếu toán hạng, hoặc cột số mà toán hạng không phải số).
    func predicate(column: QueryColumn, numeric: Bool) -> String? { predicate(expression: column.dax, numeric: numeric) }

    /// Như trên nhưng trên một biểu thức bất kỳ (cột, hoặc cột kết quả `[ValueFilterDM0]` của bộ lọc theo measure).
    func predicate(expression col: String, numeric: Bool, isDate: Bool = false) -> String? {
        guard kind.needsOperand else { return kind == .isBlank ? "ISBLANK(\(col))" : "NOT(ISBLANK(\(col)))" }
        let text = operand.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let literal: String
        if isDate {
            let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            literal = "DATE(\(parts[0]), \(parts[1]), \(parts[2]))"
        } else if numeric {
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
    case advanced(first: FilterCondition, second: FilterCondition?, useOr: Bool, numeric: Bool, isDate: Bool = false)
    case topN(TopNRule)

    func predicate(column: QueryColumn) -> String? {
        switch self {
        case .topN(let rule): return rule.predicate(column: column)
        case .advanced: return predicate(expression: column.dax)
        }
    }

    /// Vị từ Advanced trên một biểu thức; Top N không có dạng này (nil).
    func predicate(expression: String) -> String? {
        guard case .advanced(let first, let second, let useOr, let numeric, let isDate) = self else { return nil }
        guard let a = first.predicate(expression: expression, numeric: numeric, isDate: isDate) else { return nil }
        guard let second else { return a }
        // Điều kiện thứ hai còn dở thì chưa áp dụng cả bộ lọc, để không lọc nhầm một nửa.
        guard let b = second.predicate(expression: expression, numeric: numeric, isDate: isDate) else { return nil }
        return "\(useOr ? "OR" : "AND")(\(a), \(b))"
    }

    var summary: String {
        switch self {
        case .topN(let rule):
            return rule.summary
        case .advanced(let first, let second, let useOr, _, _):
            guard let second else { return first.summary }
            return "\(first.summary) \(useOr ? biN("hoặc", "or") : biN("và", "and")) \(second.summary)"
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
            guard let a = single(and["Left"]), let b = single(and["Right"]) else { return nil }
            let aTyped = a.condition.kind.needsOperand, bTyped = b.condition.kind.needsOperand
            guard !(aTyped && bTyped) || (a.numeric == b.numeric && a.isDate == b.isDate) else { return nil }
            let numeric = aTyped ? a.numeric : (bTyped ? b.numeric : false)
            let isDate = aTyped ? a.isDate : (bTyped ? b.isDate : false)
            return .advanced(first: a.condition, second: b.condition, useOr: condition["Or"] != nil, numeric: numeric, isDate: isDate)
        }
        guard let one = single(condition) else { return nil }
        return .advanced(first: one.condition, second: nil, useOr: false, numeric: one.numeric, isDate: one.isDate)
    }

    /// Đọc `filter` của thẻ Top N (VM-D6, VM-D8): truy vấn con trong `From` chọn `Top` giá trị theo một measure;
    /// `Direction` 2 là Top, 1 là Bottom. nil nếu có dạng khác.
    static func parseTopN(_ filter: JSONValue?) -> FilterRule? {
        let sources: [JSONValue] = filter?["From"]?.array ?? []
        guard let query = sources.compactMap({ $0["Expression"]?["Subquery"]?["Query"] }).first,
              let count = query["Top"]?.number, let order = query["OrderBy"]?.array, order.count == 1,
              let direction = order[0]["Direction"]?.number, direction == 1 || direction == 2,
              let measure = order[0]["Expression"]?["Measure"], let name = measure["Property"]?.string else { return nil }
        let source = measure["Expression"]?["SourceRef"]
        var table = source?["Entity"]?.string
        if table == nil, let alias = source?["Source"]?.string {
            let inner: [JSONValue] = query["From"]?.array ?? []
            table = inner.first { $0["Name"]?.string == alias }?["Entity"]?.string
        }
        guard let table else { return nil }
        return .topN(TopNRule(count: Int(count), top: direction == 2, measureTable: table, measureName: name))
    }

    private static func single(_ json: JSONValue?) -> (condition: FilterCondition, numeric: Bool, isDate: Bool)? {
        guard let json else { return nil }
        if let inner = json["Not"]?["Expression"] {
            guard let parsed = single(inner), let flipped = negated(parsed.condition.kind) else { return nil }
            return (FilterCondition(kind: flipped, operand: parsed.condition.operand), parsed.numeric, parsed.isDate)
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
            return (FilterCondition(kind: mapped, operand: right.text), right.numeric, right.isDate)
        }
        if let contains = json["Contains"], let right = literal(contains["Right"]) {
            return (FilterCondition(kind: .contains, operand: right.text), false, false)
        }
        if let starts = json["StartsWith"], let right = literal(starts["Right"]) {
            return (FilterCondition(kind: .startsWith, operand: right.text), false, false)
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

    private static func literal(_ json: JSONValue?) -> (text: String, numeric: Bool, isDate: Bool, isNull: Bool)? {
        guard let raw = json?["Literal"]?["Value"]?.string else { return nil }
        if raw.hasPrefix("datetime'") && raw.hasSuffix("'") {
            let iso = String(raw.dropFirst("datetime'".count).dropLast())
            return (String(iso.prefix(10)), false, true, false)
        }
        switch ReportLiteral(literal: raw) {
        case .string(let s): return (s, false, false, false)
        case .number(let n): return (n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n), true, false, false)
        case .null: return ("", false, false, true)
        default: return nil
        }
    }
}
