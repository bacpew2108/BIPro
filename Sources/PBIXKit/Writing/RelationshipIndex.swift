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
        let many = try VertiPaq.decodeColumn(from, abf: abf)
        guard case .dictionary(_, let dictionary) = many.storage else {
            throw WriteError.invalid("cột \(from.tableName)[\(from.columnName)] không mã hoá bằng từ điển, chưa tạo được chỉ mục quan hệ")
        }
        let one = try VertiPaq.decodeColumn(to, abf: abf)
        var row: [CellValue: Int] = [:]
        row.reserveCapacity(one.count)
        for r in 0..<one.count {
            let value = one[r]
            if case .null = value { continue }
            guard row.updateValue(r + 1, forKey: value) == nil else {
                throw WriteError.invalid("cột \(to.tableName)[\(to.columnName)] có giá trị trùng (\(value)), không làm phía một của quan hệ được")
            }
        }
        return Array(repeating: 0, count: reservedIDs) + dictionary.map { row[$0] ?? 0 }
    }

    /// Tệp `.idf` và `.idfmeta` cho `values`; `toRowCount` là số dòng bảng phía một (quyết định độ rộng bit như Desktop).
    public static func encode(values: [Int], toRowCount: Int) throws -> (idf: Data, meta: Data) {
        let needed = max(1, Int.bitWidth - toRowCount.leadingZeroBitCount)
        guard let choice = widths.first(where: { $0.bits >= needed }) else {
            throw WriteError.invalid("bảng phía một có \(toRowCount) dòng, quá lớn cho chỉ mục")
        }
        guard values.allSatisfy({ $0 >= 0 && $0 <= toRowCount }) else { throw WriteError.invalid("giá trị chỉ mục ngoài miền") }
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
