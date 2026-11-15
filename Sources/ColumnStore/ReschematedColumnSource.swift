// Phase E (R4): nguồn cột dùng lại cột đã nạp của một `ColumnStore` khác, với lược đồ khác ở chỗ quan hệ hoặc thuộc tính
// cột (bảng và cột giữ nguyên chỗ và ID). Đổi quan hệ nhờ vậy không phải giải mã lại cột của bảng lớn.

import Foundation

public struct ReschematedColumnSource: ColumnSource {
    public let schema: ModelSchema
    private let base: ColumnStore

    /// Nil khi `schema` không có đúng các bảng và cột (cùng ID, cùng tên) của kho gốc: khi đó phải dựng nguồn mới từ file.
    public init?(base: ColumnStore, schema: ModelSchema) {
        let old = base.schema.tables, new = schema.tables
        guard old.count == new.count else { return nil }
        for (a, b) in zip(old, new) {
            guard a.id == b.id, a.columns.count == b.columns.count else { return nil }
            for (x, y) in zip(a.columns, b.columns) where x.id != y.id || x.type != y.type { return nil }
        }
        self.base = base
        self.schema = schema
    }

    public func rowCount(_ table: TableID) throws -> Int { try base.rowCount(table) }

    public func loadColumn(_ id: ColumnID) throws -> ColumnData { try base.column(id) }
}
