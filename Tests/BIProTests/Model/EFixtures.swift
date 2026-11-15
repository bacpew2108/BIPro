// Fixture chung cho test Phase E trong BIProTests. File Nhom6 của người dùng, chỉ đọc; thử trên bản sao ở build/e-out/.
import Foundation

enum EFixtures {
    static let nhom6: URL? = {
        let fm = FileManager.default
        if let path = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        for name in ["Nhom6_Dashboard.pbix", "bipro-golden/Nhom6_work.pbix"] {
            let url = downloads.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }()

    static var heavy: Bool { ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1" }

    /// `build/e-out/<name>` trong thư mục gốc của dự án.
    static func outputDirectory(_ name: String) throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/e-out/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

import PBIXKit

extension EFixtures {
    /// Metadata của Nhom6 (chỉ đọc), nil khi không có file.
    static let metadata: ModelMetadata? = {
        guard let url = nhom6, let data = try? PBIXFile(url: url).loadDataModel().0.contents(named: "metadata.sqlitedb") else { return nil }
        return try? ModelMetadata(sqlite: data)
    }()
}
