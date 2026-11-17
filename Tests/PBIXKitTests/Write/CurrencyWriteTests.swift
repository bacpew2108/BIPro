// T103 (`/speckit-converge`, FR-050): cột Fixed decimal (tiền tệ). Desktop 2.159 lưu (quan sát 2026-11-17, golden
// `docs/phase-f-evidence/vm-f7/f9currency-desktop.pbix`): `Column.DataType` 10, FormatString `\$#,0.###############;(\$#,0.###############);\$#,0.###############`,
// giá trị Int64 nhân 10⁴ (`DictionaryStorage.DataType` 6), `Statistics_DBType` 6; giá trị Int64 lớn nhất bị từ chối khi nạp.
import Foundation
import SQLite3
import Testing
@testable import PBIXKit

@Suite(.enabled(if: FileManager.default.fileExists(atPath: DesktopGolden.path.path))) struct CurrencyWriteTests {
    private let money: [Int64?] = (0..<300).map { (i: Int) -> Int64? in
        if i % 7 == 0 { return nil }
        let scaled: Int64 = Int64(i) * 12_345
        return scaled - 12_345_678
    }

    private func build() throws -> Data {
        var changes = PBIXChanges()
        changes.modelEdits.append(.addTable(NewTable(name: "Tien", columns: [
            NewTableColumn(name: "k", values: .int64((0..<300).map { Int64($0) })),
            NewTableColumn(name: "m", values: .currency(money)),
        ])))
        return try PBIXWriter.build(source: DesktopGolden.path, changes: changes).data
    }

    @Test func ghiRoiDocLaiTungO() throws {
        let data = try build()
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let m = try #require(try VertiPaq.decodeTable("Tien", metadata: metadata, abf: abf).first { $0.name == "m" })
        for row in 0..<300 {
            #expect(m[row] == (money[row].map { .decimal(Double($0) / 10_000) } ?? .null), Comment(rawValue: "dòng \(row)"))
        }
        #expect(metadata.columns.first { $0.tableName == "Tien" && $0.name == "m" }?.dataType == .decimal)
    }

    @Test func metadataNhuDesktop() throws {
        let data = try build()
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cur-\(UUID().uuidString).sqlitedb")
        defer { try? FileManager.default.removeItem(at: url) }
        try abf.contents(named: "metadata.sqlitedb").write(to: url)
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = """
            select c.ExplicitDataType, c.FormatString, ds.DataType, cs.Statistics_DBType from [Column] c join [Table] t on t.ID = c.TableID
            join ColumnStorage cs on cs.ID = c.ColumnStorageID join DictionaryStorage ds on ds.ColumnStorageID = cs.ID
            where t.Name = 'Tien' and c.ExplicitName = 'm'
            """
        #expect(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int64(stmt, 0) == 10)
        #expect(String(cString: sqlite3_column_text(stmt, 1)) == #"\$#,0.###############;(\$#,0.###############);\$#,0.###############"#)
        #expect(sqlite3_column_int64(stmt, 2) == 6)
        #expect(sqlite3_column_int64(stmt, 3) == 6)
    }

    @Test func giaTriLonNhatBiTuChoiNhuDesktop() {
        var changes = PBIXChanges()
        changes.modelEdits.append(.addTable(NewTable(name: "Tien", columns: [NewTableColumn(name: "m", values: .currency([1, Int64.max]))])))
        #expect(throws: (any Error).self) { _ = try PBIXWriter.build(source: DesktopGolden.path, changes: changes) }
    }
}
