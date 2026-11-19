// specs/011, US5 (T054): lưu bảng nhiều đoạn dữ liệu và nén RLE như Desktop.
// - Nhiều đoạn: cắt mỗi `segmentSize` dòng, mỗi đoạn một khối trong `.idf`, một `<1:CS` trong `.idfmeta`; giải mã lại trùng từng ô.
// - RLE: với cùng thứ tự dòng, các run (RLE và bit-packing) trùng run Desktop ghi (Nhom6 `Fact Transaction`, 1 056 320 dòng).
// - Bảng 8 388 609 dòng qua `PBIXWriter` (nặng, `BIPRO_HEAVY=1`).
import Foundation
import Testing
@testable import PBIXKit

@Suite struct VertiPaqSegmentTests {
    private func decode(_ segment: VertiPaqWriter.SegmentResult) throws -> [Int64] {
        let metas = try VertiPaq.parseIDFMeta(segment.idfmeta, file: "t.idfmeta")
        let parts = try VertiPaq.parseIDF(segment.idf, file: "t.idf")
        #expect(metas.count == parts.count)
        return zip(parts, metas).flatMap { VertiPaq.decodeSegment($0, meta: $1) }
    }

    @Test func nhieuDoanGiaiMaLaiTrungTungO() throws {
        // 2 500 dòng, đoạn 1 000: ba đoạn (1 000, 1 000, 500); có NULL, run dài, giá trị lẻ.
        var ids: [Int64] = []
        for i in 0..<2_500 {
            switch i {
            case 0..<300: ids.append(5)
            case 300..<320: ids.append(2)
            case 990..<1_200: ids.append(9)
            default: ids.append(Int64(3 + (i * 7919) % 40))
            }
        }
        let segment = try VertiPaqWriter.encodeSegment(ids: ids, dictionaryCount: 42, segmentSize: 1_000)
        #expect(segment.segmentRecords == [1_000, 1_000, 500])
        #expect(try decode(segment) == ids)
        #expect(segment.rleRuns == 2)   // 300 dòng giá trị 5 và 200 dòng giá trị 9 ở đoạn 2; run NULL 20 dòng dưới ngưỡng 64
        #expect(segment.minDataID == 3 && segment.maxDataID == 42 && segment.originalMinDataID == 2)
    }

    @Test func runTableLaLuyThuaCuaHaiLonHonSoRun() throws {
        // 40 run RLE xen bit-packing: bảng run 128 mục (Desktop: 16 run dùng → 32, 335 → 512, 2 198 → 4 096).
        var ids: [Int64] = []
        for k in 0..<40 { ids += Array(repeating: Int64(3 + k % 5), count: 70); ids += [3, 4, 5] }
        let segment = try VertiPaqWriter.encodeSegment(ids: ids, dictionaryCount: 5)
        let runs = try VertiPaq.parseIDF(segment.idf, file: "t.idf")[0].runs
        #expect(runs.count == 128)
        #expect(segment.rleRuns == 40 && segment.bitPackedRuns == 40)
        #expect(try decode(segment) == ids)
    }

    @Test func motGiaTriChiMotRunVaMotTuRong() throws {
        // Như Desktop (Nhom6 `trans count`): một run RLE, bảng 16 mục, một từ 0, khối bit-packing 0 giá trị.
        let ids = [Int64](repeating: 3, count: 682)
        let segment = try VertiPaqWriter.encodeSegment(ids: ids, dictionaryCount: 1)
        let part = try VertiPaq.parseIDF(segment.idf, file: "t.idf")[0]
        #expect(part.runs.count == 16 && part.runs[0].value == 3 && part.runs[0].repeats == 682 && part.packed == [0])
        #expect(try VertiPaq.parseIDFMeta(segment.idfmeta, file: "t").first?.bitPackedCount == 0)
        #expect(segment.rleRuns == 1 && segment.bitPackedRuns == 0)
        #expect(try decode(segment) == ids)
    }

    @Test func bangNhieuDoanQuaEncodeTable() throws {
        let rows = 2_345
        let values = (0..<rows).map { Int64?($0 < 1_500 ? 7 : Int64($0 % 11)) }
        let table = try VertiPaqWriter.encodeTable(name: "T", tableID: 1001, partitionID: 1002, rowNumberID: 1003,
                                                   columns: [.init(id: 1004, name: "A", values: .int64(values))], segmentSize: 1_000)
        #expect(table.segmentRecords == [1_000, 1_000, 345])
        #expect(table.segmentCount == 3 && table.recordsPerSegment == 1_000)
        for column in table.columns {
            #expect(try VertiPaq.parseIDFMeta(column.idfmeta.data, file: "m").count == 3, "\(column.storageName)")
        }
        #expect(table.columns[1].rleRuns > 0)
    }

    /// Nhom6 `Fact Transaction`: các cột mã theo thứ tự dòng Desktop đã lưu, mã hoá lại ra đúng các run Desktop ghi (độ dài, loại),
    /// số giá trị bit-packing, độ rộng bit và số run trong thống kê.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"
                   && FileManager.default.fileExists(atPath: Nhom6Segments.path.path)))
    func runTrungDesktopTrenNhom6() throws {
        let abf = try PBIXFile(url: Nhom6Segments.path).loadDataModel().0
        let model = try ModelMetadata(sqlite: Data(try abf.contents(named: "metadata.sqlitedb")))
        for name in ["date_key", "account_key", "trans_type_key", "trans_count", "client_key"] {
            let storage = try #require(model.storage(table: "Fact_Transaction", column: name))
            let realIDF = try VertiPaq.parseIDF(Data(try abf.contents(named: storage.idfFiles[0])), file: "r")[0]
            let realMeta = try VertiPaq.parseIDFMeta(Data(try abf.contents(named: storage.idfFiles[0] + "meta")), file: "r")[0]
            let ids = VertiPaq.decodeSegment(realIDF, meta: realMeta)
            let ours = try VertiPaqWriter.encodeSegment(ids: ids, dictionaryCount: Int(ids.max() ?? 3) - 2)
            let oursIDF = try VertiPaq.parseIDF(ours.idf, file: "o")[0]
            let oursMeta = try VertiPaq.parseIDFMeta(ours.idfmeta, file: "o")[0]
            func shape(_ runs: [(value: UInt32, repeats: UInt32)]) -> [String] {
                runs.filter { $0.repeats > 0 }.map { ($0.value >= 0xF000_0000 ? "P" : "R\($0.value):") + "\($0.repeats)" }
            }
            let a = shape(oursIDF.runs), b = shape(realIDF.runs)
            #expect(a == b, "\(name): \(a.count) run, Desktop \(b.count); đầu khác: \(zip(a, b).first { $0 != $1 }.map { "\($0)" } ?? "-")")
            #expect(oursIDF.runs.count == realIDF.runs.count, "\(name): cỡ bảng run")
            #expect(oursMeta.bitPackedCount == realMeta.bitPackedCount && oursMeta.bitWidth == realMeta.bitWidth, "\(name)")
            #expect(oursIDF.packed == realIDF.packed, "\(name): từ bit-packing")
        }
    }

    /// 2,5 đoạn (2 621 440 dòng) qua `PBIXWriter`, đọc lại từng ô; siêu dữ liệu `SegmentMapStorage` ba đoạn.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"
                   && FileManager.default.fileExists(atPath: DesktopGolden.path.path)))
    func bangHonMotDoanQuaPBIXWriter() throws {
        let rows = VertiPaqWriter.recordsPerSegment * 5 / 2
        var ids = [Int64?](repeating: nil, count: rows), regions = [String?](repeating: nil, count: rows)
        let names = ["Bắc", "Trung", "Nam", "Tây Nguyên"]
        for i in 0..<rows {
            ids[i] = i % 1_000 == 7 ? nil : Int64(i)
            regions[i] = names[(i / 100_000) % 4]
        }
        VertiPaqWriter.segmentSizeForNewTables = VertiPaqWriter.recordsPerSegment
        defer { VertiPaqWriter.segmentSizeForNewTables = Int.max }
        var changes = PBIXChanges()
        changes.modelEdits.append(.addTable(NewTable(name: "Lon", columns: [NewTableColumn(name: "ID", values: .int64(ids)),
                                                                           NewTableColumn(name: "Vùng", values: .string(regions))])))
        let data = try PBIXWriter.build(source: DesktopGolden.path, changes: changes).data
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let columns = Dictionary(uniqueKeysWithValues: try VertiPaq.decodeTable("Lon", metadata: metadata, abf: abf).map { ($0.name, $0) })
        let id = try #require(columns["ID"]), region = try #require(columns["Vùng"])
        #expect(id.count == rows && region.count == rows)
        for i in stride(from: 0, to: rows, by: 9_973) + [rows - 2, rows - 1, VertiPaqWriter.recordsPerSegment - 1] {
            #expect(id[i] == (ids[i].map { .int($0) } ?? .null), "ID dòng \(i)")
            #expect(region[i] == .string(regions[i]!), "Vùng dòng \(i)")
        }
        let db = try TableMetadataDatabase(bytes: try abf.contents(named: "metadata.sqlitedb"))
        let map = try db.strings("""
            SELECT sm.SegmentCount || '/' || sm.RecordsPerSegment || '/' || sm.RecordCount FROM SegmentMapStorage sm
            JOIN PartitionStorage ps ON ps.SegmentMapStorageID = sm.ID JOIN Partition p ON p.PartitionStorageID = ps.ID
            JOIN [Table] t ON t.ID = p.TableID WHERE t.Name = 'Lon'
            """)
        #expect(map == ["3/\(VertiPaqWriter.recordsPerSegment)/\(rows)"])
    }
}

extension VertiPaqSegmentTests {
    /// T057: cột tính toán thêm vào bảng nhiều đoạn cắt đúng như bảng (2^20 + 2^20 + nửa đoạn), đọc lại trùng từng ô.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"
                   && FileManager.default.fileExists(atPath: DesktopGolden.path.path)))
    func cotTinhToanTrenBangHaiDoan() throws {
        let rows = VertiPaqWriter.recordsPerSegment * 5 / 2
        VertiPaqWriter.segmentSizeForNewTables = VertiPaqWriter.recordsPerSegment
        defer { VertiPaqWriter.segmentSizeForNewTables = Int.max }
        var first = PBIXChanges()
        first.modelEdits.append(.addTable(NewTable(name: "Lon", columns: [NewTableColumn(name: "ID", values: .int64((0..<rows).map { Int64($0) }))])))
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("seg-\(UUID().uuidString).pbix")
        defer { try? FileManager.default.removeItem(at: staged) }
        try PBIXWriter.build(source: DesktopGolden.path, changes: first).data.write(to: staged)

        let parity: [Int64?] = (0..<rows).map { $0 % 5 == 0 ? nil : Int64($0 % 2) }
        var second = PBIXChanges()
        second.modelEdits.append(.addCalculatedColumn(table: "Lon", name: "Chẵn lẻ", expression: "MOD([ID], 2)", dataType: .int64))
        second.calculatedData = ["Lon[Chẵn lẻ]": .int64(parity)]
        let data = try PBIXWriter.build(source: staged, changes: second).data
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let storage = try #require(metadata.storage(table: "Lon", column: "Chẵn lẻ"))
        #expect(try VertiPaq.parseIDFMeta(Data(try abf.contents(named: storage.idfFiles[0] + "meta")), file: "m").map(\.records)
                    == [VertiPaqWriter.recordsPerSegment, VertiPaqWriter.recordsPerSegment, VertiPaqWriter.recordsPerSegment / 2])
        let column = try VertiPaq.decodeColumn(storage, abf: abf)
        #expect(column.count == rows)
        for i in stride(from: 0, to: rows, by: 7_919) + [rows - 1, VertiPaqWriter.recordsPerSegment - 1] {
            #expect(column[i] == (parity[i].map { .int($0) } ?? .null), "dòng \(i)")
        }
    }
}

enum Nhom6Segments {
    static let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/bipro-golden/Nhom6_work.pbix")
}
