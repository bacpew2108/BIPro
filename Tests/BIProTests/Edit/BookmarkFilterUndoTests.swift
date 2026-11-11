import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Hoàn tác chung một lịch sử với D1 đến D5 (D6, US6): `specs/007-d6-bookmark-filter/spec.md`.
@Suite @MainActor struct BookmarkFilterUndoTests {
    typealias S = SyntheticReport
    static let key = UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.sex")

    func env() throws -> BookmarkFilterSavingTests.Env { try BookmarkFilterSavingTests.Env() }

    @Test func threeKindsOfEditUndoInReverseOrderAndLeaveTheFileUntouched() throws {
        let env = try env(); defer { env.cleanUp() }
        let e = env.editor
        let before = try ZipArchive(url: env.source).entries.map(\.crc32)
        e.deleteBookmark(id: "bm1")
        e.setFilter(BookmarkFilterSavingTests.sexFilter(), for: Self.key, coalesce: false)
        e.delete([S.a1])                       // D1: xoá visual
        #expect(e.undoDepth == 3 && e.isDirty)
        e.undo()
        #expect(e.visuals(of: "p1").map(\.id).contains(S.a1) && !e.reportEdits.filters.isEmpty)
        e.undo()
        #expect(e.reportEdits.filters.isEmpty && e.reportEdits.bookmarks.deleted == ["bm1"])
        e.undo()
        #expect(e.reportEdits.isEmpty && !e.isDirty)
        let changes = try e.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(changes.reportParts.isEmpty && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        #expect(try ZipArchive(url: env.source).entries.map(\.crc32) == before)
        e.redo(); e.redo(); e.redo()
        #expect(e.reportEdits.bookmarks.deleted == ["bm1"] && !e.reportEdits.filters.isEmpty && !e.visuals(of: "p1").map(\.id).contains(S.a1))
    }

    @Test func undoingADeletedBookmarkRestoresItAtTheSamePlaceAndSavesAsBefore() throws {
        let env = try env(); defer { env.cleanUp() }
        env.editor.addBookmark(BookmarkFilterSavingTests.displayBookmark("c123456789abcdef0123"))
        env.editor.deleteBookmark(id: "bm1")
        env.editor.undo()
        let rows = env.editor.reportEdits.bookmarks
        #expect(rows.deleted.isEmpty && rows.added.map(\.id) == ["c123456789abcdef0123"])
        let changes = try env.changes()
        #expect(changes.removedParts.isEmpty)
        #expect(PBIRBookmarkPatch.itemNames(in: changes.reportParts[BookmarkFilterSavingTests.bookmarksPath]!) == ["bm1", "c123456789abcdef0123"])
    }

    @Test func undoAfterASaveMakesTheDocumentDirtyAndTheNextSaveRevertsTheFile() throws {
        let env = try env(); defer { env.cleanUp() }
        let original = try env.read(BookmarkFilterSavingTests.pageP1)
        env.editor.setFilter(BookmarkFilterSavingTests.sexFilter(), for: Self.key, coalesce: false)
        _ = try env.save()
        #expect(!env.editor.isDirty)
        env.editor.undo()
        #expect(env.editor.isDirty)
        _ = try env.save()
        #expect(try env.read(BookmarkFilterSavingTests.pageP1) == original)
    }

    @Test func editsSurviveAPageOperationAndItsUndo() throws {
        let env = try env(); defer { env.cleanUp() }
        let e = env.editor
        e.setFilter(BookmarkFilterSavingTests.sexFilter(), for: Self.key, coalesce: false)
        let id = try #require(e.addPage())
        #expect(e.reportEdits.filters.count == 1)
        e.undo()                                // bỏ trang mới
        #expect(!e.pages.map(\.id).contains(id) && e.reportEdits.filters.count == 1)
        e.undo()
        #expect(e.reportEdits.isEmpty)
    }

    @Test func removingAFilterOfAFileCardCanBeResetOrUndone() throws {
        let page = #"{"name":"p1","displayName":"P1","width":1920,"height":1080,"filterConfig":{"filters":[{"name":"fSex","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"sex"}},"type":"Categorical"}]}}"#
        let env = try BookmarkFilterSavingTests.Env(p1Page: page); defer { env.cleanUp() }
        let key = UserFilterKey(level: .page, scope: "p1", filterID: "fSex")
        env.editor.removeFilter(key)
        #expect(env.editor.reportEdits.filterRemovals == [key])
        env.editor.resetFilter(key)
        #expect(env.editor.reportEdits.filters.isEmpty)
        let changes = try env.changes()
        #expect(changes.reportParts.isEmpty)
    }

    @Test func undoingASavedAddedBookmarkRemovesItsFileOnTheNextSave() throws {
        let env = try env(); defer { env.cleanUp() }
        let id = "d123456789abcdef0123"
        env.editor.addBookmark(BookmarkFilterSavingTests.displayBookmark(id))
        _ = try env.save()
        #expect(try ZipArchive(url: env.source).entry(BookmarkFilterSavingTests.bookmarkPath(id)) != nil)
        env.editor.undo()
        _ = try env.save()
        let after = try ZipArchive(url: env.source)
        #expect(after.entry(BookmarkFilterSavingTests.bookmarkPath(id)) == nil)
        #expect(try env.read(BookmarkFilterSavingTests.bookmarksPath) == BookmarkFilterSavingTests.bm1Index)
    }

    @Test func undoingASavedDeletionOfAFileBookmarkRestoresTheOriginalFile() throws {
        let env = try env(); defer { env.cleanUp() }
        let original = try env.read(BookmarkFilterSavingTests.bookmarkPath("bm1"))
        env.editor.deleteBookmark(id: "bm1")
        _ = try env.save()
        #expect(try ZipArchive(url: env.source).entry(BookmarkFilterSavingTests.bookmarkPath("bm1")) == nil)
        env.editor.undo()
        _ = try env.save()
        #expect(try env.read(BookmarkFilterSavingTests.bookmarkPath("bm1")) == original)
        #expect(PBIRBookmarkPatch.itemNames(in: Data(try env.read(BookmarkFilterSavingTests.bookmarksPath).utf8)) == ["bm1"])
    }

    @Test func undoingASavedRenameRestoresTheOriginalTitle() throws {
        let env = try env(); defer { env.cleanUp() }
        let original = try env.read(BookmarkFilterSavingTests.bookmarkPath("bm1"))
        #expect(env.editor.renameBookmark(id: "bm1", to: "Mới", others: []) == nil)
        _ = try env.save()
        env.editor.undo()
        _ = try env.save()
        #expect(try env.read(BookmarkFilterSavingTests.bookmarkPath("bm1")) == original)
    }
}
