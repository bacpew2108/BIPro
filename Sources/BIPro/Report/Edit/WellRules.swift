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

    var label: String { self == .column ? biN("cột", "column") : "measure" }
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
    /// Bảng đã quan sát: (loại visual, ô) → (tập loại trường nhận, ô một trường). Nguồn: Nhom6, VM-D3/D15 và VM-V11A.
    private static let observed: [String: [String: (accepts: Set<WellKind>, single: Bool)]] = [
        "card": ["Values": ([.measure], true)],
        // VM-D3 mục A, B: "Card" trong thư viện của Desktop ghi `cardVisual`, ô `Data`.
        "cardVisual": ["Data": ([.measure], false)],
        "multiRowCard": ["Values": ([.column, .measure], false)],
        "slicer": ["Values": ([.column], true)],
        // VM-V11A: Tile, List, Text slicer đều nhận 1 cột ở `Values`.
        "advancedSlicerVisual": ["Values": ([.column], true)],
        "listSlicer": ["Values": ([.column], true)],
        "textSlicer": ["Values": ([.column], true)],
        // VM-V11A: Stacked bar ghi `barChart` (tương thích ngược `stackedBarChart`).
        "barChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "stackedBarChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "hundredPercentStackedBarChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "clusteredColumnChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "columnChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false)],
        "clusteredBarChart": ["Category": ([.column], true), "Y": ([.measure], false), "Series": ([.column], true), "Tooltips": ([.measure], false)],
        "pieChart": ["Category": ([.column], false), "Series": ([.column], true), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "donutChart": ["Category": ([.column], false), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "hundredPercentStackedColumnChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false)],
        "lineChart": ["Category": ([.column], true), "Series": ([.column], true), "Tooltips": ([.measure], false), "Y": ([.measure], false),
                      "Y2": ([.measure], false)],
        "lineClusteredColumnComboChart": ["Category": ([.column], true), "Tooltips": ([.measure], false), "Y": ([.measure], false), "Y2": ([.measure], false)],
        "lineStackedColumnComboChart": ["Category": ([.column], true), "Series": ([.column], true), "Tooltips": ([.measure], false),
                                        "Y": ([.measure], false), "Y2": ([.measure], false)],
        "areaChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Y2": ([.measure], false), "Tooltips": ([.measure], false)],
        "hundredPercentStackedAreaChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Y2": ([.measure], false), "Tooltips": ([.measure], false)],
        "stackedAreaChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Y2": ([.measure], false), "Tooltips": ([.measure], false)],
        "ribbonChart": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "waterfallChart": ["Category": ([.column], true), "Breakdown": ([.column], true), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        "funnel": ["Category": ([.column], false), "Y": ([.measure], false), "Tooltips": ([.measure], false)],
        // VM-V11A Batch 2: tableEx, scatterChart, gauge, kpi, map, filledMap.
        "tableEx": ["Values": ([.column, .measure], false)],
        "scatterChart": ["Category": ([.column], true), "Series": ([.column], true), "X": ([.measure], true), "Y": ([.measure], true),
                         "Size": ([.measure], true), "Tooltips": ([.measure], false)],
        "gauge": ["Y": ([.measure], true), "MinValue": ([.measure], true), "MaxValue": ([.measure], true),
                  "TargetValue": ([.measure], true), "Tooltips": ([.measure], false)],
        "kpi": ["Indicator": ([.measure], true), "TrendLine": ([.column], true), "Goal": ([.measure], true)],
        "pivotTable": ["Columns": ([.column], true), "Rows": ([.column], true), "Values": ([.measure], false)],
        "shapeMap": ["Category": ([.column], true), "Series": ([.column], true), "Value": ([.measure], true), "Tooltips": ([.measure], false)],
        "map": ["Category": ([.column], true), "Series": ([.column], true), "Size": ([.measure], true), "Tooltips": ([.measure], false)],
        "filledMap": ["Category": ([.column], true), "Series": ([.column], true), "Y": ([.measure], true), "Tooltips": ([.measure], false)],
        "treemap": ["Group": ([.column], false), "Tooltips": ([.measure], false), "Values": ([.measure], true)],
    ]

    /// Các ô của visual, theo thứ tự hiện trong Build pane, mỗi ô kèm luật.
    static func rules(for visual: ReportVisual) -> [WellRule] {
        VisualCatalog.wells(for: visual).map { well in
            if let hit = observed[visual.type]?[well.role] {
                return WellRule(role: well.role, label: well.label, accepts: hit.accepts, isSingle: hit.single, status: .observed)
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

    static let unverifiedReason = biN("Ô này chưa kiểm với Power BI Desktop (buổi VM-D2), nên chưa thêm trường được.", "This well hasn't been verified against Power BI Desktop (session VM-D2), so fields can't be added yet.")
    static var aggregationReason: String { biN("Ô này cần measure: mô hình đặt \"discourage implicit measures\" (như Nhom6) nên Power BI Desktop cũng chặn cột ở ô này (VM-D2b). Hãy tạo measure, ví dụ SUM(Bảng[Cột]).", "This well needs a measure: the model sets \"discourage implicit measures\" (like Nhom6), so Power BI Desktop also blocks columns in this well (VM-D2b). Create a measure, for example SUM(Table[Column]).") }

    /// Lý do không thêm được `field` vào ô `role` của `visual`, hoặc nil nếu thêm được.
    /// `implicitMeasures`: mô hình không đặt "discourage implicit measures" thì ô chỉ nhận measure cũng nhận cột (thành trường gộp,
    /// VM-F10). Cột đã gộp trong visual thì từ chối: hai trường cùng `queryRef` (`Sum(Bảng.Cột)`) bị Desktop coi là một (gate VM-F10,
    /// biểu đồ hiện "Average of Qty and Average of Qty"); cách Desktop đặt `queryRef` khi thêm cùng cột hai lần chưa quan sát.
    static func refusal(adding field: FieldRef, to role: String, in visual: ReportVisual, implicitMeasures: Bool = false) -> String? {
        guard let rule = rule(for: visual, role: role) else { return biN("Visual này không có ô \"\(role)\".", "This visual has no well \"\(role)\".") }
        guard rule.status == .observed else { return unverifiedReason }
        let kind = WellKind(field.kind)
        if implicitMeasures, field.kind == .column, rule.accepts == [.measure] {
            if visual.fields.contains(where: { $0.kind == .aggregation && $0.entity == field.entity && $0.property == field.property }) {
                return biN("Cột \"\(field.property)\" đã được gộp trong visual này; đổi phép gộp ở trường đang có.", "The column \"\(field.property)\" is already aggregated in this visual; change the aggregation on the existing field.")
            }
            return nil
        }
        guard rule.accepts.contains(kind) else {
            if kind == .column, rule.accepts == [.measure] { return aggregationReason }
            return biN("Ô \"\(rule.label)\" chỉ nhận \(rule.accepts.map(\.label).sorted().joined(separator: " hoặc ")).", "The well \"\(rule.label)\" only accepts \(rule.accepts.map(\.label).sorted().joined(separator: " or ")).")
        }
        // Desktop cho thêm cùng một measure hai lần vào một ô (VM-D2 `R-D2-h-dup`); cột trùng thì chưa quan sát nên từ chối.
        if kind == .column, visual.fields.contains(where: { $0.role == role && $0.queryRef == field.queryRef }) {
            return biN("Trường \"\(field.property)\" đã có trong ô \"\(rule.label)\".", "The field \"\(field.property)\" is already in the well \"\(rule.label)\".")
        }
        if field.kind == .hierarchy, visual.fields.contains(where: { $0.role == role && $0.queryRef.hasPrefix(field.queryRef + ".") }) {
            return biN("Phân cấp \"\(field.property)\" đã có trong ô \"\(rule.label)\".", "The hierarchy \"\(field.property)\" is already in the well \"\(rule.label)\".")
        }
        return nil
    }

    /// Lý do không chuyển được `field` (đang ở một ô của `visual`) sang ô `role`, hoặc nil.
    static func refusal(moving field: ReportField, to role: String, in visual: ReportVisual, implicitMeasures: Bool = false) -> String? {
        guard let rule = rule(for: visual, role: role) else { return biN("Visual này không có ô \"\(role)\".", "This visual has no well \"\(role)\".") }
        guard rule.status == .observed else { return unverifiedReason }
        // Cột dời sang ô giá trị thành trường gộp (VM-F10 a6: Region từ Categories sang Value thành First).
        if implicitMeasures, field.kind == .column, rule.accepts == [.measure] { return nil }
        guard let kind = WellKind(field.kind), rule.accepts.contains(kind) else {
            return biN("Ô \"\(rule.label)\" không nhận loại trường này.", "The well \"\(rule.label)\" doesn't accept this field type.")
        }
        if field.role != role, kind == .column, visual.fields.contains(where: { $0.role == role && $0.queryRef == field.queryRef }) {
            return biN("Trường \"\(field.property)\" đã có trong ô \"\(rule.label)\".", "The field \"\(field.property)\" is already in the well \"\(rule.label)\".")
        }
        return nil
    }
}
