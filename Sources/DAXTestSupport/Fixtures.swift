// Đường dẫn fixture dùng chung cho test (lead, đợt 0). Chỉ đọc, không ghi.
// Các file .pbix của người dùng nằm trong ~/Downloads, nên test phải bỏ qua khi file vắng mặt.
import Foundation

public enum DAXFixtures {
    public static let downloads = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads")
    /// File Nhom6: biến môi trường `BIPRO_NHOM6` nếu có; không thì `~/Downloads/Nhom6_Dashboard.pbix`; nếu thiếu thì
    /// `~/Downloads/bipro-golden/Nhom6_work.pbix` (cùng dữ liệu và cùng bố cục báo cáo với bản gốc: test sinh truy
    /// vấn và golden đều qua, kiểm 2026-11-09). Chỉ đọc.
    public static let nhom6: URL = {
        if let path = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let primary = downloads.appendingPathComponent("Nhom6_Dashboard.pbix")
        if FileManager.default.fileExists(atPath: primary.path) { return primary }
        let work = downloads.appendingPathComponent("bipro-golden/Nhom6_work.pbix")
        return FileManager.default.fileExists(atPath: work.path) ? work : primary
    }()

    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
