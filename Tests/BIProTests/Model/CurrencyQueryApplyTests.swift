// T103 (FR-050): Query Editor đổi cột sang Fixed decimal (`Currency.Type`) → Close & Apply → lưu → mở lại. Trước đây lưu bị từ chối
// ("kiểu tiền tệ chưa lưu được"). Số mong đợi tính độc lập bằng Python trên `sales_100.csv`: 100 dòng, Σ Price 3 498,04, Σ Amount 37 860,12.
// Để lại `build/f-out/f9/bipro-currency.pbix` cho gate Desktop.
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@Suite(.enabled(if: FFixtures.sample("sales_100.csv") != nil), .serialized) @MainActor
struct CurrencyQueryApplyTests {
    @Test func doiSangFixedDecimalRoiLuu() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cq-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        let csv = try #require(FFixtures.sample("sales_100.csv"))
        state.showGetData(kind: .csv, pickFile: { _ in csv.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        state.closeGetData()

        state.showQueryEditor(loaded: loaded)
        let editor = try #require(state.queryEditorState)
        #expect(editor.perform(.changeType([ColumnTypeChange(column: "Price", type: .fixedDecimal),
                                            ColumnTypeChange(column: "Amount", type: .fixedDecimal)])) == .applied)
        state.applyQueryEditor()
        for _ in 0..<400 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(editor.applyMessage == nil)

        let view = CGRect(x: 0, y: 0, width: 1280, height: 720)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "sales_100", name: "Tổng Amount", expression: "SUM(sales_100[Amount])"))) == nil)
        let card = try #require(state.layout.insertVisual(type: "card", visibleRect: view))
        #expect(state.layout.addField(FieldRef(kind: .measure, entity: "sales_100", property: "Tổng Amount"), to: "Values", visual: card) == nil)

        let destination = try FFixtures.outputDirectory("f9").appendingPathComponent("bipro-currency.pbix")
        try? FileManager.default.removeItem(at: destination)
        let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
        #expect(outcome.didWrite)

        let reopened = try Workspace(data: Data(contentsOf: destination))
        let model = try #require(reopened.metadata)
        #expect(model.columns.first { $0.tableName == "sales_100" && $0.name == "Price" }?.dataType == .decimal)
        #expect(model.partitionQueries["sales_100"]?.contains("{\"Price\", Currency.Type}") == true)
        let result = try await reopened.daxEngine().run("EVALUATE ROW(\"p\", SUM(sales_100[Price]), \"a\", SUM(sales_100[Amount]), \"n\", COUNTROWS(sales_100))")
        let row = try #require(result.tables.first?.rows.first)
        #expect(row[0] == .currency(34_980_400))
        #expect(row[1] == .currency(378_601_200))
        #expect(row[2] == .integer(100))
    }
}
