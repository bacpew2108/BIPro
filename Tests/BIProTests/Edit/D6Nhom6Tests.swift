// Test nặng D6 trên Nhom6 thật: BIPRO_HEAVY=1 (tên có "D6Nhom6"). File: BIPRO_NHOM6, hoặc
// ~/Downloads/Nhom6_Dashboard.pbix, hoặc ~/Downloads/bipro-golden/Nhom6_work.pbix.
import DAXEngine
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

@Suite("D6: D6Nhom6", .enabled(if: heavy && nhom6 != nil), .serialized)
@MainActor
struct D6Nhom6Tests {
    static let d1 = "d1_giaodich", d3 = "d3_cskh"

    private func outputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/d-out/D6", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func save(_ editor: LayoutEditor, source: URL, stamp: FileStamp, to output: URL) throws -> Double {
        try? FileManager.default.removeItem(at: output)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-d6-backups-\(UUID().uuidString)")
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

    private func displayBookmark(_ id: String, name: String, page: String, hide: [String]) -> UserBookmark {
        var bookmark = UserBookmark(id: id, name: name)
        bookmark.pageID = page
        bookmark.data = false
        var vis = VisibilityState()
        for visual in hide { vis.setHidden(visual, true) }
        bookmark.visibility = vis
        return bookmark
    }

    @Test func themBookmarkVaLocLuuMoLai() async throws {
        let source = try #require(nhom6)
        let sourceStamp = try FileStamp.of(source)
        let original = try PBIXFile(url: source)
        let archive = original.archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        let d1 = try #require(workspace.report.pages.first { $0.id == Self.d1 })
        let hiddenVisual = try #require(d1.visuals.first { $0.type == "card" })
        editor.showPage(Self.d1)

        // Bookmark: thêm (Display + Current page), đổi tên và xoá bookmark có sẵn.
        let newID = editor.makeBookmarkID(existing: Set(workspace.bookmarks.map(\.id)))
        let t0 = Date()
        editor.addBookmark(displayBookmark(newID, name: "Bookmark D6", page: Self.d1, hide: [hiddenVisual.id]))
        let existing = try #require(workspace.bookmarks.first { $0.id == "Bookmark_Q13_GioThu" })
        let other = try #require(workspace.bookmarks.first { $0.id == "Bookmark_Q13_MuaVu" })
        #expect(editor.renameBookmark(id: existing.id, to: "Giờ × Thứ (D6)", others: workspace.bookmarks.filter { $0.id != existing.id }.map(\.displayName)) == nil)
        editor.deleteBookmark(id: other.id)
        let bookmarkMs = Date().timeIntervalSince(t0) * 1000
        print("D6Nhom6: 3 thao tác bookmark \(String(format: "%.1f", bookmarkMs)) ms")
        #expect(bookmarkMs < 300)
        let pre = try outputDirectory().appendingPathComponent("Nhom6_d6_pre.pbix")
        _ = try save(editor, source: source, stamp: sourceStamp, to: pre)

        // Bộ lọc: thêm Basic cấp trang D3, sửa một thẻ cấp visual có sẵn.
        let sex = QueryColumn(table: "Dim_Client", column: "sex")
        let pageKey = UserFilterKey(level: .page, scope: Self.d3, filterID: "added-Dim_Client.sex")
        editor.setFilter(UserFilter(column: sex, values: [.string("Female")]), for: pageKey, coalesce: false)
        let candidates: [(String, ReportFilter)] = workspace.visualFilters.compactMap { entry in
            entry.value.first(where: { UserFilter.from($0)?.values.isEmpty == false }).map { (entry.key, $0) }
        }
        let (visualID, visualFilter) = try #require(candidates.first)
        var edited = try #require(UserFilter.from(visualFilter))
        edited.exclude.toggle()
        let visualKey = UserFilterKey(level: .visual, scope: visualID, filterID: visualFilter.id)
        editor.setFilter(edited, for: visualKey, coalesce: false)
        #expect(editor.isDirty)

        // Hoàn tác từng bước tới trạng thái đã lưu của `pre`, rồi làm lại.
        let depth = editor.undoDepth
        editor.undo(); editor.undo()
        #expect(editor.reportEdits.filters.isEmpty)
        editor.redo(); editor.redo()
        #expect(editor.undoDepth == depth)

        let output = try outputDirectory().appendingPathComponent("Nhom6_d6.pbix")
        let seconds = try save(editor, source: source, stamp: sourceStamp, to: output)
        print("D6Nhom6: lưu \(String(format: "%.3f", seconds)) s")
        #expect(seconds < 1.0, "lưu dưới 1 s, thực tế \(seconds) s (máy rảnh)")
        #expect(try FileStamp.of(source) == sourceStamp, "nguồn không bị đổi")
        #expect(editor.saveNotes.isEmpty)
        try unzipTest(output)

        // Mở lại: bookmark, bộ lọc.
        let saved = try Workspace(data: Data(contentsOf: output))
        #expect(saved.bookmarks.map(\.id).contains(newID) && !saved.bookmarks.map(\.id).contains(other.id))
        #expect(saved.bookmarks.first { $0.id == existing.id }?.displayName == "Giờ × Thứ (D6)")
        let mine = try #require(saved.bookmarks.first { $0.id == newID })
        #expect(mine.suppressData && mine.activeSection == Self.d1 && mine.hidden[hiddenVisual.id] == true)
        let pageFilters = try #require(saved.pageFilters[Self.d3])
        let reopened = try #require(pageFilters.first { UserFilter.from($0)?.column == sex })
        #expect(UserFilter.from(reopened)?.values == [.string("Female")])
        let savedVisualFilter = try #require(saved.visualFilters[visualID]?.first { $0.id == visualFilter.id })
        #expect(UserFilter.from(savedVisualFilter)?.exclude == edited.exclude)
        // Báo cáo đã có sẵn 2 bộ lọc cấp báo cáo: nguyên vẹn.
        #expect(saved.reportFilters.map(\.id) == workspace.reportFilters.map(\.id))

        // Phần không sửa khớp byte.
        let afterZip = try ZipArchive(url: output)
        let touched: Set<String> = [LayoutEditor.bookmarksJSONPath, LayoutEditor.bookmarkPathForTests(newID),
                                    LayoutEditor.bookmarkPathForTests(existing.id), LayoutEditor.bookmarkPathForTests(other.id),
                                    LayoutEditor.pagePath(Self.d3), LayoutEditor.visualPath(page: try #require(workspace.report.pages.first { $0.visuals.contains { $0.id == visualID } }).id, id: visualID),
                                    "SecurityBindings", "[Content_Types].xml"]
        for entry in archive.entries where !touched.contains(entry.path) {
            let now = try #require(afterZip.entry(entry.path), Comment(rawValue: entry.path))
            #expect(now.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        #expect(try afterZip.read("DataModel") == archive.read("DataModel"))

        // Bộ lọc trang vào đường truy vấn: visual trang D3 nhận bộ lọc "Female" sau khi mở lại.
        let interaction = ReportInteraction(workspace: saved)
        let d3 = try #require(saved.report.pages.first { $0.id == Self.d3 })
        let probe = try #require(d3.visuals.first { $0.type == "card" })
        let statics = interaction.staticFilters(page: d3, visual: probe)
        #expect(statics.contains { $0.predicate.contains("Female") })

        try """
        # Kiểm tay D6: Nhom6_d6.pbix trong Power BI Desktop

        1. Mở `Nhom6_d6.pbix`: không báo lỗi.
        2. Bookmarks pane: "Bookmark D6" có (ẩn một card ở trang D1), "Giờ × Thứ (D6)" đã đổi tên, "Q1.3 · Tháng trong năm" không còn.
        3. Bấm "Bookmark D6": card bị ẩn, ở trang D1.
        4. Trang D3: Filters pane có thẻ "sex là Female"; số liệu các visual trang D3 đổi theo.
        5. Thẻ lọc cấp visual đã sửa (is not ↔ is) hiện đúng.
        6. Trượt thì dùng `Nhom6_d6_pre.pbix` (chỉ bookmark) để biết lỗi ở bookmark hay ở bộ lọc.
        """.write(to: try outputDirectory().appendingPathComponent("CHECKLIST.md"), atomically: true, encoding: .utf8)
    }
}
