import CoreGraphics
import Foundation
import Connectors
import MEngine
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

    /// Gate F-Query (T066): bốn file Nhom6 do BI Pro lưu có truy vấn M với đường dẫn Windows `C:\\Users\\bacpew\\f6\\...`: (1) bảng CSV + bước giữ 500 dòng,
    /// (2) bảng Excel + sắp xếp + giữ 50 dòng, (3) như (1) rồi sửa truy vấn (giữ 20 dòng) và lưu lần hai (thay bảng), (4) như (1) rồi tắt
    /// Enable load (xoá bảng). Ghi ra `build/f-out/f6/`. Mở trong Desktop theo `docs/phase-f-evidence/vm-f3/CHECKLIST-F6.md`.
    @Test func taoFileGateTruyVan() async throws {
        let dir = try EFixtures.outputDirectory("../f-out/f6")
        let backups = dir.appendingPathComponent("Backups")
        let windowsRoot = #"C:\Users\bacpew\f6\"#
        func fresh(_ name: String) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: url)
            return url
        }
        func open(_ url: URL) throws -> DocumentState {
            DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        }
        func save(_ state: DocumentState, _ url: URL) throws {
            #expect(try DocumentSaver.save(editor: state.layout, source: url, to: url, expectedStamp: nil, readOnlyRoots: [], backupDirectory: backups).didWrite)
        }
        /// Nạp thật từ file mẫu trên Mac nhưng ghi nguồn là đường dẫn Windows để Desktop Refresh được sau khi chép file sang VM.
        func load(_ state: DocumentState, kind: SourceKind, file: String, item: String) async throws -> LoadedTable {
            let url = try #require(FFixtures.sample(file))
            state.showGetData(kind: kind, pickFile: { _ in url.path })
            let navigator = try #require(state.getDataState)
            for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
            for entry in navigator.items where entry.name == item { navigator.toggle(entry.id) }
            let loaded = try #require(await navigator.load(existingNames: state.existingTableNames)).first.unsafelyUnwrapped
            state.closeGetData()
            let origin = try #require(loaded.origin)
            return LoadedTable(name: loaded.name, data: loaded.data,
                               origin: LoadedOrigin(kind: kind, location: windowsRoot + file, itemName: origin.itemName, itemKind: origin.itemKind))
        }
        func apply(_ state: DocumentState, _ table: LoadedTable, steps: [StepCommand]) async throws {
            state.showQueryEditor(loaded: [table])
            let editor = try #require(state.queryEditorState)
            for step in steps { #expect(editor.perform(step) == .applied) }
            state.applyQueryEditor()
            for _ in 0..<400 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
            #expect(editor.applyMessage == nil)
        }

        // (1) CSV + giữ 500 dòng
        let q1 = try fresh("q1-csv.pbix")
        let s1 = try open(q1)
        try await apply(s1, try await load(s1, kind: .csv, file: "sales_2026.csv", item: "sales_2026"), steps: [.keepTopRows(500)])
        #expect(s1.workspace.rowCount("sales_2026") == 500)
        try save(s1, q1)

        // (2) Excel Sales + sắp xếp giảm dần Qty + giữ 50 dòng
        let q2 = try fresh("q2-excel.pbix")
        let s2 = try open(q2)
        try await apply(s2, try await load(s2, kind: .excel, file: "sales_2026.xlsx", item: "Sales"),
                        steps: [.sortRows([SortKey(column: "Qty", descending: true)]), .keepTopRows(50)])
        try save(s2, q2)

        // (3) q1 → mở lại → giữ 20 dòng → thay bảng → lưu
        let q3 = try fresh("q3-thay.pbix")
        try FileManager.default.removeItem(at: q3)
        try FileManager.default.copyItem(at: q1, to: q3)
        let s3 = try open(q3)
        s3.showQueryEditor()
        let e3 = try #require(s3.queryEditorState)
        e3.selectQuery(try #require(e3.queries.first { $0.loadedTableName == "sales_2026" }).id)
        #expect(e3.perform(.keepTopRows(20)) == .applied)
        s3.applyQueryEditor()
        for _ in 0..<400 where s3.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(s3.workspace.rowCount("sales_2026") == 20)
        try save(s3, q3)

        // (4) q1 → tắt Enable load → xoá bảng → lưu
        let q4 = try fresh("q4-xoa.pbix")
        try FileManager.default.removeItem(at: q4)
        try FileManager.default.copyItem(at: q1, to: q4)
        let s4 = try open(q4)
        s4.showQueryEditor()
        let e4 = try #require(s4.queryEditorState)
        e4.setEnableLoad(try #require(e4.queries.first { $0.loadedTableName == "sales_2026" }).id, false)
        s4.applyQueryEditor()
        for _ in 0..<400 where s4.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        try save(s4, q4)
        #expect(try !open(q4).workspace.userTables.contains { $0.name == "sales_2026" })
        print("KEY F6 file gate: \(dir.path)")
    }

    /// Gate VM-F8 (2026-11-16): ba file Nhom6 do BI Pro lưu, đường dẫn nguồn là `C:\\Users\\bacpew\\f6\\` (Desktop Refresh được sau khi chép sang VM):
    /// (g1) `sales_2026` đã tắt Enable load (lưu thành dòng `Expression`), (g2) thay dữ liệu bảng `Dim_Loan_Profile` đang trong quan hệ (chỉ mục `R$` dựng
    /// lại), (g3) T074: ba truy vấn có Merge + mở rộng, Append (tham chiếu truy vấn khác) và Group By. Ghi ra `build/f-out/f8/`.
    @Test func taoFileGateF8() async throws {
        let dir = try EFixtures.outputDirectory("../f-out/f8")
        let backups = dir.appendingPathComponent("Backups")
        let windowsRoot = #"C:\Users\bacpew\f6\"#
        func fresh(_ name: String) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: url)
            return url
        }
        func open(_ url: URL) throws -> DocumentState {
            DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        }
        func save(_ state: DocumentState, _ url: URL) throws {
            #expect(try DocumentSaver.save(editor: state.layout, source: url, to: url, expectedStamp: nil, readOnlyRoots: [], backupDirectory: backups).didWrite)
        }
        func load(_ state: DocumentState, file: String, item: String) async throws -> LoadedTable {
            let url = try #require(FFixtures.sample(file))
            state.showGetData(kind: .csv, pickFile: { _ in url.path })
            let navigator = try #require(state.getDataState)
            for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
            for entry in navigator.items where entry.name == item { navigator.toggle(entry.id) }
            let loaded = try #require(await navigator.load(existingNames: state.existingTableNames)).first.unsafelyUnwrapped
            state.closeGetData()
            let origin = try #require(loaded.origin)
            return LoadedTable(name: loaded.name, data: loaded.data,
                               origin: LoadedOrigin(kind: .csv, location: windowsRoot + file, itemName: origin.itemName, itemKind: origin.itemKind))
        }
        func applyAndWait(_ state: DocumentState) async throws {
            let editor = try #require(state.queryEditorState)
            state.applyQueryEditor()
            for _ in 0..<800 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
            #expect(editor.applyMessage == nil)
        }
        func loadAndApply(_ state: DocumentState, file: String, item: String, steps: [StepCommand] = []) async throws {
            state.showQueryEditor(loaded: [try await load(state, file: file, item: item)])
            let editor = try #require(state.queryEditorState)
            for step in steps { #expect(editor.perform(step) == .applied) }
            try await applyAndWait(state)
        }
        func select(_ editor: QueryEditorState, _ name: String) async throws {
            let query = try #require(editor.queries.first { $0.name == name })
            editor.selectQuery(query.id)
            for _ in 0..<400 where editor.preview == nil { try await Task.sleep(for: .milliseconds(25)) }
        }

        // (g1) CSV giữ 500 dòng, lưu; mở lại, tắt Enable load, lưu.
        let g1 = try fresh("g1-hidden.pbix")
        let s1 = try open(g1)
        try await loadAndApply(s1, file: "sales_2026.csv", item: "sales_2026", steps: [.keepTopRows(500)])
        try save(s1, g1)
        let s1b = try open(g1)
        s1b.showQueryEditor()
        let e1 = try #require(s1b.queryEditorState)
        e1.setEnableLoad(try #require(e1.queries.first { $0.name == "sales_2026" }).id, false)
        try await applyAndWait(s1b)
        try save(s1b, g1)
        #expect(try open(g1).workspace.metadata?.expressions.contains("sales_2026") == true)

        // (g2) thay dữ liệu Dim_Loan_Profile (còn 5 dòng), bảng nằm trong quan hệ Fact_Loan → Dim_Loan_Profile.
        let g2 = try fresh("g2-rel.pbix")
        let s2 = try open(g2)
        s2.showQueryEditor()
        let e2 = try #require(s2.queryEditorState)
        try await select(e2, "Dim_Loan_Profile")
        #expect(e2.perform(.keepTopRows(5)) == .applied)
        try await applyAndWait(s2)
        try save(s2, g2)

        // (g3) T074: Merge + mở rộng, Append (tham chiếu truy vấn khác), Group By.
        let g3 = try fresh("g3-merge.pbix")
        let s3 = try open(g3)
        // Test viết trước khi có tự phát hiện quan hệ (T035): quan hệ tự tạo sales_2026 (3) → customers chặn Group By bỏ CustomerID.
        // Desktop xử lý thế nào khi cột của quan hệ tự tạo mất đi chưa quan sát (tồn đọng), nên tắt tuỳ chọn để giữ ý test.
        s3.layout.setAutodetectRelationships(false)
        try await loadAndApply(s3, file: "sales_2026.csv", item: "sales_2026")
        try await loadAndApply(s3, file: "customers.csv", item: "customers")
        try await loadAndApply(s3, file: "sales_2026.csv", item: "sales_2026")
        try await loadAndApply(s3, file: "sales_2026.csv", item: "sales_2026")
        s3.showQueryEditor()
        let e3 = try #require(s3.queryEditorState)
        print("KEY f8 queries: \(e3.queries.map(\.name))")
        try await select(e3, "sales_2026")
        #expect(e3.perform(.keepTopRows(300)) == .applied)
        #expect(e3.perform(.merge(otherQuery: "customers", leftKeys: ["CustomerID"], rightKeys: ["CustomerID"], kind: .leftOuter, newColumn: "customers")) == .applied)
        #expect(e3.perform(.expandColumn(column: "customers", names: ["Name", "Segment"], prefixed: true)) == .applied)
        try await select(e3, "sales_2026 (2)")
        #expect(e3.perform(.keepTopRows(100)) == .applied)
        #expect(e3.perform(.append(queries: ["sales_2026"])) == .applied)
        try await select(e3, "sales_2026 (3)")
        #expect(e3.perform(.groupBy(keys: ["Region"], aggregates: [GroupAggregate(name: "Orders", operation: .countRows),
                                                                    GroupAggregate(name: "TotalQty", operation: .sum, column: "Qty")])) == .applied)
        try await applyAndWait(s3)
        #expect(s3.workspace.rowCount("sales_2026") == 300)
        #expect(s3.workspace.rowCount("sales_2026 (2)") == 400)
        try save(s3, g3)
        let reopened = try open(g3)
        print("KEY f8 rows: sales_2026=\(reopened.workspace.rowCount("sales_2026")) (2)=\(reopened.workspace.rowCount("sales_2026 (2)")) (3)=\(reopened.workspace.rowCount("sales_2026 (3)"))")
        print("KEY F8 file gate: \(dir.path)")
    }

    /// Gate F-Query (T066, phần b): file `q1-desktop.pbix` do Desktop 2.159 lưu lại sau khi thêm bước "Reordered Columns" (Close & Apply, Refresh
    /// bảng, lưu) mở được trong BI Pro: truy vấn `sales_2026` đủ 5 bước đúng tên và M, bảng còn 500 dòng, 11 bảng cũ còn đủ.
    @Test func moFileDoDesktopLuuLai() async throws {
        let url = try EFixtures.outputDirectory("../f-out/f6").appendingPathComponent("q1-desktop.pbix")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        #expect(state.workspace.rowCount("sales_2026") == 500)
        #expect(state.workspace.userTables.count == 12)
        state.showQueryEditor()
        let editor = try #require(state.queryEditorState)
        let query = try #require(editor.queries.first { $0.name == "sales_2026" })
        #expect(query.steps.map(\.name) == ["Source", "Promoted Headers", "Changed Type", "Kept First Rows", "Reordered Columns"])
        #expect(query.steps[3].expression == #"Table.FirstN(#"Changed Type",500)"#)
        #expect(query.steps[4].expression.hasPrefix(#"Table.ReorderColumns(#"Kept First Rows",{"OrderID", "OrderDate", "Region", "Price""#))
        print("KEY Desktop step: \(query.steps[4].expression)")
    }
}
