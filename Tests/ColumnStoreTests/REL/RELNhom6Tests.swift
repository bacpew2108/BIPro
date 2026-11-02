// Kiểm tra lan truyền trên file thật Nhom6 (REL, đợt 1b). Chỉ chạy khi BIPRO_HEAVY=1 và có ~/Downloads/Nhom6_Dashboard.pbix.
// Lệnh: BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-rel
//
// Đáp án lấy bằng SQLite trên dữ liệu đã giải mã (chỉ đọc). Các câu SQL và kết quả:
//   SELECT count(*) FROM Fact_Transaction f JOIN Dim_Date d ON f.date_key = d.date_key WHERE d.year = 2018;
//     -> 322277 (Dim_Date có năm 2011..2018, 2922 dòng; 0 FK không khớp)
//   SELECT count(*) FROM Fact_Transaction f JOIN Dim_Client c ON f.client_key = c.client_key WHERE c.client_region <> 'Unknown';
//     -> 1056320 (tổng số dòng fact; dòng khách 'Unknown' (client_key -1) không có dòng fact nào)
//   SELECT count(*) FROM Dim_Client WHERE client_region <> 'Unknown';  -> 5369 (bỏ đúng 1 dòng)
//   SELECT count(*) FROM Fact_Transaction f JOIN Dim_Client c ON f.client_key = c.client_key WHERE c.client_region = 'Unknown';  -> 0
import Foundation
import Testing
@testable import ColumnStore
import DAXTestSupport

private let heavyEnabled = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

@Suite(.enabled(if: heavyEnabled && DAXFixtures.exists(DAXFixtures.nhom6)))
struct RELNhom6Tests {

    /// Dim_Date.year = 2018: 322277 dòng Fact_Transaction (SQL ở đầu file).
    @Test func filterYear2018ReachesFactTransactionLikeSQL() throws {
        let source = try PBIXColumnSource(url: DAXFixtures.nhom6)
        let store = ColumnStore(source: source)
        let fact = try #require(source.schema.table(named: "Fact_Transaction"))
        let year = try #require(source.schema.column(table: "Dim_Date", name: "year"))
        let yearIndex = try store.index(year.id)
        let code = try #require(yearIndex.code(of: .integer(2018)), "năm 2018 phải có trong dictionary")
        let filter = CodeSet(column: year.id, codes: [UInt32(code)])

        let rows = try Propagation.visibleRows(in: store, table: fact.id, localFilters: [filter], overrides: [])
        #expect(rows.count == 322277, "khớp SQL: 322277")
    }

    /// Dim_Client.client_region <> Unknown: dòng Unknown là dòng khách duy nhất bị bỏ, và không có dòng fact nào
    /// tham chiếu nó, nên toàn bộ 1056320 dòng fact vẫn thấy được.
    @Test func clientRegionNotUnknownKeepsEveryFactRow() throws {
        let source = try PBIXColumnSource(url: DAXFixtures.nhom6)
        let store = ColumnStore(source: source)
        let fact = try #require(source.schema.table(named: "Fact_Transaction"))
        let client = try #require(source.schema.table(named: "Dim_Client"))
        let region = try #require(source.schema.column(table: "Dim_Client", name: "client_region"))
        let regionIndex = try store.index(region.id)
        let limit = try #require(regionIndex.codeLimit)

        // Mọi mã trừ mã của "Unknown". Mã 0 (BLANK) vẫn giữ, vì BLANK <> "Unknown".
        var codes: [UInt32] = []
        for code in 0..<limit {
            if code == 0 || regionIndex.column.dictionaryValue(code: code) != .string("Unknown") {
                codes.append(UInt32(code))
            }
        }
        let filter = CodeSet(column: region.id, codes: codes)

        let clients = try Propagation.visibleRows(in: store, table: client.id, localFilters: [filter], overrides: [])
        #expect(clients.count == 5369, "5370 dòng khách, bỏ đúng 1 dòng Unknown")

        let facts = try Propagation.visibleRows(in: store, table: fact.id, localFilters: [filter], overrides: [])
        #expect(facts.count == 1_056_320, "khớp SQL: 1056320 dòng fact")
    }

    /// Kết hợp năm 2018 và Dim_Client không Unknown: vẫn 322277 dòng, vì bộ lọc khách không bỏ dòng nào.
    @Test func combinedYearAndClientFilterMatchesYearAlone() throws {
        let source = try PBIXColumnSource(url: DAXFixtures.nhom6)
        let store = ColumnStore(source: source)
        let fact = try #require(source.schema.table(named: "Fact_Transaction"))
        let year = try #require(source.schema.column(table: "Dim_Date", name: "year"))
        let region = try #require(source.schema.column(table: "Dim_Client", name: "client_region"))
        let yearCode = try #require(try store.index(year.id).code(of: .integer(2018)))
        let regionIndex = try store.index(region.id)
        let limit = try #require(regionIndex.codeLimit)
        var codes: [UInt32] = []
        for code in 0..<limit where code == 0 || regionIndex.column.dictionaryValue(code: code) != .string("Unknown") {
            codes.append(UInt32(code))
        }
        let rows = try Propagation.visibleRows(
            in: store, table: fact.id,
            localFilters: [CodeSet(column: year.id, codes: [UInt32(yearCode)]),
                           CodeSet(column: region.id, codes: codes)],
            overrides: [])
        #expect(rows.count == 322277)
    }
}
