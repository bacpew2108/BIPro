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
