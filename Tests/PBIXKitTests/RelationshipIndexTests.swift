import Foundation
import Testing
@testable import PBIXKit

/// Phase E (S1, R7): chỉ mục dữ liệu của quan hệ (`R$…INDEX.0.idf` và `.idfmeta`) dựng lại đúng từng byte so với file
/// Power BI Desktop ghi: 14 quan hệ của Nhom6 và quan hệ Desktop tạo ở VM-E3 (`build/e-out/vme3-r1.pbix`).
@Suite("Phase E: RelationshipIndex", .enabled(if: EditFixture.nhom6 != nil)) struct RelationshipIndexTests {
    private func check(_ url: URL, onlyNewest: Bool = false) throws -> Int {
        let (abf, _) = try PBIXFile(url: url).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        var checked = 0
        for relationship in model.relationships where relationship.cardinality == "M:1" {
            let guid = relationship.name.replacingOccurrences(of: "-", with: " ")
            guard let idfFile = abf.files.first(where: { $0.path.contains("$\(guid) (") && $0.path.hasSuffix("INDEX.0.idf") }),
                  let metaFile = abf.files.first(where: { $0.path == idfFile.path + "meta" }),
                  let from = model.storage(table: relationship.fromTable, column: relationship.fromColumn),
                  let to = model.storage(table: relationship.toTable, column: relationship.toColumn) else { continue }
            let rows = try VertiPaq.rowCount(to, abf: abf)
            let values = try RelationshipIndex.values(from: from, to: to, abf: abf)
            let encoded = try RelationshipIndex.encode(values: values, toRowCount: rows)
            #expect(encoded.idf == (try abf.contents(of: idfFile)), "idf của \(relationship.fromTable)[\(relationship.fromColumn)] → \(relationship.toTable)")
            let actualMeta = try abf.contents(of: metaFile)
            if encoded.meta != actualMeta {
                let a = [UInt8](encoded.meta), b = [UInt8](actualMeta)
                print("DIFFMETA mine=\(a.count) actual=\(b.count) first=\(zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }.map { "\($0.offset): \($0.element.0) vs \($0.element.1)" } ?? "none")")
            }
            #expect(encoded.meta == actualMeta, "idfmeta của \(relationship.fromTable)[\(relationship.fromColumn)] → \(relationship.toTable)")
            checked += 1
        }
        return checked
    }

    @Test func nhom6BonQuanHeDungTungByte() throws {
        let checked = try check(try #require(EditFixture.nhom6))
        #expect(checked >= 12, "phải kiểm gần hết 14 quan hệ (đã kiểm \(checked))")
    }

    @Test func quanHeDesktopTaoOVMDungTungByte() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("build/e-out/vme3-r1.pbix")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        #expect(try check(url) >= 13)
    }

    @Test func cotDichCoGiaTriTrungBiTuChoi() throws {
        let url = try #require(EditFixture.nhom6)
        let (abf, _) = try PBIXFile(url: url).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let from = try #require(model.storage(table: "Fact_Loan", column: "client_key"))
        let notUnique = try #require(model.storage(table: "Fact_Loan", column: "loan_count"))   // toàn giá trị 1
        #expect(throws: WriteError.self) { try RelationshipIndex.values(from: from, to: notUnique, abf: abf) }
    }
}
