// ColumnData (CS, đợt 1a): phần cài đặt bổ sung cho cột đã nạp.
//
// Kiểu `ColumnData` và các kiểu đi kèm vẫn ở Contracts.swift (LEAD). File này chỉ thêm extension,
// và lớp `ColumnIndex` giữ chỉ mục tính lười: posting list (mã → dòng), sortRank và code(of:).
// Cache nằm trong class, không đổi struct trong contract.

import Foundation

extension ColumnData {
    /// `true` nếu cột mã hoá bằng dictionary, kể cả cột allBlank. Cột dense trả `false`.
    public var isEncoded: Bool {
        switch payload {
        case .encoded, .allBlank: true
        case .dense: false
        }
    }

    /// Số mục dictionary, không kể BLANK. Cột dense và allBlank trả 0.
    public var dictionaryCount: Int {
        if case .encoded(_, let dictionary) = payload { return dictionary.count }
        return 0
    }

    /// Mã của dòng (0 = BLANK). Cột allBlank trả 0 ở mọi dòng. Cột dense trả nil.
    /// Dòng ngoài phạm vi trả 0, giống `Codes.code(at:)`.
    public func code(atRow row: Int) -> Int? {
        switch payload {
        case .encoded(let codes, _): codes.code(at: row)
        case .allBlank: 0
        case .dense: nil
        }
    }

    /// Giá trị của mục dictionary có mã `code` (mục `code - 1`). `nil` với cột dense, mã 0 hoặc mã ngoài phạm vi.
    public func dictionaryValue(code: Int) -> StoredValue? {
        guard case .encoded(_, let dictionary) = payload, code >= 1, code <= dictionary.count else { return nil }
        return dictionary.value(at: code - 1)
    }
}

/// Chỉ mục tính lười của một cột (CS). Mỗi cột một đối tượng, và `ColumnStore` giữ đối tượng này.
///
/// Mỗi cache (posting list, sortRank, bảng ngược giá trị → mã) được tính đúng một lần, dưới khoá riêng,
/// nên dùng từ nhiều luồng là an toàn. Cột dense không có mã, nên các hàm mã trả `nil`.
public final class ColumnIndex: @unchecked Sendable {
    /// Cột gốc. `ColumnData` là struct bất biến, nên giữ bản sao chỉ tốn tham chiếu mảng.
    public let column: ColumnData

    private let lock = NSLock()
    private var postings: Postings?
    private var sortRanks: [Int]?
    private var codesByValue: [StoredValue: Int]?

    /// Dòng không BLANK của cột dense, sắp theo (giá trị, dòng), kèm khoá số cùng thứ tự.
    private struct DenseOrder {
        let rows: [UInt32]
        /// Khoá cho cột số thực và ngày (payload `.doubles` hoặc `.dates`).
        let doubles: [Double]
        /// Khoá cho cột nguyên và tiền tệ (payload `.integers`).
        let integers: [Int64]
        /// Số dòng BLANK (NaN, hoặc đánh dấu blank của cột nguyên).
        let blankCount: Int
    }

    private var denseOrderCache: DenseOrder?

    private struct Postings {
        /// Mã c có các dòng `rows[offsets[c]..<offsets[c + 1]]`, tăng dần. Độ dài là số mã + 1.
        let offsets: [Int]
        let rows: [UInt32]
    }

    public init(column: ColumnData) {
        self.column = column
    }

    /// Số mã có thể (0 đến `dictionaryCount`). `nil` với cột dense.
    public var codeLimit: Int? {
        column.isEncoded ? column.dictionaryCount + 1 : nil
    }

    /// Các dòng có mã `code`, tăng dần, kể cả dòng BLANK khi `code == 0`. `nil` với cột dense hoặc mã ngoài phạm vi.
    public func postings(forCode code: Int) -> ArraySlice<UInt32>? {
        guard let limit = codeLimit, code >= 0, code < limit else { return nil }
        let table = postingTable()
        return table.rows[table.offsets[code]..<table.offsets[code + 1]]
    }

    /// Các dòng có mã `code` dưới dạng `RowSet` (universe = số dòng + 1).
    public func rowSet(forCode code: Int) -> RowSet? {
        guard let slice = postings(forCode: code) else { return nil }
        return RowSet(universe: column.rowCount + 1, sortedRows: Array(slice))
    }

    /// Thứ hạng sắp xếp của mã `code`. BLANK (mã 0) đứng đầu với hạng 0; các mã khác từ 1.
    /// `nil` với cột dense hoặc mã ngoài phạm vi.
    public func sortRank(ofCode code: Int) -> Int? {
        guard let limit = codeLimit, code >= 0, code < limit else { return nil }
        return rankTable()[code]
    }

    /// Mã theo thứ tự sắp xếp, bắt đầu từ BLANK. `nil` với cột dense.
    public func codesInSortOrder() -> [Int]? {
        guard let limit = codeLimit else { return nil }
        let ranks = rankTable()
        var order = [Int](repeating: 0, count: limit)
        for code in 0..<limit { order[ranks[code]] = code }
        return order
    }

    /// Mã của giá trị đúng kiểu, với BLANK là 0. `nil` nếu giá trị không có trong dictionary hoặc cột dense.
    public func code(of value: StoredValue) -> Int? {
        guard codeLimit != nil else { return nil }
        if value == .blank { return 0 }
        return codeTable()[value]
    }

    /// Số dòng BLANK thật của cột dense (NaN hoặc đánh dấu blank). `nil` với cột mã hoá.
    public func denseBlankRowCount() -> Int? {
        guard case .dense = column.payload else { return nil }
        return denseOrderTable().blankCount
    }

    /// Các dòng (tăng dần) của cột dense có giá trị đúng bằng một trong `targets`, theo `StoredValue ==`.
    /// Dòng BLANK không khớp mục nào, nên `targets` có BLANK phải dùng đường quét. Trả nil nếu cột không phải dense.
    public func denseRows(matching targets: [StoredValue]) -> [UInt32]? {
        guard case .dense(let dense) = column.payload else { return nil }
        let order = denseOrderTable()
        var out: [UInt32] = []
        for target in targets {
            switch (target, dense) {
            case (.double(let d), .doubles), (.dateTime(let d), .dates):
                guard !d.isNaN else { continue }
                let lo = ColumnIndex.lowerBound(order.doubles, d)
                let hi = ColumnIndex.upperBound(order.doubles, d)
                out.append(contentsOf: order.rows[lo..<hi])
            case (.integer(let n), .integers):
                guard column.type == .integer else { continue }
                let lo = ColumnIndex.lowerBound(order.integers, n)
                let hi = ColumnIndex.upperBound(order.integers, n)
                out.append(contentsOf: order.rows[lo..<hi])
            case (.currency(let n), .integers):
                guard column.type == .currency else { continue }
                let lo = ColumnIndex.lowerBound(order.integers, n)
                let hi = ColumnIndex.upperBound(order.integers, n)
                out.append(contentsOf: order.rows[lo..<hi])
            default:
                continue
            }
        }
        if targets.count > 1 { out.sort() }
        return out
    }

    private static func lowerBound<T: Comparable>(_ a: [T], _ x: T) -> Int {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private static func upperBound<T: Comparable>(_ a: [T], _ x: T) -> Int {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] <= x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func denseOrderTable() -> DenseOrder {
        lock.lock()
        defer { lock.unlock() }
        if let denseOrderCache { return denseOrderCache }
        let built = ColumnIndex.buildDenseOrder(column)
        denseOrderCache = built
        return built
    }

    /// Sắp các dòng không BLANK của cột dense. Mọi dòng trong [0, rowCount) được xét, như `ColumnData.value(at:)`.
    private static func buildDenseOrder(_ column: ColumnData) -> DenseOrder {
        let n = column.rowCount
        guard case .dense(let dense) = column.payload else {
            return DenseOrder(rows: [], doubles: [], integers: [], blankCount: 0)
        }
        switch dense {
        case .doubles(let v), .dates(let v):
            var pairs: [(key: Double, row: UInt32)] = []
            pairs.reserveCapacity(n)
            var blanks = 0
            for r in 0..<n {
                let x = v[r]
                if x.isNaN {
                    blanks += 1
                } else {
                    pairs.append((x, UInt32(r)))
                }
            }
            pairs.sort { $0.key < $1.key || ($0.key == $1.key && $0.row < $1.row) }
            return DenseOrder(rows: pairs.map(\.row), doubles: pairs.map(\.key), integers: [], blankCount: blanks)
        case .integers(let v, let blankRows):
            var pairs: [(key: Int64, row: UInt32)] = []
            pairs.reserveCapacity(n)
            var blanks = 0
            for r in 0..<n {
                if let blankRows, blankRows.contains(r) {
                    blanks += 1
                } else {
                    pairs.append((v[r], UInt32(r)))
                }
            }
            pairs.sort { $0.key < $1.key || ($0.key == $1.key && $0.row < $1.row) }
            return DenseOrder(rows: pairs.map(\.row), doubles: [], integers: pairs.map(\.key), blankCount: blanks)
        }
    }

    // MARK: - Tính lười

    private func postingTable() -> Postings {
        lock.lock()
        defer { lock.unlock() }
        if let postings { return postings }
        let built = ColumnIndex.buildPostings(column)
        postings = built
        return built
    }

    private func rankTable() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        if let sortRanks { return sortRanks }
        let built = ColumnIndex.buildSortRanks(column)
        sortRanks = built
        return built
    }

    private func codeTable() -> [StoredValue: Int] {
        lock.lock()
        defer { lock.unlock() }
        if let codesByValue { return codesByValue }
        var table: [StoredValue: Int] = [:]
        for code in stride(from: 1, through: column.dictionaryCount, by: 1) {
            if let value = column.dictionaryValue(code: code), table[value] == nil {
                table[value] = code
            }
        }
        codesByValue = table
        return table
    }

    /// Sắp các dòng theo mã bằng đếm và prefix sum, nên thời gian là O(số dòng + số mã).
    private static func buildPostings(_ column: ColumnData) -> Postings {
        let n = column.rowCount
        let limit = column.dictionaryCount + 1
        var offsets = [Int](repeating: 0, count: limit + 1)
        for row in 0..<n {
            offsets[(column.code(atRow: row) ?? 0) + 1] += 1
        }
        for code in 0..<limit {
            offsets[code + 1] += offsets[code]
        }
        var cursor = offsets
        var rows = [UInt32](repeating: 0, count: n)
        for row in 0..<n {
            let code = column.code(atRow: row) ?? 0
            rows[cursor[code]] = UInt32(row)
            cursor[code] += 1
        }
        return Postings(offsets: offsets, rows: rows)
    }

    /// Thứ hạng theo thứ tự sắp xếp. Chuỗi so theo chữ thường Unicode, hoà thì so theo nội dung.
    /// Đây là xấp xỉ, chưa phải collation của model (ví dụ "Đ" chưa đứng sau "D" như trong tiếng Việt).
    private static func buildSortRanks(_ column: ColumnData) -> [Int] {
        let k = column.dictionaryCount
        var values = [StoredValue](repeating: .blank, count: k + 1)
        var lowered = [String](repeating: "", count: k + 1)
        for code in stride(from: 1, through: k, by: 1) {
            let value = column.dictionaryValue(code: code) ?? .blank
            values[code] = value
            if case .string(let s) = value { lowered[code] = s.lowercased() }
        }
        var order = Array(stride(from: 1, through: k, by: 1))
        order.sort { a, b in
            if case .string(let x) = values[a], case .string(let y) = values[b] {
                if lowered[a] != lowered[b] { return lowered[a] < lowered[b] }
                return x < y
            }
            return isLess(values[a], values[b])
        }
        var ranks = [Int](repeating: 0, count: k + 1)
        for (position, code) in order.enumerated() {
            ranks[code] = position + 1
        }
        return ranks
    }

    /// So sánh giá trị cùng kiểu khác chuỗi. Khác kiểu thì trả `false`.
    private static func isLess(_ a: StoredValue, _ b: StoredValue) -> Bool {
        switch (a, b) {
        case let (.integer(x), .integer(y)), let (.currency(x), .currency(y)): x < y
        case let (.double(x), .double(y)), let (.dateTime(x), .dateTime(y)): x < y
        case let (.boolean(x), .boolean(y)): !x && y
        default: false
        }
    }
}
