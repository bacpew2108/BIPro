// Phase F (T060): ngược với `TableDataDecoding`: bảng đã có trong file (cột đã giải mã) thành `TableData` để Query Editor dùng làm
// kết quả của các bước đọc từ file. Kiểu cột theo kiểu mô hình; ô không khớp kiểu (không xảy ra với dữ liệu đọc từ VertiPaq) thành trống.

import ColumnStore
import Foundation
import PBIXKit

enum TableDataEncoding {
    /// `nil` khi bảng rỗng cột hoặc tên cột không hợp lệ (trùng, rỗng): khi đó Query Editor xem trước báo thiếu dữ liệu.
    static func tableData(from columns: [DecodedColumn]) -> TableData? {
        guard !columns.isEmpty else { return nil }
        let converted = columns.map { TableColumn(name: $0.name, data: data(of: $0)) }
        return try? TableData(columns: converted)
    }

    private static func data(of column: DecodedColumn) -> ColumnData {
        let rows = 0..<column.count
        switch column.dataType {
        case .int64:
            return ColumnBuilder.integers(rows.map { row in
                switch column[row] {
                case .int(let v): v
                case .double(let v), .decimal(let v): v.isFinite ? Int64(v) : nil
                default: nil
                }
            })
        case .double:
            return ColumnBuilder.doubles(rows.map { row in
                switch column[row] {
                case .double(let v), .decimal(let v): v
                case .int(let v): Double(v)
                default: nil
                }
            })
        case .decimal:
            return ColumnBuilder.currency(rows.map { row in
                switch column[row] {
                case .decimal(let v), .double(let v): v.isFinite ? Int64((v * 10_000).rounded()) : nil
                case .int(let v): v * 10_000
                default: nil
                }
            })
        case .dateTime:
            return ColumnBuilder.dateTimes(rows.map { row in
                if case .dateTime(let v) = column[row] { v } else { nil }
            })
        case .boolean:
            return ColumnBuilder.booleans(rows.map { row in
                if case .bool(let v) = column[row] { v } else { nil }
            })
        default:
            return ColumnBuilder.strings(rows.map { row in
                switch column[row] {
                case .null: nil
                case .string(let v): v
                default: column[row].description
                }
            })
        }
    }
}
