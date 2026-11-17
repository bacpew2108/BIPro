// Phase F, T090 (US7): luồng trên tài liệu mới: Get Data ▸ JSON (`orders.json`, mở thẳng Query Editor, Close & Apply) và Get Data ▸ Parquet
// (`sales_2026.parquet`, `parquet/types_snappy.parquet`, Load) → hai card measure → lưu lần đầu → mở lại. Số mong đợi tính độc lập bằng
// Python (`json`, pyarrow) trên tệp mẫu: orders 203 dòng, Σ Lines.Qty 521; sales_2026 10 000 dòng, Σ Amount 3 654 202,84;
// types_snappy 1 000 dòng, Σ Money 252 471,72, 314 cờ TRUE. Để lại `build/f-out/f7/bipro-f7.pbix` cho gate Desktop.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: JSON và Parquet trên tài liệu mới", .enabled(if: FFixtures.sample("orders.json") != nil && FFixtures.sample("sales_2026.parquet") != nil),
       .serialized) @MainActor
struct F7JsonParquetGateTests {
    private func waitGetData(_ state: DocumentState) async throws -> NavigatorState {
        let navigator = try #require(state.getDataState)
        for _ in 0..<400 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        #expect(navigator.phase == .ready)
        return navigator
    }

    private func scalar(_ engine: DAXEngine, _ dax: String) async throws -> Double? {
        let result = try await engine.run("EVALUATE ROW(\"v\", \(dax))")
        switch result.tables.first?.rows.first?.first {
        case .integer(let i)?: return Double(i)
        case .double(let d)?: return d
        case .currency(let c)?: return Double(c) / 10_000
        default: return nil
        }
    }

    @Test func napJsonVaParquetLuuMoLai() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f7-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        // JSON: không qua Navigator, mở thẳng Query Editor với các bước như Desktop, rồi Close & Apply.
        let json = try #require(FFixtures.sample("orders.json"))
        state.showGetData(kind: .json, pickFile: { _ in json.path })
        let jsonNavigator = try await waitGetData(state)
        #expect(jsonNavigator.opensEditorDirectly)
        let jsonTables = try #require(await jsonNavigator.loadDirectly(existingNames: state.existingTableNames))
        state.closeGetData()
        state.showQueryEditor(loaded: jsonTables)
        #expect(state.queryEditorState?.selectedQuery?.steps.count == 7)
        state.applyQueryEditor()
        for _ in 0..<400 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(state.queryEditorState == nil)

        // Parquet: Navigator một mục mỗi tệp, Load.
        for sample in ["sales_2026.parquet", "parquet/types_snappy.parquet"] {
            let url = try #require(FFixtures.sample(sample))
            state.showGetData(kind: .parquet, pickFile: { _ in url.path })
            let navigator = try await waitGetData(state)
            for item in navigator.items { navigator.toggle(item.id) }
            let tables = try #require(await navigator.load(existingNames: state.existingTableNames))
            #expect(state.loadFromGetData(tables) == nil)
            state.closeGetData()
        }
        #expect(state.workspace.userTables.map(\.name) == ["orders", "sales_2026", "types_snappy"])

        // Hai card để soát số trong Desktop.
        let view = CGRect(x: 0, y: 0, width: 1280, height: 720)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "orders", name: "Tổng Qty", expression: "SUM(orders[Lines.Qty])"))) == nil)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "sales_2026", name: "Tổng Amount", expression: "SUM(sales_2026[Amount])"))) == nil)
        for (table, measure) in [("orders", "Tổng Qty"), ("sales_2026", "Tổng Amount")] {
            let card = try #require(state.layout.insertVisual(type: "card", visibleRect: view))
            #expect(state.layout.addField(FieldRef(kind: .measure, entity: table, property: measure), to: "Values", visual: card) == nil)
        }

        let destination = try FFixtures.outputDirectory("f7").appendingPathComponent("bipro-f7.pbix")
        try? FileManager.default.removeItem(at: destination)
        let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
        #expect(outcome.didWrite)

        let reopened = try Workspace(data: Data(contentsOf: destination))
        let model = try #require(reopened.metadata)
        #expect(reopened.rowCount("orders") == 203 && reopened.rowCount("sales_2026") == 10_000 && reopened.rowCount("types_snappy") == 1_000)
        #expect(model.partitionQueries["orders"]?.contains("Table.ExpandListColumn") == true)
        #expect(model.partitionQueries["sales_2026"]?.contains("Parquet.Document(File.Contents(") == true)
        func type(_ table: String, _ column: String) -> ModelMetadata.DataType? {
            model.columns.first { $0.tableName == table && $0.name == column }?.dataType
        }
        // Kiểu như Desktop (QUAN-SAT VM-F7a): decimal → số thực, date → ngày giờ, bool → logic.
        #expect(type("orders", "Lines.Qty") == .int64 && type("orders", "Note") == .string)
        #expect(type("types_snappy", "Money") == .double && type("types_snappy", "Day") == .dateTime && type("types_snappy", "Flag") == .boolean)
        let engine = try reopened.daxEngine()
        #expect(try await scalar(engine, "SUM(orders[Lines.Qty])") == 521)
        #expect(abs((try await scalar(engine, "SUM(sales_2026[Amount])") ?? .nan) - 3_654_202.84) < 0.005)
        #expect(abs((try await scalar(engine, "SUM(types_snappy[Money])") ?? .nan) - 252_471.72) < 0.005)
        #expect(try await scalar(engine, "COUNTROWS(FILTER(types_snappy, types_snappy[Flag]))") == 314)
    }
}
