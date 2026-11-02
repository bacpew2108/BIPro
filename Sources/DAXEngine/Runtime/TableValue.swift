// Bảng ảo (FC, đợt 2), architecture.md §4.3, §4.4, §5.4.
//
// Mỗi cột có lineage (ColumnID?) để context transition và SUMMARIZE/VALUES giữ đúng cột gốc.
// Các thao tác ở đây chỉ làm việc trên dữ liệu trong bộ nhớ, không gọi evaluator.
import ColumnStore

/// Bảng ảo trong bộ nhớ: tên cột, dòng giá trị, lineage từng cột.
public struct TableValue: Sendable, Hashable {
    public var columns: [String]
    public var rows: [[Value]]
    /// Lineage của từng cột (nil khi cột là biểu thức). Luôn có cùng số phần tử với `columns`.
    public var lineage: [ColumnID?]

    /// Thiếu lineage thì điền nil cho đủ số cột.
    public init(columns: [String], rows: [[Value]], lineage: [ColumnID?] = []) {
        self.columns = columns
        self.rows = rows
        self.lineage = (0..<columns.count).map { $0 < lineage.count ? lineage[$0] : nil }
    }

    /// Vị trí cột có lineage `column`, nil nếu không có.
    public func lineageIndex(of column: ColumnID) -> Int? {
        lineage.firstIndex { $0 == column }
    }

    /// DISTINCT: bỏ dòng trùng, giữ thứ tự xuất hiện đầu tiên, giữ lineage.
    public func distinct() -> TableValue {
        var seen = Set<[Value]>()
        var out: [[Value]] = []
        for row in rows where seen.insert(row).inserted {
            out.append(row)
        }
        return TableValue(columns: columns, rows: out, lineage: lineage)
    }

    /// Chọn và sắp lại cột theo chỉ số (phải hợp lệ), giữ lineage của các cột được chọn.
    public func projecting(_ indices: [Int]) -> TableValue {
        TableValue(columns: indices.map { columns[$0] },
                   rows: rows.map { row in indices.map { row[$0] } },
                   lineage: indices.map { lineage[$0] })
    }

    /// SUMMARIZE (không tổng hợp): DISTINCT trên cột nhóm, giữ lineage của cột nhóm.
    public func summarized(groupBy indices: [Int]) -> TableValue {
        projecting(indices).distinct()
    }

    /// ADDCOLUMNS: thêm cột mới (lineage thường là nil) với giá trị theo từng dòng. Giữ lineage cũ.
    /// Thiếu giá trị thì dòng nhận BLANK.
    public func addingColumn(name: String, lineage newLineage: ColumnID?, values: [Value]) -> TableValue {
        var out = self
        out.columns.append(name)
        out.lineage.append(newLineage)
        out.rows = rows.enumerated().map { i, row in
            row + [i < values.count ? values[i] : .blank]
        }
        return out
    }

    /// CROSSJOIN: tích Descartes, nối cột và lineage của hai bảng.
    public func crossJoined(with other: TableValue) -> TableValue {
        var out: [[Value]] = []
        out.reserveCapacity(rows.count * other.rows.count)
        for left in rows {
            for right in other.rows {
                out.append(left + right)
            }
        }
        return TableValue(columns: columns + other.columns, rows: out, lineage: lineage + other.lineage)
    }

    /// VALUES(col) dựng thành bảng một cột có lineage `column`, từ danh sách giá trị (bỏ trùng).
    public static func values(of column: ColumnID, name: String, values: [Value]) -> TableValue {
        TableValue(columns: [name], rows: values.map { [$0] }, lineage: [column]).distinct()
    }

    /// Context transition cho bảng ảo (§4.3): mỗi cột có lineage thành một `FilterItem` với giá trị của dòng đó.
    /// Cột không có lineage bị bỏ qua. Dòng ngoài phạm vi trả mảng rỗng.
    public func rowFilterItems(row: Int) -> [FilterItem] {
        guard row >= 0, row < rows.count else { return [] }
        var out: [FilterItem] = []
        for (i, column) in lineage.enumerated() {
            if let column {
                out.append(FilterItem(column: column, values: [rows[row][i]]))
            }
        }
        return out
    }
}
