import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Lưu thay đổi trang (D5): `specs/005-d5-quan-ly-trang/contracts/page-save.md`.
@Suite @MainActor struct PageSavingTests {
    typealias S = SyntheticReport

    @MainActor struct Env {
        let dir: URL
        let source: URL
        let archive: ZipArchive
        let backups: URL
        let editor: LayoutEditor
        let stamp: FileStamp

        init(p1Page: String? = nil, extra: [(path: String, data: Data)] = [], bookmarks: [(name: String, json: String)]? = nil) throws {
            dir = SyntheticReport.temporaryDirectory("pagesave")
            source = try SyntheticReport.make(in: dir, p1Page: p1Page, extra: extra, bookmarks: bookmarks)
            archive = try ZipArchive(url: source)
            backups = dir.appendingPathComponent("Backups", isDirectory: true)
            editor = LayoutEditor.reading(archive: archive, report: try PBIXFile(url: source).loadReport())
            editor.showPage("p1")
            stamp = try FileStamp.of(source)
        }

        func save() throws -> SaveOutcome {
            try DocumentSaver.save(editor: editor, source: source, to: source, expectedStamp: nil, readOnlyRoots: [], backupDirectory: backups)
        }
        func report() throws -> ReportDefinition { try PBIXFile(url: source).loadReport() }
        func read(_ path: String) throws -> String { String(decoding: try ZipArchive(url: source).read(path), as: UTF8.self) }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    static let pagesPath = "Report/definition/pages/pages.json"
    static func pagePath(_ id: String) -> String { "Report/definition/pages/\(id)/page.json" }

    // MARK: thêm

    @Test func anAddedPageBecomesAPageJSONAndAPageOrderEntry() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.addPage())
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.addedParts.keys) == [Self.pagePath(id)])
        #expect(Set(changes.reportParts.keys) == [Self.pagesPath] && changes.removedParts.isEmpty)
        let pages = try #require(String(data: changes.reportParts[Self.pagesPath]!, encoding: .utf8))
        #expect(pages == #"{"pageOrder":["p1","p2","\#(id)"],"activePageName":"\#(id)"}"#)
        _ = try env.save()
        let report = try env.report()
        #expect(report.pages.map(\.id) == ["p1", "p2", id])
        #expect(report.pages.last?.displayName == "Page 1" && report.pages.last?.visuals.isEmpty == true)
        // mọi part khác nguyên byte
        let after = try ZipArchive(url: env.source)
        for entry in env.archive.entries where ![Self.pagesPath, "SecurityBindings", "[Content_Types].xml"].contains(entry.path) {
            #expect(after.entry(entry.path)?.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        #expect(after.entry("SecurityBindings") == nil)
    }

    @Test func aSecondSaveWithNothingNewWritesNothing() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = env.editor.addPage()
        _ = try env.save()
        let archive = try ZipArchive(url: env.source)
        let changes = try env.editor.makeChanges(archive: archive)
        #expect(changes.reportParts.isEmpty && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
    }

    // MARK: đổi tên

    @Test func aRenameTouchesOnlyThatPageJSON() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.renamePage("p2", to: "Hai · Việt") == nil)
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.reportParts.keys) == [Self.pagePath("p2")] && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        #expect(String(decoding: changes.reportParts[Self.pagePath("p2")]!, as: UTF8.self)
                == #"{"name":"p2","displayName":"Hai · Việt","width":1280,"height":720}"#)
        _ = try env.save()
        #expect(try env.report().pages.map(\.displayName) == ["P1", "Hai · Việt"])
        // trả tên cũ sau khi đã lưu: file về đúng như gốc
        #expect(env.editor.renamePage("p2", to: "P2") == nil)
        let back = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(String(decoding: back.reportParts[Self.pagePath("p2")]!, as: UTF8.self) == #"{"name":"p2","displayName":"P2","width":1280,"height":720}"#)
    }

    @Test func aRenamedNewPageIsWrittenWithItsFinalName() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.addPage())
        #expect(env.editor.renamePage(id, to: "Mới") == nil)
        _ = try env.save()
        #expect(try env.report().pages.last?.displayName == "Mới")
        #expect(env.editor.renamePage(id, to: "Mới hơn") == nil)      // đổi tiếp sau khi trang đã có trong file
        _ = try env.save()
        #expect(try env.report().pages.last?.displayName == "Mới hơn")
    }

    // MARK: đổi thứ tự

    @Test func aMoveChangesOnlyPagesJSON() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.movePage("p2", to: 0) == nil)
        env.editor.openPage("p2")
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.reportParts.keys) == [Self.pagesPath] && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        #expect(String(decoding: changes.reportParts[Self.pagesPath]!, as: UTF8.self) == #"{"pageOrder":["p2","p1"],"activePageName":"p2"}"#)
        _ = try env.save()
        #expect(try env.report().pages.map(\.id) == ["p2", "p1"])
    }

    @Test func noStructureChangeLeavesPagesJSONAlone() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.select("a")
        env.editor.move(["a"], dx: 16, dy: 0, snap: false)
        env.editor.openPage("p2")                                   // chỉ đổi trang đang xem
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(changes.reportParts[Self.pagesPath] == nil)
    }

    // MARK: xen kẽ với sửa trong trang

    @Test func editsInsideAnAddedPageAreWrittenAsNewVisualParts() throws {
        let env = try Env(); defer { env.cleanUp() }
        let page = try #require(env.editor.addPage())
        let card = try #require(env.editor.insertVisual(type: "card", visibleRect: nil))
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.addedParts.keys) == [Self.pagePath(page), LayoutEditor.visualPath(page: page, id: card)])
        _ = try env.save()
        let reloaded = try env.report()
        #expect(reloaded.pages.last?.visuals.map(\.id) == [card] && reloaded.pages.last?.visuals.first?.type == "card")
    }

    // MARK: nhân bản (US2)

    @Test func aDuplicatedPageIsWrittenAsNewPartsThatDifferOnlyInName() throws {
        let env = try Env(p1Page: PageDuplicateTests.drillPage, extra: PageDuplicateTests.groupedExtras()); defer { env.cleanUp() }
        let id = try #require(env.editor.duplicatePage("p1"))
        let copy = try #require(env.editor.page(id))
        let changes = try env.editor.makeChanges(archive: env.archive)
        let expectedPaths: Set<String> = Set([Self.pagePath(id)] + copy.visuals.map { LayoutEditor.visualPath(page: id, id: $0.id) }
                                             + (env.editor.pageExtraParts(id) ?? [:]).keys.map { LayoutEditor.visualPath(page: id, id: $0) })
        #expect(Set(changes.addedParts.keys) == expectedPaths)
        #expect(Set(changes.reportParts.keys) == [Self.pagesPath] && changes.removedParts.isEmpty)
        // mỗi visual của bản sao bằng visual gốc cùng vị trí, trừ name (và parentGroupName)
        let source = try #require(env.editor.page("p1"))
        for (a, b) in zip(source.visuals, copy.visuals) {
            let old = try JSONSerialization.jsonObject(with: try env.archive.read(LayoutEditor.visualPath(page: "p1", id: a.id))) as! [String: Any]
            let new = try JSONSerialization.jsonObject(with: changes.addedParts[LayoutEditor.visualPath(page: id, id: b.id)]!) as! [String: Any]
            func stripped(_ d: [String: Any]) -> NSDictionary { var d = d; d["name"] = nil; d["parentGroupName"] = nil; return d as NSDictionary }
            #expect(stripped(old).isEqual(to: stripped(new) as! [AnyHashable: Any]), Comment(rawValue: a.id))
        }
        _ = try env.save()
        let report = try env.report()
        #expect(report.pages.map(\.id) == ["p1", "p2", id])
        let written = try #require(report.pages.last)
        #expect(written.displayName == "Duplicate of P1" && written.visuals.count == source.visuals.count)
        #expect(Set(written.visuals.map(\.id)) == Set(copy.visuals.map(\.id)))
        // bản gốc nguyên byte
        let after = try ZipArchive(url: env.source)
        for entry in env.archive.entries where entry.path.hasPrefix("Report/definition/pages/p1/") {
            #expect(after.entry(entry.path)?.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        // page.json bản sao không còn pageBinding
        #expect(!(try env.read(Self.pagePath(id))).contains("pageBinding"))
        #expect(try env.read(Self.pagePath("p1")).contains("pageBinding"))
    }

    @Test func aMovedVisualOnADuplicatedPageIsWrittenWithTheCopy() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.duplicatePage("p1"))
        let target = try #require(env.editor.page(id)?.visuals.first)
        env.editor.select(target.id)
        env.editor.move([target.id], dx: 32, dy: 0, snap: false)
        _ = try env.save()
        let written = try #require(try env.report().pages.last?.visuals.first { $0.id == target.id })
        #expect(written.x == target.x + 32)
    }

    // MARK: xoá (US3)

    /// Không còn chỗ nào trong `definition/` nhắc tới mã trang (dạng chuỗi JSON đóng dấu nháy) và không có đường dẫn trang.
    func expectNoReference(to page: String, in url: URL) throws {
        let archive = try ZipArchive(url: url)
        for entry in archive.entries where entry.path.hasPrefix("Report/definition/") {
            #expect(!entry.path.contains("/pages/\(page)/"), Comment(rawValue: entry.path))
            let text = String(decoding: try archive.read(entry), as: UTF8.self)
            #expect(!text.contains("\"\(page)\""), Comment(rawValue: "\(entry.path) còn nhắc \(page)"))
        }
    }

    @Test func aRemovedPageTakesItsPartsAndItsBookmarksWithIt() throws {
        let env = try Env(bookmarks: PageRemoveTests.bookmarks); defer { env.cleanUp() }
        #expect(env.editor.removePage("p1") == nil)
        let changes = try env.editor.makeChanges(archive: env.archive)
        let p1Parts = Set(env.archive.entries.map(\.path).filter { $0.hasPrefix("Report/definition/pages/p1/") })
        #expect(p1Parts.count == 1 + 3)
        let bookmarkA = "Report/definition/bookmarks/A.bookmark.json", bookmarkB = "Report/definition/bookmarks/B.bookmark.json"
        #expect(changes.removedParts == p1Parts.union([bookmarkA]))
        #expect(Set(changes.reportParts.keys) == [Self.pagesPath, bookmarkB, "Report/definition/bookmarks/bookmarks.json"])
        #expect(changes.addedParts.isEmpty)
        #expect(String(decoding: changes.reportParts[Self.pagesPath]!, as: UTF8.self) == #"{"pageOrder":["p2"],"activePageName":"p2"}"#)
        #expect(String(decoding: changes.reportParts["Report/definition/bookmarks/bookmarks.json"]!, as: UTF8.self) == #"{"items":[{"name":"B"},{"name":"C"}]}"#)
        _ = try env.save()
        let report = try env.report()
        #expect(report.pages.map(\.id) == ["p2"])
        let after = try ZipArchive(url: env.source)
        #expect(after.entry(bookmarkA) == nil && after.entry("Report/definition/bookmarks/C.bookmark.json") != nil)
        #expect(after.entries.count == env.archive.entries.count - p1Parts.count - 1 - 1)      // phần trang, bookmark A, SecurityBindings
        try expectNoReference(to: "p1", in: env.source)
        // trang còn lại nguyên byte
        for entry in env.archive.entries where entry.path.hasPrefix("Report/definition/pages/p2/") {
            #expect(after.entry(entry.path)?.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
    }

    @Test func removingAPageCleansBookmarkVisualReferencesLikeD1() throws {
        let env = try Env(bookmarks: [PageRemoveTests.bookmark("B", display: "B", active: "p2", sections: ["p1", "p2"])]); defer { env.cleanUp() }
        #expect(env.editor.removePage("p1") == nil)
        _ = try env.save()
        let text = try env.read("Report/definition/bookmarks/B.bookmark.json")
        #expect(!text.contains("\"p1\"") && text.contains("\"p2\""))
        #expect(text.contains(#""targetVisualNames":["\#(SyntheticReport.a1)"]"#))     // như Desktop: tên visual còn trong targetVisualNames
    }

    @Test func aNewPageRemovedAfterBeingSavedLeavesNoTrace() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.addPage())
        _ = env.editor.insertVisual(type: "card", visibleRect: nil)
        _ = try env.save()
        #expect(try ZipArchive(url: env.source).entries.contains { $0.path.contains("/pages/\(id)/") })
        #expect(env.editor.removePage(id) == nil)
        _ = try env.save()
        let after = try ZipArchive(url: env.source)
        #expect(!after.entries.contains { $0.path.contains("/pages/\(id)/") })
        try expectNoReference(to: id, in: env.source)
        #expect(try env.report().pages.map(\.id) == ["p1", "p2"])
    }

    @Test func aNewPageRemovedBeforeSavingWritesNothing() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.addPage())
        _ = env.editor.insertVisual(type: "card", visibleRect: nil)
        #expect(env.editor.removePage(id) == nil)
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(changes.addedParts.isEmpty && changes.removedParts.isEmpty && changes.reportParts.isEmpty)
    }

    @Test func removeThenUndoThenSaveChangesNothing() throws {
        let env = try Env(bookmarks: PageRemoveTests.bookmarks); defer { env.cleanUp() }
        #expect(env.editor.removePage("p1") == nil)
        env.editor.undo()
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(changes.addedParts.isEmpty && changes.removedParts.isEmpty && changes.reportParts.isEmpty && !env.editor.isDirty)
    }

    // MARK: kiểm lúc lưu (US4)

    private func build(_ env: Env, adjusting: (inout PBIXChanges) -> Void = { _ in }) throws -> Data {
        var changes = try env.editor.makeChanges(archive: env.archive)
        adjusting(&changes)
        return try PBIXWriter.build(source: env.source, changes: changes).data
    }

    private func expectRejected(_ data: Data, _ env: Env, _ comment: String) {
        do {
            try DocumentSaver.verifyLayout(data, editor: env.editor)
            Issue.record("verifyLayout phải từ chối: \(comment)")
        } catch let error as SaveError {
            if case .verificationFailed = error { return }
            Issue.record("sai loại lỗi: \(error)")
        } catch { Issue.record("lỗi lạ: \(error)") }
    }

    @Test func verifyAcceptsTheRealBuildOfEveryPageOperation() throws {
        let env = try Env(bookmarks: PageRemoveTests.bookmarks); defer { env.cleanUp() }
        let added = try #require(env.editor.addPage())
        #expect(env.editor.renamePage(added, to: "Mới") == nil)
        _ = env.editor.duplicatePage("p2")
        #expect(env.editor.movePage(added, to: 0) == nil)
        #expect(env.editor.removePage("p1") == nil)
        try DocumentSaver.verifyLayout(try build(env), editor: env.editor)
    }

    @Test func verifyRejectsAMissingPageAWrongOrderAndAWrongName() throws {
        let env = try Env(); defer { env.cleanUp() }
        let original = try Data(contentsOf: env.source)
        _ = env.editor.addPage()
        expectRejected(original, env, "trang mới không có trong file")
        let env2 = try Env(); defer { env2.cleanUp() }
        #expect(env2.editor.movePage("p2", to: 0) == nil)
        expectRejected(try Data(contentsOf: env2.source), env2, "thứ tự không đổi trong file")
        let env3 = try Env(); defer { env3.cleanUp() }
        #expect(env3.editor.renamePage("p2", to: "Hai") == nil)
        expectRejected(try Data(contentsOf: env3.source), env3, "tên không đổi trong file")
    }

    @Test func verifyRejectsAnOrphanBookmarkAndAStaleReference() throws {
        let env = try Env(bookmarks: PageRemoveTests.bookmarks); defer { env.cleanUp() }
        #expect(env.editor.removePage("p1") == nil)
        // bỏ phần dọn bookmark khỏi gói thay đổi: bookmark A vẫn trỏ p1
        let orphan = try build(env) { changes in
            changes.removedParts = changes.removedParts.filter { !$0.contains("/bookmarks/") }
            changes.reportParts = changes.reportParts.filter { !$0.key.contains("/bookmarks/") }
        }
        expectRejected(orphan, env, "bookmark trỏ trang đã xoá")
        // bookmarks.json còn mục của bookmark đã gỡ
        let stale = try build(env) { changes in changes.reportParts["Report/definition/bookmarks/bookmarks.json"] = nil }
        expectRejected(stale, env, "bookmarks.json không khớp file bookmark")
    }

    @Test func verifyRejectsAReferenceToARemovedPageAnywhereInDefinition() throws {
        let env = try Env(p1Page: PageDuplicateTests.drillPage); defer { env.cleanUp() }
        #expect(env.editor.removePage("p2") == nil)
        // p1 có `"p2"` ở nơi khác (ví dụ visual của p1 nhắc p2): chèn vào một part còn lại
        let tainted = try build(env) { changes in
            changes.reportParts[Self.pagePath("p1")] = Data(#"{"name":"p1","displayName":"P1","note":"p2","width":1920,"height":1080}"#.utf8)
        }
        expectRejected(tainted, env, "còn nhắc mã trang đã xoá")
    }
}

