import Testing
import Foundation
import ColumnStore
@testable import Connectors

@Suite struct CSVSourceTests {

    // MARK: - Sample Fixture Tests

    @Test func sales2026CSVLoadAndPreview() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        #expect(items.count == 1)
        let item = items[0]
        #expect(item.name == "sales_2026")
        #expect(item.kind == .file)

        // Preview limit 5
        let preview = try await item.preview(limit: 5)
        #expect(preview.rowCount == 5)
        #expect(preview.columns.map(\.name) == ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"])
        #expect(preview.value(row: 0, column: 0) == .integer(1))
        #expect(preview.value(row: 0, column: 1) == .dateTime(46083.0))
        #expect(preview.value(row: 0, column: 2) == .string("Trung tâm"))
        #expect(preview.value(row: 0, column: 3) == .integer(7))
        #expect(preview.value(row: 0, column: 4) == .string("Đồng hồ"))
        #expect(preview.value(row: 0, column: 5) == .integer(11))
        #expect(preview.value(row: 0, column: 6) == .double(120.0))
        #expect(preview.value(row: 0, column: 7) == .double(1320.0))

        // Load full
        let box = ProgressCollector()
        let table = try await item.load(progress: { box.add($0) })
        #expect(table.rowCount == 10_000)
        #expect(table.columns.count == 8)
        #expect(box.values.first == 0.0)
        #expect(box.values.last == 1.0)

        // Column types
        #expect(table.columns[0].data.type == .integer)
        #expect(table.columns[1].data.type == .dateTime)
        #expect(table.columns[2].data.type == .string)
        #expect(table.columns[3].data.type == .integer)
        #expect(table.columns[4].data.type == .string)
        #expect(table.columns[5].data.type == .integer)
        #expect(table.columns[6].data.type == .double)
        #expect(table.columns[7].data.type == .double)

        // First row
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 1) == .dateTime(46083.0))
        #expect(table.value(row: 0, column: 2) == .string("Trung tâm"))
        #expect(table.value(row: 0, column: 3) == .integer(7))
        #expect(table.value(row: 0, column: 4) == .string("Đồng hồ"))
        #expect(table.value(row: 0, column: 5) == .integer(11))
        #expect(table.value(row: 0, column: 6) == .double(120.0))
        #expect(table.value(row: 0, column: 7) == .double(1320.0))

        // Last row (row 9999)
        #expect(table.value(row: 9999, column: 0) == .integer(10000))
        #expect(table.value(row: 9999, column: 2) == .string("East"))
        #expect(table.value(row: 9999, column: 3) == .integer(43))
        #expect(table.value(row: 9999, column: 4) == .string("Quần jean"))
        #expect(table.value(row: 9999, column: 5) == .integer(14))
        #expect(table.value(row: 9999, column: 6) == .double(25.0))
        #expect(table.value(row: 9999, column: 7) == .double(350.0))

        // Sum Qty and Amount
        var sumQty: Int64 = 0
        var sumAmount: Double = 0
        var regions = Set<String>()
        for r in 0..<table.rowCount {
            if case .integer(let q) = table.value(row: r, column: 5) { sumQty += q }
            if case .double(let a) = table.value(row: r, column: 7) { sumAmount += a }
            if case .string(let reg) = table.value(row: r, column: 2) { regions.insert(reg) }
        }
        #expect(sumQty == 99742)
        #expect(abs(sumAmount - 3654202.84) < 0.02)
        #expect(regions.count == 5)
    }

    @Test func sales100CSVLoad() async throws {
        guard let url = FFixtures.sample("sales_100.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        let table = try await items[0].load(progress: nil)
        #expect(table.rowCount == 100)

        var sumQty: Int64 = 0
        var sumAmount: Double = 0
        for r in 0..<table.rowCount {
            if case .integer(let q) = table.value(row: r, column: 5) { sumQty += q }
            if case .double(let a) = table.value(row: r, column: 7) { sumAmount += a }
        }
        #expect(sumQty == 1058)
        #expect(abs(sumAmount - 37860.12) < 0.02)
    }

    @Test func salesDirtyCSVLoad() async throws {
        guard let url = FFixtures.sample("sales_dirty.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        let table = try await items[0].load(progress: nil)
        #expect(table.rowCount == 31)

        // Row 2 (3rd row): Product is blank
        #expect(table.value(row: 2, column: 4) == .blank)

        // Row 3 (4th row): Region is blank
        #expect(table.value(row: 3, column: 2) == .blank)

        // Row 4 (5th row): Qty has "n/a", column Qty is string
        #expect(table.columns[5].data.type == .string)
        #expect(table.value(row: 4, column: 5) == .string("n/a"))

        // Row 5 (6th row): Price is blank
        #expect(table.columns[6].data.type == .double)
        #expect(table.value(row: 5, column: 6) == .blank)

        // Last row (row 30) is duplicate of row 0
        #expect(table.value(row: 30, column: 0) == table.value(row: 0, column: 0))
        #expect(table.value(row: 30, column: 4) == table.value(row: 0, column: 4))
    }

    @Test func salesSemicolonCSVLoad() async throws {
        guard let url = FFixtures.sample("sales_semicolon.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        let table = try await items[0].load(progress: nil)
        #expect(table.rowCount == 30)
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 2) == .string("Trung tâm"))
    }

    @Test func salesUTF16CSVLoad() async throws {
        guard let url = FFixtures.sample("sales_utf16.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        let table = try await items[0].load(progress: nil)
        #expect(table.rowCount == 30)
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 2) == .string("Trung tâm"))
    }

    @Test func salesUTF8BOMCSVLoad() async throws {
        guard let url = FFixtures.sample("sales_utf8bom.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        let table = try await items[0].load(progress: nil)
        #expect(table.rowCount == 30)
        #expect(table.columns[0].name == "OrderID")
        #expect(table.value(row: 0, column: 0) == .integer(1))
    }

    @Test func multilineCSVLoad() async throws {
        guard let url = FFixtures.sample("multiline.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        let table = try await items[0].load(progress: nil)
        #expect(table.rowCount == 3)
        #expect(table.columns.map(\.name) == ["Id", "Note"])
        #expect(table.columns[0].data.type == .integer)
        #expect(table.columns[1].data.type == .string)

        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 1) == .string("dòng một\ndòng hai"))

        #expect(table.value(row: 1, column: 0) == .integer(2))
        #expect(table.value(row: 1, column: 1) == .string("có \"ngoặc kép\", dấu phẩy"))

        #expect(table.value(row: 2, column: 0) == .integer(3))
        #expect(table.value(row: 2, column: 1) == .blank)
    }

    @Test func customersCSVLoad() async throws {
        guard let url = FFixtures.sample("customers.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()
        let table = try await items[0].load(progress: nil)
        #expect(table.rowCount == 50)
        #expect(table.columns.map(\.name) == ["CustomerID", "Name", "Segment"])
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 1) == .string("Khách 1"))
        #expect(table.value(row: 0, column: 2) == .string("Wholesale"))
        #expect(table.value(row: 49, column: 0) == .integer(50))
        #expect(table.value(row: 49, column: 1) == .string("Khách 50"))
        #expect(table.value(row: 49, column: 2) == .string("Online"))
    }

    // MARK: - Edge Cases & Invariant Tests (with temp files)

    private func withTempCSV(content: String, encoding: String.Encoding = .utf8, _ test: (URL) async throws -> Void) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("test.csv")
        guard let data = content.data(using: encoding) else { throw SourceError.encoding("Không thể mã hoá test") }
        try data.write(to: fileURL)
        try await test(fileURL)
    }

    @Test func lineEndingsCRLF_LF_CR_NoTrailingNewline() async throws {
        let content = "A,B\r\n1,2\n3,4\r5,6"
        try await withTempCSV(content: content) { url in
            let source = CSVSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.rowCount == 3)
            #expect(table.value(row: 0, column: 0) == .integer(1))
            #expect(table.value(row: 1, column: 0) == .integer(3))
            #expect(table.value(row: 2, column: 0) == .integer(5))
        }
    }

    @Test func rowShorterThanHeaderFillsNil() async throws {
        let content = "A,B,C\n1,2\n3,4,5"
        try await withTempCSV(content: content) { url in
            let source = CSVSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.rowCount == 2)
            #expect(table.value(row: 0, column: 2) == .blank)
            #expect(table.value(row: 1, column: 2) == .integer(5))
        }
    }

    @Test func rowLongerThanHeaderThrowsUnreadable() async throws {
        let content = "A,B\n1,2,3"
        try await withTempCSV(content: content) { url in
            let source = CSVSource(url: url)
            let items = try await source.items()
            await #expect(throws: SourceError.self) {
                try await items[0].load(progress: nil)
            }
        }
    }

    @Test func emptyFileThrowsSourceErrorEmpty() async throws {
        try await withTempCSV(content: "") { url in
            let source = CSVSource(url: url)
            let items = try await source.items()
            await #expect(throws: SourceError.empty) {
                try await items[0].load(progress: nil)
            }
        }
    }

    @Test func fileWithOnlyHeaderProducesZeroRowsStringColumns() async throws {
        let content = "ColA,ColB,ColC\n"
        try await withTempCSV(content: content) { url in
            let source = CSVSource(url: url)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.rowCount == 0)
            #expect(table.columns.count == 3)
            #expect(table.columns.allSatisfy { $0.data.type == .string })
        }
    }

    @Test func optionsPromoteHeadersFalseAndDetectTypesFalse() async throws {
        let content = "Name,Age\nAlice,30\nBob,25"
        try await withTempCSV(content: content) { url in
            let options = CSVSource.Options(promoteHeaders: false, detectTypes: false)
            let source = CSVSource(url: url, options: options)
            let items = try await source.items()
            let table = try await items[0].load(progress: nil)
            #expect(table.rowCount == 3)
            #expect(table.columns.map(\.name) == ["Column1", "Column2"])
            #expect(table.columns.allSatisfy { $0.data.type == .string })
            #expect(table.value(row: 0, column: 0) == .string("Name"))
            #expect(table.value(row: 1, column: 1) == .string("30"))
        }
    }

    @Test func cancellationDuringLoadThrowsCancelled() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let source = CSVSource(url: url)
        let items = try await source.items()

        let task = Task {
            try await items[0].load(progress: nil)
        }
        task.cancel()
        do {
            _ = try await task.value
            #expect(Bool(false), "Lẽ ra phải ném cancelled")
        } catch let err as SourceError {
            #expect(err == .cancelled)
        } catch {
            #expect(Bool(false), "Ném sai kiểu lỗi: \(error)")
        }
    }

    @Test func previewLargeCSVUnderTwoSeconds() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("large.csv")

        // Sinh 300 000 dòng CSV
        let rowChunk = (1...1000).map { "\($0),2026-01-01,Product,100,2.5\n" }.joined()
        FileManager.default.createFile(atPath: fileURL.path, contents: "ID,Date,Product,Qty,Price\n".data(using: .utf8))
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            let chunkData = rowChunk.data(using: .utf8)!
            for _ in 0..<300 {
                handle.write(chunkData)
            }
            try? handle.close()
        }

        let start = ContinuousClock.now
        let source = CSVSource(url: fileURL)
        let items = try await source.items()
        let preview = try await items[0].preview(limit: 200)
        let elapsed = ContinuousClock.now - start

        #expect(preview.rowCount == 200)
        #expect(elapsed < .seconds(2), "preview quá chậm: \(elapsed)")
    }
}

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []

    func add(_ v: Double) {
        lock.lock()
        defer { lock.unlock() }
        values.append(v)
    }
}

