// Phase F, T021: đưa bảng đã nạp vào mô hình qua ModelEditor, một bước ⌘Z cho cả lần nạp (FR-004, FR-080).
// Seam: `TableLoader.apply(_:to:)` trên ngăn xếp hoàn tác thật của LayoutEditor, kiểm hợp lệ bằng metadata Nhom6 (chỉ đọc).
import ColumnStore
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: nạp bảng vào mô hình", .enabled(if: EFixtures.metadata != nil)) @MainActor struct TableApplyTests {
    typealias Env = FieldEditingTests.Env
    let metadata = EFixtures.metadata!

    private func loaded(_ name: String, status: LoadedTable.Status = .new, rows: Int = 3) throws -> LoadedTable {
        let data = try TableData(columns: [TableColumn(name: "Key", data: ColumnBuilder.integers((1...rows).map { Int64($0) })),
                                           TableColumn(name: "Region", data: ColumnBuilder.strings((1...rows).map { "r\($0)" }))])
        return LoadedTable(name: name, data: data, status: status)
    }

    private func modelEditor(_ env: Env) -> ModelEditor {
        let base = metadata
        return ModelEditor(layout: env.editor) { edits in _ = try base.applying(edits) }
    }

    @Test func nhieuBangMotBuocHoanTacVaLamLai() throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = modelEditor(env)
        let before = env.editor.undoDepth
        #expect(TableLoader.apply([try loaded("Sales2026"), try loaded("Customers")], to: editor) == nil)
        #expect(env.editor.undoDepth == before + 1)
        #expect(env.editor.isDirty)
        #expect(env.editor.modelEdits.items.count == 2)
        let effective = try metadata.applying(env.editor.modelEdits)
        #expect(effective.userTables.map(\.name).suffix(2) == ["Sales2026", "Customers"])

        env.editor.undo()
        #expect(env.editor.modelEdits.isEmpty && !env.editor.isDirty)
        env.editor.redo()
        #expect(env.editor.modelEdits.items.count == 2)
    }

    @Test func tenTrungMoHinhBiTuChoiVaKhongDoiGi() throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = modelEditor(env)
        let existing = metadata.userTables[0].name
        let before = env.editor.undoDepth
        let reason = TableLoader.apply([try loaded("Moi"), try loaded(existing)], to: editor)
        #expect(reason?.contains("trùng") == true)
        #expect(env.editor.undoDepth == before)
        #expect(env.editor.modelEdits.isEmpty)       // bảng "Moi" cũng không vào: tất cả hoặc không
    }

    @Test func bangThayTheDungReplaceVaBangKhongDoiBiBoQua() throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = modelEditor(env)
        #expect(TableLoader.apply([try loaded("Sales2026")], to: editor) == nil)
        env.editor.markSaved()
        let reason = TableLoader.apply([try loaded("Sales2026", status: .replaced, rows: 5), try loaded("Khong doi", status: .unchanged)], to: editor)
        #expect(reason == nil)
        let kinds = env.editor.modelEdits.items.map { edit -> String in
            switch edit {
            case .addTable: "add"
            case .replaceTable: "replace"
            default: "other"
            }
        }
        #expect(kinds == ["add", "replace"])
        let effective = try metadata.applying(env.editor.modelEdits)
        #expect(!effective.userTables.contains { $0.name == "Khong doi" })
    }

    @Test func khongCoBangThiKhongTaoBuoc() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = env.editor.undoDepth
        #expect(TableLoader.apply([], to: modelEditor(env)) == nil)
        #expect(TableLoader.apply([try loaded("Bo qua", status: .unchanged)], to: modelEditor(env)) == nil)
        #expect(env.editor.undoDepth == before && !env.editor.isDirty)
    }

    @Test func bangDaGanDuLieuDeHoanTacKhongSaoChepTableData() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(TableLoader.apply([try loaded("Sales2026", rows: 4)], to: modelEditor(env)) == nil)
        guard case .addTable(let table) = env.editor.modelEdits.items[0] else { Issue.record("phải là addTable"); return }
        env.editor.undo(); env.editor.redo()
        guard case .addTable(let again) = env.editor.modelEdits.items[0] else { Issue.record("phải là addTable"); return }
        #expect(again === table)                           // cùng một đối tượng sau hoàn tác/làm lại
        #expect((again.attachment as? TableData)?.rowCount == 4)
    }
}
