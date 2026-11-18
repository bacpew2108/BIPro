// Đợt tồn đọng sau Phase F, T030: chỉ mục `U$` của phân cấp người dùng. Dựng lại `U$` từ dữ liệu các cột cấp của file Desktop 2.159 rồi so
// từng byte tệp `.idf`/`.idfmeta`, cùng `LevelDefinition` và `StructureType`: 4 phân cấp ngày của `vm-f11/f11-desktop.pbix` (bảng mẫu một
// dòng, ba bảng ngày cục bộ) và 6 phân cấp của Nhom6 (chuỗi có dấu, cột sắp theo, cấp có giá trị trùng dưới nhiều cha).
import Foundation
import Testing
@testable import PBIXKit

@Suite struct HierarchyIndexWriterTests {
    struct Loaded {
        let abf: ABFBackup
        let metadata: ModelMetadata
        let db: SQLiteReader
    }

    static func load(_ url: URL) throws -> Loaded {
        let (abf, _) = try PBIXFile(data: try Data(contentsOf: url, options: .alwaysMapped)).loadDataModel()
        let sqlite = try abf.contents(named: "metadata.sqlitedb")
        return Loaded(abf: abf, metadata: try ModelMetadata(sqlite: sqlite), db: try SQLiteReader(bytes: sqlite))
    }

    /// Mọi phân cấp: (bảng, ID bảng, tên, ID phân cấp, LevelDefinition, StructureType, các cột cấp theo thứ tự).
    static func hierarchies(_ m: Loaded) throws -> [(table: String, tableID: Int, name: String, id: Int, definition: String, structure: Int, levels: [Int])] {
        try m.db.rows("""
            SELECT t.Name, t.ID, h.Name, h.ID, s.LevelDefinition, s.StructureType FROM Hierarchy h JOIN [Table] t ON h.TableID = t.ID
            JOIN HierarchyStorage s ON s.HierarchyID = h.ID ORDER BY h.ID
            """).map { row in
            let levels = try m.db.rows("SELECT ColumnID FROM Level WHERE HierarchyID = \(row.int(3)) ORDER BY Ordinal").map { $0.int(0) }
            return (row.string(0)!, row.int(1), row.string(2)!, row.int(3), row.string(4)!, row.int(5), levels)
        }
    }

    static func levelsFromABF(_ m: Loaded, levels: [Int]) throws -> [HierarchyIndex.Level] {
        try levels.map { id in
            let column = try #require(m.metadata.columns.first { $0.id == id })
            let storage = try #require(m.metadata.storage(table: column.tableName).first { $0.columnName == column.name })
            let sortBy = try column.sortByColumnID.flatMap { sid -> (ModelMetadata.ColumnStorage, Int)? in
                guard sid != 0, let other = m.metadata.columns.first(where: { $0.id == sid }) else { return nil }
                return (try #require(m.metadata.storage(table: other.tableName).first { $0.columnName == other.name }), sid)
            }
            return try HierarchyIndex.level(storage, columnID: id, sortBy: sortBy.map { (column: $0.0, id: $0.1) }, abf: m.abf)
        }
    }

    static func desktopFiles(_ m: Loaded, hierarchy: String, id: Int, column: String) throws -> (idf: Data, meta: Data) {
        let name = ".U$"
        let suffix = "$\(hierarchy) (\(id)).\(column).0.idf"
        let file = try #require(m.abf.files.first { $0.fileName.contains(name) && $0.fileName.hasSuffix(suffix) })
        return (m.abf.contents(of: file), try m.abf.contents(named: file.fileName + "meta"))
    }

    static func check(_ url: URL) throws -> Int {
        let m = try load(url)
        var checked = 0
        for h in try hierarchies(m) {
            let nodes = try HierarchyIndex.build(try levelsFromABF(m, levels: h.levels))
            // Tên lưu trữ của cột (`ColumnStorage.Name`, Desktop đổi `_` thành dấu cách).
            let names = try h.levels.map { id in try #require(try m.db.rows("SELECT Name FROM ColumnStorage WHERE ColumnID = \(id)").first?.string(0)) }
            #expect(HierarchyIndex.levelDefinition(names, starts: nodes.levelStarts) == h.definition, "\(h.table)/\(h.name)")
            #expect(nodes.structureType == h.structure, "\(h.table)/\(h.name)")
            for file in HierarchyIndex.encode(nodes) {
                let desktop = try desktopFiles(m, hierarchy: h.name, id: h.id, column: file.column)
                #expect(file.idf == desktop.idf, "\(h.table)/\(h.name) \(file.column).idf")
                #expect(file.meta == desktop.meta, "\(h.table)/\(h.name) \(file.column).idfmeta")
            }
            checked += 1
        }
        return checked
    }

    @Test(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil))
    func f11DungTungByte() throws {
        #expect(try Self.check(try #require(F2Fixtures.desktop("vm-f11", "f11-desktop.pbix"))) == 4)
    }

    @Test(.enabled(if: F2Fixtures.nhom6 != nil))
    func nhom6DungTungByte() throws {
        #expect(try Self.check(try #require(F2Fixtures.nhom6)) == 6)
    }

    @Test(.enabled(if: F2Fixtures.w83 != nil))
    func w83DungTungByte() throws {
        #expect(try Self.check(try #require(F2Fixtures.w83)) > 0)
    }

    /// Đường bộ nhớ (bảng BI Pro sắp ghi): giá trị của bảng ngày cục bộ đọc lại từ f11 cho cùng cây như Desktop.
    @Test(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil))
    func tuGiaTriTrongBoNho() throws {
        let m = try Self.load(try #require(F2Fixtures.desktop("vm-f11", "f11-desktop.pbix")))
        let h = try #require(try Self.hierarchies(m).first { $0.table.hasPrefix("LocalDateTable_") })
        func values(_ id: Int) throws -> VertiPaqWriter.Values {
            let c = try #require(m.metadata.columns.first { $0.id == id })
            let decoded = try VertiPaq.decodeColumn(try #require(m.metadata.storage(table: c.tableName).first { $0.columnName == c.name }), abf: m.abf)
            return switch c.dataType {
            case .string: .string((0..<decoded.count).map { if case .string(let s) = decoded[$0] { s } else { nil } })
            default: .int64((0..<decoded.count).map { if case .int(let i) = decoded[$0] { i } else { nil } })
            }
        }
        let levels = try h.levels.map { id in
            let c = try #require(m.metadata.columns.first { $0.id == id })
            return try HierarchyIndex.level(try values(id), sortBy: try c.sortByColumnID.map { try values($0) })
        }
        let expected = try HierarchyIndex.build(try Self.levelsFromABF(m, levels: h.levels))
        #expect(try HierarchyIndex.build(levels) == expected)
    }

    /// `MetadataWriter` qua `PBIXWriter`: xoá phân cấp "Địa lý KH" của Nhom6 rồi thêm lại đúng các cấp đó. Tệp `U$` mới bằng từng byte tệp
    /// Desktop đã ghi, `HierarchyStorage` như cũ; tệp `U$` cũ không còn. Xoá thôi thì phân cấp cùng bảng `U$` mất hẳn.
    @Test(.enabled(if: F2Fixtures.nhom6 != nil))
    func nhom6XoaRoiThemLaiPhanCapQuaBoGhi() throws {
        let source = try #require(F2Fixtures.nhom6)
        let before = try Self.load(source)
        let original = try #require(before.metadata.hierarchies.first { $0.tableName == "Dim_Client" && $0.name == "Địa lý KH" })
        let old = try #require(try Self.hierarchies(before).first { $0.table == "Dim_Client" && $0.name == "Địa lý KH" })
        let oldFiles = try ["MULTI_LEVEL_ID", "PARENT_POS", "FIRST_CHILD_POS", "CHILD_COUNT"].map {
            try Self.desktopFiles(before, hierarchy: old.name, id: old.id, column: $0)
        }
        let levels = original.levels.map { HierarchyLevel(name: $0.name, column: $0.columnName) }

        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([.dropHierarchy(table: "Dim_Client", name: "Địa lý KH"),
                                         .addHierarchy(NewHierarchy(table: "Dim_Client", name: "Địa lý KH", levels: levels))])
        let afterURL = try Self.write(PBIXWriter.build(source: source, changes: changes).data)
        defer { try? FileManager.default.removeItem(at: afterURL) }
        let after = try Self.load(afterURL)
        let added = try #require(try Self.hierarchies(after).first { $0.table == "Dim_Client" && $0.name == "Địa lý KH" })
        #expect(added.id != old.id)
        #expect(added.definition == old.definition && added.structure == old.structure && added.levels == old.levels)
        #expect(after.metadata.hierarchies.first { $0.tableName == "Dim_Client" && $0.name == "Địa lý KH" }?.levels.map { [$0.name, $0.columnName] }
            == original.levels.map { [$0.name, $0.columnName] })
        for (column, desktop) in zip(["MULTI_LEVEL_ID", "PARENT_POS", "FIRST_CHILD_POS", "CHILD_COUNT"], oldFiles) {
            let mine = try Self.desktopFiles(after, hierarchy: added.name, id: added.id, column: column)
            #expect(mine.idf == desktop.idf && mine.meta == desktop.meta, "\(column)")
        }
        #expect(!after.abf.files.contains { $0.path.contains("$Địa lý KH (\(old.id))") })
        #expect(after.abf.files.count == before.abf.files.count)
        // Dòng lưu trữ của U$ mới đọc lại được đầy đủ (mỗi cột một ColumnStorage, mỗi tệp một StorageFile).
        let storageFiles = try after.db.rows("""
            SELECT COUNT(*) FROM StorageFile s JOIN StorageFolder f ON f.ID = s.StorageFolderID WHERE f.Path LIKE '%$Địa lý KH (\(added.id))$%'
            """).first?.int(0)
        #expect(storageFiles == 8)

        var dropOnly = PBIXChanges()
        dropOnly.modelEdits = ModelEdits([.dropHierarchy(table: "Dim_Client", name: "Địa lý KH")])
        let droppedURL = try Self.write(PBIXWriter.build(source: source, changes: dropOnly).data)
        defer { try? FileManager.default.removeItem(at: droppedURL) }
        let dropped = try Self.load(droppedURL)
        #expect(dropped.metadata.hierarchies.count == before.metadata.hierarchies.count - 1)
        #expect(dropped.abf.files.count == before.abf.files.count - 8)
        #expect(try dropped.db.rows("SELECT COUNT(*) FROM [Table] WHERE Name LIKE 'U$%Địa lý KH%'").first?.int(0) == 0)
    }

    /// Phân cấp ngày đang được `Variation` dùng thì không xoá được; tên trùng hay cột lạ bị từ chối.
    @Test(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil))
    func tuChoiKhiConVariationHoacSai() throws {
        let m = try Self.load(try #require(F2Fixtures.desktop("vm-f11", "f11-desktop.pbix")))
        let local = try #require(try Self.hierarchies(m).first { $0.table.hasPrefix("LocalDateTable_") })
        var writer = try MetadataWriter(sqlite: try m.abf.contents(named: "metadata.sqlitedb"))
        #expect(throws: WriteError.self) { try writer.apply(.dropHierarchy(table: local.table, name: "Date Hierarchy")) }
        writer.hierarchyLevelsProvider = { _, levels in try levels.map { _ in try HierarchyIndex.level(.string(["a"])) } }
        #expect(throws: WriteError.self) {
            try writer.apply(.addHierarchy(NewHierarchy(table: local.table, name: "Date Hierarchy", levels: [HierarchyLevel(name: "Y", column: "Year")])))
        }
        #expect(throws: WriteError.self) {
            try writer.apply(.addHierarchy(NewHierarchy(table: "Sales", name: "H", levels: [HierarchyLevel(name: "X", column: "Không có")])))
        }
    }

    static func write(_ data: Data) throws -> URL {
        let url = try F2Fixtures.outputDirectory("t030").appendingPathComponent("\(UUID().uuidString).pbix")
        try data.write(to: url)
        return url
    }

    @Test func cayNhoTuDungTay() throws {
        // A/x, A/y, B/x: x nằm dưới hai cha nên StructureType 2.
        let nodes = try HierarchyIndex.build([
            try HierarchyIndex.level(.string(["B", "A", "A"])),
            try HierarchyIndex.level(.string(["x", "y", "x"])),
        ])
        // Mã: B=3, A=4; x=3, y=4. Thứ tự: A, B; dưới A: x, y; dưới B: x.
        #expect(nodes.multiLevelID == [4, 3, 3, 4, 3])
        #expect(nodes.parentPosition == [0, 0, 1, 1, 2])
        #expect(nodes.firstChildPosition == [3, 5, 0, 0, 0])
        #expect(nodes.childCount == [3, 2, 0, 0, 0])
        #expect(nodes.levelStarts == [0, 2])
        #expect(nodes.structureType == 2)
        #expect(HierarchyIndex.levelDefinition(["L1 (10)", "L2 (11)"], starts: nodes.levelStarts) == "$L1 (10)$0$L2 (11)$2$")
        // Giá trị trống là một nút (mã 2), đứng đầu.
        let blank = try HierarchyIndex.build([try HierarchyIndex.level(.string(["a", nil]))])
        #expect(blank.multiLevelID == [2, 3])
        #expect(blank.structureType == 1)
    }
}
