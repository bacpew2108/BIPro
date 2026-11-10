import PBIXKit

/// Loại trường mà một ô nhận: cột (kể cả cấp hierarchy) hoặc measure (kể cả cột có phép gộp).
enum WellKind: Hashable {
    case column, measure

    init?(_ kind: ReportField.Kind) {
        switch kind {
        case .column, .hierarchyLevel: self = .column
        case .measure, .aggregation: self = .measure
        case .other: return nil
        }
    }

    init(_ kind: FieldRef.Kind) { self = kind == .column ? .column : .measure }

    var label: String { self == .column ? "cột" : "measure" }
}

/// Luật của một ô trường (`specs/003-d2-build-pane-field-well/research.md` R5).
struct WellRule: Equatable {
    enum Status: Equatable {
        /// Tổ hợp (loại visual, ô) đã có trong file thật của Nhom6 hoặc đã quan sát ở buổi VM-D2.
        case observed
        /// Ô hiện ra nhưng chưa cho thêm trường: chưa kiểm với Power BI Desktop.
        case unverified
    }

    let role: String
    let label: String
    let accepts: Set<WellKind>
    /// Ô một trường: thêm trường mới thì thay các trường cũ.
    let isSingle: Bool
    let status: Status
}

enum WellRules {
    /// Bảng đã quan sát: (loại visual, ô) → (loại trường nhận, ô một trường). Nguồn: research R1.
    private static let observed: [String: [String: (kind: WellKind, single: Bool)]] = [
        "card": ["Values": (.measure, true)],
        "slicer": ["Values": (.column, true)],
        "clusteredBarChart": ["Category": (.column, true), "Y": (.measure, false), "Series": (.column, true), "Tooltips": (.measure, false)],
        "donutChart": ["Category": (.column, true), "Y": (.measure, true), "Tooltips": (.measure, false)],
        "hundredPercentStackedColumnChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false)],
        "lineChart": ["Category": (.column, true), "Series": (.column, true), "Tooltips": (.measure, false), "Y": (.measure, false)],
        "lineClusteredColumnComboChart": ["Category": (.column, true), "Tooltips": (.measure, false), "Y": (.measure, false), "Y2": (.measure, false)],
        "lineStackedColumnComboChart": ["Category": (.column, true), "Series": (.column, true), "Tooltips": (.measure, false),
                                        "Y": (.measure, false), "Y2": (.measure, false)],
        "pivotTable": ["Columns": (.column, true), "Rows": (.column, true), "Values": (.measure, false)],
        "shapeMap": ["Category": (.column, true), "Tooltips": (.measure, false)],
        "treemap": ["Group": (.column, true), "Tooltips": (.measure, false), "Values": (.measure, true)],
    ]

    /// Các ô của visual, theo thứ tự hiện trong Build pane, mỗi ô kèm luật.
    static func rules(for visual: ReportVisual) -> [WellRule] {
        VisualCatalog.wells(for: visual).map { well in
            if let hit = observed[visual.type]?[well.role] {
                return WellRule(role: well.role, label: well.label, accepts: [hit.kind], isSingle: hit.single, status: .observed)
            }
            return WellRule(role: well.role, label: well.label, accepts: [.column, .measure], isSingle: false, status: .unverified)
        }
    }

    static func rule(for visual: ReportVisual, role: String) -> WellRule? {
        rules(for: visual).first { $0.role == role }
    }

    /// Ô mặc định khi người dùng tick một trường ở pane Dữ liệu: ô đầu tiên (theo thứ tự trong Build pane) nhận được
    /// trường, ưu tiên ô khác Chú thích công cụ. Nil nếu không có ô nào nhận.
    static func defaultRole(for field: FieldRef, in visual: ReportVisual) -> String? {
        let candidates = rules(for: visual).filter { refusal(adding: field, to: $0.role, in: visual) == nil }
        return (candidates.first { $0.role != "Tooltips" } ?? candidates.first)?.role
    }

    // MARK: Từ chối

    static let unverifiedReason = "Ô này chưa kiểm với Power BI Desktop (buổi VM-D2), nên chưa thêm trường được."
    static let aggregationReason = "Cột số cần phép gộp (Sum, Average…): chưa làm, đang chờ quan sát Power BI Desktop (D2b)."

    /// Lý do không thêm được `field` vào ô `role` của `visual`, hoặc nil nếu thêm được.
    static func refusal(adding field: FieldRef, to role: String, in visual: ReportVisual) -> String? {
        guard let rule = rule(for: visual, role: role) else { return "Visual này không có ô \"\(role)\"." }
        guard rule.status == .observed else { return unverifiedReason }
        let kind = WellKind(field.kind)
        guard rule.accepts.contains(kind) else {
            if kind == .column, rule.accepts == [.measure], field.family == .numeric { return aggregationReason }
            return "Ô \"\(rule.label)\" chỉ nhận \(rule.accepts.map(\.label).sorted().joined(separator: " hoặc "))."
        }
        if visual.fields.contains(where: { $0.role == role && $0.queryRef == field.queryRef }) {
            return "Trường \"\(field.property)\" đã có trong ô \"\(rule.label)\"."
        }
        return nil
    }

    /// Lý do không chuyển được `field` (đang ở một ô của `visual`) sang ô `role`, hoặc nil.
    static func refusal(moving field: ReportField, to role: String, in visual: ReportVisual) -> String? {
        guard let rule = rule(for: visual, role: role) else { return "Visual này không có ô \"\(role)\"." }
        guard rule.status == .observed else { return unverifiedReason }
        guard let kind = WellKind(field.kind), rule.accepts.contains(kind) else {
            return "Ô \"\(rule.label)\" không nhận loại trường này."
        }
        if field.role != role, visual.fields.contains(where: { $0.role == role && $0.queryRef == field.queryRef }) {
            return "Trường \"\(field.property)\" đã có trong ô \"\(rule.label)\"."
        }
        return nil
    }
}
