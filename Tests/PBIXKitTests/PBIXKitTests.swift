import Foundation
import Testing
@testable import PBIXKit

/// Fixtures are the author's own reports; tests are skipped when a file is absent.
enum Fixture {
    static let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    static let nhom6 = downloads.appendingPathComponent("Nhom6_Dashboard.pbix")
    static let legacy = downloads.appendingPathComponent("Nhóm 2/Dashboard/Nhóm 2 - Financial Service .pbix")

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

@Suite struct SegmentDecodingTests {
    @Test func bitPackedRunExpandsInOrder() {
        // Width 4: word 0x...4321 unpacks low nibble first.
        let segment = VertiPaq.IDFSegment(runs: [(value: 0xFFFF_FFFF, repeats: 4), (value: 9, repeats: 2)],
                                          packed: [0x4321])
        let meta = VertiPaq.SegmentMeta(records: 6, minDataID: 3, hasNulls: false, bitPackedCount: 4, bitWidth: 4)
        #expect(VertiPaq.decodeSegment(segment, meta: meta) == [4, 5, 6, 7, 9, 9])
    }

    @Test func runsAreCappedAtDeclaredRecords() {
        let segment = VertiPaq.IDFSegment(runs: [(value: 5, repeats: 3), (value: 6, repeats: 0xFFFF_FFFF)], packed: [])
        let meta = VertiPaq.SegmentMeta(records: 4, minDataID: 3, hasNulls: false, bitPackedCount: 0, bitWidth: 0)
        #expect(VertiPaq.decodeSegment(segment, meta: meta) == [5, 5, 5, 6])
    }
}

@Suite(.enabled(if: Fixture.exists(Fixture.nhom6))) struct Nhom6Tests {
    let pbix: PBIXFile
    let abf: ABFBackup
    let metadata: ModelMetadata

    init() throws {
        pbix = try PBIXFile(url: Fixture.nhom6)
        let (abf, compression) = try pbix.loadDataModel()
        #expect(compression == .singleThreaded)
        self.abf = abf
        metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }

    @Test func containerIsPBIR() {
        #expect(pbix.version == "1.32")
        #expect(pbix.reportFormat == .pbir)
    }

    @Test func modelShape() {
        #expect(metadata.userTables.count == 11)
        #expect(metadata.measures.count == 168)
        #expect(metadata.relationships.count == 14)
        #expect(metadata.relationships.filter { !$0.isActive }.map(\.fromColumn) == ["sent_date_key"])
    }

    @Test func factLoanRows() throws {
        let columns = try VertiPaq.decodeTable("Fact_Loan", columns: ["loan_id", "loan_amount", "age_group_at_loan"],
                                               metadata: metadata, abf: abf)
        #expect(columns.allSatisfy { $0.count == 682 })
        #expect(columns[0][0] == .int(6659))
    }

    @Test func vietnameseStringsDecode() throws {
        let column = try VertiPaq.decodeTable("Dim_Loan_Profile", columns: ["status_vn"], metadata: metadata, abf: abf)[0]
        #expect(column[0] == .string("Đã tất toán"))
    }

    @Test func distinctCountsMatchEngineStatistics() throws {
        for table in metadata.userTables {
            for storage in metadata.storage(table: table.name) {
                let column = try VertiPaq.decodeColumn(storage, abf: abf)
                let distinct = Set((0..<column.count).map { column[$0] })
                #expect(distinct.subtracting([.null]).count == storage.cardinality || distinct.count == storage.cardinality,
                        "\(table.name)[\(storage.columnName)]")
            }
        }
    }
}

@Suite(.enabled(if: Fixture.exists(Fixture.legacy))) struct LegacyFormatTests {
    @Test func legacyLayoutModelLoads() throws {
        let pbix = try PBIXFile(url: Fixture.legacy)
        #expect(pbix.version == "1.28")
        #expect(pbix.reportFormat == .legacyLayout)
        let (abf, _) = try pbix.loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        #expect(metadata.userTables.count == 9)
    }
}

/// Power BI behaviours observed with REA in the user's files (Phase A).
@Suite(.enabled(if: Fixture.exists(Fixture.nhom6))) struct ObservedPowerBIConventionsTests {
    let pbix: PBIXFile
    let abf: ABFBackup
    let metadata: ModelMetadata

    init() throws {
        pbix = try PBIXFile(url: Fixture.nhom6)
        (abf, _) = try pbix.loadDataModel()
        metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }

    @Test func reopensOnSavedActivePage() {
        #expect(pbix.activePageID == "d2_khoanvay")
    }

    @Test func hierarchiesAndDisplayFolders() {
        #expect(metadata.hierarchies.count == 6)
        let time = metadata.hierarchies.first { $0.name == "Thời gian" }
        #expect(time?.levels.map(\.name) == ["Năm", "Quý", "Tháng", "Ngày"])
        #expect(metadata.measures.allSatisfy { $0.displayFolder != nil })
    }

    @Test func keyColumnsHiddenAndSummarization() {
        let fk = metadata.columns.first { $0.tableName == "Fact_Transaction" && $0.name == "account_key" }
        #expect(fk?.isHidden == true)
        let amount = metadata.columns.first { $0.tableName == "Fact_Transaction" && $0.name == "amount" }
        #expect(amount?.isSummarizable == true)
        let monthName = metadata.columns.first { $0.tableName == "Dim_Date" && $0.name == "month_name" }
        #expect(monthName?.sortByColumnID.flatMap { metadata.column(id: $0)?.name } == "month_num")
    }

    @Test func reportFiltersAndBookmarks() throws {
        let report = try pbix.loadReport()
        let filters = pbix.loadFilters(report: report)
        #expect(filters.report.map(\.summary).sorted() == ["không phải 9999", "không phải Unknown"])
        #expect(pbix.loadBookmarks().count == 2)
    }

    @Test func rowCountFromSegmentMetadata() throws {
        let storage = try #require(metadata.storage(table: "Fact_Transaction").first)
        #expect(try VertiPaq.rowCount(storage, abf: abf) == 1_056_320)
    }

    @Test func tmdlDocuments() throws {
        let docs = TMDLWriter.documents(for: metadata)
        #expect(docs.count == 15)
        let relationships = try #require(docs.first { $0.path == "relationships.tmdl" })
        #expect(relationships.text.contains("isActive: false"))
        let loan = try #require(docs.first { $0.path == "tables/Fact_Loan.tmdl" })
        #expect(loan.text.contains("\tcolumn age_group_at_loan ="))
        #expect(TMDLWriter.name("Loan Count") == "'Loan Count'")
        #expect(TMDLWriter.name("loan_id") == "loan_id")
    }
}

@Suite(.enabled(if: Fixture.exists(Fixture.downloads.appendingPathComponent("Nhóm 3 - DW&BI/Dashboard/dashboard_DW&BI_nhom_3_20252.pbix"))))
struct DiagramLayoutTests {
    @Test func savedModelViewLayout() throws {
        let pbix = try PBIXFile(url: Fixture.downloads.appendingPathComponent("Nhóm 3 - DW&BI/Dashboard/dashboard_DW&BI_nhom_3_20252.pbix"))
        let layout = try #require(pbix.loadDiagramLayout())
        #expect(layout.diagrams.map(\.name) == ["All tables"])
        #expect(layout.diagrams[0].zoom == 60)
        #expect(layout.diagrams[0].nodes.count == 10)
        #expect(layout.diagrams[0].nodes.allSatisfy { $0.width == 234 })
    }
}
