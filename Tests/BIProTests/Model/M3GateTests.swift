// Phase F, T100 (gate tổng M3, SC-001, SC-009): luồng đầy đủ trên tài liệu mới: Get Data ▸ Excel `sales_2026.xlsx` (Sales) ▸ Chuyển đổi dữ liệu
// ▸ lọc Region ∈ {North, South}, bỏ cột Price, sắp giảm dần Amount ▸ Close & Apply ▸ measure + hai card ▸ lưu lần đầu. Nguồn ghi đường dẫn Windows
// `C:\Users\bacpew\m3\sales_2026.xlsx` để Desktop Refresh được sau khi chép sang VM. Kèm `Nhom6_m3.pbix`: Nhom6 thêm một measure, lưu bằng bộ nén
// XPress9 độ sâu 4 (T106) để Desktop kiểm luồng nhiều khối. Số mong đợi tính độc lập bằng Python (đọc XML của trang Sales, 500 dòng):
// 191 dòng, Σ Amount 69 256,96, Σ Qty 1 909. Ghi ra `build/f-out/m3/`.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: gate tổng M3", .enabled(if: FFixtures.sample("sales_2026.xlsx") != nil), .serialized) @MainActor
struct M3GateTests {
    @Test func taoFileGateM3() async throws {
        let dir = try FFixtures.outputDirectory("m3")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("m3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        // Get Data ▸ Excel ▸ Navigator chọn Sales ▸ "Chuyển đổi dữ liệu".
        let sample = try #require(FFixtures.sample("sales_2026.xlsx"))
        state.showGetData(kind: .excel, pickFile: { _ in sample.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<400 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for entry in navigator.items where entry.name == "Sales" { navigator.toggle(entry.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames)?.first)
        state.closeGetData()
        let origin = try #require(loaded.origin)
        let table = LoadedTable(name: loaded.name, data: loaded.data,
                                origin: LoadedOrigin(kind: .excel, location: #"C:\Users\bacpew\m3\sales_2026.xlsx"#,
                                                     itemName: origin.itemName, itemKind: origin.itemKind))
        state.showQueryEditor(loaded: [table])
        let editor = try #require(state.queryEditorState)
        #expect(editor.perform(.filterEquals(column: "Region", values: [.text("North"), .text("South")])) == .applied)
        #expect(editor.perform(.removeColumns(["Price"])) == .applied)
        #expect(editor.perform(.sortRows([SortKey(column: "Amount", descending: true)])) == .applied)
        print("KEY M3 M:\n\(editor.selectedQuery?.source ?? "")")
        state.applyQueryEditor()
        for _ in 0..<400 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(editor.applyMessage == nil)

        // Report: measure + hai card.
        let view = CGRect(x: 0, y: 0, width: 1280, height: 720)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "Sales", name: "Tong Amount", expression: "SUM(Sales[Amount])"))) == nil)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "Sales", name: "So dong", expression: "COUNTROWS(Sales)"))) == nil)
        for name in ["Tong Amount", "So dong"] {
            let card = try #require(state.layout.insertVisual(type: "card", visibleRect: view))
            #expect(state.layout.addField(FieldRef(kind: .measure, entity: "Sales", property: name), to: "Values", visual: card) == nil)
        }

        let destination = dir.appendingPathComponent("bipro-m3.pbix")
        try? FileManager.default.removeItem(at: destination)
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)

        let reopened = try Workspace(data: Data(contentsOf: destination))
        let query = try #require(reopened.metadata?.partitionQueries["Sales"])
        print("KEY M3 saved M:\n\(query)")
        #expect(query.contains(#"Excel.Workbook(File.Contents("C:\Users\bacpew\m3\sales_2026.xlsx")"#))
        let result = try await reopened.daxEngine().run("""
            EVALUATE ROW("n", COUNTROWS(Sales), "s", SUM(Sales[Amount]), "q", SUM(Sales[Qty]), "r", DISTINCTCOUNT(Sales[Region]))
            """)
        let row = try #require(result.tables.first?.rows.first)
        #expect(row[0] == .integer(191))
        if case .double(let sum) = row[1] { #expect(abs(sum - 69_256.96) < 0.005) } else { Issue.record("Σ Amount: \(row[1])") }
        #expect(row[2] == .integer(1909))
        #expect(row[3] == .integer(2))
        #expect(reopened.metadata?.columns.contains { $0.tableName == "Sales" && $0.name == "Price" } == false)

        // Nhom6 thêm một measure (T2), bộ nén XPress9 độ sâu 4.
        if let nhom6 = try FFixtures.nhom6Copy(folder: "m3", fileName: "Nhom6_m3.pbix") {
            let s6 = DocumentState(workspace: try Workspace(data: Data(contentsOf: nhom6)), fileName: nhom6.lastPathComponent, fileURL: nhom6)
            let host = try #require(s6.workspace.userTables.first { $0.name == "Fact_Loan" }?.name ?? s6.workspace.userTables.first?.name)
            #expect(s6.modelEditor.apply(.addMeasure(NewMeasure(table: host, name: "M3 kiem nen", expression: "COUNTROWS('\(host)')"))) == nil)
            #expect(try DocumentSaver.save(editor: s6.layout, source: nhom6, to: nhom6, expectedStamp: nil, readOnlyRoots: [],
                                           backupDirectory: root.appendingPathComponent("Backups")).didWrite)
            let n = try await Workspace(data: Data(contentsOf: nhom6)).daxEngine().run("EVALUATE ROW(\"n\", COUNTROWS('\(host)'))")
            print("KEY M3 Nhom6 host \(host) rows: \(n.tables.first?.rows.first?[0] ?? .blank)")
        }
        print("KEY M3 file gate: \(dir.path)")
    }
}
