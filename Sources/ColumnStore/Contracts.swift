// Contract của target ColumnStore (Phase B, đợt 0). Lead sở hữu; đóng băng sau đợt 0.
// Muốn đổi thì gửi yêu cầu cho lead, tối đa một lần mỗi đợt (xem docs/PHASE_B_PLAN.md §3.2).
//
// ColumnStore không biết cú pháp DAX. Nó chỉ biết cột, dòng, quan hệ và lan truyền lọc.
// Vì vậy giá trị lưu ở đây là `StoredValue`, không phải `DAXEngine.Value`.

import Foundation

// MARK: - Định danh

/// Số thứ tự bảng, lấy từ `Table.ID` của metadata.
public struct TableID: Hashable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(raw: Int) { self.raw = raw }
    public var description: String { "T\(raw)" }
}

/// Cột, lấy từ `Column.ID` của metadata (duy nhất trong cả model). `table` là bảng chủ.
public struct ColumnID: Hashable, Sendable, CustomStringConvertible {
    public let table: TableID
    public let index: Int
    public init(table: TableID, index: Int) {
        self.table = table
        self.index = index
    }
    public var description: String { "\(table).C\(index)" }
}

/// Quan hệ, là vị trí trong danh sách `ModelSchema.relationships`.
public struct RelationshipID: Hashable, Sendable {
    public let raw: Int
    public init(raw: Int) { self.raw = raw }
}

// MARK: - Kiểu và giá trị lưu

/// Kiểu dữ liệu của cột theo góc nhìn của engine.
/// `currency` là Int64 đã nhân 10⁴ (cùng quy ước với `decimal` của Power BI).
public enum DAXType: Sendable, Hashable {
    case integer, double, currency, string, boolean, dateTime
}

/// Giá trị đọc ra từ một ô. `DAXEngine.Value` có cùng hình dạng và chuyển đổi trực tiếp.
public enum StoredValue: Sendable, Hashable {
    case blank
    case integer(Int64)
    case double(Double)
    case currency(Int64)
    case string(String)
    case boolean(Bool)
    case dateTime(Double)
}

// MARK: - Biểu diễn cột (architecture.md §2.1)

/// Mã dictionary của từng dòng. `0` = BLANK, `k` = mục `k - 1` của dictionary.
public enum Codes: Sendable {
    case u8([UInt8])
    case u16([UInt16])
    case u32([UInt32])

    public var count: Int {
        switch self {
        case .u8(let c): c.count
        case .u16(let c): c.count
        case .u32(let c): c.count
        }
    }

    /// Mã của dòng `row`. Dòng ngoài phạm vi trả 0 (BLANK).
    public func code(at row: Int) -> Int {
        guard row >= 0, row < count else { return 0 }
        switch self {
        case .u8(let c): return Int(c[row])
        case .u16(let c): return Int(c[row])
        case .u32(let c): return Int(c[row])
        }
    }
}

/// Chuỗi UTF-8 nối liền một khối, kèm mảng offset (`offsets.count == số mục + 1`).
public struct StringPool: Sendable, Hashable {
    public let bytes: [UInt8]
    public let offsets: [UInt32]

    public init(bytes: [UInt8], offsets: [UInt32]) {
        self.bytes = bytes
        self.offsets = offsets
    }

    public var count: Int { max(0, offsets.count - 1) }

    public func string(at k: Int) -> String {
        guard k >= 0, k < count else { return "" }
        let lo = Int(offsets[k]), hi = Int(offsets[k + 1])
        return String(decoding: bytes[lo..<hi], as: UTF8.self)
    }
}

/// Dictionary có kiểu. Mục thứ k (từ 0) tương ứng mã k + 1.
public enum TypedDictionary: Sendable {
    case integers([Int64])
    case doubles([Double])
    case currency([Int64])
    case dates([Double])
    case booleans([Bool])
    case strings(StringPool)

    public var count: Int {
        switch self {
        case .integers(let v): v.count
        case .doubles(let v): v.count
        case .currency(let v): v.count
        case .dates(let v): v.count
        case .booleans(let v): v.count
        case .strings(let p): p.count
        }
    }

    public func value(at k: Int) -> StoredValue {
        guard k >= 0, k < count else { return .blank }
        switch self {
        case .integers(let v): return .integer(v[k])
        case .doubles(let v): return .double(v[k])
        case .currency(let v): return .currency(v[k])
        case .dates(let v): return .dateTime(v[k])
        case .booleans(let v): return .boolean(v[k])
        case .strings(let p): return .string(p.string(at: k))
        }
    }
}

/// Cột mã hoá theo giá trị (`amount`, `balance_after`…). NaN là BLANK với số thực và ngày.
public enum DenseValues: Sendable {
    case integers([Int64], blanks: RowSet?)
    case doubles([Double])
    case dates([Double])
}

public enum ColumnPayload: Sendable {
    case encoded(Codes, TypedDictionary)
    case dense(DenseValues)
    case allBlank
}

/// Một cột đã nạp. `rowCount` là số dòng thật của bảng. Dòng `rowCount` (blank row ảo của quan hệ)
/// và mọi dòng ngoài phạm vi đều trả `.blank`.
public struct ColumnData: Sendable {
    public let type: DAXType
    public let rowCount: Int
    public let payload: ColumnPayload

    public init(type: DAXType, rowCount: Int, payload: ColumnPayload) {
        self.type = type
        self.rowCount = rowCount
        self.payload = payload
    }

    public func value(at row: Int) -> StoredValue {
        guard row >= 0, row < rowCount else { return .blank }
        switch payload {
        case .allBlank:
            return .blank
        case .encoded(let codes, let dict):
            let c = codes.code(at: row)
            return c == 0 ? .blank : dict.value(at: c - 1)
        case .dense(let dense):
            switch dense {
            case .integers(let v, let blanks):
                if let blanks, blanks.contains(row) { return .blank }
                return type == .currency ? .currency(v[row]) : .integer(v[row])
            case .doubles(let v):
                return v[row].isNaN ? .blank : .double(v[row])
            case .dates(let v):
                return v[row].isNaN ? .blank : .dateTime(v[row])
            }
        }
    }
}

// MARK: - Bộ lọc mức cột và mức bảng

/// Tập mã của một cột (sắp tăng, không trùng; 0 = BLANK). Đây là dạng lọc theo giá trị ở tầng cột.
public struct CodeSet: Sendable, Hashable {
    public let column: ColumnID
    public let codes: [UInt32]

    public init(column: ColumnID, codes: [UInt32]) {
        self.column = column
        self.codes = codes
    }
}

/// Bộ lọc mức bảng: tập dòng đã biết là được phép.
public struct TableFilter: Sendable, Hashable {
    public let table: TableID
    public let rows: RowSet

    public init(table: TableID, rows: RowSet) {
        self.table = table
        self.rows = rows
    }
}

public enum CrossFilterBehavior: Sendable, Hashable {
    case oneDirection, bothDirections, automatic
}

/// Ghi đè quan hệ do `USERELATIONSHIP` hoặc `CROSSFILTER` đặt. `nil` nghĩa là giữ nguyên.
public struct RelationshipOverride: Sendable, Hashable {
    public let relationship: RelationshipID
    public let isActive: Bool?
    public let crossFilter: CrossFilterBehavior?

    public init(relationship: RelationshipID, isActive: Bool? = nil, crossFilter: CrossFilterBehavior? = nil) {
        self.relationship = relationship
        self.isActive = isActive
        self.crossFilter = crossFilter
    }
}

// MARK: - Lược đồ model

/// Quan hệ M:1 (hoặc 1:1, M:M). `manyColumn` là phía nhiều, `oneColumn` là phía một.
public struct RelationshipSchema: Sendable, Hashable {
    public let id: RelationshipID
    public let name: String
    public let manyColumn: ColumnID
    public let oneColumn: ColumnID
    public let isActive: Bool
    public let crossFilter: CrossFilterBehavior

    public init(id: RelationshipID, name: String, manyColumn: ColumnID, oneColumn: ColumnID,
                isActive: Bool, crossFilter: CrossFilterBehavior) {
        self.id = id
        self.name = name
        self.manyColumn = manyColumn
        self.oneColumn = oneColumn
        self.isActive = isActive
        self.crossFilter = crossFilter
    }
}

/// Lược đồ đã chuẩn hoá cho engine. Dựng từ metadata bằng `ModelSchema(metadata:)`.
public struct ModelSchema: Sendable {
    public struct Column: Sendable, Hashable {
        public let id: ColumnID
        public let name: String
        public let type: DAXType
        public let isCalculated: Bool
        public let isHidden: Bool
        public let isKey: Bool
        public let sortByColumn: ColumnID?
        public let formatString: String?

        public init(id: ColumnID, name: String, type: DAXType, isCalculated: Bool, isHidden: Bool,
                    isKey: Bool, sortByColumn: ColumnID?, formatString: String?) {
            self.id = id
            self.name = name
            self.type = type
            self.isCalculated = isCalculated
            self.isHidden = isHidden
            self.isKey = isKey
            self.sortByColumn = sortByColumn
            self.formatString = formatString
        }
    }

    public struct Table: Sendable, Hashable {
        public let id: TableID
        public let name: String
        public let isHidden: Bool
        /// `false` cho bảng hệ thống (`H$`, `R$`, `U$`).
        public let isUserTable: Bool
        /// `true` khi `Table.DataCategory` là `Time` (bảng ngày đã đánh dấu).
        public let isDateTable: Bool
        public let columns: [Column]

        public init(id: TableID, name: String, isHidden: Bool, isUserTable: Bool, isDateTable: Bool,
                    columns: [Column]) {
            self.id = id
            self.name = name
            self.isHidden = isHidden
            self.isUserTable = isUserTable
            self.isDateTable = isDateTable
            self.columns = columns
        }
    }

    public let culture: String
    public let tables: [Table]
    public let relationships: [RelationshipSchema]

    public init(culture: String, tables: [Table], relationships: [RelationshipSchema]) {
        self.culture = culture
        self.tables = tables
        self.relationships = relationships
    }

    /// Tra cứu không phân biệt hoa thường, vì tên DAX không phân biệt hoa thường.
    public func table(named name: String) -> Table? {
        let key = name.lowercased()
        return tables.first { $0.name.lowercased() == key }
    }

    public func table(_ id: TableID) -> Table? {
        tables.first { $0.id == id }
    }

    public func column(_ id: ColumnID) -> Column? {
        table(id.table)?.columns.first { $0.id == id }
    }

    public func column(table tableName: String, name: String) -> Column? {
        guard let t = table(named: tableName) else { return nil }
        let key = name.lowercased()
        return t.columns.first { $0.name.lowercased() == key }
    }
}

// MARK: - Nguồn dữ liệu và kho cột

public enum ColumnStoreError: Error, Sendable, Hashable {
    case notImplemented(String)
    case unknownTable(TableID)
    case unknownColumn(ColumnID)
    case storageMissing(String)
}

/// Nguồn cột. `PBIXColumnSource` (đợt 1a) đọc từ ABF; `InMemoryColumnSource` dùng cho test.
public protocol ColumnSource: Sendable {
    var schema: ModelSchema { get }
    /// Số dòng thật của bảng, không kể blank row ảo.
    func rowCount(_ table: TableID) throws -> Int
    /// Đọc đầy đủ một cột. `ColumnStore` gọi lười, mỗi cột một lần.
    func loadColumn(_ id: ColumnID) throws -> ColumnData
}
