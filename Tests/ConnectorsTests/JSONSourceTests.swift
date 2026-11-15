import Testing
import Foundation
import ColumnStore
@testable import Connectors

@Suite struct JSONSourceTests {

    // MARK: - Sample Fixture Tests

    @Test func ordersJSONItemsAndLoad() async throws {
        guard let url = FFixtures.sample("orders.json") else { return }
        let source = JSONSource(url: url)
        let items = try await source.items()

        #expect(items.count == 1)
        let item = items[0]
        #expect(item.name == "orders")
        #expect(item.kind == .record)

        // Preview limit 5
        let preview = try await item.preview(limit: 5)
        #expect(preview.rowCount == 5)
        #expect(preview.columns.map(\.name) == ["OrderID", "Customer", "Lines", "Note"])
        #expect(preview.columns[0].data.type == .integer)
        #expect(preview.columns[1].data.type == .string) // object lồng -> chuỗi JSON
        #expect(preview.columns[2].data.type == .string) // array lồng -> chuỗi JSON
        #expect(preview.columns[3].data.type == .string)

        // Load full
        let table = try await item.load(progress: nil)
        #expect(table.rowCount == 100)

        // Record 1 (row 0)
        #expect(table.value(row: 0, column: 0) == .integer(1))
        if case .string(let cust) = table.value(row: 0, column: 1) {
            #expect(cust.contains("\"Id\":5"))
        } else {
            #expect(Bool(false), "Customer không phải chuỗi JSON")
        }
        #expect(table.value(row: 0, column: 3) == .string("đơn 1"))

        // Note nil ở các bản ghi 10, 20, ..., 100 (index 9, 19, ..., 99)
        for i in stride(from: 9, to: 100, by: 10) {
            #expect(table.value(row: i, column: 3) == .blank, "Note tại dòng \(i) phải là blank")
        }
        // Bản ghi 11 (index 10) Note không nil
        #expect(table.value(row: 10, column: 3) == .string("đơn 11"))

        // Tổng số phần tử Lines = 203
        var totalLinesCount = 0
        for r in 0..<table.rowCount {
            if case .string(let linesJSON) = table.value(row: r, column: 2) {
                if let data = linesJSON.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                    totalLinesCount += arr.count
                }
            }
        }
        #expect(totalLinesCount == 203)
    }

    // MARK: - Edge Cases & Invariant Tests (with temp JSON files)

    private func withTempJSON(_ content: String, _ test: (URL) async throws -> Void) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("test.json")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try await test(fileURL)
    }

    @Test func singleObjectRootProducesOneRow() async throws {
        let json = "{\"name\": \"Alice\", \"age\": 30}"
        try await withTempJSON(json) { url in
            let source = JSONSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.rowCount == 1)
            #expect(table.columns.count == 2)
            #expect(table.index(ofColumn: "name") != nil)
            #expect(table.index(ofColumn: "age") != nil)
            if let nameCol = table.index(ofColumn: "name") {
                #expect(table.value(row: 0, column: nameCol) == .string("Alice"))
            }
            if let ageCol = table.index(ofColumn: "age") {
                #expect(table.value(row: 0, column: ageCol) == .integer(30))
            }
        }
    }

    @Test func arrayOfPrimitivesProducesSingleValueColumn() async throws {
        let json = "[10, 20, 30]"
        try await withTempJSON(json) { url in
            let source = JSONSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.rowCount == 3)
            #expect(table.columns.map(\.name) == ["Value"])
            #expect(table.columns[0].data.type == .integer)
            #expect(table.value(row: 0, column: 0) == .integer(10))
            #expect(table.value(row: 1, column: 0) == .integer(20))
            #expect(table.value(row: 2, column: 0) == .integer(30))
        }
    }

    @Test func columnOrderFollowsFirstAppearanceAndMissingKeysAreNil() async throws {
        let json = """
        [
            {"b": 2, "a": 1},
            {"c": 3, "a": 4}
        ]
        """
        try await withTempJSON(json) { url in
            let source = JSONSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.columns.map(\.name) == ["b", "a", "c"])
            #expect(table.rowCount == 2)
            // Row 0: b=2, a=1, c=nil
            #expect(table.value(row: 0, column: 0) == .integer(2))
            #expect(table.value(row: 0, column: 1) == .integer(1))
            #expect(table.value(row: 0, column: 2) == .blank)
            // Row 1: b=nil, a=4, c=3
            #expect(table.value(row: 1, column: 0) == .blank)
            #expect(table.value(row: 1, column: 1) == .integer(4))
            #expect(table.value(row: 1, column: 2) == .integer(3))
        }
    }

    @Test func mixedTypesInColumnBecomeString() async throws {
        let json = """
        [
            {"x": 10},
            {"x": "text"}
        ]
        """
        try await withTempJSON(json) { url in
            let source = JSONSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.columns[0].data.type == .string)
            #expect(table.value(row: 0, column: 0) == .string("10"))
            #expect(table.value(row: 1, column: 0) == .string("text"))
        }
    }

    @Test func malformedJSONThrowsUnreadable() async throws {
        let badJSON = "{ not valid json }"
        try await withTempJSON(badJSON) { url in
            let source = JSONSource(url: url)
            let items = try await source.items()
            await #expect(throws: SourceError.self) {
                try await items[0].load(progress: nil)
            }
        }
    }
}
