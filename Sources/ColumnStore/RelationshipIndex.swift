// RelationshipIndex (REL, đợt 1b): chỉ mục many→one của một quan hệ (architecture.md §3.2).
//
// `fkToPK[i]` là dòng bên một khớp với dòng i bên nhiều. Dòng không khớp (kể cả FK BLANK) trỏ tới
// `oneRowCount`, tức blank row ảo của bảng bên một. Blank row ảo chỉ "tồn tại" khi `hasUnmatched`.
//
// Đi ngược một → nhiều dùng posting list của cột FK (`ColumnStore.index`) khi bên một nhỏ, hoặc
// quét `fkToPK` khi bên một lớn. Hai đường cho cùng kết quả (test kiểm tra).
//
// Chỉ mục được cache theo `ColumnStore` qua `RelationshipIndexRegistry`. Contract đóng băng không có
// chỗ để gắn cache vào store, nên cache nằm ở đây. Cache giữ yếu tham chiếu tới store.
//
// [SUY ĐOÁN] Contract không có trường cardinality, nên mọi quan hệ được coi là M:1 (regular), tức là
// có blank row khi có FK không khớp.
// [SUY ĐOÁN] So khớp khoá: số nguyên và currency cùng dạng số nguyên; chuỗi so không phân biệt hoa thường;
// hai khoá bên một trùng nhau thì lấy dòng gặp trước.

import Foundation

/// Khoá so khớp đã chuẩn hoá. Không có khớp giữa các kiểu khác nhau (ví dụ chuỗi với số).
enum RelJoinKey: Hashable, Sendable {
    case integer(Int64)
    case text(String)
    case double(UInt64)
    case boolean(Bool)
    case date(UInt64)

    /// `nil` với BLANK, vì BLANK không khớp với gì.
    init?(_ value: StoredValue) {
        switch value {
        case .blank:
            return nil
        case .integer(let x), .currency(let x):
            self = .integer(x)
        case .string(let s):
            self = .text(s.lowercased())
        case .double(let d):
            self = .double((d == 0 ? 0 : d).bitPattern)
        case .boolean(let b):
            self = .boolean(b)
        case .dateTime(let d):
            self = .date((d == 0 ? 0 : d).bitPattern)
        }
    }
}

public struct RelationshipIndex: Sendable {
    /// Quan hệ đã dựng chỉ mục.
    public let schema: RelationshipSchema
    /// Số dòng thật của bảng bên nhiều.
    public let manyRowCount: Int
    /// Số dòng thật của bảng bên một. Cũng là chỉ số của blank row ảo bên một.
    public let oneRowCount: Int
    /// Với mỗi dòng bên nhiều, dòng bên một khớp, hoặc `oneRowCount` nếu không khớp.
    public let fkToPK: [Int32]
    /// Có dòng bên nhiều không khớp (kể cả FK BLANK). Khi đúng, blank row ảo bên một "tồn tại".
    public let hasUnmatched: Bool

    /// Mã FK → dòng PK (`oneRowCount` nếu không khớp). `nil` khi cột FK là dense.
    private let codeToPK: [Int32]?
    /// Chỉ mục của cột FK, để lấy posting list theo mã. `nil` khi cột FK là dense.
    private let manyIndex: ColumnIndex?

    /// Cách đi ngược một → nhiều. `automatic` chọn theo kích thước (dùng để kiểm thử hai đường).
    enum ManyStrategy: Sendable {
        case automatic, postings, scan
    }

    init(schema: RelationshipSchema, manyRowCount: Int, oneRowCount: Int, fkToPK: [Int32],
         codeToPK: [Int32]?, manyIndex: ColumnIndex?) {
        self.schema = schema
        self.manyRowCount = manyRowCount
        self.oneRowCount = oneRowCount
        self.fkToPK = fkToPK
        self.hasUnmatched = fkToPK.contains(Int32(oneRowCount))
        self.codeToPK = codeToPK
        self.manyIndex = manyIndex
    }

    /// Dòng bên nhiều của các dòng bên một `oneRows` (lan truyền một → nhiều).
    /// Universe đầu vào là `oneRowCount + 1`. Universe đầu ra là `manyRowCount + 1`.
    /// Blank row ảo bên nhiều (chỉ số `manyRowCount`) được lấy khi blank row bên một có trong `oneRows`.
    public func manyRows(from oneRows: RowSet) -> RowSet {
        manyRows(from: oneRows, strategy: .automatic)
    }

    /// `true` khi có dòng bên nhiều thuộc `manyRows` mà khoá không khớp với dòng bên một. Các dòng đó
    /// tham chiếu blank row ảo bên một, nên blank row ấy chỉ thấy được khi hàm này trả `true`.
    public func hasUnmatched(in manyRows: RowSet) -> Bool {
        precondition(manyRows.universe == manyRowCount + 1, "RelationshipIndex: universe phía nhiều không khớp")
        let blank = Int32(oneRowCount)
        for r in 0..<manyRowCount where fkToPK[r] == blank && manyRows.contains(r) {
            return true
        }
        return false
    }

    /// Dòng bên một được tham chiếu bởi các dòng bên nhiều `manyRows` (hai chiều, expanded table).
    /// Blank row ảo bên nhiều coi như tham chiếu blank row bên một.
    public func oneRows(from manyRows: RowSet) -> RowSet {
        precondition(manyRows.universe == manyRowCount + 1, "RelationshipIndex: universe phía nhiều không khớp")
        let blank = oneRowCount
        if manyRows.count * 8 >= oneRowCount {
            var seen = [Bool](repeating: false, count: oneRowCount + 1)
            manyRows.forEach { i in
                seen[i < manyRowCount ? Int(fkToPK[i]) : blank] = true
            }
            var out: [UInt32] = []
            for (p, hit) in seen.enumerated() where hit { out.append(UInt32(p)) }
            return RowSet(universe: oneRowCount + 1, sortedRows: out)
        }
        var hits: [UInt32] = []
        hits.reserveCapacity(manyRows.count)
        manyRows.forEach { i in
            hits.append(i < manyRowCount ? UInt32(fkToPK[i]) : UInt32(blank))
        }
        hits.sort()
        var out: [UInt32] = []
        out.reserveCapacity(hits.count)
        for h in hits where out.last != h { out.append(h) }
        return RowSet(universe: oneRowCount + 1, sortedRows: out)
    }

    /// Tương đương `manyRows(from: oneRows).intersection(restriction)`, nhưng chỉ xét các dòng trong `restriction`.
    /// Chi phí theo số dòng của `restriction`, không theo số dòng bên nhiều. Dùng trong lan truyền khi bên nhiều đã
    /// bị lọc (thường rất ít dòng) và bên một là toàn bộ, nên quét mọi dòng bên nhiều là lãng phí.
    public func manyRows(from oneRows: RowSet, restrictedTo restriction: RowSet) -> RowSet {
        precondition(oneRows.universe == oneRowCount + 1, "RelationshipIndex: universe phía một không khớp")
        precondition(restriction.universe == manyRowCount + 1, "RelationshipIndex: universe phía nhiều không khớp")
        let blankIncluded = oneRows.contains(oneRowCount)
        var out: [UInt32] = []
        restriction.forEach { r in
            if r < manyRowCount {
                if oneRows.contains(Int(fkToPK[r])) { out.append(UInt32(r)) }
            } else if blankIncluded {
                // r == manyRowCount: blank row ảo bên nhiều có FK BLANK, khớp blank row bên một.
                out.append(UInt32(r))
            }
        }
        return RowSet(universe: manyRowCount + 1, sortedRows: out)
    }

    func manyRows(from oneRows: RowSet, strategy: ManyStrategy) -> RowSet {
        precondition(oneRows.universe == oneRowCount + 1, "RelationshipIndex: universe phía một không khớp")
        let blankOne = oneRowCount
        let blankIncluded = oneRows.contains(blankOne)
        let usePostings: Bool
        switch strategy {
        case .automatic: usePostings = codeToPK != nil && oneRows.count * 16 <= manyRowCount
        case .postings: usePostings = codeToPK != nil
        case .scan: usePostings = false
        }

        var out: [UInt32] = []
        if usePostings, let codeToPK, let manyIndex {
            // Mỗi mã FK có một posting list, và các mã khác nhau có dòng khác nhau. Nên gộp rồi sắp.
            for code in 0..<codeToPK.count where oneRows.contains(Int(codeToPK[code])) {
                if let slice = manyIndex.postings(forCode: code) {
                    out.append(contentsOf: slice)
                }
            }
            out.sort()
        } else {
            for i in 0..<manyRowCount where oneRows.contains(Int(fkToPK[i])) {
                out.append(UInt32(i))
            }
        }
        // Blank row ảo bên nhiều có FK BLANK, nên khớp với blank row bên một.
        if blankIncluded { out.append(UInt32(manyRowCount)) }
        return RowSet(universe: manyRowCount + 1, sortedRows: out)
    }

    // MARK: - Dựng chỉ mục

    static func build(_ relationship: RelationshipSchema, store: ColumnStore) throws -> RelationshipIndex {
        let manyRowCount = try store.rowCount(relationship.manyColumn.table)
        let oneRowCount = try store.rowCount(relationship.oneColumn.table)
        let manyColumn = try store.column(relationship.manyColumn)
        let oneColumn = try store.column(relationship.oneColumn)
        let blank = Int32(oneRowCount)

        let keyToPK = primaryKeyRows(oneColumn, rowCount: oneRowCount)
        var fkToPK = [Int32](repeating: blank, count: manyRowCount)
        var codeToPK: [Int32]? = nil
        var manyIndex: ColumnIndex? = nil

        if manyColumn.isEncoded {
            // Tính trên dictionary (mỗi mã một lần), rồi tra qua mã cho từng dòng.
            let k = manyColumn.dictionaryCount
            var table = [Int32](repeating: blank, count: k + 1)
            for code in stride(from: 1, through: k, by: 1) {
                if let value = manyColumn.dictionaryValue(code: code),
                   let key = RelJoinKey(value), let pk = keyToPK[key] {
                    table[code] = pk
                }
            }
            for i in 0..<manyRowCount {
                let code = manyColumn.code(atRow: i) ?? 0
                fkToPK[i] = code >= 0 && code <= k ? table[code] : blank
            }
            codeToPK = table
            manyIndex = try store.index(relationship.manyColumn)
        } else {
            // Cột dense (số hoặc ngày mã hoá theo giá trị): so khớp từng dòng.
            for i in 0..<manyRowCount {
                if let key = RelJoinKey(manyColumn.value(at: i)), let pk = keyToPK[key] {
                    fkToPK[i] = pk
                }
            }
        }

        return RelationshipIndex(schema: relationship, manyRowCount: manyRowCount, oneRowCount: oneRowCount,
                                 fkToPK: fkToPK, codeToPK: codeToPK, manyIndex: manyIndex)
    }

    /// Khoá → dòng bên một. Khoá trùng thì giữ lần đầu gặp.
    private static func primaryKeyRows(_ column: ColumnData, rowCount: Int) -> [RelJoinKey: Int32] {
        var keyToPK: [RelJoinKey: Int32] = [:]
        if column.isEncoded {
            let k = column.dictionaryCount
            var rowOfCode = [Int32](repeating: -1, count: k + 1)
            for r in 0..<rowCount {
                let code = column.code(atRow: r) ?? 0
                if code > 0 && code <= k && rowOfCode[code] < 0 {
                    rowOfCode[code] = Int32(r)
                }
            }
            for code in stride(from: 1, through: k, by: 1) where rowOfCode[code] >= 0 {
                if let value = column.dictionaryValue(code: code), let key = RelJoinKey(value),
                   keyToPK[key] == nil {
                    keyToPK[key] = rowOfCode[code]
                }
            }
        } else {
            for r in 0..<rowCount {
                if let key = RelJoinKey(column.value(at: r)), keyToPK[key] == nil {
                    keyToPK[key] = Int32(r)
                }
            }
        }
        return keyToPK
    }
}

// MARK: - Cache theo ColumnStore

extension ColumnStore {
    /// Chỉ mục many→one của quan hệ, dựng lười và cache theo store. An toàn khi dùng từ nhiều luồng.
    public func relationshipIndex(_ relationship: RelationshipSchema) throws -> RelationshipIndex {
        try RelationshipIndexRegistry.shared.cache(for: self).index(relationship, store: self)
    }
}

/// Cache các chỉ mục của một store. Khoá theo cặp cột để không phụ thuộc trường khác của quan hệ.
final class RelationshipIndexCache: @unchecked Sendable {
    private struct Key: Hashable {
        let many: ColumnID
        let one: ColumnID
    }

    private let lock = NSLock()
    private var built: [Key: RelationshipIndex] = [:]

    /// Giữ khoá trong lúc dựng, để cùng một quan hệ không dựng hai lần.
    func index(_ relationship: RelationshipSchema, store: ColumnStore) throws -> RelationshipIndex {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(many: relationship.manyColumn, one: relationship.oneColumn)
        if let hit = built[key] { return hit }
        let index = try RelationshipIndex.build(relationship, store: store)
        built[key] = index
        return index
    }
}

/// Danh bạ cache theo định danh của store. Store được giữ yếu, nên giải phóng store vẫn được.
final class RelationshipIndexRegistry: @unchecked Sendable {
    static let shared = RelationshipIndexRegistry()

    private struct Entry {
        weak var store: ColumnStore?
        let cache: RelationshipIndexCache
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    func cache(for store: ColumnStore) -> RelationshipIndexCache {
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(store)
        if let entry = entries[key], entry.store === store {
            return entry.cache
        }
        // Store cũ đã giải phóng có thể để lại định danh trùng, nên dọn các mục đã mất store.
        entries = entries.filter { $0.value.store != nil }
        let cache = RelationshipIndexCache()
        entries[key] = Entry(store: store, cache: cache)
        return cache
    }
}
