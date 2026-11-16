// Phase F, T078 (US5): luồng đầy đủ trên tài liệu mới: File → Mới → Get Data (`sales_2026.xlsx`, trang Sales) → Query Editor →
// Close & Apply → card (tổng Amount) và biểu đồ cột (Amount theo Region) → lưu lần đầu → mở lại, chạy truy vấn của từng visual.
// Số mong đợi tính độc lập bằng Python đọc XML của tệp xlsx (500 dòng, Σ Amount 182 260,61; East 34 467,09, North 36 450,
// South 32 806,96, Trung tâm 36 547,92, West 41 988,64). Để lại `build/f-out/f5/bipro-moi.pbix` cho gate Desktop (T079).
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: tài liệu mới đầy đủ", .enabled(if: FFixtures.sample("sales_2026.xlsx") != nil), .serialized) @MainActor
struct F5NewDocTests {
    private let expectedTotal = 182_260.61
    private let expectedByRegion: [String: Double] = ["East": 34_467.09, "North": 36_450, "South": 32_806.96,
                                                      "Trung tâm": 36_547.92, "West": 41_988.64]

    private func number(_ value: Value?) -> Double? {
        switch value {
        case .integer(let i)?: Double(i)
        case .double(let d)?: d
        default: nil
        }
    }

    /// Tài liệu trống lưu lần đầu khi chưa sửa gì: `build/f-out/f5/bipro-trong.pbix` cho gate Desktop (T079).
    @Test func taiLieuTrongLuuRaFileChoGate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f5-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        let destination = try FFixtures.outputDirectory("f5").appendingPathComponent("bipro-trong.pbix")
        try? FileManager.default.removeItem(at: destination)
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)
        let reopened = try Workspace(data: Data(contentsOf: destination))
        #expect(reopened.userTables.isEmpty && reopened.visiblePages.count == 1)
    }

    @Test func moiNapCardVaCotLuuMoLai() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f5-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        // Get Data → Navigator (Sales) → "Chuyển đổi dữ liệu" → Close & Apply.
        let xlsx = try #require(FFixtures.sample("sales_2026.xlsx"))
        state.showGetData(kind: .excel, pickFile: { _ in xlsx.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items where item.name == "Sales" { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        state.closeGetData()
        state.showQueryEditor(loaded: loaded)
        #expect(state.queryEditorState != nil)
        state.applyQueryEditor()
        for _ in 0..<400 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(state.queryEditorState == nil)
        #expect(state.workspace.userTables.map(\.name) == ["Sales"])
        #expect(state.workspace.rowCount("Sales") == 500)

        // Card và biểu đồ cột trên trang đầu.
        let metadata = try #require(state.workspace.metadata)
        let amount = try #require(metadata.columns.first { $0.tableName == "Sales" && $0.name == "Amount" })
        let region = try #require(metadata.columns.first { $0.tableName == "Sales" && $0.name == "Region" })
        // Cột số vào ô giá trị cần measure (BI Pro chưa có phép gộp ngầm): tạo measure SUM như người dùng làm.
        let view = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let card = try #require(state.layout.insertVisual(type: "card", visibleRect: view))
        #expect(state.layout.addField(FieldRef(column: amount), to: "Values", visual: card) != nil)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "Sales", name: "Tổng Amount", expression: "SUM(Sales[Amount])"))) == nil)
        let total = FieldRef(kind: .measure, entity: "Sales", property: "Tổng Amount")
        #expect(state.layout.addField(total, to: "Values", visual: card) == nil)
        let chart = try #require(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: view))
        #expect(state.layout.addField(FieldRef(column: region), to: "Category", visual: chart) == nil)
        #expect(state.layout.addField(total, to: "Y", visual: chart) == nil)

        // Lưu lần đầu ra file thật, bản tạm giữ nguyên.
        let destination = try FFixtures.outputDirectory("f5").appendingPathComponent("bipro-moi.pbix")
        try? FileManager.default.removeItem(at: destination)
        let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
        #expect(outcome.didWrite && !state.layout.isDirty)
        #expect(try Workspace(data: Data(contentsOf: untitled)).userTables.isEmpty)

        // Mở lại: một bảng, hai visual, truy vấn của từng visual ra đúng số.
        let reopened = try Workspace(data: Data(contentsOf: destination))
        #expect(reopened.userTables.map(\.name) == ["Sales"])
        #expect(reopened.rowCount("Sales") == 500)
        #expect(reopened.metadata?.partitionQueries["Sales"]?.contains("Excel.Workbook") == true)
        let page = try #require(reopened.visiblePages.first)
        #expect(reopened.visiblePages.count == 1)
        let reader = VisualQuerySpecReader(metadata: try #require(reopened.metadata))
        let loader = VisualDataLoader(engine: try reopened.daxEngine(), maxConcurrent: 2)

        let savedCard = try #require(page.visuals.first { $0.id == card })
        #expect(savedCard.type == "card")
        guard case .single(let single) = try await loader.load(try reader.spec(for: savedCard, filters: [])).view else {
            Issue.record("card không ra một giá trị"); return
        }
        #expect(abs((number(single.cell.value) ?? .nan) - expectedTotal) < 0.005)

        let savedChart = try #require(page.visuals.first { $0.id == chart })
        #expect(savedChart.type == "clusteredColumnChart")
        guard case .categorical(let data) = try await loader.load(try reader.spec(for: savedChart, filters: [])).view else {
            Issue.record("biểu đồ cột không ra dữ liệu danh mục"); return
        }
        var byRegion: [String: Double] = [:]
        for (c, key) in data.categories.enumerated() {
            guard case .string(let name)? = key.values.first else { continue }
            byRegion[name] = number(data.cell(measure: 0, series: 0, category: c).value)
        }
        #expect(byRegion.keys.sorted() == expectedByRegion.keys.sorted())
        for (name, value) in expectedByRegion { #expect(abs((byRegion[name] ?? .nan) - value) < 0.005, Comment(rawValue: name)) }
    }
}
