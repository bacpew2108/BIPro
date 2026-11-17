// Phase F, T094 (US8, SQLite): tài liệu mới → Get Data ▸ SQLite (`sales_2026.sqlite`) → Load cả ba mục → card measure → lưu lần đầu → mở lại.
// Số mong đợi tính độc lập bằng `sqlite3` trên tệp mẫu: Sales 1 000 dòng, Σ Amount 350 317,03; NorthSales 201; Customers 50;
// 142 dòng "Đồng hồ" (chữ tiếng Việt giữ đúng, khác Desktop + driver Devart). Để lại `build/f-out/f7db/bipro-f7sqlite.pbix` cho gate Desktop.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: SQLite trên tài liệu mới", .enabled(if: FFixtures.sample("sales_2026.sqlite") != nil), .serialized) @MainActor
struct F7SQLiteGateTests {
    @Test func napSQLiteLuuMoLai() async throws {
        let sample = try #require(FFixtures.sample("sales_2026.sqlite"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f7s-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        state.showGetData(kind: .sqlite, pickFile: { _ in sample.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<400 where navigator.phase == .listingItems || navigator.phase == .choosingSource { try await Task.sleep(for: .milliseconds(25)) }
        #expect(navigator.phase == .ready)
        for item in navigator.items { navigator.toggle(item.id) }
        let tables = try #require(await navigator.load(existingNames: state.existingTableNames))
        #expect(state.loadFromGetData(tables) == nil)
        state.closeGetData()
        #expect(state.workspace.userTables.map(\.name) == ["NorthSales", "Customers", "Sales"])

        let view = CGRect(x: 0, y: 0, width: 1280, height: 720)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "Sales", name: "Tổng Amount", expression: "SUM(Sales[Amount])"))) == nil)
        let card = try #require(state.layout.insertVisual(type: "card", visibleRect: view))
        #expect(state.layout.addField(FieldRef(kind: .measure, entity: "Sales", property: "Tổng Amount"), to: "Values", visual: card) == nil)

        let destination = try FFixtures.outputDirectory("f7db").appendingPathComponent("bipro-f7sqlite.pbix")
        try? FileManager.default.removeItem(at: destination)
        let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
        #expect(outcome.didWrite)

        let reopened = try Workspace(data: Data(contentsOf: destination))
        let model = try #require(reopened.metadata)
        #expect(model.partitionQueries["Sales"]?.contains("Odbc.DataSource(\"Driver={Devart ODBC Driver for SQLite};Database=\(sample.path)\"") == true)
        let engine = try reopened.daxEngine()
        let result = try await engine.run("""
            EVALUATE ROW("n", COUNTROWS(Sales), "s", SUM(Sales[Amount]), "v", COUNTROWS(NorthSales), "c", COUNTROWS(Customers),
                "d", COUNTROWS(FILTER(Sales, Sales[Product] = "Đồng hồ")))
            """)
        let row = try #require(result.tables.first?.rows.first)
        #expect(row[0] == .integer(1000))
        if case .double(let sum) = row[1] { #expect(abs(sum - 350_317.03) < 0.005) } else { Issue.record("tổng không phải số: \(row[1])") }
        #expect(row[2] == .integer(201))
        #expect(row[3] == .integer(50))
        #expect(row[4] == .integer(142))
    }
}
