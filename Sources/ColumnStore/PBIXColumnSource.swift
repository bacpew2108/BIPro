// PBIXColumnSource (CS, đợt 1a): ColumnSource đọc từ DataModel của một .pbix (ABF đã giải nén).
//
// Đọc bằng `VertiPaq.decodeColumn` (PBIXKit, public), rồi đổi `DecodedColumn` sang `ColumnData` theo
// architecture.md §2.1:
// - mã dictionary: -1 → 0 (BLANK), k → k + 1; độ rộng u8/u16/u32 theo số mục (k + 1 ≤ 255 thì u8, ...);
// - int64 → integer; double → double; decimal → currency, round(v × 10⁴); dateTime → dateTime;
//   boolean → boolean; string → strings (StringPool). Chuỗi rỗng khác BLANK;
// - cột số có hơn 65535 giá trị khác nhau, hoặc mã hoá tốn bộ nhớ hơn dạng dense → dense.
//   Chuỗi và boolean không bao giờ dense.
//
// Struct này bất biến sau init, nên an toàn khi nhiều luồng đọc cùng lúc.

import Foundation
import PBIXKit

public struct PBIXColumnSource: ColumnSource {
    /// Một cột lưu trữ: kiểu DAX và vị trí trong ABF (metadata `ColumnStorage`).
    private struct Entry: Sendable {
        let type: DAXType
        let storage: ModelMetadata.ColumnStorage
    }

    public let schema: ModelSchema
    private let abf: ABFBackup
    private let rowCounts: [TableID: Int]
    private let entries: [ColumnID: Entry]

    /// Mở một file .pbix và đọc DataModel của nó.
    public init(url: URL) throws {
        try self.init(pbix: try PBIXFile(url: url))
    }

    public init(pbix: PBIXFile) throws {
        let (abf, _) = try pbix.loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        try self.init(abf: abf, metadata: metadata)
    }

    /// Dựng từ ABF và metadata đã có. Tính số dòng của mỗi bảng từ siêu dữ liệu đoạn, không giải mã dữ liệu.
    public init(abf: ABFBackup, metadata: ModelMetadata) throws {
        let schema = ModelSchema(metadata: metadata)
        var rowCounts: [TableID: Int] = [:]
        var entries: [ColumnID: Entry] = [:]
        for table in schema.tables {
            var firstStorage: ModelMetadata.ColumnStorage?
            for column in table.columns {
                guard let storage = metadata.storage(table: table.name, column: column.name) else { continue }
                entries[column.id] = Entry(type: column.type, storage: storage)
                if firstStorage == nil { firstStorage = storage }
            }
            if let firstStorage {
                rowCounts[table.id] = try VertiPaq.rowCount(firstStorage, abf: abf)
            }
        }
        self.schema = schema
        self.abf = abf
        self.rowCounts = rowCounts
        self.entries = entries
    }

    public func rowCount(_ table: TableID) throws -> Int {
        guard schema.table(table) != nil else { throw ColumnStoreError.unknownTable(table) }
        return rowCounts[table] ?? 0
    }

    public func loadColumn(_ id: ColumnID) throws -> ColumnData {
        guard let entry = entries[id] else {
            guard let column = schema.column(id), let table = schema.table(id.table) else {
                throw ColumnStoreError.unknownColumn(id)
            }
            throw ColumnStoreError.storageMissing("\(table.name)[\(column.name)]")
        }
        let decoded = try VertiPaq.decodeColumn(entry.storage, abf: abf)
        let expected = try rowCount(id.table)
        guard decoded.count == expected else {
            throw PBIXColumnSourceError.misaligned(
                table: entry.storage.tableName, column: entry.storage.columnName,
                expected: expected, actual: decoded.count)
        }
        return try Self.convert(decoded.storage, type: entry.type)
    }

    /// Số distinct mà engine đã ghi trong metadata (`DistinctStates`). `nil` nếu cột không có lưu trữ.
    /// Dùng để đối chiếu, giống `pbix-dump verify`.
    public func cardinality(of id: ColumnID) -> Int? {
        entries[id]?.storage.cardinality
    }

    /// Cột có dữ liệu lưu trữ nào không. Cột tính toán chưa lưu thì không có.
    public func hasStorage(_ id: ColumnID) -> Bool {
        entries[id] != nil
    }

    // MARK: - Chuyển đổi

    /// Đổi kết quả giải mã sang `ColumnData`. Kiểu và số dòng lấy từ `storage` và `type`.
    static func convert(_ storage: DecodedColumn.Storage, type: DAXType) throws -> ColumnData {
        switch storage {
        case .empty(let count):
            return ColumnData(type: type, rowCount: count, payload: .allBlank)
        case .values(let values):
            return try convertValues(values, type: type)
        case .dictionary(let codes, let dictionary):
            return try convertDictionary(codes: codes, dictionary: dictionary, type: type)
        }
    }

    /// Cột mã hoá theo dictionary của VertiPaq.
    static func convertDictionary(codes: [Int32], dictionary: [CellValue], type: DAXType) throws -> ColumnData {
        let n = codes.count
        let distinct = dictionary.count
        if distinct == 0 {
            return ColumnData(type: type, rowCount: n, payload: .allBlank)
        }
        // Mã hợp lệ là -1 (null) hoặc trong [0, distinct). Mã khác là lỗi giải mã, không được lan thành giá trị sai.
        for code in codes where code < -1 || code >= Int32(distinct) {
            throw PBIXColumnSourceError.invalidCode(Int(code), dictionaryCount: distinct)
        }
        if prefersDense(type: type, distinct: distinct, rows: n) {
            return try denseFromDictionary(codes: codes, dictionary: dictionary, type: type)
        }
        let typed = try typedDictionary(dictionary, type: type)
        return ColumnData(type: type, rowCount: n, payload: .encoded(encodeCodes(codes, distinct: distinct), typed))
    }

    /// Cột giá trị trực tiếp của VertiPaq (hash index). NaN là BLANK.
    static func convertValues(_ values: [Double], type: DAXType) throws -> ColumnData {
        let n = values.count
        switch type {
        case .integer, .currency:
            var out = [Int64](repeating: 0, count: n)
            var blanks: [UInt32] = []
            for (row, v) in values.enumerated() {
                if v.isNaN { blanks.append(UInt32(row)); continue }
                out[row] = Int64(v.rounded())
            }
            return ColumnData(type: type, rowCount: n,
                              payload: .dense(.integers(out, blanks: blankSet(blanks, rowCount: n))))
        case .double:
            return ColumnData(type: type, rowCount: n, payload: .dense(.doubles(values)))
        case .dateTime:
            return ColumnData(type: type, rowCount: n, payload: .dense(.dates(values)))
        case .boolean:
            return ColumnBuilder.booleans(values.map { $0.isNaN ? nil : $0 != 0 })
        case .string:
            throw PBIXColumnSourceError.unexpectedValue(type: type, value: "dữ liệu số")
        }
    }

    /// Cột số có quá nhiều giá trị, hoặc mã hoá không tiết kiệm hơn dạng dense, thì dùng dense.
    static func prefersDense(type: DAXType, distinct: Int, rows: Int) -> Bool {
        switch type {
        case .string, .boolean: return false
        case .integer, .double, .currency, .dateTime: break
        }
        if distinct > Int(UInt16.max) { return true }
        let codeBytes = distinct <= Int(UInt8.max) ? 1 : 2
        // Mã hoá tốn rows × codeBytes + distinct × 8 byte; dense tốn rows × 8 byte.
        return rows * codeBytes + distinct * 8 >= rows * 8
    }

    /// Chọn độ rộng mã theo số mục. Mã dictionary là k + 1, nên mục cuối có mã `distinct`.
    static func encodeCodes(_ codes: [Int32], distinct: Int) -> Codes {
        if distinct <= Int(UInt8.max) {
            return .u8(codes.map { UInt8(Int($0) + 1) })
        }
        if distinct <= Int(UInt16.max) {
            return .u16(codes.map { UInt16(Int($0) + 1) })
        }
        return .u32(codes.map { UInt32(Int($0) + 1) })
    }

    static func typedDictionary(_ dictionary: [CellValue], type: DAXType) throws -> TypedDictionary {
        switch type {
        case .integer:
            return .integers(try dictionary.map(integerValue))
        case .currency:
            return .currency(try dictionary.map(currencyValue))
        case .double:
            return .doubles(try dictionary.map(doubleValue))
        case .dateTime:
            return .dates(try dictionary.map(dateValue))
        case .boolean:
            return .booleans(try dictionary.map(boolValue))
        case .string:
            return .strings(StringPool(strings: try dictionary.map(stringValue)))
        }
    }

    /// Đổi cột mã hoá sang dạng dense. Dòng BLANK thành NaN (số thực, ngày) hoặc được ghi vào `blanks` (số nguyên).
    static func denseFromDictionary(codes: [Int32], dictionary: [CellValue], type: DAXType) throws -> ColumnData {
        let n = codes.count
        switch type {
        case .integer, .currency:
            let conv: (CellValue) throws -> Int64 = { v in
                type == .integer ? try integerValue(v) : try currencyValue(v)
            }
            var table = [Int64](repeating: 0, count: dictionary.count + 1)
            for (k, v) in dictionary.enumerated() { table[k + 1] = try conv(v) }
            var out = [Int64](repeating: 0, count: n)
            var blanks: [UInt32] = []
            for row in 0..<n {
                let code = Int(codes[row])
                if code < 0 { blanks.append(UInt32(row)) } else { out[row] = table[code + 1] }
            }
            return ColumnData(type: type, rowCount: n,
                              payload: .dense(.integers(out, blanks: blankSet(blanks, rowCount: n))))
        case .double, .dateTime:
            let conv: (CellValue) throws -> Double = { v in
                type == .double ? try doubleValue(v) : try dateValue(v)
            }
            var table = [Double](repeating: .nan, count: dictionary.count + 1)
            for (k, v) in dictionary.enumerated() { table[k + 1] = try conv(v) }
            var out = [Double](repeating: .nan, count: n)
            for row in 0..<n {
                out[row] = table[Int(codes[row]) + 1]
            }
            let payload: DenseValues = type == .double ? .doubles(out) : .dates(out)
            return ColumnData(type: type, rowCount: n, payload: .dense(payload))
        case .boolean, .string:
            throw PBIXColumnSourceError.unexpectedValue(type: type, value: "cột này không có dạng dense")
        }
    }

    static func blankSet(_ rows: [UInt32], rowCount: Int) -> RowSet? {
        rows.isEmpty ? nil : RowSet(universe: rowCount + 1, sortedRows: rows)
    }

    // MARK: - Giá trị của từng kiểu (ném lỗi nếu kiểu không khớp)

    static func integerValue(_ v: CellValue) throws -> Int64 {
        guard case .int(let x) = v else { throw mismatch(.integer, v) }
        return x
    }

    /// Dictionary của cột decimal lưu `CellValue.decimal(v / 10⁴)`, nên nhân lại rồi làm tròn để khôi phục số nguyên.
    static func currencyValue(_ v: CellValue) throws -> Int64 {
        guard case .decimal(let x) = v else { throw mismatch(.currency, v) }
        return Int64((x * 10_000).rounded())
    }

    static func doubleValue(_ v: CellValue) throws -> Double {
        switch v {
        case .double(let x): return x
        case .int(let x): return Double(x)
        default: throw mismatch(.double, v)
        }
    }

    static func dateValue(_ v: CellValue) throws -> Double {
        guard case .dateTime(let x) = v else { throw mismatch(.dateTime, v) }
        return x
    }

    static func boolValue(_ v: CellValue) throws -> Bool {
        guard case .bool(let x) = v else { throw mismatch(.boolean, v) }
        return x
    }

    static func stringValue(_ v: CellValue) throws -> String {
        guard case .string(let x) = v else { throw mismatch(.string, v) }
        return x
    }

    private static func mismatch(_ type: DAXType, _ v: CellValue) -> PBIXColumnSourceError {
        .unexpectedValue(type: type, value: v.description)
    }
}

/// Lỗi khi đổi dữ liệu VertiPaq sang `ColumnData`.
public enum PBIXColumnSourceError: Error, Sendable, CustomStringConvertible {
    case misaligned(table: String, column: String, expected: Int, actual: Int)
    case invalidCode(Int, dictionaryCount: Int)
    case unexpectedValue(type: DAXType, value: String)

    public var description: String {
        switch self {
        case .misaligned(let table, let column, let expected, let actual):
            "cột \(table)[\(column)] có \(actual) dòng, bảng có \(expected) dòng"
        case .invalidCode(let code, let count):
            "mã \(code) vượt quá dictionary \(count) mục"
        case .unexpectedValue(let type, let value):
            "giá trị \(value) không khớp kiểu \(type)"
        }
    }
}
