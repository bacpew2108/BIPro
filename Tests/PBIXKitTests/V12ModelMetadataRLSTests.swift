import Foundation
import PBIXKit
import Testing

@Suite("Wave 4 (v1.2) — PBIXKit Mark as Date Table & RLS SQLite Round-Trip")
struct V12ModelMetadataRLSTests {
    @Test("ModelMetadata + MetadataWriter ghi & đọc lại Mark as Date Table (DataCategory=Time, IsKey=1) và RLS Role/TablePermission")
    func markAsDateTableAndRLSRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("v12-rls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let blankURL = root.appendingPathComponent("blank.pbix")
        try NewDocument.blank().write(to: blankURL)
        let basePBIX = try PBIXFile(url: blankURL)
        let (baseABF, _) = try basePBIX.loadDataModel()
        let baseSQLite = try baseABF.contents(named: "metadata.sqlitedb")
        let baseMeta = try ModelMetadata(sqlite: baseSQLite)

        let calTable = NewTable(
            name: "DimCalendar",
            columns: [
                NewTableColumn(name: "Date", values: .dateTime([45292, 45293, 45294])),
                NewTableColumn(name: "Region", values: .string(["North", "South", "West"])),
            ],
            queryExpression: #"let Source = #table({"Date","Region"}, {}) in Source"#
        )
        let rlsRole = ModelMetadata.RoleDefinition(
            name: "NorthOnly",
            description: "Chỉ xem miền Bắc",
            modelPermission: 2,
            tablePermissions: [
                ModelMetadata.TablePermission(tableName: "DimCalendar", filterExpression: #"DimCalendar[Region] = "North""#),
            ]
        )

        var edits = ModelEdits()
        edits.append(.addTable(calTable))
        edits.append(.updateTable(name: "DimCalendar", patch: TablePatch(dataCategory: .set("Time"))))
        edits.append(.updateColumn(table: "DimCalendar", name: "Date", patch: ColumnPatch(isKey: true)))
        edits.append(.upsertRole(previousName: nil, role: rlsRole))

        // 1. Kiểm áp trên bộ nhớ (`ModelMetadata.applying`)
        let inMem = try baseMeta.applying(edits)
        let memTable = try #require(inMem.tables.first { $0.name == "DimCalendar" })
        #expect(memTable.dataCategory == "Time")
        let memDateCol = try #require(inMem.columns.first { $0.tableName == "DimCalendar" && $0.name == "Date" })
        #expect(memDateCol.isKey == true)
        #expect(inMem.roles == ["NorthOnly"])
        #expect(inMem.roleDefinitions.count == 1)
        #expect(inMem.roleDefinitions[0].tablePermissions.first?.filterExpression == #"DimCalendar[Region] = "North""#)

        // 2. Ghi trọn vẹn qua PBIXWriter.build (kèm tự kiểm đọc lại) rồi mở lại từ đĩa
        let savedURL = root.appendingPathComponent("v12-rls-saved.pbix")
        var changes = PBIXChanges()
        changes.modelEdits = edits
        let built1 = try PBIXWriter.build(source: blankURL, changes: changes).data
        try built1.write(to: savedURL)

        let reopenedMeta = try ModelMetadata(sqlite: try PBIXFile(data: built1).loadDataModel().0.contents(named: "metadata.sqlitedb"))
        #expect(reopenedMeta.tables.first { $0.name == "DimCalendar" }?.dataCategory == "Time")
        #expect(reopenedMeta.columns.first { $0.tableName == "DimCalendar" && $0.name == "Date" }?.isKey == true)
        #expect(reopenedMeta.roleDefinitions == [rlsRole])

        // 3. Cập nhật vai trò (đổi tên + sửa biểu thức) rồi xoá vai trò
        let updatedRole = ModelMetadata.RoleDefinition(
            name: "SouthOnly",
            description: "Miền Nam",
            modelPermission: 2,
            tablePermissions: [ModelMetadata.TablePermission(tableName: "DimCalendar", filterExpression: #"DimCalendar[Region] = "South""#)]
        )
        var ch2 = PBIXChanges()
        ch2.modelEdits.append(.upsertRole(previousName: "NorthOnly", role: updatedRole))
        let built2 = try PBIXWriter.build(source: savedURL, changes: ch2).data
        let saved2URL = root.appendingPathComponent("v12-rls-updated.pbix")
        try built2.write(to: saved2URL)
        let meta2 = try ModelMetadata(sqlite: try PBIXFile(data: built2).loadDataModel().0.contents(named: "metadata.sqlitedb"))
        #expect(meta2.roleDefinitions == [updatedRole])

        var ch3 = PBIXChanges()
        ch3.modelEdits.append(.deleteRole(name: "SouthOnly"))
        let built3 = try PBIXWriter.build(source: saved2URL, changes: ch3).data
        let meta3 = try ModelMetadata(sqlite: try PBIXFile(data: built3).loadDataModel().0.contents(named: "metadata.sqlitedb"))
        #expect(meta3.roleDefinitions.isEmpty)
    }
}
