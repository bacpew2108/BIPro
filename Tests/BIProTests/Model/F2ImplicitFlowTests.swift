// Đợt tồn đọng sau Phase F, US1 (T015): tài liệu mới → Get Data `build/f2-out/samples/sales_2026.xlsx` → card Sum Amount (gộp ngầm),
// biểu đồ cột Average Qty và Variance Price theo Region (đổi phép gộp qua menu), card mới First Region → lưu → mở lại → truy vấn từng
// visual. Số mong đợi tính độc lập bằng Python đọc XML của tệp xlsx (500 dòng): Σ Amount 186 731,23; Average Qty East 9,72,
// North 10,22, South 10,1234567901…, Trung tâm 9,6126126126…, West 9,9444444444…; VAR.P Price East 1 656,41287971; First Region "East".
// Để lại `build/f2-out/f10/bipro-f10.pbix` cho gate Desktop (T016).
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Đợt F2: gộp ngầm trên tài liệu mới", .enabled(if: F2Fixtures.sample("sales_2026.xlsx") != nil), .serialized) @MainActor
struct F2ImplicitFlowTests {
    private let averageQty: [String: Double] = ["East": 9.72, "North": 10.22, "South": 10.123456790123457,
                                                "Trung tâm": 9.612612612612613, "West": 9.944444444444445]

    private func number(_ value: Value?) -> Double? {
        switch value {
        case .integer(let i)?: Double(i)
        case .double(let d)?: d
        default: nil
        }
    }

    @Test func gopNgamLuuMoLaiRaDungSo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        let xlsx = try #require(F2Fixtures.sample("sales_2026.xlsx"))
        state.showGetData(kind: .excel, pickFile: { _ in xlsx.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items where item.name == "Sales" { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        state.closeGetData()
        state.showQueryEditor(loaded: loaded)
        state.applyQueryEditor()
        for _ in 0..<400 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(state.workspace.rowCount("Sales") == 500)
        #expect(state.layout.allowsImplicitMeasures)

        let metadata = try #require(state.workspace.metadata)
        func column(_ name: String) throws -> FieldRef {
            FieldRef(column: try #require(metadata.columns.first { $0.tableName == "Sales" && $0.name == name }))
        }
        let view = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let card = try #require(state.layout.insertVisual(type: "card", visibleRect: view))
        #expect(state.layout.addField(try column("Amount"), to: "Values", visual: card) == nil)
        let chart = try #require(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: view))
        // Tích như ở Data pane: Region vào trục, Qty vào Y (SummarizeBy Sum).
        #expect(WellRules.defaultRole(for: try column("Region"), in: try #require(state.layout.visual(chart)), implicitMeasures: true) == "Category")
        #expect(state.layout.addField(try column("Region"), to: "Category", visual: chart) == nil)
        #expect(WellRules.defaultRole(for: try column("Qty"), in: try #require(state.layout.visual(chart)), implicitMeasures: true) == "Y")
        #expect(state.layout.addField(try column("Qty"), to: "Y", visual: chart) == nil)
        #expect(state.layout.addField(try column("Qty"), to: "Y", visual: chart)?.contains("đã được gộp") == true)
        #expect(state.layout.addField(try column("Price"), to: "Y", visual: chart) == nil)
        #expect(state.layout.setAggregation(role: "Y", index: 0, to: .average, visual: chart) == nil)
        #expect(state.layout.setAggregation(role: "Y", index: 1, to: .variance, visual: chart) == nil)
        let first = try #require(state.layout.insertVisual(type: "cardVisual", visibleRect: view))
        #expect(state.layout.addField(try column("Region"), to: "Data", visual: first) == nil)
        // T017: Build pane và pane Bộ lọc cùng nhãn theo kiểu cột (cột chữ: "Đầu tiên", không phải "Nhỏ nhất").
        let regionField = try #require(state.layout.visual(first)?.fields.first)
        #expect(state.layout.label(of: regionField) == "Đầu tiên của Region")
        let qtyField = try #require(state.layout.visual(chart)?.fields.first { $0.property == "Qty" })
        #expect(state.layout.label(of: qtyField) == "Trung bình của Qty")

        let destination = try F2Fixtures.outputDirectory("f10").appendingPathComponent("bipro-f10.pbix")
        try? FileManager.default.removeItem(at: destination)
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)

        let reopened = try Workspace(data: Data(contentsOf: destination))
        let page = try #require(reopened.visiblePages.first)
        let reader = VisualQuerySpecReader(metadata: try #require(reopened.metadata))
        let loader = VisualDataLoader(engine: try reopened.daxEngine(), maxConcurrent: 2)

        let savedCard = try #require(page.visuals.first { $0.id == card })
        guard case .single(let total) = try await loader.load(try reader.spec(for: savedCard, filters: [])).view else {
            Issue.record("card không ra một giá trị"); return
        }
        #expect(abs((number(total.cell.value) ?? .nan) - 186_731.23) < 0.005)

        let savedChart = try #require(page.visuals.first { $0.id == chart })
        let chartSpec = try reader.spec(for: savedChart, filters: [])
        #expect(chartSpec.measures.map(\.aggregation) == [.average, .variance])
        #expect(chartSpec.measures.map(\.field.displayName) == ["Trung bình của Qty", "Phương sai của Price"])
        guard case .categorical(let data) = try await loader.load(chartSpec).view else {
            Issue.record("biểu đồ cột không ra dữ liệu danh mục"); return
        }
        var averages: [String: Double] = [:], variances: [String: Double] = [:]
        for (c, key) in data.categories.enumerated() {
            guard case .string(let name)? = key.values.first else { continue }
            averages[name] = number(data.cell(measure: 0, series: 0, category: c).value)
            variances[name] = number(data.cell(measure: 1, series: 0, category: c).value)
        }
        for (name, value) in averageQty { #expect(abs((averages[name] ?? .nan) - value) < 1e-9, Comment(rawValue: name)) }
        #expect(abs((variances["East"] ?? .nan) - 1656.41287971) < 1e-6)

        let savedFirst = try #require(page.visuals.first { $0.id == first })
        guard case .single(let region) = try await loader.load(try reader.spec(for: savedFirst, filters: [])).view else {
            Issue.record("card mới không ra một giá trị"); return
        }
        #expect(region.cell.value == .string("East"))
    }
}
