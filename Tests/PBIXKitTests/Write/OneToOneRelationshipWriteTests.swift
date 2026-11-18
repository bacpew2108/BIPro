// T066: quan hệ một–một (`w8.3.pbix`: `Thông tin nhân viên[ID nhân viên]` ↔ `Đào tạo nhân viên[ID nhân viên]`, hai chiều, không hoạt động).
// Desktop ghi hai bộ lưu trữ: `RelationshipStorageID` chỉ mục cột phía "từ", `RelationshipStorage2ID` chỉ mục ngược, mỗi bộ một bảng `R$`.
// Xoá rồi ghi lại cùng tên, cùng dữ liệu: hai tệp chỉ mục trùng từng byte Desktop; thay dữ liệu bảng có quan hệ này thì dựng lại được.
import Foundation
@testable import PBIXKit
import Testing

@Suite(.enabled(if: F2Fixtures.w83 != nil))
struct OneToOneRelationshipWriteTests {
    private static var source: URL { F2Fixtures.w83! }

    /// Tệp `.idf`/`.idfmeta` của bảng `R$<bảng>…` thuộc quan hệ `name`.
    private func indexFiles(_ m: HierarchyIndexWriterTests.Loaded, relationship name: String, table: String) throws -> (idf: Data, meta: Data) {
        let spaced = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        func file(_ suffix: String) throws -> Data {
            let f = try #require(m.abf.files.first { $0.path.contains("R$\(table) (") && $0.path.contains("$\(spaced) (") && $0.fileName.hasSuffix(suffix) })
            return m.abf.contents(of: f)
        }
        return (try file(".INDEX.0.idf"), try file(".INDEX.0.idfmeta"))
    }

    private func storageRows(_ m: HierarchyIndexWriterTests.Loaded, _ name: String) throws -> [String] {
        try m.db.rows("""
            SELECT r.FromCardinality, r.ToCardinality, r.IsActive, r.CrossFilteringBehavior, i.RecordCount,
                   (SELECT t.Name FROM [Table] t WHERE t.ID = i.SystemTableID), s.ID = r.RelationshipStorage2ID
            FROM Relationship r JOIN RelationshipStorage s ON s.RelationshipID = r.ID JOIN RelationshipIndexStorage i ON i.RelationshipStorageID = s.ID
            WHERE r.Name = '\(name)' ORDER BY s.ID = r.RelationshipStorage2ID
            """).map { row in
            let table = (row.string(5) ?? "").replacingOccurrences(of: #"\(\d+\)$"#, with: "", options: .regularExpression)
            return "\(row.int(0))|\(row.int(1))|\(row.int(2))|\(row.int(3))|\(row.int(4))|\(table)|\(row.int(6))"
        }
    }

    @Test func ghiLaiMotMotTrungByteDesktop() throws {
        let before = try HierarchyIndexWriterTests.load(Self.source)
        let old = try #require(before.metadata.relationships.first { $0.cardinality == "1:1" })
        let fromStorage = "Thông tin nhân viên", toStorage = "Đào tạo nhân viên"
        #expect(old.fromTable == fromStorage && old.toTable == toStorage)
        let desktopFrom = try indexFiles(before, relationship: old.name, table: fromStorage)
        let desktopTo = try indexFiles(before, relationship: old.name, table: toStorage)
        let desktopRows = try storageRows(before, old.name)
        #expect(desktopRows.count == 2)

        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([
            .deleteRelationship(name: old.name),
            .addRelationship(NewRelationship(name: old.name, fromTable: old.fromTable, fromColumn: old.fromColumn, toTable: old.toTable,
                                             toColumn: old.toColumn, fromMany: false, toMany: false, isActive: old.isActive,
                                             crossFilteringBehavior: old.crossFilteringBehavior)),
        ])
        let url = try HierarchyIndexWriterTests.write(PBIXWriter.build(source: Self.source, changes: changes).data)
        defer { try? FileManager.default.removeItem(at: url) }
        let after = try HierarchyIndexWriterTests.load(url)
        #expect(after.metadata.relationships.first { $0.name == old.name } == old)
        // Tên bảng R$ có ID quan hệ mới ở cuối: so phần trước đó.
        func stripID(_ rows: [String]) -> [String] { rows.map { $0.replacingOccurrences(of: #" \(\d+\)\|"#, with: "|", options: .regularExpression) } }
        #expect(stripID(try storageRows(after, old.name)) == stripID(desktopRows))
        let mineFrom = try indexFiles(after, relationship: old.name, table: fromStorage)
        let mineTo = try indexFiles(after, relationship: old.name, table: toStorage)
        #expect(mineFrom.idf == desktopFrom.idf && mineFrom.meta == desktopFrom.meta)
        #expect(mineTo.idf == desktopTo.idf && mineTo.meta == desktopTo.meta)
    }
}
