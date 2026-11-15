import Foundation

enum DateHelper {
    /// Số ngày kể từ 1899-12-30 (ngày 0 là 1899-12-30).
    static func serial(year: Int, month: Int, day: Int) -> Double? {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month) else { return nil }
        // Thuật toán days_from_civil (Howard Hinnant), tính từ 1970-01-01, rồi đổi sang gốc 1899-12-30 (25569 ngày).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let sinceUnixEpoch = era * 146_097 + doe - 719_468
        return Double(sinceUnixEpoch + 25_569)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// [SUY ĐOÁN] Đọc chuỗi ngày `yyyy-MM-dd` hoặc ngày giờ `yyyy-MM-dd HH:mm:ss` / `yyyy-MM-dd'T'HH:mm:ss`
    /// (chấp nhận cả phần thập phân giây và hậu tố 'Z' nếu có từ SQLite/ISO 8601).
    static func parseDateTime(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 10 else { return nil }
        let chars = Array(trimmed)

        // yyyy-MM-dd
        guard chars[4] == "-", chars[7] == "-" else { return nil }
        guard let year = Int(String(chars[0..<4])),
              let month = Int(String(chars[5..<7])),
              let day = Int(String(chars[8..<10])) else { return nil }

        guard let daySerial = serial(year: year, month: month, day: day) else { return nil }

        if chars.count == 10 {
            return daySerial
        }

        // Must have separator ' ' or 'T'
        guard chars[10] == " " || chars[10] == "T" else { return nil }
        guard chars.count >= 19, chars[13] == ":", chars[16] == ":" else { return nil }

        guard let hour = Int(String(chars[11..<13])),
              let minute = Int(String(chars[14..<16])),
              let second = Int(String(chars[17..<19])) else { return nil }

        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }

        var totalSeconds = Double(hour * 3600 + minute * 60 + second)

        // Check for fractional seconds
        if chars.count > 19 {
            var rest = String(chars[19...])
            if rest.hasSuffix("Z") {
                rest.removeLast()
            }
            if rest.hasPrefix(".") {
                rest.removeFirst()
                if let frac = Double("0." + rest) {
                    totalSeconds += frac
                }
            } else if !rest.isEmpty {
                return nil
            }
        }

        return daySerial + (totalSeconds / 86400.0)
    }
}
