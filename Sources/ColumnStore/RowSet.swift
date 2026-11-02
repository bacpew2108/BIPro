// Tập dòng của một bảng (CS, đợt 1a).
//
// Hai dạng lưu trữ, chọn theo mật độ:
// - thưa: mảng UInt32 tăng dần, dùng khi số phần tử × 32 ≤ universe (mật độ tối đa khoảng 3%).
//   Ngưỡng này là điểm hoà vốn bộ nhớ: thưa tốn 4 byte mỗi phần tử, bitset tốn universe/8 byte.
// - bitset: mảng UInt64, mỗi dòng một bit. Giao, hợp và đếm làm theo từng từ (word).
//
// Dạng được suy ra từ (universe, số phần tử), nên hai tập bằng nhau luôn cùng dạng. Vì vậy
// Hashable tổng hợp vẫn đúng. API công khai giữ nguyên đợt 0 (init, all, none, count, contains,
// intersection, union, forEach, rows); thêm `usesBitset` để kiểm tra ngưỡng.

public struct RowSet: Sendable, Hashable {
    /// Số phần tử có thể có (số dòng + 1 cho blank row ảo). Mọi chỉ số phải nhỏ hơn `universe`.
    public let universe: Int

    private let storage: Storage
    /// Số phần tử. Luôn khớp với `storage`.
    private let members: Int

    private enum Storage: Sendable, Hashable {
        case sparse([UInt32])
        case bitset([UInt64])
    }

    /// Dùng dạng thưa khi số phần tử × sparseDivisor ≤ universe.
    static let sparseDivisor = 32

    /// Các dòng, sắp tăng dần, không trùng. Dạng bitset phải giải nén mỗi lần gọi, nên tránh gọi trong vòng lặp.
    public var rows: [UInt32] {
        switch storage {
        case .sparse(let rows): rows
        case .bitset(let words): RowSet.extract(words)
        }
    }

    /// `true` khi đang ở dạng bitset (mật độ trên ngưỡng).
    public var usesBitset: Bool {
        switch storage {
        case .sparse: false
        case .bitset: true
        }
    }

    /// Dựng từ dãy dòng đã sắp tăng dần, không trùng, và mọi dòng nhỏ hơn `universe`.
    public init(universe: Int, sortedRows: [UInt32]) {
        precondition(universe >= 0, "RowSet: universe âm")
        precondition(RowSet.isValid(sortedRows, universe: universe),
                     "RowSet: dòng phải tăng dần, không trùng và nhỏ hơn universe")
        self = RowSet.make(universe: universe, sortedRows: sortedRows)
    }

    private init(universe: Int, storage: Storage, members: Int) {
        self.universe = universe
        self.storage = storage
        self.members = members
    }

    /// Mọi dòng thật 0..<rowCount (không gồm blank row ảo ở chỉ số rowCount).
    public static func all(rowCount: Int) -> RowSet {
        precondition(rowCount >= 0, "RowSet: rowCount âm")
        let universe = rowCount + 1
        var words = [UInt64](repeating: 0, count: wordCount(universe))
        let full = rowCount >> 6
        for i in 0..<full { words[i] = ~UInt64(0) }
        let remainder = rowCount & 63
        if remainder > 0 { words[full] = (UInt64(1) << UInt64(remainder)) - 1 }
        return make(universe: universe, words: words, members: rowCount)
    }

    public static func none(universe: Int) -> RowSet {
        precondition(universe >= 0, "RowSet: universe âm")
        return RowSet(universe: universe, storage: .sparse([]), members: 0)
    }

    public var count: Int { members }

    public func contains(_ row: Int) -> Bool {
        guard row >= 0, row < universe else { return false }
        switch storage {
        case .bitset(let words):
            return words[row >> 6] & (UInt64(1) << UInt64(row & 63)) != 0
        case .sparse(let rows):
            var lo = 0, hi = rows.count
            let key = UInt32(row)
            while lo < hi {
                let mid = (lo + hi) / 2
                if rows[mid] < key { lo = mid + 1 } else { hi = mid }
            }
            return lo < rows.count && rows[lo] == key
        }
    }

    public func intersection(_ other: RowSet) -> RowSet {
        precondition(universe == other.universe, "RowSet khác universe")
        switch (storage, other.storage) {
        case (.sparse(let a), .sparse(let b)):
            return RowSet.make(universe: universe, sortedRows: RowSet.mergeIntersection(a, b))
        case (.sparse(let a), _):
            return RowSet.make(universe: universe, sortedRows: a.filter { other.contains(Int($0)) })
        case (_, .sparse(let b)):
            return RowSet.make(universe: universe, sortedRows: b.filter { contains(Int($0)) })
        case (.bitset(let a), .bitset(let b)):
            var out = a
            var n = 0
            for i in 0..<out.count {
                out[i] &= b[i]
                n += out[i].nonzeroBitCount
            }
            return RowSet.make(universe: universe, words: out, members: n)
        }
    }

    public func union(_ other: RowSet) -> RowSet {
        precondition(universe == other.universe, "RowSet khác universe")
        if case .sparse(let a) = storage, case .sparse(let b) = other.storage {
            return RowSet.make(universe: universe, sortedRows: RowSet.mergeUnion(a, b))
        }
        var out = words
        let rhs = other.words
        var n = 0
        for i in 0..<out.count {
            out[i] |= rhs[i]
            n += out[i].nonzeroBitCount
        }
        return RowSet.make(universe: universe, words: out, members: n)
    }

    public func forEach(_ body: (Int) throws -> Void) rethrows {
        switch storage {
        case .sparse(let rows):
            for r in rows { try body(Int(r)) }
        case .bitset(let words):
            for (w, word) in words.enumerated() {
                var bits = word
                while bits != 0 {
                    try body(w << 6 | bits.trailingZeroBitCount)
                    bits &= bits - 1
                }
            }
        }
    }

    // MARK: - Nội bộ

    /// Bitset của tập này, kể cả khi đang ở dạng thưa.
    private var words: [UInt64] {
        switch storage {
        case .bitset(let words): words
        case .sparse(let rows): RowSet.bits(of: rows, universe: universe)
        }
    }

    /// Chọn dạng theo mật độ, từ dãy dòng đã sắp.
    private static func make(universe: Int, sortedRows rows: [UInt32]) -> RowSet {
        if usesSparse(universe: universe, members: rows.count) {
            return RowSet(universe: universe, storage: .sparse(rows), members: rows.count)
        }
        let words = bits(of: rows, universe: universe)
        return RowSet(universe: universe, storage: .bitset(words), members: rows.count)
    }

    /// Chọn dạng theo mật độ, từ bitset.
    private static func make(universe: Int, words: [UInt64], members: Int) -> RowSet {
        if usesSparse(universe: universe, members: members) {
            return RowSet(universe: universe, storage: .sparse(extract(words)), members: members)
        }
        return RowSet(universe: universe, storage: .bitset(words), members: members)
    }

    private static func usesSparse(universe: Int, members: Int) -> Bool {
        members * sparseDivisor <= universe
    }

    private static func wordCount(_ universe: Int) -> Int {
        (universe + 63) >> 6
    }

    private static func bits(of rows: [UInt32], universe: Int) -> [UInt64] {
        var words = [UInt64](repeating: 0, count: wordCount(universe))
        for r in rows {
            let i = Int(r)
            words[i >> 6] |= UInt64(1) << UInt64(i & 63)
        }
        return words
    }

    private static func extract(_ words: [UInt64]) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(words.reduce(0) { $0 + $1.nonzeroBitCount })
        for (w, word) in words.enumerated() {
            var bits = word
            while bits != 0 {
                out.append(UInt32(w << 6 | bits.trailingZeroBitCount))
                bits &= bits - 1
            }
        }
        return out
    }

    private static func isValid(_ rows: [UInt32], universe: Int) -> Bool {
        var previous = -1
        for r in rows {
            let v = Int(r)
            if v <= previous || v >= universe { return false }
            previous = v
        }
        return true
    }

    private static func mergeIntersection(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { out.append(a[i]); i += 1; j += 1 }
            else if a[i] < b[j] { i += 1 }
            else { j += 1 }
        }
        return out
    }

    private static func mergeUnion(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if j >= b.count || (i < a.count && a[i] < b[j]) {
                out.append(a[i]); i += 1
            } else if i >= a.count || b[j] < a[i] {
                out.append(b[j]); j += 1
            } else {
                out.append(a[i]); i += 1; j += 1
            }
        }
        return out
    }
}
