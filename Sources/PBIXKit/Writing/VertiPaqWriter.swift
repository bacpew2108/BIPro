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

    /// Every Desktop table names its RowNumber column `RowNumber-2662979B-1795-4F74-8F37-6A1BA8059B61` (Marketing, sales_2026, probe).
    public static let rowNumberColumnGUID = UUID(uuidString: "2662979B-1795-4F74-8F37-6A1BA8059B61")!

    /// Số dòng của một đoạn dữ liệu: 2^20 như Desktop (VM-F14, DMV `DISCOVER_STORAGE_TABLE_COLUMN_SEGMENTS`: 10 triệu dòng thành 9 đoạn
    /// 1 048 576 dòng và một đoạn 562 816). Phần lẻ nhỏ gộp vào đoạn trước (Nhom6 `Fact Transaction`: 1 056 320 dòng một đoạn);
    /// `[SUY ĐOÁN]` ngưỡng gộp là 1/8 đoạn (`tailMergeLimit`).
    public static let recordsPerSegment = 1_048_576
    static var tailMergeLimit: Int { recordsPerSegment / 8 }
    /// Cỡ đoạn bộ ghi dùng cho bảng mới: **một đoạn** (gate VM-F14, 2026-11-19: tệp 2,5 triệu dòng ghi ba đoạn bị Desktop báo DBCC hỏng, ghi một
    /// đoạn thì mở được và số đúng). Bố cục byte của nhiều đoạn chưa có mẫu Desktop để so; `recordsPerSegment` giữ cỡ Desktop dùng.
    nonisolated(unsafe) public static var segmentSizeForNewTables = Int.max

    /// Số dòng từng đoạn khi cắt `rows` dòng theo `segmentSize` (phần lẻ ≤ 1/8 đoạn gộp vào đoạn trước).
    static func segmentLayout(rows: Int, segmentSize: Int) -> [Int] {
        guard rows > segmentSize else { return [rows] }
        var sizes = Array(repeating: segmentSize, count: rows / segmentSize)
        let tail = rows % segmentSize
        if tail > 0 {
            if tail <= segmentSize / 8 { sizes[sizes.count - 1] += tail } else { sizes.append(tail) }
        }
        return sizes
    }

    /// Desktop writes 16 runs in every `.idf` run table.
    static let runTableSize = 16

    /// Bit widths that the decoder maps to a compression class.
    static let supportedWidths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16, 21, 32]

    /// Column values of one table. Rows are in storage order.
    public enum Values: Sendable, Equatable {
        case int64([Int64?])
        /// Logic: Desktop lưu 0/1 (`DataType` 11). BI Pro ghi bằng từ điển băm số nguyên, như cột số nguyên.
        case boolean([Bool?])
        case double([Double?])
        /// OLE automation days (`46083` = 2026-03-02), as Desktop stores `date` columns: a dictionary of doubles (`DataType` 9).
        case dateTime([Double?])
        /// `nil` is NULL.
        case string([String?])
        /// Fixed decimal (tiền tệ): Int64 nhân 10⁴. Desktop 2.159 (golden `f9currency-desktop.pbix`, 2026-11-17) lưu như cột số nguyên
        /// (`DictionaryStorage.DataType` 6) với `Column.DataType` 10; giá trị `Int64.max` bị Desktop từ chối.
        case currency([Int64?])

        public var count: Int {
            switch self {
            case .int64(let v), .currency(let v): v.count
            case .boolean(let v): v.count
            case .double(let v), .dateTime(let v): v.count
            case .string(let v): v.count
            }
        }

        public var dataType: ModelMetadata.DataType {
            switch self {
            case .int64: .int64
            case .currency: .decimal
            case .boolean: .boolean
            case .double: .double
            case .dateTime: .dateTime
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
        /// `DictionaryStorage.IsOperatingOn32`.
        public let operatesOn32: Bool
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
        /// `Statistics_RLERuns`, `Statistics_OthersRLERuns` (sum over segments).
        public var rleRuns: Int = 0
        public var bitPackedRuns: Int = 1
        /// `AttributeHierarchyStorage.MinValue`, `MaxValue` and `StringValueMaxLength`.
        public let minValueText: String?
        public let maxValueText: String?
        public let stringValueMaxLength: Int
        /// The `H$` system table that every dictionary column needs (gate F-T3, 2026-11-15: without it Desktop
        /// reports "The 'H$…' system table is missing"). `nil` for RowNumber.
        public let hierarchy: EncodedHierarchy?

        /// `DictionaryStorage.Type`: 1 dictionary, 2 value encoded.
        public var dictionaryType: Int { dictionary == nil ? 2 : 1 }
        /// `DictionaryStorage.BaseId`: 2 (NULL id) for dictionary columns, -3 for RowNumber.
        public var dictionaryBaseID: Int { dictionary == nil ? -3 : VertiPaqWriter.nullDataID }
        /// `DictionaryStorage.Magnitude`: 0 for dictionary columns, 1 for value encoded.
        public var magnitude: Double { dictionary == nil ? 1 : 0 }
    }

    /// The files of the `H$` system table of one column (`POS_TO_ID` and `ID_TO_POS`).
    public struct EncodedHierarchy: Sendable {
        public let positionToID: Hierarchy.Blob
        public let idToPosition: Hierarchy.Blob
        /// Dictionary entries including NULL (`AttributeHierarchyStorage.DistinctDataCount`, `RecordsPerSegment`).
        public let cardinality: Int
        /// `SegmentMapStorage.RecordCount`: the largest data ID + 1.
        public let recordCount: Int
        /// `SegmentMapStorage.SegmentCount`: `recordCount` cut into pieces of `cardinality`.
        public let segmentCount: Int
    }

    public enum Hierarchy {
        public struct Blob: Sendable {
            public let idf: Data
            public let idfmeta: Data
        }
    }

    /// The encoded files of one table, with the IDs that the metadata rows refer to.
    public struct EncodedTable: Sendable {
        public let name: String
        public let tableID: Int
        public let partitionID: Int
        public let rowCount: Int
        /// The RowNumber column first, then the data columns in input order.
        public let columns: [EncodedColumn]
        /// Rows of each segment (one entry for a table of one segment).
        public var segmentRecords: [Int] = []

        /// `SegmentMapStorage.SegmentCount` and `RecordsPerSegment` (Desktop: the row count when there is one segment).
        public var segmentCount: Int { max(1, segmentRecords.count) }
        public var recordsPerSegment: Int { segmentRecords.count > 1 ? segmentRecords[0] : rowCount }

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
                                   rowNumberGUID: UUID = rowNumberColumnGUID, columns: [ColumnInput],
                                   segmentSize: Int = segmentSizeForNewTables) throws -> EncodedTable {
        guard !name.isEmpty, !name.contains("\0") else { throw WriteError.invalid("tên bảng rỗng hoặc có ký tự NUL") }
        guard let first = columns.first else { throw WriteError.invalid("bảng «\(name)» không có cột nào") }
        let rowCount = first.values.count
        guard rowCount > 0 else { throw WriteError.invalid("bảng «\(name)» không có dòng nào, chưa lưu được bảng rỗng") }

        var ids = Set([tableID, partitionID, rowNumberID])
        guard ids.count == 3 else { throw WriteError.invalid("ID của bảng, phân vùng và cột RowNumber phải khác nhau") }
        var names = Set<String>()
        for column in columns {
            guard !column.name.isEmpty, !column.name.contains("\0") else {
                throw WriteError.invalid("bảng «\(name)» có tên cột rỗng hoặc có ký tự NUL")
            }
            // Tên cột trong một bảng không phân biệt hoa thường (như mô hình tabular).
            guard names.insert(column.name.lowercased()).inserted else {
                throw WriteError.invalid("bảng «\(name)» có hai cột trùng tên «\(column.name)» (không phân biệt hoa thường)")
            }
            guard column.values.count == rowCount else {
                throw WriteError.invalid("cột «\(column.name)» có \(column.values.count) dòng, cần \(rowCount)")
            }
            guard ids.insert(column.id).inserted else { throw WriteError.invalid("ID \(column.id) bị dùng hai lần") }
        }

        let folders = Folders(table: name, tableID: tableID, partitionID: partitionID)
        let rowNumberName = "RowNumber " + rowNumberGUID.uuidString.replacingOccurrences(of: "-", with: " ")
        var encoded: [EncodedColumn] = []

        // RowNumber: value i is data ID i + 3, value encoded (BaseId -3).
        let rowIDs = (0..<rowCount).map { Int64($0 + firstDataID) }
        let rowSegment = try encodeSegment(ids: rowIDs, dictionaryCount: rowCount, segmentSize: segmentSize)
        encoded.append(EncodedColumn(
            kind: .rowNumber, id: rowNumberID,
            explicitName: "RowNumber-" + rowNumberGUID.uuidString,
            storageName: "\(rowNumberName) (\(rowNumberID))",
            dataType: .int64, storagePosition: 0,
            operatesOn32: false, dictionary: nil, dictionaryCount: 0, dictionaryByteCount: 0,
            idf: folders.file(.partition, "0.\(name) (\(tableID)).\(rowNumberName) (\(rowNumberID)).0.idf", rowSegment.idf),
            idfmeta: folders.file(.partition, "0.\(name) (\(tableID)).\(rowNumberName) (\(rowNumberID)).0.idfmeta", rowSegment.idfmeta),
            rowCount: rowCount, distinctCount: rowCount,
            minDataID: rowSegment.minDataID, maxDataID: rowSegment.maxDataID,
            originalMinDataID: rowSegment.originalMinDataID, hasNulls: false, bitWidth: rowSegment.bitWidth,
            rleRuns: rowSegment.rleRuns, bitPackedRuns: rowSegment.bitPackedRuns,
            minValueText: "0", maxValueText: String(rowCount - 1), stringValueMaxLength: 0, hierarchy: nil))

        for (position, column) in columns.enumerated() {
            let storageName = "\(column.name) (\(column.id))"
            let dictionaryName = "0.\(name) (\(tableID)).\(storageName).dictionary"
            let segmentBase = "0.\(name) (\(tableID)).\(storageName).0"
            let dictionary = try encodeDictionary(column.values)
            let segment = try encodeSegment(ids: dictionary.ids, dictionaryCount: dictionary.count, segmentSize: segmentSize)
            let (minText, maxText, maxLength) = textStatistics(column.values)
            encoded.append(EncodedColumn(
                kind: .data, id: column.id, explicitName: column.name, storageName: storageName,
                dataType: column.values.dataType, storagePosition: position + 1,
                operatesOn32: dictionary.operatesOn32, dictionary: folders.file(.table, dictionaryName, dictionary.data),
                dictionaryCount: dictionary.count, dictionaryByteCount: dictionary.data.count,
                idf: folders.file(.partition, segmentBase + ".idf", segment.idf),
                idfmeta: folders.file(.partition, segmentBase + ".idfmeta", segment.idfmeta),
                rowCount: rowCount, distinctCount: dictionary.count,
                minDataID: segment.minDataID, maxDataID: segment.maxDataID,
                originalMinDataID: segment.originalMinDataID, hasNulls: dictionary.hasNulls,
                bitWidth: segment.bitWidth, rleRuns: segment.rleRuns, bitPackedRuns: segment.bitPackedRuns,
                minValueText: minText, maxValueText: maxText, stringValueMaxLength: maxLength,
                hierarchy: try encodeHierarchy(sortedIDs: dictionary.sortedIDs, dictionaryCount: dictionary.count,
                                               hasNulls: dictionary.hasNulls)))
        }

        return EncodedTable(name: name, tableID: tableID, partitionID: partitionID, rowCount: rowCount,
                            columns: encoded, segmentRecords: rowSegment.segmentRecords)
    }

    // MARK: - Dictionary

    struct DictionaryResult {
        let data: Data
        /// Data ID per row (`nullDataID` for NULL).
        let ids: [Int64]
        let count: Int
        let hasNulls: Bool
        /// Data IDs in ascending value order, NULL first when present. Feeds the `H$` table.
        let sortedIDs: [Int64]
        /// `DictionaryStorage.IsOperatingOn32`: whole numbers stored as 4-byte elements (Desktop: Marketing `Conversion`).
        var operatesOn32 = false
    }

    /// Builds the dictionary of a column. Entries keep the order of first appearance; NULL is data ID 2 and is not an entry.
    static func encodeDictionary(_ values: Values) throws -> DictionaryResult {
        /// IDs per row and the distinct entries in order of appearance, for any hashable value.
        func assign<T: Hashable>(_ v: [T?]) -> (ids: [Int64], order: [T], hasNulls: Bool) {
            var index: [T: Int] = [:]
            var order: [T] = []
            var hasNulls = false
            let ids: [Int64] = v.map { value in
                guard let value else { hasNulls = true; return Int64(nullDataID) }
                if let i = index[value] { return Int64(i + firstDataID) }
                index[value] = order.count
                order.append(value)
                return Int64(order.count - 1 + firstDataID)
            }
            return (ids, order, hasNulls)
        }

        if case .boolean(let flags) = values { return try encodeDictionary(.int64(flags.map { $0.map { $0 ? 1 : 0 } })) }
        if case .currency(let amounts) = values {
            guard !amounts.contains(Int64.max) else {
                throw WriteError.invalid("giá trị tiền tệ 922337203685477,5807 không được hỗ trợ (Desktop cũng từ chối)")
            }
            return try encodeDictionary(.int64(amounts))
        }
        switch values {
        case .boolean, .currency: fatalError("đã đổi sang số nguyên ở trên")
        case .int64(let v):
            let (ids, order, hasNulls) = assign(v)
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
            return DictionaryResult(data: out.data, ids: ids, count: order.count, hasNulls: hasNulls,
                                    sortedIDs: sortedIDs(order.indices.sorted { order[$0] < order[$1] }, hasNulls: hasNulls),
                                    operatesOn32: fitsInt32)

        case .double(let v), .dateTime(let v):
            // -0.0 and 0.0 are one value to the model; NaN has no place in a column.
            guard v.allSatisfy({ $0 == nil || !$0!.isNaN }) else { throw WriteError.invalid("cột số có giá trị NaN (không phải số), chưa lưu được") }
            let (ids, order, hasNulls) = assign(v.map { $0.map { $0 == 0 ? 0.0 : $0 } })
            var out = VertiPaqByteWriter()
            out.i32(1)
            out.hashInfo(longs: false)
            out.u64(UInt64(order.count))
            out.u32(8)
            for value in order { out.u64(value.bitPattern) }
            return DictionaryResult(data: out.data, ids: ids, count: order.count, hasNulls: hasNulls,
                                    sortedIDs: sortedIDs(order.indices.sorted { order[$0] < order[$1] }, hasNulls: hasNulls))

        case .string(let v):
            guard v.allSatisfy({ $0 == nil || !$0!.contains("\0") }) else { throw WriteError.invalid("cột chuỗi có giá trị chứa ký tự NUL, chưa lưu được") }
            let (ids, order, hasNulls) = assign(v)
            return DictionaryResult(data: try stringDictionary(order), ids: ids, count: order.count, hasNulls: hasNulls,
                                    sortedIDs: sortedIDs(order.indices.sorted { collates(order[$0], order[$1]) }, hasNulls: hasNulls))
        }
    }

    /// IDs in value order. `sortedIndices` are dictionary indices already sorted by value.
    static func sortedIDs(_ sortedIndices: [Int], hasNulls: Bool = false) -> [Int64] {
        (hasNulls ? [Int64(nullDataID)] : []) + sortedIndices.map { Int64($0 + firstDataID) }
    }

    /// String order of the `H$` table. [SUY ĐOÁN] en-US culture order (lowercase before uppercase on a tie); not yet
    /// checked against Desktop for accents or mixed case.
    static func collates(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US")) == .orderedAscending
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
            // Page header: mask, "has an empty string" flag (Desktop sets it; without it the string store fails DBCC, gate F-T3 2026-11-15),
            // start, count, compressed flag, then the begin marker.
            out.u64(0); out.u8(strings.contains("") ? 1 : 0); out.u64(0); out.u64(UInt64(strings.count)); out.u8(0)
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
        /// Column-level statistics over every segment.
        let minDataID: Int
        let maxDataID: Int
        let originalMinDataID: Int
        let bitWidth: Int
        /// `Statistics_RLERuns` / `Statistics_OthersRLERuns`: RLE runs and bit-packed runs, summed over segments.
        let rleRuns: Int
        let bitPackedRuns: Int
        /// Rows of each segment, in order.
        let segmentRecords: [Int]
    }

    /// One run of a segment: a repeated data ID, or `count` bit-packed values.
    enum Run: Equatable {
        case repeated(id: Int64, count: Int)
        case packed(count: Int)
    }

    /// Encodes the data IDs of a column (NULL is `nullDataID`) as segments of `segmentSize` rows (US5, T055/T056).
    ///
    /// Each segment is a hybrid RLE + bit-packing block as Desktop writes it (Nhom6 `Fact Transaction`, 1 056 320 rows):
    /// - `.idf`: per segment `u64 runTableSize`, the run table (`(u32 value, u32 repeats)`; a bit-packed run has value
    ///   `0xFFFFFFFF - values packed so far`), `u64 wordCount`, the words. The run table is the next power of two above the runs used
    ///   (at least 16), unused entries zero. With no bit-packed value Desktop still writes one zero word.
    /// - `.idfmeta`: `<1:CP n`, one `<1:CS` per segment (facet `(a, 2·runTableSize, 2·runs + 2, 0)`, statistics with RLE and bit-packed
    ///   run counts, bit-packed sub-block), `CP:1>`, then `<1:SDOs` with each segment's run section and word section offsets.
    ///
    /// `[SUY ĐOÁN]` (VM-F14 chưa quan sát): Desktop reorders rows to lengthen runs; BI Pro keeps the source order. Facet `a` (11–23 in
    /// Desktop's files, rule unknown, ignored by the decoder) stays `min(rows, 13)` as before.
    static func encodeSegment(ids: [Int64], dictionaryCount: Int, segmentSize: Int = recordsPerSegment) throws -> SegmentResult {
        guard ids.count <= Int(UInt32.max) * 4, ids.allSatisfy({ $0 >= 0 && $0 <= Int64(UInt32.max) }) else {
            throw WriteError.invalid("đoạn dữ liệu \(ids.count) dòng có mã vượt quá 32 bit, chưa lưu được")
        }
        guard segmentSize > 0 else { throw WriteError.invalid("cỡ đoạn dữ liệu phải lớn hơn 0") }
        var idf = VertiPaqByteWriter()
        var blocks: [(meta: VertiPaqByteWriter, start: Int, runTableSize: Int, words: Int)] = []
        var minAll = Int.max, maxAll = Int.min, originalMin = Int.max, widest = 1, rleTotal = 0, packedTotal = 0
        var records: [Int] = []
        var start = 0
        for size in segmentLayout(rows: ids.count, segmentSize: segmentSize) {
            let end = start + size
            let segment = ids[start..<end]
            let fileOffset = idf.data.count
            let block = try encodeOneSegment(segment, into: &idf)
            blocks.append((block.meta, fileOffset, block.runTableSize, block.words))
            minAll = min(minAll, block.minDataID); maxAll = max(maxAll, block.maxDataID); originalMin = min(originalMin, block.originalMin)
            widest = max(widest, block.bitWidth); rleTotal += block.rleRuns; packedTotal += block.packedRuns
            records.append(segment.count)
            start = end
        }

        var meta = VertiPaqByteWriter()
        meta.tag("<1:CP")
        meta.u64(UInt64(blocks.count))
        for block in blocks { meta.append(block.meta) }
        meta.tag("CP:1>")
        // Trailer describing the IDF layout of each segment (runs, then words). Ignored by the decoder.
        meta.tag("<1:SDOs")
        for block in blocks {
            meta.tag("<1:CSDOs")
            meta.u64(UInt64(block.start)); meta.u64(UInt64(block.runTableSize))
            meta.tag("<1:CSDOs")
            meta.u64(UInt64(block.start + 8 + 8 * block.runTableSize))
            meta.u64(UInt64(block.words))
            meta.tag("CSDOs:1>")
            meta.tag("CSDOs:1>")
        }
        meta.tag("SDOs:1>")
        return SegmentResult(idf: idf.data, idfmeta: meta.data, minDataID: minAll == .max ? firstDataID : minAll,
                             maxDataID: maxAll == .min ? firstDataID : maxAll, originalMinDataID: originalMin == .max ? firstDataID : originalMin,
                             bitWidth: widest, rleRuns: rleTotal, bitPackedRuns: packedTotal, segmentRecords: records)
    }

    /// Shortest run Desktop stores as an RLE entry: the shortest RLE runs in Desktop's files are 64–66 values (Nhom6 `account key`,
    /// Marketing `Conversion dự kiến`), shorter repeats stay bit packed. `[SUY ĐOÁN]` the cut is exactly 64.
    static let minimumRLERun = 64

    /// Runs of one segment: repeated IDs of at least `minimumRLERun` values become RLE entries, the rest is bit packed.
    static func runs(_ ids: ArraySlice<Int64>) -> [Run] {
        let minimum = minimumRLERun
        var out: [Run] = []
        func addPacked(_ n: Int) {
            guard n > 0 else { return }
            if case .packed(let c)? = out.last { out[out.count - 1] = .packed(count: c + n) } else { out.append(.packed(count: n)) }
        }
        var i = ids.startIndex
        while i < ids.endIndex {
            var j = i + 1
            while j < ids.endIndex, ids[j] == ids[i] { j += 1 }
            let length = j - i
            if length >= minimum { out.append(.repeated(id: ids[i], count: length)) } else { addPacked(length) }
            i = j
        }
        return out
    }

    private struct SegmentBlock {
        var meta: VertiPaqByteWriter
        var runTableSize: Int
        var words: Int
        var minDataID: Int
        var maxDataID: Int
        var originalMin: Int
        var bitWidth: Int
        var rleRuns: Int
        var packedRuns: Int
    }

    private static func encodeOneSegment(_ ids: ArraySlice<Int64>, into idf: inout VertiPaqByteWriter) throws -> SegmentBlock {
        let records = ids.count
        var hasNulls = false, minNonNull = Int64.max, maxID = Int64.min, minID = Int64.max
        for id in ids {
            if id == Int64(nullDataID) { hasNulls = true } else { minNonNull = min(minNonNull, id) }
            maxID = max(maxID, id); minID = min(minID, id)
        }
        let minDataID = minNonNull == .max ? firstDataID : Int(minNonNull)
        let maxDataID = maxID == .min ? firstDataID : Int(maxID)
        // With NULLs the segment is based at the NULL id, otherwise at its own minimum (decoder rule).
        let base = hasNulls ? nullDataID : minDataID
        // Desktop sizes the bit width on the whole segment range, RLE values included (Marketing `Nguồn traffic`: one packed value, 3 bits).
        let (width, compressionClass) = try bitWidthAndClass(for: UInt64(max(0, maxDataID - base)))
        let runs = runs(ids)
        var packed: [UInt64] = []
        packed.reserveCapacity(records)
        var cursor = ids.startIndex
        for run in runs {
            switch run {
            case .repeated(_, let count): cursor += count
            case .packed(let count):
                for id in ids[cursor..<(cursor + count)] { packed.append(UInt64(max(0, Int(id) - base))) }
                cursor += count
            }
        }
        var words = pack(packed, width: width)
        if words.isEmpty { words = [0] }
        let used = runs.count
        var tableSize = runTableSize
        while tableSize <= used { tableSize *= 2 }

        idf.u64(UInt64(tableSize))
        var packedSoFar: UInt64 = 0
        var rleRuns = 0, packedRuns = 0
        for run in runs {
            switch run {
            case .repeated(let id, let count):
                idf.u32(UInt32(id)); idf.u32(UInt32(count)); rleRuns += 1
            case .packed(let count):
                idf.u32(UInt32(0xFFFF_FFFF - packedSoFar)); idf.u32(UInt32(count)); packedSoFar += UInt64(count); packedRuns += 1
            }
        }
        for _ in used..<tableSize { idf.u32(0); idf.u32(0) }
        idf.u64(UInt64(words.count))
        for word in words { idf.u64(word) }

        var meta = VertiPaqByteWriter()
        meta.tag("<1:CS")
        meta.u64(UInt64(records))
        meta.u64(1)                      // base segment id, as observed
        meta.u32(0xABA5A)                // hybrid RLE facet
        meta.u32(UInt32(compressionClass))
        meta.u64(UInt64(min(records, 13))); meta.u64(UInt64(2 * tableSize)); meta.u64(UInt64(2 * used + 2)); meta.u8(0)
        meta.u32(UInt32(base))           // first run value
        meta.tag("<1:SS")
        meta.u64(0)                      // distinct states: 0 in Desktop's files
        meta.u32(UInt32(minDataID))
        meta.u32(UInt32(maxDataID))
        meta.u32(UInt32(nullDataID))     // original minimum segment data ID: always 2
        meta.u64(UInt64.max)             // RLE sort order: none
        meta.u64(UInt64(records))
        meta.u8(hasNulls ? 1 : 0)
        meta.u64(UInt64(rleRuns)); meta.u64(UInt64(packedRuns))
        meta.tag("SS:1>")
        meta.u8(1)
        meta.tag("<1:CS")
        meta.u64(UInt64(packed.count))   // bit-packed values
        meta.u64(0)
        meta.u8(0)
        meta.tag("CS:1>")
        meta.tag("CS:1>")
        return SegmentBlock(meta: meta, runTableSize: tableSize, words: words.count, minDataID: minDataID, maxDataID: maxDataID,
                            originalMin: Int(minID == .max ? Int64(firstDataID) : minID), bitWidth: width, rleRuns: rleRuns, packedRuns: packedRuns)
    }

    /// The smallest supported width that holds `maximum`, and its compression class.
    static func bitWidthAndClass(for maximum: UInt64) throws -> (width: Int, compressionClass: Int) {
        let needed = max(1, maximum == 0 ? 1 : 64 - maximum.leadingZeroBitCount)
        guard let width = supportedWidths.first(where: { $0 >= needed }) else {
            throw WriteError.invalid("cột có quá nhiều giá trị khác nhau (cần \(needed) bit mỗi ô, tối đa 32), chưa lưu được")
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

    // MARK: - H$ system table (data ID order)

    /// `POS_TO_ID` and `ID_TO_POS` of one dictionary column, from Desktop's files (probe tables in `f1probe.pbix`, `pq.pbix`,
    /// 2026-11-15; see `docs/phase-f-evidence/vm-f1/QUAN-SAT.md`).
    ///
    /// With `card` dictionary entries (NULL counts) and `maxID` the largest data ID (`card + 2`, or `card + 1` with NULL), both
    /// columns are arrays of `total = maxID + 1` entries:
    /// - `POS_TO_ID[position]` = data ID of the value at that sorted position (`card` entries), then zeros.
    /// - `ID_TO_POS`: `A[0] = 0`, `A[1] = card`, `A[2]` = position of NULL (0 when absent), `A[3 + i]` = position of dictionary entry `i`.
    /// The array is cut into segments of `card` entries (`RecordsPerSegment`; the last one is shorter). Each segment is stored as
    /// `u64 n` and `n` u64 words, two u32 values per word, `n = records / 2 + 1`, zero padded; the `.idf` is the segments in order.
    /// The `.idfmeta` repeats one block per segment and a trailer with each segment's byte offset and word count.
    static func encodeHierarchy(sortedIDs: [Int64], dictionaryCount: Int, hasNulls: Bool) throws -> EncodedHierarchy {
        let card = sortedIDs.count
        guard card == dictionaryCount + (hasNulls ? 1 : 0), card > 0 else { throw WriteError.invalid("sorted IDs do not match the dictionary") }
        let maxID = dictionaryCount + 2
        guard maxID <= Int(UInt32.max) else { throw WriteError.invalid("từ điển cột quá lớn (hơn 4 tỉ mục), chưa lưu được") }
        let total = maxID + 1
        var position = [Int](repeating: 0, count: total)
        for (pos, id) in sortedIDs.enumerated() { position[Int(id)] = pos }
        var idToPosition = position
        idToPosition[0] = 0
        idToPosition[1] = card
        if !hasNulls { idToPosition[2] = 0 }
        var positionToID = sortedIDs.map(Int.init)
        positionToID += [Int](repeating: 0, count: total - card)

        let sizes = stride(from: 0, to: total, by: card).map { min(card, total - $0) }
        func file(_ values: [Int]) -> Data {
            var out = VertiPaqByteWriter()
            var start = 0
            for records in sizes {
                let words = records / 2 + 1
                out.u64(UInt64(words))
                for i in 0..<(2 * words) { out.u32(UInt32(i < records ? values[start + i] : 0)) }
                start += records
            }
            return out.data
        }
        let meta = hierarchyMeta(segmentRecords: sizes)
        return EncodedHierarchy(
            positionToID: Hierarchy.Blob(idf: file(positionToID), idfmeta: meta),
            idToPosition: Hierarchy.Blob(idf: file(idToPosition), idfmeta: meta),
            cardinality: card, recordCount: total, segmentCount: sizes.count)
    }

    /// `.idfmeta` of an `H$` column: `<1:CP` with one `<1:CS` block per segment, then `<1:SDOs` with each segment's byte offset in the `.idf`
    /// and word count. Byte for byte as Desktop writes it (316 bytes for two segments).
    static func hierarchyMeta(segmentRecords: [Int]) -> Data {
        var out = VertiPaqByteWriter()
        out.tag("<1:CP")
        out.u64(UInt64(segmentRecords.count))
        for records in segmentRecords {
            out.tag("<1:CS")
            out.u64(UInt64(records)); out.u64(0)
            out.u32(0x0ABA56)       // 32-bit packed class
            out.u32(1)
            out.u32(0)
            out.tag("<1:SS")
            out.u64(0)
            out.u32(2); out.u32(2); out.u32(2)
            out.u64(UInt64.max)
            out.bytes([UInt8](repeating: 0, count: 25))
            out.tag("SS:1>")
            out.u8(0)
            out.tag("CS:1>")
        }
        out.tag("CP:1>")
        out.tag("<1:SDOs")
        var offset = 0
        for records in segmentRecords {
            let words = records / 2 + 1
            out.tag("<1:CSDOs")
            out.u64(UInt64(offset)); out.u64(UInt64(words))
            out.tag("CSDOs:1>")
            offset += 8 + 8 * words
        }
        out.tag("SDOs:1>")
        return out.data
    }

    // MARK: - Statistics

    static func textStatistics(_ values: Values) -> (String?, String?, Int) {
        switch values {
        case .int64(let v):
            let present = v.compactMap { $0 }
            return (present.min().map(String.init), present.max().map(String.init), 0)
        case .currency(let v):
            let present = v.compactMap { $0 }
            return (present.min().map { doubleText(Double($0) / 10_000) }, present.max().map { doubleText(Double($0) / 10_000) }, 0)
        case .boolean(let v):
            let present = v.compactMap { $0 }
            return (present.contains(false) ? "FALSE" : present.isEmpty ? nil : "TRUE", present.contains(true) ? "TRUE" : present.isEmpty ? nil : "FALSE", 0)
        case .double(let v):
            let present = v.compactMap { $0 }
            return (present.min().map(doubleText), present.max().map(doubleText), 0)
        case .dateTime(let v):
            let present = v.compactMap { $0 }
            return (present.min().map(dateText), present.max().map(dateText), 0)
        case .string(let v):
            let present = v.compactMap { $0 }
            let longest = present.map { $0.utf16.count }.max() ?? 0
            // Quét một lần trên các giá trị khác nhau (sắp cả triệu dòng bằng so sánh văn hoá mất hàng chục giây).
            let distinct = Array(Set(present))
            return (distinct.min { collates($0, $1) }, distinct.max { collates($0, $1) }, longest)
        }
    }

    /// Desktop's `MinValue` text of a double: whole numbers without a fraction, otherwise up to 15 significant digits.
    static func doubleText(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.15g", value)
        if text.contains("e") { text = text.replacingOccurrences(of: "e", with: "E") }
        return text
    }

    /// Desktop's `MinValue` text of a date: `M/d/yyyy` (en-US short date), from OLE automation days.
    static func dateText(_ days: Double) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let epoch = DateComponents(calendar: calendar, year: 1899, month: 12, day: 30).date!
        let date = calendar.date(byAdding: .day, value: Int(days.rounded(.down)), to: epoch)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.month!)/\(parts.day!)/\(parts.year!)"
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

    mutating func append(_ other: VertiPaqByteWriter) { data.append(other.data) }

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
