// Phase F, T015: what Desktop required of a new table before it opened the file (gate F-T3, 2026-11-15, `docs/phase-f-evidence/vm-f0/`):
// valid M in the partition, `Alignment` 1, `FormatString` of whole numbers, one `H$` system table per data column, RowNumber with the
// value-encoded dictionary row. Run on `tuan6.2.pbix` (a Desktop file); the file itself was opened in Desktop as `W4_h.pbix`.
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: FileManager.default.fileExists(atPath: DesktopGolden.path.path))) struct TableMetadataWriterV2Tests {
    private func build() throws -> (writer: TableMetadataWriter, table: VertiPaqWriter.EncodedTable, abf: ABFBackup, rebuilt: ABFBackup) {
        let abf = try PBIXFile(url: DesktopGolden.path).loadDataModel().0
        let file = try #require(abf.file(named: "metadata.sqlitedb"))
        var writer = try TableMetadataWriter(sqlite: try abf.contents(of: file))
        let base = writer.maxID
        let table = try VertiPaqWriter.encodeTable(name: "BiProTest", tableID: base + 1, partitionID: base + 2, rowNumberID: base + 3, columns: [
            .init(id: base + 4, name: "Số lượng", values: .int64((0..<100).map { Int64($0) })),
            .init(id: base + 5, name: "Đơn giá", values: .double((0..<100).map { Double($0 % 10) / 4 })),
            .init(id: base + 6, name: "Thành phố", values: .string((0..<100).map { $0 == 7 ? nil : ["Hà Nội", "Huế"][$0 % 2] })),
        ])
        try writer.addTable(table)
        let rebuilt = try ABFBackup(data: try ABFWriter.rebuild(
            abf, replacing: [ABFPayload(path: file.path, data: try writer.serialize())],
            adding: (table.files + writer.systemFiles).map { ABFPayload(path: $0.path, data: $0.data) }, removing: []))
        return (writer, table, abf, rebuilt)
    }

    private func db(_ writer: TableMetadataWriter) throws -> TableMetadataDatabase {
        try TableMetadataDatabase(bytes: try writer.serialize())
    }

    @Test func phanVungCoTruyVanMHopLeVaCotDungGiaTriDesktop() throws {
        let (writer, _, _, _) = try build()
        let database = try db(writer)
        let query = try #require(database.strings("SELECT QueryDefinition FROM Partition WHERE Name = 'BiProTest'").first)
        #expect(query.hasPrefix("let") && query.contains("#table(type table [") && query.hasSuffix("Source"))
        #expect(query.contains("#\"Số lượng\" = Int64.Type") && query.contains("#\"Thành phố\" = text"))
        let tableID = try #require(try database.int("SELECT ID FROM [Table] WHERE Name = 'BiProTest'"))
        #expect(try database.int("SELECT COUNT(*) FROM [Column] WHERE TableID = ? AND Alignment <> 1", [.int(tableID)]) == 0)
        #expect(try database.strings("SELECT FormatString FROM [Column] WHERE TableID = ? AND ExplicitName = 'Số lượng'", [.int(tableID)]) == ["0"])
        // Desktop: Partition.DataView 3 for the loaded partition.
        #expect(try database.int("SELECT DataView FROM Partition WHERE Name = 'BiProTest'") == 3)
    }

    @Test func moiCotDuLieuCoBangHeThongHashVaTepCuaNo() throws {
        let (writer, table, _, rebuilt) = try build()
        let database = try db(writer)
        let columns = table.columns.filter { $0.kind == .data }
        #expect(try database.int("SELECT COUNT(*) FROM [Table] WHERE Name LIKE 'H$BiProTest (%' AND IsHidden = 1 AND SystemFlags = 1") == Int64(columns.count))
        #expect(writer.systemFiles.count == columns.count * 4)           // POS_TO_ID, ID_TO_POS, each with .idf and .idfmeta
        let paths = Set(rebuilt.files.map(\.path))
        for file in writer.systemFiles { #expect(paths.contains(file.path), Comment(rawValue: file.path)) }
        // AttributeHierarchyStorage points at that table; RowNumber has none.
        #expect(try database.int("""
            SELECT COUNT(*) FROM AttributeHierarchyStorage a JOIN [Table] t ON t.ID = a.SystemTableID
            WHERE t.Name LIKE 'H$BiProTest (%'
            """) == Int64(columns.count))
        for column in columns {
            let rows = try database.int("""
                SELECT s.RecordCount FROM SegmentMapStorage s JOIN PartitionStorage p ON p.ID = s.PartitionStorageID
                WHERE p.Name = ?
                """, [.text("H$BiProTest (\(table.tableID))$\(column.explicitName) (\(column.id))")])
            let expected = try #require(column.hierarchy).recordCount
            #expect(rows == Int64(expected), Comment(rawValue: column.explicitName))
        }
    }

    @Test func rowNumberKhongCoTuDienNhungCoLastIdVaSizeCuaDesktop() throws {
        let (writer, table, _, _) = try build()
        let database = try db(writer)
        let rowNumber = try #require(table.columns.first { $0.kind == .rowNumber })
        #expect(rowNumber.explicitName == "RowNumber-2662979B-1795-4F74-8F37-6A1BA8059B61")
        let row = try database.strings("""
            SELECT d.LastId || ',' || d.Size || ',' || d.Type || ',' || d.BaseId FROM DictionaryStorage d
            JOIN ColumnStorage c ON c.ID = d.ColumnStorageID WHERE c.ColumnID = ?
            """, [.int(Int64(rowNumber.id))])
        #expect(row == ["2,144,2,-3"])
    }

    @Test func themBangKhongPhaDuongToanVenMetadata() throws {
        let (writer, _, _, _) = try build()
        // MAXID is the largest ID again (checked by the initializer) and SQLite agrees.
        _ = try TableMetadataWriter(sqlite: try writer.serialize())
        try db(writer).requireIntegrity()
    }
}
