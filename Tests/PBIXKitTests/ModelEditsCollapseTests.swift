import Testing
@testable import PBIXKit

/// Lỗi T096 (`/code-review`): thêm rồi xoá bảng A trong cùng đợt lưu thì `collapsingTableEdits` bỏ cặp addTable/dropTable nhưng giữ các thao
/// tác ở giữa nhắc tới A (measure, quan hệ, cột tính toán), nên bộ ghi áp thao tác lên bảng không tồn tại và lưu hỏng.
@Suite struct ModelEditsCollapseTests {
    private func table(_ name: String) -> NewTable { NewTable(name: name, columns: [NewTableColumn(name: "k", dataType: .int64)]) }

    @Test func dropsEverythingAboutATableAddedAndDroppedInTheSameBatch() {
        let a = table("A")
        let rel = NewRelationship(name: "r1", fromTable: "A", fromColumn: "k", toTable: "Sales", toColumn: "k")
        let keep = NewMeasure(table: "Sales", name: "Giữ", expression: "1")
        let edits = ModelEdits([
            .addTable(a),
            .addMeasure(NewMeasure(table: "A", name: "m", expression: "1")),
            .updateMeasure(table: "A", name: "m", patch: MeasurePatch(expression: "2")),
            .deleteMeasure(table: "A", name: "m"),
            .addRelationship(rel),
            .updateRelationship(name: "r1", patch: RelationshipPatch(isActive: false)),
            .deleteRelationship(name: "r1"),
            .addCalculatedColumn(table: "A", name: "c", expression: "1", dataType: .int64),
            .updateColumn(table: "a", name: "k", patch: ColumnPatch(isHidden: true)),
            .addMeasure(keep),
            .dropTable(name: "a"),
        ])
        #expect(edits.collapsingTableEdits().items == [.addMeasure(keep)])
    }

    @Test func keepsEditsOfTablesStillPresent() {
        let a = table("A")
        let edits = ModelEdits([.addTable(a), .addMeasure(NewMeasure(table: "A", name: "m", expression: "1"))])
        #expect(edits.collapsingTableEdits().items == edits.items)
    }
}
