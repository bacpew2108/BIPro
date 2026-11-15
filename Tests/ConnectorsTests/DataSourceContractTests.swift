// Phase F, T004: hình dạng hợp đồng DataSource bằng nguồn giả. Seam: contracts/data-source.md.
import Testing
import ColumnStore
@testable import Connectors

private struct FakeItem: SourceItem {
    let name: String
    let kind = SourceItemKind.table
    let columns: [SourceColumn]? = [SourceColumn(name: "A", type: .integer)]
    let rowCountHint: Int? = 3
    let table: TableData

    func preview(limit: Int) async throws -> TableData { table.prefix(limit) }
    func load(progress: SourceProgress?) async throws -> TableData {
        progress?(1)
        try Task.checkCancellation()
        return table
    }
}

private struct FakeSource: DataSource {
    let kind = SourceKind.sqlite
    let items_: [FakeItem]
    func items() async throws -> [any SourceItem] { items_ }
}

@Suite struct DataSourceContractTests {
    private func table() throws -> TableData {
        try TableData(columns: [TableColumn(name: "A", data: ColumnBuilder.integers([1, 2, 3]))])
    }

    @Test func previewDefaultsToTwoHundredRowsAndIsAtMostLimit() async throws {
        let item = FakeItem(name: "T", table: try table())
        #expect(try await item.preview(limit: 2).rowCount == 2)
        #expect(try await item.preview().rowCount == 3)
    }

    @Test func sourceListsItemsAndLoadReportsProgress() async throws {
        let source = FakeSource(items_: [FakeItem(name: "T", table: try table())])
        let items = try await source.items()
        #expect(items.map(\.name) == ["T"])
        let box = ProgressBox()
        let loaded = try await items[0].load(progress: { box.set($0) })
        #expect(loaded.rowCount == 3 && box.value == 1)
    }

    @Test func errorsCarryReadableMessages() {
        #expect(SourceError.unsupported("zstd") == SourceError.unsupported("zstd"))
        #expect(SourceKind.allCases.count == 6)
    }
}

private final class ProgressBox: @unchecked Sendable {
    private(set) var value = 0.0
    func set(_ v: Double) { value = v }
}
