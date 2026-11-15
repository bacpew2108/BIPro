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

    /// Đường nhanh: cột đã mã hoá bằng từ điển hoặc theo giá trị chuyển thẳng sang `ColumnData`, không băm từng ô (bảng hàng triệu dòng).
    /// `nil` khi không có đường nhanh (số nguyên mã hoá theo giá trị có ô trống, kiểu lạ): dùng đường chậm.
    private static func fastData(of column: DecodedColumn) -> ColumnData? {
        let count = column.count
        switch column.storage {
        case .empty:
            return ColumnData(type: daxType(column.dataType), rowCount: count, payload: .allBlank)
        case .dictionary(let codes, let dictionary):
            guard let typed = typedDictionary(dictionary, as: column.dataType) else { return nil }
            let encoded: Codes
            if dictionary.count < Int(UInt8.max) {
                encoded = .u8(codes.map { UInt8(truncatingIfNeeded: $0 + 1) })
            } else if dictionary.count < Int(UInt16.max) {
                encoded = .u16(codes.map { UInt16(truncatingIfNeeded: $0 + 1) })
            } else {
                encoded = .u32(codes.map { UInt32(truncatingIfNeeded: $0 + 1) })
            }
            return ColumnData(type: daxType(column.dataType), rowCount: count, payload: .encoded(encoded, typed))
        case .values(let values):
            switch column.dataType {
            case .double: return ColumnData(type: .double, rowCount: count, payload: .dense(.doubles(values)))
            case .dateTime: return ColumnData(type: .dateTime, rowCount: count, payload: .dense(.dates(values)))
            default: return nil
            }
        }
    }

    private static func daxType(_ type: ModelMetadata.DataType) -> DAXType {
        switch type {
        case .int64: .integer
        case .double: .double
        case .decimal: .currency
        case .dateTime: .dateTime
        case .boolean: .boolean
        default: .string
        }
    }

    private static func typedDictionary(_ cells: [CellValue], as type: ModelMetadata.DataType) -> TypedDictionary? {
        switch type {
        case .int64:
            var out: [Int64] = []; out.reserveCapacity(cells.count)
            for cell in cells { guard case .int(let v) = cell else { return nil }; out.append(v) }
            return .integers(out)
        case .double:
            var out: [Double] = []; out.reserveCapacity(cells.count)
            for cell in cells {
                switch cell { case .double(let v), .decimal(let v): out.append(v); case .int(let v): out.append(Double(v)); default: return nil }
            }
            return .doubles(out)
        case .decimal:
            var out: [Int64] = []; out.reserveCapacity(cells.count)
            for cell in cells {
                switch cell { case .decimal(let v), .double(let v): out.append(Int64((v * 10_000).rounded())); case .int(let v): out.append(v * 10_000); default: return nil }
            }
            return .currency(out)
        case .dateTime:
            var out: [Double] = []; out.reserveCapacity(cells.count)
            for cell in cells { guard case .dateTime(let v) = cell else { return nil }; out.append(v) }
            return .dates(out)
        case .boolean:
            var out: [Bool] = []; out.reserveCapacity(cells.count)
            for cell in cells { guard case .bool(let v) = cell else { return nil }; out.append(v) }
            return .booleans(out)
        default:
            var bytes: [UInt8] = [], offsets: [UInt32] = [0]
            for cell in cells {
                let text: String
                switch cell { case .string(let v): text = v; case .null: text = ""; default: text = cell.description }
                bytes.append(contentsOf: text.utf8)
                offsets.append(UInt32(bytes.count))
            }
            return .strings(StringPool(bytes: bytes, offsets: offsets))
        }
    }

    private static func data(of column: DecodedColumn) -> ColumnData {
        if let fast = fastData(of: column) { return fast }
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
