// Phase F, T089 (US7): nguồn Parquet tự viết (tập con): footer Thrift Compact, trang dữ liệu v1/v2 và trang từ điển, mã hoá PLAIN,
// PLAIN_DICTIONARY/RLE_DICTIONARY, RLE (boolean), nén UNCOMPRESSED/SNAPPY/GZIP. Chỉ lược đồ phẳng (cột REQUIRED/OPTIONAL); cột lồng,
// lặp, codec hay mã hoá khác báo "Chưa hỗ trợ" kèm tên.
//
// Ánh xạ kiểu theo Desktop 2.159 (VM-F7a, `docs/phase-f-evidence/vm-f7/QUAN-SAT.md`): INT32/INT64 → số nguyên; FLOAT/DOUBLE → số thực;
// DECIMAL (mọi kiểu vật lý) → số thực (Desktop không dùng Fixed decimal); DATE → ngày; TIMESTAMP (ms/µs/ns) và INT96 → ngày giờ;
// BOOLEAN → logic; chuỗi UTF-8 → text. [SUY ĐOÁN] TIME → phần giờ của ngày giờ; BYTE_ARRAY không chú thích đọc như UTF-8.

import ColumnStore
import Foundation

public struct ParquetSource: DataSource {
    public let kind: SourceKind = .parquet
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func items() async throws -> [any SourceItem] {
        let file = try ParquetFile(url: url)
        return [ParquetItem(name: url.deletingPathExtension().lastPathComponent, file: file)]
    }
}

private struct ParquetItem: SourceItem {
    let name: String
    let kind: SourceItemKind = .file
    let file: ParquetFile
    var columns: [SourceColumn]? { file.leaves.map { SourceColumn(name: $0.name, type: $0.type) } }
    var rowCountHint: Int? { file.metadata.rowCount }

    func preview(limit: Int) async throws -> TableData { try file.read(rowLimit: limit, progress: nil) }

    func load(progress: SourceProgress?) async throws -> TableData {
        try await Task.detached(priority: .userInitiated) { [file] in try file.read(rowLimit: nil, progress: progress) }.value
    }
}

/// Tệp Parquet đã đọc footer. Đọc cột theo yêu cầu (`read`).
public struct ParquetFile: Sendable {
    struct Leaf: Sendable {
        let name: String
        let element: ParquetSchemaElement
        let maxDefinition: Int
        let type: DAXType
    }

    let bytes: [UInt8]
    let metadata: ParquetFileMetaData
    let leaves: [Leaf]

    public init(url: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch {
            throw SourceError.unreadable("Không thể đọc file: \(url.lastPathComponent)")
        }
        try self.init(bytes: [UInt8](data), name: url.lastPathComponent)
    }

    init(bytes: [UInt8], name: String) throws {
        let magic: [UInt8] = Array("PAR1".utf8)
        guard bytes.count >= 12, Array(bytes[0..<4]) == magic, Array(bytes[(bytes.count - 4)...]) == magic else {
            throw SourceError.unreadable("\(name) không phải tệp Parquet")
        }
        let n = bytes.count
        let length = Int(bytes[n - 8]) | Int(bytes[n - 7]) << 8 | Int(bytes[n - 6]) << 16 | Int(bytes[n - 5]) << 24
        guard length > 0, length <= n - 12 else { throw ThriftCompactReader.failure("độ dài footer") }
        var reader = ThriftCompactReader(bytes, at: n - 8 - length)
        let metadata = try ParquetFileMetaData(reader.structure())
        guard let root = metadata.schema.first else { throw ThriftCompactReader.failure("thiếu lược đồ") }
        var leaves: [Leaf] = []
        for element in metadata.schema.dropFirst() {
            if element.children > 0 || element.repetition == 2 {
                throw SourceError.unsupported("Parquet có cột lồng hoặc lặp (\(element.name))")
            }
            leaves.append(Leaf(name: element.name, element: element, maxDefinition: element.repetition == 1 ? 1 : 0, type: try Self.type(of: element)))
        }
        guard root.children == leaves.count else { throw SourceError.unsupported("Parquet có cột lồng") }
        self.bytes = bytes
        self.metadata = metadata
        self.leaves = leaves
    }

    static func type(of e: ParquetSchemaElement) throws -> DAXType {
        if e.isDecimal { return .double }
        switch e.physical {
        case 0: return .boolean
        case 1, 2:
            if e.logical == 6 || e.converted == 6 { return .dateTime }
            if e.logical == 8 || e.converted == 9 || e.converted == 10 { return .dateTime }
            if e.logical == 7 || e.converted == 7 || e.converted == 8 { return .dateTime }
            return .integer
        case 3: return .dateTime
        case 4, 5: return .double
        case 6: return .string
        default:
            throw SourceError.unsupported("Parquet cột \(e.name) kiểu \(e.physical == 7 ? "FIXED_LEN_BYTE_ARRAY" : "vật lý \(e.physical ?? -1)")")
        }
    }

    /// Đọc `rowLimit` dòng đầu (hoặc hết). Huỷ Task giữa các row group ném `SourceError.cancelled`.
    public func read(rowLimit: Int?, progress: SourceProgress?) throws -> TableData {
        let wanted = min(rowLimit ?? metadata.rowCount, metadata.rowCount)
        var sinks = leaves.map { ColumnSink(type: $0.type, capacity: wanted) }
        var rows = 0
        for (g, group) in metadata.rowGroups.enumerated() where rows < wanted {
            if Task.isCancelled { throw SourceError.cancelled }
            let take = min(group.rowCount, wanted - rows)
            for (c, leaf) in leaves.enumerated() {
                guard let chunk = group.columns.first(where: { $0.path == [leaf.name] }) ?? (group.columns.indices.contains(c) ? group.columns[c] : nil) else {
                    throw ThriftCompactReader.failure("thiếu cột \(leaf.name)")
                }
                try readChunk(chunk, leaf: leaf, rows: take, into: &sinks[c])
            }
            rows += take
            progress?(Double(g + 1) / Double(max(metadata.rowGroups.count, 1)))
        }
        do {
            return try TableData(columns: zip(leaves, sinks).map { TableColumn(name: $0.name, data: $1.columnData()) })
        } catch TableDataError.duplicateColumn(let name) {
            throw SourceError.unreadable("Parquet có hai cột cùng tên \(name)")
        }
    }

    private func readChunk(_ chunk: ParquetColumnChunk, leaf: Leaf, rows: Int, into sink: inout ColumnSink) throws {
        var position = chunk.dataPageOffset
        if let dictionary = chunk.dictionaryPageOffset, dictionary > 0, dictionary < position { position = dictionary }
        var dictionary: ColumnValues?
        var read = 0
        let start = sink.count
        while read < rows {
            guard position < bytes.count else { throw ParquetBytes.truncated }
            var reader = ThriftCompactReader(bytes, at: position)
            let header = try ParquetPageHeader(reader.structure())
            let body = reader.index
            guard body + header.compressedSize <= bytes.count else { throw ParquetBytes.truncated }
            position = body + header.compressedSize
            let raw = bytes[body..<position]
            switch header.type {
            case 2:
                let page = try ParquetCodec.decompress(raw, codec: chunk.codec, size: header.uncompressedSize)
                var cursor = ParquetBytes(page)
                dictionary = try plain(&cursor, count: header.valueCount, leaf: leaf)
            case 0, 3:
                let count = header.valueCount
                var definitions: [Int32]?
                var cursor: ParquetBytes
                if header.type == 0 {
                    let page = try ParquetCodec.decompress(raw, codec: chunk.codec, size: header.uncompressedSize)
                    cursor = ParquetBytes(page)
                    if leaf.maxDefinition > 0 {
                        let length = try cursor.u32()
                        guard cursor.index + length <= cursor.end else { throw ParquetBytes.truncated }
                        var levels = ParquetBytes(page, from: cursor.index, to: cursor.index + length)
                        definitions = try levels.hybrid(bitWidth: 1, count: count)
                        cursor.index += length
                    }
                } else {
                    let levelBytes = header.repetitionLength + header.definitionLength
                    guard levelBytes <= raw.count else { throw ParquetBytes.truncated }
                    let levelsEnd = raw.startIndex + levelBytes
                    if leaf.maxDefinition > 0 {
                        var levels = ParquetBytes(Array(raw[(raw.startIndex + header.repetitionLength)..<levelsEnd]))
                        definitions = try levels.hybrid(bitWidth: 1, count: count)
                    }
                    let values = raw[levelsEnd...]
                    let page = header.isCompressed
                        ? try ParquetCodec.decompress(values, codec: chunk.codec, size: header.uncompressedSize - levelBytes)
                        : Array(values)
                    cursor = ParquetBytes(page)
                }
                let present = definitions.map { $0.reduce(0) { $0 + ($1 == 1 ? 1 : 0) } } ?? count
                let values: ColumnValues
                switch header.encoding {
                case 0:
                    values = try plain(&cursor, count: present, leaf: leaf)
                case 2, 8:
                    guard let dictionary else { throw ThriftCompactReader.failure("thiếu trang từ điển của cột \(leaf.name)") }
                    guard cursor.index < cursor.end else {
                        guard present == 0 else { throw ParquetBytes.truncated }
                        values = dictionary.gather([]); break
                    }
                    let width = Int(cursor.bytes[cursor.index]); cursor.index += 1
                    let indices = try cursor.hybrid(bitWidth: width, count: present)
                    guard indices.allSatisfy({ $0 >= 0 && Int($0) < dictionary.count }) else { throw ThriftCompactReader.failure("chỉ số từ điển") }
                    values = dictionary.gather(indices)
                case 3 where leaf.element.physical == 0:
                    _ = try cursor.u32()   // boolean RLE luôn có 4 byte độ dài (cả trang v2; chỉ mức lặp/định nghĩa v2 mới bỏ)
                    values = .bool(try cursor.hybrid(bitWidth: 1, count: present).map { $0 == 1 })
                default:
                    throw SourceError.unsupported("Parquet mã hoá \(Self.encodingName(header.encoding)) (cột \(leaf.name))")
                }
                let keep = min(count, rows - read)
                sink.append(values, definitions: definitions, rows: keep)
                read += keep
            default:
                continue   // trang chỉ mục: bỏ qua
            }
        }
        guard sink.count - start == rows else { throw ThriftCompactReader.failure("số dòng cột \(leaf.name)") }
    }

    static func encodingName(_ e: Int) -> String {
        [0: "PLAIN", 2: "PLAIN_DICTIONARY", 3: "RLE", 4: "BIT_PACKED", 5: "DELTA_BINARY_PACKED", 6: "DELTA_LENGTH_BYTE_ARRAY",
         7: "DELTA_BYTE_ARRAY", 8: "RLE_DICTIONARY", 9: "BYTE_STREAM_SPLIT"][e] ?? "mã \(e)"
    }

    // MARK: Giá trị PLAIN

    private func plain(_ c: inout ParquetBytes, count: Int, leaf: Leaf) throws -> ColumnValues {
        let e = leaf.element
        let b = c.bytes
        func need(_ n: Int) throws { guard c.index + n <= c.end else { throw ParquetBytes.truncated } }
        func le(_ p: Int, _ n: Int) -> UInt64 { var v: UInt64 = 0; for k in 0..<n { v |= UInt64(b[p + k]) << (8 * UInt64(k)) }; return v }
        switch e.physical {
        case 0:
            try need((count + 7) / 8)
            let start = c.index
            c.index += (count + 7) / 8
            return .bool((0..<count).map { b[start + $0 / 8] >> UInt8($0 % 8) & 1 == 1 })
        case 1, 2:
            let width = e.physical == 1 ? 4 : 8
            try need(width * count)
            let start = c.index
            c.index += width * count
            let ints: [Int64] = (0..<count).map { i in
                let v = le(start + i * width, width)
                return width == 4 ? Int64(Int32(bitPattern: UInt32(v))) : Int64(bitPattern: v)
            }
            return convertInts(ints, e)
        case 3:
            try need(12 * count)
            let start = c.index
            c.index += 12 * count
            return .double((0..<count).map { i in
                let p = start + 12 * i
                let nanos = Double(Int64(bitPattern: le(p, 8)))
                let julian = Double(UInt32(le(p + 8, 4)))
                return julian - 2_440_588 + 25_569 + nanos / 86_400e9
            })
        case 4:
            try need(4 * count)
            let start = c.index
            c.index += 4 * count
            return .double((0..<count).map { Double(Float(bitPattern: UInt32(le(start + 4 * $0, 4)))) })
        case 5:
            try need(8 * count)
            let start = c.index
            c.index += 8 * count
            return .double((0..<count).map { Double(bitPattern: le(start + 8 * $0, 8)) })
        case 6:
            var slices: [ArraySlice<UInt8>] = []
            slices.reserveCapacity(count)
            for _ in 0..<count {
                let n = try c.u32()
                try need(n)
                slices.append(b[c.index..<c.index + n])
                c.index += n
            }
            if e.isDecimal { return .double(slices.map { Self.bigEndianDecimal($0, scale: e.scale) }) }
            return .string(slices.map { String(decoding: $0, as: UTF8.self) })
        case 7:
            let n = e.typeLength
            try need(n * count)
            let start = c.index
            c.index += n * count
            guard e.isDecimal else { throw SourceError.unsupported("Parquet cột \(e.name) kiểu FIXED_LEN_BYTE_ARRAY") }
            return .double((0..<count).map { Self.bigEndianDecimal(b[(start + n * $0)..<(start + n * ($0 + 1))], scale: e.scale) })
        default:
            throw SourceError.unsupported("Parquet cột \(e.name) kiểu vật lý \(e.physical ?? -1)")
        }
    }

    private func convertInts(_ ints: [Int64], _ e: ParquetSchemaElement) -> ColumnValues {
        if e.isDecimal {
            let divisor = pow(10, Double(e.scale))
            return .double(ints.map { Double($0) / divisor })
        }
        if e.logical == 6 || e.converted == 6 { return .double(ints.map { Double($0) + 25_569 }) }
        let isTimestamp = e.logical == 8 || e.converted == 9 || e.converted == 10
        let isTime = e.logical == 7 || e.converted == 7 || e.converted == 8
        if isTimestamp || isTime {
            let unit: Int16 = e.timeUnit ?? (e.converted == 10 || e.converted == 8 ? 2 : 1)
            let perDay: Double = unit == 1 ? 86_400_000 : (unit == 2 ? 86_400_000_000 : 86_400_000_000_000)
            // Ngày giờ: phần nguyên và phần lẻ tách riêng để không mất độ chính xác µs khi cộng mốc 1970.
            return .double(ints.map { v in
                let days = (Double(v) / perDay).rounded(.down)
                let rest = Double(v - Int64(days * perDay)) / perDay
                return (isTimestamp ? 25_569 + days : days) + rest
            })
        }
        return .int(ints)
    }

    /// Số nguyên bù hai big-endian (DECIMAL trên BYTE_ARRAY/FIXED_LEN_BYTE_ARRAY) chia 10^scale.
    static func bigEndianDecimal(_ bytes: ArraySlice<UInt8>, scale: Int) -> Double {
        guard let first = bytes.first else { return 0 }
        let negative = first & 0x80 != 0
        if bytes.count <= 8 {
            var v: UInt64 = negative ? ~0 : 0
            for byte in bytes { v = v << 8 | UInt64(byte) }
            return Double(Int64(bitPattern: v)) / pow(10, Double(scale))
        }
        var magnitude = 0.0
        for byte in bytes { magnitude = magnitude * 256 + Double(negative ? ~byte : byte) }
        let value = negative ? -(magnitude + 1) : magnitude
        return value / pow(10, Double(scale))
    }
}

extension ParquetSchemaElement {
    var isDecimal: Bool { logical == 5 || converted == 5 }
}

/// Giá trị không null của một trang (hoặc từ điển), đã đổi sang kiểu BI Pro.
enum ColumnValues {
    case int([Int64])
    case double([Double])
    case bool([Bool])
    case string([String])

    var count: Int {
        switch self {
        case .int(let v): v.count
        case .double(let v): v.count
        case .bool(let v): v.count
        case .string(let v): v.count
        }
    }

    func gather(_ indices: [Int32]) -> ColumnValues {
        switch self {
        case .int(let v): .int(indices.map { v[Int($0)] })
        case .double(let v): .double(indices.map { v[Int($0)] })
        case .bool(let v): .bool(indices.map { v[Int($0)] })
        case .string(let v): .string(indices.map { v[Int($0)] })
        }
    }
}

/// Cột đang dựng: giá trị theo dòng (null theo mức định nghĩa).
struct ColumnSink {
    let type: DAXType
    private var ints: [Int64?] = []
    private var doubles: [Double?] = []
    private var bools: [Bool?] = []
    private var strings: [String?] = []
    private(set) var count = 0

    init(type: DAXType, capacity: Int) {
        self.type = type
        switch type {
        case .integer: ints.reserveCapacity(capacity)
        case .double, .dateTime, .currency: doubles.reserveCapacity(capacity)
        case .boolean: bools.reserveCapacity(capacity)
        case .string: strings.reserveCapacity(capacity)
        }
    }

    /// Thêm `rows` dòng đầu của trang: `definitions[i] == 1` là có giá trị (lấy lần lượt từ `values`), còn lại null.
    mutating func append(_ values: ColumnValues, definitions: [Int32]?, rows: Int) {
        func spread<T>(_ v: [T], into out: inout [T?]) {
            guard let definitions else { out.append(contentsOf: v.prefix(rows).map { Optional($0) }); return }
            var next = 0
            for i in 0..<rows {
                if definitions[i] == 1 { out.append(v[next]); next += 1 } else { out.append(nil) }
            }
        }
        switch values {
        case .int(let v): spread(v, into: &ints)
        case .double(let v): spread(v, into: &doubles)
        case .bool(let v): spread(v, into: &bools)
        case .string(let v): spread(v, into: &strings)
        }
        count += rows
    }

    func columnData() -> ColumnData {
        switch type {
        case .integer: ColumnBuilder.integers(ints)
        case .double, .currency: ColumnBuilder.doubles(doubles)
        case .dateTime: ColumnBuilder.dateTimes(doubles)
        case .boolean: ColumnBuilder.booleans(bools)
        case .string: ColumnBuilder.strings(strings)
        }
    }
}
