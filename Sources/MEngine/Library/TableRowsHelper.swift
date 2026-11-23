// Phase F: Trợ giúp cho thư viện dòng TableRowsLibrary (cắt dòng, dịch errorMask, tối ưu hiệu năng).
import PBIXKit
import Foundation
import ColumnStore

enum TableRowsHelper {
    /// Cắt dòng từ `table` theo danh sách chỉ số dòng `rowIndices`, dịch chuyển `errorMask` tương ứng.
    static func sliceRows(table: TableData, rowIndices: [Int]) throws -> TableData {
        guard !table.columns.isEmpty else {
            return try TableData(columns: [], errorMask: [:])
        }
        var newColumns: [TableColumn] = []
        newColumns.reserveCapacity(table.columns.count)

        for col in table.columns {
            let data = col.data
            let slicedData: ColumnData = sliceColumn(data: data, rowIndices: rowIndices)
            newColumns.append(TableColumn(name: col.name, data: slicedData))
        }

        // Dịch chuyển errorMask
        var newMask: [Int: [Int: String]] = [:]
        for (colIdx, cellErrors) in table.errorMask {
            var colErrors: [Int: String] = [:]
            for (newIdx, oldIdx) in rowIndices.enumerated() {
                if let msg = cellErrors[oldIdx] {
                    colErrors[newIdx] = msg
                }
            }
            if !colErrors.isEmpty {
                newMask[colIdx] = colErrors
            }
        }

        let nested = table.nested.mapValues { tables in rowIndices.map { tables[$0] } }
        return try TableData(columns: newColumns, errorMask: newMask, nested: nested, structured: table.slicingStructured(rows: rowIndices))
    }

    private static func sliceColumn(data: ColumnData, rowIndices: [Int]) -> ColumnData {
        let count = rowIndices.count
        switch data.payload {
        case .allBlank:
            return ColumnData(type: data.type, rowCount: count, payload: .allBlank)
        case .encoded(let codes, let dict):
            let newCodes: Codes
            switch codes {
            case .u8(let c):
                var newC = [UInt8]()
                newC.reserveCapacity(count)
                for r in rowIndices { newC.append(c[r]) }
                newCodes = .u8(newC)
            case .u16(let c):
                var newC = [UInt16]()
                newC.reserveCapacity(count)
                for r in rowIndices { newC.append(c[r]) }
                newCodes = .u16(newC)
            case .u32(let c):
                var newC = [UInt32]()
                newC.reserveCapacity(count)
                for r in rowIndices { newC.append(c[r]) }
                newCodes = .u32(newC)
            }
            return ColumnData(type: data.type, rowCount: count, payload: .encoded(newCodes, dict))
        case .dense(let dense):
            switch dense {
            case .integers(let arr, let blanks):
                var newArr = [Int64]()
                newArr.reserveCapacity(count)
                for r in rowIndices { newArr.append(arr[r]) }
                let vals: [Int64?] = rowIndices.map { r in
                    if blanks?.contains(r) == true { return nil }
                    return arr[r]
                }
                return ColumnBuilder.integers(vals)
            case .doubles(let arr):
                var newArr = [Double]()
                newArr.reserveCapacity(count)
                for r in rowIndices { newArr.append(arr[r]) }
                return ColumnData(type: data.type, rowCount: count, payload: .dense(.doubles(newArr)))
            case .dates(let arr):
                var newArr = [Double]()
                newArr.reserveCapacity(count)
                for r in rowIndices { newArr.append(arr[r]) }
                return ColumnData(type: data.type, rowCount: count, payload: .dense(.dates(newArr)))
            }
        }
    }

    /// Trích xuất danh sách tên cột từ đối số MValue (chuỗi hoặc danh sách chuỗi).
    static func extractColumnNames(_ value: MValue, functionName: String) throws -> [String] {
        switch value {
        case .text(let s):
            return [s]
        case .list(let items):
            var names: [String] = []
            for item in items {
                guard case .text(let s) = item else {
                    throw MError.expression(lt("\(functionName): tên cột trong danh sách phải là text, nhận \(item.kindName)", "\(functionName): column names in the list must be text, got \(item.kindName)"))
                }
                names.append(s)
            }
            return names
        default:
            throw MError.expression(lt("\(functionName): đối số cột phải là text hoặc list text, nhận \(value.kindName)", "\(functionName): the column argument must be text or a list of text, got \(value.kindName)"))
        }
    }
}
