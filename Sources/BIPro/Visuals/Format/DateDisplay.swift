// Hiển thị ngày theo mẫu định dạng của cột (`MMM yyyy`, `dd/MM/yyyy`, `yyyy-MM`…), en-US.
//
// Engine (`FormatString`) mới hỗ trợ mẫu số và "General/Short Date"; mẫu ngày tuỳ biến thuộc lớp hiển thị của visual nên đặt ở đây.
// Mẫu hỗ trợ: yyyy yy, MMMM MMM MM M, dddd ddd dd d, chữ trong "…" hoặc sau \, ký tự khác giữ nguyên. Mẫu có giờ/phút/giây
// chưa hỗ trợ (trả nil để người gọi dùng cách cũ).
import Foundation

enum DateDisplay {
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// (năm, tháng, ngày) của số serial OLE (ngày 0 là 30/12/1899).
    static func civil(serial: Double) -> (year: Int, month: Int, day: Int) {
        let z = Int(serial.rounded(.down)) - 25_569 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// Số serial OLE của ngày (năm, tháng, ngày); tháng ngoài 1…12 được quy về năm kế bên.
    static func serial(year: Int, month: Int, day: Int) -> Double {
        let y0 = year + (month - 1) / 12 - (month < 1 ? 1 : 0)
        let m0 = ((month - 1) % 12 + 12) % 12 + 1
        let y = m0 <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m0 > 2 ? m0 - 3 : m0 + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return Double(era * 146_097 + doe - 719_468 + 25_569)
    }

    /// Mẫu có chứa ký tự ngày (y, M, d) ngoài dấu nháy.
    static func isDatePattern(_ pattern: String) -> Bool {
        var quoted = false, escaped = false
        for ch in pattern {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { quoted.toggle(); continue }
            if !quoted, "yMd".contains(ch) { return true }
        }
        return false
    }

    /// nil nếu mẫu có giờ/phút/giây hoặc không đọc được.
    static func format(serial: Double, pattern: String) -> String? {
        let (year, month, day) = civil(serial: serial)
        let weekday = ((Int(serial.rounded(.down)) % 7) + 7 + 6) % 7
        let chars = Array(pattern)
        var out = "", i = 0
        func run(_ c: Character) -> Int { var n = 0; while i + n < chars.count, chars[i + n] == c { n += 1 }; return n }
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "\"":
                i += 1
                while i < chars.count, chars[i] != "\"" { out.append(chars[i]); i += 1 }
                i += 1
            case "\\":
                if i + 1 < chars.count { out.append(chars[i + 1]) }
                i += 2
            case "y":
                let n = run("y")
                out += n <= 2 ? String(format: "%02d", year % 100) : String(format: "%04d", year)
                i += n
            case "M":
                let n = run("M")
                switch n {
                case 1: out += String(month)
                case 2: out += String(format: "%02d", month)
                case 3: out += String(months[month - 1].prefix(3))
                default: out += months[month - 1]
                }
                i += n
            case "d":
                let n = run("d")
                switch n {
                case 1: out += String(day)
                case 2: out += String(format: "%02d", day)
                case 3: out += String(days[weekday].prefix(3))
                default: out += days[weekday]
                }
                i += n
            case "h", "H", "m", "s", "A", "a":
                return nil
            default:
                out.append(c)
                i += 1
            }
        }
        return out
    }
}
