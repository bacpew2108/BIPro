// Cache measure và RowSet (CORE, đợt 2), architecture.md §7.4.
//
// - MeasureCache: khoá (measure, vân tay ngữ cảnh sau context transition, băm các dòng ảo) → Value.
//   Vân tay FilterContext đã gồm shadow và ghi đè quan hệ, nên hai ngữ cảnh khác shadow không dùng chung kết quả.
// - RowSetCache: (bảng, vân tay) → RowSet cho R(T), và (bảng, dòng) → RowSet cho context transition.
// - Cache an toàn luồng (NSLock), giới hạn kích thước bằng cách bỏ khoảng 1/4 mục cũ nhất khi đầy.
// - Có thể xoá toàn bộ (`clear()`), ví dụ khi model đổi (Phase E).
//
// [SUY ĐOÁN] Vân tay là Int từ Hasher: hai ngữ cảnh khác nhau có thể trùng vân tay với xác suất rất nhỏ (2^-64).
import Foundation
import ColumnStore

/// Khoá cache của một lần đánh giá measure.
public struct MeasureCacheKey: Hashable, Sendable {
    public let measure: Int32
    /// `FilterContext.fingerprint` sau khi áp context transition (đã gồm shadow).
    public let filterFingerprint: Int
    /// Băm các dòng của bảng ảo trong row context (dòng không có lineage không được transition nên phải có trong khoá).
    public let virtualRowsDigest: Int

    public init(measure: Int32, filterFingerprint: Int, virtualRowsDigest: Int) {
        self.measure = measure
        self.filterFingerprint = filterFingerprint
        self.virtualRowsDigest = virtualRowsDigest
    }
}

/// Khoá cache tập dòng.
public enum RowSetCacheKey: Hashable, Sendable {
    /// R(T) dưới một vân tay ngữ cảnh.
    case visible(TableID, fingerprint: Int)
    /// R(T) như `visible`, lưu dạng bitset để giao nhanh với tập nhỏ.
    case visibleBitset(TableID, fingerprint: Int)
    /// Các dòng của T có cùng giá trị ở mọi cột với dòng `row` (context transition của một dòng vật lý).
    case transition(TableID, row: Int)
}

/// Bộ nhớ đệm LRU xấp xỉ, an toàn luồng. Khi đầy, bỏ khoảng 1/4 mục có thời điểm dùng cũ nhất.
/// Cache lớn chia thành nhiều phân đoạn, mỗi phân đoạn một khoá riêng (chọn theo băm khoá), để nhiều luồng đánh giá
/// song song không chờ nhau ở một khoá chung. Cache nhỏ (test eviction) chỉ có một phân đoạn nên giữ nguyên ngữ nghĩa.
final class LRUCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private final class Shard: @unchecked Sendable {
        let lock = NSLock()
        let capacity: Int
        var storage: [Key: (value: Value, stamp: UInt64)] = [:]
        var clock: UInt64 = 0
        var hitCount = 0
        var missCount = 0

        init(capacity: Int) { self.capacity = max(1, capacity) }

        func get(_ key: Key) -> Value? {
            lock.lock()
            defer { lock.unlock() }
            clock &+= 1
            guard var entry = storage[key] else {
                missCount += 1
                return nil
            }
            hitCount += 1
            entry.stamp = clock
            storage[key] = entry
            return entry.value
        }

        func set(_ key: Key, _ value: Value) {
            lock.lock()
            defer { lock.unlock() }
            clock &+= 1
            storage[key] = (value, clock)
            if storage.count > capacity { evictOldestQuarter() }
        }

        /// Phải được gọi khi đã giữ `lock`.
        private func evictOldestQuarter() {
            let drop = max(1, storage.count / 4)
            let oldest = storage.sorted { $0.value.stamp < $1.value.stamp }.prefix(drop)
            for (key, _) in oldest {
                storage.removeValue(forKey: key)
            }
        }
    }

    private let shards: [Shard]

    init(capacity: Int) {
        let capacity = max(1, capacity)
        let count = capacity >= 1024 ? 16 : 1
        shards = (0..<count).map { _ in Shard(capacity: (capacity + count - 1) / count) }
    }

    @inline(__always)
    private func shard(_ key: Key) -> Shard {
        shards.count == 1 ? shards[0] : shards[Int(UInt(bitPattern: key.hashValue) % UInt(shards.count))]
    }

    func get(_ key: Key) -> Value? { shard(key).get(key) }

    func set(_ key: Key, _ value: Value) { shard(key).set(key, value) }

    func removeAll() {
        for shard in shards {
            shard.lock.lock()
            shard.storage.removeAll(keepingCapacity: true)
            shard.lock.unlock()
        }
    }

    /// Số lần trúng và trượt từ khi tạo (hoặc từ lần `resetStatistics()` gần nhất).
    var statistics: (hits: Int, misses: Int) {
        var hits = 0, misses = 0
        for shard in shards {
            shard.lock.lock()
            hits += shard.hitCount
            misses += shard.missCount
            shard.lock.unlock()
        }
        return (hits, misses)
    }

    func resetStatistics() {
        for shard in shards {
            shard.lock.lock()
            shard.hitCount = 0
            shard.missCount = 0
            shard.lock.unlock()
        }
    }

    var count: Int {
        var total = 0
        for shard in shards {
            shard.lock.lock()
            total += shard.storage.count
            shard.lock.unlock()
        }
        return total
    }
}

/// Cache kết quả measure.
public final class MeasureCache: @unchecked Sendable {
    private let cache: LRUCache<MeasureCacheKey, Value>

    public init(capacity: Int = 100_000) {
        cache = LRUCache(capacity: capacity)
    }

    public func value(for key: MeasureCacheKey) -> Value? { cache.get(key) }
    public func store(_ value: Value, for key: MeasureCacheKey) { cache.set(key, value) }
    public var count: Int { cache.count }
    /// Số lần trúng và trượt.
    public var statistics: (hits: Int, misses: Int) { cache.statistics }
    public func resetStatistics() { cache.resetStatistics() }
    public func clear() { cache.removeAll() }
}

/// Cache tập dòng (R(T) và transition một dòng).
public final class RowSetCache: @unchecked Sendable {
    private let cache: LRUCache<RowSetCacheKey, RowSet>

    public init(capacity: Int = 100_000) {
        cache = LRUCache(capacity: capacity)
    }

    public func rows(for key: RowSetCacheKey) -> RowSet? { cache.get(key) }
    public func store(_ rows: RowSet, for key: RowSetCacheKey) { cache.set(key, rows) }
    public var count: Int { cache.count }
    public var statistics: (hits: Int, misses: Int) { cache.statistics }
    public func resetStatistics() { cache.resetStatistics() }
    public func clear() { cache.removeAll() }
}

/// Khoá cache giá trị thấy được của một cột (VALUES) dưới một vân tay ngữ cảnh.
public struct ValuesCacheKey: Hashable, Sendable {
    public let column: ColumnID
    public let fingerprint: Int
}

/// Cache giá trị phân biệt thấy được của cột.
public final class ValuesCache: @unchecked Sendable {
    private let cache: LRUCache<ValuesCacheKey, [Value]>
    public init(capacity: Int = 20_000) { cache = LRUCache(capacity: capacity) }
    public func values(for key: ValuesCacheKey) -> [Value]? { cache.get(key) }
    public func store(_ values: [Value], for key: ValuesCacheKey) { cache.set(key, values) }
    public func clear() { cache.removeAll() }
}

/// Gộp cache của một engine. Một `EngineCache` dùng chung cho mọi `Evaluator` của cùng một model.
public final class EngineCache: Sendable {
    public let measures: MeasureCache
    public let rowSets: RowSetCache
    public let values = ValuesCache()

    public init(measureCapacity: Int = 100_000, rowSetCapacity: Int = 100_000) {
        measures = MeasureCache(capacity: measureCapacity)
        rowSets = RowSetCache(capacity: rowSetCapacity)
    }

    /// Xoá mọi mục (dùng khi model đổi).
    public func clear() {
        measures.clear()
        rowSets.clear()
        values.clear()
    }
}
