import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Nhóm lồng nhau và Merge (bổ sung D7): `docs/phase-d-evidence/vm-d8/QUAN-SAT.md` mục 1,
/// `specs/008-d7-nhom-can-le-cu/contracts/group-editing.md`.
///
/// Trang p1 của `SyntheticReport`: a1 (40, 40, 100×50), a2 (200, 40, 150×80), a3 (400, 400, 100×50).
@Suite @MainActor struct NestedGroupTests {
    typealias Env = PageSavingTests.Env
    typealias S = SyntheticReport

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
    private func path(_ id: String) -> String { LayoutEditor.visualPath(page: "p1", id: id) }

    /// Nhóm trong (a1, a2) rồi nhóm ngoài (nhóm trong, a3), như thao tác Group trên một nhóm và một visual ở Desktop.
    private func nest(_ env: Env) throws -> (inner: String, outer: String) {
        env.editor.setSelection([S.a1, S.a2], extend: false)
        let inner = try #require(env.editor.group())
        env.editor.setSelection([inner, S.a3], extend: false)
        let outer = try #require(env.editor.group())
        return (inner, outer)
    }

    // MARK: Group trên nhóm và visual

    @Test func aGroupAndAVisualBecomeAnOuterGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let (inner, outer) = try nest(env)
        let g1 = try #require(e.item(inner)), g2 = try #require(e.item(outer))
        #expect(g1.x == 40 && g1.y == 40 && g1.width == 310 && g1.height == 80 && g1.z == 2001)
        // Hộp bao của nhóm trong và a3; `z` = `z` lớn nhất của các phần tử được nhóm + 1.
        #expect(g2.x == 40 && g2.y == 40 && g2.width == 460 && g2.height == 410 && g2.z == 3001)
        #expect(g2.groupDisplayName == "Group 2" && g2.parentGroup == nil)
        #expect(g1.parentGroup == outer && e.visual(S.a3)?.parentGroup == outer)
        #expect(e.visual(S.a1)?.parentGroup == inner && e.visual(S.a2)?.parentGroup == inner)   // con của nhóm trong không đổi
        #expect(e.selection == [outer] && e.undoDepth == 2)
        #expect([inner, outer, S.a1, S.a3].allSatisfy { !e.isLockedByGroup($0) })
        e.undo()
        #expect(e.item(inner)?.parentGroup == nil && e.visual(S.a3)?.parentGroup == nil && e.groups(of: "p1").count == 1)
    }

    @Test func theNestedFileMatchesTheDesktopShape() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        let changes = try env.editor.makeChanges(archive: env.archive)
        // Nhóm trong: toạ độ tương đối so với nhóm ngoài, `parentGroupName` là khoá cuối sau `visualGroup`
        // (`docs/phase-d-evidence/vm-d8/json/nhom-trong.visual.json`).
        let innerJSON = text(try #require(changes.addedParts[path(inner)]))
        #expect(innerJSON == #"{"$schema":"\#(PBIRGroupPatch.groupSchema)","name":"\#(inner)","position":{"x":0,"y":0,"z":2001,"height":80,"width":310,"tabOrder":2001},"visualGroup":{"displayName":"Group 1","groupMode":"ScaleMode"},"parentGroupName":"\#(outer)"}"#)
        let outerJSON = text(try #require(changes.addedParts[path(outer)]))
        #expect(outerJSON.contains(#""position":{"x":40,"y":40,"z":3001,"height":410,"width":460"#) && !outerJSON.contains("parentGroupName"))
        // a3 tương đối so với nhóm ngoài; a2 tương đối so với nhóm trong.
        let a3 = text(try #require(changes.reportParts[path(S.a3)]))
        #expect(a3.contains(#""x":360,"y":360"#) && a3.hasSuffix(#","parentGroupName":"\#(outer)"}"#))
        let a2 = text(try #require(changes.reportParts[path(S.a2)]))
        #expect(a2.contains(#""x":160,"y":0"#) && a2.hasSuffix(#","parentGroupName":"\#(inner)"}"#))
    }

    @Test func savingThenReloadingKeepsTheNesting() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = env.editor.visuals(of: "p1").map { Frame($0) }
        let (inner, outer) = try nest(env)
        _ = try env.save()
        let page = try #require(try env.report().pages.first)
        #expect(page.visuals.map { Frame($0) } == before)   // bộ đọc cộng gốc của mọi nhóm tổ tiên
        let g1 = try #require(page.groups.first { $0.id == inner })
        #expect(g1.parentGroup == outer && g1.x == 40 && g1.y == 40)
        let again = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(again.reportParts.isEmpty && again.addedParts.isEmpty && again.removedParts.isEmpty)
        // Mở lại bằng trình sửa mới: không phần tử nào bị khoá.
        let reopened = LayoutEditor.reading(archive: try ZipArchive(url: env.source), report: try env.report())
        reopened.showPage("p1")
        #expect([inner, outer, S.a1, S.a2, S.a3].allSatisfy { !reopened.isLockedByGroup($0) })
    }

    // MARK: Di chuyển, đổi cỡ

    @Test func movingTheOuterGroupMovesEveryDescendantAndWritesOnlyTheGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        _ = try env.save()
        env.editor.move([outer], dx: 100, dy: 20, snap: false)
        #expect(env.editor.visual(S.a1)?.x == 140 && env.editor.visual(S.a3)?.y == 420 && env.editor.item(inner)?.x == 140)
        let changes = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(Set(changes.reportParts.keys) == [path(outer)])
        // Kéo nhóm trong bên trong nhóm ngoài: con của nó đi theo, không ra khỏi nhóm ngoài.
        env.editor.move([inner], dx: 0, dy: 5000, snap: false)
        let g1 = try #require(env.editor.item(inner)), g2 = try #require(env.editor.item(outer))
        #expect(g1.y + g1.height == g2.y + g2.height)
        #expect(env.editor.visual(S.a1)?.y == g1.y)
    }

    /// VM-D8: co chiều dọc 772,54 → 386 thì mọi hậu duệ (kể cả cháu trong nhóm lồng) co cùng tỷ lệ; `x`, `width` giữ nguyên.
    @Test func resizingTheOuterGroupScalesEveryDescendant() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        env.editor.apply(frames: [outer: Frame(x: 40, y: 40, width: 460, height: 205)])
        let a3 = try #require(env.editor.visual(S.a3)), a2 = try #require(env.editor.visual(S.a2)), g1 = try #require(env.editor.item(inner))
        #expect(a3.y == 220 && a3.height == 25 && a3.x == 400 && a3.width == 100)
        #expect(g1.y == 40 && g1.height == 40 && g1.width == 310)
        #expect(a2.y == 40 && a2.height == 40 && a2.x == 200)   // cháu co theo cùng tỷ lệ 0,5
        #expect(env.editor.undoDepth == 3)
    }

    // MARK: Bỏ nhóm, xoá, sao

    @Test func ungroupingTheOuterGroupFreesTheInnerGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        _ = try env.save()
        env.editor.setSelection([outer], extend: false)
        #expect(Set(env.editor.ungroup()) == [inner, S.a3])
        #expect(env.editor.item(outer) == nil && env.editor.item(inner)?.parentGroup == nil && env.editor.visual(S.a3)?.parentGroup == nil)
        #expect(env.editor.visual(S.a1)?.parentGroup == inner)
        _ = try env.save()
        // Nhóm trong bỏ `parentGroupName`, về toạ độ tuyệt đối; con của nó không đổi.
        let innerJSON = try env.read(path(inner))
        #expect(!innerJSON.contains("parentGroupName") && innerJSON.contains(#""x":40,"y":40"#))
        #expect(try env.read(path(S.a2)).hasSuffix(#","parentGroupName":"\#(inner)"}"#))
        #expect(try !env.read(path(S.a3)).contains("parentGroupName"))
    }

    @Test func ungroupingTheInnerGroupMovesItsChildrenToTheOuterGroup() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        env.editor.setSelection([inner], extend: false)
        #expect(Set(env.editor.ungroup()) == [S.a1, S.a2])
        #expect(env.editor.item(inner) == nil && env.editor.visual(S.a1)?.parentGroup == outer)
    }

    /// VM-D8: Delete trên nhóm xoá nhóm, nhóm lồng bên trong và mọi visual con.
    @Test func deletingTheOuterGroupDeletesEverythingInside() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        _ = try env.save()
        env.editor.delete([outer])
        #expect(env.editor.visuals(of: "p1").isEmpty && env.editor.groups(of: "p1").isEmpty)
        let changes = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(changes.removedParts == Set([inner, outer, S.a1, S.a2, S.a3].map(path)))
        env.editor.undo()
        #expect(env.editor.groups(of: "p1").count == 2 && env.editor.visuals(of: "p1").count == 3)
    }

    @Test func deletingTheLastMembersRemovesTheEmptyGroupsUpTheChain() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        env.editor.delete([S.a1, S.a2])
        #expect(env.editor.item(inner) == nil && env.editor.item(outer) != nil)
        env.editor.delete([S.a3])
        #expect(env.editor.groups(of: "p1").isEmpty)
    }

    @Test func duplicatingTheOuterGroupCopiesTheWholeTree() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        let top = env.editor.duplicate([outer])
        #expect(top.count == 1 && top[0] != outer)
        let groups = env.editor.groups(of: "p1")
        #expect(groups.count == 4 && env.editor.visuals(of: "p1").count == 6)
        let innerCopy = try #require(groups.first { $0.parentGroup == top[0] })
        #expect(innerCopy.id != inner && env.editor.visuals(of: "p1").filter { $0.parentGroup == innerCopy.id }.count == 2)
        #expect(env.editor.visuals(of: "p1").filter { $0.parentGroup == top[0] }.count == 1)
        _ = try env.save()
        #expect(try env.report().pages[0].groups.count == 4)
    }

    @Test func duplicatingThePageKeepsTheNesting() throws {
        let env = try Env(); defer { env.cleanUp() }
        _ = try nest(env)
        let copy = try #require(env.editor.duplicatePage("p1"))
        let groups = env.editor.groups(of: copy)
        let outerCopy = try #require(groups.first { $0.parentGroup == nil })
        #expect(groups.count == 2 && groups.contains { $0.parentGroup == outerCopy.id })
        _ = try env.save()
        let page = try #require(try env.report().pages.first { $0.id == copy })
        #expect(page.groups.count == 2 && page.visuals.first { $0.type == "card" && $0.x == 400 }?.y == 400)
    }

    // MARK: Merge

    @Test func mergeAddsAVisualToTheGroupAndRecomputesTheFrame() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([S.a2, S.a3], extend: false)
        let id = try #require(e.group())
        #expect(e.item(id)?.x == 200)
        _ = try env.save()
        e.setSelection([id, S.a1], extend: false)
        #expect(e.mergeBlocker() == nil)
        #expect(e.mergeIntoGroup() == id)
        let group = try #require(e.item(id))
        // Giữ mã và tên nhóm; hộp bao = hợp của nhóm và visual mới.
        #expect(group.groupDisplayName == "Group 1" && group.x == 40 && group.y == 40 && group.width == 460 && group.height == 410)
        #expect(e.visual(S.a1)?.parentGroup == id && e.groups(of: "p1").count == 1 && e.selection == [id])
        #expect(e.visual(S.a2)?.x == 200)   // toạ độ tuyệt đối của con cũ không đổi
        let changes = try e.makeChanges(archive: try ZipArchive(url: env.source))
        // Gốc nhóm dời sang trái 160: toạ độ tương đối của con cũ được dịch theo gốc mới.
        #expect(text(try #require(changes.reportParts[path(S.a2)])).contains(#""x":160,"y":0"#))
        #expect(text(try #require(changes.reportParts[path(S.a1)])).hasSuffix(#""x":0,"y":0,"z":1000,"height":50,"width":100,"tabOrder":1000},"visual":{"visualType":"card"},"parentGroupName":"\#(id)"}"#))
        #expect(changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        _ = try env.save()
        #expect(try env.report().pages[0].visuals.allSatisfy { $0.parentGroup == id })
        e.undo()
        #expect(e.visual(S.a1)?.parentGroup == nil && e.item(id)?.x == 200)
    }

    @Test func mergeNeedsOneGroupAndVisualsOutsideGroups() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([S.a1, S.a2], extend: false)
        #expect(e.mergeBlocker() != nil && e.mergeIntoGroup() == nil)
        let id = try #require(e.group())
        e.setSelection([id], extend: false)
        #expect(e.mergeBlocker() != nil)
        e.setSelection([id, S.a1], extend: false)   // a1 đã ở trong nhóm này
        #expect(e.mergeBlocker() != nil)
        let depth = e.undoDepth
        #expect(e.mergeIntoGroup() == nil && e.undoDepth == depth)
    }

    // MARK: Từ chối và chọn

    @Test func aChildOfAGroupCannotBeGroupedWithSomethingOutside() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setSelection([S.a1, S.a2], extend: false)
        _ = try #require(env.editor.group())
        env.editor.setSelection([S.a1, S.a3], extend: false)
        #expect(env.editor.groupBlocker()?.contains("cùng cấp") == true && env.editor.group() == nil)
    }

    @Test func clickingGoesOneLevelDeeperEachTime() throws {
        let env = try Env(); defer { env.cleanUp() }
        let (inner, outer) = try nest(env)
        let e = env.editor
        e.clearSelection()
        // (50, 50) nằm trong a1
        #expect(e.hitTarget(x: 50, y: 50, isHidden: { _ in false }) == outer)
        e.select(outer)
        #expect(e.hitTarget(x: 50, y: 50, isHidden: { _ in false }) == inner)
        e.select(inner)
        #expect(e.hitTarget(x: 50, y: 50, isHidden: { _ in false }) == S.a1)
        e.select(S.a1)
        #expect(e.hitTarget(x: 210, y: 60, isHidden: { _ in false }) == S.a2)   // một con đang chọn: bấm con khác chọn con đó
        #expect(e.hitTarget(x: 410, y: 410, isHidden: { _ in false }) == S.a3)
    }

    @Test func aGroupWhoseParentIsMissingStaysLocked() throws {
        let orphan = Data(#"{"$schema":"s","name":"eeeeeeeeeeeeeeeeeee1","position":{"x":600,"y":600,"z":9000,"height":100,"width":100,"tabOrder":9000},"visualGroup":{"displayName":"Group 9","groupMode":"ScaleMode"},"parentGroupName":"khongco"}"#.utf8)
        let env = try Env(extra: [(S.visualPath("p1", "eeeeeeeeeeeeeeeeeee1"), orphan)]); defer { env.cleanUp() }
        #expect(env.editor.isLockedByGroup("eeeeeeeeeeeeeeeeeee1"))
        env.editor.move(["eeeeeeeeeeeeeeeeeee1"], dx: 10, dy: 10, snap: false)
        #expect(env.editor.undoDepth == 0 && env.editor.lockedReason != nil)
    }
}
