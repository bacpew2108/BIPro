// Phase F, T089 (US7): nạp Parquet như Desktop. Golden: `docs/phase-f-evidence/vm-f7/f7-desktop.pbix` do Desktop 2.159 lưu sau khi nạp
// `sales_2026.parquet` và `types_snappy.parquet` (VM-F7a): văn bản M, kiểu cột mô hình và từng dòng đã nén VertiPaq. Thiếu tệp thì bỏ qua.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite struct ParquetGoldenTests {
    private static let goldenURL = FFixtures.root.appendingPathComponent("docs/phase-f-evidence/vm-f7/f7-desktop.pbix")

    /// Workspace của tệp golden; `nil` chỉ khi tệp không có (có mà không mở được thì ném).
    private static func golden() throws -> Workspace? {
        guard FileManager.default.fileExists(atPath: goldenURL.path) else { return nil }
        return try Workspace(data: Data(contentsOf: goldenURL))
    }

    private func squeeze(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    private func loaded(_ sample: String) async throws -> LoadedTable? {
        guard let url = FFixtures.sample(sample) else { return nil }
        let state = NavigatorState()
        await state.openSource(kind: .parquet, location: url.path)
        #expect(state.phase == .ready)
        let id = try #require(state.items.first?.id)
        state.toggle(id)
        return try #require(await state.load()?.first)
    }

    /// Bảng đã nạp khớp bảng Desktop lưu: tên và kiểu cột mô hình, số dòng, từng ô sau khi xếp theo cột đầu (khoá duy nhất; VertiPaq không giữ
    /// thứ tự dòng). Ngày giờ so với dung sai 1/300 giây: Desktop lưu timestamp µs với độ phân giải khoảng 1/300 s (QUAN-SAT VM-F7a), BI Pro giữ µs.
    private func expectMatchesDesktop(_ table: LoadedTable, desktopName: String, golden: Workspace) throws {
        let model = try #require(golden.metadata)
        let engine = try golden.daxEngine()
        let columns = model.columns.filter { $0.tableName == desktopName && $0.kind == .data }
        #expect(table.data.columns.map(\.name) == columns.map(\.name))
        #expect(table.data.columns.map { TableLoader.modelType($0.data.type) } == columns.map(\.dataType))
        let rows = try engine.store.rowCount(try #require(engine.store.schema.column(table: desktopName, name: columns[0].name)?.id).table)
        #expect(table.data.rowCount == rows)
        var desktop = Array(repeating: [StoredValue](), count: rows)
        for column in columns {
            let stored = try engine.store.column(try #require(engine.store.schema.column(table: desktopName, name: column.name)?.id))
            for row in 0..<rows { desktop[row].append(stored.value(at: row)) }
        }
        let ours = (0..<table.data.rowCount).map { row in table.data.columns.map { $0.data.value(at: row) } }
        func key(_ r: [StoredValue]) -> Int64 { if case .integer(let v) = r[0] { v } else { .min } }
        let tick = 1.0 / (86_400 * 300) + 1e-12
        var mismatches: [String] = []
        for (a, b) in zip(ours.sorted { key($0) < key($1) }, desktop.sorted { key($0) < key($1) }) {
            for (x, y) in zip(a, b) where x != y {
                if case .dateTime(let u) = x, case .dateTime(let v) = y, abs(u - v) <= tick { continue }
                mismatches.append("\(a[0]): \(x) ≠ \(y)")
            }
        }
        #expect(mismatches.isEmpty, Comment(rawValue: "\(mismatches.count) ô lệch, ví dụ \(mismatches.prefix(4))"))
    }

    @Test func salesKhopDesktop() async throws {
        guard let golden = try Self.golden(), let table = try await loaded("sales_2026.parquet"),
              let url = FFixtures.sample("sales_2026.parquet") else { return }
        #expect(table.name == "sales_2026")
        #expect(table.initialSteps.map(\.name) == ["Source"])
        let desktopM = try #require(golden.metadata?.partitionQueries["sales_2026"])
            .replacingOccurrences(of: #""C:\Users\bacpew\f7\sales_2026.parquet ""#, with: StepFactory.quote(url.path))
        #expect(squeeze(try #require(table.queryDefinition)) == squeeze(desktopM))
        try expectMatchesDesktop(table, desktopName: "sales_2026", golden: golden)
    }

    @Test func nhieuKieuKhopDesktop() async throws {
        guard let golden = try Self.golden(), let table = try await loaded("parquet/types_snappy.parquet") else { return }
        try expectMatchesDesktop(table, desktopName: "types_snappy", golden: golden)
    }

    /// `Parquet.Document` trong M (Refresh, truy vấn sửa tay) cho cùng bảng với Get Data.
    @Test func parquetDocumentTrongM() async throws {
        guard let url = FFixtures.sample("sales_2026.parquet") else { return }
        let source = "Parquet.Document(File.Contents(\(StepFactory.quote(url.path))), [Compression=null, LegacyColumnNameEncoding=false, MaxDepth=null])"
        let value = try await MEvaluator(environment: MEnvironment(bindings: SourceFunctions.bindings)).evaluate(source: source)
        guard case .table(let t) = value else { Issue.record("không ra bảng"); return }
        #expect(t.rowCount == 10_000 && t.columns.count == 8)
    }
}
