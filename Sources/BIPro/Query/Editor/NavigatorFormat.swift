import Foundation
import ColumnStore
import Connectors

enum NavigatorFormat {
    static func rowCount(_ n: Int?) -> String {
        guard let n else { return "" }
        if n < 10_000 {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
        } else if n < 1_000_000 {
            let val = Double(n) / 1000.0
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 0
            let s = formatter.string(from: NSNumber(value: val)) ?? String(format: "%.1f", val)
            return "\(s)k"
        } else {
            let val = Double(n) / 1_000_000.0
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 0
            let s = formatter.string(from: NSNumber(value: val)) ?? String(format: "%.1f", val)
            return "\(s)M"
        }
    }

    /// Ô của cột có kiểu Power Query riêng (VM-F15, như Desktop hiện): Time "08:30:00", Duration "1.02:03:04" / "-02:30:00" /
    /// "0.00:00:00.5000000", Binary "Binary". `nil` khi hiện như thường.
    static func sourceCell(_ value: StoredValue, _ source: MSourceType?) -> String? {
        switch (source, value) {
        case (.binary, .string): return "Binary"
        case (.time, .dateTime(let d)):
            let total = (d - d.rounded(.down)) * 86_400
            let whole = Int(total.rounded(.down))
            let fraction = total - Double(whole)
            let base = String(format: "%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
            guard fraction > 5e-8 else { return base }
            var digits = String(format: "%07d", Int((fraction * 1e7).rounded()))
            while digits.hasSuffix("0") { digits.removeLast() }
            return base + "." + digits
        case (.duration, .double(let days)):
            let negative = days < 0
            let ticks = Int64((abs(days) * 86_400 * 1e7).rounded())
            let wholeDays = ticks / (86_400 * 10_000_000)
            var rest = ticks % (86_400 * 10_000_000)
            let h = rest / 36_000_000_000; rest %= 36_000_000_000
            let m = rest / 600_000_000; rest %= 600_000_000
            let sec = rest / 10_000_000, frac = rest % 10_000_000
            var text = String(format: "%02lld:%02lld:%02lld", h, m, sec)
            if wholeDays > 0 { text = "\(wholeDays)." + text }
            if frac > 0 {
                text += String(format: ".%07lld", frac)
                if wholeDays == 0 { text = "0." + text }   // Desktop: "0.00:00:00.5000000"
            }
            return (negative ? "-" : "") + text
        default: return nil
        }
    }

    static func cell(_ value: StoredValue) -> String {
        switch value {
        case .blank:
            return "null"
        case .integer(let v):
            return "\(v)"
        case .double(let v):
            guard v.isFinite else {
                return v.isNaN ? "NaN" : (v > 0 ? "Infinity" : "-Infinity")
            }
            let text = "\(v)"
            guard text.firstIndex(where: { $0 == "e" || $0 == "E" }) == nil else {
                return text
            }
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        case .currency(let raw):
            let val = Double(raw) / 10_000.0
            return String(format: "%.2f", val)
        case .string(let s):
            return s.replacingOccurrences(of: "\r\n", with: "↵")
                    .replacingOccurrences(of: "\n", with: "↵")
                    .replacingOccurrences(of: "\r", with: "↵")
        case .boolean(let b):
            return b ? "TRUE" : "FALSE"
        case .dateTime(let d):
            let seconds = (d - 25_569) * 86_400
            let roundedSeconds = (seconds * 1000).rounded() / 1000
            let date = Date(timeIntervalSince1970: roundedSeconds)
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            if abs(d.truncatingRemainder(dividingBy: 1)) < 1e-6 {
                df.dateFormat = "yyyy-MM-dd"
            } else {
                df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            }
            return df.string(from: date)
        }
    }

    static func kindBadge(_ kind: SourceItemKind) -> String {
        switch kind {
        case .sheet: return "Trang tính"
        case .namedTable: return "Bảng đặt tên"
        case .table: return "Bảng"
        case .view: return "Khung nhìn"
        case .file: return "Tệp"
        case .record: return "Bản ghi"
        case .query: return "Truy vấn SQL"
        }
    }

    static func selectedSummary(checked: Int, total: Int) -> String {
        "Đã chọn \(checked) / \(total) mục"
    }

    static func truncationNote(previewRows: Int, rowCountHint: Int?) -> String? {
        if previewRows == 200 && (rowCountHint == nil || rowCountHint! > 200) {
            return "Xem trước bị cắt ở 200 dòng đầu."
        }
        return nil
    }
}
