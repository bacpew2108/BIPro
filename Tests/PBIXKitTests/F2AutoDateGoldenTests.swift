// Đợt tồn đọng sau Phase F, T025: cấu trúc Auto date/time Desktop 2.159 lưu, đọc thôi. Hai file Desktop độc lập phải cùng một mẫu:
// `w8.3.pbix` của người dùng (bảng `Thông tin nhân viên`, `Ngày`) và `vm-f11/f11-desktop.pbix` (VM-F11: Sales, Customers, Table (2)).
// Giá trị mong đợi chép từ docs/phase-f2-evidence/vm-f11/QUAN-SAT.md mục b; `AutoDateTime.swift` (BIPro) dùng đúng mẫu này.
import Foundation
import Testing
@testable import PBIXKit

@Suite struct F2AutoDateGoldenTests {
    /// Một cột của bảng ngày: tên, biểu thức, kiểu (ExplicitDataType), DataCategory, FormatString, cột sắp theo, chú thích TemplateId.
    struct ColumnSpec: Hashable, CustomStringConvertible {
        let name: String, expression: String, dataType: Int, dataCategory: String, formatString: String, sortBy: String, templateId: String
        var description: String { "\(name) = \(expression) [\(dataType)] \(dataCategory) '\(formatString)' sort:\(sortBy) tid:\(templateId)" }
    }

    static let expectedColumns: Set<ColumnSpec> = [
        ColumnSpec(name: "Date", expression: "", dataType: 9, dataCategory: "PaddedDateTableDates", formatString: "General Date", sortBy: "", templateId: ""),
        ColumnSpec(name: "Year", expression: "YEAR([Date])", dataType: 6, dataCategory: "Years", formatString: "0", sortBy: "", templateId: "Year"),
        ColumnSpec(name: "MonthNo", expression: "MONTH([Date])", dataType: 6, dataCategory: "MonthOfYear", formatString: "0", sortBy: "", templateId: "MonthNumber"),
        ColumnSpec(name: "Month", expression: "FORMAT([Date], \"MMMM\")", dataType: 2, dataCategory: "Months", formatString: "", sortBy: "MonthNo", templateId: "Month"),
        ColumnSpec(name: "QuarterNo", expression: "INT(([MonthNo] + 2) / 3)", dataType: 6, dataCategory: "QuarterOfYear", formatString: "0", sortBy: "", templateId: "QuarterNumber"),
        ColumnSpec(name: "Quarter", expression: "\"Qtr \" & [QuarterNo]", dataType: 2, dataCategory: "Quarters", formatString: "", sortBy: "QuarterNo", templateId: "Quarter"),
        ColumnSpec(name: "Day", expression: "DAY([Date])", dataType: 6, dataCategory: "DayOfMonth", formatString: "0", sortBy: "", templateId: "Day"),
    ]

    struct DateTable {
        let id: Int, name: String, isHidden: Bool, showAsVariationsOnly: Bool, isPrivate: Bool, expression: String
        let annotations: [String: String]
    }

    private static func metadata(_ url: URL) throws -> Data {
        let (abf, _) = try PBIXFile(data: try Data(contentsOf: url, options: .alwaysMapped)).loadDataModel()
        return try abf.contents(named: "metadata.sqlitedb")
    }

    private static func annotations(_ db: SQLiteReader, type: Int, id: Int) throws -> [String: String] {
        Dictionary(try db.rows("SELECT Name, Value FROM Annotation WHERE ObjectType = \(type) AND ObjectID = \(id)")
            .map { ($0.string(0) ?? "", $0.string(1) ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    private static func dateTables(_ db: SQLiteReader) throws -> [DateTable] {
        try db.rows("""
            SELECT t.ID, t.Name, t.IsHidden, t.ShowAsVariationsOnly, t.IsPrivate, p.QueryDefinition
            FROM [Table] t JOIN Partition p ON p.TableID = t.ID
            WHERE t.Name LIKE 'LocalDateTable\\_%' ESCAPE '\\' OR t.Name LIKE 'DateTableTemplate\\_%' ESCAPE '\\'
            ORDER BY t.ID
            """).map {
            DateTable(id: $0.int(0), name: $0.string(1) ?? "", isHidden: $0.int(2) != 0, showAsVariationsOnly: $0.int(3) != 0,
                      isPrivate: $0.int(4) != 0, expression: $0.string(5) ?? "", annotations: try annotations(db, type: 3, id: $0.int(0)))
        }
    }

    private static func columns(_ db: SQLiteReader, table: Int) throws -> [ColumnSpec] {
        try db.rows("""
            SELECT c.ID, COALESCE(c.ExplicitName, c.InferredName), COALESCE(c.Expression, ''), c.ExplicitDataType,
                   COALESCE(c.DataCategory, ''), COALESCE(c.FormatString, ''),
                   COALESCE((SELECT COALESCE(s.ExplicitName, s.InferredName) FROM [Column] s WHERE s.ID = c.SortByColumnID), ''),
                   c.IsHidden, c.SummarizeBy
            FROM [Column] c WHERE c.TableID = \(table) AND c.Type <> 3 ORDER BY c.ID
            """).map {
            #expect($0.int(7) == 1, "cột \($0.string(1) ?? "") phải ẩn")
            #expect($0.int(8) == 2, "cột \($0.string(1) ?? "") phải SummarizeBy None")
            let notes = try annotations(db, type: 4, id: $0.int(0))
            #expect(notes["SummarizationSetBy"] == "User")
            return ColumnSpec(name: $0.string(1) ?? "", expression: $0.string(2) ?? "", dataType: $0.int(3),
                              dataCategory: $0.string(4) ?? "", formatString: $0.string(5) ?? "", sortBy: $0.string(6) ?? "",
                              templateId: notes["TemplateId"] ?? "")
        }
    }

    static var files: [URL] {
        [F2Fixtures.w83, F2Fixtures.desktop("vm-f11", "f11-desktop.pbix")].compactMap { $0 }
    }

    @Test(.enabled(if: !files.isEmpty), arguments: files)
    func autoDateStructureMatchesDesktop(_ url: URL) throws {
        try Self.checkStructure(try Self.metadata(url))
    }

    /// Mẫu Auto date/time của Desktop trên một `metadata.sqlitedb` (dùng lại cho file BI Pro ghi, `AutoDateWriteTests`).
    static func checkStructure(_ bytes: Data) throws {
        let db = try SQLiteReader(bytes: bytes)
        let model = try ModelMetadata(sqlite: bytes)
        #expect(model.modelAnnotations["__PBI_TimeIntelligenceEnabled"] == "1")

        let tables = try Self.dateTables(db)
        let templates = tables.filter { $0.name.hasPrefix("DateTableTemplate_") }
        let locals = tables.filter { $0.name.hasPrefix("LocalDateTable_") }
        try #require(templates.count == 1, "mỗi mô hình đúng một bảng mẫu")
        #expect(!locals.isEmpty)

        let template = templates[0]
        #expect(template.isHidden && template.isPrivate && !template.showAsVariationsOnly)
        #expect(template.expression == "Calendar(Date(2015,1,1), Date(2015,1,1))")
        #expect(template.annotations == ["__PBI_TemplateDateTable": "true", "DefaultItem": "DateHierarchy"])
        #expect(Set(try Self.columns(db, table: template.id)) == Self.expectedColumns)

        // Mỗi bảng cục bộ ứng với đúng một Variation; biểu thức lấy khoảng năm từ cột nguồn.
        #expect(model.variations.count == locals.count)
        for local in locals {
            #expect(local.isHidden && local.showAsVariationsOnly && !local.isPrivate)
            #expect(local.annotations == ["__PBI_LocalDateTable": "true"])
            #expect(Set(try Self.columns(db, table: local.id)) == Self.expectedColumns)

            let variation = try #require(model.variations.first { $0.hierarchy.table == local.name })
            #expect(variation.name == "Variation" && variation.isDefault && variation.hierarchy.name == "Date Hierarchy")
            let source = "'\(variation.table)'[\(variation.column)]"
            #expect(local.expression == "Calendar(Date(Year(MIN(\(source))), 1, 1), Date(Year(MAX(\(source))), 12, 31))")

            let relationship = try #require(model.dateTableRelationships.first { $0.name == variation.relationship })
            #expect(UUID(uuidString: relationship.name) != nil, "quan hệ ngày tên là GUID trần: \(relationship.name)")
            #expect(relationship.fromTable == variation.table && relationship.fromColumn == variation.column)
            #expect(relationship.toTable == local.name && relationship.toColumn == "Date")
            #expect(relationship.isActive && relationship.crossFilteringBehavior == 1 && relationship.joinOnDateBehavior == 2)
        }

        // Phân cấp "Date Hierarchy" ở bảng mẫu và mỗi bảng cục bộ, chú thích TemplateId = DateHierarchy.
        for table in tables {
            let hierarchies = try db.rows("SELECT ID, Name, IsHidden FROM Hierarchy WHERE TableID = \(table.id)")
            try #require(hierarchies.count == 1)
            let id = hierarchies[0].int(0)
            #expect(hierarchies[0].string(1) == "Date Hierarchy" && hierarchies[0].int(2) == 0)
            let levels = try db.rows("""
                SELECT l.Name, COALESCE(c.ExplicitName, c.InferredName) FROM Level l JOIN [Column] c ON c.ID = l.ColumnID
                WHERE l.HierarchyID = \(id) ORDER BY l.Ordinal
                """)
            #expect(levels.map { $0.string(0) } == ["Year", "Quarter", "Month", "Day"])
            #expect(levels.map { $0.string(1) } == ["Year", "Quarter", "Month", "Day"])
            #expect(try Self.annotations(db, type: 9, id: id) == ["TemplateId": "DateHierarchy"])
        }

    }
}
