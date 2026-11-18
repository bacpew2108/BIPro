import Foundation

/// Chỉ mục `U$` của một phân cấp người dùng (đợt tồn đọng sau Phase F, T030). Định dạng đọc từ Desktop 2.159: 4 phân cấp ngày của
/// `vm-f11/f11-desktop.pbix` và 6 phân cấp của Nhom6 (`HierarchyIndexWriterTests` dựng lại từng giá trị).
///
/// - Mỗi nút của cây là một dòng, xếp theo tầng: mọi nút cấp 0, rồi cấp 1 theo thứ tự cha, v.v. `HierarchyStorage.LevelDefinition`
///   ghi vị trí đầu mỗi tầng: `$Year (154)$0$Quarter (158)$2$Month (156)$10$Day (159)$34$`.
/// - Con của một nút xếp theo thứ tự sắp của cột cấp (`H$`), hoặc của cột "sắp theo" (`SortByColumn`) nếu có.
/// - Bốn cột, cột nào cũng nén bit 32 (lớp 703062) đúng như `R$`: `MULTI_LEVEL_ID` mã dữ liệu của giá trị cấp; `PARENT_POS`,
///   `FIRST_CHILD_POS` vị trí cộng 1 (0 = không có); `CHILD_COUNT` số con cộng 1 (0 = lá).
/// - `HierarchyStorage.StructureType` 1 khi mỗi giá trị của một cấp chỉ nằm dưới một cha (số nút bằng tổng số giá trị khác nhau
///   các cấp), còn lại 2.
public enum HierarchyIndex {
    /// Dữ liệu một cấp: mã dữ liệu từng dòng (NULL là 2, mục từ điển đầu là 3) và thứ tự sắp của các mã.
    public struct Level: Sendable, Equatable {
        public var dataIDs: [Int64]
        /// Hạng sắp của từng mã dữ liệu (nhỏ trước).
        public var rank: [Int64: Int]
        public init(dataIDs: [Int64], rank: [Int64: Int]) { self.dataIDs = dataIDs; self.rank = rank }
    }

    /// Cây đã dựng: bốn cột của `U$` (giá trị như lưu) và vị trí đầu mỗi tầng.
    public struct Nodes: Sendable, Equatable {
        public var multiLevelID: [Int64] = []
        public var parentPosition: [Int64] = []
        public var firstChildPosition: [Int64] = []
        public var childCount: [Int64] = []
        public var levelStarts: [Int] = []
        /// `HierarchyStorage.StructureType`.
        public var structureType: Int = 1
        public var count: Int { multiLevelID.count }
    }

    /// Tên bốn cột theo `StoragePosition`, kèm `ColumnStorage.Settings` Desktop ghi.
    static let columns: [(name: String, settings: Int64)] =
        [("MULTI_LEVEL_ID", 16), ("PARENT_POS", 8), ("FIRST_CHILD_POS", 9), ("CHILD_COUNT", 17)]

    // MARK: Dựng cây

    public static func build(_ levels: [Level]) throws -> Nodes {
        guard let first = levels.first else { throw WriteError.invalid("phân cấp không có cấp nào") }
        let rows = first.dataIDs.count
        guard levels.allSatisfy({ $0.dataIDs.count == rows }) else { throw WriteError.invalid("các cột cấp của phân cấp lệch số dòng") }
        var nodes = Nodes()
        var groups: [[Int]] = [Array(0..<rows)]
        var groupParent: [Int64] = [0]
        var distinctTotal = 0
        for level in levels {
            nodes.levelStarts.append(nodes.count)
            distinctTotal += Set(level.dataIDs).count
            var nextGroups: [[Int]] = [], nextParent: [Int64] = []
            for (g, members) in groups.enumerated() {
                var byID: [Int64: [Int]] = [:]
                var order: [Int64] = []
                for row in members {
                    let id = level.dataIDs[row]
                    if byID[id] == nil { order.append(id) }
                    byID[id, default: []].append(row)
                }
                order.sort { (level.rank[$0] ?? Int.max, $0) < (level.rank[$1] ?? Int.max, $1) }
                for id in order {
                    nodes.multiLevelID.append(id)
                    nodes.parentPosition.append(groupParent[g])
                    nodes.firstChildPosition.append(0)
                    nodes.childCount.append(0)
                    nextGroups.append(byID[id]!)
                    nextParent.append(Int64(nodes.count))
                }
            }
            groups = nextGroups
            groupParent = nextParent
        }
        for (i, parent) in nodes.parentPosition.enumerated() where parent > 0 {
            let p = Int(parent - 1)
            if nodes.firstChildPosition[p] == 0 { nodes.firstChildPosition[p] = Int64(i + 1) }
            nodes.childCount[p] += 1
        }
        for i in nodes.childCount.indices where nodes.childCount[i] > 0 { nodes.childCount[i] += 1 }
        guard nodes.count <= Int(UInt32.max) else { throw WriteError.invalid("phân cấp quá nhiều nút") }
        nodes.structureType = nodes.count == distinctTotal ? 1 : 2
        return nodes
    }

    /// `HierarchyStorage.LevelDefinition`: `levels` là tên lưu trữ của cột cấp (`<tên> (<ID cột>)`).
    public static func levelDefinition(_ levels: [String], starts: [Int]) -> String {
        "$" + zip(levels, starts).map { "\($0)$\($1)$" }.joined()
    }

    // MARK: Mã hoá

    /// `.idfmeta` của một cột `U$` (176 byte, chép từ Desktop); `records` (byte 20), giá trị đầu (byte 44) và số từ (byte 151) đổi theo cột.
    private static let metaTemplate: [UInt8] = hex("""
        3c313a43500001000000000000003c313a4353000400000000000000000000000000000056ba0a0001000000ffffffff3c313a5353000000000000000000\
        020000000200000002000000ffffffffffffffff0000000000000000000000000000000000000000000000000053533a313e000043533a313e0043503a313e\
        003c313a53444f73003c313a4353444f7300000000000000000003000000000000004353444f733a313e0053444f733a313e00
        """)

    private static func hex(_ text: String) -> [UInt8] {
        let chars = Array(text.filter { $0.isHexDigit })
        return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! }
    }

    /// Tệp `.idf` và `.idfmeta` của bốn cột, theo thứ tự `columns`.
    public static func encode(_ nodes: Nodes) -> [(column: String, idf: Data, meta: Data)] {
        let values = [nodes.multiLevelID, nodes.parentPosition, nodes.firstChildPosition, nodes.childCount]
        return zip(columns, values).map { column, values in
            let wordCount = values.count / 2 + 1
            var idf = Data(capacity: 8 + wordCount * 8)
            func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { idf.append(contentsOf: $0) } }
            append(UInt64(wordCount))
            for i in 0..<(wordCount * 2) { append(UInt32(i < values.count ? values[i] : 0)) }
            var meta = metaTemplate
            func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
                withUnsafeBytes(of: value.littleEndian) { for (i, b) in $0.enumerated() { meta[offset + i] = b } }
            }
            put(UInt64(values.count), at: 20)
            // Desktop ghi 0 ở cột đầu, 0xFFFFFFFF ở ba cột sau (mọi file đã xem).
            put(column.name == "MULTI_LEVEL_ID" ? UInt32(0) : UInt32.max, at: 44)
            put(UInt64(wordCount), at: 151)
            return (column.name, idf, Data(meta))
        }
    }

    // MARK: Dữ liệu cấp

    /// Cấp từ giá trị trong bộ nhớ (bảng BI Pro sắp ghi): mã dữ liệu và thứ tự sắp như `VertiPaqWriter` (từ điển theo thứ tự xuất hiện,
    /// `H$` theo giá trị). `sortBy` là giá trị cột "sắp theo" cùng số dòng, nếu có.
    public static func level(_ values: VertiPaqWriter.Values, sortBy: VertiPaqWriter.Values? = nil) throws -> Level {
        let own = try VertiPaqWriter.encodeDictionary(values)
        let ownRank = Dictionary(uniqueKeysWithValues: own.sortedIDs.enumerated().map { ($1, $0) })
        guard let sortBy else { return Level(dataIDs: own.ids, rank: ownRank) }
        guard sortBy.count == values.count else { throw WriteError.invalid("cột sắp theo lệch số dòng") }
        let other = try VertiPaqWriter.encodeDictionary(sortBy)
        let otherRank = Dictionary(uniqueKeysWithValues: other.sortedIDs.enumerated().map { ($1, $0) })
        return Level(dataIDs: own.ids, rank: sortedRank(own.ids, own: ownRank, by: other.ids, rank: otherRank))
    }

    /// Cấp từ cột đã có trong ABF: mã dữ liệu đọc từ `.idf`, thứ tự sắp từ `POS_TO_ID` của `H$` (cột không có `H$` thì theo mã).
    public static func level(_ column: ModelMetadata.ColumnStorage, columnID: Int, sortBy: (column: ModelMetadata.ColumnStorage, id: Int)?,
                             abf: ABFBackup) throws -> Level {
        let ids = try dataIDs(column, abf: abf)
        let ownRank = try positions(columnID: columnID, abf: abf) ?? Dictionary(uniqueKeysWithValues: Set(ids).sorted().enumerated().map { ($1, $0) })
        guard let sortBy else { return Level(dataIDs: ids, rank: ownRank) }
        let otherIDs = try dataIDs(sortBy.column, abf: abf)
        guard otherIDs.count == ids.count else { throw WriteError.invalid("cột sắp theo lệch số dòng") }
        let otherRank = try positions(columnID: sortBy.id, abf: abf)
            ?? Dictionary(uniqueKeysWithValues: Set(otherIDs).sorted().enumerated().map { ($1, $0) })
        return Level(dataIDs: ids, rank: sortedRank(ids, own: ownRank, by: otherIDs, rank: otherRank))
    }

    /// Hạng theo cột sắp: mỗi mã lấy hạng của giá trị sắp ở dòng đầu tiên mang mã đó; trùng thì theo hạng riêng.
    private static func sortedRank(_ ids: [Int64], own: [Int64: Int], by other: [Int64], rank otherRank: [Int64: Int]) -> [Int64: Int] {
        var key: [Int64: (Int, Int)] = [:]
        for (row, id) in ids.enumerated() where key[id] == nil {
            key[id] = (otherRank[other[row]] ?? Int.max, own[id] ?? Int.max)
        }
        let ordered = key.keys.sorted { key[$0]! < key[$1]! }
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
    }

    /// Mã dữ liệu từng dòng của một cột trong ABF (mọi phân vùng, theo thứ tự lưu).
    static func dataIDs(_ column: ModelMetadata.ColumnStorage, abf: ABFBackup) throws -> [Int64] {
        var out: [Int64] = []
        for idf in column.idfFiles {
            let metas = try VertiPaq.parseIDFMeta(try abf.contents(named: idf + "meta"), file: idf + "meta")
            let parts = try VertiPaq.parseIDF(try abf.contents(named: idf), file: idf)
            for (i, meta) in metas.enumerated() {
                guard i < parts.count else { out += Array(repeating: VertiPaq.nullDataID, count: meta.records); continue }
                out += VertiPaq.decodeSegment(parts[i], meta: meta)
            }
        }
        return out
    }

    /// Hạng của từng mã theo `POS_TO_ID` của `H$` cột `columnID` (đoạn đầu dài đúng bằng số mã); `nil` khi không có `H$`.
    static func positions(columnID: Int, abf: ABFBackup) throws -> [Int64: Int]? {
        let suffix = " (\(columnID)).POS_TO_ID.0.idf"
        guard let file = abf.files.first(where: { $0.fileName.hasSuffix(suffix) && $0.fileName.contains(".H$") }) else { return nil }
        let data = abf.contents(of: file)
        guard data.count >= 8 else { return nil }
        let records = try VertiPaq.parseIDFMeta(try abf.contents(named: file.fileName + "meta"), file: file.fileName + "meta").first?.records ?? 0
        return data.withUnsafeBytes { raw -> [Int64: Int] in
            let words = Int(raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self))
            let n = min(records, words * 2, (data.count - 8) / 4)
            var rank: [Int64: Int] = [:]
            for i in 0..<n { rank[Int64(raw.loadUnaligned(fromByteOffset: 8 + i * 4, as: UInt32.self))] = i }
            return rank
        }
    }
}
