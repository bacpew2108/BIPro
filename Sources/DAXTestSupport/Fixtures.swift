// Đường dẫn fixture dùng chung cho test (lead, đợt 0). Chỉ đọc, không ghi.
// Các file .pbix của người dùng nằm trong ~/Downloads, nên test phải bỏ qua khi file vắng mặt.
import Foundation

public enum DAXFixtures {
    public static let downloads = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads")
    public static let nhom6 = downloads.appendingPathComponent("Nhom6_Dashboard.pbix")

    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
