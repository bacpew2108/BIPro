import Foundation

/// Chỉ mục dữ liệu của một quan hệ (Phase E, spike S1, `docs/phase-e-evidence/vm-e3/QUAN-SAT.md`). Mỗi quan hệ nhiều-một có một
/// bảng hệ thống ẩn `R$…` với một cột `INDEX`: với mỗi mã dữ liệu của cột phía nhiều (ba mã đầu dành riêng, rồi từng mục
/// từ điển theo thứ tự), giá trị là số thứ tự dòng (đếm từ 1) của dòng phía một có cùng khoá, hoặc 0 nếu không có.
/// Cột được nén bit theo độ rộng cố định (không tràn sang từ kế); định dạng đối chiếu từng byte với 14 quan hệ của Nhom6.
public enum RelationshipIndex {
    /// Số mã dữ liệu dành riêng ở đầu cột (giá trị 0).
    static let reservedIDs = 3

    /// Các lớp nén được dùng: `(độ rộng bit, lớp nén ghi trong .idfmeta)`.
    static let widths: [(bits: Int, compressionClass: UInt32)] =
        (1...10).map { ($0, UInt32(703_030 + $0)) } + [(12, 703_042), (16, 703_046), (21, 703_051), (32, 703_062)]

    /// `.idfmeta` mẫu (176 byte) của một chỉ mục 4 mục, lớp 703046; chỉ `records` (byte 20), lớp nén (byte 36) và số từ của .idf (byte 151) đổi theo chỉ mục.
    private static let metaTemplate: [UInt8] = hex("""
        3c313a43500001000000000000003c313a4353000400000000000000000000000000000046ba0a0001000000ffffffff3c313a5353000000000000000000\
        020000000200000002000000ffffffffffffffff0000000000000000000000000000000000000000000000000053533a313e000043533a313e0043503a313e\
        003c313a53444f73003c313a4353444f7300000000000000000002000000000000004353444f733a313e0053444f733a313e00
        """)

    private static func hex(_ text: String) -> [UInt8] {
        let chars = Array(text.filter { $0.isHexDigit })
        return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! }
    }

    /// Các giá trị của cột `INDEX`: ba số 0 rồi, với mỗi mục từ điển của cột phía nhiều, số thứ tự dòng (từ 1) trong cột phía một.
    /// Ném `WriteError.invalid` khi cột phía nhiều không mã hoá bằng từ điển (chưa hỗ trợ), hoặc cột phía một có giá trị trùng.
    public static func values(from: ModelMetadata.ColumnStorage, to: ModelMetadata.ColumnStorage, abf: ABFBackup) throws -> [Int] {
        let one = try VertiPaq.decodeColumn(to, abf: abf)
        return try values(from: from, abf: abf, oneCells: (0..<one.count).map { one[$0] }, oneName: "\(to.tableName)[\(to.columnName)]")
    }

    /// Chỉ mục khi cột phía nhiều nằm trong ABF và phía một là các ô `one` (theo thứ tự dòng): cột từ điển theo mục từ điển; cột mã hoá theo
    /// giá trị (T066, `w8.3.pbix` một–một trên `ID nhân viên`) theo mã dữ liệu = giá trị × magnitude − baseID, mỗi mã từ 0 tới mã lớn nhất
    /// một mục (ba mã đầu dành riêng).
    public static func values(from: ModelMetadata.ColumnStorage, abf: ABFBackup, oneCells one: [CellValue], oneName: String) throws -> [Int] {
        let many = try VertiPaq.decodeColumn(from, abf: abf)
        switch many.storage {
        case .dictionary(_, let dictionary):
            return try values(manyDictionary: dictionary, oneCells: one, oneName: oneName)
        case .values(let numbers):
            var byValue: [Double: Int] = [:]
            for (r, cell) in one.enumerated() {
                let value: Double?
                switch cell {
                case .int(let i): value = Double(i)
                case .double(let d), .decimal(let d), .dateTime(let d): value = d
                default: value = nil
                }
                guard let value else { continue }
                guard byValue.updateValue(r + 1, forKey: value) == nil else {
                    throw WriteError.invalid(lt("cột \(oneName) có giá trị trùng (\(value)), không làm phía một của quan hệ được", "column \(oneName) has a duplicate value (\(value)) and can't be the one side of a relationship"))
                }
            }
            let magnitude = from.magnitude == 0 ? 1 : from.magnitude
            let ids = numbers.filter { !$0.isNaN }.map { Int(($0 * magnitude).rounded()) - from.baseID }
            let top = max(reservedIDs - 1, ids.max() ?? 0)
            return (0...top).map { id in id < reservedIDs ? 0 : byValue[Double(id + from.baseID) / magnitude] ?? 0 }
        case .empty:
            throw WriteError.invalid(lt("cột \(from.tableName)[\(from.columnName)] không có dữ liệu, chưa tạo được chỉ mục quan hệ", "column \(from.tableName)[\(from.columnName)] has no data, so a relationship index can't be created yet"))
        }
    }

    /// Mục từ điển của một cột trong bộ nhớ (bảng mới chưa vào ABF): giá trị khác nhau theo thứ tự xuất hiện, như bộ ghi VertiPaq.
    public static func dictionary(ofCells cells: [CellValue]) -> [CellValue] {
        var seen = Set<CellValue>()
        var out: [CellValue] = []
        for value in cells {
            if case .null = value { continue }
            if seen.insert(value).inserted { out.append(value) }
        }
        return out
    }

    /// Như `values(from:to:abf:)` nhưng khi một hoặc hai phía là cột trong bộ nhớ: `manyDictionary` là các mục từ điển của cột phía nhiều
    /// (theo thứ tự mã dữ liệu), `one` là các ô của cột phía một theo thứ tự dòng.
    public static func values(manyDictionary: [CellValue], oneCells one: [CellValue], oneName: String) throws -> [Int] {
        var row: [CellValue: Int] = [:]
        row.reserveCapacity(one.count)
        for (r, value) in one.enumerated() {
            if case .null = value { continue }
            guard row.updateValue(r + 1, forKey: value) == nil else {
                throw WriteError.invalid(lt("cột \(oneName) có giá trị trùng (\(value)), không làm phía một của quan hệ được", "column \(oneName) has a duplicate value (\(value)) and can't be the one side of a relationship"))
            }
        }
        return Array(repeating: 0, count: reservedIDs) + manyDictionary.map { row[$0] ?? 0 }
    }

    /// Tệp `.idf` và `.idfmeta` cho `values`; `toRowCount` là số dòng bảng phía một (quyết định độ rộng bit như Desktop).
    public static func encode(values: [Int], toRowCount: Int) throws -> (idf: Data, meta: Data) {
        let needed = max(1, Int.bitWidth - toRowCount.leadingZeroBitCount)
        guard let choice = widths.first(where: { $0.bits >= needed }) else {
            throw WriteError.invalid(lt("bảng phía một có \(toRowCount) dòng, quá lớn cho chỉ mục", "the one-side table has \(toRowCount) rows, too large for the index"))
        }
        guard values.allSatisfy({ $0 >= 0 && $0 <= toRowCount }) else { throw WriteError.invalid(lt("giá trị chỉ mục ngoài miền", "index value out of range")) }
        let perWord = 64 / choice.bits
        let wordCount = values.count / perWord + 1
        var words = [UInt64](repeating: 0, count: wordCount)
        for (i, value) in values.enumerated() {
            words[i / perWord] |= UInt64(value) << UInt64((i % perWord) * choice.bits)
        }
        var idf = Data()
        withUnsafeBytes(of: UInt64(wordCount).littleEndian) { idf.append(contentsOf: $0) }
        for word in words { withUnsafeBytes(of: word.littleEndian) { idf.append(contentsOf: $0) } }

        var meta = metaTemplate
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { for (i, b) in $0.enumerated() { meta[offset + i] = b } }
        }
        put(UInt64(values.count), at: 20)
        put(choice.compressionClass, at: 36)
        put(UInt64(wordCount), at: 151)   // kích thước dữ liệu tính bằng từ 64 bit (khối SDOs)
        return (idf, Data(meta))
    }
}
