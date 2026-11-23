// Phase F (T020): nguồn cột chồng. Bảng nạp mới hoặc thay thế (`TableData` trong bộ nhớ) chồng lên kho cột của file gốc;
// bảng còn lại dùng lại cột đã giải mã của kho gốc, nên thêm bảng không làm giải mã lại các bảng lớn.
//
// `schema` là lược đồ hiệu lực (dựng từ `ModelMetadata` sau khi áp `ModelEdits`). Cột của bảng chồng tìm theo tên trong
// `TableData` (tên đã cắt khoảng trắng như ở `ModelMetadata`), kiểu phải khớp lược đồ.

import PBIXKit
import Foundation

public struct OverlayColumnSource: ColumnSource {
    public let schema: ModelSchema
    private let base: ColumnStore
    private let overlays: [TableID: Overlay]

    private struct Overlay: Sendable {
        let data: TableData
        let indexByName: [String: Int]
    }

    public init(base: ColumnStore, schema: ModelSchema, tables: [TableID: TableData]) {
        self.base = base
        self.schema = schema
        self.overlays = tables.mapValues { data in
            var index: [String: Int] = [:]
            for (i, column) in data.columns.enumerated() {
                let key = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
                index[key] = index[key] ?? i
            }
            return Overlay(data: data, indexByName: index)
        }
    }

    public func rowCount(_ table: TableID) throws -> Int {
        if let overlay = overlays[table] { return overlay.data.rowCount }
        guard schema.table(table) != nil else { throw ColumnStoreError.unknownTable(table) }
        guard base.schema.table(table) != nil else { throw ColumnStoreError.storageMissing(lt("bảng \(table) chưa có dữ liệu", "table \(table) has no data yet")) }
        return try base.rowCount(table)
    }

    public func loadColumn(_ id: ColumnID) throws -> ColumnData {
        guard let column = schema.column(id) else { throw ColumnStoreError.unknownColumn(id) }
        if let overlay = overlays[id.table] {
            guard let index = overlay.indexByName[column.name] else {
                throw ColumnStoreError.storageMissing(lt("cột \(column.name) không có trong dữ liệu đã nạp", "column \(column.name) isn't in the loaded data"))
            }
            let data = overlay.data.columns[index].data
            guard data.type == column.type else {
                throw ColumnStoreError.storageMissing(lt("cột \(column.name) có kiểu \(data.type), lược đồ cần \(column.type)", "column \(column.name) has type \(data.type) but the schema needs \(column.type)"))
            }
            return data
        }
        guard base.schema.column(id) != nil else { throw ColumnStoreError.storageMissing(lt("cột \(column.name) chưa có dữ liệu", "column \(column.name) has no data yet")) }
        return try base.column(id)
    }
}
