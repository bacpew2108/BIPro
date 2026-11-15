import Foundation
import Testing
@testable import PBIXKit

/// Phase E (T006): lưu T2 với `ModelEdits` và thay phần `DiagramLayout`, trên bản Nhom6 thật (chỉ đọc).
@Suite("Phase E: PBIXWriter model edits", .enabled(if: EditFixture.nhom6 != nil), .serialized) struct PBIXWriterModelTests {
    let source = EditFixture.nhom6!

    private func metadata(_ pbix: PBIXFile) throws -> (ABFBackup, ModelMetadata) {
        let (abf, _) = try pbix.loadDataModel()
        return (abf, try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")))
    }

    @Test func luuT2GhiMoHinhVaGiuNguyenPhanConLai() throws {
        let before = try PBIXFile(url: source)
        let (abfBefore, modelBefore) = try metadata(before)
        let rel = try #require(modelBefore.relationships.first { $0.isActive && $0.crossFilteringBehavior == 1 })
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([
            .addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "COUNTROWS(Dim_Account)+1", dataType: 6)),
            .updateRelationship(name: rel.name, patch: RelationshipPatch(crossFilteringBehavior: 2)),
        ])
        #expect(changes.tier == .metadata)

        let t0 = Date()
        let result = try PBIXWriter.build(source: source, changes: changes)
        let seconds = Date().timeIntervalSince(t0)
        print("KEY T2 Nhom6 build: \(String(format: "%.2f", seconds)) s")
        #expect(result.tier == .metadata)

        let after = try PBIXFile(data: result.data)
        let (abfAfter, modelAfter) = try metadata(after)
        #expect(modelAfter.measures.contains { $0.name == "E_Test" && $0.dataType == .int64 })
        #expect(modelAfter.relationships.first { $0.name == rel.name }?.crossFilteringBehavior == 2)
        #expect(modelAfter.columns == modelBefore.columns)
        // Mọi tệp ABF ngoài metadata.sqlitedb giữ nguyên byte.
        #expect(abfAfter.files.map(\.path) == abfBefore.files.map(\.path))
        for file in abfBefore.files where file.fileName != "metadata.sqlitedb" {
            let other = try #require(abfAfter.files.first { $0.path == file.path })
            #expect(try abfBefore.contents(of: file) == abfAfter.contents(of: other), "\(file.path) phải giữ nguyên")
        }
    }

    @Test func thayPhanDiagramLayout() throws {
        let before = try PBIXFile(url: source)
        let original = try before.archive.read(try #require(before.archive.entry("DiagramLayout")))
        var changes = PBIXChanges()
        let replaced = Data("\u{FEFF}".utf8) + original   // nội dung khác, cùng chỗ
        changes.diagramLayout = replaced
        #expect(changes.tier == .report)
        let result = try PBIXWriter.build(source: source, changes: changes)
        let after = try PBIXFile(data: result.data)
        #expect(try after.archive.read(try #require(after.archive.entry("DiagramLayout"))) == replaced)
        // chỉ bố cục đổi: DataModel không đụng
        let model = try #require(after.archive.entry("DataModel"))
        let old = try #require(before.archive.entry("DataModel"))
        #expect(model.crc32 == old.crc32)
    }

    @Test func diagramLayoutKhongCoThiTuChoi() throws {
        var changes = PBIXChanges()
        changes.diagramLayout = Data([1, 2, 3])
        // đường dẫn thật tồn tại trong Nhom6; thử trên file tổng hợp không có DiagramLayout
        let dir = SyntheticPBIX.temporaryDirectory("e-diagram")
        let url = try SyntheticPBIX.make(in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: WriteError.self) { try PBIXWriter.build(source: url, changes: changes) }
    }

    // MARK: Quan hệ mới và xoá quan hệ (spike S1)

    private func indexFiles(_ abf: ABFBackup) -> [String: Data] {
        var out: [String: Data] = [:]
        for f in abf.files where f.path.hasSuffix("INDEX.0.idf") || f.path.hasSuffix("INDEX.0.idfmeta") {
            out[f.path] = try? abf.contents(of: f)
        }
        return out
    }

    @Test func themQuanHeGhiDuBoChiMucNhuDesktop() throws {
        let (abfBefore, modelBefore) = try metadata(try PBIXFile(url: source))
        let newName = "f4511e83-f9c7-f2c3-5117-e8f8be98a4a1"
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([.addRelationship(NewRelationship(
            name: newName, fromTable: "Fact_Loan", fromColumn: "loan_count", toTable: "Dim_Client", toColumn: "client_key", isActive: false))])
        let result = try PBIXWriter.build(source: source, changes: changes)
        let (abfAfter, modelAfter) = try metadata(try PBIXFile(data: result.data))
        #expect(modelAfter.relationships.count == modelBefore.relationships.count + 1)
        let added = try #require(modelAfter.relationships.first { $0.name == newName })
        #expect(!added.isActive && added.cardinality == "M:1" && added.crossFilteringBehavior == 1)
        // thêm đúng hai tệp chỉ mục; nội dung bằng tệp Desktop ghi ở VM-E3 (cùng quan hệ trên cùng dữ liệu)
        let before = indexFiles(abfBefore), after = indexFiles(abfAfter)
        #expect(after.count == before.count + 2)
        let newFiles = after.filter { before[$0.key] == nil }
        let idf = try #require(newFiles.first { $0.key.hasSuffix(".idf") }?.value)
        let meta = try #require(newFiles.first { $0.key.hasSuffix(".idfmeta") }?.value)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let desktop = root.appendingPathComponent("build/e-out/vme3-r1.pbix")
        if FileManager.default.fileExists(atPath: desktop.path) {
            let desktopFiles = indexFiles(try PBIXFile(url: desktop).loadDataModel().0)
            #expect(desktopFiles.values.contains(idf) && desktopFiles.values.contains(meta), "tệp chỉ mục phải bằng tệp Desktop ghi")
        }
        // mọi tệp ABF khác (ngoài metadata) giữ nguyên
        for file in abfBefore.files where file.fileName != "metadata.sqlitedb" {
            let other = try #require(abfAfter.files.first { $0.path == file.path })
            #expect(try abfBefore.contents(of: file) == abfAfter.contents(of: other))
        }
        // đọc lại bằng bộ đọc thường: lược đồ cột và dữ liệu không đổi (ColumnStorage đọc được)
        #expect(modelAfter.storage.count == modelBefore.storage.count)
    }

    @Test func xoaQuanHeBoBangChiMucCuaNo() throws {
        let (abfBefore, modelBefore) = try metadata(try PBIXFile(url: source))
        let victim = try #require(modelBefore.relationships.first { $0.fromTable == "Fact_Loan" && $0.fromColumn == "loan_profile_key" })
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([.deleteRelationship(name: victim.name)])
        let result = try PBIXWriter.build(source: source, changes: changes)
        let (abfAfter, modelAfter) = try metadata(try PBIXFile(data: result.data))
        #expect(modelAfter.relationships.count == modelBefore.relationships.count - 1)
        #expect(!modelAfter.relationships.contains { $0.name == victim.name })
        #expect(indexFiles(abfAfter).count == indexFiles(abfBefore).count - 2)
        // bảng R$ của nó không còn trong metadata
        let guid = victim.name.replacingOccurrences(of: "-", with: " ")
        #expect(!abfAfter.files.contains { $0.path.contains(guid) })
    }

    @Test func themRoiXoaCungLanLuuKhongDeLaiGi() throws {
        let (abfBefore, modelBefore) = try metadata(try PBIXFile(url: source))
        var changes = PBIXChanges()
        let name = "aaaaaaaa-1111-2222-3333-444444444444"
        changes.modelEdits = ModelEdits([
            .addRelationship(NewRelationship(name: name, fromTable: "Fact_Loan", fromColumn: "loan_count", toTable: "Dim_Client", toColumn: "client_key", isActive: false)),
            .deleteRelationship(name: name),
        ])
        let result = try PBIXWriter.build(source: source, changes: changes)
        let (abfAfter, modelAfter) = try metadata(try PBIXFile(data: result.data))
        #expect(modelAfter.relationships == modelBefore.relationships)
        #expect(Set(abfAfter.files.map(\.path)) == Set(abfBefore.files.map(\.path)))
    }
}
