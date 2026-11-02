// Kiểm tra trên file thật Nhom6 (CS, đợt 1a). Chỉ chạy khi BIPRO_HEAVY=1 và có ~/Downloads/Nhom6_Dashboard.pbix.
// Lệnh: BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-cs-rel
// Đáp án: `pbix-dump verify` báo "verified 110 columns, 0 mismatches", và 11 bảng người dùng.
import Foundation
import Testing
@testable import ColumnStore
import DAXTestSupport

private let heavyEnabled = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

@Suite(.enabled(if: heavyEnabled && DAXFixtures.exists(DAXFixtures.nhom6)))
struct CSNhom6Tests {

    @Test func distinctCountsMatchEngineStatistics() throws {
        let source = try PBIXColumnSource(url: DAXFixtures.nhom6)
        let store = ColumnStore(source: source)
        #expect(source.schema.tables.count == 11, "Nhom6 có 11 bảng người dùng")

        var checked = 0
        var mismatches: [String] = []
        for table in source.schema.tables {
            for column in table.columns where source.hasStorage(column.id) {
                let data = try store.column(column.id)
                var distinct = Set<StoredValue>()
                for row in 0..<data.rowCount { distinct.insert(data.value(at: row)) }
                let nonBlank = distinct.subtracting([.blank]).count
                let expected = try #require(source.cardinality(of: column.id))
                checked += 1
                if nonBlank != expected && distinct.count != expected {
                    mismatches.append("\(table.name)[\(column.name)]: \(nonBlank) (+blank \(distinct.count)), engine \(expected)")
                }
            }
        }
        #expect(checked == 110, "verify kiểm 110 cột")
        #expect(mismatches.isEmpty, "lệch: \(mismatches.prefix(5))")
    }

    @Test func transactionAmountAndBalanceAreDense() throws {
        let source = try PBIXColumnSource(url: DAXFixtures.nhom6)
        let amount = try #require(source.schema.column(table: "Fact_Transaction", name: "amount"))
        let balance = try #require(source.schema.column(table: "Fact_Transaction", name: "balance_after"))
        let store = ColumnStore(source: source)
        let amountData = try store.column(amount.id)
        let balanceData = try store.column(balance.id)
        #expect(!amountData.isEncoded, "amount phải dense")
        #expect(!balanceData.isEncoded, "balance_after phải dense")
    }

    @Test func prefetchAllLoadsEveryStoredColumn() throws {
        let source = try PBIXColumnSource(url: DAXFixtures.nhom6)
        let store = ColumnStore(source: source)
        try store.prefetchAll()
        let factID = try #require(source.schema.table(named: "Fact_Transaction")?.id)
        let rows = try store.rowCount(factID)
        #expect(rows == 1_056_320, "Fact_Transaction có 1.056.320 dòng")
    }
}
