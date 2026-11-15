import Foundation
import PBIXKit

/// Phase E (T029): thứ tự và tập dòng hiển thị của lưới Table view khi người dùng sắp xếp hoặc lọc. Chỉ để xem: không đụng
/// mô hình hay dữ liệu, nên không tạo thay đổi chưa lưu.
enum GridRows {
    struct Sort: Equatable {
        var column: Int
        var ascending: Bool
    }

    struct Filter: Equatable {
        var column: Int
        var text: String
    }

    /// Chỉ số dòng gốc theo thứ tự hiển thị; nil khi không sắp xếp và không lọc (hiện nguyên bảng).
    /// Lọc: giá trị cột chứa `text` (không phân biệt hoa thường, dòng trống không khớp). Sắp xếp: số theo giá trị, chữ theo
    /// thứ tự chuẩn của hệ thống không phân biệt hoa thường, dòng trống lên đầu khi tăng dần; bằng nhau giữ thứ tự gốc.
    static func compute(columns: [DecodedColumn], sort: Sort?, filter: Filter?) -> [Int]? {
        let active = filter.flatMap { $0.text.isEmpty ? nil : $0 }
        guard sort != nil || active != nil, let count = columns.first?.count else { return nil }
        var rows = Array(0..<count)
        if let active, columns.indices.contains(active.column) {
            let column = columns[active.column]
            let needle = active.text.lowercased()
            rows = rows.filter { row in
                let value = column[row]
                if case .null = value { return false }
                return value.description.lowercased().contains(needle)
            }
        }
        if let sort, columns.indices.contains(sort.column) {
            let column = columns[sort.column]
            let keys = rows.map { Key(column[$0]) }
            let order = rows.indices.sorted { a, b in
                let c = keys[a].compare(keys[b])
                if c == .orderedSame { return rows[a] < rows[b] }
                return sort.ascending ? c == .orderedAscending : c == .orderedDescending
            }
            rows = order.map { rows[$0] }
        }
        return rows
    }

    private enum Key {
        case null
        case number(Double)
        case text(String)

        init(_ value: CellValue) {
            switch value {
            case .null: self = .null
            case .int(let v): self = .number(Double(v))
            case .double(let v), .decimal(let v), .dateTime(let v): self = .number(v)
            case .bool(let v): self = .number(v ? 1 : 0)
            case .string(let s): self = .text(s)
            }
        }

        func compare(_ other: Key) -> ComparisonResult {
            switch (self, other) {
            case (.null, .null): .orderedSame
            case (.null, _): .orderedAscending
            case (_, .null): .orderedDescending
            case (.number(let a), .number(let b)): a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
            case (.text(let a), .text(let b)): a.localizedStandardCompare(b)
            case (.number, .text): .orderedAscending
            case (.text, .number): .orderedDescending
            }
        }
    }
}
