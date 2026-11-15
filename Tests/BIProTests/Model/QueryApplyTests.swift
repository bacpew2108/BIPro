// Phase F, T062: Close & Apply của Query Editor đưa truy vấn vào mô hình qua ModelEditor (một bước ⌘Z chung, FR-080), thay bảng đã nạp
// khi sửa truy vấn, tôn trọng "Enable load" và từ chối kèm nơi dùng khi mất cột còn được dùng (FR-054). Metadata Nhom6 chỉ đọc.
import ColumnStore
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: Close & Apply", .enabled(if: EFixtures.metadata != nil)) @MainActor struct QueryApplyTests {
    typealias Env = FieldEditingTests.Env
    let metadata = EFixtures.metadata!

    private func table(rows: Int = 6) throws -> TableData {
        try TableData(columns: [
            TableColumn(name: "Key", data: ColumnBuilder.integers((1...rows).map { Int64($0) })),
            TableColumn(name: "Region", data: ColumnBuilder.strings((1...rows).map { "r\($0 % 3)" })),
            TableColumn(name: "Qty", data: ColumnBuilder.integers((1...rows).map { Int64($0 * 10) })),
        ])
    }

    private func modelEditor(_ env: Env) -> ModelEditor {
        let base = metadata
        return ModelEditor(layout: env.editor) { edits in _ = try base.applying(edits) }
    }

    private func stateWithQuery(named name: String = "Sales2026") throws -> QueryEditorState {
        let state = QueryEditorState()
        state.addQuery(from: LoadedTable(name: name, data: try table(),
                                         origin: LoadedOrigin(kind: .csv, location: "/khong/co/\(name).csv", itemName: name, itemKind: .file)))
        return state
    }

    private func tableEdits(_ env: Env) -> [(kind: String, name: String, query: String?)] {
        env.editor.modelEdits.items.compactMap { edit in
            switch edit {
            case .addTable(let t): ("add", t.name, t.queryExpression)
            case .replaceTable(_, let t): ("replace", t.name, t.queryExpression)
            case .dropTable(let name): ("drop", name, nil)
            default: nil
            }
        }
    }

    @Test func truyVanMoiThanhBangVoiMDesktopMotBuocHoanTac() async throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = modelEditor(env)
        let state = try stateWithQuery()
        state.perform(.keepTopRows(4))
        let before = env.editor.undoDepth
        #expect(await state.closeAndApply(to: editor, existingTableNames: Set(metadata.tables.map(\.name))) == nil)
        #expect(env.editor.undoDepth == before + 1)
        let edits = tableEdits(env)
        #expect(edits.count == 1 && edits[0].kind == "add" && edits[0].name == "Sales2026")
        #expect(edits[0].query == state.selectedQuery?.source)
        #expect(edits[0].query?.contains(#"Table.FirstN(#"Changed Type",4)"#) == true)
        let effective = try metadata.applying(env.editor.modelEdits)
        #expect(effective.columns.filter { $0.tableName == "Sales2026" && $0.kind == .data }.map(\.name) == ["Key", "Region", "Qty"])
        #expect(effective.partitionQueries["Sales2026"] == edits[0].query)
        // Bảng nhận đúng 4 dòng của kết quả truy vấn (không phải 6 dòng gốc).
        let data = env.editor.modelEdits.tableData(in: effective).values.first
        #expect(data?.rowCount == 4)
        #expect(state.selectedQuery?.loadedTableName == "Sales2026" && state.selectedQuery?.isModified == false)
        #expect(!state.hasPendingChanges)

        env.editor.undo()
        #expect(env.editor.modelEdits.isEmpty)
    }

    @Test func ApDungLanHaiKhongDoiGiVaSuaTruyVanThanhThayBang() async throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = modelEditor(env)
        let state = try stateWithQuery()
        let existing = Set(metadata.tables.map(\.name))
        #expect(await state.closeAndApply(to: editor, existingTableNames: existing) == nil)
        let depth = env.editor.undoDepth
        #expect(!state.hasUnappliedQueries)
        #expect(await state.closeAndApply(to: editor, existingTableNames: existing.union(["Sales2026"])) == nil)
        #expect(env.editor.undoDepth == depth)   // không có gì để áp

        state.perform(.removeColumns(["Qty"]))
        #expect(state.hasUnappliedQueries)
        #expect(await state.closeAndApply(to: editor, existingTableNames: existing.union(["Sales2026"])) == nil)
        #expect(tableEdits(env).map(\.kind) == ["add", "replace"])
        let effective = try metadata.applying(env.editor.modelEdits)
        #expect(effective.columns.filter { $0.tableName == "Sales2026" && $0.kind == .data }.map(\.name) == ["Key", "Region"])
        #expect(effective.partitionQueries["Sales2026"]?.contains("Table.RemoveColumns") == true)
    }

    @Test func tatEnableLoadGoBangDaNap() async throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = modelEditor(env)
        let state = try stateWithQuery()
        let existing = Set(metadata.tables.map(\.name))
        #expect(await state.closeAndApply(to: editor, existingTableNames: existing) == nil)
        state.setEnableLoad(try #require(state.selectedQueryID), false)
        #expect(state.hasUnappliedQueries)
        #expect(await state.closeAndApply(to: editor, existingTableNames: existing.union(["Sales2026"])) == nil)
        #expect(tableEdits(env).map(\.kind) == ["add", "drop"])
        #expect(try !metadata.applying(env.editor.modelEdits).tables.contains { $0.name == "Sales2026" })
        #expect(state.selectedQuery?.loadedTableName == nil)
    }

    @Test func truyVanTatEnableLoadChuaNapKhongTaoBang() async throws {
        let env = try Env(); defer { env.cleanUp() }
        let state = try stateWithQuery()
        state.setEnableLoad(try #require(state.selectedQueryID), false)
        #expect(!state.hasUnappliedQueries)
        #expect(await state.closeAndApply(to: modelEditor(env), existingTableNames: []) == nil)
        #expect(tableEdits(env).isEmpty)
    }

    @Test func buocLoiTraLyDoVaKhongDoiGi() async throws {
        let env = try Env(); defer { env.cleanUp() }
        let state = try stateWithQuery()
        state.perform(.keepTopRows(2))
        #expect(state.setExpression(at: 3, #"Table.SelectRows(#"Changed Type", each [KhongCo] > 1)"#) == nil)
        let before = env.editor.undoDepth
        let reason = await state.closeAndApply(to: modelEditor(env), existingTableNames: [])
        #expect(reason?.contains("Sales2026") == true)
        #expect(env.editor.undoDepth == before && tableEdits(env).isEmpty)
        #expect(state.hasPendingChanges)
    }

    @Test func mauThuanTenBangBiTuChoiTatCaHoacKhong() async throws {
        let env = try Env(); defer { env.cleanUp() }
        let existing = metadata.userTables[0].name
        let state = try stateWithQuery(named: existing)
        // Tên truy vấn trùng bảng đã có: bảng nạp được đặt tên khử trùng, không đè bảng của mô hình.
        #expect(await state.closeAndApply(to: modelEditor(env), existingTableNames: Set(metadata.tables.map(\.name))) == nil)
        let added = try #require(tableEdits(env).first)
        #expect(added.name != existing && added.name.hasPrefix(existing))
    }

    @Test func matCotDangDuocDungBiTuChoiKemNoiDung() async throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = modelEditor(env)
        let state = try stateWithQuery()
        let existing = Set(metadata.tables.map(\.name))
        #expect(await state.closeAndApply(to: editor, existingTableNames: existing) == nil)
        #expect(editor.apply(.addMeasure(NewMeasure(table: "Sales2026", name: "Tong Qty", expression: "SUM(Sales2026[Qty])"))) == nil)

        state.perform(.removeColumns(["Qty"]))
        let depth = env.editor.undoDepth
        let reason = await state.closeAndApply(to: editor, existingTableNames: existing.union(["Sales2026"]))
        #expect(reason?.contains("Qty") == true && reason?.contains("Tong Qty") == true)
        #expect(env.editor.undoDepth == depth)
        #expect(state.hasPendingChanges && state.selectedQuery?.isModified == true)
    }
}
