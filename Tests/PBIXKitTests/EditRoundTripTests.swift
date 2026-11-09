import Foundation
import Testing
@testable import PBIXKit

/// Nhom6 thật (file của tác giả): `BIPRO_NHOM6`, hoặc `~/Downloads/bipro-golden/Nhom6_work.pbix`, hoặc bản gốc cũ.
enum EditFixture {
    static let nhom6: URL? = {
        let fm = FileManager.default
        if let path = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        for name in ["Nhom6_Dashboard.pbix", "bipro-golden/Nhom6_work.pbix"] {
            let url = downloads.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }()

    /// `build/d-out/<name>` trong thư mục gốc của dự án.
    static func outputDirectory(_ name: String) throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/d-out/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

@Suite(.enabled(if: EditFixture.nhom6 != nil)) struct EditRoundTripTests {
    static let page = "d1_giaodich"
    /// Có trong bookmark Q1.3 (targetVisualNames và visualContainers).
    static let bookmarked = "2132ddc1caa56c2879e6"

    @Test func moveDuplicateRemoveOnNhom6() throws {
        let source = try #require(EditFixture.nhom6)
        let original = try PBIXFile(url: source)
        let archive = original.archive
        let before = try original.loadReport()
        let d1 = try #require(before.pages.first { $0.id == Self.page })

        // Dời 3 visual (không phải visual bị xoá), nhân bản 1 card, xoá visual có trong bookmark.
        let movable = Array(d1.visuals.filter { $0.id != Self.bookmarked }.prefix(3))
        #expect(movable.count == 3)
        var changes = PBIXChanges()
        var moved: [String: (x: Int, y: Int, w: Int, h: Int)] = [:]
        for (i, visual) in movable.enumerated() {
            let path = "Report/definition/pages/\(Self.page)/visuals/\(visual.id)/visual.json"
            let x = Int(visual.x) + 40 + i * 8, y = Int(visual.y) + 16, w = Int(visual.width) + 8, h = Int(visual.height) + 8
            changes.reportParts[path] = try PBIRLayoutPatch.setPosition(in: try archive.read(path), x: x, y: y, width: w, height: h)
            moved[visual.id] = (x, y, w, h)
        }
        let card = try #require(d1.visuals.first { $0.type == "card" })
        let cardPath = "Report/definition/pages/\(Self.page)/visuals/\(card.id)/visual.json"
        let taken = Set(before.pages.flatMap { $0.visuals.map(\.id) })
        let newID = PBIRLayoutPatch.makeVisualName(avoiding: taken)
        let maxZ = d1.visuals.map(\.z).max() ?? 0
        let copyPath = "Report/definition/pages/\(Self.page)/visuals/\(newID)/visual.json"
        changes.addedParts[copyPath] = try PBIRLayoutPatch.duplicated(
            try archive.read(cardPath), newName: newID, x: Int(card.x) + 16, y: Int(card.y) + 16,
            width: Int(card.width), height: Int(card.height), z: Int(maxZ) + 1000)

        let removedPath = "Report/definition/pages/\(Self.page)/visuals/\(Self.bookmarked)/visual.json"
        changes.removedParts.insert(removedPath)
        for entry in archive.entries where entry.path.hasSuffix(".bookmark.json") {
            let data = try archive.read(entry)
            let cleaned = try PBIRLayoutPatch.removingVisualReferences([Self.bookmarked], fromBookmark: data)
            if cleaned != data { changes.reportParts[entry.path] = cleaned }
        }
        #expect(changes.reportParts.keys.contains { $0.hasSuffix(".bookmark.json") }, "bookmark Q1.3 phải được dọn")

        let result = try PBIXWriter.build(source: source, changes: changes)
        let dir = try EditFixture.outputDirectory("D1")
        let output = dir.appendingPathComponent("Nhom6_pre.pbix")
        try result.data.write(to: output)

        // Bảng ZIP hợp lệ.
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tq", output.path]
        let pipe = Pipe()
        unzip.standardOutput = pipe
        unzip.standardError = pipe
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0, "unzip -t: \(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")

        // Trang không sửa và DataModel khớp từng byte.
        let after = try PBIXFile(url: output)
        for entry in archive.entries {
            let touched = changes.reportParts[entry.path] != nil || changes.removedParts.contains(entry.path)
            if touched { continue }
            let now = try #require(after.archive.entry(entry.path), "\(entry.path)")
            #expect(now.crc32 == entry.crc32, "\(entry.path)")
        }
        #expect(try after.archive.read("DataModel") == archive.read("DataModel"))
        for page in before.pages where page.id != Self.page {
            for visual in page.visuals {
                let path = "Report/definition/pages/\(page.id)/visuals/\(visual.id)/visual.json"
                #expect(try after.archive.read(path) == archive.read(path), Comment(rawValue: path))
            }
        }

        // Đọc lại: vị trí mới, bản sao, visual đã xoá.
        let report = try after.loadReport()
        let page = try #require(report.pages.first { $0.id == Self.page })
        for (id, frame) in moved {
            let v = try #require(page.visuals.first { $0.id == id })
            #expect(Int(v.x) == frame.x && Int(v.y) == frame.y && Int(v.width) == frame.w && Int(v.height) == frame.h, Comment(rawValue: id))
        }
        let copy = try #require(page.visuals.first { $0.id == newID })
        #expect(copy.type == "card" && Int(copy.z) == Int(maxZ) + 1000)
        #expect(copy.fields == card.fields)
        #expect(!page.visuals.contains { $0.id == Self.bookmarked })
        #expect(page.visuals.count == d1.visuals.count)  // +1 bản sao −1 đã xoá

        // Bookmark còn đọc được và không nhắc tới visual đã xoá.
        let bookmarks = after.loadBookmarks()
        #expect(bookmarks.count == original.loadBookmarks().count)
        for part in after.archive.entries where part.path.hasSuffix(".bookmark.json") {
            #expect(!String(decoding: try after.archive.read(part), as: UTF8.self).contains(Self.bookmarked), Comment(rawValue: part.path))
        }
    }
}
