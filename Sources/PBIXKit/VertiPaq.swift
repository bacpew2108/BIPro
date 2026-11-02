import Foundation

// VertiPaq (xVelocity) column storage decoding.
//
// Format references: [MS-XLDM] §2.3 (column data), §2.7.4 (Huffman string
// stores), and the MIT-licensed pbixray reader by Igor Cotruta, whose layout
// this port follows.

/// One cell of a decoded column.
public enum CellValue: Sendable, Hashable, CustomStringConvertible {
    case null
    case int(Int64)
    case double(Double)
    case decimal(Double)
    case string(String)
    case bool(Bool)
    /// Days since 1899-12-30 (OLE automation date).
    case dateTime(Double)

    public var description: String {
        switch self {
        case .null: return ""
        case .int(let v): return String(v)
        case .double(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
        case .decimal(let v): return String(format: "%.4f", v)
        case .string(let s): return s
        case .bool(let b): return b ? "True" : "False"
        case .dateTime(let days):
            let date = Date(timeIntervalSince1970: (days - 25_569) * 86_400)
            let f = ISO8601DateFormatter()
            f.formatOptions = days == days.rounded() ? [.withFullDate] : [.withFullDate, .withTime, .withColonSeparatorInTime]
            f.timeZone = TimeZone(identifier: "UTC")
            return f.string(from: date)
        }
    }
}

/// A decoded column. Dictionary-encoded columns keep their codes so the
/// query engine can group and filter without materialising every cell.
public struct DecodedColumn: Sendable {
    public enum Storage: Sendable {
        /// `codes[row]` indexes `dictionary`; -1 is null.
        case dictionary(codes: [Int32], dictionary: [CellValue])
        /// Value-encoded numbers; NaN is null.
        case values([Double])
        /// No stored data (e.g. an all-null column).
        case empty(count: Int)
    }

    public let name: String
    public let dataType: ModelMetadata.DataType
    public let storage: Storage

    public var count: Int {
        switch storage {
        case .dictionary(let codes, _): codes.count
        case .values(let v): v.count
        case .empty(let n): n
        }
    }

    public subscript(row: Int) -> CellValue {
        switch storage {
        case .dictionary(let codes, let dictionary):
            let code = codes[row]
            return code < 0 ? .null : dictionary[Int(code)]
        case .values(let values):
            let v = values[row]
            return v.isNaN ? .null : VertiPaq.typed(v, as: dataType)
        case .empty:
            return .null
        }
    }
}

public enum VertiPaq {
    public enum Error: Swift.Error, CustomStringConvertible {
        case badTag(String, file: String)
        case truncated(String)
        case huffman(String)
        case unknownColumn(String)
        case misaligned(table: String, lengths: [String: Int])

        public var description: String {
            switch self {
            case .badTag(let tag, let file): "unexpected \(tag) in \(file)"
            case .truncated(let file): "truncated \(file)"
            case .huffman(let m): "huffman: \(m)"
            case .unknownColumn(let c): "unknown column \(c)"
            case .misaligned(let t, let l): "columns of \(t) have different lengths: \(l)"
            }
        }
    }

    /// Data id reserved for NULL; the first real dictionary entry is id 3.
    static let nullDataID: Int64 = 2
    static let firstDataID: Int64 = 3

    /// Decodes every stored column of `table`, in storage order.
    public static func decodeTable(_ table: String, columns wanted: [String]? = nil,
                                   metadata: ModelMetadata, abf: ABFBackup) throws -> [DecodedColumn] {
        var selected = metadata.storage(table: table)
        if let wanted {
            for name in wanted where !selected.contains(where: { $0.columnName == name }) {
                throw Error.unknownColumn("\(table)[\(name)]")
            }
            selected = selected.filter { wanted.contains($0.columnName) }
        }
        let decoded = try selected.map { try decodeColumn($0, abf: abf) }
        let lengths = Dictionary(decoded.map { ($0.name, $0.count) }, uniquingKeysWith: { a, _ in a })
        if Set(lengths.values).count > 1 { throw Error.misaligned(table: table, lengths: lengths) }
        return decoded
    }

    public static func decodeColumn(_ column: ModelMetadata.ColumnStorage, abf: ABFBackup) throws -> DecodedColumn {
        // Gather every partition's segments in storage order.
        var segments: [(meta: SegmentMeta, data: IDFSegment?)] = []
        let hasData = column.dictionaryFile != nil || column.hashIndexFile != nil
        for idf in column.idfFiles {
            let metas = try parseIDFMeta(try abf.contents(named: idf + "meta"), file: idf + "meta")
            if !hasData {
                segments += metas.map { ($0, nil) }
                continue
            }
            let parts = try parseIDF(try abf.contents(named: idf), file: idf)
            for (i, meta) in metas.enumerated() {
                segments.append((meta, i < parts.count ? parts[i] : nil))
            }
        }

        if let dictionaryFile = column.dictionaryFile {
            let dictionary = try readDictionary(try abf.contents(named: dictionaryFile), file: dictionaryFile, dataType: column.dataType)
            var codes: [Int32] = []
            codes.reserveCapacity(segments.reduce(0) { $0 + $1.meta.records })
            for (meta, data) in segments {
                guard let data else { codes += Array(repeating: -1, count: meta.records); continue }
                for id in decodeSegment(data, meta: meta) {
                    let code = id - firstDataID
                    codes.append(code >= 0 && code < dictionary.count ? Int32(code) : -1)
                }
            }
            return DecodedColumn(name: column.columnName, dataType: column.dataType,
                                 storage: .dictionary(codes: codes, dictionary: dictionary))
        }

        if column.hashIndexFile != nil {
            var values: [Double] = []
            let base = Double(column.baseID)
            let magnitude = column.magnitude == 0 ? 1 : column.magnitude
            for (meta, data) in segments {
                guard let data else { values += Array(repeating: .nan, count: meta.records); continue }
                for id in decodeSegment(data, meta: meta) {
                    values.append(meta.hasNulls && id == nullDataID ? .nan : (Double(id) + base) / magnitude)
                }
            }
            return DecodedColumn(name: column.columnName, dataType: column.dataType, storage: .values(values))
        }

        return DecodedColumn(name: column.columnName, dataType: column.dataType,
                             storage: .empty(count: segments.reduce(0) { $0 + $1.meta.records }))
    }

    static func typed(_ number: Double, as type: ModelMetadata.DataType) -> CellValue {
        switch type {
        case .int64: .int(Int64(number))
        case .decimal: .decimal(number / 10_000)
        case .dateTime: .dateTime(number)
        case .boolean: .bool(number != 0)
        default: .double(number)
        }
    }

    // MARK: - .idfmeta

    struct SegmentMeta {
        var records: Int
        var minDataID: Int64
        var hasNulls: Bool
        var bitPackedCount: Int
        var bitWidth: Int
    }

    static func parseIDFMeta(_ data: Data, file: String) throws -> [SegmentMeta] {
        var r = ByteReader(data, file: file)
        try r.expectTag("<1:CP\0")
        let count = Int(try r.u64())
        var result: [SegmentMeta] = []
        for _ in 0..<count {
            try r.expectTag("<1:CS\0")
            let records = Int(try r.u64())
            _ = try r.u64() // base id
            let compressionClass = Int(try r.u32())
            let subCompressionClass = Int(try r.u32())
            if compressionClass == 0xABA5A { // hybrid RLE facet
                _ = try r.u64(); _ = try r.u64(); _ = try r.u64(); _ = try r.u8()
            }
            _ = try r.u32() // first run value
            try r.expectTag("<1:SS\0")
            _ = try r.u64() // distinct states
            let minDataID = Int64(try r.u32())
            _ = try r.u32(); _ = try r.u32() // max, original min
            _ = try r.u64() // rle sort order
            _ = try r.u64() // row count
            let hasNulls = try r.u8() != 0
            _ = try r.u64(); _ = try r.u64() // rle runs
            try r.expectTag("SS:1>\0")
            var bitPacked = 0
            if try r.u8() != 0 {
                try r.expectTag("<1:CS\0")
                bitPacked = Int(try r.u64())
                _ = try r.u64()
                if try r.u8() != 0 { throw Error.badTag("nested subsegment", file: file) }
                try r.expectTag("CS:1>\0")
            }
            try r.expectTag("CS:1>\0")
            result.append(SegmentMeta(
                records: records,
                // A segment holding nulls is based at the null id, otherwise at its own minimum.
                minDataID: hasNulls ? nullDataID : minDataID,
                hasNulls: hasNulls, bitPackedCount: bitPacked,
                bitWidth: bitWidth(compressionClass) ?? (compressionClass == 0xABA5A ? bitWidth(subCompressionClass) ?? 0 : 0)))
        }
        try r.expectTag("CP:1>\0")
        return result
    }

    private static func bitWidth(_ compressionClass: Int) -> Int? {
        switch compressionClass {
        case 703_031...703_040: compressionClass - 703_030
        case 703_042: 12
        case 703_046: 16
        case 703_051: 21
        case 703_062: 32
        default: nil
        }
    }

    // MARK: - .idf (RLE + bit-packed hybrid)

    struct IDFSegment {
        var runs: [(value: UInt32, repeats: UInt32)]
        var packed: [UInt64]
    }

    static func parseIDF(_ data: Data, file: String) throws -> [IDFSegment] {
        var r = ByteReader(data, file: file)
        var segments: [IDFSegment] = []
        while !r.atEnd {
            let runCount = Int(try r.u64())
            var runs: [(UInt32, UInt32)] = []
            runs.reserveCapacity(runCount)
            for _ in 0..<runCount { runs.append((try r.u32(), try r.u32())) }
            let wordCount = Int(try r.u64())
            var words: [UInt64] = []
            words.reserveCapacity(wordCount)
            for _ in 0..<wordCount { words.append(try r.u64()) }
            segments.append(IDFSegment(runs: runs.map { (value: $0.0, repeats: $0.1) }, packed: words))
        }
        return segments
    }

    static func decodeSegment(_ segment: IDFSegment, meta: SegmentMeta) -> [Int64] {
        let base = meta.minDataID
        var packedValues: [Int64] = []
        if meta.bitPackedCount > 0, meta.bitWidth > 0 {
            if segment.packed.count == 1, segment.packed[0] == 0 {
                packedValues = Array(repeating: base, count: meta.bitPackedCount)
            } else {
                let width = UInt64(meta.bitWidth)
                let perWord = 64 / meta.bitWidth
                let mask: UInt64 = width == 64 ? .max : (1 << width) - 1
                packedValues.reserveCapacity(segment.packed.count * perWord)
                for word in segment.packed {
                    for k in 0..<perWord {
                        packedValues.append(Int64((word >> (UInt64(k) * width)) & mask) + base)
                    }
                }
            }
        }

        var output: [Int64] = []
        output.reserveCapacity(meta.records)
        var packedOffset = 0
        for run in segment.runs {
            // Cap at the declared record count: trailing slots may hold stale data.
            let remaining = meta.records - output.count
            if remaining <= 0 { break }
            let count = min(Int(run.repeats), remaining)
            if count == 0 { continue }
            // A bit-packed run is marked by value == 0xFFFFFFFF - (packed values consumed so far).
            if UInt64(run.value) + UInt64(packedOffset) == 0xFFFF_FFFF {
                let end = min(packedOffset + count, packedValues.count)
                output += packedValues[packedOffset..<end]
                if end - packedOffset < count { output += Array(repeating: base, count: count - (end - packedOffset)) }
                packedOffset += count
            } else {
                output += repeatElement(Int64(run.value), count: count)
            }
        }
        return output
    }

    // MARK: - .dictionary

    static func readDictionary(_ data: Data, file: String, dataType: ModelMetadata.DataType) throws -> [CellValue] {
        var r = ByteReader(data, file: file)
        let kind = try r.i32()
        for _ in 0..<6 { _ = try r.i32() } // hash information
        switch kind {
        case 0, 1: // long, real
            let count = Int(try r.u64())
            let elementSize = Int(try r.u32())
            var values: [CellValue] = []
            values.reserveCapacity(count)
            for _ in 0..<count {
                let number: Double
                if elementSize == 4 {
                    number = Double(try r.i32())
                } else if kind == 1 {
                    number = Double(bitPattern: try r.u64())
                } else {
                    let raw = Int64(bitPattern: try r.u64())
                    if dataType == .int64 { values.append(.int(raw)); continue }
                    number = Double(raw)
                }
                values.append(typed(number, as: dataType))
            }
            return values
        case 2:
            return try readStringDictionary(&r)
        default:
            throw Error.badTag("dictionary type \(kind)", file: file)
        }
    }

    private struct CompressedPage {
        var bits: UInt32
        var isGeneral: Bool
        var charset: UInt8
        var lengths: [UInt8]
        var buffer: [UInt8]
    }

    private static func readStringDictionary(_ r: inout ByteReader) throws -> [CellValue] {
        _ = try r.u64() // string count
        _ = try r.u8()  // store compressed
        _ = try r.u64() // longest string
        let pageCount = Int(try r.u64())

        enum Page { case plain([String]), compressed(CompressedPage) }
        var pages: [Page] = []
        for _ in 0..<pageCount {
            _ = try r.u64(); _ = try r.u8(); _ = try r.u64(); _ = try r.u64() // mask, nulls, start, count
            let compressed = try r.u8() != 0
            try r.expectBytes([0xDD, 0xCC, 0xBB, 0xAA], what: "string store begin")
            if compressed {
                let totalBits = try r.u32()
                let charsetType = try r.u32()
                let length = Int(try r.u64())
                let charset: UInt8 = charsetType == 0xABA91 ? try r.u8() : 0
                _ = try r.u32() // decode bits
                let packed = try r.bytes(128)
                var lengths = [UInt8](repeating: 0, count: 256)
                for (i, b) in packed.enumerated() {
                    lengths[2 * i] = b & 0x0F
                    lengths[2 * i + 1] = b >> 4
                }
                _ = try r.u64() // buffer size
                pages.append(.compressed(CompressedPage(bits: totalBits, isGeneral: charsetType == 0xABA92,
                                                        charset: charset, lengths: lengths, buffer: try r.bytes(length))))
            } else {
                _ = try r.u64() // remaining
                let used = Int(try r.u64())
                let allocation = Int(try r.u64())
                let text = Data(try r.bytes(used * 2)).utf16LEString()
                _ = try r.bytes(allocation - used * 2)
                var strings = text.components(separatedBy: "\0")
                strings.removeLast()
                pages.append(.plain(strings))
            }
            try r.expectBytes([0xCD, 0xAB, 0xCD, 0xAB], what: "string store end")
        }

        let handleCount = Int(try r.u64())
        try r.expectBytes([8, 0, 0, 0], what: "record handle size")
        var offsetsByPage: [Int: [UInt32]] = [:]
        for _ in 0..<handleCount {
            let offset = try r.u32()
            let page = Int(try r.u32())
            offsetsByPage[page, default: []].append(offset)
        }

        var values: [CellValue] = []
        for (index, page) in pages.enumerated() {
            switch page {
            case .plain(let strings):
                values += strings.map { .string($0) }
            case .compressed(let page):
                guard let offsets = offsetsByPage[index] else { continue }
                values += try decodeHuffmanPage(page, offsets: offsets).map { .string($0) }
            }
        }
        return values
    }

    /// Canonical Huffman over byte symbols; the bitstream is stored with each
    /// byte pair swapped and is read MSB-first.
    private static func decodeHuffmanPage(_ page: CompressedPage, offsets: [UInt32]) throws -> [String] {
        var count = [Int](repeating: 0, count: 16)
        var maxLength = 0
        for l in page.lengths where l > 0 {
            count[Int(l)] += 1
            maxLength = max(maxLength, Int(l))
        }
        guard maxLength > 0 else { return Array(repeating: "", count: offsets.count) }

        var firstCode = [Int](repeating: 0, count: 17)
        var code = 0
        for l in 1...maxLength {
            code = (code + count[l - 1]) << 1
            firstCode[l] = code
        }
        var table = [UInt16](repeating: 0, count: 1 << maxLength)
        var next = firstCode
        for symbol in 0..<256 {
            let l = Int(page.lengths[symbol])
            if l == 0 { continue }
            let c = next[l]; next[l] += 1
            let pad = maxLength - l
            let entry = UInt16(symbol << 8 | l)
            for k in 0..<(1 << pad) { table[(c << pad) + k] = entry }
        }

        var stream = page.buffer
        var i = 0
        while i + 1 < stream.count { stream.swapAt(i, i + 1); i += 2 }
        stream += [UInt8](repeating: 0, count: 8)

        let mask = UInt64(1 << maxLength) - 1
        let shift = UInt64(64 - maxLength)
        var strings: [String] = []
        strings.reserveCapacity(offsets.count)
        for (n, start) in offsets.enumerated() {
            let end = n + 1 == offsets.count ? UInt64(page.bits) : UInt64(offsets[n + 1])
            var bit = UInt64(start)
            var bytes: [UInt8] = []
            while bit < end {
                let byte = Int(bit >> 3)
                guard byte < stream.count - 8 + 1 else { throw Error.huffman("bit offset past end of page") }
                var word: UInt64 = 0
                for k in 0..<8 { word = word << 8 | UInt64(stream[byte + k]) }
                let entry = table[Int((word >> (shift - (bit & 7))) & mask)]
                let length = UInt64(entry & 0xFF)
                if length == 0 { throw Error.huffman("corrupt stream") }
                let symbol = UInt8(entry >> 8)
                if page.isGeneral {
                    bytes.append(symbol)
                } else if page.charset == 0 {
                    bytes.append(symbol); bytes.append(0) // Latin-1 → UTF-16LE
                } else {
                    bytes.append(symbol); bytes.append(page.charset)
                }
                bit += length
            }
            if bytes.count % 2 == 1 { bytes.removeLast() }
            strings.append(String(data: Data(bytes), encoding: .utf16LittleEndian) ?? "")
        }
        return strings
    }
}

// MARK: - Byte reader

struct ByteReader {
    private let data: Data
    private let file: String
    private(set) var position: Int

    init(_ data: Data, file: String) {
        self.data = data
        self.file = file
        position = data.startIndex
    }

    var atEnd: Bool { position >= data.endIndex }

    private mutating func need(_ n: Int) throws {
        guard n >= 0, position + n <= data.endIndex else { throw VertiPaq.Error.truncated(file) }
    }

    mutating func u8() throws -> UInt8 {
        try need(1); defer { position += 1 }
        return data[position]
    }

    mutating func u32() throws -> UInt32 {
        try need(4); defer { position += 4 }
        return data.u32(at: position - data.startIndex)
    }

    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }

    mutating func u64() throws -> UInt64 {
        try need(8); defer { position += 8 }
        return data.u64(at: position - data.startIndex)
    }

    mutating func bytes(_ n: Int) throws -> [UInt8] {
        try need(n); defer { position += n }
        return [UInt8](data[position..<(position + n)])
    }

    mutating func expectBytes(_ expected: [UInt8], what: String) throws {
        guard try bytes(expected.count) == expected else { throw VertiPaq.Error.badTag(what, file: file) }
    }

    mutating func expectTag(_ tag: String) throws {
        try expectBytes(Array(tag.utf8), what: tag.replacingOccurrences(of: "\0", with: ""))
    }
}

extension VertiPaq {
    /// Row count of a column's table from its segment metadata, without decoding data.
    public static func rowCount(_ column: ModelMetadata.ColumnStorage, abf: ABFBackup) throws -> Int {
        try column.idfFiles.reduce(0) { total, idf in
            total + (try parseIDFMeta(try abf.contents(named: idf + "meta"), file: idf + "meta")).reduce(0) { $0 + $1.records }
        }
    }
}
