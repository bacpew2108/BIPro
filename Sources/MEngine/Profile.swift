// Phase F, T056: column profile của Power Query Editor ("Column profiling based on top 1000 rows", QUAN-SAT VM-F3 mục 2).
// Các quy tắc đếm dưới đây là [SUY ĐOÁN] (chưa đối chiếu số liệu cột của Desktop): Empty = null hoặc chuỗi rỗng; Distinct đếm
// cả null và chuỗi rỗng như giá trị riêng, không đếm ô lỗi; Unique = số giá trị chỉ xuất hiện đúng một lần.

import ColumnStore

public struct ValueCount: Sendable, Equatable {
    public let value: MValue
    public let count: Int

    public init(value: MValue, count: Int) {
        self.value = value
        self.count = count
    }
}

public struct ColumnStats: Sendable, Equatable {
    public let name: String
    public let valid: Int
    public let error: Int
    public let empty: Int
    public let distinct: Int
    public let unique: Int
    /// Chỉ cho cột số, ngày, giờ, khoảng thời gian (bỏ qua ô trống và ô lỗi).
    public let min: MValue?
    public let max: MValue?
    /// Chỉ cho cột số.
    public let average: Double?
    /// Tối đa `ColumnProfiler.distributionLimit` giá trị hợp lệ thường gặp nhất (giảm theo số lần, rồi theo giá trị).
    public let distribution: [ValueCount]
}

public enum ColumnProfiler {
    public static let defaultRowLimit = 1000
    public static let distributionLimit = 20

    public static func profile(_ table: TableData, rowLimit: Int = defaultRowLimit) -> [ColumnStats] {
        let rows = max(0, min(rowLimit, table.rowCount))
        return table.columns.indices.map { stats(table, column: $0, rows: rows) }
    }

    private static func stats(_ table: TableData, column: Int, rows: Int) -> ColumnStats {
        var valid = 0, error = 0, empty = 0
        var counts: [StoredValue: Int] = [:]
        var sum = 0.0, numeric = 0
        var minimum: StoredValue?, maximum: StoredValue?
        let type = table.columns[column].data.type
        let ordered = type == .integer || type == .double || type == .currency || type == .dateTime
        for row in 0..<rows {
            if table.error(row: row, column: column) != nil { error += 1; continue }
            let value = table.value(row: row, column: column)
            counts[value, default: 0] += 1
            switch value {
            case .blank: empty += 1
            case .string(let s) where s.isEmpty: empty += 1
            default:
                valid += 1
                if let d = number(value), type != .dateTime { sum += d; numeric += 1 }
                if ordered, let d = number(value) {
                    if minimum == nil || d < number(minimum!)! { minimum = value }
                    if maximum == nil || d > number(maximum!)! { maximum = value }
                }
            }
        }
        let distribution = counts.filter { $0.key != .blank }
            .map { ValueCount(value: MTables.value($0.key), count: $0.value) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return MOperators.compare(a.value, b.value).map { $0 < 0 } ?? false
            }
            .prefix(distributionLimit)
        return ColumnStats(
            name: table.columns[column].name, valid: valid, error: error, empty: empty, distinct: counts.count,
            unique: counts.values.filter { $0 == 1 }.count,
            min: minimum.map(MTables.value), max: maximum.map(MTables.value),
            average: type != .dateTime && numeric > 0 ? sum / Double(numeric) : nil,
            distribution: Array(distribution))
    }

    private static func number(_ value: StoredValue) -> Double? {
        switch value {
        case .integer(let v): Double(v)
        case .double(let v): v
        case .currency(let v): Double(v) / 10_000
        case .dateTime(let v): v
        default: nil
        }
    }
}
