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

    init(_ kind: FieldRef.Kind) { self = kind == .measure ? .measure : .column }

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
    /// Bảng đã quan sát: (loại visual, ô) → (loại trường nhận, ô một trường). Nguồn: research R1 (Nhom6) và VM-D3
    /// (donut → treemap giữ cả ba cấp ở `Category`/`Group`, nên hai ô đó nhận nhiều cột).
    private static let observed: [String: [String: (kind: WellKind, single: Bool)]] = [
        "card": ["Values": (.measure, true)],
        // VM-D3 mục A, B: "Card" trong thư viện của Desktop ghi `cardVisual`, ô `Data`; mới thấy measure vào ô này.
        "cardVisual": ["Data": (.measure, false)],
        "slicer": ["Values": (.column, true)],
        // VM-D3 (`R-D3-t-clusteredColumn`, `-stackedColumn`): cột xếp chồng của Desktop có visualType `columnChart`.
        // VM-D9 mục 1: đổi đường sang cột nhóm, Desktop giữ `Tooltips`.
        "clusteredColumnChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false), "Tooltips": (.measure, false)],
        "columnChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false)],
        "clusteredBarChart": ["Category": (.column, true), "Y": (.measure, false), "Series": (.column, true), "Tooltips": (.measure, false)],
        "donutChart": ["Category": (.column, false), "Y": (.measure, false), "Tooltips": (.measure, false)],
        "hundredPercentStackedColumnChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false)],
        "lineChart": ["Category": (.column, true), "Series": (.column, true), "Tooltips": (.measure, false), "Y": (.measure, false),
                      "Y2": (.measure, false)],   // VM-D3: combo → đường giữ Y2 ("Trục Y phụ")
        "lineClusteredColumnComboChart": ["Category": (.column, true), "Tooltips": (.measure, false), "Y": (.measure, false), "Y2": (.measure, false)],
        "lineStackedColumnComboChart": ["Category": (.column, true), "Series": (.column, true), "Tooltips": (.measure, false),
                                        "Y": (.measure, false), "Y2": (.measure, false)],
        // VM-D15 mục 4 (VM-D12 `retype-*`, tạo mới trong Desktop): vùng và ruy-băng có Category, Series (Legend), Y, Tooltips;
        // thác nước có Category, Breakdown, Y, Tooltips (VM-D16 mục 3), phễu Category, Y, Tooltips.
        "areaChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false), "Y2": (.measure, false), "Tooltips": (.measure, false)],
        "hundredPercentStackedAreaChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false), "Y2": (.measure, false), "Tooltips": (.measure, false)],
        "stackedAreaChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false), "Y2": (.measure, false), "Tooltips": (.measure, false)],
        "ribbonChart": ["Category": (.column, true), "Series": (.column, true), "Y": (.measure, false), "Tooltips": (.measure, false)],
        "waterfallChart": ["Category": (.column, true), "Breakdown": (.column, true), "Y": (.measure, false), "Tooltips": (.measure, false)],
        "funnel": ["Category": (.column, false), "Y": (.measure, false), "Tooltips": (.measure, false)],
        "pivotTable": ["Columns": (.column, true), "Rows": (.column, true), "Values": (.measure, false)],
        // VM-D12: bản đồ hình tạo trong Desktop có thêm `Series` (Chú giải) và `Value` (Độ bão hoà màu).
        "shapeMap": ["Category": (.column, true), "Series": (.column, true), "Value": (.measure, true), "Tooltips": (.measure, false)],
        "treemap": ["Group": (.column, false), "Tooltips": (.measure, false), "Values": (.measure, true)],
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
    /// Mô hình cho gộp ngầm (`implicitMeasures`): cột số có `SummarizeBy` khác None vào ô giá trị trước (VM-F10: tích `Amount`,
    /// `OrderID` vào Y-axis; tích `Region` vào X-axis).
    static func defaultRole(for field: FieldRef, in visual: ReportVisual, implicitMeasures: Bool = false) -> String? {
        let candidates = rules(for: visual).filter { refusal(adding: field, to: $0.role, in: visual, implicitMeasures: implicitMeasures) == nil }
        if implicitMeasures, field.kind == .column, field.family == .numeric, (field.summarizeBy ?? 2) > 2,
           let value = candidates.first(where: { $0.role != "Tooltips" && $0.accepts == [.measure] }) {
            return value.role
        }
        let ordinary = candidates.filter { !(implicitMeasures && field.kind == .column && $0.accepts == [.measure]) }
        return (ordinary.first { $0.role != "Tooltips" } ?? ordinary.first ?? candidates.first)?.role
    }

    // MARK: Từ chối

    static let unverifiedReason = "Ô này chưa kiểm với Power BI Desktop (buổi VM-D2), nên chưa thêm trường được."
    static let aggregationReason = "Ô này cần measure: mô hình đặt \"discourage implicit measures\" (như Nhom6) nên Power BI Desktop cũng chặn cột ở ô này (VM-D2b). Hãy tạo measure, ví dụ SUM(Bảng[Cột])."

    /// Lý do không thêm được `field` vào ô `role` của `visual`, hoặc nil nếu thêm được.
    /// `implicitMeasures`: mô hình không đặt "discourage implicit measures" thì ô chỉ nhận measure cũng nhận cột (thành trường gộp,
    /// VM-F10). Cột đã gộp trong visual thì từ chối: hai trường cùng `queryRef` (`Sum(Bảng.Cột)`) bị Desktop coi là một (gate VM-F10,
    /// biểu đồ hiện "Average of Qty and Average of Qty"); cách Desktop đặt `queryRef` khi thêm cùng cột hai lần chưa quan sát.
    static func refusal(adding field: FieldRef, to role: String, in visual: ReportVisual, implicitMeasures: Bool = false) -> String? {
        guard let rule = rule(for: visual, role: role) else { return "Visual này không có ô \"\(role)\"." }
        guard rule.status == .observed else { return unverifiedReason }
        let kind = WellKind(field.kind)
        if implicitMeasures, field.kind == .column, rule.accepts == [.measure] {
            if visual.fields.contains(where: { $0.kind == .aggregation && $0.entity == field.entity && $0.property == field.property }) {
                return "Cột \"\(field.property)\" đã được gộp trong visual này; đổi phép gộp ở trường đang có."
            }
            return nil
        }
        guard rule.accepts.contains(kind) else {
            if kind == .column, rule.accepts == [.measure] { return aggregationReason }
            return "Ô \"\(rule.label)\" chỉ nhận \(rule.accepts.map(\.label).sorted().joined(separator: " hoặc "))."
        }
        // Desktop cho thêm cùng một measure hai lần vào một ô (VM-D2 `R-D2-h-dup`); cột trùng thì chưa quan sát nên từ chối.
        if kind == .column, visual.fields.contains(where: { $0.role == role && $0.queryRef == field.queryRef }) {
            return "Trường \"\(field.property)\" đã có trong ô \"\(rule.label)\"."
        }
        if field.kind == .hierarchy, visual.fields.contains(where: { $0.role == role && $0.queryRef.hasPrefix(field.queryRef + ".") }) {
            return "Phân cấp \"\(field.property)\" đã có trong ô \"\(rule.label)\"."
        }
        return nil
    }

    /// Lý do không chuyển được `field` (đang ở một ô của `visual`) sang ô `role`, hoặc nil.
    static func refusal(moving field: ReportField, to role: String, in visual: ReportVisual, implicitMeasures: Bool = false) -> String? {
        guard let rule = rule(for: visual, role: role) else { return "Visual này không có ô \"\(role)\"." }
        guard rule.status == .observed else { return unverifiedReason }
        // Cột dời sang ô giá trị thành trường gộp (VM-F10 a6: Region từ Categories sang Value thành First).
        if implicitMeasures, field.kind == .column, rule.accepts == [.measure] { return nil }
        guard let kind = WellKind(field.kind), rule.accepts.contains(kind) else {
            return "Ô \"\(rule.label)\" không nhận loại trường này."
        }
        if field.role != role, kind == .column, visual.fields.contains(where: { $0.role == role && $0.queryRef == field.queryRef }) {
            return "Trường \"\(field.property)\" đã có trong ô \"\(rule.label)\"."
        }
        return nil
    }
}
