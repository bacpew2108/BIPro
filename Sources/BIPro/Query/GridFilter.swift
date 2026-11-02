import Foundation
import DAXEngine

public struct GridFilter: Sendable {
    public enum SortDirection: Sendable, Hashable {
        case ascending
        case descending
    }

    public struct SortKey: Sendable, Hashable {
        public var column: Int
        public var direction: SortDirection

        public init(column: Int, direction: SortDirection) {
            self.column = column
            self.direction = direction
        }
    }

    /// Nhãn hiển thị của một giá trị: BLANK là "(Trống)", còn lại dùng `ResultFormat.display(_:)`.
    public static func displayLabel(for value: Value) -> String {
        if case .blank = value {
            return "(Trống)"
        }
        return ResultFormat.display(value)
    }

    /// Kiểm tra xem cột có chứa dữ liệu số hoặc ngày không.
    public static func isNumericOrDateColumn(in table: ResultTable, column: Int) -> Bool {
        for row in table.rows.prefix(200) {
            guard column < row.count else { continue }
            switch row[column] {
            case .integer, .double, .currency, .dateTime:
                return true
            case .string, .boolean:
                return false
            case .blank:
                continue
            }
        }
        return false
    }

    /// So sánh hai giá trị: BLANK so như 0 với số và như "" với chuỗi (giống engine).
    public static func compareValues(_ a: Value, _ b: Value) -> ComparisonResult {
        if a == b { return .orderedSame }
        if case .blank = a, case .blank = b { return .orderedSame }

        // Giá trị thay thế cho BLANK khi so sánh với vế kia
        let left: Value
        let right: Value
        switch (a, b) {
        case (.blank, .string):
            left = .string("")
            right = b
        case (.string, .blank):
            left = a
            right = .string("")
        case (.blank, .boolean):
            left = .boolean(false)
            right = b
        case (.boolean, .blank):
            left = a
            right = .boolean(false)
        case (.blank, _):
            left = .double(0)
            right = b
        case (_, .blank):
            left = a
            right = .double(0)
        default:
            left = a
            right = b
        }

        switch (left, right) {
        case (.string(let s1), .string(let s2)):
            let res = s1.localizedCaseInsensitiveCompare(s2)
            if res != .orderedSame { return res }
            return s1.compare(s2)
        case (.boolean(let b1), .boolean(let b2)):
            if b1 == b2 { return .orderedSame }
            return b1 ? .orderedDescending : .orderedAscending
        default:
            if let n1 = numericValue(left), let n2 = numericValue(right) {
                if n1 < n2 { return .orderedAscending }
                if n1 > n2 { return .orderedDescending }
                return .orderedSame
            }
            // Khác kiểu: xếp hạng kiểu để đảm bảo so sánh ổn định
            let r1 = typeRank(left), r2 = typeRank(right)
            if r1 != r2 {
                return r1 < r2 ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        }
    }

    private static func numericValue(_ v: Value) -> Double? {
        switch v {
        case .integer(let x): Double(x)
        case .double(let x): x
        case .currency(let x): Double(x) / 10_000
        case .dateTime(let x): x
        default: nil
        }
    }

    private static func typeRank(_ v: Value) -> Int {
        switch v {
        case .blank: 0
        case .integer, .double, .currency, .dateTime: 1
        case .boolean: 2
        case .string: 3
        }
    }

    /// Lấy danh sách giá trị phân biệt của một cột để hiện trong danh sách.
    /// Sắp theo thứ tự tăng dần của giá trị (không theo chữ).
    public static func distinctValues(in table: ResultTable, column: Int) -> [Value] {
        var seen = Set<Value>()
        var list: [Value] = []
        for row in table.rows {
            guard column < row.count else { continue }
            let val = row[column]
            if seen.insert(val).inserted {
                list.append(val)
            }
        }
        list.sort { a, b in
            let cmp = compareValues(a, b)
            if cmp == .orderedSame {
                // Nếu cả hai so sánh bằng nhau nhưng khác dạng (ví dụ .blank và 0), ưu tiên .blank lên trước
                if a == .blank { return true }
                if b == .blank { return false }
                return false
            }
            return cmp == .orderedAscending
        }
        return list
    }

    /// Lọc theo ô tìm kiếm: chứa chuỗi con, không phân biệt hoa thường.
    public static func filterValues(_ values: [Value], query: String) -> [Value] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return values }
        return values.filter { val in
            displayLabel(for: val).localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Từ trạng thái lọc của mọi cột (cột → tập giá trị được chọn) và một khoá sắp xếp (cột, tăng/giảm),
    /// tính ra mảng chỉ số dòng hiện ra.
    /// Lọc giữa các cột là AND. Khi hai giá trị bằng nhau thì giữ thứ tự gốc.
    public static func filteredAndSortedIndices(
        in table: ResultTable,
        filters: [Int: Set<Value>],
        sortKey: SortKey? = nil
    ) -> [Int] {
        var visible: [Int] = []
        visible.reserveCapacity(table.rows.count)

        for r in 0..<table.rows.count {
            let row = table.rows[r]
            var matches = true
            for (col, allowed) in filters {
                guard col < row.count else { continue }
                if !allowed.contains(row[col]) {
                    matches = false
                    break
                }
            }
            if matches {
                visible.append(r)
            }
        }

        if let sortKey, sortKey.column < table.columns.count {
            let c = sortKey.column
            let ascending = (sortKey.direction == .ascending)
            visible.sort { i, j in
                let vi = table.rows[i][c]
                let vj = table.rows[j][c]
                let cmp = compareValues(vi, vj)
                if cmp == .orderedSame {
                    // Giữ thứ tự gốc khi bằng nhau
                    return i < j
                }
                if ascending {
                    return cmp == .orderedAscending
                } else {
                    return cmp == .orderedDescending
                }
            }
        }

        return visible
    }
}
