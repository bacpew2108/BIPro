import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T020 đến T022): sửa thuộc tính quan hệ (hướng lọc, hoạt động) trên Nhom6 thật (BIPRO_HEAVY=1).
@Suite("Phase E: sửa quan hệ", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct RelationshipEditorTests {
    private func makeState() throws -> DocumentState {
        let workspace = try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6)))
        let state = DocumentState(workspace: workspace, fileName: "Nhom6_e.pbix")
        state.mode = .model
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        return state
    }

    private func number(_ state: DocumentState, _ expression: String) async throws -> Double {
        let result = try await state.workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))")
        switch result.tables.first?.rows.first?.first {
        case .integer(let i)?: return Double(i)
        case .double(let d)?: return d
        default: Issue.record("không phải số: \(expression)"); return .nan
        }
    }

    private func relationship(_ state: DocumentState, from: String, to: String) throws -> ModelMetadata.Relationship {
        try #require(state.workspace.metadata?.relationships.first { "\($0.fromTable)[\($0.fromColumn)]" == from && "\($0.toTable)[\($0.toColumn)]" == to })
    }

    /// Đổi hướng lọc sang hai chiều: số của truy vấn chạy sau khi sửa bằng đúng số của truy vấn viết tay có CROSSFILTER BOTH
    /// trên mô hình gốc; hoàn tác trả số cũ.
    @Test func huongLocHaiChieuKhopCrossfilterVietTay() async throws {
        let state = try makeState()
        let rel = try relationship(state, from: "Fact_Loan[client_key]", to: "Dim_Client[client_key]")
        let key = try await number(state, "MIN(Fact_Loan[loan_profile_key])")
        let query = "CALCULATE(COUNTROWS(Dim_Client), Fact_Loan[loan_profile_key] = \(Int(key)))"
        let single = try await number(state, query)
        let handwritten = try await number(state, "CALCULATE(COUNTROWS(Dim_Client), CROSSFILTER(Fact_Loan[client_key], Dim_Client[client_key], BOTH), Fact_Loan[loan_profile_key] = \(Int(key)))")
        #expect(handwritten != single, "truy vấn thử phải nhạy với hướng lọc")

        let t0 = Date()
        #expect(state.modelEditor.apply(.updateRelationship(name: rel.name, patch: RelationshipPatch(crossFilteringBehavior: 2))) == nil)
        let both = try await number(state, query)
        print("KEY S2 đổi hướng lọc + truy vấn đầu tiên (debug): \(String(format: "%.0f", Date().timeIntervalSince(t0) * 1000)) ms")
        #expect(both == handwritten)
        #expect(state.workspace.metadata?.relationships.first { $0.name == rel.name }?.crossFilteringBehavior == 2)
        state.layout.undo()
        #expect(try await number(state, query) == single)
    }

    /// Tắt quan hệ ngày: bộ lọc năm không còn tới bảng fact.
    @Test func tatQuanHeKhongConLanTruyen() async throws {
        let state = try makeState()
        let rel = try relationship(state, from: "Fact_Loan[loan_date_key]", to: "Dim_Date[date_key]")
        let filtered = "CALCULATE(COUNTROWS(Fact_Loan), Dim_Date[year] = 2013)"
        let total = try await number(state, "COUNTROWS(Fact_Loan)")
        let before = try await number(state, filtered)
        #expect(before < total)
        #expect(state.modelEditor.apply(.updateRelationship(name: rel.name, patch: RelationshipPatch(isActive: false))) == nil)
        #expect(try await number(state, filtered) == total)
        #expect(state.workspace.metadata?.relationships.first { $0.name == rel.name }?.isActive == false)
        state.layout.undo()
        #expect(try await number(state, filtered) == before)
    }

    @Test func quanHeSaiBiTuChoi() async throws {
        let state = try makeState()
        #expect(state.modelEditor.apply(.updateRelationship(name: "khong co", patch: RelationshipPatch(isActive: false))) != nil)
        #expect(state.modelEditor.apply(.updateRelationship(name: try relationship(state, from: "Fact_Loan[client_key]", to: "Dim_Client[client_key]").name,
                                                            patch: RelationshipPatch(crossFilteringBehavior: 9))) != nil)
        #expect(!state.layout.isDirty)
    }

    // MARK: Tạo và xoá quan hệ (T025, T026)

    /// Kéo cột thả cột → đề xuất → xác nhận → quan hệ vào mô hình và engine; lưu T2 (kèm chỉ mục), mở lại đọc đúng.
    /// Ghi `build/e-out/E2/Nhom6_e2.pbix` cho buổi kiểm Desktop.
    @Test func taoQuanHeBangKeoThaLuuMoLai() async throws {
        let dir = try EFixtures.outputDirectory("E2")
        let source = dir.appendingPathComponent("Nhom6_e2.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        let before = try #require(workspace.metadata).relationships.count

        // cột phía một thả lên cột trùng giá trị: Fact_Loan[loan_count] → Dim_Client[client_key] (như VM-E3), không hoạt động
        state.proposeRelationship(drag: .init(table: "Dim_Client", column: "client_key"), drop: .init(table: "Fact_Loan", column: "loan_count"))
        let draft = try #require(state.relationshipDraft, Comment(rawValue: state.relationshipNotice ?? ""))
        #expect(draft.forcedInactive && draft.relationship.fromTable == "Fact_Loan")
        state.confirmRelationshipDraft(crossFiltering: 1, isActive: true)
        #expect(state.relationshipNotice == nil && state.relationshipDraft == nil, Comment(rawValue: state.relationshipNotice ?? ""))
        let created = try #require(workspace.metadata?.relationships.first { $0.fromColumn == "loan_count" && $0.toTable == "Dim_Client" })
        #expect(!created.isActive && workspace.metadata?.relationships.count == before + 1 && state.relationship == created.name)
        // engine chạy với quan hệ mới (không hoạt động nên dùng USERELATIONSHIP được)
        let result = try await workspace.daxEngine().execute("EVALUATE ROW(\"v\", CALCULATE(COUNTROWS(Dim_Client), USERELATIONSHIP(Fact_Loan[loan_count], Dim_Client[client_key])))")
        #expect(result.tables.first?.rows.first?.first != nil)

        // lưu T2 và mở lại
        let t0 = Date()
        let outcome = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                             readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        print("KEY E2 lưu T2 có quan hệ mới (debug): \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        #expect(outcome.didWrite)
        let (abf, _) = try PBIXFile(url: source).loadDataModel()
        let reopened = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        #expect(reopened.relationships.contains { $0.name == created.name && !$0.isActive && $0.cardinality == "M:1" })
        let guid = created.name.replacingOccurrences(of: "-", with: " ")
        #expect(abf.files.filter { $0.path.contains(guid) }.count == 2)

        // xoá quan hệ rồi hoàn tác
        #expect(state.deleteRelationship(name: created.name) == nil)
        #expect(workspace.metadata?.relationships.contains { $0.name == created.name } == false)
        state.layout.undo()
        #expect(workspace.metadata?.relationships.contains { $0.name == created.name } == true)
    }

    @Test func keoThaSaiBiTuChoiKemLyDo() async throws {
        let state = try makeState()
        // cả hai cột trùng giá trị
        state.proposeRelationship(drag: .init(table: "Fact_Loan", column: "loan_count"), drop: .init(table: "Fact_Transaction", column: "trans_type_key"))
        #expect(state.relationshipDraft == nil && state.relationshipNotice?.contains("nhiều-nhiều") == true)
        // cả hai duy nhất
        state.proposeRelationship(drag: .init(table: "Dim_Client", column: "client_key"), drop: .init(table: "Dim_Account", column: "account_key"))
        #expect(state.relationshipDraft == nil && state.relationshipNotice?.contains("một-một") == true)
        // chế độ Xem
        state.mode = .report; state.editMode = false
        state.proposeRelationship(drag: .init(table: "Dim_Client", column: "client_key"), drop: .init(table: "Fact_Loan", column: "loan_count"))
        #expect(state.relationshipDraft == nil && state.relationshipNotice?.contains("Sửa") == true)
        #expect(!state.layout.isDirty)
    }

    /// Lưu, rồi thêm một quan hệ và xoá một quan hệ khác, lưu lần hai: cả hai thay đổi vào file (không rơi mất ở lần lưu thứ hai).
    @Test func luuLanHaiGhiThemVaXoaQuanHe() async throws {
        let dir = try EFixtures.outputDirectory("E2b")
        let source = dir.appendingPathComponent("Nhom6_e2b.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        func save() throws {
            _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                       readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        }
        func saved() throws -> ModelMetadata {
            let (abf, _) = try PBIXFile(url: source).loadDataModel()
            return try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        }
        let original = try #require(workspace.metadata).relationships
        // lần 1: đổi hướng lọc một quan hệ
        let first = try #require(original.first { $0.isActive && $0.crossFilteringBehavior == 1 })
        #expect(state.modelEditor.apply(.updateRelationship(name: first.name, patch: RelationshipPatch(crossFilteringBehavior: 2))) == nil)
        try save()
        // lần 2: thêm quan hệ mới và xoá quan hệ khác
        state.proposeRelationship(drag: .init(table: "Dim_Client", column: "client_key"), drop: .init(table: "Fact_Loan", column: "loan_count"))
        state.confirmRelationshipDraft(crossFiltering: 1, isActive: false)
        let created = try #require(workspace.metadata?.relationships.first { $0.fromColumn == "loan_count" })
        let victim = try #require(original.first { $0.fromTable == "Fact_Loan" && $0.fromColumn == "loan_profile_key" })
        #expect(state.deleteRelationship(name: victim.name) == nil)
        try save()
        let result = try saved()
        #expect(result.relationships.contains { $0.name == created.name } && !result.relationships.contains { $0.name == victim.name })
        #expect(result.relationships.first { $0.name == first.name }?.crossFilteringBehavior == 2)
        // lần 3 sau hoàn tác về trước lần thêm: quan hệ mới biến mất khỏi file
        state.layout.undo(); state.layout.undo()
        try save()
        let reverted = try saved()
        #expect(!reverted.relationships.contains { $0.name == created.name } && reverted.relationships.contains { $0.name == victim.name })
    }
}
