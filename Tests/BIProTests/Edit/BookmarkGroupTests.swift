import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Nhóm bookmark (bổ sung D6): `docs/phase-d-evidence/vm-d8/QUAN-SAT.md` mục 5,
/// `specs/007-d6-bookmark-filter/contracts/bookmark-editing.md`.
@Suite @MainActor struct BookmarkGroupTests {
    typealias Env = BookmarkFilterSavingTests.Env
    static let indexPath = BookmarkFilterSavingTests.bookmarksPath

    static func bookmark(_ id: String) -> (name: String, json: String) {
        (id, #"{"name":"\#(id)","displayName":"\#(id.uppercased())","options":{"suppressData":true},"explorationState":{"version":"1.0","activeSection":"p1","sections":{"p1":{"visualContainers":{}}}}}"#)
    }
    static let three = ["bm1", "bm2", "bm3"].map(bookmark)
    static let groupID = "0123456789abcdef0123"

    private func index(_ env: Env) throws -> String { try env.read(Self.indexPath) }

    // MARK: Nhóm

    @Test func groupingWritesOneGroupItemLikeDesktop() throws {
        let env = try Env(bookmarks: Self.three); defer { env.cleanUp() }
        #expect(env.editor.groupBookmarks(["bm1", "bm3"], id: Self.groupID, name: "Group 1"))
        #expect(env.editor.undoDepth == 1)
        let changes = try env.changes()
        #expect(Set(changes.reportParts.keys) == [Self.indexPath] && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        #expect(String(decoding: changes.reportParts[Self.indexPath]!, as: UTF8.self)
                    == #"{"items":[{"name":"\#(Self.groupID)","displayName":"Group 1","children":["bm1","bm3"]},{"name":"bm2"}]}"#)
        _ = try env.save()
        // Đọc lại: hai bookmark thuộc nhóm, bookmark còn lại ở ngoài.
        let bookmarks = try PBIXFile(url: env.source).loadBookmarks()
        #expect(bookmarks.filter { $0.group == "Group 1" && $0.groupID == Self.groupID }.map(\.id) == ["bm1", "bm3"])
        #expect(bookmarks.first { $0.id == "bm2" }?.group == nil)
        // Lưu lần hai không ghi gì.
        let again = try env.changes()
        #expect(again.reportParts.isEmpty && again.addedParts.isEmpty && again.removedParts.isEmpty)
    }

    @Test func aBookmarkAddedInTheSessionCanBeGrouped() throws {
        let env = try Env(bookmarks: Self.three); defer { env.cleanUp() }
        let fresh = "fedcba9876543210fedc"
        env.editor.addBookmark(BookmarkFilterSavingTests.displayBookmark(fresh))
        #expect(env.editor.groupBookmarks(["bm2", fresh], id: Self.groupID, name: "Group 1"))
        _ = try env.save()
        #expect(try index(env) == #"{"items":[{"name":"bm1"},{"name":"\#(Self.groupID)","displayName":"Group 1","children":["bm2","\#(fresh)"]},{"name":"bm3"}]}"#)
    }

    @Test func groupingNeedsTwoBookmarksOutsideGroups() throws {
        let env = try Env(bookmarks: Self.three); defer { env.cleanUp() }
        #expect(!env.editor.groupBookmarks(["bm1"], id: Self.groupID, name: "Group 1"))
        #expect(env.editor.groupBookmarks(["bm1", "bm2"], id: Self.groupID, name: "Group 1"))
        // bm1 đã ở trong nhóm vừa tạo.
        #expect(!env.editor.groupBookmarks(["bm1", "bm3"], id: "aaaaaaaaaaaaaaaaaaaa", name: "Group 2"))
        #expect(env.editor.undoDepth == 1)
    }

    // MARK: Trạng thái hiển thị

    @Test func editsTellWhichGroupABookmarkIsIn() throws {
        var edits = BookmarkEdits()
        edits.groupsAdded = [BookmarkGroupEdit(id: "g1", name: "Group 1", children: ["a", "b"])]
        edits.groupsRemoved = [BookmarkGroupEdit(id: "old", name: "Cũ", children: ["c"])]
        #expect(edits.group(of: "a", inFile: nil)?.name == "Group 1")
        #expect(edits.group(of: "c", inFile: (id: "old", name: "Cũ")) == nil)                 // nhóm của file đã bỏ
        #expect(edits.group(of: "d", inFile: (id: "keep", name: "Giữ"))?.id == "keep")       // nhóm của file còn nguyên
        #expect(edits.group(of: "e", inFile: nil) == nil)
        #expect(!edits.isEmpty)
    }

    // MARK: Bỏ nhóm, hoàn tác, xoá

    @Test func ungroupingAFileGroupPutsTheBookmarksBack() throws {
        let env = try Env(bookmarks: Self.three); defer { env.cleanUp() }
        #expect(env.editor.groupBookmarks(["bm1", "bm3"], id: Self.groupID, name: "Group 1"))
        _ = try env.save()
        // Mở lại: nhóm nay là nhóm của file.
        let reopened = LayoutEditor.reading(archive: try ZipArchive(url: env.source), report: try PBIXFile(url: env.source).loadReport())
        reopened.showPage("p1")
        #expect(reopened.ungroupBookmarks(BookmarkGroupEdit(id: Self.groupID, name: "Group 1", children: ["bm1", "bm3"])))
        let changes = try reopened.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(String(decoding: changes.reportParts[Self.indexPath]!, as: UTF8.self) == #"{"items":[{"name":"bm1"},{"name":"bm3"},{"name":"bm2"}]}"#)
    }

    @Test func undoAfterSavingTakesTheGroupOutOfTheFileAgain() throws {
        let env = try Env(bookmarks: Self.three); defer { env.cleanUp() }
        let original = try index(env)
        #expect(env.editor.groupBookmarks(["bm1", "bm2"], id: Self.groupID, name: "Group 1"))
        _ = try env.save()
        #expect(try index(env).contains(#""children":["bm1","bm2"]"#))
        env.editor.undo()
        _ = try env.save()
        #expect(try index(env) == original)
        env.editor.redo()
        _ = try env.save()
        #expect(try index(env).contains(#""children":["bm1","bm2"]"#))
    }

    @Test func ungroupingASessionGroupBeforeSavingWritesNothing() throws {
        let env = try Env(bookmarks: Self.three); defer { env.cleanUp() }
        #expect(env.editor.groupBookmarks(["bm1", "bm2"], id: Self.groupID, name: "Group 1"))
        #expect(env.editor.ungroupBookmarks(BookmarkGroupEdit(id: Self.groupID, name: "Group 1", children: ["bm1", "bm2"])))
        let changes = try env.changes()
        #expect(changes.reportParts.isEmpty && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        #expect(env.editor.reportEdits.bookmarks.group(of: "bm1", inFile: nil) == nil)
    }

    @Test func deletingAMemberShrinksTheGroupAndTheLastOneRemovesIt() throws {
        let env = try Env(bookmarks: Self.three); defer { env.cleanUp() }
        #expect(env.editor.groupBookmarks(["bm1", "bm2"], id: Self.groupID, name: "Group 1"))
        _ = try env.save()
        env.editor.deleteBookmark(id: "bm1")
        _ = try env.save()
        #expect(try index(env) == #"{"items":[{"name":"\#(Self.groupID)","displayName":"Group 1","children":["bm2"]},{"name":"bm3"}]}"#)
        env.editor.deleteBookmark(id: "bm2")
        _ = try env.save()
        #expect(try index(env) == #"{"items":[{"name":"bm3"}]}"#)
        #expect(env.editor.reportEdits.bookmarks.groupsAdded.isEmpty)
    }
}
