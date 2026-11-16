// Phase F, T081 (US6): cột tính toán và bảng tính toán. Golden là dữ liệu Desktop đã tính và lưu sẵn trong file (Desktop ghi
// VertiPaq cho cột/bảng tính toán, quan sát ở `docs/phase-f-evidence/vm-f6/QUAN-SAT.md`): engine tính lại biểu thức từng dòng
// rồi so với giá trị đã lưu, không hard-code số nào.
// - Nhom6: 7 cột (IF/BLANK, HOUR, nối chuỗi, DATE, VAR + RELATED + DATEDIFF, SWITCH(TRUE()) phụ thuộc cột tính toán khác).
// - `w8.3.pbix` (bài tập của người dùng): bảng `Ngày` = CALENDAR(...) và ba cột DAY/MONTH/YEAR.
// Chạy khi BIPRO_HEAVY=1 và có file.
import ColumnStore
import DAXTestSupport
import Foundation
import PBIXKit
import Testing
@testable import DAXEngine

private let heavy = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"
private let w83 = DAXFixtures.downloads.appendingPathComponent("DWH&BI/w8.3.pbix")

private func load(_ url: URL) throws -> (DAXEngine, ModelMetadata) {
    let (abf, _) = try PBIXFile(url: url).loadDataModel()
    let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    let store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: metadata))
    return (DAXEngine(store: store, catalog: Catalog(metadata: metadata)), metadata)
}

/// Giá trị đã lưu của cột `table[column]`, theo thứ tự dòng.
private func stored(_ engine: DAXEngine, _ table: String, _ column: String) throws -> [Value] {
    let schemaColumn = try #require(engine.store.schema.column(table: table, name: column))
    let data = try engine.store.column(schemaColumn.id)
    let count = try engine.store.rowCount(schemaColumn.id.table)
    return (0..<count).map { Value(stored: data.value(at: $0)) }
}

private func same(_ a: Value, _ b: Value) -> Bool {
    switch (a, b) {
    case (.double(let x), .double(let y)), (.dateTime(let x), .dateTime(let y)): return abs(x - y) < 1e-9
    case (.integer(let x), .double(let y)), (.double(let y), .integer(let x)): return abs(Double(x) - y) < 1e-9
    default: return a == b
    }
}

@Suite("Phase F: cột và bảng tính toán", .enabled(if: heavy && FileManager.default.fileExists(atPath: DAXFixtures.nhom6.path)), .serialized)
struct CalculatedColumnTests {
    @Test func bayCotTinhToanNhom6KhopGiaTriDesktopDaLuu() throws {
        let (engine, metadata) = try load(DAXFixtures.nhom6)
        let userTables = Set(metadata.userTables.map(\.id))
        let columns = metadata.columns.filter { $0.kind == .calculated && userTables.contains($0.tableID) }
        #expect(columns.count == 7)
        for column in columns {
            let expression = try #require(column.expression)
            let computed = try engine.calculatedColumn(table: column.tableName, expression: expression)
            let expected = try stored(engine, column.tableName, column.name)
            #expect(computed.count == expected.count, Comment(rawValue: "\(column.tableName)[\(column.name)]"))
            let mismatches = Array(zip(computed, expected).enumerated()).filter { item in !same(item.element.0, item.element.1) }
            #expect(mismatches.isEmpty, Comment(rawValue: "\(column.tableName)[\(column.name)]: \(mismatches.count) dòng lệch, đầu tiên \(mismatches.prefix(3).map { "dòng \($0.offset): \($0.element.0) ≠ \($0.element.1)" })"))
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: w83.path))) func bangCalendarVaCotNgayThangNamKhopDesktop() throws {
        let (engine, metadata) = try load(w83)
        let partition = try #require(metadata.calculatedTableExpressions["Ngày"])
        let table = try engine.calculatedTable(expression: partition)
        #expect(table.columns == ["Date"])
        let expectedDates = try stored(engine, "Ngày", "Date")
        #expect(table.rows.count == expectedDates.count)
        // Desktop lưu dòng theo thứ tự CALENDAR (ngày tăng dần).
        #expect(zip(table.rows.map { $0[0] }, expectedDates).allSatisfy { same($0, $1) })
        for name in ["Ngày", "Tháng", "Năm"] {
            let column = try #require(metadata.columns.first { $0.tableName == "Ngày" && $0.name == name && $0.kind == .calculated })
            let computed = try engine.calculatedColumn(table: "Ngày", expression: try #require(column.expression))
            let expected = try stored(engine, "Ngày", name)
            #expect(computed.count == expected.count)
            #expect(zip(computed, expected).allSatisfy { same($0, $1) }, Comment(rawValue: name))
        }
    }
}
