// Phase F, T088 (US7): nạp JSON lồng như Desktop. Golden: `docs/phase-f-evidence/vm-f7/f7-desktop.pbix` do Desktop 2.159 lưu sau khi nạp
// `orders.json` (VM-F7a, QUAN-SAT.md): văn bản M của truy vấn, kiểu cột và 203 dòng đã nén VertiPaq. Thiếu tệp mẫu hoặc golden thì bỏ qua.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite struct JsonGoldenTests {
    private static let goldenURL = FFixtures.root.appendingPathComponent("docs/phase-f-evidence/vm-f7/f7-desktop.pbix")
    /// Workspace của tệp golden; `nil` chỉ khi tệp không có (có mà không mở được thì ném, để test không âm thầm bỏ qua).
    private static func golden() throws -> Workspace? {
        guard FileManager.default.fileExists(atPath: goldenURL.path) else { return nil }
        return try Workspace(data: Data(contentsOf: goldenURL))
    }

    private func squeeze(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// Desktop ghi đường dẫn Windows của buổi VM; thay bằng đường dẫn tệp mẫu trên máy này.
    private func desktopQuery(_ golden: Workspace, table: String, localPath: String) throws -> String {
        let text = try #require(golden.metadata?.partitionQueries[table])
        return text.replacingOccurrences(of: #""C:\Users\Bacpew\f7\orders.json""#, with: StepFactory.quote(localPath))
    }

    @Test func getDataJsonMoThangQueryEditorVoiCacBuocNhuDesktop() async throws {
        guard let url = FFixtures.sample("orders.json"), let golden = try Self.golden() else { return }
        let state = NavigatorState()
        await state.openSource(kind: .json, location: url.path)
        #expect(state.opensEditorDirectly)
        let tables = try #require(await state.loadDirectly())
        let loaded = try #require(tables.first)
        #expect(loaded.name == "orders")
        #expect(loaded.initialSteps.map(\.name) == ["Source", "Converted to Table", "Expanded Column1", "Expanded Customer", "Expanded Lines",
                                                     "Expanded Lines1", "Changed Type"])
        let ours = try #require(loaded.queryDefinition)
        #expect(squeeze(ours) == squeeze(try desktopQuery(golden, table: "orders", localPath: url.path)))
    }

    @Test func kieuVaGiaTriKhopBangDesktopLuu() async throws {
        guard let url = FFixtures.sample("orders.json"), let golden = try Self.golden() else { return }
        let data = try JsonQuery.plan(location: url.path).data
        let engine = try golden.daxEngine()
        let model = try #require(golden.metadata)
        let desktopColumns = model.columns.filter { $0.tableName == "orders" && $0.kind == .data }
        #expect(data.columns.map(\.name) == desktopColumns.map(\.name))
        #expect(data.columns.map { TableLoader.modelType($0.data.type) } == desktopColumns.map(\.dataType))
        let rows = try engine.store.rowCount(try #require(engine.store.schema.column(table: "orders", name: "OrderID")?.id).table)
        #expect(data.rowCount == rows && rows == 203)
        // VertiPaq không giữ thứ tự dòng: so tập dòng (kể cả số lần lặp).
        var desktopRows: [String] = Array(repeating: "", count: rows)
        for column in desktopColumns {
            let stored = try engine.store.column(try #require(engine.store.schema.column(table: "orders", name: column.name)?.id))
            for row in 0..<rows { desktopRows[row] += "\(stored.value(at: row))|" }
        }
        let ourRows = (0..<data.rowCount).map { row in data.columns.map { "\($0.data.value(at: row))|" }.joined() }
        #expect(ourRows.sorted() == desktopRows.sorted())
    }

    @Test func jsonGocLaBanGhiVaMangGiaTriDon() throws {
        let record = try JsonQuery.build(root: try MJson.parse(Data(#"{"a":1,"b":{"c":"x"}}"#.utf8)), sourceExpression: "null")
        #expect(record.steps.map(\.name) == ["Source", "Converted to Table", "Expanded b", "Changed Type"])
        #expect(record.data.columns.map(\.name) == ["a", "b.c"])
        let values = try JsonQuery.build(root: try MJson.parse(Data("[1, 2.5, null]".utf8)), sourceExpression: "null")
        #expect(values.data.columns.map(\.name) == ["Column1"])
        #expect(values.steps.last?.expression.contains("type number") == true)   // có số lẻ → number, không phải Int64
    }
}
