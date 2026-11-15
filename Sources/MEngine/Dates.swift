// Phase F (T049): ngày theo số ngày kể từ 1899-12-30 (cùng quy ước với `StoredValue.dateTime` và Excel).

enum MDates {
    /// Số ngày kể từ 1899-12-30; `nil` nếu ngày không tồn tại.
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
}
