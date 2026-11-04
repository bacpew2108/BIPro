import Dispatch
import Foundation
import Synchronization

/// Kho cột của một model (CS, đợt 1a): nạp lười từng cột, cache an toàn khi dùng song song, nạp song song.
///
/// Mỗi cột có một ô (slot) với khoá riêng. Hai luồng cùng xin một cột thì chỉ một luồng nạp, luồng kia chờ.
/// Các cột khác nhau nạp song song và không chặn nhau. Lỗi nạp không được lưu, nên lần sau thử lại.
public final class ColumnStore: @unchecked Sendable {
    public let source: any ColumnSource
    public let schema: ModelSchema

    /// Từ điển `slots` và `rowCounts` chia thành nhiều phân đoạn, mỗi phân đoạn một khoá, để các luồng đánh giá song song
    /// (mỗi lần tra chỉ mục là một lần lấy khoá) không xếp hàng ở một khoá chung. Không giữ khoá khi nạp dữ liệu.
    private final class Shard: @unchecked Sendable {
        let lock = NSLock()
        var slots: [ColumnID: ColumnSlot] = [:]
        var rowCounts: [TableID: Int] = [:]
    }
    private static let shardCount = 16
    private let shards = (0..<ColumnStore.shardCount).map { _ in Shard() }

    private func shard(_ table: TableID, _ column: Int = 0) -> Shard {
        shards[(table.raw &* 31 &+ column) & (ColumnStore.shardCount - 1)]
    }

    /// Ô của một cột. `lock` giữ suốt lúc nạp, để cùng một cột không nạp hai lần.
    /// `indexReady` cho đọc chỉ mục không cần khoá sau khi đã dựng.
    private final class ColumnSlot: @unchecked Sendable {
        let lock = NSLock()
        let indexReady = Atomic<Bool>(false)
        var data: ColumnData?
        var index: ColumnIndex?
    }

    /// Ô của mọi cột trong lược đồ, dựng một lần khi khởi tạo. Từ điển bất biến nên đọc không cần khoá: hàng trăm
    /// nghìn lần tra chỉ mục mỗi truy vấn từ nhiều luồng không còn xếp hàng ở một khoá.
    private let knownSlots: [ColumnID: ColumnSlot]
    /// Số dòng đã biết của từng bảng (-1 = chưa biết). Bất biến về tập khoá, giá trị là Atomic.
    private let knownRowCounts: [TableID: RowCountCell]

    public init(source: any ColumnSource) {
        self.source = source
        self.schema = source.schema
        var slots: [ColumnID: ColumnSlot] = [:]
        var counts: [TableID: RowCountCell] = [:]
        for table in schema.tables {
            counts[table.id] = RowCountCell()
            for column in table.columns { slots[column.id] = ColumnSlot() }
        }
        self.knownSlots = slots
        self.knownRowCounts = counts
    }

    /// Cột đã nạp (lười). Nạp lần đầu gọi `source.loadColumn`, các lần sau lấy từ cache.
    public func column(_ id: ColumnID) throws -> ColumnData {
        let slot = slotFor(id)
        slot.lock.lock()
        defer { slot.lock.unlock() }
        return try load(slot, id)
    }

    /// Chỉ mục tính lười của cột (posting list, sortRank, code(of:)). Dùng chung một đối tượng cho mọi người gọi.
    public func index(_ id: ColumnID) throws -> ColumnIndex {
        let slot = slotFor(id)
        if slot.indexReady.load(ordering: .acquiring), let index = slot.index { return index }
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if let index = slot.index { return index }
        let index = ColumnIndex(column: try load(slot, id))
        slot.index = index
        slot.indexReady.store(true, ordering: .releasing)
        return index
    }

    /// Số dòng thật của bảng.
    public func rowCount(_ table: TableID) throws -> Int {
        if let cell = knownRowCounts[table] {
            let known = cell.value.load(ordering: .relaxed)
            if known >= 0 { return known }
            let n = try source.rowCount(table)
            cell.value.store(n, ordering: .relaxed)
            return n
        }
        let shard = shard(table)
        shard.lock.lock()
        if let hit = shard.rowCounts[table] {
            shard.lock.unlock()
            return hit
        }
        shard.lock.unlock()
        let n = try source.rowCount(table)
        shard.lock.lock()
        shard.rowCounts[table] = n
        shard.lock.unlock()
        return n
    }

    /// Mọi dòng thật của bảng (không gồm blank row ảo).
    public func allRows(_ table: TableID) throws -> RowSet {
        RowSet.all(rowCount: try rowCount(table))
    }

    /// Nạp song song các cột cho trước (trùng lặp được bỏ qua). Trả khi mọi cột đã nạp.
    /// Nếu có cột lỗi, ném lỗi đầu tiên gặp phải, còn các cột khác vẫn được nạp.
    public func prefetch(_ ids: [ColumnID]) throws {
        let unique = Array(Set(ids)).sorted { ($0.table.raw, $0.index) < ($1.table.raw, $1.index) }
        let failure = FirstError()
        DispatchQueue.concurrentPerform(iterations: unique.count) { i in
            do {
                _ = try self.column(unique[i])
            } catch {
                failure.record(error)
            }
        }
        if let error = failure.error { throw error }
    }

    /// Nạp song song mọi cột của mọi bảng trong lược đồ.
    public func prefetchAll() throws {
        try prefetch(schema.tables.flatMap { $0.columns.map(\.id) })
    }

    // MARK: - Nội bộ

    private func slotFor(_ id: ColumnID) -> ColumnSlot {
        if let known = knownSlots[id] { return known }
        let shard = shard(id.table, id.index)
        shard.lock.lock()
        defer { shard.lock.unlock() }
        if let existing = shard.slots[id] { return existing }
        let created = ColumnSlot()
        shard.slots[id] = created
        return created
    }

    /// Phải được gọi khi đã giữ `slot.lock`.
    private func load(_ slot: ColumnSlot, _ id: ColumnID) throws -> ColumnData {
        if let data = slot.data { return data }
        let loaded = try source.loadColumn(id)
        slot.data = loaded
        return loaded
    }
}

/// Ô số dòng của một bảng, -1 khi chưa biết.
private final class RowCountCell: @unchecked Sendable {
    let value = Atomic<Int>(-1)
}

/// Giữ lỗi đầu tiên của các luồng song song.
private final class FirstError: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?

    func record(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        if stored == nil { stored = error }
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
