// Fixture chung cho test Phase F (ConnectorsTests). Chỉ đọc file gốc của người dùng; thử trên bản sao ở build/f-out/.
// File mẫu do `python3 scripts/f-samples/make_samples.py` sinh ra `build/f-out/samples/`; thiếu thì test bỏ qua.
import Foundation

enum FFixtures {
    /// Thư mục gốc dự án (nơi có Package.swift), tìm từ vị trí file này.
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    static var heavy: Bool { ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1" }

    /// File mẫu `build/f-out/samples/<name>`, `nil` nếu chưa sinh.
    static func sample(_ name: String) -> URL? {
        let url = root.appendingPathComponent("build/f-out/samples/\(name)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// `build/f-out/<name>`, tạo nếu chưa có.
    static func outputDirectory(_ name: String) throws -> URL {
        let dir = root.appendingPathComponent("build/f-out/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
