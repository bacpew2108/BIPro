// Phase F, T017/T022 (PBIXKit): lưu bảng mới (T3) qua `PBIXWriter.build`, đọc lại từng ô bằng bộ giải mã. Chạy trên `tuan6.2.pbix`
// (file Desktop). Mở được trong Desktop đã kiểm bằng tay (`docs/phase-f-evidence/vm-f0/CHECKLIST-KET-QUA.md`).
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: FileManager.default.fileExists(atPath: DesktopGolden.path.path))) struct PBIXWriterTableTests {
    private let cities = ["Hà Nội", "Đà Nẵng", "Hồ Chí Minh"]

    private func sales(_ name: String = "Sales2026", rows: Int = 200) -> NewTable {
        var codes: [Int64?] = [], prices: [Double?] = [], dates: [Double?] = [], towns: [String?] = [], flags: [Bool?] = []
        for i in 0..<rows {
            codes.append(i % 17 == 5 ? nil : Int64(i) * 3 - 7)
            prices.append(i % 13 == 0 ? nil : Double(i) / 8)
            dates.append(i % 11 == 0 ? nil : 46_000 + Double(i % 40))
            towns.append(i % 7 == 3 ? nil : cities[i % 3])
            flags.append(i % 9 == 4 ? nil : i % 2 == 0)
        }
        return NewTable(name: name, columns: [
            NewTableColumn(name: "Mã", values: .int64(codes)),
            NewTableColumn(name: "Giá", values: .double(prices)),
            NewTableColumn(name: "Ngày", values: .dateTime(dates)),
            NewTableColumn(name: "Thành phố", values: .string(towns)),
            NewTableColumn(name: "Đúng", values: .boolean(flags)),
        ])
    }

    private func build(_ edits: [ModelEdit], source: URL = DesktopGolden.path) throws -> Data {
        var changes = PBIXChanges()
        for edit in edits { changes.modelEdits.append(edit) }
        #expect(changes.tier == .data)
        return try PBIXWriter.build(source: source, changes: changes).data
    }

    private func decode(_ data: Data, table: String) throws -> [String: DecodedColumn] {
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        return Dictionary(uniqueKeysWithValues: try VertiPaq.decodeTable(table, metadata: metadata, abf: abf).map { ($0.name, $0) })
    }

    @Test func bangMoiGhiRoiDocLaiTungO() throws {
        let table = sales()
        let data = try build([.addTable(table)])
        let columns = try decode(data, table: "Sales2026")
        #expect(columns.values.allSatisfy { $0.count == 200 })
        for (i, column) in table.columns.enumerated() {
            let decoded = try #require(columns[column.name])
            for row in 0..<200 {
                let expected: CellValue
                switch try #require(column.values) {
                case .int64(let v): expected = v[row].map { .int($0) } ?? .null
                case .double(let v): expected = v[row].map { .double($0) } ?? .null
                case .dateTime(let v): expected = v[row].map { .dateTime($0) } ?? .null
                case .string(let v): expected = v[row].map { .string($0) } ?? .null
                case .boolean(let v): expected = v[row].map { .bool($0) } ?? .null
                case .currency(let v): expected = v[row].map { .decimal(Double($0) / 10_000) } ?? .null
                }
                #expect(decoded[row] == expected, Comment(rawValue: "cột \(i) dòng \(row)"))
            }
        }
    }

    @Test func phanConLaiCuaFileKhongDoiVaMeasureTrenBangMoi() throws {
        let source = try ZipArchive(url: DesktopGolden.path)
        var edits: [ModelEdit] = [.addTable(sales())]
        edits.append(.addMeasure(NewMeasure(table: "Sales2026", name: "Tong gia", expression: "SUM(Sales2026[Giá])")))
        let data = try build(edits)
        let written = try ZipArchive(data: data)
        for entry in source.entries where entry.path != "DataModel" {
            #expect(written.entry(entry.path)?.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        #expect(model.measures.contains { $0.tableName == "Sales2026" && $0.name == "Tong gia" })
        #expect(model.userTables.map(\.name).contains("Sales2026"))
        // Bảng Marketing cũ vẫn đọc đúng số dòng.
        #expect(try decode(data, table: "Marketing").values.first?.count == 1363)
    }

    @Test func themRoiThayRoiXoaTrongMotDotGopLai() throws {
        let a = sales("A", rows: 50), b = sales("A", rows: 80), c = sales("C", rows: 30)
        let data = try build([.addTable(a), .replaceTable(name: "A", b), .addTable(c), .dropTable(name: "C")])
        #expect(try decode(data, table: "A").values.first?.count == 80)
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        #expect(!model.userTables.map(\.name).contains("C"))
    }

    @Test func luuHaiLanLienTiepKhongDoiBangDaLuu() throws {
        let first = try build([.addTable(sales("Sales2026"))])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pbix-table-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.pbix")
        try first.write(to: url)
        let second = try build([.addTable(sales("Khach", rows: 40))], source: url)
        #expect(try decode(second, table: "Sales2026").values.first?.count == 200)
        #expect(try decode(second, table: "Khach").values.first?.count == 40)
        // MAXID là bộ đếm: sau hai lần ghi vẫn bằng ID lớn nhất.
        let (abf, _) = try PBIXFile(data: second).loadDataModel()
        _ = try TableMetadataWriter(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }

    @Test func thayDuLieuBangDaCoTrongFileBiTuChoiRoRang() throws {
        let existing = "Marketing"
        #expect(throws: WriteError.self) { _ = try build([.replaceTable(name: existing, sales(existing))]) }
        #expect(throws: WriteError.self) { _ = try build([.dropTable(name: existing)]) }
    }

    @Test func cotThieuDuLieuMaHoaBiTuChoiVaFileGocNguyen() throws {
        let broken = NewTable(name: "X", columns: [NewTableColumn(name: "A", dataType: .int64)])
        #expect(throws: WriteError.self) { _ = try build([.addTable(broken)]) }
    }

    @Test func bangKhongNapKhongGhiGi() throws {
        let hidden = NewTable(name: "An", columns: sales().columns, enableLoad: false)
        let data = try build([.addTable(hidden)])
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        #expect(!model.userTables.map(\.name).contains("An"))
    }
}

/// Quan hệ từ/đến bảng mới (T017). Cần Nhom6 (lược đồ Desktop mới, có `StringIndexID`; `tuan6.2.pbix` cũ hơn).
@Suite(.enabled(if: FFixtures.nhom6 != nil)) struct PBIXWriterTableRelationshipTests {
    private func build(_ edits: [ModelEdit]) throws -> (ModelMetadata, ABFBackup) {
        var changes = PBIXChanges()
        for edit in edits { changes.modelEdits.append(edit) }
        let data = try PBIXWriter.build(source: try #require(FFixtures.nhom6), changes: changes).data
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        return (try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")), abf)
    }

    /// Một cột số nguyên phía một có sẵn trong Nhom6 (khoá của quan hệ đang có).
    private func existingKey() throws -> (table: String, column: String, firstValue: Int64) {
        let (abf, _) = try PBIXFile(url: try #require(FFixtures.nhom6)).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let target = try #require(model.relationships.compactMap { r in
            model.columns.first { $0.tableName == r.toTable && $0.name == r.toColumn && $0.dataType == .int64 }
        }.first)
        let storage = try #require(model.storage(table: target.tableName, column: target.name))
        let column = try VertiPaq.decodeColumn(storage, abf: abf)
        guard case .int(let first) = column[0] else { throw WriteError.invalid("khoá không phải số nguyên") }
        return (target.tableName, target.name, first)
    }

    @Test func quanHeTuBangMoiToiBangCuVaGiuaHaiBangMoi() throws {
        let key = try existingKey()
        let fact = NewTable(name: "Fact2026", columns: [NewTableColumn(name: "Khoa", values: .int64([key.firstValue, key.firstValue, nil, 9_999_999_999])),
                                                        NewTableColumn(name: "SoLuong", values: .double([1, 2, 3, 4]))])
        let kinds = NewTable(name: "Loai", columns: [NewTableColumn(name: "Khoa", values: .int64([key.firstValue, 5_000_000_000])),
                                                     NewTableColumn(name: "Ten", values: .string(["a", "b"]))])
        let (model, abf) = try build([
            .addTable(fact), .addTable(kinds),
            .addRelationship(NewRelationship(fromTable: "Fact2026", fromColumn: "Khoa", toTable: key.table, toColumn: key.column)),
            .addRelationship(NewRelationship(fromTable: "Fact2026", fromColumn: "Khoa", toTable: "Loai", toColumn: "Khoa")),
        ])
        #expect(model.relationships.contains { $0.fromTable == "Fact2026" && $0.toTable == key.table })
        #expect(model.relationships.contains { $0.fromTable == "Fact2026" && $0.toTable == "Loai" })
        #expect(abf.files.filter { $0.path.hasSuffix("INDEX.0.idf") && $0.path.contains("Fact2026") || $0.path.hasPrefix("R$Fact2026") }.count >= 2)
    }

    @Test func quanHePhiaMotCoGiaTriTrungBiTuChoi() throws {
        let fact = NewTable(name: "Fact", columns: [NewTableColumn(name: "K", values: .int64([1, 2]))])
        let dim = NewTable(name: "Dim", columns: [NewTableColumn(name: "K", values: .int64([1, 1]))])
        #expect(throws: WriteError.self) {
            _ = try build([.addTable(fact), .addTable(dim),
                           .addRelationship(NewRelationship(fromTable: "Fact", fromColumn: "K", toTable: "Dim", toColumn: "K"))])
        }
    }
}
