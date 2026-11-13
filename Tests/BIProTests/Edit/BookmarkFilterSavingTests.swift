import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Lưu bookmark và bộ lọc (D6): `specs/007-d6-bookmark-filter/contracts/bookmark-filter-save.md`.
@Suite @MainActor struct BookmarkFilterSavingTests {
    typealias S = SyntheticReport
    static let bookmarksPath = "Report/definition/bookmarks/bookmarks.json"
    static func bookmarkPath(_ name: String) -> String { "Report/definition/bookmarks/\(name).bookmark.json" }
    static let reportPath = "Report/definition/report.json"
    static let pageP1 = "Report/definition/pages/p1/page.json"

    @MainActor struct Env {
        let dir: URL
        let source: URL
        let backups: URL
        let editor: LayoutEditor

        init(p1Page: String? = nil, bookmarks: [(name: String, json: String)]? = nil, extra: [(path: String, data: Data)] = []) throws {
            dir = SyntheticReport.temporaryDirectory("bmfilter")
            source = try SyntheticReport.make(in: dir, p1Page: p1Page, extra: extra, bookmarks: bookmarks)
            backups = dir.appendingPathComponent("Backups", isDirectory: true)
            editor = LayoutEditor.reading(archive: try ZipArchive(url: source), report: try PBIXFile(url: source).loadReport())
            editor.showPage("p1")
        }
        var archive: ZipArchive { get throws { try ZipArchive(url: source) } }
        func changes() throws -> PBIXChanges { try editor.makeChanges(archive: archive) }
        func save() throws -> SaveOutcome {
            try DocumentSaver.save(editor: editor, source: source, to: source, expectedStamp: nil, readOnlyRoots: [], backupDirectory: backups)
        }
        func read(_ path: String) throws -> String { String(decoding: try ZipArchive(url: source).read(path), as: UTF8.self) }
        func json(_ path: String) throws -> JSONValue { try JSONValue.parse(try ZipArchive(url: source).read(path)) }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    static func displayBookmark(_ id: String, name: String = "Bookmark 9", page: String = "p1", hide: [String] = [], currentPage: Bool = true,
                                display: Bool = true) -> UserBookmark {
        var bookmark = UserBookmark(id: id, name: name)
        bookmark.pageID = page
        bookmark.data = false
        bookmark.display = display
        bookmark.currentPage = currentPage
        var vis = VisibilityState()
        for visual in hide { vis.setHidden(visual, true) }
        bookmark.visibility = vis
        return bookmark
    }

    static let bm1Index = #"{"items":[{"name":"bm1"}]}"#

    // MARK: Thêm bookmark

    @Test func addedBookmarkWritesAFileAndAnIndexEntry() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = "0123456789abcdef0123"
        env.editor.addBookmark(Self.displayBookmark(id, hide: [S.a2]))
        let changes = try env.changes()
        #expect(Set(changes.addedParts.keys) == [Self.bookmarkPath(id)])
        #expect(Set(changes.reportParts.keys) == [Self.bookmarksPath] && changes.removedParts.isEmpty)
        #expect(String(decoding: changes.reportParts[Self.bookmarksPath]!, as: UTF8.self) == #"{"items":[{"name":"bm1"},{"name":"\#(id)"}]}"#)
        let file = try JSONValue.parse(changes.addedParts[Self.bookmarkPath(id)]!)
        #expect(file["displayName"]?.string == "Bookmark 9" && file["name"]?.string == id)
        #expect(file["options"]?["suppressData"]?.bool == true && file["options"]?["suppressActiveSection"] == nil)
        #expect(file["options"]?["targetVisualNames"]?.array.compactMap(\.string) == [S.a1, S.a2, S.a3])
        #expect(file["explorationState"]?["activeSection"]?.string == "p1")
        let containers = try #require(file["explorationState"]?["sections"]?["p1"]?["visualContainers"]?.object)
        #expect(Set(containers.keys) == [S.a1, S.a2, S.a3])
        #expect(containers[S.a2]?["singleVisual"]?["display"]?["mode"]?.string == "hidden")
        #expect(containers[S.a1]?["singleVisual"]?["display"] == nil)
    }

    @Test func optionFlagsFollowDataDisplayAndCurrentPage() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = "1123456789abcdef0123"
        env.editor.addBookmark(Self.displayBookmark(id, hide: [S.a2], currentPage: false, display: false))
        let file = try JSONValue.parse(try env.changes().addedParts[Self.bookmarkPath(id)]!)
        #expect(file["options"]?["suppressActiveSection"]?.bool == true && file["options"]?["suppressDisplay"]?.bool == true)
        let containers = try #require(file["explorationState"]?["sections"]?["p1"]?["visualContainers"]?.object)
        #expect(containers[S.a2]?["singleVisual"]?["display"] == nil)
    }

    @Test func aSecondSaveWritesNothingAndTheFileReadsBack() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = "2123456789abcdef0123"
        env.editor.addBookmark(Self.displayBookmark(id, hide: [S.a1]))
        _ = try env.save()
        let again = try env.changes()
        #expect(again.reportParts.isEmpty && again.addedParts.isEmpty && again.removedParts.isEmpty)
        let reopened = try PBIXFile(url: env.source).loadBookmarks()
        let mine = try #require(reopened.first { $0.id == id })
        #expect(mine.suppressData && mine.activeSection == "p1" && mine.hidden[S.a1] == true && mine.hidden[S.a2] == false)
        #expect(mine.targetVisualNames == [S.a1, S.a2, S.a3])
    }

    @Test func aBookmarkWithDrillDataStaysInTheSessionWithAReason() throws {
        let env = try Env(); defer { env.cleanUp() }
        var data = Self.displayBookmark("3123456789abcdef0123"); data.data = true; data.drillDepth["v"] = 1
        env.editor.addBookmark(data)
        env.editor.addBookmark(Self.displayBookmark("4123456789abcdef0123", name: "Hiển thị"))
        let changes = try env.changes()
        #expect(Set(changes.addedParts.keys) == [Self.bookmarkPath("4123456789abcdef0123")])
        #expect(env.editor.saveNotes.count == 1 && env.editor.saveNotes[0].contains("drill"))
    }

    @Test func aDataBookmarkWithASlicerSelectionRoundTrips() throws {
        let env = try Env(extra: S.formatExtras); defer { env.cleanUp() }
        let id = "abc3456789abcdef0123"
        var bookmark = Self.displayBookmark(id, name: "Data")
        bookmark.data = true
        var state = FilterState()
        state.setSlicer(visualID: S.f2, columns: [QueryColumn(table: "Dim_Trans_Type", column: "trans_type")], selection: SlicerSelection([[.string("Credit")]]))
        bookmark.states["p1"] = state
        env.editor.addBookmark(bookmark)
        let changes = try env.changes()
        #expect(env.editor.saveNotes.isEmpty && changes.addedParts[Self.bookmarkPath(id)] != nil)
        _ = try env.save()
        let reopened = try #require(PBIXFile(url: env.source).loadBookmarks().first { $0.id == id })
        #expect(!reopened.suppressData)
        let slicer = try #require(reopened.data?.slicerFilters[S.f2])
        #expect(ReportInteraction.slicerPaths(slicer) == [[.string("Credit")]])
        #expect(reopened.data?.slicerFilters[S.a2] == nil && reopened.data?.visualFilters[S.f2] != nil)
    }

    @Test func aBookmarkOfAnUnknownPageIsSkipped() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.addBookmark(Self.displayBookmark("5123456789abcdef0123", page: "gone"))
        let changes = try env.changes()
        #expect(changes.addedParts.isEmpty && changes.reportParts.isEmpty && env.editor.saveNotes.count == 1)
    }

    @Test func existingIndexLayoutIsKeptWhenThereIsNoBookmarksJSONYet() throws {
        let env = try Env(bookmarks: []); defer { env.cleanUp() }
        // `bookmarks: []` tạo bookmarks.json rỗng; xoá nó khỏi file để thử đường "chưa có chỗ nào".
        let id = "6123456789abcdef0123"
        env.editor.addBookmark(Self.displayBookmark(id))
        let changes = try env.changes()
        let index = try #require(changes.reportParts[Self.bookmarksPath] ?? changes.addedParts[Self.bookmarksPath])
        #expect(PBIRBookmarkPatch.itemNames(in: index) == [id])
    }

    // MARK: Cập nhật, đổi tên, xoá, thứ tự

    @Test func renamingAFileBookmarkChangesOnlyItsDisplayName() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try env.read(Self.bookmarkPath("bm1"))
        #expect(env.editor.renameBookmark(id: "bm1", to: "Tên mới", others: []) == nil)
        let changes = try env.changes()
        #expect(Set(changes.reportParts.keys) == [Self.bookmarkPath("bm1")] && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        let after = try JSONValue.parse(changes.reportParts[Self.bookmarkPath("bm1")]!)
        #expect(after["displayName"]?.string == "Tên mới" && after["name"]?.string == "bm1")
        #expect(after["options"]?["targetVisualNames"]?.array.count == 2)
    }

    @Test func deletingTheLastBookmarkRemovesBothTheFileAndBookmarksJSON() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.deleteBookmark(id: "bm1")
        let changes = try env.changes()
        #expect(changes.removedParts == [Self.bookmarkPath("bm1"), Self.bookmarksPath] && changes.reportParts.isEmpty && changes.addedParts.isEmpty)
        _ = try env.save()
        let after = try env.archive
        #expect(after.entry(Self.bookmarksPath) == nil && after.entry(Self.bookmarkPath("bm1")) == nil)
    }

    @Test func deletingOneOfTwoBookmarksKeepsTheOther() throws {
        let two: [(name: String, json: String)] = [("A", #"{"name":"A","displayName":"A","explorationState":{"activeSection":"p1","sections":{"p1":{}}}}"#),
                                                   ("B", #"{"name":"B","displayName":"B","explorationState":{"activeSection":"p1","sections":{"p1":{}}}}"#)]
        let env = try Env(bookmarks: two); defer { env.cleanUp() }
        env.editor.deleteBookmark(id: "A")
        let changes = try env.changes()
        #expect(changes.removedParts == [Self.bookmarkPath("A")])
        #expect(String(decoding: changes.reportParts[Self.bookmarksPath]!, as: UTF8.self) == #"{"items":[{"name":"B"}]}"#)
    }

    @Test func addingThenDeletingInTheSameSessionLeavesNothing() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = "7123456789abcdef0123"
        env.editor.addBookmark(Self.displayBookmark(id))
        env.editor.deleteBookmark(id: id)
        let changes = try env.changes()
        #expect(changes.addedParts.isEmpty && changes.reportParts.isEmpty && changes.removedParts.isEmpty)
    }

    @Test func deletingAfterASaveRemovesTheFileWrittenBefore() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = "8123456789abcdef0123"
        env.editor.addBookmark(Self.displayBookmark(id))
        _ = try env.save()
        env.editor.deleteBookmark(id: id)
        let changes = try env.changes()
        #expect(changes.removedParts == [Self.bookmarkPath(id)])
        #expect(String(decoding: changes.reportParts[Self.bookmarksPath]!, as: UTF8.self) == Self.bm1Index)
    }

    @Test func updatingAFileBookmarkRewritesItKeepingNameAndTitle() throws {
        let env = try Env(); defer { env.cleanUp() }
        var fresh = Self.displayBookmark("bm1", name: "bm1")
        fresh.visibility.setHidden(S.a3, true)
        env.editor.updateBookmark(fresh)
        let changes = try env.changes()
        let file = try JSONValue.parse(changes.reportParts[Self.bookmarkPath("bm1")]!)
        #expect(file["name"]?.string == "bm1")
        #expect(file["explorationState"]?["sections"]?["p1"]?["visualContainers"]?[S.a3]?["singleVisual"]?["display"]?["mode"]?.string == "hidden")
        #expect(Set(changes.reportParts.keys) == [Self.bookmarkPath("bm1")])
    }

    @Test func renamingAFileBookmarkWhoseUpdateIsSessionOnlyStillSavesTheNewName() throws {
        let env = try Env(); defer { env.cleanUp() }
        var fresh = Self.displayBookmark("bm1", name: "bm1"); fresh.data = true; fresh.drillDepth["v"] = 1   // Data có drill: chưa ghi được
        env.editor.updateBookmark(fresh)
        #expect(env.editor.renameBookmark(id: "bm1", to: "Tên mới", others: []) == nil)
        _ = try env.save()                       // không được ném verificationFailed
        let file = try env.json(Self.bookmarkPath("bm1"))
        #expect(file["displayName"]?.string == "Tên mới" && file["options"]?["targetVisualNames"]?.array.count == 2)
        #expect(env.editor.saveNotes.count == 1)
    }

    @Test func reorderingBookmarksRewritesOnlyTheIndex() throws {
        let two: [(name: String, json: String)] = [("A", #"{"name":"A","explorationState":{"sections":{}}}"#), ("B", #"{"name":"B","explorationState":{"sections":{}}}"#)]
        let env = try Env(bookmarks: two); defer { env.cleanUp() }
        env.editor.moveBookmarks(order: ["B", "A"])
        let changes = try env.changes()
        #expect(Set(changes.reportParts.keys) == [Self.bookmarksPath])
        #expect(String(decoding: changes.reportParts[Self.bookmarksPath]!, as: UTF8.self) == #"{"items":[{"name":"B"},{"name":"A"}]}"#)
    }

    @Test func deletingAPageDropsAnAddedBookmarkOfThatPage() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = "9123456789abcdef0123"
        env.editor.addBookmark(Self.displayBookmark(id, page: "p2"))
        #expect(env.editor.removePage("p2") == nil)
        let changes = try env.changes()
        #expect(changes.addedParts[Self.bookmarkPath(id)] == nil)
        #expect(!env.editor.saveNotes.isEmpty)
    }

    // MARK: Bộ lọc

    static func sexFilter(_ value: String? = "Female", exclude: Bool = false) -> UserFilter {
        UserFilter(column: QueryColumn(table: "Dim_Client", column: "sex"), values: value.map { [.string($0)] } ?? [], exclude: exclude)
    }

    @Test func addedFiltersGoToTheRightPartAtEachLevel() throws {
        let env = try Env(); defer { env.cleanUp() }
        let page = UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.sex")
        let report = UserFilterKey(level: .report, scope: "", filterID: "added-Dim_Client.sex")
        let visual = UserFilterKey(level: .visual, scope: S.a1, filterID: "added-Dim_Client.sex")
        for key in [page, report, visual] { env.editor.setFilter(Self.sexFilter(), for: key, coalesce: false) }
        let changes = try env.changes()
        #expect(Set(changes.reportParts.keys) == [Self.reportPath, Self.pageP1, S.visualPath("p1", S.a1)] && changes.addedParts.isEmpty)
        let name = FilterExport.cardName(for: page, column: QueryColumn(table: "Dim_Client", column: "sex"))
        #expect(name.count == 20 && name.allSatisfy { $0.isHexDigit })
        for path in [Self.reportPath, Self.pageP1, S.visualPath("p1", S.a1)] {
            let card = try #require(JSONValue.parse(changes.reportParts[path]!)["filterConfig"]?["filters"]?[0])
            #expect(card["type"]?.string == "Categorical" && card["howCreated"]?.string == "User")
            #expect(card["field"]?["Column"]?["Property"]?.string == "sex")
            #expect(card["filter"]?["Where"]?[0]?["Condition"]?["In"]?["Values"]?[0]?[0]?["Literal"]?["Value"]?.string == "'Female'")
        }
    }

    @Test func savingFiltersTwiceWritesTheSecondTimeNothingAndTheFileReadsBack() throws {
        let env = try Env(); defer { env.cleanUp() }
        let key = UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.sex")
        env.editor.setFilter(Self.sexFilter(), for: key, coalesce: false)
        _ = try env.save()
        let again = try env.changes()
        #expect(again.reportParts.isEmpty && again.addedParts.isEmpty && again.removedParts.isEmpty)
        let filters = PBIXFile.filters(try env.json(Self.pageP1)["filterConfig"]?["filters"], level: .page)
        #expect(filters.count == 1 && UserFilter.from(filters[0])?.values == [.string("Female")])
    }

    @Test func changingAnAddedFilterAfterASaveReplacesTheSameCard() throws {
        let env = try Env(); defer { env.cleanUp() }
        let key = UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.sex")
        env.editor.setFilter(Self.sexFilter("Female"), for: key, coalesce: false)
        _ = try env.save()
        env.editor.setFilter(Self.sexFilter("Male", exclude: true), for: key, coalesce: false)
        let changes = try env.changes()
        let filters = try #require(JSONValue.parse(changes.reportParts[Self.pageP1]!)["filterConfig"]?["filters"]?.array)
        #expect(filters.count == 1)
        #expect(filters[0]["filter"]?["Where"]?[0]?["Condition"]?["Not"] != nil)
    }

    @Test func removingAnAddedFilterAfterASaveRestoresThePageJSON() throws {
        let env = try Env(); defer { env.cleanUp() }
        let original = try env.read(Self.pageP1)
        let key = UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.sex")
        env.editor.setFilter(Self.sexFilter(), for: key, coalesce: false)
        _ = try env.save()
        env.editor.removeFilter(key, column: QueryColumn(table: "Dim_Client", column: "sex"))
        _ = try env.save()
        let restored = try env.read(Self.pageP1)
        #expect(restored == original, Comment(rawValue: restored))
    }

    @Test func removingAFileFilterDropsItsCardOnly() throws {
        let page = #"{"name":"p1","displayName":"P1","width":1920,"height":1080,"filterConfig":{"filters":[{"name":"keep","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"year"}},"type":"Categorical"},{"name":"drop","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"sex"}},"type":"Categorical"}]}}"#
        let env = try Env(p1Page: page); defer { env.cleanUp() }
        env.editor.removeFilter(UserFilterKey(level: .page, scope: "p1", filterID: "drop"))
        let changes = try env.changes()
        #expect(String(decoding: changes.reportParts[Self.pageP1]!, as: UTF8.self)
                == #"{"name":"p1","displayName":"P1","width":1920,"height":1080,"filterConfig":{"filters":[{"name":"keep","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"year"}},"type":"Categorical"}]}}"#)
    }

    @Test func editingAFileFilterKeepsItsNameAndOtherKeys() throws {
        let page = #"{"name":"p1","displayName":"P1","width":1920,"height":1080,"filterConfig":{"filters":[{"name":"fSex","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"sex"}},"type":"Categorical","isLockedInViewMode":true}]}}"#
        let env = try Env(p1Page: page); defer { env.cleanUp() }
        env.editor.setFilter(Self.sexFilter("Female"), for: UserFilterKey(level: .page, scope: "p1", filterID: "fSex"), coalesce: false)
        let card = try #require(JSONValue.parse(try env.changes().reportParts[Self.pageP1]!)["filterConfig"]?["filters"]?[0])
        #expect(card["name"]?.string == "fSex" && card["isLockedInViewMode"]?.bool == true && card["filter"] != nil)
    }

    @Test func aFilterOnDateValuesStaysInTheSessionWithAReason() throws {
        let env = try Env(); defer { env.cleanUp() }
        let dates = UserFilter(column: QueryColumn(table: "Dim_Date", column: "date"), values: [.dateTime(1)])
        env.editor.setFilter(dates, for: UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Date.date"), coalesce: false)
        let changes = try env.changes()
        #expect(changes.reportParts.isEmpty && changes.addedParts.isEmpty)
        #expect(env.editor.saveNotes.count == 1)
    }

    /// VM-D8: so sánh số, "Hoặc", Bottom N và thẻ measure nay ghi vào file; lưu xong đọc lại ra đúng bộ lọc đã đặt.
    @Test func numericOrBottomNAndMeasureFiltersAreSavedAndReadBack() throws {
        let env = try Env(); defer { env.cleanUp() }
        let numeric = UserFilter(column: QueryColumn(table: "Dim_Date", column: "year"),
                                 rule: .advanced(first: FilterCondition(kind: .greaterThan, operand: "2014"),
                                                 second: FilterCondition(kind: .isBlank, operand: ""), useOr: true, numeric: true))
        let bottom = UserFilter(column: QueryColumn(table: "Dim_CRM_Issue", column: "product"),
                                rule: .topN(TopNRule(count: 2, top: false, measureTable: "Fact_CRM_Complaint", measureName: "Complaints")))
        let measure = UserFilter(column: QueryColumn(table: "F", column: "M"),
                                 rule: .advanced(first: FilterCondition(kind: .lessOrEqual, operand: "0.5"), second: nil, useOr: false, numeric: true), isMeasure: true)
        env.editor.setFilter(numeric, for: UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Date.year"), coalesce: false)
        env.editor.setFilter(bottom, for: UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_CRM_Issue.product"), coalesce: false)
        env.editor.setFilter(measure, for: UserFilterKey(level: .visual, scope: S.a1, filterID: "implicit-F.M-Y"), coalesce: false)
        _ = try env.save()
        #expect(env.editor.saveNotes.isEmpty)

        let page = PBIXFile.filters(try env.json(Self.pageP1)["filterConfig"]?["filters"], level: .page).compactMap(UserFilter.from)
        #expect(Set(page) == [numeric, bottom])
        let cards = try #require(try env.json(S.visualPath("p1", S.a1))["filterConfig"]?["filters"]?.array)
        #expect(cards.count == 1 && cards[0]["field"]?["Measure"]?["Property"]?.string == "M" && cards[0]["howCreated"] == nil)
        #expect(PBIXFile.filters(.array(cards), level: .visual).compactMap(UserFilter.from) == [measure])

        let again = try env.changes()
        #expect(again.reportParts.isEmpty && again.addedParts.isEmpty && again.removedParts.isEmpty)
    }

    @Test func advancedTextAndTopNAreWritable() throws {
        let env = try Env(); defer { env.cleanUp() }
        let adv = UserFilter(column: QueryColumn(table: "Dim_Client", column: "sex"),
                             rule: .advanced(first: FilterCondition(kind: .startsWith, operand: "Fem"), second: nil, useOr: false, numeric: false))
        let top = UserFilter(column: QueryColumn(table: "Dim_CRM_Issue", column: "product"),
                             rule: .topN(TopNRule(count: 1, top: true, measureTable: "Fact_CRM_Complaint", measureName: "Complaints")))
        env.editor.setFilter(adv, for: UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.sex"), coalesce: false)
        env.editor.setFilter(top, for: UserFilterKey(level: .visual, scope: S.a1, filterID: "added-Dim_CRM_Issue.product"), coalesce: false)
        let changes = try env.changes()
        #expect(env.editor.saveNotes.isEmpty)
        let pageCard = try #require(JSONValue.parse(changes.reportParts[Self.pageP1]!)["filterConfig"]?["filters"]?[0])
        #expect(pageCard["type"]?.string == "Advanced" && pageCard["filter"]?["Where"]?[0]?["Condition"]?["StartsWith"] != nil)
        let visualCard = try #require(JSONValue.parse(changes.reportParts[S.visualPath("p1", S.a1)]!)["filterConfig"]?["filters"]?[0])
        #expect(visualCard["type"]?.string == "TopN")
    }

    @Test func filterEditsOfADeletedVisualOrPageAreDropped() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFilter(Self.sexFilter(), for: UserFilterKey(level: .visual, scope: S.a1, filterID: "added-Dim_Client.sex"), coalesce: false)
        env.editor.setFilter(Self.sexFilter(), for: UserFilterKey(level: .page, scope: "p2", filterID: "added-Dim_Client.sex"), coalesce: false)
        env.editor.delete([S.a1])
        #expect(env.editor.removePage("p2") == nil)
        let changes = try env.changes()
        #expect(changes.reportParts[S.visualPath("p1", S.a1)] == nil && changes.reportParts[Self.pagePath("p2")] == nil)
    }
    static func pagePath(_ id: String) -> String { "Report/definition/pages/\(id)/page.json" }
}
