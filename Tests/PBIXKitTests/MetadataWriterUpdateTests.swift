import Foundation
import Testing
@testable import PBIXKit

/// Phase E (T005): `MetadataWriter.apply` ghi đúng như Power BI Desktop (docs/phase-e-evidence/vm-e1/QUAN-SAT.md):
/// UPDATE tại chỗ, giữ `ID`/`LineageTag`/`StructureModifiedTime`, đặt `ModifiedTime`, cập nhật các `DBPROPERTIES`.
@Suite("Phase E: MetadataWriter.apply", .enabled(if: ModelEditFixture.data != nil)) struct MetadataWriterUpdateTests {
    let source = ModelEditFixture.data!
    let base = ModelEditFixture.metadata!

    private func edited(_ edits: [ModelEdit]) throws -> Data {
        var writer = try MetadataWriter(sqlite: source)
        try writer.apply(ModelEdits(edits))
        return try writer.serialize()
    }

    private func scalar(_ bytes: Data, _ sql: String) throws -> String? {
        try SQLiteProbe.withFile(bytes) { try SQLiteProbe.strings($0, sql).first }
    }

    private func firstMeasure(where predicate: @escaping (ModelMetadata.Measure) -> Bool = { _ in true }) throws -> ModelMetadata.Measure {
        try #require(base.measures.first(where: predicate))
    }

    @Test func suaMeasureTaiChoKhopMoHinhHieuLuc() throws {
        let m = try firstMeasure { $0.formatStringDefinition == nil }
        let patch = MeasurePatch(expression: "1+1", formatString: .set("0.0"), displayFolder: .set("Thu muc E"),
                                 description: .set("mo ta E"), isHidden: true)
        let edits: [ModelEdit] = [.updateMeasure(table: m.tableName, name: m.name, patch: patch)]
        let bytes = try edited(edits)
        let read = try ModelMetadata(sqlite: bytes)
        let expected = try base.applying(ModelEdits(edits))
        #expect(read.measures == expected.measures)
        // Giữ ID, LineageTag, StructureModifiedTime; đổi ModifiedTime.
        let sql = "SELECT %@ FROM Measure WHERE Name = '\(m.name.replacingOccurrences(of: "'", with: "''"))' AND TableID = (SELECT ID FROM [Table] WHERE Name = '\(m.tableName)')"
        for column in ["ID", "LineageTag", "StructureModifiedTime", "DataType"] {
            let before = try scalar(source, String(format: sql, column))
            let after = try scalar(bytes, String(format: sql, column))
            #expect(before == after, "\(column) phải giữ nguyên")
        }
        let beforeTime = try #require(try scalar(source, String(format: sql, "ModifiedTime")).flatMap(Int64.init))
        let afterTime = try #require(try scalar(bytes, String(format: sql, "ModifiedTime")).flatMap(Int64.init))
        #expect(afterTime > beforeTime)
        // DBPROPERTIES cập nhật, MAXID giữ.
        let committed = "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'LASTCOMMITTED'"
        #expect(try Int64(scalar(bytes, committed)!)! > Int64(scalar(source, committed)!)!)
        let maxID = "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'MAXID'"
        #expect(try scalar(bytes, maxID) == scalar(source, maxID))
        _ = try MetadataWriter(sqlite: bytes)   // integrity_check
    }

    @Test func themMeasureCoChinhXacCacTruongDesktopGhi() throws {
        let new = NewMeasure(table: "Dim_Account", name: "E_Test", expression: "COUNTROWS(Dim_Account)+1",
                             formatString: "0", displayFolder: "Thu muc E", description: "mo ta E", dataType: 6)
        let bytes = try edited([.addMeasure(new)])
        let read = try ModelMetadata(sqlite: bytes)
        let added = try #require(read.measures.first { $0.name == "E_Test" })
        #expect(added.dataType == .int64 && added.formatString == "0" && added.displayFolder == "Thu muc E")
        #expect(added.state == 1 && added.lineageTag != nil)
        #expect(try Int64(scalar(bytes, "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'MAXID'")!)! == Int64(scalar(source, "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'MAXID'")!)! + 1)
        let committed = "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'LASTCOMMITTED'"
        #expect(try Int64(scalar(bytes, committed)!)! > Int64(scalar(source, committed)!)!)
        // Desktop cập nhật Table.ModifiedTime của bảng chứa khi thêm measure (VM-E1).
        let tableTime = "SELECT ModifiedTime FROM [Table] WHERE Name = 'Dim_Account'"
        #expect(try Int64(scalar(bytes, tableTime)!)! > Int64(scalar(source, tableTime)!)!)
    }

    @Test func xoaMeasureDonCacDongPhuThuoc() throws {
        let m = try firstMeasure { $0.formatStringDefinition != nil }
        let id = try #require(try scalar(source, "SELECT ID FROM Measure WHERE Name = '\(m.name.replacingOccurrences(of: "'", with: "''"))' AND TableID = (SELECT ID FROM [Table] WHERE Name = '\(m.tableName)')").flatMap(Int.init))
        #expect(try scalar(source, "SELECT COUNT(*) FROM FormatStringDefinition WHERE ObjectID = \(id)") != "0")
        let bytes = try edited([.deleteMeasure(table: m.tableName, name: m.name)])
        let read = try ModelMetadata(sqlite: bytes)
        #expect(read.measures.count == base.measures.count - 1)
        #expect(!read.measures.contains { $0.tableName == m.tableName && $0.name == m.name })
        #expect(try scalar(bytes, "SELECT COUNT(*) FROM FormatStringDefinition WHERE ObjectID = \(id)") == "0")
        #expect(try scalar(bytes, "SELECT COUNT(*) FROM Measure WHERE ID = \(id)") == "0")
        // Desktop cập nhật Table.ModifiedTime của bảng chứa khi xoá measure (VM-E2).
        let tableTime = "SELECT ModifiedTime FROM [Table] WHERE Name = '\(m.tableName)'"
        #expect(try Int64(scalar(bytes, tableTime)!)! > Int64(scalar(source, tableTime)!)!)
        _ = try MetadataWriter(sqlite: bytes)
    }

    @Test func suaQuanHeChiDoiHaiTruong() throws {
        let rel = try #require(base.relationships.first { $0.isActive && $0.crossFilteringBehavior == 1 })
        let edits: [ModelEdit] = [.updateRelationship(name: rel.name, patch: RelationshipPatch(isActive: true, crossFilteringBehavior: 2))]
        let bytes = try edited(edits)
        let read = try ModelMetadata(sqlite: bytes)
        #expect(read.relationships == (try base.applying(ModelEdits(edits))).relationships)
        let row = "SELECT %@ FROM Relationship WHERE Name = '\(rel.name)'"
        #expect(try scalar(bytes, String(format: row, "CrossFilteringBehavior")) == "2")
        for column in ["ID", "FromColumnID", "ToColumnID", "FromCardinality", "ToCardinality", "RelationshipStorageID", "RefreshedTime"] {
            #expect(try scalar(source, String(format: row, column)) == scalar(bytes, String(format: row, column)), "\(column) giữ nguyên")
        }
        let before = try #require(try scalar(source, String(format: row, "ModifiedTime")).flatMap(Int64.init))
        let after = try #require(try scalar(bytes, String(format: row, "ModifiedTime")).flatMap(Int64.init))
        #expect(after > before)
        // Không đụng chỉ mục quan hệ.
        #expect(try scalar(bytes, "SELECT COUNT(*) FROM RelationshipIndexStorage") == scalar(source, "SELECT COUNT(*) FROM RelationshipIndexStorage"))
    }

    @Test func suaCotKhopMoHinhHieuLuc() throws {
        let userTableNames = Set(base.userTables.map(\.name))
        let data = base.columns.filter { $0.kind == .data && userTableNames.contains($0.tableName) }
        let column = try #require(data.first { !$0.isHidden && $0.displayFolder == nil })
        let sort = try #require(data.first { $0.tableName == column.tableName && $0.id != column.id })
        let patch = ColumnPatch(isHidden: true, formatString: .set("0.00"), summarizeBy: 3, dataCategory: .set("City"),
                                sortBy: .set(sort.name), displayFolder: .set("Thu muc"), description: .set("mo ta"))
        let edits: [ModelEdit] = [.updateColumn(table: column.tableName, name: column.name, patch: patch)]
        let bytes = try edited(edits)
        let read = try ModelMetadata(sqlite: bytes)
        #expect(read.columns == (try base.applying(ModelEdits(edits))).columns)
        let id = column.id
        #expect(try scalar(bytes, "SELECT ColumnStorageID FROM [Column] WHERE ID = \(id)") == scalar(source, "SELECT ColumnStorageID FROM [Column] WHERE ID = \(id)"))
        // Đổi tên đặt ExplicitName.
        let renamed = try edited([.updateColumn(table: column.tableName, name: column.name, patch: ColumnPatch(name: "Cot Moi"))])
        #expect(try ModelMetadata(sqlite: renamed).columns.contains { $0.id == id && $0.name == "Cot Moi" })
    }

    @Test func anBangGhiIsHiddenCuaBang() throws {
        let table = try #require(base.userTables.first { !$0.isHidden })
        let edits: [ModelEdit] = [.updateTable(name: table.name, patch: TablePatch(isHidden: true))]
        let bytes = try edited(edits)
        let read = try ModelMetadata(sqlite: bytes)
        #expect(read.tables.first { $0.name == table.name }?.isHidden == true)
        #expect(read.tables.filter { $0.name != table.name }.map(\.isHidden) == base.tables.filter { $0.name != table.name }.map(\.isHidden))
    }

    @Test func loiGiuNguyenCoSoDuLieu() throws {
        var writer = try MetadataWriter(sqlite: source)
        #expect(throws: (any Error).self) {
            try writer.apply(ModelEdits([.updateMeasure(table: "Dim_Account", name: "Khong Co", patch: MeasurePatch(expression: "1"))]))
        }
        #expect(throws: (any Error).self) {
            try writer.apply(ModelEdits([.updateRelationship(name: "khong co", patch: RelationshipPatch(isActive: false))]))
        }
        let out = try writer.serialize()
        #expect(try ModelMetadata(sqlite: out).measures == base.measures)
    }
}
