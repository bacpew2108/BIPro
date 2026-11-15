import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T025): đề xuất quan hệ khi kéo cột này thả lên cột kia ở Model view (quy tắc dò theo hộp thoại New relationship của
/// Desktop, VM-E3). Dùng metadata Nhom6 thật; tính duy nhất do test cho sẵn.
@Suite("Phase E: RelationshipDraft", .enabled(if: EFixtures.metadata != nil)) struct RelationshipDraftTests {
    let model = EFixtures.metadata!
    typealias C = RelationshipDraft.ColumnRef

    /// Cột duy nhất trong Nhom6: khoá của các bảng chiều và `loan_key`.
    func unique(_ c: C) -> Bool { ["client_key", "account_key", "date_key", "district_key", "loan_key"].contains(c.column) && c.table.hasPrefix(c.column == "loan_key" ? "Fact_Loan" : "Dim_") }

    private func propose(_ a: C, _ b: C) -> Result<RelationshipDraft, RelationshipDraft.Refusal> {
        RelationshipDraft.propose(model: model, drag: a, drop: b, isUnique: unique)
    }

    @Test func motMotNhieuTuDongDatPhiaNhieuLamTu() throws {
        // kéo cột duy nhất (Dim_Client.client_key) thả lên cột trùng (Fact_Loan.loan_count): từ = phía nhiều
        let draft = try propose(C(table: "Dim_Client", column: "client_key"), C(table: "Fact_Loan", column: "loan_count")).get()
        let r = draft.relationship
        #expect(r.fromTable == "Fact_Loan" && r.fromColumn == "loan_count" && r.toTable == "Dim_Client" && r.toColumn == "client_key")
        #expect(r.fromMany && !r.toMany && r.crossFilteringBehavior == 1)
        // đã có quan hệ hoạt động giữa hai bảng → không hoạt động (VM-E3)
        #expect(!r.isActive && draft.forcedInactive && draft.notes.contains { $0.contains("không hoạt động") })
        #expect(UUIDString(r.name))
    }

    @Test func thaTheoChieuNguocLaiCungKetQua() throws {
        let a = try propose(C(table: "Fact_Loan", column: "loan_count"), C(table: "Dim_Client", column: "client_key")).get().relationship
        #expect(a.fromTable == "Fact_Loan" && a.toTable == "Dim_Client")
    }

    @Test func haiBangDaNoiQuaDuongKhacThiKhongHoatDong() throws {
        // Fact_Loan và Dim_Trans_Type chưa có quan hệ trực tiếp nhưng đã nối qua Dim_Date, Fact_Transaction...
        let custom: (C) -> Bool = { c in self.unique(c) || (c.table == "Dim_Trans_Type" && c.column == "trans_type_key") }
        let draft = try RelationshipDraft.propose(model: model, drag: C(table: "Fact_Loan", column: "loan_count"),
                                                  drop: C(table: "Dim_Trans_Type", column: "trans_type_key"), isUnique: custom).get()
        #expect(!draft.relationship.isActive && draft.forcedInactive && draft.notes.contains { $0.contains("mơ hồ") })
    }

    @Test func haiBangChuaNoiVoiNhauThiHoatDong() throws {
        // Tách Dim_Trans_Type khỏi mô hình (xoá các quan hệ của nó): quan hệ mới thành hoạt động.
        let isolated = try model.applying(ModelEdits(model.relationships.filter { $0.toTable == "Dim_Trans_Type" || $0.fromTable == "Dim_Trans_Type" }
            .map { .deleteRelationship(name: $0.name) }))
        let custom: (C) -> Bool = { c in self.unique(c) || (c.table == "Dim_Trans_Type" && c.column == "trans_type_key") }
        let draft = try RelationshipDraft.propose(model: isolated, drag: C(table: "Fact_Loan", column: "loan_count"),
                                                  drop: C(table: "Dim_Trans_Type", column: "trans_type_key"), isUnique: custom).get()
        #expect(draft.relationship.isActive && !draft.forcedInactive && draft.notes.isEmpty)
    }

    @Test func tuChoi() {
        func reason(_ r: Result<RelationshipDraft, RelationshipDraft.Refusal>) -> String? {
            if case .failure(let f) = r { return f.reason }
            return nil
        }
        #expect(reason(propose(C(table: "Dim_Client", column: "client_key"), C(table: "Dim_Client", column: "client_id")))?.contains("hai bảng khác nhau") == true)
        #expect(reason(propose(C(table: "Dim_Client", column: "client_key"), C(table: "Dim_Account", column: "account_id")))?.contains("kiểu") == true
                || reason(propose(C(table: "Dim_Client", column: "client_key"), C(table: "Dim_Account", column: "account_id"))) != nil)
        // cả hai duy nhất: một-một chưa hỗ trợ
        #expect(reason(propose(C(table: "Dim_Client", column: "client_key"), C(table: "Dim_Account", column: "account_key")))?.contains("một-một") == true)
        // cả hai không duy nhất: nhiều-nhiều
        #expect(reason(propose(C(table: "Fact_Loan", column: "loan_count"), C(table: "Fact_Transaction", column: "trans_type_key")))?.contains("nhiều-nhiều") == true)
        // đã có quan hệ nối đúng hai cột
        #expect(reason(propose(C(table: "Dim_Client", column: "client_key"), C(table: "Fact_Loan", column: "client_key")))?.contains("Đã có quan hệ") == true)
        // cột không có
        #expect(reason(propose(C(table: "Dim_Client", column: "khong co"), C(table: "Fact_Loan", column: "loan_count"))) != nil)
    }

    private func UUIDString(_ s: String) -> Bool { UUID(uuidString: s) != nil && s == s.lowercased() }
}
