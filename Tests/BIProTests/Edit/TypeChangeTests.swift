import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct TypeChangeTests {
    typealias Well = PBIRQueryPatch.Well
    typealias Element = PBIRQueryPatch.Element

    static func element(_ role: String, _ kind: ReportField.Kind, _ entity: String, _ property: String, source: Bool = true) -> Element {
        let ref = "\(entity).\(property)"
        let field = ReportField(role: role, kind: kind, entity: entity, property: property, queryRef: ref, nativeQueryRef: property)
        return Element(field: field, source: source ? Data(#"{"queryRef":"\#(ref)"}"#.utf8) : nil)
    }
    static func visual(_ type: String, _ wells: [Well]) -> ReportVisual {
        ReportVisual(id: "aaaaaaaaaaaaaaaaaaa1", type: type, fields: wells.flatMap { $0.elements.map(\.field) })
    }
    static let combo: [Well] = [
        .init(role: "Category", elements: [element("Category", .column, "Dim_Date", "month_name")]),
        .init(role: "Y", elements: [element("Y", .measure, "Fact", "Credit"), element("Y", .measure, "Fact", "Debit")]),
        .init(role: "Y2", elements: [element("Y2", .measure, "Fact", "Net")]),
        .init(role: "Tooltips", elements: [element("Tooltips", .measure, "Fact", "Avg")]),
    ]
    static let noRefs: (ReportField) -> [FieldReference] = { _ in [] }

    func plan(_ from: String, _ wells: [Well], to type: String, keys: [String] = [], seen: Set<String> = [],
              references: @escaping (ReportField) -> [FieldReference] = TypeChangeTests.noRefs) -> TypeChangePlan {
        TypeChange.plan(visual: Self.visual(from, wells), wells: wells, to: type, objectKeys: keys, seenObjectKeys: seen, references: references)
    }
    func roles(_ plan: TypeChangePlan) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: plan.wells.map { ($0.role, $0.elements.map(\.field.property)) })
    }

    // MARK: ánh xạ ô

    @Test func sameNamedWellsMoveWholeAndKeepElementBytes() {
        let wells: [Well] = [
            .init(role: "Category", elements: [Self.element("Category", .column, "Dim", "region")]),
            .init(role: "Series", elements: [Self.element("Series", .column, "Dim", "sex")]),
            .init(role: "Y", elements: [Self.element("Y", .measure, "Fact", "Credit"), Self.element("Y", .measure, "Fact", "Debit")]),
            .init(role: "Tooltips", elements: [Self.element("Tooltips", .measure, "Fact", "Avg")]),
        ]
        for target in ["lineChart", "hundredPercentStackedColumnChart"] {
            let p = plan("clusteredBarChart", wells, to: target)
            #expect(p.blocked == nil, Comment(rawValue: target))
            if target == "lineChart" {
                #expect(p.droppedFields.isEmpty)
                #expect(roles(p) == ["Category": ["region"], "Series": ["sex"], "Y": ["Credit", "Debit"], "Tooltips": ["Avg"]])
                #expect(p.wells.flatMap(\.elements).map(\.source) == wells.flatMap(\.elements).map(\.source))
            } else {
                // cột 100% không có Tooltips đã quan sát: Tooltips bị bỏ và báo
                #expect(p.droppedFields.map(\.property) == ["Avg"])
            }
        }
    }

    @Test func comboToLineMovesY2IntoYWhenThereIsNoY2() {
        let p = plan("lineClusteredColumnComboChart", Self.combo, to: "lineChart")
        #expect(p.blocked == nil)
        #expect(roles(p)["Y"] == ["Credit", "Debit", "Net"])
        #expect(roles(p)["Category"] == ["month_name"] && roles(p)["Tooltips"] == ["Avg"])
        #expect(p.droppedFields.isEmpty)
        // phần tử đã chuyển mang ô mới
        #expect(p.wells.first { $0.role == "Y" }?.elements.allSatisfy { $0.field.role == "Y" } == true)
    }

    @Test func donutToTreemapAndBack() {
        let donut: [Well] = [
            .init(role: "Category", elements: [Self.element("Category", .column, "Dim", "type")]),
            .init(role: "Y", elements: [Self.element("Y", .measure, "Fact", "Amount")]),
            .init(role: "Tooltips", elements: [Self.element("Tooltips", .measure, "Fact", "Count")]),
        ]
        let tree = plan("donutChart", donut, to: "treemap")
        #expect(tree.blocked == nil && tree.droppedFields.isEmpty)
        #expect(roles(tree) == ["Group": ["type"], "Values": ["Amount"], "Tooltips": ["Count"]])
        let back = plan("treemap", tree.wells, to: "donutChart")
        #expect(roles(back) == ["Category": ["type"], "Y": ["Amount"], "Tooltips": ["Count"]])
    }

    @Test func singleWellsKeepOnlyTheFirstFieldAndReportTheRest() {
        let line: [Well] = [
            .init(role: "Category", elements: [Self.element("Category", .column, "Dim", "a")]),
            .init(role: "Y", elements: [Self.element("Y", .measure, "Fact", "M1"), Self.element("Y", .measure, "Fact", "M2")]),
        ]
        let p = plan("lineChart", line, to: "donutChart")      // donut: Y là ô một trường
        #expect(roles(p)["Y"] == ["M1"] && p.droppedFields.map(\.property) == ["M2"])
    }

    @Test func cardAndSlicerCannotHoldEachOthersFields() {
        let card: [Well] = [.init(role: "Values", elements: [Self.element("Values", .measure, "Fact", "Net")])]
        let toSlicer = plan("card", card, to: "slicer")
        #expect(toSlicer.wells.allSatisfy { $0.elements.isEmpty } && toSlicer.droppedFields.map(\.property) == ["Net"])
        let slicer: [Well] = [.init(role: "Values", elements: [Self.element("Values", .column, "Dim", "region")])]
        let toCard = plan("slicer", slicer, to: "card")
        #expect(toCard.droppedFields.map(\.property) == ["region"])
    }

    @Test func hierarchyLevelsAreKeptWhereTheNewWellTakesColumnsAndDroppedOtherwise() {
        let level = Element(field: ReportField(role: "Category", kind: .hierarchyLevel, entity: "Dim_Date", property: "Năm",
                                               queryRef: "Dim_Date.Thời gian.Năm", nativeQueryRef: "Năm", active: true),
                            source: Data(#"{"queryRef":"Dim_Date.Thời gian.Năm"}"#.utf8))
        let wells: [Well] = [.init(role: "Category", elements: [level]), .init(role: "Y", elements: [Self.element("Y", .measure, "Fact", "Credit")])]
        let toLine = plan("lineClusteredColumnComboChart", wells, to: "lineChart")
        #expect(toLine.droppedFields.isEmpty)
        #expect(toLine.wells.first { $0.role == "Category" }?.elements.first?.source == level.source)
        // card không có ô nào nhận cột: cấp hierarchy và measure đều không có chỗ cho cấp, bị bỏ và báo
        let toCard = plan("lineClusteredColumnComboChart", wells, to: "card")
        #expect(toCard.droppedFields.map(\.property).contains("Năm"))
    }

    // MARK: chặn khi còn tham chiếu

    @Test func blockedWhenADroppedFieldIsStillReferencedAndNothingElseHoldsIt() {
        let sortRef: (ReportField) -> [FieldReference] = { $0.property == "Avg" ? [FieldReference(kind: .sort, detail: "x")] : [] }
        let p = plan("lineChart", [
            .init(role: "Category", elements: [Self.element("Category", .column, "Dim", "a")]),
            .init(role: "Y", elements: [Self.element("Y", .measure, "Fact", "Credit")]),
            .init(role: "Tooltips", elements: [Self.element("Tooltips", .measure, "Fact", "Avg")]),
        ], to: "hundredPercentStackedColumnChart", references: sortRef)
        #expect(p.blocked?.contains("sắp xếp") == true)
        // cùng trường còn giữ ở ô khác thì không chặn
        let both = plan("lineChart", [
            .init(role: "Y", elements: [Self.element("Y", .measure, "Fact", "Avg")]),
            .init(role: "Tooltips", elements: [Self.element("Tooltips", .measure, "Fact", "Avg")]),
        ], to: "hundredPercentStackedColumnChart", references: sortRef)
        #expect(both.blocked == nil)
    }

    // MARK: định dạng (objects)

    @Test func objectKeysAreKeptOnlyWhenSeenOnAVisualOfTheTargetType() {
        let p = plan("clusteredBarChart", Self.combo, to: "lineChart", keys: ["dataPoint", "labels", "categoryAxis"],
                     seen: ["valueAxis", "labels", "categoryAxis", "trend"])
        #expect(p.droppedObjectKeys == ["dataPoint"])
        // loại đích không có visual nào trong báo cáo: bỏ hết
        let none = plan("clusteredBarChart", Self.combo, to: "lineChart", keys: ["dataPoint", "labels"], seen: [])
        #expect(none.droppedObjectKeys == ["dataPoint", "labels"])
        // không có định dạng thì không có gì bỏ
        #expect(plan("clusteredBarChart", Self.combo, to: "lineChart", keys: [], seen: []).droppedObjectKeys.isEmpty)
    }

    // MARK: không đổi và hộp văn bản

    @Test func sameTypeIsANoOpAndTextboxesDoNotChangeType() {
        let same = plan("lineChart", Self.combo, to: "lineChart")
        #expect(same.isNoOp)
        #expect(plan("textbox", [], to: "card").blocked?.contains("Hộp văn bản") == true)
        #expect(plan("card", [], to: "textbox").blocked?.contains("Hộp văn bản") == true)
        #expect(plan("lineChart", Self.combo, to: "scatterChart").blocked != nil)
    }

    @Test func noticeListsEverythingThatWasDropped() {
        let p = plan("lineClusteredColumnComboChart", Self.combo, to: "hundredPercentStackedColumnChart", keys: ["dataPoint"], seen: [])
        let notice = p.notice
        #expect(notice?.contains("Avg") == true && notice?.contains("dataPoint") == true)
        #expect(plan("lineChart", Self.combo, to: "clusteredBarChart").notice == nil)
    }
}
