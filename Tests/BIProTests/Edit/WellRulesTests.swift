import PBIXKit
import Testing
@testable import BIPro

@Suite struct WellRulesTests {
    static func visual(_ type: String, fields: [ReportField] = []) -> ReportVisual {
        ReportVisual(id: "aaaaaaaaaaaaaaaaaaa1", type: type, fields: fields)
    }
    static func field(_ role: String, _ kind: ReportField.Kind, _ entity: String, _ property: String) -> ReportField {
        ReportField(role: role, kind: kind, entity: entity, property: property, queryRef: "\(entity).\(property)")
    }
    static let measure = FieldRef(kind: .measure, entity: "Fact", property: "Credit")
    static let column = FieldRef(kind: .column, entity: "Dim", property: "Vùng", family: .text)
    static let numeric = FieldRef(kind: .column, entity: "Fact", property: "amount", family: .numeric, summarizeBy: 3)

    /// 30 tổ hợp (loại visual, ô) đã quan sát trong Nhom6 (research R1): loại trường nhận và số tối đa khi thêm.
    static let observed: [(type: String, role: String, kind: WellKind, single: Bool)] = [
        ("card", "Values", .measure, true),
        ("slicer", "Values", .column, true),
        ("clusteredBarChart", "Category", .column, true), ("clusteredBarChart", "Y", .measure, false),
        ("clusteredBarChart", "Series", .column, true), ("clusteredBarChart", "Tooltips", .measure, false),
        ("donutChart", "Category", .column, true), ("donutChart", "Y", .measure, true), ("donutChart", "Tooltips", .measure, false),
        ("hundredPercentStackedColumnChart", "Category", .column, true), ("hundredPercentStackedColumnChart", "Series", .column, true),
        ("hundredPercentStackedColumnChart", "Y", .measure, false),
        ("lineChart", "Category", .column, true), ("lineChart", "Series", .column, true),
        ("lineChart", "Tooltips", .measure, false), ("lineChart", "Y", .measure, false),
        ("lineClusteredColumnComboChart", "Category", .column, true), ("lineClusteredColumnComboChart", "Tooltips", .measure, false),
        ("lineClusteredColumnComboChart", "Y", .measure, false), ("lineClusteredColumnComboChart", "Y2", .measure, false),
        ("lineStackedColumnComboChart", "Category", .column, true), ("lineStackedColumnComboChart", "Series", .column, true),
        ("lineStackedColumnComboChart", "Tooltips", .measure, false), ("lineStackedColumnComboChart", "Y", .measure, false),
        ("lineStackedColumnComboChart", "Y2", .measure, false),
        ("pivotTable", "Columns", .column, true), ("pivotTable", "Rows", .column, true), ("pivotTable", "Values", .measure, false),
        ("shapeMap", "Category", .column, true), ("shapeMap", "Tooltips", .measure, false),
        ("treemap", "Group", .column, true), ("treemap", "Tooltips", .measure, false), ("treemap", "Values", .measure, true),
    ]

    @Test func everyObservedWellAcceptsItsKindAndRejectsTheOther() {
        for item in Self.observed {
            let v = Self.visual(item.type)
            let rule = WellRules.rule(for: v, role: item.role)
            #expect(rule != nil, "\(item.type)/\(item.role)")
            #expect(rule?.status == .observed, "\(item.type)/\(item.role)")
            #expect(rule?.isSingle == item.single, "\(item.type)/\(item.role)")
            let good = item.kind == .measure ? Self.measure : Self.column
            let bad = item.kind == .measure ? Self.column : Self.measure
            #expect(WellRules.refusal(adding: good, to: item.role, in: v) == nil, Comment(rawValue: "\(item.type)/\(item.role) nhận \(item.kind)"))
            #expect(WellRules.refusal(adding: bad, to: item.role, in: v) != nil, Comment(rawValue: "\(item.type)/\(item.role) từ chối loại kia"))
        }
    }

    @Test func wellsOfTheCatalogAllHaveARule() {
        for type in ["card", "slicer", "clusteredBarChart", "lineChart", "donutChart", "pivotTable", "treemap", "shapeMap",
                     "lineClusteredColumnComboChart", "scatterChart", "kpi", "gauge", "tableEx", "stackedColumnChart"] {
            let v = Self.visual(type)
            let wells = VisualCatalog.wells(for: v)
            #expect(WellRules.rules(for: v).map(\.role) == wells.map(\.role), Comment(rawValue: type))
            #expect(WellRules.rules(for: v).map(\.label) == wells.map(\.label), Comment(rawValue: type))
        }
    }

    @Test func unobservedWellsAreShownButRefuse() {
        let v = Self.visual("lineClusteredColumnComboChart")        // Series chưa quan sát ở loại này
        let rule = WellRules.rule(for: v, role: "Series")
        #expect(rule?.status == .unverified)
        let reason = WellRules.refusal(adding: Self.column, to: "Series", in: v)
        #expect(reason?.contains("chưa kiểm") == true)
        #expect(WellRules.refusal(adding: Self.column, to: "Y", in: Self.visual("scatterChart"))?.contains("chưa kiểm") == true)
        #expect(WellRules.refusal(adding: Self.measure, to: "NoSuchRole", in: v) != nil)
    }

    @Test func numericColumnInAValueWellWaitsForAggregation() {
        let reason = WellRules.refusal(adding: Self.numeric, to: "Y", in: Self.visual("clusteredBarChart"))
        #expect(reason?.contains("phép gộp") == true)
        // cột số vào ô cột (Category) thì được
        #expect(WellRules.refusal(adding: Self.numeric, to: "Category", in: Self.visual("clusteredBarChart")) == nil)
    }

    @Test func duplicatesAreRefusedAndSingleWellsReplace() {
        let v = Self.visual("clusteredBarChart", fields: [Self.field("Y", .measure, "Fact", "Credit"), Self.field("Category", .column, "Dim", "Vùng")])
        #expect(WellRules.refusal(adding: Self.measure, to: "Y", in: v)?.contains("đã có") == true)
        // ô một trường: thêm trường khác thì thay, không từ chối
        #expect(WellRules.refusal(adding: FieldRef(kind: .column, entity: "Dim", property: "Khác", family: .text), to: "Category", in: v) == nil)
        #expect(WellRules.rule(for: v, role: "Category")?.isSingle == true)
    }

    @Test func movingChecksTheTargetRule() {
        let v = Self.visual("lineClusteredColumnComboChart")
        let m = Self.field("Y", .measure, "Fact", "Credit")
        #expect(WellRules.refusal(moving: m, to: "Y2", in: v) == nil)
        #expect(WellRules.refusal(moving: m, to: "Category", in: v) != nil)
        let hierarchy = Self.field("Category", .hierarchyLevel, "Dim_Account", "Vùng")
        #expect(WellRules.refusal(moving: hierarchy, to: "Category", in: v) == nil)
        #expect(WellRules.refusal(moving: hierarchy, to: "Y", in: v) != nil)
    }

    @Test func hierarchyAndAggregationKindsMapToWellKinds() {
        #expect(WellKind(Self.field("A", .hierarchyLevel, "T", "L").kind) == .column)
        #expect(WellKind(.measure) == .measure)
        #expect(WellKind(.aggregation) == .measure)
        #expect(WellKind(.other) == nil)
    }

    @Test func defaultWellForATickedField() {
        let combo = Self.visual("lineClusteredColumnComboChart")
        #expect(WellRules.defaultRole(for: Self.measure, in: combo) == "Y")
        #expect(WellRules.defaultRole(for: Self.column, in: combo) == "Category")
        #expect(WellRules.defaultRole(for: Self.measure, in: Self.visual("card")) == "Values")
        #expect(WellRules.defaultRole(for: Self.column, in: Self.visual("card")) == nil)
        // số trong ô trục: cột số tick vào combo thì vào trục X (Category), không vào ô giá trị
        #expect(WellRules.defaultRole(for: Self.numeric, in: combo) == "Category")
    }
}
