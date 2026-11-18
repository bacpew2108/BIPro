// Phase F, T076 (US5): tài liệu `.pbix` trống dựng từ mẫu DataModel do Desktop 2.159 tạo (VM-F5,
// `docs/phase-f-evidence/vm-f5/QUAN-SAT.md`), đọc lại bằng `PBIXFile`, rồi thêm bảng qua `PBIXWriter.build`.
import Foundation
import Testing
@testable import PBIXKit

struct NewDocumentTests {
    private func model(_ data: Data) throws -> ModelMetadata {
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        return try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }

    @Test func taiLieuTrongMoLaiDuocVaKhongCoBang() throws {
        let data = try NewDocument.blank()
        let file = try PBIXFile(data: data)
        #expect(file.reportFormat == .pbir)
        let metadata = try model(data)
        #expect(metadata.userTables.isEmpty)
        #expect(metadata.measures.isEmpty)
        #expect(metadata.relationships.isEmpty)
        let report = try file.loadReport()
        #expect(report.pages.map(\.displayName) == ["Page 1"])
        #expect(report.pages.first?.visuals.isEmpty == true)
    }

    @Test func taiLieuTrongTheoTapThanhPhanCuaDesktopKhongCoSecurityBindings() throws {
        let archive = try ZipArchive(data: try NewDocument.blank())
        let paths = Set(archive.entries.map(\.path))
        for required in ["Version", "[Content_Types].xml", "Settings", "Metadata", "DataModel",
                         "Report/definition/version.json", "Report/definition/report.json",
                         "Report/definition/pages/pages.json",
                         "Report/StaticResources/SharedResources/BaseThemes/Fluent2-CY26SU10.json"] {
            #expect(paths.contains(required), Comment(rawValue: required))
        }
        #expect(!paths.contains("SecurityBindings"))
        #expect(!paths.contains("DataMashup"))
        let types = String(decoding: try archive.read(try #require(archive.entry("[Content_Types].xml"))), as: UTF8.self)
        #expect(!types.contains("SecurityBindings"))
        #expect(try PBIXFile(data: try NewDocument.blank()).version == "1.32")
    }

    @Test func moHinhTrongBatAutoDateTimeVaCoThuTuTruyVanRong() throws {
        let metadata = try model(try NewDocument.blank())
        #expect(metadata.modelAnnotations["__PBI_TimeIntelligenceEnabled"] == "1")
        #expect(metadata.modelAnnotations["PBI_QueryOrder"] == "[]")
    }

    @Test func haiTaiLieuMoiCoTenTrangKhacNhau() throws {
        let a = try PBIXFile(data: try NewDocument.blank()).loadReport()
        let b = try PBIXFile(data: try NewDocument.blank()).loadReport()
        #expect(a.pages.first?.id != b.pages.first?.id)
    }

    @Test func themBangVaoTaiLieuTrongRoiDocLai() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("newdoc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let blank = dir.appendingPathComponent("blank.pbix")
        try NewDocument.blank().write(to: blank)

        let table = NewTable(name: "sales", columns: [
            NewTableColumn(name: "Region", values: .string(["North", "South", nil, "North"])),
            NewTableColumn(name: "Amount", values: .double([1.5, 2, 3.25, nil])),
            NewTableColumn(name: "Qty", values: .int64([1, nil, 3, 4])),
        ], queryExpression: "let\n    Source = #table({\"Region\"}, {})\nin\n    Source")
        var changes = PBIXChanges()
        changes.modelEdits.append(.addTable(table))
        let data = try PBIXWriter.build(source: blank, changes: changes).data

        let metadata = try model(data)
        #expect(metadata.userTables.map(\.name) == ["sales"])
        #expect(metadata.modelAnnotations["PBI_QueryOrder"] == #"["sales"]"#)
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let columns = Dictionary(uniqueKeysWithValues: try VertiPaq.decodeTable("sales", metadata: metadata, abf: abf).map { ($0.name, $0) })
        let region = try #require(columns["Region"]), amount = try #require(columns["Amount"]), qty = try #require(columns["Qty"])
        #expect((0..<4).map { region[$0] } == [.string("North"), .string("South"), .null, .string("North")])
        #expect((0..<4).map { amount[$0] } == [.double(1.5), .double(2), .double(3.25), .null])
        #expect((0..<4).map { qty[$0] } == [.int(1), .null, .int(3), .int(4)])
    }
}
