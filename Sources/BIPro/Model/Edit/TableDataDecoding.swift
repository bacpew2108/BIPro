// Phase F (T043): đưa `TableData` (bảng nạp trong bộ nhớ) về dạng `DecodedColumn` mà Table View đọc cho bảng của file.
// Cột theo thứ tự và tên của mô hình hiệu lực; tên trong `TableData` so sau khi cắt khoảng trắng (như `OverlayColumnSource`).

import ColumnStore
import Foundation
import PBIXKit

enum TableDataDecoding {
    static func decode(_ data: TableData, names: [String], types: [ModelMetadata.DataType]) -> [DecodedColumn] {
        var index: [String: Int] = [:]
        for (i, column) in data.columns.enumerated() {
            let key = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            index[key] = index[key] ?? i
        }
        return names.enumerated().map { position, name in
            let type = position < types.count ? types[position] : .string
            guard let i = index[name] else {
                return DecodedColumn(name: name, dataType: type, storage: .empty(count: data.rowCount))
            }
            return DecodedColumn(name: name, dataType: type, storage: storage(of: data.columns[i].data))
        }
    }

    private static func storage(of column: ColumnData) -> DecodedColumn.Storage {
        if case .encoded(let codes, let dictionary) = column.payload {
            let entries = (0..<dictionary.count).map { cell(dictionary.value(at: $0)) }
            let mapped = (0..<column.rowCount).map { Int32(codes.code(at: $0)) - 1 }   // 0 (BLANK) → -1
            return .dictionary(codes: mapped, dictionary: entries)
        }
        // Cột mã hoá theo giá trị hoặc rỗng: đọc từng ô, gom giá trị khác nhau vào từ điển.
        var seen: [StoredValue: Int32] = [:]
        var entries: [CellValue] = []
        var codes: [Int32] = []
        codes.reserveCapacity(column.rowCount)
        for row in 0..<column.rowCount {
            let value = column.value(at: row)
            if value == .blank { codes.append(-1); continue }
            if let code = seen[value] { codes.append(code); continue }
            let code = Int32(entries.count)
            seen[value] = code
            entries.append(cell(value))
            codes.append(code)
        }
        return .dictionary(codes: codes, dictionary: entries)
    }

    private static func cell(_ value: StoredValue) -> CellValue {
        switch value {
        case .blank: .null
        case .integer(let v): .int(v)
        case .double(let v): .double(v)
        case .currency(let v): .decimal(Double(v) / 10_000)
        case .string(let v): .string(v)
        case .boolean(let v): .bool(v)
        case .dateTime(let v): .dateTime(v)
        }
    }
}
