import Foundation
import Testing
@testable import PBIXKit

/// Fixture for the VertiPaq writer: a 100-row table added to the `tuan6.2.pbix` model.
private enum VertiPaqFixture {
    static let tuan6 = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/tuan6.2.pbix")
    static var exists: Bool { FileManager.default.fileExists(atPath: tuan6.path) }

    static let tableName = "BiProTest"
    static let rowCount = 100
    static let cities = ["Hà Nội", "Đà Nẵng", "Hồ Chí Minh", "Cần Thơ", "Huế"]
    static let nullRow = 7

    static let ints = (0..<rowCount).map { Int64($0) }
    static let doubles = (0..<rowCount).map { Double($0 % 10) / 4 }
    static let strings: [String?] = (0..<rowCount).map { $0 == nullRow ? nil : cities[$0 % cities.count] }

    static let outDir: URL = {
        if let path = ProcessInfo.processInfo.environment["PBIX_WP5_OUT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: "/private/tmp/claude-501/-Users-macprom114-Desktop-PowerBINative/39e5fdc8-d27c-46a2-b750-47ff2adaa733/scratchpad/w/out/wp5", isDirectory: true)
    }()

    static func writeOutput(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try data.write(to: outDir.appendingPathComponent(name))
    }
}

@Suite struct VertiPaqWriteTests {
    /// Writes `BiProTest` into the sample model, rebuilds the ABF, compresses it, and reads it back
    /// with the project's own decoder (`VertiPaq.decodeTable`) and metadata reader (`ModelMetadata`).
    @Test(.enabled(if: VertiPaqFixture.exists))
    func roundTripsBiProTestThroughABFAndDecoder() throws {
        let abf = try PBIXFile(url: VertiPaqFixture.tuan6).loadDataModel().0
        var metadata = try TableMetadataWriter(sqlite: Data(try abf.contents(named: "metadata.sqlitedb")))
        let base = metadata.maxID

        let table = try VertiPaqWriter.encodeTable(
            name: VertiPaqFixture.tableName,
            tableID: base + 1, partitionID: base + 2, rowNumberID: base + 3,
            columns: [
                .init(id: base + 4, name: "Số lượng", values: .int64(VertiPaqFixture.ints)),
                .init(id: base + 5, name: "Đơn giá", values: .double(VertiPaqFixture.doubles)),
                .init(id: base + 6, name: "Thành phố", values: .string(VertiPaqFixture.strings)),
            ])
        try metadata.addTable(table)
        let newMetadata = try metadata.serialize()

        let newABF = try ABFWriter.rebuild(
            abf,
            replacing: [ABFPayload(path: "metadata.sqlitedb", data: newMetadata)],
            adding: table.files.map { ABFPayload(path: $0.path, data: $0.data) })

        // Metadata: integrity check and MAXID invariant (TableMetadataWriter.init), then the reader.
        _ = try TableMetadataWriter(sqlite: newMetadata)
        let model = try ModelMetadata(sqlite: newMetadata)
        let added = model.tables.first { $0.name == VertiPaqFixture.tableName }
        #expect(added?.isUserTable == true)
        let addedColumns = model.columns.filter { $0.tableName == VertiPaqFixture.tableName }
        #expect(addedColumns.count == 4)
        let dataColumns = addedColumns.filter { $0.kind == .data }
        #expect(dataColumns.map(\.name) == ["Số lượng", "Đơn giá", "Thành phố"])
        #expect(dataColumns.map(\.dataType) == [.int64, .double, .string])

        // Decode the ABF with the project decoder and compare every cell.
        let backup = try ABFBackup(data: newABF)
        let decoded = try VertiPaq.decodeTable(VertiPaqFixture.tableName, metadata: model, abf: backup)
        #expect(decoded.map(\.name) == ["Số lượng", "Đơn giá", "Thành phố"])
        #expect(decoded.map(\.dataType) == [.int64, .double, .string])
        guard decoded.count == 3 else { return }

        #expect(decoded[0].count == VertiPaqFixture.rowCount)
        let intMismatches = (0..<VertiPaqFixture.rowCount).filter { decoded[0][$0] != .int(VertiPaqFixture.ints[$0]) }
        let doubleMismatches = (0..<VertiPaqFixture.rowCount).filter { decoded[1][$0] != .double(VertiPaqFixture.doubles[$0]) }
        let stringMismatches = (0..<VertiPaqFixture.rowCount).filter {
            let expected: CellValue = VertiPaqFixture.strings[$0].map { .string($0) } ?? .null
            return decoded[2][$0] != expected
        }
        #expect(intMismatches.isEmpty, "int64 column: \(intMismatches.count) rows differ")
        #expect(doubleMismatches.isEmpty, "double column: \(doubleMismatches.count) rows differ")
        #expect(stringMismatches.isEmpty, "string column: \(stringMismatches.count) rows differ")
        #expect(decoded[2][VertiPaqFixture.nullRow] == .null)

        // The compressed DataModel must decompress to the same ABF.
        let dataModel = try DataModelStream.compress(abf: newABF)
        let (roundTrip, _) = try DataModelStream.decompress(dataModel)
        #expect(roundTrip == newABF)

        try VertiPaqFixture.writeOutput(newABF, name: "tuan6.2.biprotest.abf")
        try VertiPaqFixture.writeOutput(newMetadata, name: "tuan6.2.biprotest.sqlitedb")
        try VertiPaqFixture.writeOutput(dataModel, name: "tuan6.2.biprotest.datamodel.bin")
    }

    /// Control on real data: values of four `Marketing` columns of `tuan6.2.pbix`, decoded with the
    /// project decoder, are rebuilt by the writer's dictionary and IDs, and its segment statistics
    /// (base ID, bit width, NULL flag) agree with the real `.idfmeta`. Byte equality of the dictionary is
    /// not expected: real dictionaries are not in first-appearance order, and the IDs make the order irrelevant.
    @Test(.enabled(if: VertiPaqFixture.exists))
    func agreesWithRealMarketingColumns() throws {
        let abf = try PBIXFile(url: VertiPaqFixture.tuan6).loadDataModel().0
        let model = try ModelMetadata(sqlite: Data(try abf.contents(named: "metadata.sqlitedb")))
        for name in ["Nguồn traffic", "Dòng sản phẩm", "Marketer", "Conversion dự kiến"] {
            guard let storage = model.storage(table: "Marketing", column: name) else {
                Issue.record("Marketing[\(name)] not found in tuan6.2.pbix")
                continue
            }
            let column = try VertiPaq.decodeColumn(storage, abf: abf)
            let cells = (0..<column.count).map { column[$0] }
            let values: VertiPaqWriter.Values
            switch column.dataType {
            case .string:
                values = .string(cells.map { cell -> String? in
                    if case .string(let text) = cell { return text }
                    return nil
                })
            default:
                values = .double(cells.map { cell -> Double in
                    if case .double(let number) = cell { return number }
                    return .nan
                })
            }

            let ours = try VertiPaqWriter.encodeDictionary(values)
            let entries = try VertiPaq.readDictionary(ours.data, file: "ours.dictionary", dataType: column.dataType)
            let rebuilt: [CellValue] = ours.ids.map { id in
                id == Int64(VertiPaqWriter.nullDataID) ? .null : entries[Int(id) - VertiPaqWriter.firstDataID]
            }
            let mismatches = (0..<cells.count).filter { rebuilt[$0] != cells[$0] }
            #expect(mismatches.isEmpty, "Marketing[\(name)]: \(mismatches.count) rows rebuilt differently")

            let segment = try VertiPaqWriter.encodeSegment(ids: ours.ids, dictionaryCount: ours.count)
            let realMeta = try VertiPaq.parseIDFMeta(Data(try abf.contents(named: storage.idfFiles[0] + "meta")), file: "real.idfmeta")
            let oursMeta = try VertiPaq.parseIDFMeta(segment.idfmeta, file: "ours.idfmeta")
            #expect(oursMeta.first?.records == realMeta.first?.records, "Marketing[\(name)]: row count")
            #expect(oursMeta.first?.minDataID == realMeta.first?.minDataID, "Marketing[\(name)]: base data ID")
            #expect(oursMeta.first?.bitWidth == realMeta.first?.bitWidth, "Marketing[\(name)]: bit width")
            #expect(oursMeta.first?.hasNulls == realMeta.first?.hasNulls, "Marketing[\(name)]: NULL flag")
        }
    }

    @Test func bitPackingRoundTripsEverySupportedWidth() throws {
        // Widths up to 21 bits: data IDs must stay inside the 32-bit fields of the segment metadata.
        for width in VertiPaqWriter.supportedWidths where width <= 21 {
            let top = Int64(VertiPaqWriter.mask(width))
            for withNulls in [false, true] {
                // Without NULLs the base is 3; with NULLs the base is the NULL id 2. Values are base or base + top,
                // so the width chosen is exactly `width`.
                let base: Int64 = withNulls ? 2 : 3
                let column: [Int64] = (0..<50).map { $0 % 3 == 0 ? base : base + top }
                let segment = try VertiPaqWriter.encodeSegment(ids: column, dictionaryCount: 2)
                #expect(segment.bitWidth == width, "width \(width) chose \(segment.bitWidth)")
                let metas = try VertiPaq.parseIDFMeta(segment.idfmeta, file: "test.idfmeta")
                let parts = try VertiPaq.parseIDF(segment.idf, file: "test.idf")
                #expect(metas.count == 1 && parts.count == 1)
                guard metas.count == 1, parts.count == 1 else { continue }
                let decoded = VertiPaq.decodeSegment(parts[0], meta: metas[0])
                #expect(decoded == column, "width \(width), nulls \(withNulls): IDs differ after decode")
            }
        }
    }

    @Test func segmentsWiderThanTheMetadataFieldsAreRejected() throws {
        // A 32-bit width needs data IDs above UInt32.max, which the segment metadata cannot hold.
        #expect(throws: WriteError.self) {
            _ = try VertiPaqWriter.encodeSegment(ids: [3, 3 + Int64(UInt32.max)], dictionaryCount: 2)
        }
        let wide = try VertiPaqWriter.encodeSegment(ids: [3, 3 + Int64(VertiPaqWriter.mask(21))], dictionaryCount: 2)
        #expect(wide.bitWidth == 21)
    }

    @Test func integerDictionaryUsesFourOrEightByteElements() throws {
        let small = try VertiPaqWriter.encodeDictionary(.int64([5, -3, 5, 7]))
        #expect(small.ids == [3, 4, 3, 5])
        #expect(small.count == 3)
        let smallValues = try VertiPaq.readDictionary(small.data, file: "small.dictionary", dataType: .int64)
        #expect(smallValues == [.int(5), .int(-3), .int(7)])

        let large = try VertiPaqWriter.encodeDictionary(.int64([1 << 40, 5, 1 << 40]))
        #expect(large.ids == [3, 4, 3])
        let largeValues = try VertiPaq.readDictionary(large.data, file: "large.dictionary", dataType: .int64)
        #expect(largeValues == [.int(1 << 40), .int(5)])
    }

    @Test func doubleAndStringDictionariesDecode() throws {
        let doubles = try VertiPaqWriter.encodeDictionary(.double([0.5, 0.25, 0.5]))
        #expect(doubles.ids == [3, 4, 3])
        let doubleValues = try VertiPaq.readDictionary(doubles.data, file: "d.dictionary", dataType: .double)
        #expect(doubleValues == [.double(0.5), .double(0.25)])

        let strings = try VertiPaqWriter.encodeDictionary(.string(["Hà Nội", nil, "Huế", "Hà Nội", ""]))
        #expect(strings.ids == [3, 2, 4, 3, 5])
        #expect(strings.hasNulls)
        #expect(strings.count == 3)
        let stringValues = try VertiPaq.readDictionary(strings.data, file: "s.dictionary", dataType: .string)
        #expect(stringValues == [.string("Hà Nội"), .string("Huế"), .string("")])
    }

    @Test func rejectsNULInStringsAndRaggedColumns() throws {
        #expect(throws: WriteError.self) {
            _ = try VertiPaqWriter.encodeDictionary(.string(["a\0b"]))
        }
        #expect(throws: WriteError.self) {
            _ = try VertiPaqWriter.encodeTable(name: "T", tableID: 100, partitionID: 101, rowNumberID: 102, columns: [
                .init(id: 103, name: "A", values: .int64([1, 2])),
                .init(id: 104, name: "B", values: .int64([1])),
            ])
        }
    }
}
