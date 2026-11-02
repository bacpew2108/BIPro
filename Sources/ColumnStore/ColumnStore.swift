import Dispatch
import Foundation

/// Kho cột của một model (CS, đợt 1a): nạp lười từng cột, cache an toàn khi dùng song song, nạp song song.
///
/// Mỗi cột có một ô (slot) với khoá riêng. Hai luồng cùng xin một cột thì chỉ một luồng nạp, luồng kia chờ.
/// Các cột khác nhau nạp song song và không chặn nhau. Lỗi nạp không được lưu, nên lần sau thử lại.
public final class ColumnStore: @unchecked Sendable {
    public let source: any ColumnSource
    public let schema: ModelSchema

    /// Bảo vệ hai từ điển `slots` và `rowCounts`. Không giữ khoá khi nạp dữ liệu.
    private let lock = NSLock()
    private var slots: [ColumnID: ColumnSlot] = [:]
    private var rowCounts: [TableID: Int] = [:]

    /// Ô của một cột. `lock` giữ suốt lúc nạp, để cùng một cột không nạp hai lần.
    private final class ColumnSlot: @unchecked Sendable {
        let lock = NSLock()
        var data: ColumnData?
        var index: ColumnIndex?
    }

    public init(source: any ColumnSource) {
        self.source = source
        self.schema = source.schema
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
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if let index = slot.index { return index }
        let index = ColumnIndex(column: try load(slot, id))
        slot.index = index
        return index
    }

    /// Số dòng thật của bảng.
    public func rowCount(_ table: TableID) throws -> Int {
        lock.lock()
        if let hit = rowCounts[table] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let n = try source.rowCount(table)
        lock.lock()
        rowCounts[table] = n
        lock.unlock()
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
        lock.lock()
        defer { lock.unlock() }
        if let existing = slots[id] { return existing }
        let created = ColumnSlot()
        slots[id] = created
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
