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

    // T116: sửa và xoá cột, bảng tính toán trong cùng đợt lưu.

    @Test func calculatedColumnAddedThenEditedBecomesOneAdd() {
        let edits = ModelEdits([
            .addCalculatedColumn(table: "Sales", name: "c", expression: "1", dataType: .int64),
            .updateColumn(table: "Sales", name: "c", patch: ColumnPatch(isHidden: true)),
            .updateCalculatedColumn(table: "Sales", name: "c", expression: "\"a\"", dataType: .string),
        ])
        #expect(edits.collapsingTableEdits().items == [
            .addCalculatedColumn(table: "Sales", name: "c", expression: "\"a\"", dataType: .string),
            .updateColumn(table: "Sales", name: "c", patch: ColumnPatch(isHidden: true)),
        ])
    }

    @Test func calculatedColumnAddedThenDeletedLeavesNothing() {
        let keep = ModelEdit.updateColumn(table: "Sales", name: "k", patch: ColumnPatch(isHidden: true))
        let edits = ModelEdits([
            .addCalculatedColumn(table: "Sales", name: "c", expression: "1", dataType: .int64),
            .updateColumn(table: "Sales", name: "c", patch: ColumnPatch(isHidden: true)),
            keep,
            .deleteCalculatedColumn(table: "Sales", name: "c"),
        ])
        #expect(edits.collapsingTableEdits().items == [keep])
    }

    @Test func existingCalculatedColumnKeepsOnlyTheLastEditOrTheDelete() {
        let edits = ModelEdits([
            .updateCalculatedColumn(table: "Sales", name: "c", expression: "1", dataType: .int64),
            .updateCalculatedColumn(table: "Sales", name: "c", expression: "2", dataType: .int64),
        ])
        #expect(edits.collapsingTableEdits().items == [.updateCalculatedColumn(table: "Sales", name: "c", expression: "2", dataType: .int64)])
        let deleted = ModelEdits(edits.items + [.deleteCalculatedColumn(table: "Sales", name: "c")])
        #expect(deleted.collapsingTableEdits().items == [.deleteCalculatedColumn(table: "Sales", name: "c")])
    }

    @Test func renamedAddedColumnStillCollapses() {
        let edits = ModelEdits([
            .addCalculatedColumn(table: "Sales", name: "c", expression: "1", dataType: .int64),
            .updateColumn(table: "Sales", name: "c", patch: ColumnPatch(name: "d")),
            .deleteCalculatedColumn(table: "Sales", name: "d"),
        ])
        #expect(edits.collapsingTableEdits().items.isEmpty)
    }

    @Test func calculatedTableAddedEditedOrDropped() {
        let columns = [ColumnSignature(name: "Region", dataType: .string)]
        let edited = ModelEdits([
            .addCalculatedTable(name: "V", expression: "DISTINCT(Sales[Region])", columns: columns),
            .updateCalculatedTable(name: "V", expression: "VALUES(Sales[Region])", columns: columns),
        ])
        #expect(edited.collapsingTableEdits().items == [.addCalculatedTable(name: "V", expression: "VALUES(Sales[Region])", columns: columns)])
        let dropped = ModelEdits(edited.items + [
            .addCalculatedColumn(table: "V", name: "w", expression: "1", dataType: .int64),
            .dropTable(name: "V"),
        ])
        #expect(dropped.collapsingTableEdits().items.isEmpty)
        // Bảng có sẵn trong file: sửa công thức rồi xoá thì chỉ còn xoá.
        let existing = ModelEdits([
            .updateCalculatedTable(name: "W", expression: "VALUES(Sales[Region])", columns: columns),
            .updateCalculatedColumn(table: "W", name: "x", expression: "1", dataType: .int64),
            .dropTable(name: "W"),
        ])
        #expect(existing.collapsingTableEdits().items == [.dropTable(name: "W")])
    }
}
