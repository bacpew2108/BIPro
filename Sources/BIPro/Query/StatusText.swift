import Foundation

/// Định dạng trạng thái và thời gian cho thanh trạng thái DAX Query View theo quan sát Power BI (O6).
enum StatusText {
    /// Định dạng thời gian trôi qua:
    /// - dưới 1 giây: "523,1 ms" (1 chữ số thập phân)
    /// - từ 1 giây trở lên: "12,34 s" (2 chữ số thập phân)
    static func elapsed(_ nanoseconds: UInt64) -> String {
        if nanoseconds < 1_000_000_000 {
            let ms = Double(nanoseconds) / 1_000_000.0
            return String(format: "%.1f ms", ms).replacingOccurrences(of: ".", with: ",")
        } else {
            let s = Double(nanoseconds) / 1_000_000_000.0
            return String(format: "%.2f s", s).replacingOccurrences(of: ".", with: ",")
        }
    }

    /// Định dạng số nguyên có dấu chấm phân cách hàng nghìn (ví dụ "1.234").
    static func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Chuỗi tóm tắt trạng thái theo chuẩn Power BI:
    /// - Thành công: "Thành công (523,1 ms) · Truy vấn 1/1 · Kết quả 1/1 · 14 cột, 96 dòng"
    /// - Trạng thái khác: "Đang chạy…", "Đã huỷ", "Lỗi", "Chưa chạy"
    static func summary(
        status: DAXQueryRunState,
        elapsedNanoseconds: UInt64 = 0,
        queryIndex: Int = 1,
        queryCount: Int = 1,
        resultIndex: Int = 1,
        resultCount: Int = 1,
        columns: Int = 0,
        rows: Int = 0
    ) -> String {
        switch status {
        case .idle:
            return "Chưa chạy"
        case .running:
            return "Đang chạy…"
        case .cancelled:
            return "Đã huỷ"
        case .failed:
            return "Lỗi"
        case .done:
            let elapsedStr = elapsed(elapsedNanoseconds)
            let colsStr = formatNumber(columns)
            let rowsStr = formatNumber(rows)
            return "Thành công (\(elapsedStr)) · Truy vấn \(queryIndex)/\(queryCount) · Kết quả \(resultIndex)/\(resultCount) · \(colsStr) cột, \(rowsStr) dòng"
        }
    }
}
