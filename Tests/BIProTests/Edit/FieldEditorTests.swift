import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct FieldEditorTests {
    // Mẫu: Category [month_name], Y [Credit(displayName), Debit], Tooltips [Net]
    static func element(_ role: String, _ kind: ReportField.Kind, _ entity: String, _ property: String, display: String? = nil) -> PBIRQueryPatch.Element {
        let ref = "\(entity).\(property)"
        let source = Data(#"{"queryRef":"\#(ref)"}"#.utf8)
        return .init(field: ReportField(role: role, kind: kind, entity: entity, property: property, displayName: display,
                                        queryRef: ref, nativeQueryRef: property), source: source)
    }
    static var wells: [PBIRQueryPatch.Well] {
        [.init(role: "Category", elements: [element("Category", .column, "Dim_Date", "month_name")]),
         .init(role: "Y", elements: [element("Y", .measure, "Fact", "Credit", display: "Tiền vào"), element("Y", .measure, "Fact", "Debit")]),
         .init(role: "Tooltips", elements: [element("Tooltips", .measure, "Fact", "Net")])]
    }
    static func visual(_ type: String = "lineClusteredColumnComboChart") -> ReportVisual {
        var fields: [ReportField] = []
        for w in wells { fields += w.elements.map(\.field) }
        return ReportVisual(id: "aaaaaaaaaaaaaaaaaaa1", type: type, fields: fields)
    }
    static let newMeasure = FieldRef(kind: .measure, entity: "Fact", property: "Balance")
    static let newColumn = FieldRef(kind: .column, entity: "Dim_Client", property: "region", family: .text)
    func props(_ w: [PBIRQueryPatch.Well], _ role: String) -> [String] { w.first { $0.role == role }?.elements.map(\.field.property) ?? [] }
    func ok(_ r: FieldEditor.Result) -> [PBIRQueryPatch.Well]? { if case .changed(let w) = r { w } else { nil } }
    func refused(_ r: FieldEditor.Result) -> String? { if case .refused(let m) = r { m } else { nil } }
    let noRefs: (ReportField) -> [FieldReference] = { _ in [] }

    @Test func addAppendsToTheEndAndNewElementHasNoSource() {
        let r = FieldEditor.add(Self.newMeasure, to: "Y", wells: Self.wells, visual: Self.visual())
        let w = ok(r)
        #expect(props(w ?? [], "Y") == ["Credit", "Debit", "Balance"])
        #expect(w?.first { $0.role == "Y" }?.elements.last?.source == nil)
        #expect(w?.first { $0.role == "Y" }?.elements.last?.field.kind == .measure)
        // ô chưa có trong file thì được tạo
        let c = ok(FieldEditor.add(Self.newColumn, to: "Series", wells: Self.wells, visual: Self.visual("lineStackedColumnComboChart")))
        #expect(c?.last?.role == "Series" && props(c ?? [], "Series") == ["region"])
    }

    @Test func addToASingleWellReplacesAndRefusalsComeFromTheRules() {
        let r = ok(FieldEditor.add(Self.newColumn, to: "Category", wells: Self.wells, visual: Self.visual()))
        #expect(props(r ?? [], "Category") == ["region"])
        #expect(refused(FieldEditor.add(Self.newColumn, to: "Y", wells: Self.wells, visual: Self.visual()))?.contains("measure") == true)
        #expect(refused(FieldEditor.add(Self.newMeasure, to: "Series", wells: Self.wells, visual: Self.visual()))?.contains("chưa kiểm") == true)
        // measure trùng thì thêm được lần hai (VM-D2 R-D2-h-dup); cột trùng ở ô một trường chỉ thay
        let twice = ok(FieldEditor.add(FieldRef(kind: .measure, entity: "Fact", property: "Credit"), to: "Y", wells: Self.wells, visual: Self.visual()))
        #expect(props(twice ?? [], "Y").filter { $0 == "Credit" }.count == 2)
    }

    @Test func removeDropsTheElementAndTheEmptyWell() {
        let r = ok(FieldEditor.remove(role: "Y", index: 1, wells: Self.wells, visual: Self.visual(), references: noRefs))
        #expect(props(r ?? [], "Y") == ["Credit"])
        let last = ok(FieldEditor.remove(role: "Tooltips", index: 0, wells: Self.wells, visual: Self.visual(), references: noRefs))
        #expect(props(last ?? [], "Tooltips").isEmpty)
        #expect(last?.contains { $0.role == "Tooltips" } == false || last?.first { $0.role == "Tooltips" }?.elements.isEmpty == true)
    }

    @Test func removeIsBlockedWhileTheFieldIsReferencedElsewhere() {
        let blocked: (ReportField) -> [FieldReference] = { $0.property == "month_name" ? [FieldReference(kind: .sort, detail: "Dim_Date[month_name]")] : [] }
        let r = FieldEditor.remove(role: "Category", index: 0, wells: Self.wells, visual: Self.visual(), references: blocked)
        #expect(refused(r)?.contains("sắp xếp") == true)
        // cùng trường còn ở ô khác thì bỏ được
        var wells = Self.wells
        wells.append(.init(role: "Tooltips2", elements: [Self.element("Tooltips2", .column, "Dim_Date", "month_name")]))
        let r2 = FieldEditor.remove(role: "Category", index: 0, wells: wells, visual: Self.visual(), references: blocked)
        #expect(ok(r2) != nil)
        // bỏ trường khác không bị chặn
        #expect(ok(FieldEditor.remove(role: "Y", index: 0, wells: Self.wells, visual: Self.visual(), references: blocked)) != nil)
    }

    @Test func reorderMovesWithinTheWellAndKeepsSources() {
        let r = ok(FieldEditor.reorder(role: "Y", from: 0, to: 1, wells: Self.wells))
        #expect(props(r ?? [], "Y") == ["Debit", "Credit"])
        #expect(r?.first { $0.role == "Y" }?.elements.map(\.source) == Self.wells[1].elements.reversed().map(\.source))
        if case .unchanged = FieldEditor.reorder(role: "Y", from: 0, to: 0, wells: Self.wells) {} else { Issue.record("vẫn chỗ cũ phải là unchanged") }
        #expect(refused(FieldEditor.reorder(role: "Y", from: 0, to: 5, wells: Self.wells)) != nil)
    }

    @Test func moveBetweenWellsKeepsTheElementAndRespectsRules() {
        let r = ok(FieldEditor.move(role: "Y", index: 0, to: "Y2", wells: Self.wells, visual: Self.visual()))
        #expect(props(r ?? [], "Y") == ["Debit"] && props(r ?? [], "Y2") == ["Credit"])
        #expect(r?.first { $0.role == "Y2" }?.elements.first?.source == Self.wells[1].elements[0].source)
        #expect(r?.first { $0.role == "Y2" }?.elements.first?.field.role == "Y2")
        #expect(refused(FieldEditor.move(role: "Y", index: 0, to: "Category", wells: Self.wells, visual: Self.visual())) != nil)
        // chuyển trường duy nhất làm ô cũ trống: ô cũ biến mất khỏi danh sách (rỗng)
        let t = ok(FieldEditor.move(role: "Tooltips", index: 0, to: "Y2", wells: Self.wells, visual: Self.visual()))
        #expect(props(t ?? [], "Tooltips").isEmpty && props(t ?? [], "Y2") == ["Net"])
    }

    @Test func renameSetsClearsAndIgnoresNoChange() {
        let r = ok(FieldEditor.rename(role: "Y", index: 1, to: "Chi", wells: Self.wells))
        #expect(r?.first { $0.role == "Y" }?.elements[1].field.displayName == "Chi")
        let clear = ok(FieldEditor.rename(role: "Y", index: 0, to: "", wells: Self.wells))
        #expect(clear?.first { $0.role == "Y" }?.elements[0].field.displayName == nil)
        let same = ok(FieldEditor.rename(role: "Y", index: 0, to: "Tiền vào", wells: Self.wells))
        #expect(same == nil)   // không đổi
        // bằng tên gốc (property) thì bỏ displayName
        let back = ok(FieldEditor.rename(role: "Y", index: 0, to: "Credit", wells: Self.wells))
        #expect(back?.first { $0.role == "Y" }?.elements[0].field.displayName == nil)
        #expect(refused(FieldEditor.rename(role: "Nope", index: 0, to: "x", wells: Self.wells)) != nil)
    }
}
