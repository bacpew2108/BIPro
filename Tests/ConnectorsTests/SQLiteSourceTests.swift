import Testing
import Foundation
import ColumnStore
@testable import Connectors

#if canImport(Darwin)
import Darwin
#endif
import SQLite3

@Suite struct SQLiteSourceTests {

    // MARK: - Sample Fixture Tests

    @Test func sales2026SQLiteItemsAndLoad() async throws {
        guard let url = FFixtures.sample("sales_2026.sqlite") else { return }
        let source = SQLiteSource(url: url)
        let items = try await source.items()

        #expect(items.count == 3)
        let itemNames = items.map(\.name)
        #expect(itemNames.contains("Sales"))
        #expect(itemNames.contains("Customers"))
        #expect(itemNames.contains("NorthSales"))

        let salesItem = try #require(items.first { $0.name == "Sales" })
        #expect(salesItem.kind == .table)
        #expect(salesItem.rowCountHint == 1000)

        let custItem = try #require(items.first { $0.name == "Customers" })
        #expect(custItem.kind == .table)
        #expect(custItem.rowCountHint == 50)

        let viewItem = try #require(items.first { $0.name == "NorthSales" })
        #expect(viewItem.kind == .view)
        #expect(viewItem.rowCountHint == nil) // không chạy count cho view

        // Preview Sales
        let preview = try await salesItem.preview(limit: 5)
        #expect(preview.rowCount == 5)
        #expect(preview.columns[0].name == "OrderID")
        #expect(preview.columns[1].name == "OrderDate")
        #expect(preview.columns[1].data.type == .string) // TEXT khai báo -> string
        #expect(preview.value(row: 0, column: 0) == .integer(1))
        #expect(preview.value(row: 0, column: 1) == .string("2026-03-02"))
        #expect(preview.value(row: 0, column: 2) == .string("Trung tâm"))
        #expect(preview.value(row: 0, column: 3) == .integer(7))
        #expect(preview.value(row: 0, column: 4) == .string("Đồng hồ"))
        #expect(preview.value(row: 0, column: 5) == .integer(11))
        #expect(preview.value(row: 0, column: 6) == .double(120.0))
        #expect(preview.value(row: 0, column: 7) == .double(1320.0))

        // Load Sales
        let salesTable = try await salesItem.load(progress: nil)
        #expect(salesTable.rowCount == 1000)
        #expect(salesTable.columns[0].data.type == .integer)
        #expect(salesTable.columns[1].data.type == .string)
        #expect(salesTable.columns[5].data.type == .integer)
        #expect(salesTable.columns[6].data.type == .double)
        #expect(salesTable.columns[7].data.type == .double)

        var sumQty: Int64 = 0
        var sumAmount: Double = 0
        for r in 0..<salesTable.rowCount {
            if case .integer(let q) = salesTable.value(row: r, column: 5) { sumQty += q }
            if case .double(let a) = salesTable.value(row: r, column: 7) { sumAmount += a }
        }
        #expect(sumQty == 9972)
        #expect(abs(sumAmount - 350317.03) < 0.02)

        // Load Customers
        let custTable = try await custItem.load(progress: nil)
        #expect(custTable.rowCount == 50)

        // Load NorthSales View
        let viewTable = try await viewItem.load(progress: nil)
        #expect(viewTable.rowCount == 201)
    }

    // MARK: - Edge Cases & Invariant Tests (with temp SQLite DB)

    private func withTempDB(_ body: (URL) async throws -> Void) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("test.db")
        try await body(dbURL)
    }

    /// T108 (SC-003): liệt kê không quét bảng lớn. Bảng có `MAX(rowid)` quá 100 000 không có số dòng lúc liệt kê; nạp cả bảng
    /// mới đếm để báo tiến độ. Bảng nhỏ đếm đúng (kể cả khi đã xoá dòng), bảng WITHOUT ROWID không đếm.
    @Test func listingSkipsCountOnLargeTables() async throws {
        try await withTempDB { url in
            var db: OpaquePointer?
            sqlite3_open(url.path, &db)
            defer { sqlite3_close(db) }
            sqlite3_exec(db, """
                CREATE TABLE Big (id INTEGER PRIMARY KEY, v INTEGER);
                WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 150000) INSERT INTO Big SELECT i, i % 7 FROM n;
                CREATE TABLE Small (id INTEGER PRIMARY KEY, v TEXT);
                INSERT INTO Small VALUES (1, 'a'), (2, 'b'), (3, 'c'), (900000, 'd');
                DELETE FROM Small WHERE id = 2;
                CREATE TABLE NoRowid (k TEXT PRIMARY KEY, v INTEGER) WITHOUT ROWID;
                INSERT INTO NoRowid VALUES ('x', 1), ('y', 2);
                """, nil, nil, nil)

            let items = try await SQLiteSource(url: url).items()
            let big = try #require(items.first { $0.name == "Big" })
            #expect(big.rowCountHint == nil)
            #expect(items.first { $0.name == "NoRowid" }?.rowCountHint == nil)

            let reports = ProgressLog()
            let table = try await big.load(progress: { reports.append($0) })
            #expect(table.rowCount == 150_000)
            #expect(!reports.values.isEmpty)
            #expect(reports.values.contains { $0 > 0 && $0 < 1 })   // tiến độ giữa chừng (ngoài 0 và 1 lúc đầu, cuối)

            let small = try #require(items.first { $0.name == "Small" })
            // MAX(rowid) = 900 000 nhưng chỉ 3 dòng: không đếm lúc liệt kê (tránh quét bảng lớn mà không biết cỡ thật).
            #expect(small.rowCountHint == nil)
            #expect(try await small.load(progress: nil).rowCount == 3)
            #expect(try await items.first { $0.name == "NoRowid" }!.load(progress: nil).rowCount == 2)
        }
    }

    @Test func listingCountsSmallTablesExactly() async throws {
        try await withTempDB { url in
            var db: OpaquePointer?
            sqlite3_open(url.path, &db)
            defer { sqlite3_close(db) }
            sqlite3_exec(db, """
                CREATE TABLE T (id INTEGER PRIMARY KEY, v TEXT);
                INSERT INTO T VALUES (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd');
                DELETE FROM T WHERE id = 2;
                """, nil, nil, nil)
            let items = try await SQLiteSource(url: url).items()
            #expect(items.first?.rowCountHint == 3)
        }
    }

    @Test func specialCharactersInTableAndColumnNames() async throws {
        try await withTempDB { url in
            var db: OpaquePointer?
            sqlite3_open(url.path, &db)
            defer { sqlite3_close(db) }

            let createSQL = "CREATE TABLE \"Table \"\"Special\"\"\" (\"Col \"\"A\"\"\" INTEGER, \"B C\" TEXT);"
            sqlite3_exec(db, createSQL, nil, nil, nil)
            let insertSQL = "INSERT INTO \"Table \"\"Special\"\"\" VALUES (42, 'hello');"
            sqlite3_exec(db, insertSQL, nil, nil, nil)

            let source = SQLiteSource(url: url)
            let items = try await source.items()
            #expect(items.count == 1)
            #expect(items[0].name == "Table \"Special\"")

            let table = try await items[0].load(progress: nil)
            #expect(table.rowCount == 1)
            #expect(table.columns.map(\.name) == ["Col \"A\"", "B C"])
            #expect(table.value(row: 0, column: 0) == .integer(42))
            #expect(table.value(row: 0, column: 1) == .string("hello"))
        }
    }

    @Test func declaredTypeMappings() async throws {
        try await withTempDB { url in
            var db: OpaquePointer?
            sqlite3_open(url.path, &db)
            defer { sqlite3_close(db) }

            let createSQL = """
            CREATE TABLE TypesTest (
                c_int BIGINT,
                c_real REAL,
                c_num NUMERIC,
                c_dec DECIMAL(10,2),
                c_bool BOOLEAN,
                c_date DATE,
                c_time TIMESTAMP,
                c_text VARCHAR(100),
                c_none
            );
            """
            sqlite3_exec(db, createSQL, nil, nil, nil)
            let insertSQL = """
            INSERT INTO TypesTest VALUES (
                100, 2.5, 3.14, 99.99, 1, '2026-03-02', '2026-03-02 10:00:00', 'text', 'any'
            );
            """
            sqlite3_exec(db, insertSQL, nil, nil, nil)

            let source = SQLiteSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)

            #expect(table.columns[0].data.type == .integer)
            #expect(table.columns[1].data.type == .double)
            #expect(table.columns[2].data.type == .double)
            #expect(table.columns[3].data.type == .double)
            #expect(table.columns[4].data.type == .boolean)
            #expect(table.columns[5].data.type == .dateTime)
            #expect(table.columns[6].data.type == .dateTime)
            #expect(table.columns[7].data.type == .string)
            #expect(table.columns[8].data.type == .string)

            #expect(table.value(row: 0, column: 0) == .integer(100))
            #expect(table.value(row: 0, column: 4) == .boolean(true))
            #expect(table.value(row: 0, column: 5) == .dateTime(46083.0))
        }
    }

    @Test func blobColumnThrowsUnsupportedOnLoad() async throws {
        try await withTempDB { url in
            var db: OpaquePointer?
            sqlite3_open(url.path, &db)
            defer { sqlite3_close(db) }

            sqlite3_exec(db, "CREATE TABLE BlobTest (id INTEGER, data BLOB);", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO BlobTest VALUES (1, x'0102');", nil, nil, nil)

            let source = SQLiteSource(url: url)
            let items = try await source.items()
            #expect(items.count == 1)

            await #expect(throws: SourceError.self) {
                try await items[0].load(progress: nil)
            }
        }
    }

    @Test func nonExistentFileThrowsUnreadable() async throws {
        let badURL = URL(fileURLWithPath: "/tmp/non_existent_\(UUID().uuidString).sqlite")
        let source = SQLiteSource(url: badURL)
        await #expect(throws: SourceError.self) {
            try await source.items()
        }
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func append(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
}
