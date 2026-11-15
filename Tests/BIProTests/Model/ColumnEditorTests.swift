import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T028 đến T030): sửa thuộc tính cột (không đụng dữ liệu) ở Table view trên Nhom6 thật (BIPRO_HEAVY=1).
@Suite("Phase E: sửa cột", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct ColumnEditorTests {
    private func makeState() throws -> DocumentState {
        let workspace = try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6)))
        let state = DocumentState(workspace: workspace, fileName: "Nhom6_e.pbix")
        state.mode = .table
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        return state
    }

    private func column(_ state: DocumentState, _ table: String, _ name: String) throws -> ModelMetadata.Column {
        try #require(state.workspace.column(table: table, name: name))
    }

    @Test func suaMoiThuocTinhVaHoanTac() throws {
        let state = try makeState()
        let before = try column(state, "Dim_Client", "client_division")
        #expect(state.updateColumn(table: "Dim_Client", name: "client_division", patch: ColumnPatch(
            isHidden: true, formatString: .set("@"), dataCategory: .set("StateOrProvince"), displayFolder: .set("Thu muc"), description: .set("mo ta"))) == nil)
        let after = try column(state, "Dim_Client", "client_division")
        #expect(after.isHidden && after.formatString == "@" && after.dataCategory == "StateOrProvince" && after.displayFolder == "Thu muc" && after.description == "mo ta")
        #expect(after.id == before.id && after.dataType == before.dataType)
        state.layout.undo()
        let restored = try column(state, "Dim_Client", "client_division")
        #expect(restored.isHidden == before.isHidden && restored.formatString == before.formatString && restored.description == before.description)
        #expect(!state.layout.isDirty)
    }

    @Test func tongHopMacDinhVaSapXepTheoCot() throws {
        let state = try makeState()
        #expect(state.updateColumn(table: "Fact_Loan", name: "loan_amount", patch: ColumnPatch(summarizeBy: 7)) == nil)
        #expect(try column(state, "Fact_Loan", "loan_amount").summarizeBy == 7)
        // sắp xếp theo cột cùng bảng; khác bảng hoặc chính nó bị từ chối
        #expect(state.updateColumn(table: "Dim_Client", name: "age_group_current", patch: ColumnPatch(sortBy: .set("age_group_order"))) == nil)
        let sorted = try column(state, "Dim_Client", "age_group_current")
        let order = try column(state, "Dim_Client", "age_group_order")
        #expect(sorted.sortByColumnID == order.id)
        #expect(state.updateColumn(table: "Dim_Client", name: "age_group_current", patch: ColumnPatch(sortBy: .set("age_group_current"))) != nil)
        #expect(state.updateColumn(table: "Dim_Client", name: "age_group_current", patch: ColumnPatch(sortBy: .set("khong co"))) != nil)
        #expect(state.updateColumn(table: "Dim_Client", name: "age_group_current", patch: ColumnPatch(sortBy: .clear)) == nil)
        #expect(try column(state, "Dim_Client", "age_group_current").sortByColumnID == nil)
    }

    @Test func doiTenCotChanKhiConNoiDung() throws {
        let state = try makeState()
        // đầu quan hệ: bị chặn kèm lý do
        let reason = try #require(state.updateColumn(table: "Fact_Loan", name: "client_key", patch: ColumnPatch(name: "client_key2")))
        #expect(reason.contains("còn được dùng ở") || reason.contains("đầu của một quan hệ"))
        #expect(state.workspace.column(table: "Fact_Loan", name: "client_key") != nil)
        // cột đang dùng trong DAX của measure: bị chặn
        let model = try #require(state.workspace.metadata)
        let used = try #require(model.columns.first { c in
            c.kind == .data && model.measures.contains { DAXEngine.references(in: $0.expression).contains { $0.table == c.tableName && $0.name == c.name } }
                && !model.relationships.contains { ($0.fromTable == c.tableName && $0.fromColumn == c.name) || ($0.toTable == c.tableName && $0.toColumn == c.name) }
        })
        #expect(state.updateColumn(table: used.tableName, name: used.name, patch: ColumnPatch(name: used.name + "_moi"))?.contains("còn được dùng ở") == true)
        // cột không ai dùng: đổi tên được và `state.column` đi theo
        let free = try #require(model.columns.first { c in
            c.kind == .data && c.tableName == "Dim_Client" && !model.relationships.contains { ($0.fromTable == c.tableName && $0.fromColumn == c.name) || ($0.toTable == c.tableName && $0.toColumn == c.name) }
                && !model.measures.contains { DAXEngine.references(in: $0.expression).contains { $0.name == c.name } }
                && !model.columns.contains { $0.sortByColumnID == c.id }
                && !model.hierarchies.contains { $0.tableName == c.tableName && $0.levels.contains { $0.columnName == c.name } }
        })
        state.select(table: free.tableName, column: free.name)
        #expect(state.updateColumn(table: free.tableName, name: free.name, patch: ColumnPatch(name: "Cot Moi")) == nil)
        #expect(state.column == "Cot Moi" && state.workspace.column(table: free.tableName, name: "Cot Moi")?.id == free.id)
        #expect(state.workspace.displayNames(table: free.tableName, baseNames: [free.name]) == ["Cot Moi"])
    }

    @Test func chedoXemChanSuaCot() throws {
        let state = try makeState()
        state.mode = .report; state.editMode = false
        #expect(state.updateColumn(table: "Dim_Client", name: "client_division", patch: ColumnPatch(isHidden: true))?.contains("Sửa") == true)
    }

    /// Đổi định dạng, ẩn, sắp xếp theo cột, tổng hợp; lưu T2; mở lại. Ghi `build/e-out/E3/Nhom6_e3.pbix` cho buổi kiểm Desktop.
    @Test func luuMoLaiThuocTinhCot() throws {
        let dir = try EFixtures.outputDirectory("E3")
        let source = dir.appendingPathComponent("Nhom6_e3.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .table
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        #expect(state.updateColumn(table: "Dim_Client", name: "client_city", patch: ColumnPatch(displayFolder: .set("Thu muc cot"), description: .set("mo ta cot"))) == nil)
        #expect(state.updateColumn(table: "Dim_Client", name: "client_division", patch: ColumnPatch(isHidden: true)) == nil)
        #expect(state.updateColumn(table: "Fact_Loan", name: "loan_amount", patch: ColumnPatch(formatString: .set("#,0.00"), summarizeBy: 7)) == nil)
        #expect(state.updateColumn(table: "Dim_District", name: "division", patch: ColumnPatch(dataCategory: .set("StateOrProvince"))) == nil)
        #expect(state.updateColumn(table: "Dim_Client", name: "age_group_current", patch: ColumnPatch(sortBy: .set("age_group_order"))) == nil)
        let outcome = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                             readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        #expect(outcome.didWrite)
        let (abf, _) = try PBIXFile(url: source).loadDataModel()
        let read = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        func col(_ t: String, _ n: String) throws -> ModelMetadata.Column { try #require(read.columns.first { $0.tableName == t && $0.name == n }) }
        #expect(try col("Dim_Client", "client_city").description == "mo ta cot" && col("Dim_Client", "client_city").displayFolder == "Thu muc cot")
        #expect(try col("Dim_Client", "client_division").isHidden)
        #expect(try col("Fact_Loan", "loan_amount").formatString == "#,0.00" && col("Fact_Loan", "loan_amount").summarizeBy == 7)
        #expect(try col("Dim_District", "division").dataCategory == "StateOrProvince")
        #expect(try col("Dim_Client", "age_group_current").sortByColumnID == col("Dim_Client", "age_group_order").id)
    }
}
