import Foundation
import Testing
@testable import PBIXKit

/// Đợt tồn đọng sau Phase F, T006: hình dạng hợp đồng `contracts/model-edits.md` (phân cấp, variation, chú thích mô hình, thuộc tính bảng
/// và quan hệ cho Auto date/time). Áp dụng thật làm ở US2 (T030–T032); tới lúc đó mô hình và bộ ghi báo "chưa hỗ trợ" rõ ràng.
@Suite struct ModelEditF2ContractTests {
    private let hierarchy = NewHierarchy(table: "LocalDateTable_1", name: "Date Hierarchy",
                                         levels: [HierarchyLevel(name: "Year", column: "Year"), HierarchyLevel(name: "Day", column: "Day")])

    @Test func newCasesNameTheirTablesAndNeedData() {
        let variation = ModelEdit.addVariation(table: "Sales", column: "OrderDate", relationship: "r1",
                                               hierarchy: HierarchyRef(table: "LocalDateTable_1", name: "Date Hierarchy"))
        #expect(ModelEdit.addHierarchy(hierarchy).mentionsTable("localdatetable_1"))
        #expect(ModelEdit.dropHierarchy(table: "T", name: "H").mentionsTable("t"))
        #expect(variation.mentionsTable("sales"))
        #expect(ModelEdit.dropVariation(table: "Sales", column: "OrderDate").mentionsTable("sales"))
        #expect(!ModelEdit.setModelAnnotation(name: "__PBI_TimeIntelligenceEnabled", value: "1").mentionsTable("sales"))
        // Phân cấp cần dữ liệu các cấp để dựng chỉ mục `U$` (T3); variation và chú thích chỉ là metadata (T2).
        #expect(ModelEdit.addHierarchy(hierarchy).needsData)
        #expect(!variation.needsData)
        #expect(!ModelEdit.setModelAnnotation(name: "a", value: "b").needsData)
    }

    @Test func defaultsKeepPhaseFBehaviour() {
        let relationship = NewRelationship(fromTable: "Sales", fromColumn: "d", toTable: "LocalDateTable_1", toColumn: "Date")
        #expect(relationship.joinOnDateBehavior == 1)
        let table = NewTable(name: "T", columns: [NewTableColumn(name: "k", dataType: .int64)])
        #expect(!table.isPrivate && !table.showAsVariationsOnly && table.annotations.isEmpty)
        let local = NewTable(name: "LocalDateTable_1", columns: [], isPrivate: false, showAsVariationsOnly: true,
                             annotations: ["__PBI_LocalDateTable": "true"])
        #expect(local.showAsVariationsOnly && local.annotations["__PBI_LocalDateTable"] == "true")
    }

    @Test func applyingNewCasesIsNotSupportedYet() throws {
        let (abf, _) = try PBIXFile(data: try NewDocument.blank()).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        #expect(throws: ModelEditError.self) { try model.applying(ModelEdits([.addHierarchy(hierarchy)])) }
    }
}
