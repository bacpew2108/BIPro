// Phase F, T089 (US7): đọc siêu dữ liệu Parquet (footer `FileMetaData`, `PageHeader`) theo giao thức Thrift Compact, tự viết theo đặc tả
// parquet-format (`parquet.thrift`). Chỉ giữ các trường BI Pro dùng; trường khác bỏ qua theo kiểu (không cần biết nghĩa).

import PBIXKit
import Foundation

/// Giá trị Thrift đã giải mã (dạng cây, không cần lược đồ trước).
indirect enum ThriftValue {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case binary(ArraySlice<UInt8>)
    case list([ThriftValue])
    case structure([Int16: ThriftValue])
    case map

    var int: Int64? { if case .int(let v) = self { v } else { nil } }
    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    var list: [ThriftValue]? { if case .list(let v) = self { v } else { nil } }
    var fields: [Int16: ThriftValue]? { if case .structure(let v) = self { v } else { nil } }
    var string: String? { if case .binary(let b) = self { String(decoding: b, as: UTF8.self) } else { nil } }
}

struct ThriftCompactReader {
    let bytes: [UInt8]
    var index: Int

    init(_ bytes: [UInt8], at index: Int = 0) {
        self.bytes = bytes
        self.index = index
    }

    static func failure(_ what: String) -> SourceError { .unreadable(lt("Tệp Parquet hỏng: \(what)", "Corrupt Parquet file: \(what)")) }

    mutating func byte() throws -> UInt8 {
        guard index < bytes.count else { throw Self.failure(lt("siêu dữ liệu bị cắt", "truncated metadata")) }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let b = try byte()
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else { throw Self.failure(lt("varint quá dài", "varint too long")) }
        }
    }

    mutating func zigzag() throws -> Int64 {
        let v = try varint()
        return Int64(bitPattern: (v >> 1) ^ (0 &- (v & 1)))
    }

    /// Đọc một struct (đến STOP).
    mutating func structure(depth: Int = 0) throws -> [Int16: ThriftValue] {
        guard depth < 64 else { throw Self.failure(lt("lồng quá sâu", "nested too deeply")) }
        var fields: [Int16: ThriftValue] = [:]
        var lastID: Int16 = 0
        while true {
            let header = try byte()
            if header == 0 { return fields }
            let delta = Int16(header >> 4)
            let type = header & 0x0F
            let id: Int16 = delta == 0 ? Int16(truncatingIfNeeded: try zigzag()) : lastID + delta
            lastID = id
            fields[id] = try value(type: type, depth: depth)
        }
    }

    mutating func value(type: UInt8, depth: Int) throws -> ThriftValue {
        switch type {
        case 1: return .bool(true)
        case 2: return .bool(false)
        case 3: return .int(Int64(Int8(bitPattern: try byte())))
        case 4, 5, 6: return .int(try zigzag())
        case 7:
            guard index + 8 <= bytes.count else { throw Self.failure(lt("double bị cắt", "truncated double")) }
            var bits: UInt64 = 0
            for k in 0..<8 { bits |= UInt64(bytes[index + k]) << (8 * UInt64(k)) }
            index += 8
            return .double(Double(bitPattern: bits))
        case 8:
            let length = Int(try varint())
            guard length >= 0, index + length <= bytes.count else { throw Self.failure(lt("chuỗi bị cắt", "truncated string")) }
            defer { index += length }
            return .binary(bytes[index..<index + length])
        case 9, 10:
            let header = try byte()
            var count = Int(header >> 4)
            if count == 15 { count = Int(try varint()) }
            let element = header & 0x0F
            guard count <= bytes.count else { throw Self.failure(lt("danh sách quá dài", "list too long")) }
            var items: [ThriftValue] = []
            items.reserveCapacity(count)
            for _ in 0..<count {
                if element == 1 || element == 2 { items.append(.bool(try byte() == 1)) } else { items.append(try value(type: element, depth: depth + 1)) }
            }
            return .list(items)
        case 11:
            let count = Int(try varint())
            guard count > 0 else { return .map }
            let kinds = try byte()
            for _ in 0..<count {
                _ = try value(type: kinds >> 4, depth: depth + 1)
                _ = try value(type: kinds & 0x0F, depth: depth + 1)
            }
            return .map
        case 12: return .structure(try structure(depth: depth + 1))
        default: throw Self.failure(lt("kiểu Thrift lạ \(type)", "unexpected Thrift type \(type)"))
        }
    }
}

// MARK: - Siêu dữ liệu dùng tới

struct ParquetSchemaElement {
    var name: String
    var physical: Int?            // BOOLEAN 0, INT32 1, INT64 2, INT96 3, FLOAT 4, DOUBLE 5, BYTE_ARRAY 6, FIXED_LEN_BYTE_ARRAY 7
    var typeLength: Int
    var repetition: Int           // REQUIRED 0, OPTIONAL 1, REPEATED 2
    var children: Int
    var converted: Int?
    var scale: Int
    var precision: Int
    /// Logical type: id trường trong union `LogicalType` (1 STRING, 5 DECIMAL, 6 DATE, 7 TIME, 8 TIMESTAMP, 10 INTEGER, …).
    var logical: Int16?
    /// TIMESTAMP/TIME: đơn vị (1 MILLIS, 2 MICROS, 3 NANOS).
    var timeUnit: Int16?

    init(_ f: [Int16: ThriftValue]) {
        name = f[4]?.string ?? ""
        physical = f[1]?.int.map(Int.init)
        typeLength = Int(f[2]?.int ?? 0)
        repetition = Int(f[3]?.int ?? 0)
        children = Int(f[5]?.int ?? 0)
        converted = f[6]?.int.map(Int.init)
        scale = Int(f[7]?.int ?? 0)
        precision = Int(f[8]?.int ?? 0)
        if let logicalFields = f[10]?.fields, let (id, value) = logicalFields.first {
            logical = id
            if id == 5, let d = value.fields {
                scale = Int(d[1]?.int ?? Int64(scale))
                precision = Int(d[2]?.int ?? Int64(precision))
            }
            if id == 7 || id == 8, let t = value.fields, let unit = t[2]?.fields?.keys.first { timeUnit = unit }
        }
    }
}

struct ParquetColumnChunk {
    var path: [String]
    var physical: Int
    var codec: Int                // UNCOMPRESSED 0, SNAPPY 1, GZIP 2, LZO 3, BROTLI 4, LZ4 5, ZSTD 6, LZ4_RAW 7
    var valueCount: Int
    var dataPageOffset: Int
    var dictionaryPageOffset: Int?
    var totalCompressedSize: Int
}

struct ParquetRowGroup {
    var rowCount: Int
    var columns: [ParquetColumnChunk]
}

struct ParquetFileMetaData {
    var schema: [ParquetSchemaElement]
    var rowCount: Int
    var rowGroups: [ParquetRowGroup]

    init(_ f: [Int16: ThriftValue]) throws {
        schema = (f[2]?.list ?? []).compactMap { $0.fields.map(ParquetSchemaElement.init) }
        rowCount = Int(f[3]?.int ?? 0)
        rowGroups = try (f[4]?.list ?? []).map { group in
            guard let g = group.fields else { throw ThriftCompactReader.failure("row group") }
            let columns = try (g[1]?.list ?? []).map { chunk -> ParquetColumnChunk in
                guard let c = chunk.fields else { throw ThriftCompactReader.failure("column chunk") }
                if let file = c[1]?.string, !file.isEmpty { throw SourceError.unsupported(lt("Parquet có cột nằm ở tệp ngoài (\(file))", "Parquet has a column in an external file (\(file))")) }
                guard let m = c[3]?.fields else { throw ThriftCompactReader.failure(lt("thiếu ColumnMetaData", "missing ColumnMetaData")) }
                return ParquetColumnChunk(path: (m[3]?.list ?? []).compactMap(\.string), physical: Int(m[1]?.int ?? -1), codec: Int(m[4]?.int ?? 0),
                                          valueCount: Int(m[5]?.int ?? 0), dataPageOffset: Int(m[9]?.int ?? 0),
                                          dictionaryPageOffset: m[11]?.int.map(Int.init), totalCompressedSize: Int(m[7]?.int ?? 0))
            }
            return ParquetRowGroup(rowCount: Int(g[3]?.int ?? 0), columns: columns)
        }
    }
}

struct ParquetPageHeader {
    var type: Int                 // DATA_PAGE 0, INDEX_PAGE 1, DICTIONARY_PAGE 2, DATA_PAGE_V2 3
    var uncompressedSize: Int
    var compressedSize: Int
    var valueCount: Int
    var encoding: Int
    /// Trang v2: độ dài mức lặp/định nghĩa (không nén) và cờ nén phần giá trị.
    var repetitionLength = 0
    var definitionLength = 0
    var isCompressed = true

    init(_ f: [Int16: ThriftValue]) throws {
        type = Int(f[1]?.int ?? -1)
        uncompressedSize = Int(f[2]?.int ?? 0)
        compressedSize = Int(f[3]?.int ?? 0)
        guard uncompressedSize >= 0, compressedSize >= 0 else { throw ThriftCompactReader.failure(lt("cỡ trang âm", "negative page size")) }
        switch type {
        case 0:
            let h = f[5]?.fields ?? [:]
            valueCount = Int(h[1]?.int ?? 0); encoding = Int(h[2]?.int ?? 0)
        case 2:
            let h = f[7]?.fields ?? [:]
            valueCount = Int(h[1]?.int ?? 0); encoding = Int(h[2]?.int ?? 0)
        case 3:
            let h = f[8]?.fields ?? [:]
            valueCount = Int(h[1]?.int ?? 0); encoding = Int(h[4]?.int ?? 0)
            definitionLength = Int(h[5]?.int ?? 0); repetitionLength = Int(h[6]?.int ?? 0)
            isCompressed = h[7]?.bool ?? true
        default:
            valueCount = 0; encoding = 0
        }
    }
}
