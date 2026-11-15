import CoreGraphics
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Gate Desktop sau Phase E: một file Nhom6 do BI Pro lưu với (A) tab bố cục mới đã đổi tên có một bảng, (B) quan hệ hoạt động
/// do BI Pro tạo (xoá quan hệ cũ rồi kéo lại), (C) tổng hợp mặc định và cột sắp xếp theo. Mở file trong Power BI Desktop theo
/// `docs/phase-e-evidence/vm-e6/CHECKLIST.md`. Ghi ra `build/f-out/Nhom6_f2.pbix`.
@Suite("Gate Desktop VM-E6", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct FGateTests {
    @Test func taoFileGateDesktop() throws {
        let dir = try EFixtures.outputDirectory("../f-out")
        let source = dir.appendingPathComponent("Nhom6_f2.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }

        // (A) tab bố cục
        state.addDiagramTab()
        state.addTableToCurrentDiagram("Fact_Loan", frames: [:])
        state.addTableToCurrentDiagram("Dim_Client", frames: ["Fact_Loan": CGRect(x: 40, y: 40, width: 234, height: 300)])
        #expect(state.renameDiagramTab("Layout 1", to: "Vay von") == nil)

        // (B) quan hệ hoạt động: bỏ quan hệ Fact_Loan.loan_profile_key → Dim_Loan_Profile rồi tạo lại bằng kéo thả
        let victim = try #require(workspace.metadata?.relationships.first { $0.fromTable == "Fact_Loan" && $0.fromColumn == "loan_profile_key" })
        #expect(state.deleteRelationship(name: victim.name) == nil)
        state.proposeRelationship(drag: .init(table: "Fact_Loan", column: "loan_profile_key"), drop: .init(table: victim.toTable, column: victim.toColumn))
        let draft = try #require(state.relationshipDraft, Comment(rawValue: state.relationshipNotice ?? ""))
        #expect(!draft.forcedInactive)
        state.confirmRelationshipDraft(crossFiltering: 1, isActive: true)
        let created = try #require(workspace.metadata?.relationships.first { $0.fromTable == "Fact_Loan" && $0.fromColumn == "loan_profile_key" })
        #expect(created.isActive && created.name != victim.name)

        // (C) cột
        #expect(state.updateColumn(table: "Fact_Loan", name: "loan_amount", patch: ColumnPatch(summarizeBy: 7)) == nil)           // Average
        #expect(state.updateColumn(table: "Fact_Loan", name: "loan_count", patch: ColumnPatch(summarizeBy: 5)) == nil)            // Max
        #expect(state.updateColumn(table: "Dim_Client", name: "age_group_current", patch: ColumnPatch(sortBy: .set("age_group_order"))) == nil)

        _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        let diagrams = try #require(PBIXFile(url: source).loadDiagramLayout()).diagrams
        #expect(diagrams.last?.name == "Vay von" && Set(diagrams.last?.nodes.map(\.table) ?? []) == ["Fact_Loan", "Dim_Client"])
        print("KEY F2 file gate: \(source.path)")
    }

    /// Quan sát VM-E7: file có ba tab (Layout 1..3) để xoá, đổi thứ tự và gỡ bảng khỏi tab trong Desktop. Ghi `build/f-out/Nhom6_f3.pbix`.
    @Test func taoFileQuanSatTab() throws {
        let dir = try EFixtures.outputDirectory("../f-out")
        let source = dir.appendingPathComponent("Nhom6_f3.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        let plan: [(String, [String])] = [("Layout 1", ["Fact_Loan", "Dim_Client"]), ("Layout 2", ["Dim_Client", "Dim_Loan_Profile"]), ("Layout 3", ["Fact_Loan"])]
        for (_, tables) in plan {
            state.addDiagramTab()
            var frames: [String: CGRect] = [:]
            for (i, t) in tables.enumerated() {
                state.addTableToCurrentDiagram(t, frames: frames)
                frames[t] = CGRect(x: 40 + 300 * CGFloat(i), y: 40, width: 234, height: 300)
            }
        }
        _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        print("KEY F3 file: \(source.path)")
    }

    /// Gate Desktop VM-E7: từ file ba tab (f3) BI Pro xoá "Layout 2", gỡ Fact_Loan khỏi "Layout 1" và kéo Dim_Client; lưu `build/f-out/Nhom6_f4.pbix`.
    @Test func taoFileGateXoaTab() throws {
        let dir = try EFixtures.outputDirectory("../f-out")
        let f3 = dir.appendingPathComponent("Nhom6_f3.pbix")
        let target = dir.appendingPathComponent("Nhom6_f4.pbix")
        try #require(FileManager.default.fileExists(atPath: f3.path), "chạy taoFileQuanSatTab trước")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: f3, to: target)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: target)), fileName: target.lastPathComponent, fileURL: target)
        state.mode = .model
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        state.selectDiagram("Layout 1")
        state.removeTableFromCurrentDiagram("Fact_Loan")
        state.moveCard(table: "Dim_Client", to: CGPoint(x: 500, y: 300))
        #expect(state.deleteDiagramTab("Layout 2") == nil)
        _ = try DocumentSaver.save(editor: state.layout, source: target, to: target, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        let diagrams = try #require(PBIXFile(url: target).loadDiagramLayout()).diagrams
        #expect(diagrams.map(\.name) == ["All tables", "Layout 1", "Layout 3"] && diagrams[1].nodes.map(\.table) == ["Dim_Client"])
        print("KEY F4 file gate: \(target.path)")
    }
}
