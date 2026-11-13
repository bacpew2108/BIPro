import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Thao tác trang (D5): `specs/005-d5-quan-ly-trang/contracts/page-operations.md`.
@Suite @MainActor struct PageOperationsTests {
    static func editor(hiddenPage: Bool = false) -> LayoutEditor {
        var report = LayoutEditorTests.report()
        if hiddenPage { report.pages[1].isHidden = true }
        let editor = LayoutEditor(report: report)
        editor.showPage("p1")
        return editor
    }

    // MARK: thêm

    @Test func addPageAppendsAnEmptyPageAndOpensIt() throws {
        let e = Self.editor()
        e.select("a")
        let depth = e.undoDepth
        let id = try #require(e.addPage())
        #expect(PBIRLayoutPatch.isValidVisualName(id) && id.count == 20)
        #expect(e.pages.map(\.id) == ["p1", "p2", id] && e.currentPageID == id)
        let page = try #require(e.page(id))
        #expect(page.displayName == "Page 1" && page.width == 1920 && page.height == 1080 && page.visuals.isEmpty)
        #expect(e.selection.isEmpty && e.undoDepth == depth + 1 && e.isDirty && e.fieldRefusal == nil)
        let second = try #require(e.addPage())
        #expect(second != id && e.page(second)?.displayName == "Page 2")
        e.undo(); e.undo()
        #expect(e.pages.map(\.id) == ["p1", "p2"] && !e.isDirty)
        // mã đã dùng không bao giờ dùng lại, kể cả sau hoàn tác
        #expect(e.usedPageIDs.isSuperset(of: [id, second]))
    }

    @Test func addedPageTakesVisualsAndItsNameFollowsTheLargestPageNumber() throws {
        let e = Self.editor()
        let id = try #require(e.addPage())
        #expect(e.insertVisual(type: "card", visibleRect: nil) != nil && e.visuals(of: id).count == 1)
        #expect(e.renamePage(id, to: "Page 7") == nil)
        #expect(e.page(try #require(e.addPage()))?.displayName == "Page 8")
    }

    // MARK: đổi tên

    @Test func renameChangesTheNameAndKeepsTheID() throws {
        let e = Self.editor()
        let depth = e.undoDepth
        #expect(e.renamePage("p2", to: "  Hai · Việt  ") == nil)
        #expect(e.page("p2")?.displayName == "Hai · Việt" && e.pages.map(\.id) == ["p1", "p2"])
        #expect(e.undoDepth == depth + 1 && e.isDirty)
        // tên cũ trả lại: không còn khác file
        #expect(e.renamePage("p2", to: "P2") == nil)
        #expect(e.structure.renamed.isEmpty)
        e.undo(); e.undo()
        #expect(e.page("p2")?.displayName == "P2" && !e.isDirty)
    }

    @Test func renameRefusalsAndNoOpsMakeNoStep() throws {
        let e = Self.editor()
        let depth = e.undoDepth
        #expect(e.renamePage("p1", to: "   ")?.contains("để trống") == true)
        #expect(e.fieldRefusal?.contains("để trống") == true)
        #expect(e.renamePage("p1", to: String(repeating: "x", count: 101))?.contains("100") == true)
        #expect(e.renamePage("zz", to: "A") != nil)
        #expect(e.renamePage("p1", to: "P1") == nil)          // không đổi
        #expect(e.undoDepth == depth && !e.isDirty)
        // tên trùng trang khác được phép
        #expect(e.renamePage("p2", to: "P1") == nil && e.pages.map(\.displayName) == ["P1", "P1"])
    }

    @Test func renamingANewPageUpdatesItsPageJSON() throws {
        let e = Self.editor()
        let id = try #require(e.addPage())
        #expect(e.renamePage(id, to: "Tên \"mới\"") == nil)
        let json = try #require(e.structure.created[id]?.pageJSON)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["displayName"] as? String == "Tên \"mới\"" && object["name"] as? String == id)
    }

    @Test func hiddenPagesRenameAndMoveLikeAnyPage() throws {
        let e = Self.editor(hiddenPage: true)
        #expect(e.renamePage("p2", to: "Ẩn") == nil && e.movePage("p2", to: 0) == nil)
        #expect(e.pages.map(\.id) == ["p2", "p1"] && e.page("p2")?.isHidden == true)
    }

    // MARK: đổi thứ tự

    @Test func moveChangesTheOrderAndKeepsTheOpenPage() throws {
        let e = Self.editor()
        let extra = try #require(e.addPage())
        e.openPage("p1")
        let depth = e.undoDepth
        #expect(e.movePage(extra, to: 0) == nil)
        #expect(e.pages.map(\.id) == [extra, "p1", "p2"] && e.currentPageID == "p1" && e.undoDepth == depth + 1)
        #expect(e.movePage("p1", to: 2) == nil)
        #expect(e.pages.map(\.id) == [extra, "p2", "p1"])
        e.undo()
        #expect(e.pages.map(\.id) == [extra, "p1", "p2"])
    }

    @Test func moveRefusalsAndNoOps() {
        let e = Self.editor()
        let depth = e.undoDepth
        #expect(e.movePage("p1", to: 5) != nil && e.movePage("p1", to: -1) != nil && e.movePage("zz", to: 0) != nil)
        #expect(e.movePage("p1", to: 0) == nil)               // cùng chỗ
        #expect(e.undoDepth == depth && e.pages.map(\.id) == ["p1", "p2"])
    }

    // MARK: điều kiện sửa

    @Test func editingIsBlockedInViewModeAndForLegacyReports() {
        #expect(PageEditing.blocker(editMode: true, canEditLayout: true, mode: .report) == nil)
        #expect(PageEditing.blocker(editMode: false, canEditLayout: true, mode: .report)?.contains("⌘E") == true)
        #expect(PageEditing.blocker(editMode: true, canEditLayout: false, mode: .report)?.contains("định dạng cũ") == true)
        #expect(PageEditing.blocker(editMode: true, canEditLayout: true, mode: .table) != nil)
    }

    // MARK: kéo tab (review D5 c)

    @Test func aTabDropTakesOnlyATabOfTheSameDocument() {
        let document = UUID(), other = UUID()
        let dragged = PageTabDrag.payload(page: "p2", document: document)
        #expect(PageTabDrag.page(from: dragged, document: document, pages: ["p1", "p2"]) == "p2")
        #expect(PageTabDrag.page(from: dragged, document: other, pages: ["p1", "p2"]) == nil)            // tab của cửa sổ khác
        #expect(PageTabDrag.page(from: "page:p2", document: document, pages: ["p1", "p2"]) == nil)       // chữ kéo từ nơi khác
        #expect(PageTabDrag.page(from: "p2", document: document, pages: ["p1", "p2"]) == nil)
        let gone = PageTabDrag.payload(page: "p9", document: document)
        #expect(PageTabDrag.page(from: gone, document: document, pages: ["p1", "p2"]) == nil)            // trang không còn trong dãy
    }
}

// MARK: nhân bản trang (D5, US2)

@Suite @MainActor struct PageDuplicateTests {
    typealias Env = PageSavingTests.Env
    static let group = "gggggggggggggggggggg"
    static let child = "hhhhhhhhhhhhhhhhhhhh"

    static var drillPage: String {
        #"{"name":"p1","displayName":"P1","width":1920,"height":1080,"filterConfig":{"filters":[{"name":"f"}]},"visualInteractions":[{"source":"\#(SyntheticReport.a1)","target":"\#(SyntheticReport.a2)","type":"NoFilter"}],"pageBinding":{"name":"b","type":"Drillthrough","parameters":[]}}"#
    }

    static func groupedExtras() -> [(path: String, data: Data)] {
        [(SyntheticReport.visualPath("p1", group), Data(#"{"name":"\#(group)","position":{"x":0,"y":0,"z":9000,"height":200,"width":300,"tabOrder":9000},"visualGroup":{"displayName":"G"}}"#.utf8)),
         (SyntheticReport.visualPath("p1", child), Data(#"{"name":"\#(child)","position":{"x":218.8235294117647,"y":145.41176470588235,"z":9100,"height":40,"width":40,"tabOrder":9100},"parentGroupName":"\#(group)","visual":{"visualType":"card"}}"#.utf8))]
    }

    @Test func duplicatePageCopiesEveryVisualWithNewIDs() throws {
        let env = try Env(); defer { env.cleanUp() }
        let source = try #require(env.editor.page("p1"))
        let depth = env.editor.undoDepth
        let id = try #require(env.editor.duplicatePage("p1"))
        #expect(env.editor.pages.map(\.id) == ["p1", "p2", id] && env.editor.currentPageID == id)
        let copy = try #require(env.editor.page(id))
        #expect(copy.displayName == "Duplicate of P1" && copy.width == source.width && copy.visuals.count == source.visuals.count)
        let oldIDs = Set(source.visuals.map(\.id))
        #expect(oldIDs.isDisjoint(with: copy.visuals.map(\.id)) && Set(copy.visuals.map(\.id)).count == copy.visuals.count)
        #expect(copy.visuals.allSatisfy { PBIRLayoutPatch.isValidVisualName($0.id) })
        for (a, b) in zip(source.visuals, copy.visuals) {
            #expect(Frame(a) == Frame(b) && a.z == b.z && a.type == b.type && a.fields == b.fields)
            #expect(b.raw["name"]?.string == b.id)
        }
        #expect(env.editor.page("p1")?.visuals.map(\.id) == source.visuals.map(\.id))          // trang gốc không đổi
        #expect(env.editor.undoDepth == depth + 1 && env.editor.notice == nil)
        env.editor.undo()
        #expect(env.editor.pages.map(\.id) == ["p1", "p2"] && !env.editor.isDirty)
        env.editor.redo()
        #expect(env.editor.page(id)?.visuals.count == source.visuals.count)
    }

    @Test func editsNotYetSavedComeAlongWithTheCopy() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.select(SyntheticReport.a1)
        env.editor.move([SyntheticReport.a1], dx: 24, dy: 8, snap: false)
        let movedFrame = Frame(try #require(env.editor.visual(SyntheticReport.a1)))
        let card = try #require(env.editor.insertVisual(type: "card", visibleRect: nil))
        let id = try #require(env.editor.duplicatePage("p1"))
        let copy = try #require(env.editor.page(id))
        #expect(copy.visuals.count == 4)                                       // 3 gốc + 1 thêm; (a1 đã kéo)
        #expect(copy.visuals.contains { Frame($0) == movedFrame })
        #expect(copy.visuals.contains { $0.type == "card" && $0.id != card })
    }

    @Test func groupChildrenFollowTheirCopiedGroup() throws {
        let env = try Env(p1Page: Self.drillPage, extra: Self.groupedExtras()); defer { env.cleanUp() }
        let id = try #require(env.editor.duplicatePage("p1"))
        let copy = try #require(env.editor.page(id))
        let child = try #require(copy.visuals.first { $0.parentGroup != nil })
        // nhóm (D7): có trong `groups` của bản sao với mã mới; con trỏ vào nhóm mới
        #expect(copy.groups.count == 1)
        let groupID = try #require(copy.groups.first?.id)
        #expect(groupID != Self.group && child.parentGroup == groupID && child.raw["parentGroupName"]?.string == groupID)
        // số thực của vị trí giữ nguyên chữ trong bản ghi
        let changes = try env.editor.makeChanges(archive: env.archive)
        let text = String(decoding: try #require(changes.addedParts[LayoutEditor.visualPath(page: id, id: child.id)]), as: UTF8.self)
        #expect(text.contains(#""x":218.8235294117647,"y":145.41176470588235"#))
        #expect(changes.addedParts[LayoutEditor.visualPath(page: id, id: groupID)] != nil)
        // nhân bản tiếp trang bản sao: nhóm theo sang
        let again = try #require(env.editor.duplicatePage(id))
        #expect(env.editor.page(again)?.groups.count == 1)
    }

    @Test func aDrillthroughPageIsCopiedWithoutItsBindingAndTheUserIsTold() throws {
        let env = try Env(p1Page: Self.drillPage); defer { env.cleanUp() }
        let id = try #require(env.editor.duplicatePage("p1"))
        #expect(env.editor.notice?.contains("drillthrough") == true)
        let json = try #require(env.editor.structure.created[id]?.pageJSON)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["pageBinding"] == nil && object["filterConfig"] != nil)
        let copy = try #require(env.editor.page(id))
        let interactions = try #require(object["visualInteractions"] as? [[String: Any]])
        let ids = copy.visuals.map(\.id)
        #expect(interactions.count == 1 && ids.contains(interactions[0]["source"] as? String ?? "") && ids.contains(interactions[0]["target"] as? String ?? ""))
        #expect(!ids.contains(SyntheticReport.a1))
    }

    @Test func aNewPageCanBeDuplicatedAndRenamedCopiesKeepTheirName() throws {
        let env = try Env(); defer { env.cleanUp() }
        let page = try #require(env.editor.addPage())
        _ = env.editor.insertVisual(type: "card", visibleRect: nil)
        #expect(env.editor.renamePage(page, to: "Mới") == nil)
        let copy = try #require(env.editor.duplicatePage(page))
        #expect(env.editor.page(copy)?.displayName == "Duplicate of Mới" && env.editor.page(copy)?.visuals.count == 1)
        // trang của file đã đổi tên: bản sao theo tên mới
        #expect(env.editor.renamePage("p2", to: "Hai") == nil)
        let two = try #require(env.editor.duplicatePage("p2"))
        #expect(env.editor.page(two)?.displayName == "Duplicate of Hai")
    }

    @Test func aMissingSourceIsRefusedWithoutAStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.duplicatePage("zz") == nil && env.editor.fieldRefusal != nil)
        #expect(env.editor.undoDepth == depth)
    }
}

// MARK: xoá trang (D5, US3)

@Suite @MainActor struct PageRemoveTests {
    typealias Env = PageSavingTests.Env

    static func bookmark(_ name: String, display: String, active: String, sections: [String]) -> (name: String, json: String) {
        let body = sections.map { #""\#($0)":{"visualContainers":{}}"# }.joined(separator: ",")
        return (name, #"{"name":"\#(name)","displayName":"\#(display)","options":{"targetVisualNames":["\#(SyntheticReport.a1)"]},"explorationState":{"version":"1.3","activeSection":"\#(active)","sections":{\#(body)}}}"#)
    }

    /// A trỏ p1 (gỡ), B có p1 và p2 với trang chính p2 (chỉ bỏ mục), C chỉ p2 (giữ).
    static var bookmarks: [(name: String, json: String)] {
        [bookmark("A", display: "Bookmark A", active: "p1", sections: ["p1"]),
         bookmark("B", display: "Bookmark B", active: "p2", sections: ["p1", "p2"]),
         bookmark("C", display: "Bookmark C", active: "p2", sections: ["p2"])]
    }

    static func navigationButton(to page: String) -> [(path: String, data: Data)] {
        let link = #"[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"type":{"expr":{"Literal":{"Value":"'PageNavigation'"}}},"navigationSection":{"expr":{"Literal":{"Value":"'\#(page)'"}}}}}]"#
        let json = #"{"name":"nnnnnnnnnnnnnnnnnnnn","position":{"x":0,"y":0,"z":8000,"height":30,"width":90,"tabOrder":8000},"visual":{"visualType":"actionButton","visualContainerObjects":{"visualLink":\#(link)}}}"#
        return [(SyntheticReport.visualPath("p1", "nnnnnnnnnnnnnnnnnnnn"), Data(json.utf8))]
    }

    @Test func removeDropsThePageAndOpensTheRightNeighbour() throws {
        let env = try Env(bookmarks: Self.bookmarks); defer { env.cleanUp() }
        let extra = try #require(env.editor.addPage())
        env.editor.openPage("p2")
        let depth = env.editor.undoDepth
        #expect(env.editor.removePage("p2") == nil)
        #expect(env.editor.pages.map(\.id) == ["p1", extra] && env.editor.currentPageID == extra)   // bên phải
        #expect(env.editor.undoDepth == depth + 1 && env.editor.isDirty)
        #expect(env.editor.removePage(extra) == nil)
        #expect(env.editor.currentPageID == "p1")                                                  // trang cuối: bên trái
        #expect(env.editor.structure.created.isEmpty)                                              // trang tạo trong phiên biến hẳn
        #expect(env.editor.structure.removed == ["p2"])
    }

    /// VM-D8: Desktop xoá trang mà không cảnh báo và để nguyên nút điều hướng trỏ tới nó. BI Pro làm theo và nói nút nào.
    @Test func aPageANavigationButtonPointsAtCanBeRemovedAndTheUserIsToldWhichButton() throws {
        let env = try Env(extra: Self.navigationButton(to: "p2")); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.removePage("p2") == nil)
        #expect(env.editor.pages.map(\.id) == ["p1"] && env.editor.undoDepth == depth + 1)
        #expect(env.editor.notice?.contains("nút điều hướng") == true && env.editor.notice?.contains("nnnnnnnnnnnnnnnnnnnn") == true)
        env.editor.undo()
        #expect(env.editor.pages.map(\.id) == ["p1", "p2"])
    }

    @Test func theLastPageCannotBeRemoved() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.removePage("p1") == nil)
        let reason = env.editor.removePage("p2")
        #expect(reason?.contains("ít nhất một trang") == true && env.editor.fieldRefusal == reason)
        #expect(env.editor.pages.count == 1 && env.editor.undoDepth == depth + 1)
    }

    @Test func bookmarksOfARemovedPageAreRemovedOrTrimmedAndTheUserIsTold() throws {
        let env = try Env(bookmarks: Self.bookmarks); defer { env.cleanUp() }
        #expect(env.editor.removePage("p1") == nil)
        #expect(env.editor.structure.removedBookmarks == ["A"] && env.editor.structure.trimmedBookmarkSections == ["B": ["p1"]])
        let notice = try #require(env.editor.notice)
        #expect(notice.contains("Bookmark A") && notice.contains("1 bookmark") && notice.contains("Bookmark B"))
        // không có bookmark bị ảnh hưởng: không có thông báo
        let quiet = try Env(bookmarks: Self.bookmarks); defer { quiet.cleanUp() }
        #expect(quiet.editor.removePage("p2") == nil)
        #expect(quiet.editor.structure.removedBookmarks == ["B", "C"])   // trang chính của B và C là p2
    }

    @Test func undoRestoresThePageItsEditsAndTheBookmarks() throws {
        let env = try Env(bookmarks: Self.bookmarks); defer { env.cleanUp() }
        env.editor.select(SyntheticReport.a1)
        env.editor.move([SyntheticReport.a1], dx: 40, dy: 0, snap: false)
        let moved = Frame(try #require(env.editor.visual(SyntheticReport.a1)))
        let beforeRemove = env.editor.pages.map(\.id)
        #expect(env.editor.removePage("p1") == nil)
        #expect(!env.editor.pages.map(\.id).contains("p1") && env.editor.currentPageID == "p2")
        env.editor.undo()
        #expect(env.editor.pages.map(\.id) == beforeRemove && env.editor.currentPageID == "p1")
        #expect(Frame(try #require(env.editor.visual(SyntheticReport.a1))) == moved)               // phần sửa chưa lưu còn
        #expect(env.editor.structure.removedBookmarks.isEmpty && env.editor.structure.trimmedBookmarkSections.isEmpty && env.editor.structure.removed.isEmpty)
        env.editor.redo()
        #expect(!env.editor.pages.map(\.id).contains("p1") && env.editor.structure.removedBookmarks == ["A"])
    }

    @Test func hiddenAndDrillthroughPagesAreRemovedLikeAnyPage() throws {
        let env = try Env(p1Page: PageDuplicateTests.drillPage); defer { env.cleanUp() }
        #expect(env.editor.removePage("p1") == nil && env.editor.pages.map(\.id) == ["p2"])
    }

    @Test func aRemovedBookmarkStaysOutOfTheLaterImpactOfAnotherRemoval() throws {
        let env = try Env(bookmarks: Self.bookmarks); defer { env.cleanUp() }
        #expect(env.editor.removePage("p1") == nil)
        #expect(env.editor.addPage() != nil)
        #expect(env.editor.removePage("p2") == nil)
        #expect(env.editor.structure.removedBookmarks == ["A", "B", "C"])
    }
}
