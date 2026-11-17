// Đợt tồn đọng sau Phase F, T007: đọc cờ "discourage implicit measures" (US1), dòng `Variation` và `JoinOnDateBehavior` (US2, Auto
// date/time). Golden: Nhom6 (cờ bật), tài liệu trống BI Pro (cờ tắt), `w8.3.pbix` của Desktop (2 variation tới bảng ngày cục bộ).
import Foundation
import Testing
@testable import PBIXKit

@Suite struct F2ModelMetadataTests {
    private func model(_ url: URL) throws -> ModelMetadata {
        let (abf, _) = try PBIXFile(data: try Data(contentsOf: url, options: .alwaysMapped)).loadDataModel()
        return try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }

    /// Lỗi có sẵn: quan hệ tới bảng tính toán của người dùng (`SystemFlags = 2`, bảng `Ngày` = CALENDAR của w8.3) bị bỏ khi đọc.
    @Test(.enabled(if: F2Fixtures.w83 != nil)) func relationshipsToCalculatedUserTablesAreRead() throws {
        let w83 = try model(try #require(F2Fixtures.w83))
        #expect(w83.relationships.filter { $0.toTable == "Ngày" }.count == 4)
        #expect(w83.relationships.contains { $0.name.hasPrefix("AutoDetected_") })
    }

    @Test func blankDocumentAllowsImplicitMeasures() throws {
        let (abf, _) = try PBIXFile(data: try NewDocument.blank()).loadDataModel()
        #expect(try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")).discourageImplicitMeasures == false)
    }

    @Test(.enabled(if: F2Fixtures.nhom6 != nil)) func nhom6DiscouragesImplicitMeasures() throws {
        let nhom6 = try model(try #require(F2Fixtures.nhom6))
        #expect(nhom6.discourageImplicitMeasures)
        #expect(nhom6.variations.isEmpty)
        #expect(nhom6.relationships.allSatisfy { $0.joinOnDateBehavior == 1 })
    }

    @Test(.enabled(if: F2Fixtures.w83 != nil)) func w83VariationsPointAtLocalDateTables() throws {
        let w83 = try model(try #require(F2Fixtures.w83))
        #expect(!w83.discourageImplicitMeasures)
        #expect(w83.variations.count == 2)
        for variation in w83.variations {
            #expect(variation.isDefault)
            #expect(variation.hierarchy.name == "Date Hierarchy")
            #expect(variation.hierarchy.table.hasPrefix("LocalDateTable_"))
            #expect(!w83.relationships.contains { $0.name == variation.relationship })   // giao diện không thấy bảng ngày cục bộ
            let relationship = try #require(w83.dateTableRelationships.first { $0.name == variation.relationship })
            #expect(relationship.joinOnDateBehavior == 2)
            #expect(relationship.fromTable == variation.table && relationship.fromColumn == variation.column)
            #expect(relationship.toTable == variation.hierarchy.table && relationship.toColumn == "Date")
        }
    }
}
