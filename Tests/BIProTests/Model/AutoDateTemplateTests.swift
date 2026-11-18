// Đợt tồn đọng sau Phase F, T025: mẫu Auto date/time của `AutoDateTime` trùng với cái Desktop 2.159 lưu trong `w8.3.pbix` và
// `vm-f11/f11-desktop.pbix` (cột, biểu thức bảng, quan hệ ngày, variation). Chú thích và cờ bảng kiểm ở PBIXKit (`F2AutoDateGoldenTests`).
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct AutoDateTemplateTests {
    static var files: [URL] { [F2Fixtures.w83, F2Fixtures.desktop("vm-f11", "f11-desktop.pbix")].compactMap { $0 } }

    private func model(_ url: URL) throws -> ModelMetadata {
        let (abf, _) = try PBIXFile(data: try Data(contentsOf: url, options: .alwaysMapped)).loadDataModel()
        return try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }

    @Test(.enabled(if: !files.isEmpty), arguments: files)
    func templateMatchesDesktop(_ url: URL) throws {
        let model = try model(url)
        #expect(model.modelAnnotations[AutoDateTime.modelAnnotation] == "1")
        let dateTables = model.tables.map(\.name)
            .filter { $0.hasPrefix(AutoDateTime.templateTablePrefix) || $0.hasPrefix(AutoDateTime.localTablePrefix) }
        #expect(dateTables.filter { $0.hasPrefix(AutoDateTime.templateTablePrefix) }.count == 1)

        for table in dateTables {
            let columns = model.columns.filter { $0.tableName == table && $0.kind != .rowNumber }
            #expect(columns.count == AutoDateTime.columns.count)
            for expected in AutoDateTime.columns {
                let actual = try #require(columns.first { $0.name == expected.name }, "\(table) thiếu \(expected.name)")
                #expect(actual.expression == expected.expression)
                #expect(actual.dataType == expected.dataType)
                #expect(actual.dataCategory == expected.dataCategory)
                #expect(actual.formatString == expected.formatString)
                #expect(actual.sortByColumnID.flatMap { model.column(id: $0)?.name } == expected.sortBy)
                #expect(actual.isHidden && actual.summarizeBy == 2)
            }
            if table.hasPrefix(AutoDateTime.templateTablePrefix) {
                #expect(model.calculatedTableExpressions[table] == AutoDateTime.templateExpression)
            }
        }

        for variation in model.variations {
            #expect(variation.name == AutoDateTime.variationName)
            #expect(variation.hierarchy.name == AutoDateTime.hierarchyName)
            #expect(model.calculatedTableExpressions[variation.hierarchy.table]
                    == AutoDateTime.localExpression(table: variation.table, column: variation.column))
            let relationship = try #require(model.dateTableRelationships.first { $0.name == variation.relationship })
            #expect(relationship.name == relationship.name.lowercased() && UUID(uuidString: relationship.name) != nil)
            #expect(relationship.joinOnDateBehavior == AutoDateTime.joinOnDateBehavior)
            #expect(relationship.crossFilteringBehavior == AutoDateTime.crossFilteringBehavior)
        }
    }

    @Test func localExpressionEscapesNames() {
        #expect(AutoDateTime.localExpression(table: "O'Brien", column: "a]b")
                == "Calendar(Date(Year(MIN('O''Brien'[a]]b])), 1, 1), Date(Year(MAX('O''Brien'[a]]b])), 12, 31))")
        #expect(AutoDateTime.tableName(prefix: AutoDateTime.localTablePrefix, id: UUID(uuidString: "FB0E2A6F-B4AD-4CEF-8DDA-8E88DC9B733B")!)
                == "LocalDateTable_fb0e2a6f-b4ad-4cef-8dda-8e88dc9b733b")
    }
}
