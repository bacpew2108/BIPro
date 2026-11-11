import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Nhóm visual (D7, US3): cấu trúc theo Power BI Desktop (VM-D7, `docs/phase-d-evidence/vm-d7/QUAN-SAT.md` §1–4).
@Suite @MainActor struct GroupTests {
    typealias Env = PageSavingTests.Env
    typealias S = SyntheticReport

    private func groupAll(_ env: Env) throws -> String {
        env.editor.setSelection([S.a1, S.a2, S.a3], extend: false)
        return try #require(env.editor.group())
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // MARK: nhóm

    @Test func groupingBuildsTheContainerAndKeepsAbsolutePositions() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        let e = env.editor
        let group = try #require(e.groups(of: "p1").first)
        #expect(group.id == id && group.groupDisplayName == "Group 1" && group.isGroup)
        // hộp bao: x 40..500, y 40..450; z = z lớn nhất của con + 1
        #expect(group.x == 40 && group.y == 40 && group.width == 460 && group.height == 410 && group.z == 3001)
        #expect(e.visuals(of: "p1").prefix(3).allSatisfy { $0.parentGroup == id })
        #expect(e.visual(S.a2)?.x == 200)                    // toạ độ tuyệt đối trong mô hình
        #expect(e.selection == [id] && e.undoDepth == 1)
        e.undo()
        #expect(e.groups(of: "p1").isEmpty && e.visuals(of: "p1").allSatisfy { $0.parentGroup == nil })
    }

    @Test func groupedFileMatchesTheDesktopShape() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        let changes = try env.editor.makeChanges(archive: env.archive)
        let groupJSON = try #require(changes.addedParts[LayoutEditor.visualPath(page: "p1", id: id)])
        #expect(text(groupJSON) == #"{"$schema":"\#(PBIRGroupPatch.groupSchema)","name":"\#(id)","position":{"x":40,"y":40,"z":3001,"height":410,"width":460,"tabOrder":3001},"visualGroup":{"displayName":"Group 1","groupMode":"ScaleMode"}}"#)
        // con: toạ độ tương đối so với nhóm, `parentGroupName` là khoá cuối, mọi thứ khác nguyên byte
        let a2 = try #require(changes.reportParts[LayoutEditor.visualPath(page: "p1", id: S.a2)])
        let original = try env.archive.read(LayoutEditor.visualPath(page: "p1", id: S.a2))
        #expect(text(a2) == text(original).replacingOccurrences(of: #""x":200,"y":40"#, with: #""x":160,"y":0"#)
                    .dropLast() + #","parentGroupName":"\#(id)"}"#)
        #expect(changes.removedParts.isEmpty)
    }

    @Test func savingThenReloadingGivesTheSameLayout() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = env.editor.visuals(of: "p1").map { Frame($0) }
        let id = try groupAll(env)
        _ = try env.save()
        let pages = try env.report().pages
        let page = try #require(pages.first)
        #expect(page.groups.map(\.id) == [id])
        #expect(page.visuals.map { Frame($0) } == before)    // loader cộng toạ độ nhóm: tuyệt đối như cũ
        #expect(page.visuals.allSatisfy { $0.parentGroup == id })
        // lưu lần hai không ghi gì
        let again = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(again.reportParts.isEmpty && again.addedParts.isEmpty && again.removedParts.isEmpty)
    }

    @Test func ungroupingRestoresTheOriginalBytes() throws {
        let env = try Env(); defer { env.cleanUp() }
        let originals = try [S.a1, S.a2, S.a3].map { try env.archive.read(LayoutEditor.visualPath(page: "p1", id: $0)) }
        _ = try groupAll(env)
        _ = try env.save()
        #expect(env.editor.ungroup().count == 3)
        #expect(env.editor.groups(of: "p1").isEmpty && env.editor.undoDepth == 2)
        _ = try env.save()
        let after = try ZipArchive(url: env.source)
        for (id, original) in zip([S.a1, S.a2, S.a3], originals) {
            #expect(try after.read(LayoutEditor.visualPath(page: "p1", id: id)) == original)
        }
        #expect(try env.report().pages[0].groups.isEmpty)
    }

    @Test func ungroupBeforeSavingLeavesNothingToWrite() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try groupAll(env)
        env.editor.ungroup()
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(changes.reportParts.isEmpty && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
    }

    // MARK: di chuyển và đổi cỡ nhóm

    @Test func movingAGroupChangesOnlyTheGroupFile() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        _ = try env.save()
        env.editor.move([id], dx: 100, dy: 20, snap: false)
        #expect(env.editor.visual(S.a2)?.x == 300 && env.editor.group(of: S.a2)?.x == 140)
        let changes = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(Set(changes.reportParts.keys) == [LayoutEditor.visualPath(page: "p1", id: id)])
        #expect(text(changes.reportParts.values.first!).contains(#""x":140,"y":60"#))
        env.editor.undo()
        #expect(env.editor.visual(S.a2)?.x == 200)
    }

    @Test func resizingAGroupScalesItsChildren() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        _ = try env.save()
        // nửa bề rộng: 460 → 230
        env.editor.apply(frames: [id: Frame(x: 40, y: 40, width: 230, height: 410)])
        #expect(env.editor.visual(S.a2)?.x == 40 + 160 * 0.5 && env.editor.visual(S.a2)?.width == 75)
        let changes = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        let a2bytes = try #require(changes.reportParts[LayoutEditor.visualPath(page: "p1", id: S.a2)])
        let a2 = text(a2bytes)
        #expect(a2.contains(#""x":80,"y":0"#) && a2.contains(#""width":75"#) && a2.hasSuffix(#""parentGroupName":"\#(id)"}"#))
        _ = try env.save()
        let reloaded = try env.report().pages[0]
        #expect(reloaded.visuals.first { $0.id == S.a2 }?.x == 120)
    }

    @Test func aChildStaysInsideItsGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try groupAll(env)
        env.editor.move([S.a1], dx: -500, dy: 0, snap: false)
        #expect(env.editor.visual(S.a1)?.x == 40)             // kẹp ở mép trái của nhóm
        env.editor.move([S.a3], dx: 900, dy: 900, snap: false)
        let a3 = try #require(env.editor.visual(S.a3))
        #expect(a3.x + a3.width <= 500 && a3.y + a3.height <= 450)
    }

    // MARK: xoá và nhân bản

    @Test func deletingAGroupDeletesItsChildren() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        _ = try env.save()
        env.editor.delete([id])
        #expect(env.editor.visuals(of: "p1").isEmpty && env.editor.groups(of: "p1").isEmpty)
        let changes = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(changes.removedParts.count == 4)
        _ = try env.save()
        let reloaded = try env.report().pages[0]
        #expect(reloaded.visuals.isEmpty && reloaded.groups.isEmpty)
        env.editor.undo()
        #expect(env.editor.visuals(of: "p1").count == 3 && env.editor.groups(of: "p1").count == 1)
    }

    @Test func deletingTheLastChildRemovesTheGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setSelection([S.a1, S.a2], extend: false)
        let id = try #require(env.editor.group())
        env.editor.delete([S.a1])
        #expect(env.editor.groups(of: "p1").map(\.id) == [id])
        env.editor.delete([S.a2])
        #expect(env.editor.groups(of: "p1").isEmpty)
    }

    @Test func duplicatingAGroupCopiesTheChildrenIntoTheNewGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        let copies = env.editor.duplicate([id])
        let newGroup = try #require(copies.first)
        #expect(copies.count == 1 && newGroup != id)
        #expect(env.editor.groups(of: "p1").count == 2)
        let kids = env.editor.children(ofGroup: newGroup)
        #expect(kids.count == 3 && kids.allSatisfy { $0.id != S.a1 })
        let group = try #require(env.editor.item(newGroup))
        #expect(group.x == 56 && group.y == 56 && kids.map(\.z).max()! < group.z)
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(changes.addedParts.count == 1 + 3 + 1)        // nhóm gốc mới (chưa lưu) + 3 con mới + nhóm mới... 
        _ = try env.save()
        let pages = try env.report().pages
        let page = try #require(pages.first)
        #expect(page.groups.count == 2 && page.visuals.count == 6)
        for kid in page.visuals where kid.parentGroup == newGroup {
            let g = try #require(page.groups.first { $0.id == newGroup })
            #expect(kid.x >= g.x - 1 && kid.x + kid.width <= g.x + g.width + 1)
        }
    }

    @Test func copyingOneChildMakesAnUngroupedVisual() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try groupAll(env)
        env.editor.select(S.a2)
        env.editor.copy()
        let ids = env.editor.paste()
        let copyID = try #require(ids.first)
        let copy = try #require(env.editor.visual(copyID))
        #expect(copy.parentGroup == nil && copy.x == 210 && copy.y == 50)  // +10 mỗi lần dán (VM-D7)
        let changes = try env.editor.makeChanges(archive: env.archive)
        let bytes = try #require(changes.addedParts[LayoutEditor.visualPath(page: "p1", id: copy.id)])
        let json = text(bytes)
        #expect(!json.contains("parentGroupName") && json.contains(#""x":210,"y":50"#))
    }

    // MARK: từ chối và chọn

    @Test func nestedGroupsAreRefused() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        env.editor.setSelection([id, S.b1], extend: false)
        #expect(env.editor.group() == nil)
        env.editor.setSelection([S.a1], extend: false)
        #expect(env.editor.groupBlocker() == "Nhóm cần chọn từ 2 visual.")
        env.editor.showPage("p1")
    }

    @Test func clickingAChildSelectsTheGroupFirstThenTheChild() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        env.editor.clearSelection()
        // (210, 60) nằm trong a2
        #expect(env.editor.hitTarget(x: 210, y: 60, isHidden: { _ in false }) == id)
        env.editor.select(id)
        #expect(env.editor.hitTarget(x: 210, y: 60, isHidden: { _ in false }) == S.a2)
        env.editor.select(S.a2)
        #expect(env.editor.hitTarget(x: 50, y: 50, isHidden: { _ in false }) == S.a1)   // một con đang chọn: bấm con khác chọn con đó
        // chỗ trống trong khung nhóm: chọn nhóm
        #expect(env.editor.hitTarget(x: 480, y: 100, isHidden: { _ in false }) == id)
    }

    @Test func alignWorksBetweenChildrenOfTheSameGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try groupAll(env)
        env.editor.setSelection([S.a1, S.a2], extend: false)
        #expect(env.editor.align(.bottom))
        #expect(env.editor.visual(S.a1)?.y == 70)               // a2 dưới = 120 → a1 cao 50 → y = 70
        env.editor.setSelection([S.a1, S.b1], extend: false)
        #expect(env.editor.alignBlocker(.left) != nil)           // khác cấp
    }

    // MARK: sửa sau review

    @Test func aChildPastedOnItsOwnIsNotLocked() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try groupAll(env)
        env.editor.select(S.a2); env.editor.copy()
        env.editor.showPage("p2")
        let id = try #require(env.editor.paste().first)
        #expect(env.editor.isLockedByGroup(id) == false)
        env.editor.move([id], dx: 30, dy: 0, snap: false)
        #expect(env.editor.visual(id)?.x == 240)            // 200 + 10 (dán) + 30
    }

    @Test func ungroupedChildrenOfAFileGroupAreEditableAgain() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try groupAll(env)
        _ = try env.save()
        // mở lại từ file: con có `parentGroupName` trong raw
        let reopened = LayoutEditor.reading(archive: try ZipArchive(url: env.source), report: try env.report())
        reopened.showPage("p1")
        reopened.select(S.a1)
        reopened.ungroup()
        reopened.move([S.a1], dx: 8, dy: 0, snap: false)
        #expect(reopened.visual(S.a1)?.x == 48 && reopened.isLockedByGroup(S.a1) == false)
    }

    @Test func scalingAGroupNeverMakesAChildSmallerThanOnePoint() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try groupAll(env)
        env.editor.apply(frames: [id: Frame(x: 40, y: 40, width: 2, height: 2)])
        #expect(env.editor.visuals(of: "p1").allSatisfy { $0.width >= 1 && $0.height >= 1 })
        _ = try env.save()                                  // không ném "width must be at least 1"
    }

    @Test func theGroupGetsAZNoOtherItemHas() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setSelection([S.a1, S.a2], extend: false)    // z lớn nhất của con 2000; a3 có z 3000
        let id = try #require(env.editor.group())
        let z = try #require(env.editor.item(id)).z
        #expect(z == 2001 && env.editor.visuals(of: "p1").allSatisfy { $0.z != z })
        env.editor.undo()
        env.editor.setSelection([S.a1, S.a3], extend: false)
        let again = try #require(env.editor.group())
        #expect(env.editor.item(again)?.z == 3001)
    }

    @Test func alignInsideAGroupFollowsTheFormulaInsideTheGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try groupAll(env)                                // nhóm x 40..500
        env.editor.setSelection([S.a1, S.a2, S.a3], extend: false)
        #expect(env.editor.align(.distributeH))
        #expect(env.editor.visual(S.a2)?.x == 195)           // như ngoài nhóm: hai đầu giữ, khoảng hở đều
    }

    @Test func editingAChildOfAGroupKeepsItsGroupAndRelativePosition() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([S.a1, S.a2], extend: false)
        let id = try #require(e.group())
        _ = try env.save()
        #expect(e.fieldEditingBlocker(for: S.a1) != "Visual nằm trong nhóm, chưa sửa trường được.")
        #expect(e.formatEditingBlocker(for: S.a1) == nil)
        e.move([S.a1], dx: 8, dy: 0, snap: false)
        let changes = try e.makeChanges(archive: try ZipArchive(url: env.source))
        let bytes = try #require(changes.reportParts[LayoutEditor.visualPath(page: "p1", id: S.a1)])
        #expect(text(bytes).hasSuffix(#""parentGroupName":"\#(id)"}"#) && text(bytes).contains(#""x":8,"y":0"#))
        _ = try env.save()
        let pages = try env.report().pages
        let child = try #require(pages[0].visuals.first { $0.id == S.a1 })
        #expect(child.parentGroup == id && child.x == 48)
    }

    @Test func deletingAGroupRemovesItAndItsChildrenFromBookmarks() throws {
        let bookmark = #"{"name":"bm1","options":{"targetVisualNames":["\#(S.a1)","\#(S.a2)"]},"explorationState":{"sections":{"p1":{"visualContainers":{"\#(S.a1)":{"singleVisual":{"visualType":"card"}},"\#(S.a2)":{"singleVisual":{"visualType":"card"}}}}}}}"#
        let env = try Env(bookmarks: [("bm1", bookmark)]); defer { env.cleanUp() }
        env.editor.setSelection([S.a1, S.a2], extend: false)
        let id = try #require(env.editor.group())
        _ = try env.save()
        env.editor.delete([id])
        let changes = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        let cleaned = String(decoding: try #require(changes.reportParts["Report/definition/bookmarks/bm1.bookmark.json"]), as: UTF8.self)
        #expect(!cleaned.contains(#""\#(S.a1)":{"singleVisual""#) && !cleaned.contains(#""\#(S.a2)":{"singleVisual""#))
    }
}

extension LayoutEditor {
    /// Nhóm chứa `id` (cho test).
    func group(of id: String) -> ReportVisual? {
        guard let parent = visual(id)?.parentGroup else { return nil }
        return item(parent)
    }
}
