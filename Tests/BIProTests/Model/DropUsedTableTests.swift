// Phase F, T098 (FR-004, FR-054): tắt "Enable load" của bảng đã nạp mà visual hoặc cột tính toán ở bảng khác còn dùng thì Close & Apply
// bị từ chối kèm nơi dùng (như quy tắc chặn của Phase E); không ai dùng thì gỡ được.
import ColumnStore
import Connectors
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: chặn gỡ bảng còn được dùng", .enabled(if: FFixtures.sample("sales_2026.sqlite") != nil), .serialized) @MainActor
struct DropUsedTableTests {
    private func loadedDocument(root: URL) async throws -> DocumentState {
        let sample = try #require(FFixtures.sample("sales_2026.sqlite"))
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        state.showGetData(kind: .sqlite, pickFile: { _ in sample.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<400 where navigator.phase == .listingItems || navigator.phase == .choosingSource { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items where item.name != "NorthSales" { navigator.toggle(item.id) }
        let tables = try #require(await navigator.load(existingNames: state.existingTableNames))
        #expect(state.loadFromGetData(tables) == nil)
        state.closeGetData()
        return state
    }

    private func disableLoadAndApply(_ table: String, in state: DocumentState) async throws -> String? {
        state.showQueryEditor()
        let editor = try #require(state.queryEditorState)
        let query = try #require(editor.queries.first { $0.name == table })
        editor.setEnableLoad(query.id, false)
        state.applyQueryEditor()
        for _ in 0..<400 where editor.isApplying || state.queryEditorState != nil && editor.applyMessage == nil { try await Task.sleep(for: .milliseconds(25)) }
        return editor.applyMessage
    }

    @Test func visualConDungBangThiKhongGoDuoc() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await loadedDocument(root: root)
        let card = try #require(state.layout.insertVisual(type: "slicer", visibleRect: CGRect(x: 0, y: 0, width: 1280, height: 720)))
        #expect(state.layout.addField(FieldRef(kind: .column, entity: "Customers", property: "CustomerID"), to: "Values", visual: card) == nil)

        let reason = try await disableLoadAndApply("Customers", in: state)
        #expect(reason?.contains("visual \(card)") == true, "\(reason ?? "nil")")
        #expect(state.workspace.userTables.contains { $0.name == "Customers" })
    }

    @Test func cotTinhToanBangKhacConDungThiKhongGoDuoc() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await loadedDocument(root: root)
        #expect(state.modelEditor.apply(.addCalculatedColumn(table: "Sales", name: "So khach", expression: "COUNTROWS(Customers)", dataType: .int64)) == nil)

        let reason = try await disableLoadAndApply("Customers", in: state)
        #expect(reason?.contains("Sales[So khach]") == true, "\(reason ?? "nil")")
        #expect(state.workspace.userTables.contains { $0.name == "Customers" })
    }

    @Test func khongAiDungThiGoDuoc() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await loadedDocument(root: root)
        #expect(try await disableLoadAndApply("Customers", in: state) == nil)
        #expect(!state.workspace.userTables.contains { $0.name == "Customers" })
    }
}
