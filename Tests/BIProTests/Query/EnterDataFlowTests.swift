// Đợt tồn đọng sau Phase F, T028: Ribbon "Nhập dữ liệu" → hộp "Tạo bảng" → Tải: bảng vào mô hình một bước ⌘Z, tên cột bỏ U+FEFF đầu như
// Desktop (VM-F11a), M Enter Data lưu vào `Partition.QueryDefinition`, mở lại vẫn đúng. Seam: `DocumentState` (`showEnterData`,
// `loadEnterData`), `DocumentSaver.saveUntitled`.
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Đợt F2: Enter Data", .serialized) @MainActor struct EnterDataFlowTests {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("enterdata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func scalar(_ state: DocumentState, _ expression: String) async throws -> Double? {
        let result = try await state.workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))")
        switch result.tables.first?.rows.first?.first {
        case .integer(let i)?: return Double(i)
        case .double(let d)?: return d
        default: return nil
        }
    }

    @Test func nhapDuLieuVaoTaiLieuMoiRoiLuuMoLai() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent,
                                  fileURL: untitled)
        #expect(state.enterDataBlocker == nil)
        state.showEnterData()
        var table = try #require(state.enterData)
        #expect(table.name == "Table")
        try table.paste(EnterDataStateTests.pastedTable)
        let depth = state.layout.undoDepth
        #expect(await state.loadEnterData(table) == nil)
        #expect(state.enterData == nil)
        #expect(state.layout.undoDepth == depth + 1)

        let columns = state.workspace.metadata?.columns.filter { $0.tableName == "Table" && $0.kind != .rowNumber }.map(\.name)
        #expect(columns == ["Tên", "Số lượng", "Ghi chú"])
        #expect(state.workspace.rowCount("Table") == 5)
        #expect(try await scalar(state, "SUM('Table'[Số lượng])") == 13.5)
        #expect(try await scalar(state, "COUNTROWS(FILTER('Table', ISBLANK('Table'[Số lượng])))") == 1)

        // Lần hai: tên mặc định "Table (2)".
        state.showEnterData()
        #expect(state.enterData?.name == "Table (2)")
        state.closeEnterData()
        #expect(state.enterData == nil)

        // ⌘Z bỏ cả bảng, ⇧⌘Z trả lại.
        state.layout.undo()
        #expect(!state.workspace.userTables.contains { $0.name == "Table" })
        state.layout.redo()
        #expect(state.workspace.rowCount("Table") == 5)

        let destination = root.appendingPathComponent("enter-data.pbix")
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)
        let reopened = DocumentState(workspace: try Workspace(data: Data(contentsOf: destination)), fileName: "enter-data.pbix",
                                     fileURL: destination)
        #expect(reopened.workspace.rowCount("Table") == 5)
        #expect(try await scalar(reopened, "SUM('Table'[Số lượng])") == 13.5)
        #expect(reopened.workspace.metadata?.partitionQueries["Table"] == table.m)
    }

    /// Query Editor: truy vấn Enter Data đọc từ file không bị khoá; bánh răng bước Source mở lại lưới, OK thay bước Source (VM-F11a, ảnh a7).
    @Test func suaLaiQuaBuocSourceTrongQueryEditor() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent,
                                  fileURL: untitled)
        state.showEnterData()
        var table = try #require(state.enterData)
        try table.paste("A\tB\r\nx\t1\r\ny\t2\r\n")
        #expect(await state.loadEnterData(table) == nil)

        state.showQueryEditor()
        let editor = try #require(state.queryEditorState)
        let query = try #require(editor.queries.first { $0.name == "Table" })
        #expect(query.lockedStepCount == 0)
        editor.selectQuery(query.id)
        #expect(editor.enterDataSource(at: 1) == nil)   // chỉ bước Source
        // Gửi lại đúng biểu thức cũ (thanh công thức mất tiêu điểm) không tính là thay đổi.
        #expect(editor.setExpression(at: 1, try #require(editor.selectedQuery?.steps[1].expression)) == nil)
        #expect(!editor.hasPendingChanges)
        var source = try #require(editor.enterDataSource(at: 0))
        #expect(source.rows == [["x", "1"], ["y", "2"]])
        source.addRow()
        source.set(row: 2, column: 0, to: "z")
        source.set(row: 2, column: 1, to: "3")
        #expect(editor.setEnterData(source) == nil)
        await editor.refresh()
        #expect(editor.errorMessage == nil)
        #expect(editor.preview?.rowCount == 3)
        #expect(editor.selectedQuery?.steps.map(\.name) == ["Source", "Changed Type"])
        #expect(editor.hasPendingChanges)
    }

    @Test func bangRongVanNapDuoc() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent,
                                  fileURL: untitled)
        state.showEnterData()
        #expect(await state.loadEnterData(try #require(state.enterData)) == nil)
        #expect(state.workspace.rowCount("Table") == 1)
    }
}
