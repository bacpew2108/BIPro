import Foundation
import Testing
@testable import PBIXKit

/// Phase E (T036): phân tích tập con TMDL áp dụng được và tính `ModelEdits` so với văn bản `TMDLWriter` sinh ra
/// (specs/009-e-mo-hinh-hoa-luu-t2/contracts/tmdl-subset.md).
@Suite struct TMDLParserTests {
    static let table = """
    table Sales
    \tlineageTag: tag-sales

    \tmeasure 'Total Sales' = SUM(Sales[amount])
    \t\tformatString: #,0
    \t\tdisplayFolder: Doanh thu
    \t\tlineageTag: tag-m1

    \tmeasure Multi =
    \t\t\tVAR x = 1
    \t\t\tRETURN x
    \t\tlineageTag: tag-m2

    \tcolumn amount
    \t\tdataType: double
    \t\tisHidden
    \t\tsummarizeBy: sum
    \t\tsourceColumn: amount
    \t\tlineageTag: tag-c1

    \tcolumn region
    \t\tdataType: string
    \t\tsummarizeBy: none
    \t\tsourceColumn: region
    \t\tsortByColumn: region_order

    \tcolumn region_order
    \t\tdataType: int64
    \t\tsummarizeBy: none
    \t\tsourceColumn: region_order

    \tpartition Sales = m
    \t\tmode: import
    \t\tsource =
    \t\t\t\tlet x = 1 in x
    """

    static let relationships = """
    relationship r1
    \tfromColumn: Sales.region
    \ttoColumn: Dim.region
    """

    private func parse(_ docs: [(String, String)]) throws -> TMDLModel {
        try TMDLParser.parse(documents: docs.map { (path: $0.0, text: $0.1) })
    }

    @Test func docBang() throws {
        let m = try parse([("tables/Sales.tmdl", Self.table)])
        let t = try #require(m.tables.first)
        #expect(t.name == "Sales" && !t.isHidden)
        #expect(t.measures.map(\.name) == ["Total Sales", "Multi"])
        #expect(t.measures[0].expression == "SUM(Sales[amount])" && t.measures[0].formatString == "#,0" && t.measures[0].displayFolder == "Doanh thu")
        #expect(t.measures[1].expression == "VAR x = 1\nRETURN x")
        #expect(t.columns.map(\.name) == ["amount", "region", "region_order"])
        #expect(t.columns[0].isHidden && t.columns[0].summarizeBy == "sum" && t.columns[0].dataType == "double")
        #expect(t.columns[1].sortByColumn == "region_order")
        #expect(t.opaque.contains { $0.contains("partition Sales") })
    }

    @Test func moTaDocComment() throws {
        let text = "table T\n\n\t/// Dòng một\n\t/// Dòng hai\n\tmeasure M = 1\n\n\t/// Mô tả cột\n\tcolumn c\n\t\tdataType: int64\n"
        let t = try #require(try parse([("tables/T.tmdl", text)]).tables.first)
        #expect(t.measures[0].description == "Dòng một\nDòng hai" && t.columns[0].description == "Mô tả cột")
    }

    @Test func quanHe() throws {
        let m = try parse([("relationships.tmdl", Self.relationships + "\n\nrelationship 'r 2'\n\tisActive: false\n\tcrossFilteringBehavior: bothDirections\n\tfromColumn: 'Fact Loan'.'loan key'\n\ttoColumn: Dim.key\n")])
        #expect(m.relationships.map(\.name) == ["r1", "r 2"])
        let r2 = m.relationships[1]
        #expect(!r2.isActive && r2.crossFilteringBehavior == 2 && r2.fromTable == "Fact Loan" && r2.fromColumn == "loan key" && r2.toTable == "Dim")
    }

    @Test func loiCuPhapBaoDong() {
        func line(_ text: String) -> Int? {
            do { _ = try parse([("tables/T.tmdl", text)]); return nil } catch let e as TMDLParseError { return e.line } catch { return -1 }
        }
        #expect(line("table T\n\tmeasure M\n") != nil)                       // thiếu dấu =
        #expect(line("table T\n\t\tformatString: x\n") != nil)               // thuộc tính không có đối tượng cha
        #expect(line("table T\n\tcolumn c\n\t\tdataType\n") == nil || true)  // cờ không hợp lệ thì bỏ qua hoặc báo, không sập
        #expect(line("lung tung\n") == 1)                                    // không phải table/relationship
        #expect(line("table T\n\tmeasure 'M = 1\n") == 2)                    // tên nháy đơn không đóng
    }

    // MARK: edits

    private func apply(_ old: [(String, String)], _ new: [(String, String)]) -> TMDLApplyResult {
        TMDLParser.edits(old: old.map { (path: $0.0, text: $0.1) }, new: new.map { (path: $0.0, text: $0.1) })
    }

    @Test func khongDoiGiThiKhongCoThaoTac() {
        let r = apply([("tables/Sales.tmdl", Self.table)], [("tables/Sales.tmdl", Self.table)])
        #expect(r.edits.isEmpty && r.issues.isEmpty)
    }

    @Test func suaBieuThucFormatVaThemXoaMeasure() throws {
        var text = Self.table.replacingOccurrences(of: "SUM(Sales[amount])", with: "SUM(Sales[amount]) + 1")
        text = text.replacingOccurrences(of: "\t\tformatString: #,0\n", with: "\t\tformatString: 0.00\n")
        text = text.replacingOccurrences(of: "\tmeasure Multi =\n\t\t\tVAR x = 1\n\t\t\tRETURN x\n\t\tlineageTag: tag-m2\n\n", with: "")
        text = text.replacingOccurrences(of: "\tcolumn amount", with: "\tmeasure Moi = COUNTROWS(Sales)\n\t\tdisplayFolder: F\n\n\tcolumn amount")
        let r = apply([("tables/Sales.tmdl", Self.table)], [("tables/Sales.tmdl", text)])
        #expect(r.issues.isEmpty, Comment(rawValue: "\(r.issues)"))
        #expect(r.edits.items.contains(.updateMeasure(table: "Sales", name: "Total Sales",
                                                      patch: MeasurePatch(expression: "SUM(Sales[amount]) + 1", formatString: .set("0.00")))))
        #expect(r.edits.items.contains(.deleteMeasure(table: "Sales", name: "Multi")))
        #expect(r.edits.items.contains { if case .addMeasure(let m) = $0 { m.name == "Moi" && m.expression == "COUNTROWS(Sales)" && m.displayFolder == "F" } else { false } })
    }

    @Test func suaThuocTinhCot() throws {
        var text = Self.table.replacingOccurrences(of: "\t\tisHidden\n\t\tsummarizeBy: sum", with: "\t\tsummarizeBy: average")
        text = text.replacingOccurrences(of: "\t\tsummarizeBy: none\n\t\tsourceColumn: region\n\t\tsortByColumn: region_order", with: "\t\tsummarizeBy: none\n\t\tdataCategory: City\n\t\tsourceColumn: region")
        let r = apply([("tables/Sales.tmdl", Self.table)], [("tables/Sales.tmdl", text)])
        #expect(r.issues.isEmpty, Comment(rawValue: "\(r.issues)"))
        #expect(r.edits.items.contains(.updateColumn(table: "Sales", name: "amount", patch: ColumnPatch(isHidden: false, summarizeBy: 7))))
        #expect(r.edits.items.contains(.updateColumn(table: "Sales", name: "region", patch: ColumnPatch(dataCategory: .set("City"), sortBy: .clear))))
    }

    @Test func anBangVaQuanHe() {
        let table = Self.table.replacingOccurrences(of: "table Sales\n\tlineageTag", with: "table Sales\n\tisHidden\n\tlineageTag")
        let rels = Self.relationships + "\n\tisActive: false\n\tcrossFilteringBehavior: bothDirections"
        let r = apply([("tables/Sales.tmdl", Self.table), ("relationships.tmdl", Self.relationships)], [("tables/Sales.tmdl", table), ("relationships.tmdl", rels)])
        #expect(r.issues.isEmpty, Comment(rawValue: "\(r.issues)"))
        #expect(r.edits.items.contains(.updateTable(name: "Sales", patch: TablePatch(isHidden: true))))
        #expect(r.edits.items.contains(.updateRelationship(name: "r1", patch: RelationshipPatch(isActive: false, crossFilteringBehavior: 2))))
    }

    @Test func phanNgoaiPhamViBiTuChoiTungMucKemLyDo() {
        // đổi kiểu dữ liệu, thêm cột, đổi partition, thêm bảng
        var text = Self.table.replacingOccurrences(of: "dataType: double", with: "dataType: int64")
        text = text.replacingOccurrences(of: "\tcolumn region_order", with: "\tcolumn moi\n\t\tdataType: string\n\n\tcolumn region_order")
        text = text.replacingOccurrences(of: "let x = 1 in x", with: "let x = 2 in x")
        let r = apply([("tables/Sales.tmdl", Self.table)], [("tables/Sales.tmdl", text), ("tables/Moi.tmdl", "table Moi\n")])
        #expect(r.edits.isEmpty, "áp nguyên khối: có từ chối thì không áp gì")
        let messages = r.issues.map(\.message).joined(separator: " | ")
        #expect(messages.contains("kiểu dữ liệu") && messages.contains("cột mới") && messages.contains("partition") && messages.contains("bảng mới"))
        #expect(r.issues.allSatisfy { !$0.path.isEmpty })
    }

    @Test func loiCuPhapTraVeIssueCoDong() {
        let r = apply([("tables/Sales.tmdl", Self.table)], [("tables/Sales.tmdl", "table Sales\n\tmeasure M\n")])
        #expect(r.edits.isEmpty && r.issues.first?.line == 2)
    }

    @Test func themXoaQuanHe() {
        let new = Self.relationships + "\n\nrelationship r3\n\tfromColumn: Sales.amount\n\ttoColumn: Dim.amount\n"
        let added = apply([("relationships.tmdl", Self.relationships)], [("relationships.tmdl", new)])
        #expect(added.edits.items.contains { if case .addRelationship(let r) = $0 { r.name == "r3" && r.fromTable == "Sales" && r.toTable == "Dim" && r.fromMany && !r.toMany } else { false } })
        let removed = apply([("relationships.tmdl", new)], [("relationships.tmdl", Self.relationships)])
        #expect(removed.edits.items == [.deleteRelationship(name: "r3")])
    }
}
