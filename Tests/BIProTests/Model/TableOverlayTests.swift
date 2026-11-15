// Phase F, T020: engine DAX chạy trên bảng nạp mới (nguồn cột chồng). Seam: `ModelRuntime.setEdits` + `Workspace.daxEngine()`.
// Chạy trên Nhom6 thật (BIPRO_HEAVY=1, vì mở Workspace giải nén cả mô hình). Giá trị mong đợi là hằng tính tay từ dữ liệu dựng ở test.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: bảng chồng lên mô hình", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
struct TableOverlayTests {
    private func workspace() throws -> Workspace {
        try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6)))
    }

    private func number(_ result: QueryResult) -> Double? {
        switch result.tables.first?.rows.first?.first {
        case .integer(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }

    private func table(_ name: String, keys: [Int64?], qty: [Int64?], amount: [Double?]) throws -> NewTable {
        let data = try TableData(columns: [TableColumn(name: "Key", data: ColumnBuilder.integers(keys)),
                                           TableColumn(name: "Qty", data: ColumnBuilder.integers(qty)),
                                           TableColumn(name: "Amount", data: ColumnBuilder.doubles(amount))])
        return TableLoader.newTable(from: LoadedTable(name: name, data: data))
    }

    private func evaluate(_ workspace: Workspace, _ dax: String) async throws -> Double? {
        number(try await workspace.daxEngine().execute(dax))
    }

    @Test func sumVaCountRowsTrenBangMoi() async throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let sales = try table("Sales2026", keys: [1, 2, 3], qty: [5, nil, 7], amount: [1.5, 2.5, 3.5])
        try runtime.setEdits(ModelEdits([.addTable(sales)]))
        #expect(workspace.metadata?.userTables.contains { $0.name == "Sales2026" } == true)
        #expect(try await evaluate(workspace, "EVALUATE ROW(\"x\", SUM(Sales2026[Qty]))") == 12)
        #expect(try await evaluate(workspace, "EVALUATE ROW(\"x\", SUM(Sales2026[Amount]))") == 7.5)
        #expect(try await evaluate(workspace, "EVALUATE ROW(\"x\", COUNTROWS(Sales2026))") == 3)
    }

    @Test func bangGocKhongDoiKhiThemBangMoi() async throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let before = try await evaluate(workspace, "EVALUATE ROW(\"x\", COUNTROWS(Dim_Account))")
        try runtime.setEdits(ModelEdits([.addTable(try table("Sales2026", keys: [1], qty: [1], amount: [1]))]))
        #expect(try await evaluate(workspace, "EVALUATE ROW(\"x\", COUNTROWS(Dim_Account))") == before)
    }

    @Test func quanHeTuBangMoiLocTheoBangChieu() async throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let metadata = try #require(workspace.metadata)
        let target = try #require(metadata.relationships.compactMap { r in
            metadata.columns.first { $0.tableName == r.toTable && $0.name == r.toColumn && $0.dataType == .int64 }
        }.first)
        let dimension = target.tableName, key = target.name
        let first = try #require(try await evaluate(workspace, "EVALUATE ROW(\"x\", MINX(\(dimension), \(dimension)[\(key)]))"))
        let k = Int64(first)
        let fact = try table("Sales2026", keys: [k, k, nil, k], qty: [1, 2, 3, 4], amount: [1, 1, 1, 1])
        let relationship = NewRelationship(fromTable: "Sales2026", fromColumn: "Key", toTable: dimension, toColumn: key)
        try runtime.setEdits(ModelEdits([.addTable(fact), .addRelationship(relationship)]))
        // Ba dòng có khoá k (hai dòng khác khoá k hoặc BLANK không thuộc k).
        let dax = "EVALUATE ROW(\"x\", CALCULATE(SUM(Sales2026[Qty]), \(dimension)[\(key)] = \(k)))"
        #expect(try await evaluate(workspace, dax) == 7)   // 1 + 2 + 4
    }

    @Test func tableViewDocDuocBangMoiVaThayDoiTheoHoanTac() async throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let sales = try table("Sales2026", keys: [1, 2, 3], qty: [5, nil, 7], amount: [1.5, 2.5, 3.5])
        #expect(workspace.rowCount("Sales2026") == 0)
        try runtime.setEdits(ModelEdits([.addTable(sales)]))
        #expect(workspace.rowCount("Sales2026") == 3)
        let columns = try workspace.table("Sales2026")
        #expect(columns.map(\.name) == ["Key", "Qty", "Amount"])
        #expect((0..<3).map { columns[1][$0] } == [.int(5), .null, .int(7)])
        #expect((0..<3).map { columns[2][$0] } == [.double(1.5), .double(2.5), .double(3.5)])
        // Thay dữ liệu: Table View thấy ngay bản mới (không dính cache cũ).
        let bigger = try table("Sales2026", keys: [1, 2, 3, 4], qty: [1, 1, 1, 1], amount: [0, 0, 0, 0])
        try runtime.setEdits(ModelEdits([.addTable(sales), .replaceTable(name: "Sales2026", bigger)]))
        #expect(workspace.rowCount("Sales2026") == 4)
        #expect(try workspace.table("Sales2026")[1].count == 4)
        // Hoàn tác về gốc: bảng biến mất khỏi Table View.
        try runtime.setEdits(ModelEdits())
        #expect(workspace.rowCount("Sales2026") == 0)
        #expect(try workspace.table("Sales2026").isEmpty)
    }

    @Test func thayDuLieuBangMoiVaXoaBang() async throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let first = try table("Sales2026", keys: [1, 2], qty: [10, 20], amount: [1, 2])
        let second = try table("Sales2026", keys: [1, 2, 3, 4], qty: [1, 1, 1, 1], amount: [1, 1, 1, 1])
        try runtime.setEdits(ModelEdits([.addTable(first)]))
        #expect(try await evaluate(workspace, "EVALUATE ROW(\"x\", SUM(Sales2026[Qty]))") == 30)
        try runtime.setEdits(ModelEdits([.addTable(first), .replaceTable(name: "Sales2026", second)]))
        #expect(try await evaluate(workspace, "EVALUATE ROW(\"x\", SUM(Sales2026[Qty]))") == 4)
        try runtime.setEdits(ModelEdits([.addTable(first), .replaceTable(name: "Sales2026", second), .dropTable(name: "Sales2026")]))
        await #expect(throws: (any Error).self) { try await workspace.daxEngine().execute("EVALUATE ROW(\"x\", COUNTROWS(Sales2026))") }
        // Quay về mô hình gốc.
        try runtime.setEdits(ModelEdits())
        #expect(workspace.metadata?.userTables.contains { $0.name == "Sales2026" } == false)
    }
}

// MARK: - Chuyển LoadedTable thành NewTable (không cần Nhom6)

@Suite("Phase F: LoadedTable → NewTable") struct NewTableConversionTests {
    @Test func kieuCotVaDuLieuDuocGiu() throws {
        let data = try TableData(columns: [
            TableColumn(name: "I", data: ColumnBuilder.integers([1])),
            TableColumn(name: "D", data: ColumnBuilder.doubles([1.5])),
            TableColumn(name: "C", data: ColumnBuilder.currency([10_000])),
            TableColumn(name: "T", data: ColumnBuilder.dateTimes([45000])),
            TableColumn(name: "B", data: ColumnBuilder.booleans([true])),
            TableColumn(name: "S", data: ColumnBuilder.strings(["a"])),
        ])
        let loaded = LoadedTable(name: "Bang", queryName: "Truy vấn", data: data)
        let table = TableLoader.newTable(from: loaded, queryExpression: "let Source = 1 in Source")
        #expect(table.name == "Bang")
        #expect(table.columns.map(\.name) == ["I", "D", "C", "T", "B", "S"])
        #expect(table.columns.map(\.dataType) == [.int64, .double, .decimal, .dateTime, .boolean, .string])
        #expect(table.queryExpression == "let Source = 1 in Source")
        #expect((table.attachment as? TableData)?.rowCount == 1)
    }
}
