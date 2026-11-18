// Đợt tồn đọng sau Phase F, T031: ghi bộ bảng ngày cục bộ của Auto date/time qua `PBIXWriter` (bảng tính toán có cờ và chú thích, cột ẩn
// có chú thích, phân cấp "Date Hierarchy", quan hệ chỉ so phần ngày, `Variation`, chú thích mô hình). Trên `vm-f11/f11-desktop.pbix`: bỏ bộ
// bảng ngày của `Customers` rồi dựng lại từ cùng dữ liệu, file ghi ra phải theo đúng mẫu Desktop (`F2AutoDateGoldenTests.checkStructure`),
// chỉ mục `R$` và `U$` mới trùng từng byte tệp Desktop đã ghi.
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil)) struct AutoDateWriteTests {
    typealias Loaded = HierarchyIndexWriterTests.Loaded

    static var source: URL { F2Fixtures.desktop("vm-f11", "f11-desktop.pbix")! }

    /// Thao tác dựng bảng ngày cục bộ `local` cho `table[column]`, theo thứ tự T032 sẽ sinh: bảng và cột trước, cờ bảng sau cùng
    /// (bộ ghi đặt `SystemFlags = 2` cho mọi cột đã có), rồi phân cấp, quan hệ, variation.
    static func localDateEdits(table: String, column: String, local: String, relationship: String) -> [ModelEdit] {
        let source = "'\(table)'[\(column)]"
        let expression = "Calendar(Date(Year(MIN(\(source))), 1, 1), Date(Year(MAX(\(source))), 12, 31))"
        let specs = F2AutoDateGoldenTests.expectedColumns.sorted { order($0.name) < order($1.name) }
        var edits: [ModelEdit] = [.addCalculatedTable(name: local, expression: expression,
                                                      columns: [ColumnSignature(name: "Date", dataType: .dateTime, sourceColumn: "[Date]")])]
        for spec in specs where spec.name != "Date" {
            edits.append(.addCalculatedColumn(table: local, name: spec.name, expression: spec.expression,
                                              dataType: ModelMetadata.DataType(rawValue: spec.dataType)!))
        }
        for spec in specs {
            var annotations: [String: Assignment<String>] = ["SummarizationSetBy": .set("User")]
            if !spec.templateId.isEmpty { annotations["TemplateId"] = .set(spec.templateId) }
            edits.append(.updateColumn(table: local, name: spec.name, patch: ColumnPatch(
                isHidden: true, formatString: spec.formatString.isEmpty ? nil : .set(spec.formatString), summarizeBy: 2,
                dataCategory: .set(spec.dataCategory), sortBy: spec.sortBy.isEmpty ? nil : .set(spec.sortBy), annotations: annotations)))
        }
        edits += [
            .updateTable(name: local, patch: TablePatch(isHidden: true, showAsVariationsOnly: true, annotations: ["__PBI_LocalDateTable": .set("true")])),
            .addHierarchy(NewHierarchy(table: local, name: "Date Hierarchy",
                                       levels: ["Year", "Quarter", "Month", "Day"].map { HierarchyLevel(name: $0, column: $0) },
                                       annotations: ["TemplateId": "DateHierarchy"])),
            .addRelationship(NewRelationship(name: relationship, fromTable: table, fromColumn: column, toTable: local, toColumn: "Date",
                                             joinOnDateBehavior: 2)),
            .addVariation(table: table, column: column, relationship: relationship, hierarchy: HierarchyRef(table: local, name: "Date Hierarchy")),
            .setModelAnnotation(name: "__PBI_TimeIntelligenceEnabled", value: "1"),
        ]
        return edits
    }

    private static func order(_ name: String) -> Int { ["Date", "Year", "MonthNo", "Month", "QuarterNo", "Quarter", "Day"].firstIndex(of: name) ?? 99 }

    /// Giá trị các cột của bảng ngày cục bộ có sẵn, làm giá trị đã tính cho bảng mới (cùng khoảng năm nên cùng dữ liệu).
    static func values(of local: String, as newName: String, in m: Loaded) throws -> [String: VertiPaqWriter.Values] {
        var out: [String: VertiPaqWriter.Values] = [:]
        for decoded in try VertiPaq.decodeTable(local, metadata: m.metadata, abf: m.abf) {
            let cells = (0..<decoded.count).map { decoded[$0] }
            let values: VertiPaqWriter.Values
            switch try #require(m.metadata.columns.first { $0.tableName == local && $0.name == decoded.name }).dataType {
            case .string: values = .string(cells.map { if case .string(let s) = $0 { s } else { nil } })
            case .dateTime: values = .dateTime(cells.map { if case .dateTime(let d) = $0 { d } else { nil } })
            default: values = .int64(cells.map { if case .int(let i) = $0 { i } else { nil } })
            }
            out["\(newName)[\(decoded.name)]"] = values
        }
        return out
    }

    static func indexFile(_ m: Loaded, relationship: String) throws -> Data {
        let spaced = relationship.replacingOccurrences(of: "-", with: " ")
        let file = try #require(m.abf.files.first { $0.fileName.contains("$\(spaced) (") && $0.fileName.hasSuffix(".INDEX.0.idf") })
        return m.abf.contents(of: file)
    }

    @Test func dungLaiBangNgayCucBoCuaCustomersNhuDesktop() throws {
        let before = try HierarchyIndexWriterTests.load(Self.source)
        let variation = try #require(before.metadata.variations.first { $0.table == "Customers" })
        let oldLocal = variation.hierarchy.table
        let oldHierarchy = try #require(try HierarchyIndexWriterTests.hierarchies(before).first { $0.table == oldLocal })
        let oldIndex = try Self.indexFile(before, relationship: variation.relationship)
        let columnsU = ["MULTI_LEVEL_ID", "PARENT_POS", "FIRST_CHILD_POS", "CHILD_COUNT"]
        let oldU = try columnsU.map { try HierarchyIndexWriterTests.desktopFiles(before, hierarchy: oldHierarchy.name, id: oldHierarchy.id, column: $0) }

        let local = "LocalDateTable_" + UUID().uuidString.lowercased(), relationship = UUID().uuidString.lowercased()
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits([
            .dropVariation(table: "Customers", column: variation.column),
            .deleteRelationship(name: variation.relationship),
            .dropHierarchy(table: oldLocal, name: "Date Hierarchy"),
            .dropTable(name: oldLocal),
        ] + Self.localDateEdits(table: "Customers", column: variation.column, local: local, relationship: relationship))
        changes.calculatedData = try Self.values(of: oldLocal, as: local, in: before)
        let url = try HierarchyIndexWriterTests.write(PBIXWriter.build(source: Self.source, changes: changes).data)
        defer { try? FileManager.default.removeItem(at: url) }
        let after = try HierarchyIndexWriterTests.load(url)

        // Mẫu Desktop: bảng mẫu, ba bảng cục bộ (một bảng mới), cột, chú thích, phân cấp, quan hệ, variation.
        try F2AutoDateGoldenTests.checkStructure(try after.abf.contents(named: "metadata.sqlitedb"))
        #expect(!after.metadata.tables.contains { $0.name == oldLocal })
        #expect(after.metadata.tables.first { $0.name == local }.map { !$0.isUserTable && $0.systemFlags == 2 } == true)
        #expect(after.metadata.userTables.map(\.name) == before.metadata.userTables.map(\.name))
        #expect(after.metadata.relationships == before.metadata.relationships)
        #expect(after.metadata.variations.count == before.metadata.variations.count)
        let added = try #require(after.metadata.variations.first { $0.table == "Customers" })
        #expect(added.relationship == relationship && added.hierarchy == HierarchyRef(table: local, name: "Date Hierarchy") && added.isDefault)
        let rel = try #require(after.metadata.dateTableRelationships.first { $0.name == relationship })
        #expect(rel.joinOnDateBehavior == 2 && rel.isActive && rel.crossFilteringBehavior == 1 && rel.cardinality == "M:1")

        // Dòng lưu trữ như Desktop (f11): `SystemFlags` 2 ở bảng, phân vùng và mọi cột; `Date` kiểu tường minh 9; `DefinitionType` 2.
        let tableID = try #require(after.metadata.tables.first { $0.name == local }?.id)
        #expect(try after.db.rows("SELECT SystemFlags FROM Partition WHERE TableID = \(tableID)").map { $0.int(0) } == [2])
        #expect(Set(try after.db.rows("SELECT SystemFlags FROM [Column] WHERE TableID = \(tableID)").map { $0.int(0) }) == [2])
        #expect(try after.db.rows("SELECT ExplicitDataType, InferredDataType FROM [Column] WHERE TableID = \(tableID) AND Type = 4")
            .map { [$0.int(0), $0.int(1)] } == [[9, 9]])
        #expect(try after.db.rows("""
            SELECT s.DefinitionType FROM RelationshipStorage s JOIN Relationship r ON r.ID = s.RelationshipID WHERE r.Name = '\(relationship)'
            """).map { $0.int(0) } == [2])
        #expect(try after.db.rows("SELECT v.Name, v.DefaultColumnID, v.IsDefault, v.Description FROM Variation v JOIN [Column] c ON c.ID = v.ColumnID WHERE c.TableID = (SELECT ID FROM [Table] WHERE Name = 'Customers')")
            .map { "\($0.string(0) ?? "")|\($0.int(1))|\($0.int(2))|\($0.string(3) ?? "nil")" } == ["Variation|0|1|nil"])

        // Chỉ mục quan hệ và phân cấp dựng từ cùng dữ liệu nên trùng từng byte tệp Desktop.
        #expect(try Self.indexFile(after, relationship: relationship) == oldIndex)
        let newHierarchy = try #require(try HierarchyIndexWriterTests.hierarchies(after).first { $0.table == local })
        #expect(newHierarchy.definition.split(separator: "$").count == oldHierarchy.definition.split(separator: "$").count)
        #expect(newHierarchy.structure == oldHierarchy.structure)
        for (column, desktop) in zip(columnsU, oldU) {
            let mine = try HierarchyIndexWriterTests.desktopFiles(after, hierarchy: newHierarchy.name, id: newHierarchy.id, column: column)
            #expect(mine.idf == desktop.idf && mine.meta == desktop.meta, "\(column)")
        }
        #expect(!after.abf.files.contains { $0.path.contains(oldLocal) })
        #expect(after.metadata.modelAnnotations["__PBI_TimeIntelligenceEnabled"] == "1")
    }

    /// Tắt tuỳ chọn: bỏ hết bộ bảng ngày (variation, quan hệ, phân cấp, bảng cục bộ, bảng mẫu) và đặt chú thích về 0. File ghi ra không còn
    /// dấu vết Auto date/time; bảng người dùng và quan hệ của chúng giữ nguyên.
    @Test func tatAutoDateXoaHetBoBangNgay() throws {
        let before = try HierarchyIndexWriterTests.load(Self.source)
        var edits: [ModelEdit] = []
        for v in before.metadata.variations {
            edits += [.dropVariation(table: v.table, column: v.column), .deleteRelationship(name: v.relationship),
                      .dropHierarchy(table: v.hierarchy.table, name: v.hierarchy.name), .dropTable(name: v.hierarchy.table)]
        }
        let template = try #require(before.metadata.tables.first { $0.name.hasPrefix("DateTableTemplate_") }?.name)
        edits += [.dropHierarchy(table: template, name: "Date Hierarchy"), .dropTable(name: template),
                  .setModelAnnotation(name: "__PBI_TimeIntelligenceEnabled", value: "0")]
        var changes = PBIXChanges()
        changes.modelEdits = ModelEdits(edits)
        let url = try HierarchyIndexWriterTests.write(PBIXWriter.build(source: Self.source, changes: changes).data)
        defer { try? FileManager.default.removeItem(at: url) }
        let after = try HierarchyIndexWriterTests.load(url)
        #expect(after.metadata.variations.isEmpty && after.metadata.dateTableRelationships.isEmpty)
        #expect(!after.metadata.tables.contains { $0.name.hasPrefix("LocalDateTable_") || $0.name.hasPrefix("DateTableTemplate_") })
        #expect(!after.abf.files.contains { $0.path.contains("LocalDateTable_") || $0.path.contains("DateTableTemplate_") })
        #expect(after.metadata.modelAnnotations["__PBI_TimeIntelligenceEnabled"] == "0")
        #expect(after.metadata.userTables.map(\.name) == before.metadata.userTables.map(\.name))
        #expect(after.metadata.relationships == before.metadata.relationships)
    }

    /// Từ chối: quan hệ còn variation dùng, variation trùng hay trỏ sai quan hệ.
    @Test func tuChoiVariationSai() throws {
        let m = try HierarchyIndexWriterTests.load(Self.source)
        let v = try #require(m.metadata.variations.first)
        var writer = try MetadataWriter(sqlite: try m.abf.contents(named: "metadata.sqlitedb"))
        #expect(throws: WriteError.self) { try writer.apply(.deleteRelationship(name: v.relationship)) }
        #expect(throws: WriteError.self) { try writer.apply(.addVariation(table: v.table, column: v.column, relationship: v.relationship, hierarchy: v.hierarchy)) }
        let other = try #require(m.metadata.variations.first { $0.relationship != v.relationship })
        try writer.apply(.dropVariation(table: v.table, column: v.column))
        #expect(throws: WriteError.self) {
            try writer.apply(.addVariation(table: v.table, column: v.column, relationship: other.relationship, hierarchy: v.hierarchy))
        }
        try writer.apply(.addVariation(table: v.table, column: v.column, relationship: v.relationship, hierarchy: v.hierarchy))
        #expect(try ModelMetadata(sqlite: try writer.serialize()).variations.count == m.metadata.variations.count)

        #expect(throws: ModelEditError.self) { _ = try m.metadata.applying(ModelEdits([.deleteRelationship(name: v.relationship)])) }
        #expect(throws: ModelEditError.self) {
            _ = try m.metadata.applying(ModelEdits([.addVariation(table: v.table, column: v.column, relationship: v.relationship, hierarchy: v.hierarchy)]))
        }
    }
}
