// Gói P (Phase C đợt 3, lead): trạng thái xem do người dùng đặt, nằm trên bản đọc từ file.
//
// - `VisibilityState`: ẩn/hiện visual từ Selection pane và bookmark (ghi đè `ReportVisual.isHidden`, không ghi ngược vào file).
// - `UserFilter`: bộ lọc Basic (là / không phải một tập giá trị) người dùng sửa ở Filters pane, ghi đè hoặc thêm vào bộ lọc trong file.
import DAXEngine
import Foundation
import PBIXKit

// MARK: - Ẩn/hiện

struct VisibilityState: Hashable, Sendable {
    /// id visual → đang ẩn. Visual không có trong bảng dùng giá trị trong file.
    private(set) var overrides: [String: Bool] = [:]
    /// Bookmark đang áp dụng gần nhất (đánh dấu trong Bookmarks pane). Đổi ẩn/hiện tay thì xoá.
    private(set) var activeBookmarkID: String?

    func isHidden(_ visual: ReportVisual) -> Bool { overrides[visual.id] ?? visual.isHidden }

    mutating func setHidden(_ visualID: String, _ hidden: Bool) {
        overrides[visualID] = hidden
        activeBookmarkID = nil
    }

    mutating func toggle(_ visual: ReportVisual) { setHidden(visual.id, !isHidden(visual)) }

    /// Áp hiển thị của bookmark. Trả id trang cần chuyển tới (nil nếu bookmark không đổi trang).
    /// [QUAN SÁT] hai bookmark của Nhom6 có `suppressData` + `applyOnlyToTargetVisuals`: chỉ đổi ẩn/hiện của visual đích.
    /// [SUY ĐOÁN] bookmark không `suppressData` còn khôi phục bộ lọc/slicer; chưa làm (ghi ở docs/STATE.md).
    @discardableResult
    mutating func apply(_ bookmark: ReportBookmark) -> String? {
        for (id, hidden) in bookmark.hidden where bookmark.targetVisualNames.map({ $0.contains(id) }) ?? true {
            overrides[id] = hidden
        }
        activeBookmarkID = bookmark.id
        return bookmark.suppressActiveSection ? nil : bookmark.activeSection
    }
}

// MARK: - Bộ lọc Basic do người dùng sửa

/// Khoá của một thẻ bộ lọc: cấp, trang hoặc visual chứa nó, id bộ lọc (thẻ ngầm của field dùng id `implicit-…`).
struct UserFilterKey: Hashable, Sendable {
    var level: ReportFilter.Level
    /// id trang (cấp page), id visual (cấp visual), "" (cấp report).
    var scope: String
    var filterID: String
}

struct UserFilter: Hashable, Sendable {
    var column: QueryColumn
    var values: [Value]
    /// `false`: "là" (IN); `true`: "không phải" (NOT IN).
    var exclude: Bool
    /// Bộ lọc Advanced hoặc Top N. Có thì thay cho `values`/`exclude`.
    var rule: FilterRule?

    init(column: QueryColumn, values: [Value] = [], exclude: Bool = false, rule: FilterRule? = nil) {
        self.column = column
        self.values = values
        self.exclude = exclude
        self.rule = rule
    }

    /// Không chọn giá trị nào = "Tất cả" = không lọc. Advanced/Top N chưa đủ điều kiện cũng chưa lọc.
    var isActive: Bool { rule.map { $0.predicate(column: column) != nil } ?? !values.isEmpty }

    /// Vị từ DAX; nil khi không lọc. Giá trị xếp tăng dần như `FilterTranslator`.
    var predicate: String? {
        if let rule { return rule.predicate(column: column) }
        guard isActive else { return nil }
        let sorted = values.sorted(by: FilterTranslator.valuePrecedes)
        let inList = "\(column.dax) IN {\(sorted.map(FilterTranslator.literal).joined(separator: ", "))}"
        return exclude ? "NOT(\(inList))" : inList
    }

    /// Chữ tóm tắt như Power BI: `là 2016, 2017` / `không phải 9999`.
    var summary: String { summary(format: nil) }

    /// Như `summary`, giá trị hiện theo định dạng của cột (`format`, ví dụ `00":00"` → `17:00`).
    func summary(format: String?) -> String {
        if let rule, isActive { return rule.summary }
        guard isActive else { return "là (Tất cả)" }
        let text = values.sorted(by: FilterTranslator.valuePrecedes).map { Self.display($0, format: format) }.joined(separator: ", ")
        return (exclude ? "không phải " : "là ") + text
    }

    /// Giá trị theo định dạng của cột; không có định dạng thì như `display(_:)`.
    static func display(_ value: Value, format: String?) -> String {
        if case .blank = value { return display(value) }
        guard let format, !format.isEmpty else { return display(value) }
        return NumberDisplay.plain(DataCell(value, formatString: format))
    }

    static func display(_ value: Value) -> String {
        switch value {
        case .blank: "(Trống)"
        case .integer(let n): String(n)
        case .double(let d): d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        case .currency(let n): String(Double(n) / 10000)
        case .string(let s): s
        case .boolean(let b): b ? "True" : "False"
        case .dateTime(let d): String(d)
        }
    }

    /// Đọc bộ lọc Categorical `In` / `Not In` trong file thành dạng sửa được. nil nếu bộ lọc phức tạp hơn
    /// (Advanced, TopN, nhiều điều kiện…): khi đó thẻ chỉ hiện, chưa sửa được.
    static func from(_ filter: ReportFilter) -> UserFilter? {
        guard filter.type == "Categorical" || filter.type == "Advanced",
              let field = (filter.raw["field"] ?? filter.raw["expression"])?["Column"], let table = field["Expression"]?["SourceRef"]?["Entity"]?.string,
              let name = field["Property"]?.string else { return nil }
        let column = QueryColumn(table: table, column: name)
        if filter.type == "Advanced" {
            guard let conditions = filter.raw["filter"]?["Where"]?.array, conditions.count == 1,
                  let rule = FilterRule.parseAdvanced(conditions[0]["Condition"]) else { return nil }
            return UserFilter(column: column, rule: rule)
        }
        let conditions = filter.raw["filter"]?["Where"]?.array ?? []
        guard conditions.count == 1, var condition = conditions[0]["Condition"] else {
            return conditions.isEmpty ? UserFilter(column: column, values: [], exclude: false) : nil
        }
        var exclude = false
        if let inner = condition["Not"]?["Expression"] { condition = inner; exclude = true }
        guard let list = condition["In"]?["Values"]?.array else { return nil }
        var values: [Value] = []
        for entry in list {
            guard let value = Self.value(of: entry[0]) else { return nil }
            values.append(value)
        }
        return UserFilter(column: column, values: values, exclude: exclude)
    }

    /// Giá trị của một literal PBIR (`{"Literal":{"Value":"2016L"}}`). nil nếu không phải chữ, số, logic hoặc null.
    static func value(of json: JSONValue?) -> Value? {
        guard let raw = json?["Literal"]?["Value"]?.string else { return nil }
        switch ReportLiteral(literal: raw) {
        case .string(let s): return .string(s)
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? .integer(Int64(n)) : .double(n)
        case .bool(let b): return .boolean(b)
        case .null: return .blank
        default: return nil
        }
    }
}
