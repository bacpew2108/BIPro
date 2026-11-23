// Phase F, T089 (US7): nguồn Parquet tự viết (tập con): footer Thrift Compact, trang dữ liệu v1/v2 và trang từ điển, mã hoá PLAIN,
// PLAIN_DICTIONARY/RLE_DICTIONARY, RLE (boolean), nén UNCOMPRESSED/SNAPPY/GZIP. Cột phẳng REQUIRED/OPTIONAL; cột lồng struct/LIST tới độ
// sâu 3 (T042, `ParquetNested.swift`); MAP, lặp kiểu cũ, codec hay mã hoá khác báo "Chưa hỗ trợ" kèm tên.
//
// Ánh xạ kiểu theo Desktop 2.159 (VM-F7a, `docs/phase-f-evidence/vm-f7/QUAN-SAT.md`): INT32/INT64 → số nguyên; FLOAT/DOUBLE → số thực;
// DECIMAL (mọi kiểu vật lý) → số thực (Desktop không dùng Fixed decimal); DATE → ngày; TIMESTAMP (ms/µs/ns) và INT96 → ngày giờ;
// BOOLEAN → logic; chuỗi UTF-8 → text. [SUY ĐOÁN] TIME → phần giờ của ngày giờ; BYTE_ARRAY không chú thích đọc như UTF-8.

import PBIXKit
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
    var columns: [SourceColumn]? { file.fields.map { field in
        switch field {
        case .flat(let i): SourceColumn(name: file.leaves[i].name, type: file.leaves[i].type)
        case .nested(let node): SourceColumn(name: node.element.name, type: .string)
        }
    } }
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

    /// Nội dung tệp, ánh xạ từ đĩa khi được (T109, SC-005): không chép cả tệp vào bộ nhớ, mỗi lần chỉ chép footer hoặc một column chunk.
    /// Cột trên cùng theo thứ tự lược đồ: phẳng (chỉ số trong `leaves`) hay lồng.
    enum Field: @unchecked Sendable {
        case flat(Int)
        case nested(ParquetNode)
    }

    let data: Data
    let metadata: ParquetFileMetaData
    let leaves: [Leaf]
    let fields: [Field]
    static let maxNesting = 3

    public init(url: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch {
            throw SourceError.unreadable(lt("Không thể đọc file: \(url.lastPathComponent)", "Couldn't read the file: \(url.lastPathComponent)"))
        }
        try self.init(data: data, name: url.lastPathComponent)
    }

    init(bytes: [UInt8], name: String) throws {
        try self.init(data: Data(bytes), name: name)
    }

    init(data: Data, name: String) throws {
        let magic: [UInt8] = Array("PAR1".utf8)
        let n = data.count
        guard n >= 12, Self.copy(data, 0, 4) == magic, Self.copy(data, n - 4, n) == magic else {
            throw SourceError.unreadable(lt("\(name) không phải tệp Parquet", "\(name) isn't a Parquet file"))
        }
        let tail = Self.copy(data, n - 8, n - 4)
        let length = Int(tail[0]) | Int(tail[1]) << 8 | Int(tail[2]) << 16 | Int(tail[3]) << 24
        guard length > 0, length <= n - 12 else { throw ThriftCompactReader.failure(lt("độ dài footer", "footer length")) }
        var reader = ThriftCompactReader(Self.copy(data, n - 8 - length, n - 8))
        let metadata = try ParquetFileMetaData(reader.structure())
        guard let root = metadata.schema.first else { throw ThriftCompactReader.failure(lt("thiếu lược đồ", "missing schema")) }
        var leaves: [Leaf] = []
        var fields: [Field] = []
        var index = 1
        let elements = metadata.schema
        while index < elements.count {
            let node = ParquetNode.build(elements, &index, parentDefinition: 0, parentRepetition: 0, parentPath: [])
            if node.isLeaf && node.element.repetition != 2 {
                fields.append(.flat(leaves.count))
                leaves.append(Leaf(name: node.element.name, element: node.element, maxDefinition: node.definition, type: try Self.type(of: node.element)))
                continue
            }
            if let reason = node.unsupportedReason() { throw SourceError.unsupported(reason) }
            guard node.nesting <= Self.maxNesting else {
                throw SourceError.unsupported(lt("Parquet cột \(node.element.name) lồng sâu \(node.nesting) tầng (tối đa \(Self.maxNesting))", "Parquet column \(node.element.name) is nested \(node.nesting) levels deep (max \(Self.maxNesting))"))
            }
            for leaf in node.leaves { _ = try Self.type(of: leaf.element) }
            fields.append(.nested(node))
        }
        guard fields.count == root.children else { throw SourceError.unsupported(lt("Parquet có lược đồ lạ", "Parquet has an unexpected schema")) }
        self.data = data
        self.metadata = metadata
        self.leaves = leaves
        self.fields = fields
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
            throw SourceError.unsupported(lt("Parquet cột \(e.name) kiểu \(e.physical == 7 ? "FIXED_LEN_BYTE_ARRAY" : "vật lý \(e.physical ?? -1)")", "Parquet column \(e.name) of type \(e.physical == 7 ? "FIXED_LEN_BYTE_ARRAY" : "physical \(e.physical ?? -1)")"))
        }
    }

    /// Đọc `rowLimit` dòng đầu (hoặc hết). Huỷ Task giữa các row group ném `SourceError.cancelled`.
    public func read(rowLimit: Int?, progress: SourceProgress?) throws -> TableData {
        let wanted = min(rowLimit ?? metadata.rowCount, metadata.rowCount)
        var sinks = leaves.map { ColumnSink(type: $0.type, capacity: wanted) }
        var nestedValues: [Int: [ParquetValue]] = [:]
        var rows = 0
        for (g, group) in metadata.rowGroups.enumerated() where rows < wanted {
            if Task.isCancelled { throw SourceError.cancelled }
            let take = min(group.rowCount, wanted - rows)
            for (f, field) in fields.enumerated() {
                switch field {
                case .flat(let c):
                    let leaf = leaves[c]
                    guard let chunk = group.columns.first(where: { $0.path == [leaf.name] }) else { throw ThriftCompactReader.failure(lt("thiếu cột \(leaf.name)", "missing column \(leaf.name)")) }
                    try readChunk(chunk, leaf: leaf, rows: take, into: &sinks[c])
                case .nested(let node):
                    var entries: [[String]: ParquetLeafEntries] = [:]
                    for leafNode in node.leaves {
                        guard let chunk = group.columns.first(where: { $0.path == leafNode.path }) else {
                            throw ThriftCompactReader.failure(lt("thiếu cột \(leafNode.path.joined(separator: "."))", "missing column \(leafNode.path.joined(separator: "."))"))
                        }
                        entries[leafNode.path] = try readEntries(chunk, node: leafNode)
                    }
                    nestedValues[f, default: []] += ParquetAssembler.assemble(node, entries: entries, rows: take)
                }
            }
            rows += take
            progress?(Double(g + 1) / Double(max(metadata.rowGroups.count, 1)))
        }
        var columns: [TableColumn] = []
        var structured: [Int: [Int: any Sendable]] = [:]
        for (f, field) in fields.enumerated() {
            switch field {
            case .flat(let c): columns.append(TableColumn(name: leaves[c].name, data: sinks[c].columnData()))
            case .nested(let node):
                let values = nestedValues[f] ?? []
                var cells: [Int: any Sendable] = [:]
                for (row, value) in values.enumerated() where value != .null { cells[row] = value }
                if !cells.isEmpty { structured[f] = cells }
                columns.append(TableColumn(name: node.element.name, data: ColumnBuilder.strings(values.map(\.placeholder)),
                                           sourceType: node.listElement != nil ? .list : .record))
            }
        }
        do {
            return try TableData(columns: columns, structured: structured)
        } catch TableDataError.duplicateColumn(let name) {
            throw SourceError.unreadable(lt("Parquet có hai cột cùng tên \(name)", "Parquet has two columns named \(name)"))
        }
    }

    /// Mọi mục (mức lặp, mức định nghĩa, giá trị có mặt) của một lá thuộc cột lồng trong một column chunk.
    private func readEntries(_ chunk: ParquetColumnChunk, node: ParquetNode) throws -> ParquetLeafEntries {
        let leaf = Leaf(name: node.path.joined(separator: "."), element: node.element, maxDefinition: node.definition, type: try Self.type(of: node.element))
        var out = ParquetLeafEntries()
        var position = chunk.dataPageOffset
        if let dictionary = chunk.dictionaryPageOffset, dictionary > 0, dictionary < position { position = dictionary }
        var dictionary: ColumnValues?
        let repWidth = Self.levelWidth(node.repetition), defWidth = Self.levelWidth(node.definition)
        while out.definition.count < chunk.valueCount {
            guard position < data.count else { throw ParquetBytes.truncated }
            var reader = ThriftCompactReader(Self.copy(data, position, min(data.count, position + 64 * 1024)), at: 0)
            let header = try ParquetPageHeader(reader.structure())
            let body = position + reader.index
            guard body + header.compressedSize <= data.count else { throw ParquetBytes.truncated }
            position = body + header.compressedSize
            let raw = Self.copy(data, body, position)[...]
            switch header.type {
            case 2:
                var cursor = ParquetBytes(try ParquetCodec.decompress(raw, codec: chunk.codec, size: header.uncompressedSize))
                dictionary = try plain(&cursor, count: header.valueCount, leaf: leaf)
            case 0, 3:
                let count = header.valueCount
                var reps = [Int32](repeating: 0, count: count), defs = [Int32](repeating: Int32(node.definition), count: count)
                var cursor: ParquetBytes
                if header.type == 0 {
                    let page = try ParquetCodec.decompress(raw, codec: chunk.codec, size: header.uncompressedSize)
                    cursor = ParquetBytes(page)
                    for (max, width, isRep) in [(node.repetition, repWidth, true), (node.definition, defWidth, false)] where max > 0 {
                        let length = try cursor.u32()
                        guard cursor.index + length <= cursor.end else { throw ParquetBytes.truncated }
                        var levels = ParquetBytes(page, from: cursor.index, to: cursor.index + length)
                        let decoded = try levels.hybrid(bitWidth: width, count: count)
                        if isRep { reps = decoded } else { defs = decoded }
                        cursor.index += length
                    }
                } else {
                    let levelBytes = header.repetitionLength + header.definitionLength
                    guard levelBytes <= raw.count else { throw ParquetBytes.truncated }
                    if node.repetition > 0 {
                        var levels = ParquetBytes(Array(raw[raw.startIndex..<(raw.startIndex + header.repetitionLength)]))
                        reps = try levels.hybrid(bitWidth: repWidth, count: count)
                    }
                    if node.definition > 0 {
                        var levels = ParquetBytes(Array(raw[(raw.startIndex + header.repetitionLength)..<(raw.startIndex + levelBytes)]))
                        defs = try levels.hybrid(bitWidth: defWidth, count: count)
                    }
                    let values = raw[(raw.startIndex + levelBytes)...]
                    cursor = ParquetBytes(header.isCompressed
                        ? try ParquetCodec.decompress(values, codec: chunk.codec, size: header.uncompressedSize - levelBytes) : Array(values))
                }
                let present = defs.reduce(0) { $0 + (Int($1) == node.definition ? 1 : 0) }
                let values: ColumnValues
                switch header.encoding {
                case 0: values = try plain(&cursor, count: present, leaf: leaf)
                case 2, 8:
                    guard let dictionary else { throw ThriftCompactReader.failure(lt("thiếu trang từ điển của cột \(leaf.name)", "missing dictionary page for column \(leaf.name)")) }
                    if present == 0 { values = dictionary.gather([]); break }
                    let width = Int(cursor.bytes[cursor.index]); cursor.index += 1
                    let indices = try cursor.hybrid(bitWidth: width, count: present)
                    guard indices.allSatisfy({ $0 >= 0 && Int($0) < dictionary.count }) else { throw ThriftCompactReader.failure(lt("chỉ số từ điển", "dictionary index")) }
                    values = dictionary.gather(indices)
                default:
                    throw SourceError.unsupported(lt("Parquet mã hoá \(Self.encodingName(header.encoding)) (cột \(leaf.name))", "Parquet encoding \(Self.encodingName(header.encoding)) (column \(leaf.name))"))
                }
                out.repetition += reps
                out.definition += defs
                out.values += values.stored(as: leaf.type)
            default:
                continue
            }
        }
        return out
    }

    static func levelWidth(_ max: Int) -> Int { max == 0 ? 0 : Int.bitWidth - max.leadingZeroBitCount }

    /// Byte `from..<to` của `data` (đã chặn trong tệp), chép ra mảng.
    static func copy(_ data: Data, _ from: Int, _ to: Int) -> [UInt8] {
        let lower = data.startIndex + max(0, min(from, data.count)), upper = data.startIndex + max(0, min(to, data.count))
        return lower < upper ? [UInt8](data[lower..<upper]) : []
    }

    private func readChunk(_ chunk: ParquetColumnChunk, leaf: Leaf, rows: Int, into sink: inout ColumnSink) throws {
        var position = chunk.dataPageOffset
        if let dictionary = chunk.dictionaryPageOffset, dictionary > 0, dictionary < position { position = dictionary }
        // Chỉ chép column chunk (`total_compressed_size` byte từ trang đầu); vị trí trong `bytes` tính từ `base`. Vài bộ ghi cũ ghi
        // `total_compressed_size` thiếu: trang vượt khung thì mở khung tới cuối phần dữ liệu (trước footer).
        let base = position
        var bytes = Self.copy(data, base, base + max(chunk.totalCompressedSize, 0))
        func covers(_ end: Int) -> Bool {
            if end <= base + bytes.count { return true }
            guard bytes.count < data.count - base else { return false }
            bytes = Self.copy(data, base, data.count)
            return end <= base + bytes.count
        }
        var dictionary: ColumnValues?
        var read = 0
        let start = sink.count
        while read < rows {
            guard position < data.count, covers(position + 1) else { throw ParquetBytes.truncated }
            var reader = ThriftCompactReader(bytes, at: position - base)
            let header: ParquetPageHeader
            do { header = try ParquetPageHeader(reader.structure()) } catch {
                // Tiêu đề trang bị khung cắt ngang: mở khung rồi đọc lại.
                guard bytes.count < data.count - base, covers(data.count) else { throw error }
                reader = ThriftCompactReader(bytes, at: position - base)
                header = try ParquetPageHeader(reader.structure())
            }
            let body = base + reader.index
            guard body + header.compressedSize <= data.count, covers(body + header.compressedSize) else { throw ParquetBytes.truncated }
            position = body + header.compressedSize
            let raw = bytes[(body - base)..<(position - base)]
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
                    guard let dictionary else { throw ThriftCompactReader.failure(lt("thiếu trang từ điển của cột \(leaf.name)", "missing dictionary page for column \(leaf.name)")) }
                    guard cursor.index < cursor.end else {
                        guard present == 0 else { throw ParquetBytes.truncated }
                        values = dictionary.gather([]); break
                    }
                    let width = Int(cursor.bytes[cursor.index]); cursor.index += 1
                    let indices = try cursor.hybrid(bitWidth: width, count: present)
                    guard indices.allSatisfy({ $0 >= 0 && Int($0) < dictionary.count }) else { throw ThriftCompactReader.failure(lt("chỉ số từ điển", "dictionary index")) }
                    values = dictionary.gather(indices)
                case 3 where leaf.element.physical == 0:
                    _ = try cursor.u32()   // boolean RLE luôn có 4 byte độ dài (cả trang v2; chỉ mức lặp/định nghĩa v2 mới bỏ)
                    values = .bool(try cursor.hybrid(bitWidth: 1, count: present).map { $0 == 1 })
                default:
                    throw SourceError.unsupported(lt("Parquet mã hoá \(Self.encodingName(header.encoding)) (cột \(leaf.name))", "Parquet encoding \(Self.encodingName(header.encoding)) (column \(leaf.name))"))
                }
                let keep = min(count, rows - read)
                sink.append(values, definitions: definitions, rows: keep)
                read += keep
            default:
                continue   // trang chỉ mục: bỏ qua
            }
        }
        guard sink.count - start == rows else { throw ThriftCompactReader.failure(lt("số dòng cột \(leaf.name)", "row count of column \(leaf.name)")) }
    }

    static func encodingName(_ e: Int) -> String {
        [0: "PLAIN", 2: "PLAIN_DICTIONARY", 3: "RLE", 4: "BIT_PACKED", 5: "DELTA_BINARY_PACKED", 6: "DELTA_LENGTH_BYTE_ARRAY",
         7: "DELTA_BYTE_ARRAY", 8: "RLE_DICTIONARY", 9: "BYTE_STREAM_SPLIT"][e] ?? lt("mã \(e)", "code \(e)")
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
            guard e.isDecimal else { throw SourceError.unsupported(lt("Parquet cột \(e.name) kiểu FIXED_LEN_BYTE_ARRAY", "Parquet column \(e.name) of type FIXED_LEN_BYTE_ARRAY")) }
            return .double((0..<count).map { Self.bigEndianDecimal(b[(start + n * $0)..<(start + n * ($0 + 1))], scale: e.scale) })
        default:
            throw SourceError.unsupported(lt("Parquet cột \(e.name) kiểu vật lý \(e.physical ?? -1)", "Parquet column \(e.name) with physical type \(e.physical ?? -1)"))
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

    /// Giá trị dạng `StoredValue` theo kiểu cột (số ngày của cột ngày giờ thành `.dateTime`).
    func stored(as type: DAXType) -> [StoredValue] {
        switch self {
        case .int(let v): v.map { .integer($0) }
        case .double(let v): v.map { type == .dateTime ? .dateTime($0) : .double($0) }
        case .bool(let v): v.map { .boolean($0) }
        case .string(let v): v.map { .string($0) }
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
