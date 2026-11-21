import Foundation

/// Phím định dạng nhanh (`$`, `%`, `,`, `.00`) trên thanh Ribbon `Công cụ cột` (Column Tools).
enum ColumnFormatShortcut {
    /// Đặt định dạng tiền tệ (`\$#,0.00`), giữ độ chính xác thập phân nếu định dạng hiện tại đã đặt.
    static func currency(current: String?) -> String {
        guard let cur = current?.trimmingCharacters(in: .whitespacesAndNewlines), !cur.isEmpty else {
            return "\\$#,0.00"
        }
        if cur.contains("$") {
            return cur
        }
        if let dotIdx = cur.firstIndex(of: ".") {
            let afterDot = cur[cur.index(after: dotIdx)...].prefix { $0 == "0" || $0 == "#" }
            if !afterDot.isEmpty {
                return "\\$#,0.\(afterDot)"
            }
        }
        return "\\$#,0.00"
    }

    /// Đặt định dạng phần trăm (`0.00%`), giữ độ chính xác thập phân nếu đã có.
    static func percent(current: String?) -> String {
        guard let cur = current?.trimmingCharacters(in: .whitespacesAndNewlines), !cur.isEmpty else {
            return "0.00%"
        }
        if cur.hasSuffix("%") {
            return cur
        }
        if let dotIdx = cur.firstIndex(of: ".") {
            let afterDot = cur[cur.index(after: dotIdx)...].prefix { $0 == "0" || $0 == "#" }
            if !afterDot.isEmpty {
                return "0.\(afterDot)%"
            }
        }
        return "0.00%"
    }

    /// Bật / tắt dấu phân tách hàng nghìn (`#,`).
    static func toggleThousandsSeparator(current: String?) -> String {
        guard let cur = current?.trimmingCharacters(in: .whitespacesAndNewlines), !cur.isEmpty else {
            return "#,0"
        }
        if cur.contains("#,") {
            return cur.replacingOccurrences(of: "#,", with: "")
        }
        if cur.hasPrefix("\\$") {
            return "\\$#," + cur.dropFirst(2)
        }
        if cur.hasPrefix("$") {
            return "$#," + cur.dropFirst(1)
        }
        if cur.hasPrefix("0") {
            return "#," + cur
        }
        return "#,0"
    }

    /// Bật / tắt 2 chữ số thập phân (`.00`), bảo toàn tiền tố tiền tệ / hậu tố `%` / dấu phân tách hàng nghìn.
    static func toggleTwoDecimals(current: String?) -> String {
        guard let cur = current?.trimmingCharacters(in: .whitespacesAndNewlines), !cur.isEmpty else {
            return "#,0.00"
        }
        let isPct = cur.hasSuffix("%")
        let core = isPct ? String(cur.dropLast()) : cur
        if let dotIdx = core.firstIndex(of: ".") {
            let before = core[..<dotIdx]
            let rest = core[core.index(after: dotIdx)...]
            let digits = rest.prefix { $0 == "0" || $0 == "#" }
            let suffix = rest.dropFirst(digits.count)
            if digits.count == 2 {
                return String(before) + String(suffix) + (isPct ? "%" : "")
            } else {
                return String(before) + ".00" + String(suffix) + (isPct ? "%" : "")
            }
        }
        if core.contains("0") || core.contains("#") {
            return core + ".00" + (isPct ? "%" : "")
        }
        return "#,0.00"
    }
}
