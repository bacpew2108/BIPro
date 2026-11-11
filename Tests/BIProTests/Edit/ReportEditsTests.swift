import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// D6: giá trị thay đổi bookmark/lọc, luật gộp, và nằm chung lịch sử hoàn tác (`specs/007-d6-bookmark-filter/data-model.md`).
@Suite @MainActor struct ReportEditsTests {
    static let key = UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.sex")
    static let sex = QueryColumn(table: "Dim_Client", column: "sex")

    func editor() throws -> LayoutEditor {
        let dir = SyntheticReport.temporaryDirectory("redits")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try SyntheticReport.make(in: dir)
        let editor = LayoutEditor.reading(archive: try ZipArchive(url: url), report: try PBIXFile(url: url).loadReport())
        editor.showPage("p1")
        return editor
    }

    @Test func emptyEditsAreEqualAndNotDirty() throws {
        #expect(ReportEdits().isEmpty)
        let e = try editor()
        #expect(!e.isDirty && e.reportEdits.isEmpty)
    }

    @Test func effectiveFiltersLetTheSessionWinAndUnionRemovals() {
        let doc = UserFilter(column: Self.sex, values: [.string("Female")])
        let mine = UserFilter(column: Self.sex, values: [.string("Male")])
        var edits = ReportEdits()
        edits.filters[Self.key] = .set(doc)
        let other = UserFilterKey(level: .report, scope: "", filterID: "fOld")
        edits.filters[other] = .remove(name: "fOld")
        #expect(ReportEdits.effectiveFilters(edits: edits, session: [:])[Self.key] == doc)
        #expect(ReportEdits.effectiveFilters(edits: edits, session: [Self.key: mine])[Self.key] == mine)
        #expect(ReportEdits.effectiveRemovals(edits: edits, session: []) == [other])
        let sessionRemoved = UserFilterKey(level: .visual, scope: "a1", filterID: "x")
        #expect(ReportEdits.effectiveRemovals(edits: edits, session: [sessionRemoved]) == [other, sessionRemoved])
    }

    @Test func aFilterEditIsOneUndoStepAndMakesTheDocumentDirty() throws {
        let e = try editor()
        #expect(e.setFilter(UserFilter(column: Self.sex, values: [.string("Female")]), for: Self.key, coalesce: false))
        #expect(e.isDirty && e.canUndo && e.reportEdits.filters.count == 1)
        e.undo()
        #expect(!e.isDirty && e.reportEdits.isEmpty)
        e.redo()
        #expect(e.isDirty && e.reportEdits.filters.count == 1)
    }

    @Test func consecutiveEditsOfTheSameCardWithinTheWindowCoalesce() throws {
        let e = try editor()
        var t = Date(timeIntervalSince1970: 1000)
        e.now = { t }
        e.setFilter(UserFilter(column: Self.sex, values: [.string("A")]), for: Self.key)
        t = t.addingTimeInterval(0.2)
        e.setFilter(UserFilter(column: Self.sex, values: [.string("A"), .string("B")]), for: Self.key)
        #expect(e.undoDepth == 1)
        t = t.addingTimeInterval(2)
        e.setFilter(UserFilter(column: Self.sex, values: [.string("C")]), for: Self.key)
        #expect(e.undoDepth == 2)
        e.undo()
        #expect(e.reportEdits.filters[Self.key] == .set(UserFilter(column: Self.sex, values: [.string("A"), .string("B")])))
    }

    @Test func settingTheSameValueCreatesNoStep() throws {
        let e = try editor()
        let filter = UserFilter(column: Self.sex, values: [.string("A")])
        e.setFilter(filter, for: Self.key, coalesce: false)
        #expect(!e.setFilter(filter, for: Self.key, coalesce: false))
        #expect(e.undoDepth == 1)
    }

    @Test func bookmarkOperationsAreEachOneStepAndRestoreOrder() throws {
        let e = try editor()
        var a = UserBookmark(id: "aaaa", name: "Bookmark 1"); a.pageID = "p1"; a.data = false
        var b = UserBookmark(id: "bbbb", name: "Bookmark 2"); b.pageID = "p1"; b.data = false
        e.addBookmark(a); e.addBookmark(b)
        #expect(e.reportEdits.bookmarks.added.map(\.id) == ["aaaa", "bbbb"] && e.undoDepth == 2)
        #expect(e.renameBookmark(id: "aaaa", to: "Mới", others: ["Bookmark 2"]) == nil)
        #expect(e.reportEdits.bookmarks.added[0].name == "Mới")
        e.deleteBookmark(id: "aaaa")
        #expect(e.reportEdits.bookmarks.added.map(\.id) == ["bbbb"] && e.reportEdits.bookmarks.deleted == ["aaaa"])
        e.undo()
        #expect(e.reportEdits.bookmarks.added.map(\.id) == ["aaaa", "bbbb"] && e.reportEdits.bookmarks.deleted.isEmpty)
        e.undo(); e.undo(); e.undo()
        #expect(e.reportEdits.isEmpty && !e.isDirty)
    }

    @Test func renameIsRefusedForEmptyDuplicateOrTooLongNames() throws {
        let e = try editor()
        #expect(e.renameBookmark(id: "x", to: "   ", others: []) != nil)
        #expect(e.renameBookmark(id: "x", to: "Bookmark 2", others: ["bookmark 2"]) != nil)
        #expect(e.renameBookmark(id: "x", to: String(repeating: "a", count: 129), others: []) != nil)
        #expect(!e.isDirty)
    }

    @Test func movingBookmarksOnlyChangesOrder() throws {
        let e = try editor()
        e.moveBookmarks(order: ["b", "a"])
        #expect(e.reportEdits.bookmarks.order == ["b", "a"])
        #expect(!e.moveBookmarks(order: ["b", "a"]))
    }

    @Test func savedStateIsCleanAfterMarkSavedAndDirtyAfterUndo() throws {
        let e = try editor()
        e.setFilter(UserFilter(column: Self.sex), for: Self.key, coalesce: false)
        e.markSaved()
        #expect(!e.isDirty)
        e.undo()
        #expect(e.isDirty)
        e.redo()
        #expect(!e.isDirty)
    }
}
