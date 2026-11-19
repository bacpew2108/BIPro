// Đợt tồn đọng sau Phase F, T022: chuỗi khi vào kho VertiPaq của Desktop (VM-F12, `docs/phase-f2-evidence/vm-f12/QUAN-SAT.md` mục đầu):
// - khoảng trắng cuối bị bỏ, khoảng trắng đầu giữ ("  khoảng trắng   giữa  " → "  khoảng trắng   giữa", " 12 " → " 12");
// - chuỗi chỉ khác hoa thường của chữ ASCII là một giá trị, giữ cách viết gặp trước ("abc" ở dòng 7 thì "ABC" ở dòng 8 thành
//   "abc"); chữ có dấu khác hoa thường thì vẫn hai giá trị (`MID` ra "à N" ở dòng 1 và "À N" ở dòng 3 của cùng cột);
// - không chuẩn hoá Unicode: "ộ" NFC và NFD là hai giá trị (so theo đơn vị UTF-16, không theo `String ==` của Swift).
// Áp cho mọi cột chữ vào mô hình: bảng nạp (Get Data, Enter Data, Close & Apply) và cột/bảng tính toán.
// [SUY ĐOÁN] chỉ bỏ U+0020 ở cuối (chưa thử tab, NBSP); chỉ gộp hoa thường A–Z (chưa thử chữ ngoài Latin-1, như Ω/ω).

public enum ModelText {
    /// Các giá trị như kho lưu (BLANK giữ BLANK).
    public static func normalize(_ values: [String?]) -> [String?] {
        var first: [[UInt16]: String] = [:]
        var out: [String?] = []
        out.reserveCapacity(values.count)
        for value in values {
            guard var text = value else { out.append(nil); continue }
            if text.hasSuffix(" ") {
                var scalars = Substring(text).unicodeScalars
                while scalars.last == " " { scalars.removeLast() }
                text = String(scalars)
            }
            let key = text.utf16.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
            if let kept = first[key] { out.append(kept) } else { first[key] = text; out.append(text) }
        }
        return out
    }

    /// Cột chữ đã chuẩn hoá; cột kiểu khác trả nguyên.
    public static func normalize(_ data: ColumnData) -> ColumnData {
        guard data.type == .string else { return data }
        let values: [String?] = (0..<data.rowCount).map { row in
            if case .string(let s) = data.value(at: row) { return s }
            return nil
        }
        let normalized = normalize(values)
        guard zip(values, normalized).contains(where: { !same($0, $1) }) else { return data }
        return ColumnBuilder.strings(normalized)
    }

    /// Bảng với mọi cột chữ đã chuẩn hoá (giữ lỗi ô, bảng lồng, giá trị có cấu trúc).
    public static func normalize(_ table: TableData) -> TableData {
        let columns = table.columns.map { TableColumn(name: $0.name, data: normalize($0.data)) }
        return (try? TableData(columns: columns, errorMask: table.errorMask, nested: table.nested, structured: table.structured)) ?? table
    }

    private static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): x.utf16.elementsEqual(y.utf16)
        default: false
        }
    }
}
