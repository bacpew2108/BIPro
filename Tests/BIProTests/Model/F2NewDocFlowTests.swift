// T036: tài liệu mới đi hết các bước của buổi VM-F11 (Enter Data `Table`, nạp Sales + Customers + products cùng lúc, biểu đồ cột Sum of
// Amount theo phân cấp ngày của OrderDate, nạp thêm Enter Data `Table (2)`), lưu, mở lại; cấu trúc phải như `f11-desktop.pbix`
// (bảng, bảng ngày cục bộ, variation, quan hệ, chú thích), số liệu đúng. Để lại `build/f2-out/f11/bipro-f11.pbix` cho gate T037.
// M Enter Data lấy nguyên văn từ file Desktop. Thiếu file Desktop hay mẫu thì bỏ qua.
import Connectors
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil && F2Fixtures.sample("sales_2026.xlsx") != nil
                && F2Fixtures.sample("customers.xlsx") != nil && F2Fixtures.sample("products.csv") != nil))
struct F2NewDocFlowTests {
    private func navigate(_ state: DocumentState, _ kind: SourceKind, _ file: String, pick: String) async throws -> [LoadedTable] {
        let url = try #require(F2Fixtures.sample(file))
        state.showGetData(kind: kind, pickFile: { _ in url.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<400 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        #expect(navigator.items.contains { $0.name == pick }, "\(file): \(navigator.items.map(\.name))")
        for item in navigator.items where item.name == pick { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        state.closeGetData()
        return loaded
    }

    private func number(_ result: QueryResult) -> Double? {
        switch result.tables.first?.rows.first?.first {
        case .integer(let i)?: Double(i)
        case .double(let d)?: d
        case .currency(let c)?: Double(c) / 10_000
        default: nil
        }
    }

    @Test func taiLieuMoiNhuBuoiVMF11() async throws {
        let desktopURL = try #require(F2Fixtures.desktop("vm-f11", "f11-desktop.pbix"))
        let desktop = try #require(try Workspace(data: Data(contentsOf: desktopURL)).metadata)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f2newdoc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        // 1. Enter Data `Table` (3 cột × 5 dòng).
        let tableM = try #require(desktop.partitionQueries["Table"])
        #expect(await state.loadEnterData(try #require(EnterDataTable(name: "Table", m: tableM))) == nil)
        // 2. Sales, Customers, products cùng một lần nạp.
        var batch = try await navigate(state, .excel, "sales_2026.xlsx", pick: "Sales")
        batch += try await navigate(state, .excel, "customers.xlsx", pick: "Customers")
        batch += try await navigate(state, .csv, "products.csv", pick: "products")
        #expect(state.loadFromGetData(batch) == nil)
        // 3. Biểu đồ cột Sum of Amount theo OrderDate (phân cấp ngày).
        let chart = try #require(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: nil))
        state.visualID = chart
        #expect(state.layout.addField(try #require(state.workspace.dateHierarchy(table: "Sales", column: "OrderDate")), to: "Category", visual: chart) == nil)
        let amount = try #require(state.workspace.columns(of: "Sales").first { $0.name == "Amount" })
        #expect(state.layout.addField(FieldRef(column: amount), to: "Y", visual: chart) == nil)
        // 4. Enter Data `Table (2)` (Manager, Region).
        let table2M = try #require(desktop.partitionQueries["Table (2)"])
        #expect(await state.loadEnterData(try #require(EnterDataTable(name: "Table (2)", m: table2M))) == nil)
        #expect(state.workspace.runtime?.calculationErrors.isEmpty == true, "\(state.workspace.runtime?.calculationErrors ?? [:])")

        // Lưu ra build/f2-out/f11/bipro-f11.pbix, mở lại.
        let destination = try F2Fixtures.outputDirectory("f11").appendingPathComponent("bipro-f11.pbix")
        try? FileManager.default.removeItem(at: destination)
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)
        let reopened = try Workspace(data: Data(contentsOf: destination))
        let ours = try #require(reopened.metadata)

        // Cấu trúc như Desktop.
        #expect(Set(ours.userTables.map(\.name)) == Set(desktop.userTables.map(\.name)))
        for table in desktop.userTables.map(\.name) {
            #expect(reopened.rowCount(table) == (try Workspace(data: Data(contentsOf: desktopURL))).rowCount(table), "\(table)")
        }
        func columns(_ m: ModelMetadata) -> Set<String> {
            Set(m.columns.filter { c in m.userTables.contains { $0.name == c.tableName } && c.kind != .rowNumber }.map { "\($0.tableName)[\($0.name)]:\($0.dataType)" })
        }
        #expect(columns(ours) == columns(desktop))
        #expect(ours.modelAnnotations[AutoDateTime.modelAnnotation] == "1")
        #expect(Set(ours.variations.map { "\($0.table)[\($0.column)]" }) == Set(desktop.variations.map { "\($0.table)[\($0.column)]" }))
        #expect(ours.tables.filter { AutoDateTime.isLocalTable($0.name) }.count == desktop.tables.filter { AutoDateTime.isLocalTable($0.name) }.count)
        #expect(ours.tables.filter { AutoDateTime.isTemplateTable($0.name) }.count == 1)
        #expect(ours.dateTableRelationships.count == desktop.dateTableRelationships.count)
        func relationships(_ m: ModelMetadata) -> Set<String> {
            Set(m.relationships.map { "\($0.fromTable)[\($0.fromColumn)]→\($0.toTable)[\($0.toColumn)] \($0.isActive) \($0.cardinality) \($0.crossFilteringBehavior) \($0.name.hasPrefix("AutoDetected_"))" })
        }
        #expect(relationships(ours) == relationships(desktop))

        // Số liệu: biểu đồ theo Năm bằng tổng theo năm tính thẳng trên Sales.
        let saved = try #require(reopened.report.pages.flatMap(\.visuals).first { $0.id == chart })
        let spec = try VisualQuerySpecReader(metadata: ours).spec(for: saved, filters: [])
        let engine = try await reopened.daxEngine()
        let result = try await engine.execute(DAXQueryBuilder.build(spec))
        let rows = try #require(result.tables.first?.rows)
        #expect(!rows.isEmpty)
        for row in rows {
            guard case .integer(let year)? = row.first else { Issue.record("năm không phải số nguyên: \(row)"); continue }
            let direct = number(try await engine.execute(
                "EVALUATE ROW(\"v\", SUMX(FILTER(Sales, YEAR(Sales[OrderDate]) = \(year)), Sales[Amount]))"))
            let shown: Double? = switch row.last { case .integer(let i)?: Double(i); case .double(let d)?: d; case .currency(let c)?: Double(c) / 10_000; default: nil }
            #expect(shown.map { abs($0 - (direct ?? .nan)) < 0.005 } == true, "\(year): \(String(describing: shown)) ≠ \(String(describing: direct))")
        }
        let total = number(try await engine.execute("EVALUATE ROW(\"v\", SUM(Sales[Amount]))"))
        let desktopEngine = try await (try Workspace(data: Data(contentsOf: desktopURL))).daxEngine()
        #expect(total == number(try await desktopEngine.execute("EVALUATE ROW(\"v\", SUM(Sales[Amount]))")))
    }
}
