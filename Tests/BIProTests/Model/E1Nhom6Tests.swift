// Test nặng Phase E trên Nhom6 thật: BIPRO_HEAVY=1 (tên có "E1Nhom6"). File Nhom6: BIPRO_NHOM6 hoặc ~/Downloads/bipro-golden/Nhom6_work.pbix.
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase E: E1Nhom6", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct E1Nhom6Tests {
    private func number(_ value: Value?) -> Double? {
        switch value {
        case .integer(let i)?: Double(i)
        case .double(let d)?: d
        case .currency(let c)?: Double(c) / 10_000
        default: nil
        }
    }

    private func scalar(_ workspace: Workspace, _ expression: String) async throws -> Double {
        let result = try await workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))")
        return try #require(number(result.tables.first?.rows.first?.first), Comment(rawValue: expression))
    }

    /// Thêm hai measure (một viết tay, một chép biểu thức của measure có sẵn), số khớp DAX viết tay, lưu T2, mở lại: số vẫn khớp.
    /// Ghi `build/e-out/E1/Nhom6_e1.pbix` cho buổi kiểm Desktop.
    @Test func themMeasureSoKhopDAXVietTayLuuMoLai() async throws {
        let dir = try EFixtures.outputDirectory("E1")
        let source = dir.appendingPathComponent("Nhom6_e1.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .table
        let model = try #require(workspace.metadata)

        // (a) measure viết tay
        let t0 = Date()
        state.beginNewMeasure(table: "Fact_Loan")
        state.measureDraft?.text = "E_Loan Amount = SUM(Fact_Loan[loan_amount])"
        await state.applyMeasureDraft()
        let applySeconds = Date().timeIntervalSince(t0)
        #expect(state.measureDraft?.message == nil, Comment(rawValue: state.measureDraft?.message ?? ""))
        print("KEY E1 áp dụng measure (kiểm + suy kiểu + vào mô hình): \(String(format: "%.0f", applySeconds * 1000)) ms")
        let hand = try await scalar(workspace, "SUM(Fact_Loan[loan_amount])")
        #expect(try await scalar(workspace, "[E_Loan Amount]") == hand)

        // (b) chép biểu thức của một measure có sẵn (CALCULATE, quan hệ) dưới tên mới
        let original = try #require(model.measures.first { $0.tableName == "Fact_Transaction" && $0.name == "Net_Cashflow" }
                                    ?? model.measures.first { $0.tableName == "Fact_Transaction" && !$0.expression.contains("SELECTEDMEASURE") })
        state.beginNewMeasure(table: original.tableName)
        state.measureDraft?.text = MeasureFormula.format(name: "E_Copy", expression: original.expression)
        await state.applyMeasureDraft()
        #expect(state.measureDraft?.message == nil, Comment(rawValue: state.measureDraft?.message ?? ""))
        #expect(try await scalar(workspace, "[E_Copy]") == scalar(workspace, "[\(original.name)]"))
        #expect(state.updateMeasure(table: original.tableName, name: "E_Copy",
                                    patch: MeasurePatch(displayFolder: .set("Thu muc E"), description: .set("mo ta E"))) == nil)

        // lưu T2 (đường D1: dựng, kiểm, ghi tạm, thay)
        let t1 = Date()
        let outcome = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                             readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        print("KEY E1 lưu T2 qua DocumentSaver (debug): \(String(format: "%.2f", Date().timeIntervalSince(t1))) s")
        #expect(outcome.didWrite && !state.layout.isDirty)

        // mở lại từ file đã lưu
        let reopened = try Workspace(data: Data(contentsOf: source))
        let loan = try #require(reopened.measure(table: "Fact_Loan", name: "E_Loan Amount"))
        #expect(loan.expression == "SUM(Fact_Loan[loan_amount])" && loan.dataType != .variant)
        let copy = try #require(reopened.measure(table: original.tableName, name: "E_Copy"))
        #expect(copy.displayFolder == "Thu muc E" && copy.description == "mo ta E" && copy.expression == original.expression)
        #expect(try await scalar(reopened, "[E_Loan Amount]") == hand)
        #expect(try await scalar(reopened, "[E_Copy]") == scalar(reopened, "[\(original.name)]"))
        // mọi measure cũ còn nguyên
        #expect(reopened.metadata?.measures.count == model.measures.count + 2)
        #expect(reopened.metadata?.relationships == model.relationships)
    }
}
