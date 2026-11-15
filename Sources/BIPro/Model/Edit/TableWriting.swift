// Phase F, T022: bảng nạp từ Get Data (`TableData` trong bộ nhớ) → dữ liệu mã hoá cho bộ ghi `.pbix` tầng T3 (`VertiPaqWriter.Values`).
// Kiểu ghi được: số nguyên, thập phân (double), ngày, logic, chuỗi. Tiền tệ chưa quan sát Desktop (không nguồn nào sinh ra kiểu này): báo lỗi tiếng Việt,
// không ghi nửa chừng (FR-051).

import ColumnStore
import Foundation
import PBIXKit

extension TableLoader {
    /// `edits` với mỗi bảng thêm/thay mang `TableData` được gắn dữ liệu mã hoá để ghi. Bảng đã có dữ liệu mã hoá giữ nguyên.
    static func writable(_ edits: ModelEdits) throws -> ModelEdits {
        var out = ModelEdits()
        for edit in edits.items {
            switch edit {
            case .addTable(let table): out.append(.addTable(try writable(table)))
            case .replaceTable(let name, let table): out.append(.replaceTable(name: name, try writable(table)))
            default: out.append(edit)
            }
        }
        return out
    }

    static func writable(_ table: NewTable) throws -> NewTable {
        guard table.enableLoad, let data = table.attachment as? TableData, table.columns.contains(where: { $0.values == nil }) else { return table }
        var columns: [NewTableColumn] = []
        for column in data.columns {
            columns.append(NewTableColumn(name: column.name, values: try values(of: column, rows: data.rowCount)))
        }
        return NewTable(name: table.name, columns: columns, queryExpression: table.queryExpression, enableLoad: table.enableLoad,
                        attachment: data, lineageTag: table.lineageTag)
    }

    static func values(of column: TableColumn, rows count: Int) throws -> VertiPaqWriter.Values {
        let data = column.data
        switch data.type {
        case .integer:
            var v: [Int64?] = []; v.reserveCapacity(count)
            for row in 0..<count { if case .integer(let x) = data.value(at: row) { v.append(x) } else { v.append(nil) } }
            return .int64(v)
        case .double:
            var v: [Double?] = []; v.reserveCapacity(count)
            for row in 0..<count { if case .double(let x) = data.value(at: row) { v.append(x) } else { v.append(nil) } }
            return .double(v)
        case .dateTime:
            var v: [Double?] = []; v.reserveCapacity(count)
            for row in 0..<count { if case .dateTime(let x) = data.value(at: row) { v.append(x) } else { v.append(nil) } }
            return .dateTime(v)
        case .string:
            var v: [String?] = []; v.reserveCapacity(count)
            for row in 0..<count { if case .string(let x) = data.value(at: row) { v.append(x) } else { v.append(nil) } }
            return .string(v)
        case .boolean:
            var v: [Bool?] = []; v.reserveCapacity(count)
            for row in 0..<count { if case .boolean(let x) = data.value(at: row) { v.append(x) } else { v.append(nil) } }
            return .boolean(v)
        case .currency:
            throw ModelEditError("Cột «\(column.name)» kiểu tiền tệ chưa lưu được vào file .pbix (đang làm). Đổi sang số thập phân rồi lưu lại.")
        }
    }
}
