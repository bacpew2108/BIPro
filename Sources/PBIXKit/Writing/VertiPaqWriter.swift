import Foundation

/// Writes VertiPaq column files (dictionary, IDF, IDFMETA) for a new table (T3, WP5).
///
/// Layout follows `VertiPaq.swift` (the decoder is the reference for the binary format) and the
/// files of a real `Marketing` table in `tuan6.2.pbix` (inspected byte by byte):
/// - `.dictionary`: `i32 kind` (0 long, 1 real, 2 string), 6 × `i32` hash info, then the values.
///   Strings use one plain (uncompressed) page per store, UTF-16LE, every string NUL-terminated.
/// - `.idf`: one segment, `u64 runCount`, `(u32 value, u32 repeats)` per run, `u64 wordCount`, words.
///   All rows are one bit-packed run whose marker is `0xFFFFFFFF`.
/// - `.idfmeta`: `<1:CP` with one `<1:CS` segment (hybrid RLE facet, `0xABA5A`, sub class
///   `703030 + bit width`), `<1:SS` statistics, a bit-packed sub-block, then the `<1:SDOs` trailer
///   that describes the IDF layout. The decoder stops at `CP:1>`, so the trailer is written only to
///   match Power BI's files.
///
/// Data IDs: a value's data ID is its dictionary index + 3, NULL is 2. Value-encoded columns
/// (RowNumber) use data ID = value + 3, with `DictionaryStorage.BaseId = -3`.
public enum VertiPaqWriter {
    /// Data ID reserved for NULL. The first real dictionary entry is ID 3.
    static let nullDataID = 2
    static let firstDataID = 3

    /// Bit widths that the decoder maps to a compression class.
    static let supportedWidths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16, 21, 32]

    /// Column values of one table. Rows are in storage order.
    public enum Values: Sendable, Equatable {
        case int64([Int64])
        case double([Double])
        /// `nil` is NULL.
        case string([String?])

        public var count: Int {
            switch self {
            case .int64(let v): v.count
            case .double(let v): v.count
            case .string(let v): v.count
            }
        }

        public var dataType: ModelMetadata.DataType {
            switch self {
            case .int64: .int64
            case .double: .double
            case .string: .string
            }
        }
    }

    /// One data column to encode. `id` is the TOM `Column.ID` chosen by the caller.
    public struct ColumnInput: Sendable, Equatable {
        public var id: Int
        /// `Column.ExplicitName`, e.g. `Doanh thu`. Used in file names as `Doanh thu (<id>)`.
        public var name: String
        public var values: Values

        public init(id: Int, name: String, values: Values) {
            self.id = id
            self.name = name
            self.values = values
        }
    }

    public enum Folder: Sendable, Equatable {
        /// `<Table> (<id>).tbl`
        case table
        /// `<Table> (<id>).tbl\<partition id>.prt`
        case partition
    }

    /// One file of the table. `path` is relative to the database persist root, with `\` separators.
    public struct EncodedFile: Sendable, Equatable {
        public let path: String
        /// Last path component, which is also `StorageFile.FileName`.
        public let fileName: String
        public let folder: Folder
        public let data: Data
    }

    /// One encoded column with the metadata that the metadata rows need.
    public struct EncodedColumn: Sendable {
        public enum Kind: Sendable, Equatable { case data, rowNumber }

        public let kind: Kind
        /// `Column.ID`.
        public let id: Int
        /// `Column.ExplicitName`, e.g. `Doanh thu` or `RowNumber-<GUID>`.
        public let explicitName: String
        /// Name in file names and `ColumnStorage.Name`, e.g. `Doanh thu (14)`.
        public let storageName: String
        public let dataType: ModelMetadata.DataType
        /// `ColumnStorage.StoragePosition`.
        public let storagePosition: Int
        /// The `.dictionary` file. `nil` for value-encoded columns.
        public let dictionary: EncodedFile?
        public let dictionaryCount: Int
        public let dictionaryByteCount: Int
        public let idf: EncodedFile
        public let idfmeta: EncodedFile
        public let rowCount: Int
        public let distinctCount: Int
        /// `SegmentStorage` statistics. `minDataID` is the base of bit-packed values.
        public let minDataID: Int
        public let maxDataID: Int
        public let originalMinDataID: Int
        public let hasNulls: Bool
        public let bitWidth: Int
        /// `AttributeHierarchyStorage.MinValue`, `MaxValue` and `StringValueMaxLength`.
        public let minValueText: String?
        public let maxValueText: String?
        public let stringValueMaxLength: Int

        /// `DictionaryStorage.Type`: 1 dictionary, 2 value encoded.
        public var dictionaryType: Int { dictionary == nil ? 2 : 1 }
        /// `DictionaryStorage.BaseId`: 2 (NULL id) for dictionary columns, -3 for RowNumber.
        public var dictionaryBaseID: Int { dictionary == nil ? -3 : VertiPaqWriter.nullDataID }
        /// `DictionaryStorage.Magnitude`: 0 for dictionary columns, 1 for value encoded.
        public var magnitude: Double { dictionary == nil ? 1 : 0 }
    }

    /// The encoded files of one table, with the IDs that the metadata rows refer to.
    public struct EncodedTable: Sendable {
        public let name: String
        public let tableID: Int
        public let partitionID: Int
        public let rowCount: Int
        /// The RowNumber column first, then the data columns in input order.
        public let columns: [EncodedColumn]

        /// Every file, in the order to add them to the ABF.
        public var files: [EncodedFile] {
            columns.flatMap { column in (column.dictionary.map { [$0] } ?? []) + [column.idf, column.idfmeta] }
        }

        public var tableFolderPath: String { "\(name) (\(tableID)).tbl" }
        public var partitionFolderPath: String { "\(name) (\(tableID)).tbl\\\(partitionID).prt" }
    }

    // MARK: - Table

    /// Encodes a table. Adds a RowNumber column (value encoded, `rowNumberID`) and the data columns.
    ///
    /// Throws `WriteError.invalid` when a name is empty or has a NUL, the column counts differ,
    /// IDs repeat, a string contains a NUL, or a bit width above 32 would be needed.
    public static func encodeTable(name: String, tableID: Int, partitionID: Int, rowNumberID: Int,
                                   rowNumberGUID: UUID = UUID(), columns: [ColumnInput]) throws -> EncodedTable {
        guard !name.isEmpty, !name.contains("\0") else { throw WriteError.invalid("table name is empty or has a NUL") }
        guard let first = columns.first else { throw WriteError.invalid("table \(name) has no columns") }
        let rowCount = first.values.count
        guard rowCount > 0 else { throw WriteError.invalid("table \(name) has no rows") }

        var ids = Set([tableID, partitionID, rowNumberID])
        guard ids.count == 3 else { throw WriteError.invalid("table, partition and RowNumber IDs must differ") }
        for column in columns {
            guard !column.name.isEmpty, !column.name.contains("\0") else {
                throw WriteError.invalid("column name is empty or has a NUL")
            }
            guard column.values.count == rowCount else {
                throw WriteError.invalid("column \(column.name) has \(column.values.count) rows, expected \(rowCount)")
            }
            guard ids.insert(column.id).inserted else { throw WriteError.invalid("ID \(column.id) is used twice") }
        }

        let folders = Folders(table: name, tableID: tableID, partitionID: partitionID)
        let rowNumberName = "RowNumber " + rowNumberGUID.uuidString.replacingOccurrences(of: "-", with: " ")
        var encoded: [EncodedColumn] = []

        // RowNumber: value i is data ID i + 3, value encoded (BaseId -3).
        let rowIDs = (0..<rowCount).map { Int64($0 + firstDataID) }
        let rowSegment = try encodeSegment(ids: rowIDs, dictionaryCount: rowCount)
        encoded.append(EncodedColumn(
            kind: .rowNumber, id: rowNumberID,
            explicitName: "RowNumber-" + rowNumberGUID.uuidString,
            storageName: "\(rowNumberName) (\(rowNumberID))",
            dataType: .int64, storagePosition: 0,
            dictionary: nil, dictionaryCount: 0, dictionaryByteCount: 0,
            idf: folders.file(.partition, "0.\(name) (\(tableID)).\(rowNumberName) (\(rowNumberID)).0.idf", rowSegment.idf),
            idfmeta: folders.file(.partition, "0.\(name) (\(tableID)).\(rowNumberName) (\(rowNumberID)).0.idfmeta", rowSegment.idfmeta),
            rowCount: rowCount, distinctCount: rowCount,
            minDataID: rowSegment.minDataID, maxDataID: rowSegment.maxDataID,
            originalMinDataID: rowSegment.originalMinDataID, hasNulls: false, bitWidth: rowSegment.bitWidth,
            minValueText: "0", maxValueText: String(rowCount - 1), stringValueMaxLength: 0))

        for (position, column) in columns.enumerated() {
            let storageName = "\(column.name) (\(column.id))"
            let dictionaryName = "0.\(name) (\(tableID)).\(storageName).dictionary"
            let segmentBase = "0.\(name) (\(tableID)).\(storageName).0"
            let dictionary = try encodeDictionary(column.values)
            let segment = try encodeSegment(ids: dictionary.ids, dictionaryCount: dictionary.count)
            let (minText, maxText, maxLength) = textStatistics(column.values)
            encoded.append(EncodedColumn(
                kind: .data, id: column.id, explicitName: column.name, storageName: storageName,
                dataType: column.values.dataType, storagePosition: position + 1,
                dictionary: folders.file(.table, dictionaryName, dictionary.data),
                dictionaryCount: dictionary.count, dictionaryByteCount: dictionary.data.count,
                idf: folders.file(.partition, segmentBase + ".idf", segment.idf),
                idfmeta: folders.file(.partition, segmentBase + ".idfmeta", segment.idfmeta),
                rowCount: rowCount, distinctCount: dictionary.count,
                minDataID: segment.minDataID, maxDataID: segment.maxDataID,
                originalMinDataID: segment.originalMinDataID, hasNulls: dictionary.hasNulls,
                bitWidth: segment.bitWidth,
                minValueText: minText, maxValueText: maxText, stringValueMaxLength: maxLength))
        }

        return EncodedTable(name: name, tableID: tableID, partitionID: partitionID, rowCount: rowCount,
                            columns: encoded)
    }

    // MARK: - Dictionary

    struct DictionaryResult {
        let data: Data
        /// Data ID per row (`nullDataID` for NULL).
        let ids: [Int64]
        let count: Int
        let hasNulls: Bool
    }

    /// Builds the dictionary of a column. Entries keep the order of first appearance.
    static func encodeDictionary(_ values: Values) throws -> DictionaryResult {
        switch values {
        case .int64(let v):
            var index: [Int64: Int] = [:]
            var order: [Int64] = []
            let ids: [Int64] = v.map { value in
                if let i = index[value] { return Int64(i + firstDataID) }
                index[value] = order.count
                order.append(value)
                return Int64(order.count - 1 + firstDataID)
            }
            var out = VertiPaqByteWriter()
            out.i32(0)
            out.hashInfo(longs: true)
            out.u64(UInt64(order.count))
            // Small values use 4-byte elements, as Power BI does; larger ones use 8 bytes.
            let fitsInt32 = order.allSatisfy { Int32(exactly: $0) != nil }
            out.u32(fitsInt32 ? 4 : 8)
            for value in order {
                if fitsInt32 { out.i32(Int32(value)) } else { out.u64(UInt64(bitPattern: value)) }
            }
            return DictionaryResult(data: out.data, ids: ids, count: order.count, hasNulls: false)

        case .double(let v):
            var index: [UInt64: Int] = [:]
            var order: [Double] = []
            let ids: [Int64] = v.map { value in
                let key = value.bitPattern
                if let i = index[key] { return Int64(i + firstDataID) }
                index[key] = order.count
                order.append(value)
                return Int64(order.count - 1 + firstDataID)
            }
            var out = VertiPaqByteWriter()
            out.i32(1)
            out.hashInfo(longs: false)
            out.u64(UInt64(order.count))
            out.u32(8)
            for value in order { out.u64(value.bitPattern) }
            return DictionaryResult(data: out.data, ids: ids, count: order.count, hasNulls: false)

        case .string(let v):
            var index: [String: Int] = [:]
            var order: [String] = []
            var hasNulls = false
            var ids: [Int64] = []
            ids.reserveCapacity(v.count)
            for value in v {
                guard let value else {
                    hasNulls = true
                    ids.append(Int64(nullDataID))
                    continue
                }
                guard !value.contains("\0") else { throw WriteError.invalid("string value contains a NUL") }
                if let i = index[value] {
                    ids.append(Int64(i + firstDataID))
                } else {
                    index[value] = order.count
                    order.append(value)
                    ids.append(Int64(order.count - 1 + firstDataID))
                }
            }
            return DictionaryResult(data: try stringDictionary(order), ids: ids, count: order.count, hasNulls: hasNulls)
        }
    }

    /// String dictionary: one plain page holding every string, each followed by a NUL code unit.
    static func stringDictionary(_ strings: [String]) throws -> Data {
        var page: [UInt16] = []
        var offsets: [UInt32] = []
        var longest = 0
        for string in strings {
            offsets.append(UInt32(page.count))
            let units = Array(string.utf16)
            longest = max(longest, units.count)
            page += units
            page.append(0)
        }

        var out = VertiPaqByteWriter()
        out.i32(2)
        out.hashInfo(longs: false, string: true)
        out.u64(UInt64(strings.count))
        out.u8(1) // store compressed (as observed); the single page itself is plain
        out.u64(UInt64(longest))
        if strings.isEmpty {
            out.u64(0)
        } else {
            out.u64(1)
            // Page header: mask, nulls, start, count, compressed flag, then the begin marker.
            out.u64(0); out.u8(0); out.u64(0); out.u64(UInt64(strings.count)); out.u8(0)
            out.bytes([0xDD, 0xCC, 0xBB, 0xAA])
            // Plain page: remaining, used (code units), allocation (bytes), text, end marker.
            out.u64(0)
            out.u64(UInt64(page.count))
            out.u64(UInt64(page.count * 2))
            for unit in page { out.u16(unit) }
            out.bytes([0xCD, 0xAB, 0xCD, 0xAB])
        }
        out.u64(UInt64(strings.count))
        out.bytes([8, 0, 0, 0])
        for offset in offsets {
            out.u32(offset)
            out.u32(0)
        }
        return out.data
    }

    // MARK: - Segment

    struct SegmentResult {
        let idf: Data
        let idfmeta: Data
        let minDataID: Int
        let maxDataID: Int
        let originalMinDataID: Int
        let bitWidth: Int
    }

    /// One segment with all rows bit packed. `ids` are data IDs (NULL is `nullDataID`).
    static func encodeSegment(ids: [Int64], dictionaryCount: Int) throws -> SegmentResult {
        let records = ids.count
        guard records <= Int(UInt32.max), ids.allSatisfy({ $0 >= 0 && $0 <= Int64(UInt32.max) }) else {
            throw WriteError.invalid("segment of \(records) rows has data IDs outside the 32-bit range")
        }
        let hasNulls = ids.contains(Int64(nullDataID))
        let nonNull = ids.filter { $0 != Int64(nullDataID) }
        let minDataID = Int(nonNull.min() ?? Int64(firstDataID))
        let maxDataID = Int(ids.max() ?? Int64(firstDataID))
        let originalMin = Int(ids.min() ?? Int64(firstDataID))
        // With NULLs the segment is based at the NULL id, otherwise at its own minimum (decoder rule).
        let base = hasNulls ? nullDataID : minDataID
        let packedValues = ids.map { UInt64(max(0, Int($0) - base)) }
        let (width, compressionClass) = try bitWidthAndClass(for: packedValues.max() ?? 0)
        let words = pack(packedValues, width: width)

        // .idf: one bit-packed run (marker 0xFFFFFFFF - 0), then the words.
        var idf = VertiPaqByteWriter()
        idf.u64(1)
        idf.u32(0xFFFF_FFFF)
        idf.u32(UInt32(records))
        idf.u64(UInt64(words.count))
        for word in words { idf.u64(word) }

        // .idfmeta: CP / CS / SS / bit-packed sub-block / trailer.
        var meta = VertiPaqByteWriter()
        meta.tag("<1:CP")
        meta.u64(1)
        meta.tag("<1:CS")
        meta.u64(UInt64(records))
        meta.u64(1)                      // base segment id, as observed
        meta.u32(0xABA5A)                // hybrid RLE facet
        meta.u32(UInt32(compressionClass))
        meta.u64(13); meta.u64(32); meta.u64(4); meta.u8(0) // facet values observed for bit-packed-only segments
        meta.u32(UInt32(base))           // first run value
        meta.tag("<1:SS")
        meta.u64(UInt64(dictionaryCount))
        meta.u32(UInt32(minDataID))
        meta.u32(UInt32(maxDataID))
        meta.u32(UInt32(originalMin))
        meta.u64(UInt64.max)             // RLE sort order: none
        meta.u64(UInt64(records))
        meta.u8(hasNulls ? 1 : 0)
        meta.u64(0); meta.u64(0)         // RLE runs
        meta.tag("SS:1>")
        meta.u8(1)
        meta.tag("<1:CS")
        meta.u64(UInt64(records))        // bit-packed values
        meta.u64(0)
        meta.u8(0)
        meta.tag("CS:1>")
        meta.tag("CS:1>")
        meta.tag("CP:1>")
        // Trailer describing the IDF layout (runs, then words). Ignored by the decoder.
        meta.tag("<1:SDOs")
        meta.tag("<1:CSDOs")
        meta.u64(0); meta.u64(1)
        meta.tag("<1:CSDOs")
        meta.u64(16)                     // runs section: count + one run
        meta.u64(UInt64(words.count))
        meta.tag("CSDOs:1>")
        meta.tag("CSDOs:1>")
        meta.tag("SDOs:1>")

        return SegmentResult(idf: idf.data, idfmeta: meta.data, minDataID: minDataID, maxDataID: maxDataID,
                             originalMinDataID: originalMin, bitWidth: width)
    }

    /// The smallest supported width that holds `maximum`, and its compression class.
    static func bitWidthAndClass(for maximum: UInt64) throws -> (width: Int, compressionClass: Int) {
        let needed = max(1, maximum == 0 ? 1 : 64 - maximum.leadingZeroBitCount)
        guard let width = supportedWidths.first(where: { $0 >= needed }) else {
            throw WriteError.invalid("values need \(needed) bits, which the VertiPaq writer does not support")
        }
        let compressionClass: Int
        switch width {
        case 1...10: compressionClass = 703_030 + width
        case 12: compressionClass = 703_042
        case 16: compressionClass = 703_046
        case 21: compressionClass = 703_051
        default: compressionClass = 703_062 // 32
        }
        return (width, compressionClass)
    }

    /// Packs values LSB first, `64 / width` values per word, never straddling a word.
    static func pack(_ values: [UInt64], width: Int) -> [UInt64] {
        let perWord = 64 / width
        var words = [UInt64](repeating: 0, count: (values.count + perWord - 1) / perWord)
        for (i, value) in values.enumerated() {
            words[i / perWord] |= (value & mask(width)) << (UInt64(i % perWord) * UInt64(width))
        }
        return words
    }

    static func mask(_ width: Int) -> UInt64 {
        width >= 64 ? .max : (UInt64(1) << UInt64(width)) - 1
    }

    // MARK: - Statistics

    static func textStatistics(_ values: Values) -> (String?, String?, Int) {
        switch values {
        case .int64(let v):
            return (v.min().map(String.init), v.max().map(String.init), 0)
        case .double(let v):
            return (v.min().map { String($0) }, v.max().map { String($0) }, 0)
        case .string(let v):
            let present = v.compactMap { $0 }
            let longest = present.map { $0.utf16.count }.max() ?? 0
            return (present.min(), present.max(), longest)
        }
    }

    // MARK: - Files

    struct Folders {
        let table: String
        let tableID: Int
        let partitionID: Int

        func file(_ folder: Folder, _ fileName: String, _ data: Data) -> EncodedFile {
            let prefix: String
            switch folder {
            case .table: prefix = "\(table) (\(tableID)).tbl"
            case .partition: prefix = "\(table) (\(tableID)).tbl\\\(partitionID).prt"
            }
            return EncodedFile(path: prefix + "\\" + fileName, fileName: fileName, folder: folder, data: data)
        }
    }
}

/// Little-endian byte writer for the VertiPaq layouts.
struct VertiPaqByteWriter {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }

    mutating func u16(_ v: UInt16) {
        data.append(UInt8(truncatingIfNeeded: v))
        data.append(UInt8(truncatingIfNeeded: v >> 8))
    }

    mutating func u32(_ v: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: v >> UInt32(shift))) }
    }

    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }

    mutating func u64(_ v: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) { data.append(UInt8(truncatingIfNeeded: v >> UInt64(shift))) }
    }

    mutating func bytes(_ values: [UInt8]) { data.append(contentsOf: values) }

    /// An ASCII tag followed by a NUL byte, as in `<1:CP\0`.
    mutating func tag(_ text: String) {
        data.append(contentsOf: Array(text.utf8))
        data.append(0)
    }

    /// The six `i32` hash-information fields that follow the kind.
    mutating func hashInfo(longs: Bool, string: Bool = false) {
        let values: [Int32]
        if string {
            values = [0, 8, 64, 6, -1, -1]
        } else if longs {
            values = [-1, 8, 64, 6, -1, -1]
        } else {
            values = [-1, 16, 64, 3, -1, -1]
        }
        for value in values { i32(value) }
    }
}
