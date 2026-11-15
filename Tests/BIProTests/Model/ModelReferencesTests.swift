import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T011): ai đang dùng một measure hoặc cột (để chặn xoá và đổi tên).
@Suite("Phase E: ModelReferences", .enabled(if: EFixtures.metadata != nil)) struct ModelReferencesTests {
    let model = EFixtures.metadata!

    private func visual(_ json: String, label: String = "visual v1 (trang p1)") throws -> ModelDocument {
        ModelDocument(label: label, json: try JSONValue.parse(Data(json.utf8)))
    }

    private func measureField(_ entity: String, _ property: String) -> String {
        #"{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"\#(entity)"}},"Property":"\#(property)"}},"queryRef":"\#(entity).\#(property)"}"#
    }

    @Test func measureDuocMeasureKhacDungTrongDAX() throws {
        // tìm measure được measure khác nhắc tới bằng [Tên]
        let all = model.measures
        let target = try #require(all.first { m in
            all.contains { $0.name != m.name && DAXEngine.references(in: $0.expression).contains { $0.name == m.name && ($0.table == nil || $0.table == m.tableName) } }
        })
        let usages = ModelReferences.usages(ofMeasure: target.tableName, name: target.name, in: model, documents: [])
        #expect(usages.contains { $0.kind == .measure })
        #expect(!usages.contains { $0.detail.contains("[\(target.name)]") && $0.kind == .measure && $0.detail.hasPrefix("\(target.tableName)[\(target.name)]") },
                "không tính chính nó")
    }

    @Test func measureMoiKhongAiDung() throws {
        let edited = try model.applying(ModelEdits([.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "1"))]))
        #expect(ModelReferences.usages(ofMeasure: "Dim_Account", name: "E_Test", in: edited, documents: []).isEmpty)
    }

    @Test func visualBookmarkVaTrangDungMeasure() throws {
        let docs = [
            try visual(#"{"visual":{"query":{"queryState":{"Values":{"projections":[\#(measureField("Dim_Account", "E_Test"))]}}}}}"#),
            try visual(#"{"filterConfig":{"filters":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Dim_Account"}},"Property":"E_Test"}}}]}}"#, label: "bộ lọc trang p2"),
            try visual(#"{"visual":{"query":{"queryState":{"Values":{"projections":[\#(measureField("Dim_Account", "Khac"))]}}}}}"#, label: "visual khác"),
        ]
        let usages = ModelReferences.usages(ofMeasure: "Dim_Account", name: "E_Test", in: model, documents: docs)
        #expect(usages.map(\.detail).contains("visual v1 (trang p1)"))
        #expect(usages.map(\.detail).contains("bộ lọc trang p2"))
        #expect(!usages.map(\.detail).contains("visual khác"))
        #expect(usages.allSatisfy { $0.kind == .document })
    }

    @Test func cotLaDauQuanHeHoacCotSapXep() throws {
        let rel = try #require(model.relationships.first)
        let usages = ModelReferences.usages(ofColumn: rel.fromTable, name: rel.fromColumn, in: model, documents: [])
        #expect(usages.contains { $0.kind == .relationship })
        // cột là đích sắp xếp của cột khác
        if let sorted = model.columns.first(where: { $0.sortByColumnID != nil }),
           let target = model.columns.first(where: { $0.id == sorted.sortByColumnID }) {
            let sortUsages = ModelReferences.usages(ofColumn: target.tableName, name: target.name, in: model, documents: [])
            #expect(sortUsages.contains { $0.kind == .sortBy })
        }
    }

    @Test func cotDuocDAXVaVisualNhacToi() throws {
        let column = try #require(model.columns.first { c in
            c.kind == .data && model.measures.contains { DAXEngine.references(in: $0.expression).contains { $0.table == c.tableName && $0.name == c.name } }
        })
        let doc = try visual(#"{"visual":{"query":{"queryState":{"Category":{"projections":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"\#(column.tableName)"}},"Property":"\#(column.name)"}}}]}}}}}"#)
        let usages = ModelReferences.usages(ofColumn: column.tableName, name: column.name, in: model, documents: [doc])
        #expect(usages.contains { $0.kind == .measure } && usages.contains { $0.kind == .document })
    }

    @Test func cotCuaPhanCapDuocBaoLaDangDung() throws {
        let hierarchy = try #require(model.hierarchies.first { !$0.levels.isEmpty })
        let level = hierarchy.levels[0]
        let usages = ModelReferences.usages(ofColumn: hierarchy.tableName, name: level.columnName, in: model, documents: [])
        #expect(usages.contains { $0.kind == .hierarchy })
    }

    @Test func thongBaoRutGonKhiQuaNhieuNoiDung() {
        let usages = (1...13).map { ModelUsage(kind: .document, detail: "visual \($0)") }
        let text = ModelReferences.message(usages, what: "measure E_Test")
        #expect(text.contains("visual 1") && text.contains("visual 10") && !text.contains("visual 11"))
        #expect(text.contains("và 3 nơi nữa"))
        #expect(ModelReferences.message([ModelUsage(kind: .document, detail: "visual a")], what: "x").contains("visual a"))
    }
}
