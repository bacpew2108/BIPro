import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Logic sửa bố cục (không cần cửa sổ): `specs/002-d1-canvas-luu-t1/contracts/layout-editing.md`.
@Suite @MainActor struct LayoutEditorTests {
    static func visual(_ id: String, x: Double = 0, y: Double = 0, w: Double = 100, h: Double = 50, z: Double,
                       hidden: Bool = false, group: String? = nil) -> ReportVisual {
        var raw: JSONValue = .null
        if let group { raw = .object(["parentGroupName": .string(group), "name": .string(id)]) }
        return ReportVisual(id: id, type: "card", x: x, y: y, z: z, width: w, height: h, isHidden: hidden, raw: raw, parentGroup: group)
    }

    static func report() -> ReportDefinition {
        ReportDefinition(pages: [
            ReportPage(id: "p1", displayName: "P1", width: 1920, height: 1080, visuals: [
                visual("a", x: 40, y: 40, z: 1000),
                visual("b", x: 200, y: 40, w: 150, h: 80, z: 2000),
                visual("c", x: 400, y: 400, z: 3000),
                visual("hid", x: 40, y: 40, z: 4000, hidden: true),
                visual("kid", x: 10, y: 10, z: 5000, group: "grp"),
            ]),
            ReportPage(id: "p2", displayName: "P2", width: 1280, height: 720, visuals: [
                visual("d", x: 8, y: 8, z: 1000),
            ]),
        ])
    }

    static func makeEditor() -> LayoutEditor {
        let editor = LayoutEditor(report: report())
        editor.showPage("p1")
        return editor
    }

    // MARK: chọn

    @Test func selectOneReplacesSelectionAndSetsPrimary() {
        let e = Self.makeEditor()
        e.select("a")
        #expect(e.selection == ["a"] && e.primary == "a")
        e.select("b")
        #expect(e.selection == ["b"] && e.primary == "b")
    }

    @Test func selectWithExtendTogglesMembership() {
        let e = Self.makeEditor()
        e.select("a")
        e.select("b", extend: true)
        #expect(e.selection == ["a", "b"] && e.primary == "b")
        e.select("a", extend: true)
        #expect(e.selection == ["b"] && e.primary == "b")
        e.select("b", extend: true)
        #expect(e.selection.isEmpty && e.primary == nil)
    }

    @Test func clearSelectionAndUnknownIDs() {
        let e = Self.makeEditor()
        e.select("a")
        e.select("nope")
        #expect(e.selection == ["a"], "mã không có trong trang bị bỏ qua")
        e.clearSelection()
        #expect(e.selection.isEmpty && e.primary == nil)
    }

    @Test func setSelectionTakesVisualsOfTheCurrentPageOnly() {
        let e = Self.makeEditor()
        e.setSelection(["a", "c", "d", "zzz"], extend: false)
        #expect(e.selection == ["a", "c"])
        e.setSelection(["b"], extend: true)
        #expect(e.selection == ["a", "b", "c"])
    }

    @Test func switchingPageClearsSelection() {
        let e = Self.makeEditor()
        e.select("a")
        e.showPage("p2")
        #expect(e.selection.isEmpty && e.primary == nil && e.currentPageID == "p2")
        e.select("d")
        #expect(e.selection == ["d"])
    }

    @Test func hiddenVisualsCanBeSelectedFromThePane() {
        let e = Self.makeEditor()
        e.select("hid")
        #expect(e.selection == ["hid"])
    }

    // MARK: di chuyển và đổi cỡ

    @Test func moveUpdatesOnlyTheCurrentPageCopy() {
        let e = Self.makeEditor()
        #expect(e.edited.isEmpty, "trang chưa đụng tới không có bản sao")
        e.move(["a"], dx: 45, dy: 3, snap: true)
        #expect(e.edited.keys.sorted() == ["p1"])
        let a = e.visual("a")!
        #expect(a.x == 88 && a.y == 40)   // 85 → 88, 43 → 40
        #expect(e.visual("b")! == Self.report().pages[0].visuals[1])
        #expect(e.page("p2")!.visuals == Self.report().pages[1].visuals)
    }

    @Test func moveSeveralKeepsRelativePositions() {
        let e = Self.makeEditor()
        e.move(["a", "b"], dx: 100, dy: 100, snap: true)
        let a = e.visual("a")!, b = e.visual("b")!
        #expect(b.x - a.x == 160 && b.y - a.y == 0)
        #expect(a.x == 144 && a.y == 144)
    }

    @Test func resizeChangesFrameButNotZOrType() {
        let e = Self.makeEditor()
        e.resize("b", handle: .se, dx: 40, dy: 24, snap: true)
        let b = e.visual("b")!
        #expect(b.x == 200 && b.y == 40 && b.width == 192 && b.height == 104)   // 390 → 392? xem dưới
        #expect(b.z == 2000 && b.type == "card")
    }

    @Test func applyFramesCommitsAllAtOnce() {
        let e = Self.makeEditor()
        e.apply(frames: ["a": Frame(x: 8, y: 8, width: 100, height: 50), "c": Frame(x: 16, y: 16, width: 64, height: 64)])
        #expect(e.visual("a")!.x == 8 && e.visual("c")!.width == 64)
        #expect(e.undoDepth == 1)
    }

    @Test func noChangeDoesNotCreateAnEditOrACopy() {
        let e = Self.makeEditor()
        e.move(["a"], dx: 0, dy: 0, snap: true)       // a đang ở 40,40: đã trên lưới
        #expect(e.edited.isEmpty && e.undoDepth == 0)
        e.apply(frames: ["a": Frame(x: 40, y: 40, width: 100, height: 50)])
        #expect(e.edited.isEmpty && e.undoDepth == 0)
    }

    @Test func visualsInsideAGroupAreLockedAgainstEditing() {
        let e = Self.makeEditor()
        #expect(e.isLockedByGroup("kid"))
        #expect(!e.isLockedByGroup("a"))
        e.select("kid")
        #expect(e.selection == ["kid"], "vẫn chọn được")
        let beforeKid = e.visual("kid")!
        e.move(["kid", "a"], dx: 80, dy: 80, snap: true)
        #expect(e.visual("kid")! == beforeKid, "visual trong nhóm không bị dời")
        #expect(e.visual("a")!.x == 120, "visual thường trong cùng thao tác vẫn dời")
        e.resize("kid", handle: .se, dx: 40, dy: 40, snap: true)
        #expect(e.visual("kid")! == beforeKid)
        e.apply(frames: ["kid": Frame(x: 99, y: 99, width: 50, height: 50)])
        #expect(e.visual("kid")! == beforeKid)
        #expect(e.lockedReason != nil)
    }

    @Test func pageReturnsBaselinePageWithEditedVisuals() {
        let e = Self.makeEditor()
        e.move(["c"], dx: 8, dy: 8, snap: true)
        let page = e.page("p1")!
        #expect(page.displayName == "P1" && page.width == 1920)
        #expect(page.visuals.first { $0.id == "c" }!.x == 408)
        #expect(page.visuals.map(\.id) == ["a", "b", "c", "hid", "kid"])
        #expect(e.page("zzz") == nil)
    }
}

/// Hoàn tác, làm lại, dấu "chưa lưu" (US3).
@Suite @MainActor struct LayoutEditorUndoTests {
    private func editor() -> LayoutEditor { LayoutEditorTests.makeEditor() }

    @Test func oneGestureIsOneStepAndUndoRestoresEverything() {
        let e = editor()
        let original = e.page("p1")!.visuals
        e.select("a")
        e.apply(frames: ["a": Frame(x: 64, y: 64, width: 100, height: 50)])
        #expect(e.undoDepth == 1 && e.canUndo && !e.canRedo)
        e.undo()
        #expect(e.page("p1")!.visuals == original)
        #expect(e.edited["p1"] == nil, "về đúng trạng thái chưa sửa, không còn bản sao trang")
        #expect(e.selection == ["a"], "vùng chọn trước thao tác được khôi phục")
        #expect(e.canRedo && !e.canUndo)
        e.redo()
        #expect(e.visual("a")!.x == 64 && e.visual("a")!.y == 64)
        #expect(e.undoDepth == 1 && !e.canRedo)
    }

    @Test func undoAcrossPagesGoesBackToThePageOfTheStep() {
        let e = editor()
        e.select("a")
        e.move(["a"], dx: 80, dy: 0, snap: true)       // bước 1 trên p1
        e.showPage("p2")
        e.select("d")
        e.move(["d"], dx: 80, dy: 0, snap: true)       // bước 2 trên p2
        e.undo()
        #expect(e.currentPageID == "p2")
        #expect(e.visual("d")!.x == 8)
        e.undo()
        #expect(e.currentPageID == "p1", "chuyển tới trang của bước được hoàn tác")
        #expect(e.visual("a")!.x == 40)
        e.redo(); e.redo()
        #expect(e.visual("a", page: "p1")!.x == 120 && e.visual("d", page: "p2")!.x == 88)
    }

    @Test func newEditAfterUndoDropsTheRedoStack() {
        let e = editor()
        e.apply(frames: ["a": Frame(x: 8, y: 8, width: 100, height: 50)])
        e.undo()
        #expect(e.canRedo)
        e.apply(frames: ["b": Frame(x: 16, y: 16, width: 100, height: 50)])
        #expect(!e.canRedo)
        e.redo()
        #expect(e.visual("a")!.x == 40, "redo cũ không còn tác dụng")
    }

    @Test func dirtyFollowsTheSavedMark() {
        let e = editor()
        #expect(!e.isDirty)
        e.apply(frames: ["a": Frame(x: 8, y: 8, width: 100, height: 50)])
        #expect(e.isDirty)
        e.undo()
        #expect(!e.isDirty)
        e.redo()
        #expect(e.isDirty)
        e.markSaved()
        #expect(!e.isDirty)
        e.undo()
        #expect(e.isDirty)
        e.redo()
        #expect(!e.isDirty)
    }

    @Test func goingBackThenEditingDifferentlyIsNeverClean() {
        let e = editor()
        e.apply(frames: ["a": Frame(x: 8, y: 8, width: 100, height: 50)])
        e.markSaved()                                       // đã lưu ở độ sâu 1
        e.undo()
        e.apply(frames: ["b": Frame(x: 24, y: 24, width: 100, height: 50)])   // độ sâu lại là 1 nhưng nội dung khác
        #expect(e.undoDepth == 1 && e.isDirty)
        e.undo()
        #expect(e.isDirty, "trạng thái đã lưu không còn quay về được")
    }

    @Test func arrowNudgesWithinHalfASecondMergeIntoOneStep() {
        let e = editor()
        var clock = Date(timeIntervalSince1970: 1000)
        e.now = { clock }
        e.select("a")
        for _ in 0..<5 {
            e.move(["a"], dx: 1, dy: 0, snap: false, coalescing: true)
            clock = clock.addingTimeInterval(0.1)
        }
        #expect(e.visual("a")!.x == 45)
        #expect(e.undoDepth == 1)
        clock = clock.addingTimeInterval(0.6)
        e.move(["a"], dx: 1, dy: 0, snap: false, coalescing: true)   // quá 0,5 s
        #expect(e.undoDepth == 2)
        e.move(["b"], dx: 1, dy: 0, snap: false, coalescing: true)   // nhóm chọn khác
        #expect(e.undoDepth == 3)
        e.undo(); e.undo()
        #expect(e.visual("a")!.x == 45)
        e.undo()
        #expect(e.visual("a")!.x == 40, "một lần hoàn tác đưa cả chuỗi mũi tên về chỗ cũ")
    }

    @Test func mergedNudgeNeverCrossesASave() {
        let e = editor()
        var clock = Date(timeIntervalSince1970: 1000)
        e.now = { clock }
        e.move(["a"], dx: 1, dy: 0, snap: false, coalescing: true)
        e.markSaved()
        clock = clock.addingTimeInterval(0.1)
        e.move(["a"], dx: 1, dy: 0, snap: false, coalescing: true)
        #expect(e.undoDepth == 2 && e.isDirty)
    }

    @Test func historyIsLimitedAndOldestSavedMarkIsLost() {
        let e = editor()
        e.markSaved()                                       // mốc ở độ sâu 0
        for i in 0..<(LayoutEditor.historyLimit + 5) {
            e.apply(frames: ["c": Frame(x: 400 + i, y: 400, width: 100, height: 50)])
        }
        #expect(e.undoDepth == LayoutEditor.historyLimit)
        for _ in 0..<LayoutEditor.historyLimit { e.undo() }
        #expect(!e.canUndo)
        #expect(e.isDirty, "mốc đã lưu nằm trong phần lịch sử bị bỏ")
    }

    @Test func undoRedoWithNothingToDoIsHarmless() {
        let e = editor()
        e.undo(); e.redo()
        #expect(!e.canUndo && !e.canRedo && !e.isDirty)
    }
}

/// Xoá, nhân bản, chép/dán (US4). Dùng `.pbix` nhỏ dựng sẵn để có `visual.json` thật.
@Suite @MainActor struct LayoutEditorDeleteDuplicateTests {
    @MainActor private struct Env {
        let dir: URL
        let source: URL
        let archive: ZipArchive
        let editor: LayoutEditor

        init() throws {
            dir = SyntheticReport.temporaryDirectory("dup")
            source = try SyntheticReport.make(in: dir)
            archive = try ZipArchive(url: source)
            let archive = self.archive
            let report = try PBIXFile(url: source).loadReport()
            editor = LayoutEditor(report: report, sourceJSON: { page, id in
                try? archive.read(LayoutEditor.visualPath(page: page, id: id))
            })
            editor.showPage("p1")
        }

        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    private typealias S = SyntheticReport

    // MARK: xoá

    @Test func deleteRemovesVisualsAndRecordsBaselineOnes() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.select(S.a1); e.select(S.a2, extend: true)
        e.delete([S.a1, S.a2])
        #expect(e.visuals(of: "p1").map(\.id) == [S.a3])
        #expect(e.edited["p1"]?.deleted == [S.a1, S.a2])
        #expect(e.selection.isEmpty && e.primary == nil)
        #expect(e.undoDepth == 1)
    }

    @Test func undoOfDeleteBringsBackSameVisualsInPlace() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let before = e.visuals(of: "p1")
        e.select(S.a2)
        e.delete([S.a2])
        e.undo()
        #expect(e.visuals(of: "p1") == before, "đúng chỗ trong thứ tự lớp và đúng z")
        #expect(e.selection == [S.a2])
        e.redo()
        #expect(!e.visuals(of: "p1").contains { $0.id == S.a2 })
    }

    @Test func deleteSkipsVisualsInsideAGroup() throws {
        let e = LayoutEditorTests.makeEditor()
        e.delete(["kid", "a"])
        #expect(e.visual("kid") != nil && e.visual("a") == nil)
        #expect(e.lockedReason != nil)
    }

    @Test func deleteOfNothingDoesNotCreateAStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.delete([])
        env.editor.delete(["không-có"])
        #expect(env.editor.undoDepth == 0 && env.editor.edited.isEmpty)
    }

    // MARK: nhân bản

    @Test func duplicateMakesAnOffsetCopyOnTop() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.select(S.a1)
        let ids = e.duplicate([S.a1])
        let id = try #require(ids.first)
        #expect(ids.count == 1 && PBIRLayoutPatch.isValidVisualName(id))
        let copy = try #require(e.visual(id))
        #expect(Frame(copy) == Frame(x: 56, y: 56, width: 100, height: 50))
        #expect(copy.z == 4000, "max z (3000) + 1000")
        #expect(copy.type == "card")
        #expect(e.selection == [id] && e.primary == id)
        #expect(e.visuals(of: "p1").last?.id == id)
        let json = try #require(e.edited["p1"]?.added[id])
        let position = try PBIRLayoutPatch.position(in: json)
        #expect(position.x == 56 && position.z == 4000 && position.tabOrder == 4000)
        let root = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(root["name"] as? String == id)
        #expect(copy.raw["name"]?.string == id, "raw của bản sao trỏ tới mã mới")
        #expect(e.undoDepth == 1)
    }

    @Test func duplicateSeveralKeepsRelativePositionsAndOrder() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let ids = e.duplicate([S.a1, S.a2])
        #expect(ids.count == 2 && Set(ids).count == 2)
        let c1 = try #require(e.visual(ids[0])), c2 = try #require(e.visual(ids[1]))
        let a1 = try #require(e.visual(S.a1)), a2 = try #require(e.visual(S.a2))
        #expect(c2.x - c1.x == a2.x - a1.x && c2.y - c1.y == a2.y - a1.y)
        #expect(c1.z < c2.z && c1.z > 3000, "z tăng theo thứ tự lớp gốc, trên mọi visual cũ")
        #expect(e.selection == Set(ids))
        #expect(e.undoDepth == 1)
    }

    @Test func duplicateNearThePageEdgeStaysInsideThePage() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.apply(frames: [S.a1: Frame(x: 1800, y: 1020, width: 100, height: 50)])    // sát góc dưới phải 1920×1080
        let id = try #require(e.duplicate([S.a1]).first)
        let copy = try #require(e.visual(id))
        #expect(copy.x >= 0 && copy.y >= 0 && copy.x + copy.width <= 1920 && copy.y + copy.height <= 1080)
    }

    @Test func idsAreNeverReusedEvenAfterUndo() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let existing = Set(["p1", "p2"].flatMap { e.visuals(of: $0).map(\.id) })
        var seen = Set<String>()
        for round in 0..<300 {
            let ids = e.duplicate([S.a1])
            for id in ids {
                #expect(!seen.contains(id) && !existing.contains(id), "vòng \(round)")
                seen.insert(id)
            }
            if round % 3 == 0 { e.undo() }
            if round % 7 == 0 { e.redo() }
        }
        #expect(seen.count == 300)
    }

    @Test func duplicateOfACopyUsesItsOwnData() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let first = try #require(e.duplicate([S.a1]).first)
        e.move([first], dx: 80, dy: 0, snap: true)
        let second = try #require(e.duplicate([first]).first)
        #expect(second != first && e.edited["p1"]?.added.count == 2)
        let json = try #require(e.edited["p1"]?.added[second])
        #expect(try PBIRLayoutPatch.position(in: json).x == Double(e.visual(second)!.x))
    }

    @Test func duplicateSkipsLockedGroupVisuals() throws {
        let e = LayoutEditorTests.makeEditor()
        #expect(e.duplicate(["kid"]).isEmpty)
        #expect(e.lockedReason != nil && e.undoDepth == 0)
    }

    @Test func duplicateWithoutSourceDataDoesNothing() throws {
        let e = LayoutEditorTests.makeEditor()      // không có sourceJSON
        #expect(e.duplicate(["a"]).isEmpty)
        #expect(e.undoDepth == 0)
    }

    @Test func undoOfDuplicateRemovesTheCopyAndItsData() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.duplicate([S.a1])
        e.undo()
        #expect(e.edited["p1"] == nil)
        #expect(e.visuals(of: "p1").count == 3)
    }

    // MARK: chép và dán

    @Test func copyThenPasteIntoAnotherPage() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.select(S.a1)
        e.copy()
        e.showPage("p2")
        let ids = e.paste()
        let id = try #require(ids.first)
        #expect(e.visual(id)?.type == "card" && e.visuals(of: "p2").contains { $0.id == id })
        #expect(e.visuals(of: "p1").count == 3, "trang nguồn không đổi")
        #expect(e.edited["p2"]?.added[id] != nil)
        // Dán lần nữa: một bản mới, lệch thêm.
        let again = try #require(e.paste().first)
        #expect(again != id && e.visual(again)!.x > e.visual(id)!.x)
    }

    @Test func pasteWithEmptyClipboardDoesNothing() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.paste().isEmpty && env.editor.undoDepth == 0)
    }

    // MARK: gói thay đổi

    @Test func changesForDuplicateAndDelete() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let copy = try #require(e.duplicate([S.a3]).first)
        e.delete([S.a1])                                  // a1 có trong bookmark bm1
        let changes = try e.makeChanges(archive: env.archive)
        let copyPath = LayoutEditor.visualPath(page: "p1", id: copy)
        #expect(Set(changes.addedParts.keys) == [copyPath])
        #expect(changes.removedParts == [LayoutEditor.visualPath(page: "p1", id: S.a1)])
        let bookmarkPath = "Report/definition/bookmarks/bm1.bookmark.json"
        let cleaned = try #require(changes.reportParts[bookmarkPath])
        // Như Power BI Desktop: bỏ khỏi visualContainers, targetVisualNames giữ nguyên.
        #expect(!bookmarkContainerIDs(cleaned).contains(S.a1) && bookmarkContainerIDs(cleaned).contains(S.a2))
        #expect(String(decoding: cleaned, as: UTF8.self).contains(#""targetVisualNames":["\#(S.a1)","\#(S.a2)"]"#))
        // Ghi ra file thật: mở lại thấy bản sao, không thấy a1.
        let output = env.dir.appendingPathComponent("out.pbix")
        try PBIXWriter.save(source: env.source, to: output, changes: changes, backup: .none)
        let after = try PBIXFile(url: output).loadReport().pages.first { $0.id == "p1" }!
        #expect(after.visuals.contains { $0.id == copy } && !after.visuals.contains { $0.id == S.a1 })
    }

    @Test func deletingACopyLeavesNoParts() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let copy = try #require(e.duplicate([S.a1]).first)
        e.delete([copy])
        let changes = try e.makeChanges(archive: env.archive)
        #expect(changes.addedParts.isEmpty && changes.removedParts.isEmpty && changes.reportParts.isEmpty)
        #expect(e.edited["p1"]?.added.isEmpty == true)
    }

    @Test func savedCopyThenMovedIsPatchedOnTheSecondSave() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let copy = try #require(e.duplicate([S.a1]).first)
        let backups = env.dir.appendingPathComponent("b")
        var outcome = try DocumentSaver.save(editor: e, source: env.source, to: env.source, expectedStamp: try FileStamp.of(env.source),
                                             readOnlyRoots: [], backupDirectory: backups)
        e.move([copy], dx: 40, dy: 0, snap: true)
        outcome = try DocumentSaver.save(editor: e, source: env.source, to: env.source, expectedStamp: outcome.newStamp,
                                         readOnlyRoots: [], backupDirectory: backups)
        #expect(outcome.didWrite)
        let page = try PBIXFile(url: env.source).loadReport().pages.first { $0.id == "p1" }!
        #expect(Frame(page.visuals.first { $0.id == copy }!).x == Frame(e.visual(copy)!).x)
        // Xoá bản sao đã lưu rồi lưu lần ba: phần của nó bị bỏ khỏi file.
        e.delete([copy])
        outcome = try DocumentSaver.save(editor: e, source: env.source, to: env.source, expectedStamp: outcome.newStamp,
                                         readOnlyRoots: [], backupDirectory: backups)
        let final = try PBIXFile(url: env.source).loadReport().pages.first { $0.id == "p1" }!
        #expect(!final.visuals.contains { $0.id == copy })
    }
}
