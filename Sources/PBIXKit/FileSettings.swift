import Foundation

/// Part `Settings` của `.pbix` (JSON UTF-16LE): tuỳ chọn của file ở Options ▸ Current File ▸ Data Load (T033).
///
/// "Autodetect new relationships after data is loaded" là `ReportSettings.IsRelationshipAutodetectionEnabled` (gate VM-F11, T037):
/// Desktop tắt thì ghi `"ReportSettings":{"IsRelationshipAutodetectionEnabled":false}`, bật lại thì xoá khoá (về `{}`); thiếu khoá
/// là bật. (`QueriesSettings.RunBackgroundAnalysis` là ô "Allow data previews to download in the background", không đụng tới.)
/// Sửa ở mức văn bản để giữ nguyên thứ tự khoá và phần còn lại từng byte.
public enum FileSettings {
    public static let path = "Settings"
    static let autodetectKey = "\"IsRelationshipAutodetectionEnabled\":"

    public static func decode(_ data: Data) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(data.count / 2)
        var index = data.startIndex
        while index + 1 < data.endIndex {
            units.append(UInt16(data[index]) | UInt16(data[index + 1]) << 8)
            index += 2
        }
        var text = String(decoding: units, as: UTF16.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// Tuỳ chọn tự phát hiện quan hệ của file; thiếu khoá thì bật (mặc định của Desktop).
    public static func autodetectRelationships(in settings: Data) -> Bool {
        let text = decode(settings)
        guard let range = text.range(of: autodetectKey) else { return true }
        return !text[range.upperBound...].hasPrefix("false")
    }

    /// `settings` với tuỳ chọn tự phát hiện quan hệ đặt thành `enabled`: tắt thì chèn khoá `false` ở đầu `ReportSettings`
    /// (khi đối tượng còn khoá khác thì vị trí là `[SUY ĐOÁN]`), bật thì xoá khoá cùng dấu phẩy đi kèm.
    public static func setting(autodetectRelationships enabled: Bool, in settings: Data) throws -> Data {
        var text = decode(settings)
        if let range = text.range(of: autodetectKey) {
            let rest = text[range.upperBound...]
            let old = rest.hasPrefix("true") ? "true" : rest.hasPrefix("false") ? "false" : nil
            guard let old else { throw WriteError.invalid(lt("Settings: giá trị IsRelationshipAutodetectionEnabled không phải true/false", "Settings: the value of IsRelationshipAutodetectionEnabled isn't true/false")) }
            let end = text.index(range.upperBound, offsetBy: old.count)
            if enabled {
                var lower = range.lowerBound, upper = end
                if upper < text.endIndex, text[upper] == "," { upper = text.index(after: upper) }
                else if lower > text.startIndex, text[text.index(before: lower)] == "," { lower = text.index(before: lower) }
                text.removeSubrange(lower..<upper)
            } else {
                text.replaceSubrange(range.upperBound..<end, with: "false")
            }
        } else if !enabled {
            guard let report = text.range(of: "\"ReportSettings\":{") else {
                throw WriteError.invalid(lt("Settings không có ReportSettings", "Settings has no ReportSettings"))
            }
            let empty = report.upperBound < text.endIndex && text[report.upperBound] == "}"
            text.insert(contentsOf: autodetectKey + "false" + (empty ? "" : ","), at: report.upperBound)
        }
        return NewDocument.utf16LE(text)
    }
}
