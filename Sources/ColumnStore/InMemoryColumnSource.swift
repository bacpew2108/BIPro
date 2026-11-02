// Nguồn cột dựng tay, dùng cho test (MiniBank và các test đơn vị). Lead, đợt 0.

public struct InMemoryColumnSource: ColumnSource {
    public let schema: ModelSchema
    private let rowCounts: [TableID: Int]
    private let columns: [ColumnID: ColumnData]

    public init(schema: ModelSchema, rowCounts: [TableID: Int], columns: [ColumnID: ColumnData]) {
        self.schema = schema
        self.rowCounts = rowCounts
        self.columns = columns
    }

    public func rowCount(_ table: TableID) throws -> Int {
        guard let n = rowCounts[table] else { throw ColumnStoreError.unknownTable(table) }
        return n
    }

    public func loadColumn(_ id: ColumnID) throws -> ColumnData {
        guard let c = columns[id] else { throw ColumnStoreError.unknownColumn(id) }
        return c
    }
}

/// Mã hoá một mảng giá trị thành cột đúng kiểu. `nil` là BLANK.
/// Mã hoá theo thứ tự xuất hiện, nên kết quả xác định và dễ kiểm tay trong test.
public enum ColumnBuilder {
    public static func integers(_ values: [Int64?]) -> ColumnData {
        let (codes, uniques) = encode(values)
        return ColumnData(type: .integer, rowCount: values.count, payload: .encoded(codes, .integers(uniques)))
    }

    public static func currency(_ values: [Int64?]) -> ColumnData {
        let (codes, uniques) = encode(values)
        return ColumnData(type: .currency, rowCount: values.count, payload: .encoded(codes, .currency(uniques)))
    }

    public static func doubles(_ values: [Double?]) -> ColumnData {
        let (codes, uniques) = encode(values)
        return ColumnData(type: .double, rowCount: values.count, payload: .encoded(codes, .doubles(uniques)))
    }

    public static func dateTimes(_ values: [Double?]) -> ColumnData {
        let (codes, uniques) = encode(values)
        return ColumnData(type: .dateTime, rowCount: values.count, payload: .encoded(codes, .dates(uniques)))
    }

    public static func booleans(_ values: [Bool?]) -> ColumnData {
        let (codes, uniques) = encode(values)
        return ColumnData(type: .boolean, rowCount: values.count, payload: .encoded(codes, .booleans(uniques)))
    }

    /// Chuỗi rỗng `""` khác BLANK: được giữ như một mục dictionary (architecture.md §2.1).
    public static func strings(_ values: [String?]) -> ColumnData {
        let (codes, uniques) = encode(values)
        var bytes: [UInt8] = []
        var offsets: [UInt32] = [0]
        for s in uniques {
            bytes.append(contentsOf: Array(s.utf8))
            offsets.append(UInt32(bytes.count))
        }
        return ColumnData(type: .string, rowCount: values.count,
                          payload: .encoded(codes, .strings(StringPool(bytes: bytes, offsets: offsets))))
    }

    private static func encode<T: Hashable>(_ values: [T?]) -> (Codes, [T]) {
        var index: [T: Int] = [:]
        var uniques: [T] = []
        var raw: [Int] = []
        raw.reserveCapacity(values.count)
        for value in values {
            guard let value else { raw.append(0); continue }
            if let code = index[value] {
                raw.append(code)
            } else {
                uniques.append(value)
                index[value] = uniques.count
                raw.append(uniques.count)
            }
        }
        let codes: Codes
        if uniques.count <= Int(UInt8.max) {
            codes = .u8(raw.map { UInt8($0) })
        } else if uniques.count <= Int(UInt16.max) {
            codes = .u16(raw.map { UInt16($0) })
        } else {
            codes = .u32(raw.map { UInt32($0) })
        }
        return (codes, uniques)
    }
}
