// Đợt tồn đọng sau Phase F, US1 (T012–T013): thêm, dời và đổi phép gộp ngầm trong ô trường. Quy tắc từ VM-F10
// (`docs/phase-f2-evidence/vm-f10/QUAN-SAT.md`): mặc định theo `SummarizeBy` (3 → Sum, 6 → Count), cột chữ vào ô giá trị thành
// First (Function 3); đổi phép gộp giữ `queryRef`.
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct ImplicitAggregationEditingTests {
    static let amount = FieldRef(kind: .column, entity: "Sales", property: "Amount", family: .numeric, summarizeBy: 3)
    static let orderID = FieldRef(kind: .column, entity: "Sales", property: "OrderID", family: .numeric, summarizeBy: 6)
    static let region = FieldRef(kind: .column, entity: "Sales", property: "Region", family: .text, summarizeBy: 2)
    static let chart = ReportVisual(id: "aaaaaaaaaaaaaaaaaaa1", type: "clusteredColumnChart", fields: [])
    static let card = ReportVisual(id: "aaaaaaaaaaaaaaaaaaa2", type: "cardVisual", fields: [])

    func ok(_ r: FieldEditor.Result) -> [PBIRQueryPatch.Well]? { if case .changed(let w) = r { w } else { nil } }
    func refused(_ r: FieldEditor.Result) -> String? { if case .refused(let m) = r { m } else { nil } }

    @Test func moHinhChoGopNgamThiCotVaoOGiaTri() throws {
        let wells = try #require(ok(FieldEditor.add(Self.amount, to: "Y", wells: [], visual: Self.chart, implicitMeasures: true)))
        let field = try #require(wells.first { $0.role == "Y" }?.elements.first?.field)
        #expect(field.kind == .aggregation && field.aggregationFunction == 0)
        #expect(field.queryRef == "Sum(Sales.Amount)" && field.nativeQueryRef == "Sum of Amount")
        let count = try #require(ok(FieldEditor.add(Self.orderID, to: "Y", wells: wells, visual: Self.chart, implicitMeasures: true)))
        #expect(count.first { $0.role == "Y" }?.elements.last?.field.aggregationFunction == 5)
        // Cùng cột hai lần: từ chối (gate VM-F10: Desktop gộp hai trường cùng `queryRef` thành một).
        let withAmount = ReportVisual(id: "aaaaaaaaaaaaaaaaaaa1", type: "clusteredColumnChart", fields: wells.flatMap { $0.elements.map(\.field) })
        #expect(refused(FieldEditor.add(Self.amount, to: "Y", wells: wells, visual: withAmount, implicitMeasures: true))?.contains("đã được gộp") == true)
        let first = try #require(ok(FieldEditor.add(Self.region, to: "Data", wells: [], visual: Self.card, implicitMeasures: true)))
        #expect(first.first?.elements.first?.field.aggregationFunction == 3)
    }

    @Test func moHinhChanGopNgamThiTuChoiNhuCu() {
        let reason = refused(FieldEditor.add(Self.amount, to: "Y", wells: [], visual: Self.chart, implicitMeasures: false))
        #expect(reason == WellRules.aggregationReason)
    }

    @Test func tichCotSoThiVaoOGiaTriCotChuThiVaoTruc() {
        #expect(WellRules.defaultRole(for: Self.amount, in: Self.chart, implicitMeasures: true) == "Y")
        #expect(WellRules.defaultRole(for: Self.orderID, in: Self.chart, implicitMeasures: true) == "Y")
        #expect(WellRules.defaultRole(for: Self.region, in: Self.chart, implicitMeasures: true) == "Category")
        #expect(WellRules.defaultRole(for: Self.amount, in: Self.chart, implicitMeasures: false) == "Category")
    }

    @Test func doiPhepGopGiuQueryRefVaNhanTheoKieuCot() throws {
        let wells = try #require(ok(FieldEditor.add(Self.amount, to: "Y", wells: [], visual: Self.chart, implicitMeasures: true)))
        let changed = try #require(ok(FieldEditor.setAggregation(role: "Y", index: 0, to: .average, kind: .number, wells: wells)))
        let field = try #require(changed.first?.elements.first?.field)
        #expect(field.aggregationFunction == 1 && field.queryRef == "Sum(Sales.Amount)" && field.nativeQueryRef == "Average of Amount")
        #expect(refused(FieldEditor.setAggregation(role: "Y", index: 0, to: .median, kind: .text, wells: wells)) != nil)
        #expect(FieldEditor.setAggregation(role: "Y", index: 0, to: .sum, kind: .number, wells: wells).isUnchanged)
    }

    @Test func doiCotSangOGiaTriThanhTruongGop() throws {
        let category = PBIRQueryPatch.newElement(kind: .column, entity: "Sales", property: "Region", displayName: nil, role: "Category",
                                                 active: true)
        let wells = [PBIRQueryPatch.Well(role: "Category", elements: [category])]
        let chart = ReportVisual(id: "aaaaaaaaaaaaaaaaaaa1", type: "clusteredColumnChart", fields: [category.field])
        // VM-F10 a6: dời cột chữ sang ô giá trị thì thành First (Function 3), giữ `nativeQueryRef`. [SUY ĐOÁN] ô Y như ô Data của card.
        let moved = try #require(ok(FieldEditor.move(role: "Category", index: 0, to: "Y", wells: wells, visual: chart,
                                                    implicitMeasures: true, column: Self.region)))
        let field = try #require(moved.first { $0.role == "Y" }?.elements.first?.field)
        #expect(field.kind == .aggregation && field.aggregationFunction == 3 && field.nativeQueryRef == "Region")
    }

    @Test func nhanTiengVietTheoKieuCot() {
        #expect(AggregateFunction.min.label(column: "Region", kind: .text) == "Đầu tiên của Region")
        #expect(AggregateFunction.sum.label(column: "Amount", kind: .number) == "Tổng của Amount")
        #expect(AggregateFunction.defaultFunction(for: Self.region) == .min)
        #expect(AggregateFunction.defaultFunction(for: Self.orderID) == .count)
    }
}
