import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T014 đến T016): tạo, sửa, xoá measure ở Table view trên Nhom6 thật (BIPRO_HEAVY=1).
@Suite("Phase E: sửa measure", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct MeasureEditorTests {
    private func makeState() throws -> DocumentState {
        let workspace = try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6)))
        let state = DocumentState(workspace: workspace, fileName: "Nhom6_e.pbix")
        state.mode = .table
        // Đồng hồ giả để các lần sửa liên tiếp không bị gộp thành một bước hoàn tác.
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        return state
    }

    private func value(_ state: DocumentState, _ measure: String) async throws -> Double? {
        let result = try await state.workspace.daxEngine().execute("EVALUATE ROW(\"x\", [\(measure)])")
        switch result.tables.first?.rows.first?.first {
        case .integer(let i)?: return Double(i)
        case .double(let d)?: return d
        default: return nil
        }
    }

    @Test func taoSuaHoanTacMeasure() async throws {
        let state = try makeState()
        let before = try #require(state.workspace.metadata).measures.count
        state.beginNewMeasure(table: "Dim_Account")
        let draft = try #require(state.measureDraft)
        #expect(draft.text == "Measure = ")     // tên mặc định như Desktop
        draft.text = "E_Test = COUNTROWS(Dim_Account)+1"
        await state.applyMeasureDraft()
        #expect(draft.message == nil, Comment(rawValue: draft.message ?? ""))
        let created = try #require(state.workspace.measure(table: "Dim_Account", name: "E_Test"))
        #expect(created.dataType == .int64 && created.formatString == "0" && created.state == 1)
        #expect(state.workspace.metadata?.measures.count == before + 1)
        #expect(draft.preview != nil && draft.mode == .edit(table: "Dim_Account", name: "E_Test"))
        #expect(try await value(state, "E_Test") == 4502)
        #expect(state.layout.isDirty && state.measure == "E_Test")

        // Sửa biểu thức: số mới ngay, hoàn tác một bước về số cũ.
        draft.text = "E_Test = COUNTROWS(Dim_Account)+2"
        await state.applyMeasureDraft()
        #expect(try await value(state, "E_Test") == 4503)
        state.layout.undo()
        #expect(try await value(state, "E_Test") == 4502)
        state.layout.undo()
        #expect(state.workspace.measure(table: "Dim_Account", name: "E_Test") == nil)
        #expect(!state.layout.isDirty)
        state.layout.redo()
        #expect(state.workspace.measure(table: "Dim_Account", name: "E_Test") != nil)
    }

    @Test func bieuThucSaiVaTrungTenBiTuChoiKhongDoiGi() async throws {
        let state = try makeState()
        let measures = try #require(state.workspace.metadata).measures
        let existing = try #require(measures.first { $0.tableName == "Dim_Account" })
        state.beginNewMeasure(table: "Dim_Account")
        let draft = try #require(state.measureDraft)

        draft.text = "E_Bad = COUNTRWS(Dim_Account)"
        await state.applyMeasureDraft()
        #expect(draft.message != nil)
        draft.text = "E_Bad = COUNTROWS("
        await state.applyMeasureDraft()
        #expect(draft.message?.contains("dòng 1") == true)
        draft.text = "\(existing.name) = 1"
        await state.applyMeasureDraft()
        #expect(draft.message?.contains("đã có") == true)
        draft.text = "chỉ có tên"
        await state.applyMeasureDraft()
        #expect(draft.message?.contains("Tên = biểu thức") == true)
        #expect(state.workspace.metadata?.measures.count == measures.count)
        #expect(!state.layout.isDirty)
    }

    @Test func xoaVaDoiTenBiChanKhiConNoiDung() async throws {
        let state = try makeState()
        let model = try #require(state.workspace.metadata)
        let used = try #require(model.measures.first { m in
            model.measures.contains { $0.name != m.name && DAXEngine.references(in: $0.expression).contains { $0.name == m.name } }
        })
        // xoá bị chặn kèm lý do và danh sách
        let reason = try #require(state.deleteMeasure(table: used.tableName, name: used.name))
        #expect(reason.contains("còn được dùng ở"))
        #expect(state.workspace.measure(table: used.tableName, name: used.name) != nil && !state.layout.isDirty)
        // đổi tên bị chặn
        state.selectMeasure(table: used.tableName, name: used.name)
        let draft = try #require(state.measureDraft)
        draft.text = MeasureFormula.format(name: used.name + " Moi", expression: used.expression)
        await state.applyMeasureDraft()
        #expect(draft.message?.contains("Không đổi tên được") == true)
        #expect(state.workspace.measure(table: used.tableName, name: used.name) != nil)

        // measure mới không ai dùng: xoá được, hoàn tác đưa lại
        state.beginNewMeasure(table: "Dim_Account")
        state.measureDraft?.text = "E_Test = 1"
        await state.applyMeasureDraft()
        #expect(state.deleteMeasure(table: "Dim_Account", name: "E_Test") == nil)
        #expect(state.workspace.measure(table: "Dim_Account", name: "E_Test") == nil && state.measure == nil)
        state.layout.undo()
        #expect(state.workspace.measure(table: "Dim_Account", name: "E_Test") != nil)
    }

    @Test func thuocTinhMeasureQuaUpdateMeasure() async throws {
        let state = try makeState()
        state.beginNewMeasure(table: "Dim_Account")
        state.measureDraft?.text = "E_Test = 1"
        await state.applyMeasureDraft()
        #expect(state.updateMeasure(table: "Dim_Account", name: "E_Test",
                                    patch: MeasurePatch(formatString: .set("#,0"), displayFolder: .set("Thu muc E"),
                                                        description: .set("mo ta"), isHidden: true)) == nil)
        let m = try #require(state.workspace.measure(table: "Dim_Account", name: "E_Test"))
        #expect(m.formatString == "#,0" && m.displayFolder == "Thu muc E" && m.description == "mo ta" && m.isHidden)
        #expect(state.updateMeasure(table: "Dim_Account", name: "Khong Co", patch: MeasurePatch(isHidden: true)) != nil)
    }

    @Test func chedoXemChanSuaMoHinh() async throws {
        let state = try makeState()
        state.mode = .report
        state.editMode = false
        #expect(state.modelEditingBlocker?.contains("Sửa") == true)
        state.beginNewMeasure(table: "Dim_Account")
        #expect(state.measureDraft == nil)
        let existing = try #require(state.workspace.metadata?.measures.first)
        #expect(state.deleteMeasure(table: existing.tableName, name: existing.name) != nil)
        state.editMode = true
        #expect(state.modelEditingBlocker == nil)
    }

    /// Từ Data pane của chế độ Báo cáo (đang Sửa): "Measure mới" và "Sửa công thức" chuyển sang Table view.
    @Test func tuChedoBaoCaoMoMeasureOTableView() async throws {
        let state = try makeState()
        state.mode = .report
        state.editMode = false
        state.newMeasureInTableView(table: "Dim_Account")
        #expect(state.mode == .report && state.measureDraft == nil, "chế độ Xem: bị chặn, không chuyển")
        state.editMode = true
        state.newMeasureInTableView(table: "Dim_Account")
        #expect(state.mode == .table && state.measureDraft?.mode == .new(table: "Dim_Account"))
        state.mode = .report
        let existing = try #require(state.workspace.measures(of: "Dim_Account").first)
        state.editMeasureInTableView(table: "Dim_Account", name: existing.name)
        #expect(state.mode == .table && state.measure == existing.name)
        #expect(state.measureDraft?.text == MeasureFormula.format(name: existing.name, expression: existing.expression))
    }

    /// Ở Model view: chọn measure giữ nguyên Model view, mở bản nháp để sửa ở ngăn thuộc tính; chọn bảng bỏ chọn measure.
    @Test func chonMeasureOModelViewGiuChedo() async throws {
        let state = try makeState()
        state.mode = .model
        let existing = try #require(state.workspace.measures(of: "Dim_Account").first)
        state.selectMeasure(table: "Dim_Account", name: existing.name)
        #expect(state.mode == .model && state.measureDraft != nil)
        state.select(table: "Dim_Account")
        #expect(state.measure == nil && state.measureDraft == nil)
    }
}
