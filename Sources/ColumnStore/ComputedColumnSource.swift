// Phase F (T082): nguồn cột cho cột và bảng tính toán thêm trong phiên. Giá trị do engine tính lần lượt theo thứ tự thao tác rồi đặt vào
// đây (`setColumn`, `setTable`); mọi cột khác đọc từ kho cột bên dưới (kho gốc hoặc kho có bảng nạp chồng), nên thêm cột tính toán không
// làm giải mã lại các bảng lớn. `schema` là lược đồ hiệu lực, có cả cột/bảng tính toán.

import Foundation

public final class ComputedColumnSource: ColumnSource, @unchecked Sendable {
    public let schema: ModelSchema
    private let base: ColumnStore
    private let lock = NSLock()
    private var columns: [ColumnID: ColumnData] = [:]
    private var tables: [TableID: (rowCount: Int, columns: [String: ColumnData])] = [:]

    public init(base: ColumnStore, schema: ModelSchema) {
        self.base = base
        self.schema = schema
    }

    /// Giá trị của một cột tính toán (đủ số dòng của bảng).
    public func setColumn(_ id: ColumnID, _ data: ColumnData) {
        lock.withLock { columns[id] = data }
    }

    /// Dữ liệu của một bảng tính toán; cột tìm theo tên trong lược đồ.
    public func setTable(_ id: TableID, rowCount: Int, columns byName: [String: ColumnData]) {
        lock.withLock { tables[id] = (rowCount, byName) }
    }

    public func rowCount(_ table: TableID) throws -> Int {
        if let computed = lock.withLock({ tables[table] }) { return computed.rowCount }
        guard schema.table(table) != nil else { throw ColumnStoreError.unknownTable(table) }
        return try base.rowCount(table)
    }

    public func loadColumn(_ id: ColumnID) throws -> ColumnData {
        guard let column = schema.column(id) else { throw ColumnStoreError.unknownColumn(id) }
        if let data = lock.withLock({ columns[id] }) { return data }
        if let table = lock.withLock({ tables[id.table] }) {
            guard let data = table.columns[column.name] else {
                throw ColumnStoreError.storageMissing("cột \(column.name) không có trong kết quả bảng tính toán")
            }
            return data
        }
        if column.isCalculated, base.schema.column(id) == nil {
            throw ColumnStoreError.storageMissing("cột tính toán \(column.name) chưa được tính")
        }
        return try base.column(id)
    }
}
