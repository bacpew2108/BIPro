// Test nặng D7 trên Nhom6 và Nhóm 2 thật: BIPRO_HEAVY=1 (tên có "D7Nhom6"). File Nhom6: BIPRO_NHOM6, hoặc
// ~/Downloads/Nhom6_Dashboard.pbix, hoặc ~/Downloads/bipro-golden/Nhom6_work.pbix. Nhóm 2 (định dạng cũ): BIPRO_LEGACY2 hoặc
// ~/Downloads/Nhóm 2/Dashboard/Nhóm 2 - Financial Service .pbix (chỉ đọc; chép sang build/ trước khi sửa).
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private let heavy = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

private let nhom6: URL? = {
    let fm = FileManager.default
    if let path = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
    let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    for name in ["Nhom6_Dashboard.pbix", "bipro-golden/Nhom6_work.pbix"] {
        let url = downloads.appendingPathComponent(name)
        if fm.fileExists(atPath: url.path) { return url }
    }
    return nil
}()

private let nhom2: URL? = {
    let fm = FileManager.default
    if let path = ProcessInfo.processInfo.environment["BIPRO_LEGACY2"], fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
    let url = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Nhóm 2/Dashboard/Nhóm 2 - Financial Service .pbix")
    return fm.fileExists(atPath: url.path) ? url : nil
}()

@Suite("D7: D7Nhom6", .enabled(if: heavy && nhom6 != nil), .serialized)
@MainActor
struct D7Nhom6Tests {
    static let d1 = "d1_giaodich", d3 = "d3_cskh"
    // Trang D3 của Nhom6: ba thẻ hàng trên (x = 24, 338, 1594), ba biểu đồ hàng giữa, ba biểu đồ hàng dưới.
    static let cards = ["595dca09f0512e48b400", "f1bef09ae9c6f41d2003", "5b863d08c68634abb1b7"]
    static let middle = ["5c5c251aff61e492741c", "aabc04ac1cf734cd9e04", "c1ed9ef59aa712205f98"]
    static let bottom = ["e32431bc6968b6d0983e", "312cad44402b6f94be21", "1106a6e5b10c0fc7f175"]

    private func outputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/d-out/D7", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func save(_ editor: LayoutEditor, source: URL, stamp: FileStamp, to output: URL) throws -> Double {
        try? FileManager.default.removeItem(at: output)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-d7-backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backups) }
        let t0 = Date()
        let outcome = try DocumentSaver.save(editor: editor, source: source, to: output, expectedStamp: stamp, backupDirectory: backups)
        let seconds = Date().timeIntervalSince(t0)
        #expect(outcome.didWrite && !editor.isDirty)
        return seconds
    }

    private func unzipTest(_ url: URL) throws {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tq", url.path]
        let pipe = Pipe()
        unzip.standardOutput = pipe; unzip.standardError = pipe
        try unzip.run(); unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
    }

    private func milliseconds(_ body: () -> Void) -> Double {
        let t0 = Date(); body(); return Date().timeIntervalSince(t0) * 1000
    }

    @Test func canPhanBoDanGopLuuMoLai() async throws {
        let source = try #require(nhom6)
        let stamp = try FileStamp.of(source)
        let original = try PBIXFile(url: source)
        let archive = original.archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.showPage(Self.d3)
        let before = Dictionary(uniqueKeysWithValues: editor.visuals(of: Self.d3).map { ($0.id, Frame($0)) })

        // Căn trái ba biểu đồ hàng giữa; phân bố ngang ba thẻ hàng trên.
        editor.setSelection(Self.middle, extend: false)
        let alignMs = milliseconds { #expect(editor.align(.left)) }
        editor.setSelection(Self.cards, extend: false)
        let distributeMs = milliseconds { #expect(editor.align(.distributeH)) }
        #expect(editor.visual(Self.cards[1])?.x == 809)                       // đúng số đo ở Desktop (VM-D7)
        #expect(Self.middle.allSatisfy { editor.visual($0)?.x == 24 })
        print("D7Nhom6: căn \(String(format: "%.1f", alignMs)) ms, phân bố \(String(format: "%.1f", distributeMs)) ms")

        // Dán sang trang khác: thẻ đầu của D3 sang D1.
        editor.select(Self.cards[0]); editor.copy()
        editor.showPage(Self.d1)
        var pasted: [String] = []
        let pasteMs = milliseconds { pasted = editor.paste() }
        let pastedID = try #require(pasted.first)
        let copy = try #require(editor.visual(pastedID))
        let d1Top = workspace.report.pages.first { $0.id == Self.d1 }!.visuals.map(\.z).max()!
        #expect(copy.x == 34 && copy.y == 186 && copy.z == d1Top + 1)         // +10, +10 và z + 1 (VM-D7)
        print("D7Nhom6: dán \(String(format: "%.1f", pasteMs)) ms")
        let pre = try outputDirectory().appendingPathComponent("Nhom6_d7_pre.pbix")
        _ = try save(editor, source: source, stamp: stamp, to: pre)

        // Nhóm ba biểu đồ hàng dưới, kéo nhóm, rồi lưu.
        editor.showPage(Self.d3)
        editor.setSelection(Self.bottom, extend: false)
        var groupID: String?
        let groupMs = milliseconds { groupID = editor.group() }
        let id = try #require(groupID)
        editor.move([id], dx: 16, dy: 0, snap: false)
        print("D7Nhom6: nhóm \(String(format: "%.1f", groupMs)) ms")
        #expect(alignMs < 150 && distributeMs < 150 && pasteMs < 150 && groupMs < 150)

        // Hoàn tác việc kéo rồi bỏ nhóm ngay (chưa lưu): ba biểu đồ về đúng vị trí ban đầu (0 điểm lệch).
        editor.undo()
        editor.ungroup()
        #expect(editor.groups(of: Self.d3).isEmpty)
        for id in Self.bottom { #expect(editor.visual(id).map(Frame.init) == before[id]) }
        editor.undo()                                                           // quay lại nhóm
        editor.move([id], dx: 16, dy: 0, snap: false)

        let output = try outputDirectory().appendingPathComponent("Nhom6_d7.pbix")
        let seconds = try save(editor, source: source, stamp: stamp, to: output)
        print("D7Nhom6: lưu \(String(format: "%.3f", seconds)) s")
        #expect(seconds < 1.0, "lưu dưới 1 s, thực tế \(seconds) s (máy rảnh)")
        #expect(try FileStamp.of(source) == stamp, "nguồn không bị đổi")
        try unzipTest(output)

        // Mở lại.
        let saved = try Workspace(data: Data(contentsOf: output))
        let page = try #require(saved.report.pages.first { $0.id == Self.d3 })
        #expect(page.groups.count == 1)
        let group = try #require(page.groups.first)
        let kids = page.visuals.filter { $0.parentGroup == group.id }
        #expect(Set(kids.map(\.id)) == Set(Self.bottom))
        for kid in kids {
            let was = try #require(before[kid.id])
            #expect(Frame(kid) == Frame(x: was.x + 16, y: was.y, width: was.width, height: was.height))   // 0 điểm lệch
        }
        let savedD1 = try #require(saved.report.pages.first { $0.id == Self.d1 })
        #expect(savedD1.visuals.count == workspace.report.pages.first { $0.id == Self.d1 }!.visuals.count + 1)

        // Phần không sửa khớp byte.
        let afterZip = try ZipArchive(url: output)
        let changedParts = (try ZipArchive(url: output)).entries.filter { entry in
            guard let old = archive.entry(entry.path) else { return true }
            return old.crc32 != entry.crc32
        }.map(\.path)
        print("D7Nhom6: part đổi \(changedParts.count)")
        #expect(changedParts.allSatisfy { $0.hasPrefix("Report/definition/pages/") || $0 == "[Content_Types].xml" })
        #expect(try afterZip.read("DataModel") == archive.read("DataModel"))

        try """
        # Kiểm tay D7: Nhom6_d7.pbix trong Power BI Desktop

        1. Mở `Nhom6_d7.pbix`: không báo lỗi.
        2. Trang D3: ba thẻ hàng trên cách đều (thẻ giữa ở x = 809); ba biểu đồ hàng giữa thẳng mép trái (x = 24).
        3. Ba biểu đồ hàng dưới thành một nhóm "Group 1" (Selection pane), kéo nhóm thì cả ba đi cùng; Format > Group > Ungroup trả về ba visual riêng.
        4. Trang D1: có thêm một thẻ "Tổng khách hàng" ở lệch (10, 10) so với thẻ gốc ở D3, trên cùng.
        5. Trượt thì dùng `Nhom6_d7_pre.pbix` (chỉ căn, phân bố, dán, không nhóm) để biết lỗi ở nhóm hay không.
        """.write(to: try outputDirectory().appendingPathComponent("CHECKLIST.md"), atomically: true, encoding: .utf8)
    }
}

@Suite("D7: D7Nhom6 định dạng cũ", .enabled(if: heavy && nhom2 != nil), .serialized)
@MainActor
struct D7LegacyNhom6Tests {
    @Test func suaBoCucNhom2() async throws {
        let source = try #require(nhom2)
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/d-out/D7", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let work = dir.appendingPathComponent("Nhom2_work.pbix"), output = dir.appendingPathComponent("Nhom2_d7.pbix")
        try? FileManager.default.removeItem(at: work); try? FileManager.default.removeItem(at: output)
        try FileManager.default.copyItem(at: source, to: work)
        defer { try? FileManager.default.removeItem(at: work) }
        let stamp = try FileStamp.of(work)
        let archive = try ZipArchive(url: work)
        let report = try PBIXFile(url: work).loadReport()
        let editor = LayoutEditor.readingLegacy(archive: archive, report: report)
        let page = try #require(report.pages.first)
        editor.showPage(page.id)
        let free = page.visuals.filter { !editor.isLockedByGroup($0.id) }
        let ids = Array(free.prefix(3).map(\.id))
        editor.setSelection(ids, extend: false)
        editor.move([ids[0]], dx: 24, dy: 8, snap: false)
        #expect(editor.align(.left))
        editor.delete([ids[2]])
        let copy = try #require(editor.duplicate([ids[1]]).first)
        let backups = dir.appendingPathComponent("backups")
        defer { try? FileManager.default.removeItem(at: backups) }
        let t0 = Date()
        _ = try DocumentSaver.save(editor: editor, source: work, to: output, expectedStamp: stamp, backupDirectory: backups)
        let seconds = Date().timeIntervalSince(t0)
        print("D7Nhom2: lưu \(String(format: "%.3f", seconds)) s")
        #expect(seconds < 2.0, "lưu dưới 2 s, thực tế \(seconds) s (đo riêng 0,4 s; chạy cùng test nặng khác có thể chậm hơn)")
        let saved = try PBIXFile(url: output).loadReport()
        let savedPage = try #require(saved.pages.first { $0.id == page.id })
        #expect(savedPage.visuals.contains { $0.id == copy } && !savedPage.visuals.contains { $0.id == ids[2] })
        #expect(saved.pages.dropFirst().map { $0.visuals.map(\.id) } == report.pages.dropFirst().map { $0.visuals.map(\.id) })
        let after = try ZipArchive(url: output)
        for entry in archive.entries where !["Report/Layout", "SecurityBindings", "[Content_Types].xml"].contains(entry.path) {
            #expect(after.entry(entry.path)?.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        try """
        # Kiểm tay D7, báo cáo định dạng cũ: Nhom2_d7.pbix trong Power BI Desktop

        1. Mở `Nhom2_d7.pbix`: không báo lỗi ("file is corrupted" nghĩa là ghi `Report/Layout` hoặc bỏ `SecurityBindings` chưa đúng).
        2. Trang đầu (BC1): ba visual đầu theo thứ tự trong file đã căn trái; visual thứ ba đã xoá; có thêm một bản sao của visual thứ hai lệch 16 điểm.
        3. Các trang khác và các visual khác y như bản gốc.
        """.write(to: dir.appendingPathComponent("CHECKLIST-NHOM2.md"), atomically: true, encoding: .utf8)
    }
}
