import Foundation
import Connectors
import DAXEngine
import MEngine
import PBIXKit
import Testing
@testable import BIPro

/// Phase F (VM-F8): truy vấn tắt "Enable load" lưu thành dòng `Expression` của file (M nguyên văn, như Desktop 2.159), mở lại thấy nó trong
/// Query Editor, xem trước bằng M thật từ tệp nguồn, bật lại thì thành bảng và dòng `Expression` mất. File Nhom6 thật, nguồn CSV mẫu.
@Suite("Phase F: truy vấn tắt Enable load", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct HiddenQueryTests {
    private func open(_ url: URL) throws -> DocumentState {
        DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
    }

    private func save(_ state: DocumentState, _ url: URL, _ backups: URL) throws {
        #expect(try DocumentSaver.save(editor: state.layout, source: url, to: url, expectedStamp: nil, readOnlyRoots: [], backupDirectory: backups).didWrite)
    }

    private func applyAndWait(_ state: DocumentState) async throws {
        let editor = try #require(state.queryEditorState)
        state.applyQueryEditor()
        for _ in 0..<800 where state.queryEditorState != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(editor.applyMessage == nil)
    }

    @Test func disableLoadSavesTheQueryAndEnableLoadBringsTheTableBack() async throws {
        let dir = try EFixtures.outputDirectory("../f-out/f8")
        let backups = dir.appendingPathComponent("Backups")
        let url = dir.appendingPathComponent("hidden.pbix")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: url)
        let csv = try #require(FFixtures.sample("sales_2026.csv"))

        // 1. Nạp CSV, giữ 500 dòng, lưu.
        let s1 = try open(url)
        s1.showGetData(kind: .csv, pickFile: { _ in csv.path })
        let navigator = try #require(s1.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for entry in navigator.items where entry.name == "sales_2026" { navigator.toggle(entry.id) }
        let loaded = try #require(await navigator.load(existingNames: s1.existingTableNames)).first.unsafelyUnwrapped
        s1.closeGetData()
        s1.showQueryEditor(loaded: [loaded])
        let e1 = try #require(s1.queryEditorState)
        #expect(e1.perform(.keepTopRows(500)) == .applied)
        try await applyAndWait(s1)
        try save(s1, url, backups)

        // 2. Mở lại, tắt Enable load, áp dụng, lưu: bảng mất, truy vấn thành dòng Expression.
        let s2 = try open(url)
        #expect(s2.workspace.rowCount("sales_2026") == 500)
        s2.showQueryEditor()
        let e2 = try #require(s2.queryEditorState)
        let id2 = try #require(e2.queries.first { $0.name == "sales_2026" }).id
        e2.setEnableLoad(id2, false)
        #expect(e2.hasUnappliedQueries)
        try await applyAndWait(s2)
        #expect(!s2.workspace.userTables.contains { $0.name == "sales_2026" })
        try save(s2, url, backups)

        // 3. Mở lại: Expression có M, truy vấn hiện trong editor (tắt nạp), xem trước đọc tệp nguồn thật.
        let s3 = try open(url)
        let metadata = try #require(s3.workspace.metadata)
        #expect(!metadata.userTables.contains { $0.name == "sales_2026" })
        #expect(metadata.expressions.contains("sales_2026"))
        #expect(metadata.expressionBodies["sales_2026"]?.contains("Csv.Document") == true)
        #expect(metadata.expressionBodies["sales_2026"]?.contains("Table.FirstN") == true)
        s3.showQueryEditor()
        let e3 = try #require(s3.queryEditorState)
        let hidden = try #require(e3.queries.first { $0.name == "sales_2026" })
        #expect(hidden.enableLoad == false)
        #expect(hidden.savedQueryName == "sales_2026")
        #expect(hidden.lockedStepCount == 0)
        #expect(e3.hasUnappliedQueries == false)
        e3.selectQuery(hidden.id)
        await e3.refresh()
        #expect(e3.errorMessage == nil)
        #expect(e3.preview != nil)
        let full = try await e3.evaluateFull(hidden)
        #expect(full.rowCount == 500)
        // DataFolder (tham số) vẫn nằm trong file, không vào danh sách truy vấn.
        #expect(metadata.expressions.contains("DataFolder"))
        #expect(!e3.queries.contains { $0.name == "DataFolder" })

        // 4. Bật lại Enable load: thành bảng 500 dòng, dòng Expression mất.
        e3.setEnableLoad(hidden.id, true)
        try await applyAndWait(s3)
        #expect(s3.workspace.rowCount("sales_2026") == 500)
        try save(s3, url, backups)
        let s4 = try open(url)
        #expect(s4.workspace.rowCount("sales_2026") == 500)
        #expect(s4.workspace.metadata?.expressions.contains("sales_2026") == false)
        #expect(s4.workspace.metadata?.expressions.contains("DataFolder") == true)
        print("KEY hidden query ok: \(url.path)")
    }

    private func number(_ result: QueryResult) -> Double? {
        switch result.tables.first?.rows.first?.first {
        case .integer(let i)?: Double(i)
        case .double(let d)?: d
        default: nil
        }
    }

    /// Thay dữ liệu bảng `Dim_Loan_Profile` (một vế của quan hệ Fact_Loan → Dim_Loan_Profile; bảng không có phân cấp và cột tính toán): chỉ mục quan hệ `R$` dựng lại theo bảng mới,
    /// quan hệ giữ tên và số lượng, lọc từ bảng thay lan sang bảng sự kiện đúng.
    @Test func replacingATableInARelationshipRebuildsTheIndex() async throws {
        let dir = try EFixtures.outputDirectory("../f-out/f8")
        let backups = dir.appendingPathComponent("Backups")
        let url = dir.appendingPathComponent("rel.pbix")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: url)
        let before = try open(url)
        let namesBefore = try #require(before.workspace.metadata).relationships.map(\.name).sorted()
        #expect(namesBefore.count == 14)
        let fullFacts = number(try await before.workspace.daxEngine().execute("EVALUATE ROW(\"x\", COUNTROWS(Fact_Loan))"))

        let s1 = try open(url)
        s1.showQueryEditor()
        let e1 = try #require(s1.queryEditorState)
        let query = try #require(e1.queries.first { $0.name == "Dim_Loan_Profile" })
        e1.selectQuery(query.id)
        for _ in 0..<400 where e1.preview == nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(e1.perform(.keepTopRows(5)) == .applied)
        try await applyAndWait(s1)
        #expect(s1.workspace.rowCount("Dim_Loan_Profile") == 5)
        try save(s1, url, backups)   // trước đây bị từ chối: bảng đang tham gia quan hệ

        let s2 = try open(url)
        #expect(s2.workspace.rowCount("Dim_Loan_Profile") == 5)
        let metadata = try #require(s2.workspace.metadata)
        #expect(metadata.relationships.map(\.name).sorted() == namesBefore)
        #expect(metadata.tables.filter { $0.name.hasPrefix("R$") }.count == 14)
        // Số dòng sự kiện nối được tới 5 dòng của bảng thay (đếm bằng quan hệ so với đếm trực tiếp theo khoá).
        let engine = try await s2.workspace.daxEngine()
        let keys = try await engine.execute("EVALUATE VALUES(Dim_Loan_Profile[loan_profile_key])")
        let keyList: [String] = (keys.tables.first?.rows ?? []).compactMap { row in
            switch row.first { case .integer(let i)?: "\(i)"; case .double(let d)?: "\(Int(d))"; default: nil }
        }
        #expect(keyList.count == 5)
        let direct = number(try await engine.execute("EVALUATE ROW(\"x\", COUNTROWS(FILTER(Fact_Loan, "
            + keyList.map { "Fact_Loan[loan_profile_key] = \($0)" }.joined(separator: " || ") + ")))"))
        // Lọc theo từng khoá của bảng thay: đếm qua quan hệ (chỉ mục R$ dựng lại) bằng đếm trực tiếp theo khoá.
        let perKey = try await keyList.asyncMap { key in
            number(try await engine.execute("EVALUATE ROW(\"x\", CALCULATE(COUNTROWS(Fact_Loan), Dim_Loan_Profile[loan_profile_key] = \(key)))"))
        }
        let directPerKey = try await keyList.asyncMap { key in
            number(try await engine.execute("EVALUATE ROW(\"x\", COUNTROWS(FILTER(Fact_Loan, Fact_Loan[loan_profile_key] = \(key))))"))
        }
        #expect(perKey == directPerKey)
        #expect(perKey.compactMap { $0 }.reduce(0, +) == direct)
        #expect((direct ?? 0) > 0 && (direct ?? 0) < (fullFacts ?? 0))
        print("KEY relationship rebuilt: \(url.path)")
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for element in self { out.append(try await transform(element)) }
        return out
    }
}
