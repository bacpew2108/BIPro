// Kiểm tra ColumnStore (CS, đợt 1a): mỗi cột nạp đúng một lần dù gọi đồng thời, nạp song song,
// lỗi nạp được báo lại và không bị lưu thành cache.
import Dispatch
import Foundation
import Testing
@testable import ColumnStore
@testable import DAXTestSupport

/// Nguồn đếm số lần nạp từng cột, có độ trễ nhỏ để các luồng thật sự chồng lên nhau.
final class CSCountingSource: ColumnSource, @unchecked Sendable {
    let schema: ModelSchema
    private let inner: InMemoryColumnSource
    private let failing: ColumnID?
    private let lock = NSLock()
    private var counts: [ColumnID: Int] = [:]

    init(inner: InMemoryColumnSource, failing: ColumnID? = nil) {
        self.inner = inner
        self.schema = inner.schema
        self.failing = failing
    }

    func rowCount(_ table: TableID) throws -> Int {
        try inner.rowCount(table)
    }

    func loadColumn(_ id: ColumnID) throws -> ColumnData {
        lock.lock()
        counts[id, default: 0] += 1
        lock.unlock()
        usleep(2_000)
        if id == failing { throw ColumnStoreError.storageMissing("thử lỗi có chủ đích") }
        return try inner.loadColumn(id)
    }

    func loadCount(_ id: ColumnID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[id] ?? 0
    }
}

@Suite struct CSStoreTests {

    @Test func concurrentRequestsLoadEachColumnOnce() throws {
        let source = CSCountingSource(inner: MiniBank.makeSource())
        let store = ColumnStore(source: source)
        let id = MiniBank.Columns.FactTrans.balanceAfter
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            _ = try? store.column(id)
        }
        #expect(source.loadCount(id) == 1, "64 luồng xin một cột thì chỉ nạp một lần")
        #expect(try store.column(id).value(at: 0) == .currency(MiniBankRaw.transBalanceAfter[0]))
    }

    @Test func prefetchLoadsEveryColumnOnceInParallel() throws {
        let source = CSCountingSource(inner: MiniBank.makeSource())
        let store = ColumnStore(source: source)
        let ids = MiniBank.schema.tables.flatMap { $0.columns.map(\.id) }
        try store.prefetch(ids + ids)  // trùng lặp phải được bỏ qua
        for id in ids {
            #expect(source.loadCount(id) == 1, "cột \(id) phải nạp đúng một lần")
        }
        let clientKey = try store.column(MiniBank.Columns.DimClient.clientKey)
        #expect(clientKey.value(at: 0) == .integer(MiniBankRaw.clientKey[0]), "cột đã nạp đọc được từ cache")
    }

    @Test func prefetchAllMatchesLazyLoad() throws {
        let store = ColumnStore(source: MiniBank.makeSource())
        try store.prefetchAll()
        let lazy = MiniBank.makeStore()
        for table in MiniBank.schema.tables {
            for column in table.columns {
                let a = try store.column(column.id)
                let b = try lazy.column(column.id)
                #expect(a.rowCount == b.rowCount)
                for row in 0..<a.rowCount {
                    #expect(a.value(at: row) == b.value(at: row), "\(table.name)[\(column.name)] dòng \(row)")
                }
            }
        }
    }

    @Test func prefetchReportsErrorAndStillLoadsOthers() throws {
        let failing = MiniBank.Columns.FactTrans.amount
        let source = CSCountingSource(inner: MiniBank.makeSource(), failing: failing)
        let store = ColumnStore(source: source)
        let ids = MiniBank.schema.tables.flatMap { $0.columns.map(\.id) }
        #expect(throws: ColumnStoreError.self) {
            try store.prefetch(ids)
        }
        for id in ids where id != failing {
            #expect(source.loadCount(id) == 1, "cột \(id) vẫn phải được nạp")
        }
        // Lỗi không được lưu: lần gọi sau vẫn thử nạp lại.
        #expect(throws: ColumnStoreError.self) {
            _ = try store.column(failing)
        }
        #expect(source.loadCount(failing) == 2)
    }

    @Test func indexIsSharedAndBuiltFromSameColumn() throws {
        let store = MiniBank.makeStore()
        let id = MiniBank.Columns.DimDate.year
        let first = try store.index(id)
        let second = try store.index(id)
        #expect(first === second, "cùng một cột thì dùng chung một chỉ mục")
        let loaded = try store.column(id)
        #expect(first.column.rowCount == loaded.rowCount)
    }

    @Test func rowCountsAndAllRows() throws {
        let store = MiniBank.makeStore()
        #expect(try store.rowCount(MiniBank.Tables.factTrans) == MiniBankRaw.transKey.count)
        let rows = try store.allRows(MiniBank.Tables.factTrans)
        #expect(rows.count == MiniBankRaw.transKey.count)
        #expect(rows.universe == MiniBankRaw.transKey.count + 1)
        #expect(!rows.contains(MiniBankRaw.transKey.count), "blank row ảo không có trong allRows")
    }
}
