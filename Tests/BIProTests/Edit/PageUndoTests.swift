import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Hoàn tác toàn trạng thái (D5): `specs/005-d5-quan-ly-trang/research.md` R2.
@Suite @MainActor struct PageUndoTests {
    static func newPage(_ id: String, name: String = "Page 1") -> NewPage {
        NewPage(id: id, displayName: name, pageJSON: PBIRPagePatch.newPageJSON(id: id, displayName: name, schema: nil),
                sourcePage: nil, width: 1920, height: 1080)
    }

    /// Thêm một trang trống ở cuối bằng thao tác cấp cấu trúc (thao tác thật đến ở giai đoạn 3).
    @discardableResult
    static func addPage(_ editor: LayoutEditor, id: String = "np1") -> Bool {
        let changed = editor.commitStructure { structure, edited in
            structure.created[id] = newPage(id)
            structure.order.append(id)
            edited[id] = PageEdit(visuals: [])
        }
        if changed { editor.openPage(id) }
        return changed
    }

    @Test func aStructureStepIsOneUndoStepAndRestoresThePageAndSelection() {
        let e = LayoutEditorTests.makeEditor()
        e.select("a")
        let depth = e.undoDepth
        #expect(Self.addPage(e))
        #expect(e.undoDepth == depth + 1 && e.isDirty)
        #expect(e.pages.map(\.id) == ["p1", "p2", "np1"] && e.currentPageID == "np1")
        e.undo()
        #expect(e.pages.map(\.id) == ["p1", "p2"] && e.currentPageID == "p1")
        #expect(e.selection == ["a"] && !e.isDirty)
        e.redo()
        #expect(e.pages.map(\.id) == ["p1", "p2", "np1"] && e.currentPageID == "np1" && e.isDirty)
        #expect(e.page("np1")?.displayName == "Page 1")
    }

    @Test func undoAndRedoClearTheStaleMessage() {
        let e = LayoutEditorTests.makeEditor()
        #expect(Self.addPage(e))
        e.setNotice("Đã xoá trang \"X\".")
        e.undo()
        #expect(e.notice == nil && e.fieldRefusal == nil)
        e.setNotice("Đã thêm trang.")
        e.redo()
        #expect(e.notice == nil)
    }

    @Test func pageEditsAndStructureEditsShareOneStack() {
        let e = LayoutEditorTests.makeEditor()
        e.select("a")
        e.move(["a"], dx: 16, dy: 0, snap: false)
        let moved = e.visual("a")?.x
        Self.addPage(e)
        e.undo()                                  // bỏ trang mới
        #expect(e.pages.map(\.id) == ["p1", "p2"] && e.visual("a", page: "p1")?.x == moved)
        e.undo()                                  // bỏ lần kéo
        #expect(e.visual("a", page: "p1")?.x == 40 && !e.isDirty)
        e.redo(); e.redo()
        #expect(e.pages.count == 3 && e.visual("a", page: "p1")?.x == moved)
    }

    @Test func aNoOpStructureStepMakesNoStep() {
        let e = LayoutEditorTests.makeEditor()
        let depth = e.undoDepth
        #expect(!e.commitStructure { _, _ in })
        #expect(e.undoDepth == depth && !e.isDirty)
    }

    @Test func aNewPageTakesVisualEditsLikeAnyPage() {
        let e = LayoutEditorTests.makeEditor()
        Self.addPage(e)
        #expect(e.visuals(of: "np1").isEmpty && e.page("np1")?.width == 1920)
        // thêm visual vào trang mới: chạy trên cùng bộ máy của D3
        let id = e.insertVisual(type: "card", visibleRect: nil)
        #expect(id != nil && e.visuals(of: "np1").count == 1)
        e.undo()
        #expect(e.visuals(of: "np1").isEmpty && e.pages.count == 3)
        e.undo()
        #expect(e.pages.count == 2)
    }

    @Test func renamedPagesCarryTheirNameThroughUndo() {
        let e = LayoutEditorTests.makeEditor()
        e.commitStructure { structure, _ in structure.renamed["p2"] = "Hai" }
        #expect(e.page("p2")?.displayName == "Hai" && e.pages.map(\.displayName) == ["P1", "Hai"])
        e.undo()
        #expect(e.page("p2")?.displayName == "P2")
    }

    @Test func undoOfTheOnlyStepGoesBackToTheCleanStateEvenAfterSwitchingPages() {
        let e = LayoutEditorTests.makeEditor()
        e.commitStructure { structure, _ in structure.order = ["p2", "p1"] }
        e.openPage("p2")
        e.undo()
        #expect(e.pages.map(\.id) == ["p1", "p2"] && !e.isDirty && e.currentPageID == "p1")
    }

    @Test func historyLimitStillHoldsWithStructureSteps() {
        let e = LayoutEditorTests.makeEditor()
        for index in 0..<(LayoutEditor.historyLimit + 5) {
            e.commitStructure { structure, _ in structure.renamed["p1"] = "N\(index)" }
        }
        #expect(e.undoDepth == LayoutEditor.historyLimit)
    }

    // MARK: chuỗi hỗn hợp với D1 đến D3 (T034)

    /// Chữ ký của trạng thái: trang (mã, tên), visual (mã, khung, loại) của từng trang, trang đang mở.
    static func signature(_ e: LayoutEditor) -> String {
        let pages = e.pages.map { page in
            "\(page.id)|\(page.displayName)|" + page.visuals.map { "\($0.id):\(Frame($0)):\($0.type)" }.sorted().joined(separator: ",")
        }
        return pages.joined(separator: "\n") + "\ncurrent=\(e.currentPageID ?? "-")"
    }

    @Test func aMixedHistoryUndoesAndRedoesStepByStepInReverseOrder() throws {
        let env = try PageSavingTests.Env(bookmarks: PageRemoveTests.bookmarks); defer { env.cleanUp() }
        let e = env.editor
        var states = [Self.signature(e)]
        func step(_ label: String, _ body: () -> Void) {
            let before = e.undoDepth
            body()
            #expect(e.undoDepth == before + 1, Comment(rawValue: "\(label) phải là đúng một bước"))
            states.append(Self.signature(e))
        }
        e.select(SyntheticReport.a1)
        step("kéo visual") { e.move([SyntheticReport.a1], dx: 24, dy: 0, snap: false) }
        step("thêm visual") { _ = e.insertVisual(type: "card", visibleRect: nil) }
        step("thêm trang") { _ = e.addPage() }
        step("đổi tên trang") { _ = e.renamePage(e.currentPageID ?? "", to: "Mới") }
        step("nhân bản trang") { _ = e.duplicatePage("p1") }
        step("kéo trang") { _ = e.movePage(e.currentPageID ?? "", to: 0) }
        step("xoá trang") { _ = e.removePage("p2") }
        step("thêm visual vào trang mới") { _ = e.insertVisual(type: "slicer", visibleRect: nil) }
        let usedPages = e.usedPageIDs, usedVisuals = e.usedIDs
        // hoàn tác từng bước về đúng trạng thái trước nó
        for index in stride(from: states.count - 1, to: 0, by: -1) {
            #expect(Self.signature(e) == states[index], Comment(rawValue: "trước hoàn tác bước \(index)"))
            e.undo()
            #expect(Self.signature(e) == states[index - 1], Comment(rawValue: "sau hoàn tác bước \(index)"))
        }
        #expect(!e.isDirty && !e.canUndo)
        // làm lại từng bước
        for index in 1..<states.count {
            e.redo()
            #expect(Self.signature(e) == states[index], Comment(rawValue: "sau làm lại bước \(index)"))
        }
        #expect(e.isDirty && !e.canRedo)
        // mã đã dùng không mất và không dùng lại
        #expect(e.usedPageIDs.isSuperset(of: usedPages) && e.usedIDs.isSuperset(of: usedVisuals))
        let again = try #require(e.addPage())
        #expect(!usedPages.contains(again))
    }

    @Test func undoingBackToTheSavedStateIsCleanEvenWithPageSteps() throws {
        let env = try PageSavingTests.Env(); defer { env.cleanUp() }
        let e = env.editor
        _ = e.addPage()
        _ = try env.save()                                  // trạng thái sạch ở đây
        #expect(!e.isDirty)
        #expect(e.renamePage(e.currentPageID ?? "", to: "Đổi") == nil)
        #expect(e.isDirty)
        e.undo()
        #expect(!e.isDirty)
        e.undo()                                            // quay về trước lần lưu: bẩn lại
        #expect(e.isDirty)
        e.redo()
        #expect(!e.isDirty)
    }

    @Test func dragCoalescingDoesNotSwallowPageSteps() throws {
        let env = try PageSavingTests.Env(); defer { env.cleanUp() }
        let e = env.editor
        e.select(SyntheticReport.a1)
        var clock = Date(timeIntervalSince1970: 1_000_000)
        e.now = { clock }
        e.move([SyntheticReport.a1], dx: 8, dy: 0, snap: false, coalescing: true)
        clock = clock.addingTimeInterval(0.1)
        #expect(e.movePage("p2", to: 0) == nil)
        clock = clock.addingTimeInterval(0.1)
        e.move([SyntheticReport.a1], dx: 8, dy: 0, snap: false, coalescing: true)
        #expect(e.undoDepth == 3)                           // kéo, kéo trang, kéo (không gộp xuyên thao tác trang)
    }
}

