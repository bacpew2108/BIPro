// Phase F (T003): bảng trong bộ nhớ của Get Data và Power Query. Hợp đồng: specs/010-f-get-data-power-query-t3/data-model.md.
//
// Cột dùng lại `ColumnData` (từ điển + mã) của ColumnStore, nên cùng dạng với dữ liệu đọc từ VertiPaq và với
// dữ liệu ghi lại VertiPaq. Ô lỗi của M (`Error`) không nằm trong cột (kiểu cột giữ nguyên, ô đó là BLANK) mà ở
// `errorMask`: cột → dòng → thông điệp, thưa.

public struct TableColumn: Sendable {
    public let name: String
    public let data: ColumnData

    public init(name: String, data: ColumnData) {
        self.name = name
        self.data = data
    }
}

public enum TableDataError: Error, Equatable, Sendable {
    case emptyColumnName
    case duplicateColumn(String)
    case rowCountMismatch(column: String, expected: Int, actual: Int)
    case errorOutOfRange(column: Int, row: Int)
}

public struct TableData: Sendable {
    public let columns: [TableColumn]
    public let rowCount: Int
    /// cột → dòng → thông điệp lỗi. Chỉ chứa ô lỗi.
    public let errorMask: [Int: [Int: String]]
    /// cột → dòng → bảng lồng (kết quả `Table.NestedJoin`). Cột đó giữ chỗ bằng cột chuỗi trống. Chỉ do `Table.NestedJoin` tạo; mọi phép
    /// biến đổi khác dựng bảng mới nên bỏ phần này (`Table.ExpandTableColumn` sau đó báo cột không phải bảng lồng).
    public let nested: [Int: [TableData]]
    /// cột → dòng → giá trị có cấu trúc của M (bản ghi, danh sách, bảng; T087: kết quả `Json.Document`, `Table.FromList`). ColumnStore không
    /// hiểu giá trị này (MEngine đọc lại); cột giữ chỗ bằng chuỗi "Record"/"List"/"Table" (ô null không có mục). Phép chọn/đổi tên/sắp xếp
    /// cột và cắt dòng giữ lại phần này (`keeping`, `slicingStructured`).
    public let structured: [Int: [Int: any Sendable]]

    /// Bất biến: mọi cột cùng `rowCount`; tên cột không rỗng và duy nhất (phân biệt hoa thường, như M);
    /// mọi ô trong `errorMask` nằm trong bảng.
    public init(columns: [TableColumn], errorMask: [Int: [Int: String]] = [:], nested: [Int: [TableData]] = [:],
                structured: [Int: [Int: any Sendable]] = [:]) throws {
        var seen = Set<String>()
        let rows = columns.first?.data.rowCount ?? 0
        for column in columns {
            guard !column.name.isEmpty else { throw TableDataError.emptyColumnName }
            guard seen.insert(column.name).inserted else { throw TableDataError.duplicateColumn(column.name) }
            guard column.data.rowCount == rows else {
                throw TableDataError.rowCountMismatch(column: column.name, expected: rows, actual: column.data.rowCount)
            }
        }
        for (column, cells) in errorMask {
            for row in cells.keys where column < 0 || column >= columns.count || row < 0 || row >= rows {
                throw TableDataError.errorOutOfRange(column: column, row: row)
            }
        }
        self.columns = columns
        self.rowCount = rows
        for (column, tables) in nested where column < 0 || column >= columns.count || tables.count != rows {
            throw TableDataError.errorOutOfRange(column: column, row: tables.count)
        }
        for (column, cells) in structured {
            for row in cells.keys where column < 0 || column >= columns.count || row < 0 || row >= rows {
                throw TableDataError.errorOutOfRange(column: column, row: row)
            }
        }
        self.errorMask = errorMask
        self.nested = nested
        self.structured = structured.filter { !$0.value.isEmpty }
    }

    /// Bảng mới gồm `columns`, trong đó cột thứ `i` lấy từ cột `sources[i]` của bảng này (nil: cột mới): mang theo bảng lồng và ô có cấu trúc
    /// của cột nguồn. Dùng cho chọn, bỏ, đổi tên, sắp xếp, đổi kiểu cột.
    public func keeping(columns: [TableColumn], sources: [Int?], errorMask: [Int: [Int: String]]) throws -> TableData {
        var keptNested: [Int: [TableData]] = [:]
        var keptStructured: [Int: [Int: any Sendable]] = [:]
        for (index, source) in sources.enumerated() {
            guard let source else { continue }
            if let tables = nested[source] { keptNested[index] = tables }
            if let cells = structured[source] { keptStructured[index] = cells }
        }
        return try TableData(columns: columns, errorMask: errorMask, nested: keptNested, structured: keptStructured)
    }

    /// Ô có cấu trúc sau khi cắt dòng: dòng mới `i` lấy từ dòng `rows[i]`.
    public func slicingStructured(rows: [Int]) -> [Int: [Int: any Sendable]] {
        guard !structured.isEmpty else { return [:] }
        var out: [Int: [Int: any Sendable]] = [:]
        for (column, cells) in structured {
            var kept: [Int: any Sendable] = [:]
            for (newRow, oldRow) in rows.enumerated() { if let value = cells[oldRow] { kept[newRow] = value } }
            if !kept.isEmpty { out[column] = kept }
        }
        return out
    }

    public func index(ofColumn name: String) -> Int? {
        columns.firstIndex { $0.name == name }
    }

    /// Giá trị ô. Ô lỗi trả `.blank` (xem `error(row:column:)`).
    public func value(row: Int, column: Int) -> StoredValue {
        guard column >= 0, column < columns.count else { return .blank }
        return columns[column].data.value(at: row)
    }

    public func error(row: Int, column: Int) -> String? {
        errorMask[column]?[row]
    }

    /// `count` dòng đầu (dùng cho xem trước). Mã hoá lại từ điển theo thứ tự xuất hiện.
    public func prefix(_ count: Int) -> TableData {
        let n = max(0, min(count, rowCount))
        if n == rowCount { return self }
        let taken = columns.map { TableColumn(name: $0.name, data: $0.data.prefix(n)) }
        let mask = errorMask.compactMapValues { cells -> [Int: String]? in
            let kept = cells.filter { $0.key < n }
            return kept.isEmpty ? nil : kept
        }
        let keptNested = nested.mapValues { Array($0.prefix(n)) }
        // Bất biến giữ nguyên (cùng cột, dòng ngắn đi), nên không thể ném.
        return try! TableData(columns: taken, errorMask: mask, nested: keptNested, structured: slicingStructured(rows: Array(0..<n)))
    }
}

extension ColumnData {
    /// `count` dòng đầu của cột, cùng kiểu.
    func prefix(_ count: Int) -> ColumnData {
        let n = max(0, min(count, rowCount))
        switch type {
        case .integer:
            return ColumnBuilder.integers((0..<n).map { if case .integer(let v) = value(at: $0) { v } else { nil } })
        case .currency:
            return ColumnBuilder.currency((0..<n).map { if case .currency(let v) = value(at: $0) { v } else { nil } })
        case .double:
            return ColumnBuilder.doubles((0..<n).map { if case .double(let v) = value(at: $0) { v } else { nil } })
        case .dateTime:
            return ColumnBuilder.dateTimes((0..<n).map { if case .dateTime(let v) = value(at: $0) { v } else { nil } })
        case .boolean:
            return ColumnBuilder.booleans((0..<n).map { if case .boolean(let v) = value(at: $0) { v } else { nil } })
        case .string:
            return ColumnBuilder.strings((0..<n).map { if case .string(let v) = value(at: $0) { v } else { nil } })
        }
    }
}
