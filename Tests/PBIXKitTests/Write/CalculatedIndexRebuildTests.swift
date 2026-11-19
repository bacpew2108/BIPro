// specs/011, US4 (T048): sửa và xoá cột tính toán còn được dùng: trong quan hệ, là cấp phân cấp, là cột sắp xếp của cột khác. Trước đây bộ ghi
// từ chối (T116); nay dựng lại chỉ mục như Desktop: `R$` của quan hệ, `U$` của phân cấp. Xoá cột thì bỏ kèm quan hệ, cấp phân cấp và cột
// sắp xếp `[SUY ĐOÁN]` (VM-F13 chưa quan sát). Ca không hợp lệ (phía một có giá trị trùng, cột sắp xếp không còn một–một) thì báo lỗi.
// Chạy trên `tuan6.2.pbix` (bảng Marketing 1 363 dòng của Desktop). Phép kiểm chỉ mục: dựng lại từ dữ liệu trong tệp rồi so từng byte.
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: FileManager.default.fileExists(atPath: DesktopGolden.path.path)), .serialized)
struct CalculatedIndexRebuildTests {
    static let rows = 1363

    /// Tệp nền: Marketing có cột tính toán `Nhóm` (i % 7) và `Nhãn` ("L" + i % 7, sắp theo `Nhóm`), `MaDong` (i, duy nhất); phân cấp `PC`
    /// (Nguồn traffic → Nhóm); quan hệ Marketing[Nhóm] → Nhom[K], Ref[Dong] → Marketing[MaDong].
    static let staged: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("calcidx-\(UUID().uuidString).pbix")
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([
            .addTable(NewTable(name: "Nhom", columns: [NewTableColumn(name: "K", values: .int64((0..<7).map { Int64($0) })),
                                                       NewTableColumn(name: "Ten", values: .string((0..<7).map { "N\($0)" }))])),
            .addTable(NewTable(name: "Ref", columns: [NewTableColumn(name: "Dong", values: .int64((0..<200).map { Int64($0 * 3) }))])),
            .addCalculatedColumn(table: "Marketing", name: "Nhóm", expression: "MOD([Conversion], 7)", dataType: .int64),
            .addCalculatedColumn(table: "Marketing", name: "Nhãn", expression: "\"L\" & [Nhóm]", dataType: .string),
            .addCalculatedColumn(table: "Marketing", name: "MaDong", expression: "[Conversion]", dataType: .int64),
            .addRelationship(NewRelationship(name: UUID().uuidString.lowercased(), fromTable: "Marketing", fromColumn: "Nhóm", toTable: "Nhom", toColumn: "K")),
            .addRelationship(NewRelationship(name: UUID().uuidString.lowercased(), fromTable: "Ref", fromColumn: "Dong", toTable: "Marketing", toColumn: "MaDong")),
            .addHierarchy(NewHierarchy(table: "Marketing", name: "PC", levels: [HierarchyLevel(name: "Nguồn", column: "Nguồn traffic"),
                                                                              HierarchyLevel(name: "Nhóm", column: "Nhóm")])),
            .updateColumn(table: "Marketing", name: "Nhãn", patch: ColumnPatch(sortBy: .set("Nhóm"))),
        ])
        changes.calculatedData = [
            "Marketing[Nhóm]": .int64((0..<rows).map { Int64($0 % 7) }),
            "Marketing[Nhãn]": .string((0..<rows).map { "L\($0 % 7)" }),
            "Marketing[MaDong]": .int64((0..<rows).map { Int64($0) }),
        ]
        do { try PBIXWriter.build(source: DesktopGolden.path, changes: changes).data.write(to: url) } catch { Issue.record("tệp nền: \(error)") }
        return url
    }()

    private func build(_ edits: [ModelEdit], _ calculated: [String: VertiPaqWriter.Values]) throws -> URL {
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits(edits)
        changes.calculatedData = calculated
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("calcidx-out-\(UUID().uuidString).pbix")
        try PBIXWriter.build(source: Self.staged, changes: changes).data.write(to: url)
        return url
    }

    /// Mọi `R$` nhiều–một của tệp dựng lại từ dữ liệu cột bằng từng byte tệp đã ghi. Trả số quan hệ đã kiểm.
    static func checkRelationshipIndexes(_ url: URL) throws -> Int {
        let (abf, _) = try PBIXFile(url: url).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        var checked = 0
        for relationship in model.relationships where relationship.cardinality == "M:1" {
            let guid = relationship.name.replacingOccurrences(of: "-", with: " ")
            let idfFile = try #require(abf.files.first { $0.path.contains("$\(guid) (") && $0.path.hasSuffix("INDEX.0.idf") }, "R$ của \(relationship.name)")
            let from = try #require(model.storage(table: relationship.fromTable, column: relationship.fromColumn))
            let to = try #require(model.storage(table: relationship.toTable, column: relationship.toColumn))
            let encoded = try RelationshipIndex.encode(values: try RelationshipIndex.values(from: from, to: to, abf: abf), toRowCount: try VertiPaq.rowCount(to, abf: abf))
            #expect(encoded.idf == (try abf.contents(of: idfFile)), "R$ \(relationship.fromTable)[\(relationship.fromColumn)] → \(relationship.toTable)")
            checked += 1
        }
        return checked
    }

    private func model(_ url: URL) throws -> (ModelMetadata, ABFBackup) {
        let (abf, _) = try PBIXFile(url: url).loadDataModel()
        return (try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")), abf)
    }

    @Test func tepNenCoDuChiMuc() throws {
        #expect(try Self.checkRelationshipIndexes(Self.staged) == 2)
        #expect(try HierarchyIndexWriterTests.check(Self.staged) >= 1)
        let (metadata, _) = try model(Self.staged)
        #expect(metadata.columns.first { $0.tableName == "Marketing" && $0.name == "Nhãn" }?.sortByColumnID
                    == metadata.columns.first { $0.tableName == "Marketing" && $0.name == "Nhóm" }?.id)
    }

    /// Sửa cột vừa là khoá quan hệ phía nhiều, vừa là cấp phân cấp, vừa là cột sắp xếp (giữ một–một): `R$` và `U$` dựng lại theo dữ liệu mới.
    @Test func suaGiuMotMotDungLaiChiMuc() throws {
        let url = try build([.updateCalculatedColumn(table: "Marketing", name: "Nhóm", expression: "MOD([Conversion], 7) + 3", dataType: .int64)],
                            ["Marketing[Nhóm]": .int64((0..<Self.rows).map { Int64($0 % 7 + 3) })])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Self.checkRelationshipIndexes(url) == 2)
        #expect(try HierarchyIndexWriterTests.check(url) >= 1)
        let (metadata, abf) = try model(url)
        let nhom = try VertiPaq.decodeColumn(try #require(metadata.storage(table: "Marketing", column: "Nhóm")), abf: abf)
        #expect((0..<Self.rows).allSatisfy { nhom[$0] == .int(Int64($0 % 7 + 3)) })
        #expect(metadata.relationships.count == 2 && metadata.hierarchies.contains { $0.name == "PC" && $0.levels.count == 2 })
        // Quan hệ giữ tên; cột sắp xếp giữ nguyên.
        #expect(metadata.columns.first { $0.tableName == "Marketing" && $0.name == "Nhãn" }?.sortByColumnID
                    == metadata.columns.first { $0.tableName == "Marketing" && $0.name == "Nhóm" }?.id)
    }

    /// Phía một của quan hệ có giá trị trùng: Desktop không cho (báo cột phía một phải duy nhất).
    @Test func phiaMotTrungBiTuChoi() {
        do {
            _ = try build([.updateCalculatedColumn(table: "Marketing", name: "MaDong", expression: "MOD([Conversion], 3)", dataType: .int64)],
                          ["Marketing[MaDong]": .int64((0..<Self.rows).map { Int64($0 % 3) })])
            Issue.record("phải báo lỗi")
        } catch {
            #expect("\(error)".contains("trùng"), "\(error)")
        }
    }

    /// Cột sắp xếp mất một–một: engine Desktop vẫn nhận (VM-F13), nên bộ ghi lưu được; quan hệ và phân cấp vẫn dựng lại.
    @Test func cotSapXepMatMotMotVanLuuDuoc() throws {
        let url = try build([.updateCalculatedColumn(table: "Marketing", name: "Nhóm", expression: "MOD([Conversion], 5)", dataType: .int64)],
                            ["Marketing[Nhóm]": .int64((0..<Self.rows).map { Int64($0 % 5) })])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Self.checkRelationshipIndexes(url) == 2)
        #expect(try HierarchyIndexWriterTests.check(url) >= 1)
    }

    /// Xoá cột: quan hệ dùng nó bị bỏ (kèm `R$`), phân cấp còn cấp khác thì giữ và dựng lại `U$`, cột sắp theo nó về sắp mặc định.
    @Test func xoaBoKemQuanHePhanCapCotSapXep() throws {
        let url = try build([.deleteCalculatedColumn(table: "Marketing", name: "Nhóm")], [:])
        defer { try? FileManager.default.removeItem(at: url) }
        let (metadata, abf) = try model(url)
        #expect(!metadata.columns.contains { $0.tableName == "Marketing" && $0.name == "Nhóm" })
        #expect(metadata.relationships.count == 1 && metadata.relationships[0].toColumn == "MaDong")
        #expect(try Self.checkRelationshipIndexes(url) == 1)
        let pc = try #require(metadata.hierarchies.first { $0.name == "PC" })
        #expect(pc.levels.map(\.columnName) == ["Nguồn traffic"])
        #expect(try HierarchyIndexWriterTests.check(url) >= 1)
        #expect(metadata.columns.first { $0.tableName == "Marketing" && $0.name == "Nhãn" }.map { $0.sortByColumnID ?? 0 } == 0)
        #expect(!abf.files.contains { $0.path.contains("Nhóm (") })
    }

    /// Xoá cột là cấp duy nhất còn lại: phân cấp bị xoá cùng `U$`.
    @Test func xoaCapCuoiXoaPhanCap() throws {
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([.dropHierarchy(table: "Marketing", name: "PC"),
                                         .addHierarchy(NewHierarchy(table: "Marketing", name: "Chi Nhóm", levels: [HierarchyLevel(name: "Nhóm", column: "Nhóm")]))])
        let one = FileManager.default.temporaryDirectory.appendingPathComponent("calcidx-one-\(UUID().uuidString).pbix")
        defer { try? FileManager.default.removeItem(at: one) }
        try PBIXWriter.build(source: Self.staged, changes: changes).data.write(to: one)
        var drop = PBIXChanges()
        drop.modelEdits = ModelEdits([.deleteCalculatedColumn(table: "Marketing", name: "Nhóm")])
        let (metadata, abf) = try { () throws -> (ModelMetadata, ABFBackup) in
            let data = try PBIXWriter.build(source: one, changes: drop).data
            let (abf, _) = try PBIXFile(data: data).loadDataModel()
            return (try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")), abf)
        }()
        #expect(!metadata.hierarchies.contains { $0.name == "Chi Nhóm" })
        #expect(!abf.files.contains { $0.path.contains("U$") && $0.path.contains("Chi Nhóm") })
    }
}
