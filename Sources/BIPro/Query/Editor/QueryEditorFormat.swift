import Foundation
import ColumnStore

public enum QueryEditorFormat {
    /// "93%": làm tròn gần nhất; total == 0 → "0%"
    public static func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "0%" }
        let p = (Double(part) / Double(total) * 100.0).rounded()
        return "\(Int(p))%"
    }

    /// rows ≤ 999: "9 cột · 500 dòng"; rows ≥ 1000: "9 cột · 999+ dòng"
    public static func statusSummary(columns: Int, rows: Int) -> String {
        if rows <= 999 {
            return "\(columns) cột · \(rows) dòng"
        } else {
            return "\(columns) cột · 999+ dòng"
        }
    }

    /// "Dựa trên 1000 dòng đầu" (rowsProfiled là số dòng của preview; < 1000 thì "Dựa trên 500 dòng")
    public static func profileCaption(rowsProfiled: Int) -> String {
        if rowsProfiled >= 1000 {
            return "Dựa trên 1000 dòng đầu"
        } else {
            return "Dựa trên \(rowsProfiled) dòng"
        }
    }

    /// integer, double, currency → "123"; string → "ABC"; dateTime → "Ngày"; boolean → "T/F"
    public static func typeBadge(_ type: DAXType) -> String {
        switch type {
        case .integer, .double, .currency:
            return "123"
        case .string:
            return "ABC"
        case .dateTime:
            return "Ngày"
        case .boolean:
            return "T/F"
        }
    }

    /// valid + error + empty
    public static func countLine(_ profile: ColumnProfile) -> Int {
        profile.valid + profile.error + profile.empty
    }
}
