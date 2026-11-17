// Fixture cho test đợt tồn đọng sau Phase F (specs/011-ton-dong-sau-phase-f). Chỉ đọc file gốc của người dùng; thử trên bản sao ở
// build/f2-out/. Mẫu do `python3 -I scripts/f2-samples/make_f2_samples.py [--large]` sinh vào build/f2-out/samples/; file Desktop lưu
// ở buổi VM nằm trong docs/phase-f2-evidence/vm-f1x/ (ngoài git). Thiếu file thì test bỏ qua. Test nặng đặt tên chứa `F2`.
import Foundation

enum F2Fixtures {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    static var heavy: Bool { ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1" }

    private static func existing(_ url: URL) -> URL? { FileManager.default.fileExists(atPath: url.path) ? url : nil }

    /// Mẫu `build/f2-out/samples/<name>`, `nil` nếu chưa sinh.
    static func sample(_ name: String) -> URL? { existing(root.appendingPathComponent("build/f2-out/samples/\(name)")) }

    /// File Desktop lưu ở buổi VM, ví dụ `desktop("vm-f10", "f10-desktop.pbix")`.
    static func desktop(_ session: String, _ name: String) -> URL? {
        existing(root.appendingPathComponent("docs/phase-f2-evidence/\(session)/\(name)"))
    }

    /// `build/f2-out/<name>`, tạo nếu chưa có.
    static func outputDirectory(_ name: String) throws -> URL {
        let dir = root.appendingPathComponent("build/f2-out/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    /// Nhom6 của người dùng (chỉ đọc). `BIPRO_NHOM6` ghi đè đường dẫn.
    static let nhom6: URL? = {
        if let path = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return ["Nhom6_Dashboard.pbix", "bipro-golden/Nhom6_work.pbix"].lazy
            .compactMap { existing(downloads.appendingPathComponent($0)) }.first
    }()

    /// File Desktop bật Auto date/time (chỉ đọc). `BIPRO_W83` ghi đè đường dẫn.
    static let w83: URL? = {
        if let path = ProcessInfo.processInfo.environment["BIPRO_W83"], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return existing(downloads.appendingPathComponent("DWH&BI/w8.3.pbix"))
    }()

    /// Bản sao của `source` ở `build/f2-out/<folder>/<fileName>` để thử ghi; `nil` khi không có file gốc.
    static func copy(_ source: URL?, folder: String, fileName: String) throws -> URL? {
        guard let source else { return nil }
        let target = try outputDirectory(folder).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}
