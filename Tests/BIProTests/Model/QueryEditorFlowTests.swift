// Phase F, T060/T063: Query Editor nối vào tài liệu, từ DocumentState (Ribbon "Biến đổi dữ liệu", Navigator "Chuyển đổi dữ liệu") đến
// mô hình: Excel → thêm bước → Close & Apply → bảng đúng số dòng, một bước ⌘Z. Chạy trên Nhom6 thật (BIPRO_HEAVY=1) và file mẫu
// `build/f-out/samples/sales_2026.xlsx` (Sales 500 dòng). Số mong đợi viết tay.
import ColumnStore
import Connectors
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: Query Editor trong tài liệu", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil && FFixtures.sample("sales_2026.xlsx") != nil),
       .serialized)
@MainActor
struct QueryEditorFlowTests {
    private func makeState() throws -> DocumentState {
        DocumentState(workspace: try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6))), fileName: "Nhom6_f.pbix")
    }

    private func loadSales(_ state: DocumentState) async throws -> [LoadedTable] {
        let url = try #require(FFixtures.sample("sales_2026.xlsx"))
        state.showGetData(kind: .excel, pickFile: { _ in url.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems {
            try await Task.sleep(for: .milliseconds(25))
        }
        for item in navigator.items where item.name == "Sales" { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        state.closeGetData()
        return loaded
    }

    private func waitUntilClosed(_ state: DocumentState) async throws {
        for _ in 0..<400 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
    }

    @Test func excelThemBuocApDungMotBuocHoanTac() async throws {
        let state = try makeState()
        let loaded = try await loadSales(state)
        let name = try #require(loaded.first?.name)
        let before = state.layout.undoDepth

        state.showQueryEditor(loaded: loaded)
        let editor = try #require(state.queryEditorState)
        #expect(editor.queries.count == 1 && editor.selectedQuery?.loadedTableName == nil)
        #expect(editor.perform(.keepTopRows(100)) == .applied)

        state.applyQueryEditor()
        try await waitUntilClosed(state)
        #expect(state.queryEditorState == nil)
        #expect(editor.applyMessage == nil && !editor.isApplying)
        #expect(state.workspace.rowCount(name) == 100)
        #expect(state.layout.undoDepth == before + 1)
        #expect(state.workspace.metadata?.partitionQueries[name]?.contains("Table.FirstN") == true)

        state.layout.undo()
        #expect(state.workspace.metadata?.userTables.contains { $0.name == name } == false)
    }

    @Test func moBangCoSanLietKeTruyVanVaXemTruocTuDuLieuMoHinh() async throws {
        let state = try makeState()
        state.showQueryEditor()
        let editor = try #require(state.queryEditorState)
        #expect(editor.queries.count == 11)
        #expect(editor.queries.allSatisfy { $0.lockedStepCount == $0.steps.count && $0.loadedTableName != nil })
        for _ in 0..<200 where editor.preview == nil { try await Task.sleep(for: .milliseconds(25)) }
        let preview = try #require(editor.preview)
        let table = try #require(editor.selectedQuery?.loadedTableName)
        #expect(preview.rowCount == min(1000, state.workspace.rowCount(table)))
        // Đang mở thì nút Ribbon báo lý do, mở lần hai không tạo cửa sổ thứ hai.
        #expect(state.queryEditorBlocker != nil)
        state.showQueryEditor()
        #expect(state.queryEditorState === editor)
        state.closeQueryEditor()
        #expect(state.queryEditorBlocker == nil)
    }

    /// Lưu rồi mở lại: truy vấn M đọc lại từ file (bước khoá), sửa tiếp và Apply lần hai thay bảng trong phiên; lưu thay bảng đã có trong file chưa cài nên bị từ chối.
    @Test func luuMoLaiSuaTiepApDungLanHai() async throws {
        let dir = try EFixtures.outputDirectory("F-queryeditor")
        let source = dir.appendingPathComponent("Nhom6_f_qe.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: dir.appendingPathComponent("Backups")) }
        let backups = dir.appendingPathComponent("Backups")
        func open() throws -> DocumentState {
            DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
        }

        let first = try open()
        let loaded = try await loadSales(first)
        let name = try #require(loaded.first?.name)
        first.showQueryEditor(loaded: loaded)
        #expect(try #require(first.queryEditorState).perform(.keepTopRows(100)) == .applied)
        first.applyQueryEditor()
        try await waitUntilClosed(first)
        #expect(try DocumentSaver.save(editor: first.layout, source: source, to: source, expectedStamp: nil,
                                       readOnlyRoots: [], backupDirectory: backups).didWrite)

        let second = try open()
        #expect(second.workspace.rowCount(name) == 100)
        second.showQueryEditor()
        let editor = try #require(second.queryEditorState)
        let index = try #require(editor.queries.firstIndex { $0.loadedTableName == name })
        let query = editor.queries[index]
        #expect(query.steps.last?.expression.contains("Table.FirstN") == true)
        #expect(query.lockedStepCount == query.steps.count && !query.isModified)
        editor.selectQuery(query.id)
        for _ in 0..<200 where editor.preview == nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(editor.preview?.rowCount == 100)
        #expect(editor.perform(.keepTopRows(20)) == .applied)
        second.applyQueryEditor()
        try await waitUntilClosed(second)
        #expect(second.workspace.rowCount(name) == 20)
        // Ghi lại dữ liệu thay thế cho bảng đã có trong file chưa cài (T063b): lưu bị từ chối, file giữ nguyên 100 dòng.
        #expect(throws: (any Error).self) {
            try DocumentSaver.save(editor: second.layout, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: backups)
        }
        #expect(try open().workspace.rowCount(name) == 100)
    }
}
