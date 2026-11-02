import Foundation
import SQLite3
import Testing
@testable import PBIXKit

/// Fixtures are the author's own reports, read only. Tests that need one are disabled when it is absent.
/// Reference output goes to `$PBIX_WP4_OUT` when set, otherwise to the WP4 output folder.
enum MetaFixture {
    static let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    static let tuan62 = downloads.appendingPathComponent("tuan6.2.pbix")
    static let nhom6 = downloads.appendingPathComponent("Nhom6_Dashboard.pbix")

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static let outDir: URL = {
        if let path = ProcessInfo.processInfo.environment["PBIX_WP4_OUT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: "/private/tmp/claude-501/-Users-macprom114-Desktop-PowerBINative/39e5fdc8-d27c-46a2-b750-47ff2adaa733/scratchpad/w/out/wp4", isDirectory: true)
    }()

    /// The `metadata.sqlitedb` member of a report's ABF backup.
    static func metadata(in url: URL) throws -> Data {
        try PBIXFile(url: url).loadDataModel().0.contents(named: "metadata.sqlitedb")
    }

    static func isInvalid(_ error: WriteError?) -> Bool {
        guard let error else { return false }
        if case .invalid = error { return true }
        return false
    }

    /// The thrown `WriteError`, or nil when the body succeeds or throws something else.
    static func writeError<T>(_ body: () throws -> T) -> WriteError? {
        do {
            _ = try body()
            return nil
        } catch let error as WriteError {
            return error
        } catch {
            return nil
        }
    }
}

/// Reads a SQLite file with the C API, to check the output independently of `MetadataWriter`.
enum SQLiteProbe {
    /// Writes the bytes to a scratch file and opens it read-only.
    static func withFile<T>(_ bytes: Data, _ body: (OpaquePointer) throws -> T) throws -> T {
        let folder = MetaFixture.outDir.appendingPathComponent("probe", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("probe-\(UUID().uuidString).sqlitedb")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw SQLiteProbeError.open
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    enum SQLiteProbeError: Error { case open, query(String) }

    static func strings(_ db: OpaquePointer, _ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteProbeError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw SQLiteProbeError.query(String(cString: sqlite3_errmsg(db))) }
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
        }
        return result
    }

    static func int(_ db: OpaquePointer, _ sql: String) throws -> Int64? {
        try strings(db, sql).first.flatMap { Int64($0) }
    }

    /// Largest ID over every table with an `ID` column, computed independently of the writer.
    static func actualMaxID(_ db: OpaquePointer) throws -> Int64 {
        var maxima: [Int64] = []
        for table in try strings(db, "SELECT name FROM sqlite_master WHERE type = 'table'") {
            let quoted = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let hasID = try strings(db, "SELECT name FROM pragma_table_info('\(table.replacingOccurrences(of: "'", with: "''"))')")
                .contains("ID")
            if hasID, let value = try int(db, "SELECT MAX(ID) FROM \(quoted)") { maxima.append(value) }
        }
        return maxima.max() ?? 0
    }

    static func storedMaxID(_ db: OpaquePointer) throws -> Int64? {
        try int(db, "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'MAXID'")
    }
}

/// Edits on tuan6.2 (one user table, Marketing, and no measures).
@Suite(.enabled(if: MetaFixture.exists(MetaFixture.tuan62)))
struct MetadataTuan62Tests {
    static let testMeasure = NewMeasure(table: "Marketing", name: "Test BI Pro", expression: "COUNTROWS('Marketing')",
                                        formatString: "#,0", displayFolder: "Test", isHidden: true)

    /// Adds the test measure and returns the edited bytes together with the new measure's ID.
    static func editedBytes() throws -> (bytes: Data, source: Data, newID: Int) {
        let source = try MetaFixture.metadata(in: MetaFixture.tuan62)
        var writer = try MetadataWriter(sqlite: source)
        let id = try writer.addMeasure(testMeasure)
        return (try writer.serialize(), source, id)
    }

    // (a) Identity: opening and serializing without edits keeps the model.
    @Test func identityRoundTripKeepsModel() throws {
        let source = try MetaFixture.metadata(in: MetaFixture.tuan62)
        let writer = try MetadataWriter(sqlite: source)
        let out = try writer.serialize()
        let before = try ModelMetadata(sqlite: source)
        let after = try ModelMetadata(sqlite: out)

        #expect(after.tables.map(\.name) == before.tables.map(\.name))
        #expect(after.columns.map { "\($0.tableName).\($0.name)" } == before.columns.map { "\($0.tableName).\($0.name)" })
        #expect(after.measures.map(\.name) == before.measures.map(\.name))
        #expect(after.relationships.count == before.relationships.count)
        #expect(after.relationships.map(\.name) == before.relationships.map(\.name))
        #expect(after.hierarchies.count == before.hierarchies.count)
        #expect(after.storage.count == before.storage.count)
        #expect(after.roles == before.roles)
        #expect(after.cultures == before.cultures)
        #expect(after.partitionQueries == before.partitionQueries)
        print("KEY tuan6.2 identity: source \(source.count) B, serialized \(out.count) B, byte-identical \(out == source), tables \(after.tables.count), columns \(after.columns.count), relationships \(after.relationships.count)")
    }

    // (b) Adding one measure: ModelMetadata sees it with the right fields, and the ID follows MAXID.
    @Test func addedMeasureIsVisibleWithExpectedFields() throws {
        let (bytes, source, newID) = try Self.editedBytes()
        let model = try ModelMetadata(sqlite: bytes)
        let added = try #require(model.measures.first { $0.name == "Test BI Pro" })

        #expect(added.tableName == "Marketing")
        #expect(added.expression == "COUNTROWS('Marketing')")
        #expect(added.displayFolder == "Test")
        #expect(added.formatString == "#,0")
        #expect(added.isHidden)
        #expect(model.measures.count == 1)

        let oldMax = try #require(try SQLiteProbe.withFile(source) { try SQLiteProbe.storedMaxID($0) })
        #expect(oldMax == 1024)
        #expect(Int64(newID) == oldMax + 1)
        try SQLiteProbe.withFile(bytes) { db in
            let check1 = try SQLiteProbe.storedMaxID(db)
            #expect(check1 == Int64(newID))
            let check2 = try SQLiteProbe.actualMaxID(db)
            #expect(check2 == Int64(newID))
            let check3 = try SQLiteProbe.int(db, "SELECT ID FROM Measure WHERE Name = 'Test BI Pro'")
            #expect(check3 == Int64(newID))
            // Fields the writer sets by rule.
            let check4 = try SQLiteProbe.int(db, "SELECT State FROM Measure WHERE ID = \(newID)")
            #expect(check4 == 1)
            let check5 = try SQLiteProbe.int(db, "SELECT IsSimpleMeasure FROM Measure WHERE ID = \(newID)")
            #expect(check5 == 0)
            let check6 = try SQLiteProbe.int(db, "SELECT KPIID FROM Measure WHERE ID = \(newID)")
            #expect(check6 == 0)
            let check7 = try SQLiteProbe.int(db, "SELECT DetailRowsDefinitionID FROM Measure WHERE ID = \(newID)")
            #expect(check7 == 0)
            let check8 = try SQLiteProbe.int(db, "SELECT FormatStringDefinitionID FROM Measure WHERE ID = \(newID)")
            #expect(check8 == 0)
            let check9 = try SQLiteProbe.int(db, "SELECT DataType FROM Measure WHERE ID = \(newID)")
            #expect(check9 == 8)
            let modified = try SQLiteProbe.int(db, "SELECT ModifiedTime FROM Measure WHERE ID = \(newID)") ?? 0
            #expect(modified > 134_000_000_000_000_000)
            let check10 = try SQLiteProbe.strings(db, "SELECT typeof(SourceLineageTag) || typeof(ErrorMessage) || typeof(DataCategory) FROM Measure WHERE ID = \(newID)")
            #expect(check10 == ["nullnullnull"])
            let lineage = try SQLiteProbe.strings(db, "SELECT LineageTag FROM Measure WHERE ID = \(newID)")
            #expect(lineage.count == 1 && lineage[0] == lineage[0].lowercased() && UUID(uuidString: lineage[0]) != nil)
        }
    }

    // (c) The output passes SQLite's own integrity check when opened as a file.
    @Test func exportPassesIntegrityCheck() throws {
        let (bytes, _, _) = try Self.editedBytes()
        let result = try SQLiteProbe.withFile(bytes) { try SQLiteProbe.strings($0, "PRAGMA integrity_check") }
        #expect(result == ["ok"])
    }

    // (d) Rejections: unknown table, duplicate name, column name clash, empty expression. A failed call changes nothing.
    @Test func rejectsBadRequestsAndLeavesDatabaseUnchanged() throws {
        let source = try MetaFixture.metadata(in: MetaFixture.tuan62)
        var writer = try MetadataWriter(sqlite: source)
        try writer.addMeasure(Self.testMeasure)
        let beforeFailures = try writer.serialize()

        let unknownTable = MetaFixture.writeError {
            try writer.addMeasure(NewMeasure(table: "NoSuchTable", name: "X", expression: "1"))
        }
        #expect(MetaFixture.isInvalid(unknownTable))

        let duplicate = MetaFixture.writeError { try writer.addMeasure(Self.testMeasure) }
        #expect(MetaFixture.isInvalid(duplicate))

        let duplicateCaseInsensitive = MetaFixture.writeError {
            try writer.addMeasure(NewMeasure(table: "marketing", name: "test bi pro", expression: "1"))
        }
        #expect(MetaFixture.isInvalid(duplicateCaseInsensitive))

        let marketingColumns = try ModelMetadata(sqlite: source).columns.filter { $0.tableName == "Marketing" }
        let columnName = try #require(marketingColumns.first?.name)
        let clash = MetaFixture.writeError {
            try writer.addMeasure(NewMeasure(table: "Marketing", name: columnName, expression: "1"))
        }
        #expect(MetaFixture.isInvalid(clash))

        let emptyExpression = MetaFixture.writeError {
            try writer.addMeasure(NewMeasure(table: "Marketing", name: "Empty", expression: "  "))
        }
        #expect(MetaFixture.isInvalid(emptyExpression))

        let check11 = try writer.serialize()
        #expect(check11 == beforeFailures)
        let model = try ModelMetadata(sqlite: beforeFailures)
        #expect(model.measures.map(\.name) == ["Test BI Pro"])
        try SQLiteProbe.withFile(beforeFailures) { db in
            let check12 = try SQLiteProbe.storedMaxID(db)
            #expect(check12 == 1025)
            let check13 = try SQLiteProbe.actualMaxID(db)
            #expect(check13 == 1025)
        }
    }

    // Timestamp updates are off by default and only change the listed rows when enabled.
    @Test func timestampOptionIsOffByDefault() throws {
        let source = try MetaFixture.metadata(in: MetaFixture.tuan62)
        let sourceStamps = try SQLiteProbe.withFile(source) { db in
            (try SQLiteProbe.int(db, "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'LASTCOMMITTED'"),
             try SQLiteProbe.int(db, "SELECT StructureModifiedTime FROM [Table] WHERE ID = 12"))
        }

        var off = try MetadataWriter(sqlite: source)
        try off.addMeasure(Self.testMeasure)
        let offStamps = try SQLiteProbe.withFile(try off.serialize()) { db in
            (try SQLiteProbe.int(db, "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'LASTCOMMITTED'"),
             try SQLiteProbe.int(db, "SELECT StructureModifiedTime FROM [Table] WHERE ID = 12"))
        }
        #expect(offStamps.0 == sourceStamps.0)
        #expect(offStamps.1 == sourceStamps.1)

        var on = try MetadataWriter(sqlite: source)
        on.updateTimestamps = true
        try on.addMeasure(Self.testMeasure)
        let onStamps = try SQLiteProbe.withFile(try on.serialize()) { db in
            (try SQLiteProbe.int(db, "SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'LASTCOMMITTED'"),
             try SQLiteProbe.int(db, "SELECT StructureModifiedTime FROM [Table] WHERE ID = 12"))
        }
        let sourceCommitted = try #require(sourceStamps.0)
        let onCommitted = try #require(onStamps.0)
        let onStructure = try #require(onStamps.1)
        #expect(onCommitted > sourceCommitted)
        #expect(onStructure > (sourceStamps.1 ?? 0))
    }

    // (f) Reference output for the lead to inspect with REA inspect_sqlite_database.
    @Test func writesReferenceOutput() throws {
        let (bytes, _, newID) = try Self.editedBytes()
        try FileManager.default.createDirectory(at: MetaFixture.outDir, withIntermediateDirectories: true)
        let url = MetaFixture.outDir.appendingPathComponent("tuan6.2.metadata-test.sqlitedb")
        try bytes.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        print("KEY tuan6.2 reference: \(url.path) \(bytes.count) B, new measure ID \(newID)")
    }
}

/// Edits on Nhom6 (168 measures, 141 tables).
@Suite(.enabled(if: MetaFixture.exists(MetaFixture.nhom6)))
struct MetadataNhom6Tests {
    // (e) 168 measures become 169, and MAXID matches the largest ID afterwards.
    @Test func addingMeasureToNhom6UpdatesCountAndMaxID() throws {
        let source = try MetaFixture.metadata(in: MetaFixture.nhom6)
        let check14 = try ModelMetadata(sqlite: source).measures.count
        #expect(check14 == 168)
        let sourceMax = try SQLiteProbe.withFile(source) { db in
            (try SQLiteProbe.storedMaxID(db), try SQLiteProbe.actualMaxID(db))
        }
        #expect(sourceMax.0 == sourceMax.1)
        #expect(sourceMax.0 == 11889)

        var writer = try MetadataWriter(sqlite: source)
        let newID = try writer.addMeasure(NewMeasure(table: "Fact_Transaction", name: "Test BI Pro",
                                                     expression: "COUNTROWS('Fact_Transaction')"))
        let out = try writer.serialize()

        let check15 = try ModelMetadata(sqlite: out).measures.count
        #expect(check15 == 169)
        #expect(newID == 11890)
        try SQLiteProbe.withFile(out) { db in
            let stored = try SQLiteProbe.storedMaxID(db)
            #expect(stored == Int64(newID))
            let check16 = try SQLiteProbe.actualMaxID(db)
            #expect(check16 == stored)
            let check17 = try SQLiteProbe.int(db, "SELECT COUNT(*) FROM Measure")
            #expect(check17 == 169)
            let check18 = try SQLiteProbe.strings(db, "PRAGMA integrity_check")
            #expect(check18 == ["ok"])
        }
    }
}

/// Invalid input is rejected without any fixture.
@Suite struct MetadataInvalidInputTests {
    @Test func emptyBytesAreInvalid() {
        #expect(MetaFixture.isInvalid(MetaFixture.writeError { try MetadataWriter(sqlite: Data()) }))
    }

    @Test func nonDatabaseBytesAreInvalid() {
        let text = Data("this is not a sqlite database, only plain text padding for the test".utf8)
        #expect(MetaFixture.isInvalid(MetaFixture.writeError { try MetadataWriter(sqlite: text) }))
    }

    @Test func databaseWithoutMetadataTablesIsInvalid() throws {
        let folder = MetaFixture.outDir.appendingPathComponent("probe", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("other-\(UUID().uuidString).sqlitedb")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        try #require(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
        try #require(sqlite3_exec(db, "CREATE TABLE other (x INTEGER); INSERT INTO other VALUES (1);", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let bytes = try Data(contentsOf: url)
        #expect(MetaFixture.isInvalid(MetaFixture.writeError { try MetadataWriter(sqlite: bytes) }))
    }
}
