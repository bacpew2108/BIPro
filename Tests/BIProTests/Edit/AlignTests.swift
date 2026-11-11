import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Căn lề và phân bố (D7, US1): công thức theo Power BI Desktop (VM-D7, `docs/phase-d-evidence/vm-d7/QUAN-SAT.md` §5).
@Suite struct AlignGeometryTests {
    private let page = PageBounds(width: 1920, height: 1080)
    private typealias G = LayoutGeometry

    @Test func leftRightTopBottomUseTheEdgeOfTheSelection() {
        let a = Frame(x: 26, y: 296, width: 540, height: 380), b = Frame(x: 26, y: 687, width: 308, height: 380)
        #expect(G.align(.left, frames: [Frame(x: 1356, y: 296, width: 540, height: 380), b], page: page).map(\.x) == [26, 26])
        #expect(G.align(.right, frames: [Frame(x: 0, y: 296, width: 540, height: 380), Frame(x: 84, y: 687, width: 308, height: 380)], page: page).map(\.x) == [0, 232])
        #expect(G.align(.bottom, frames: [a, b], page: page).map(\.y) == [687, 687])
        #expect(G.align(.top, frames: [a, b], page: page).map(\.y) == [296, 296])
    }

    @Test func centerIsTheMeanOfTheCentersNotTheBoundingBox() {
        // VM-D7: tâm 270 và 386 → 328 (không phải 270, tâm hộp bao).
        let frames = [Frame(x: 0, y: 687, width: 540, height: 380), Frame(x: 232, y: 687, width: 308, height: 380)]
        let out = G.align(.centerH, frames: frames, page: page)
        #expect(out.map(\.x) == [58, 174])
        let sizes = zip(frames, out).allSatisfy { $0.width == $1.width && $0.height == $1.height }
        #expect(sizes)
    }

    @Test func resultIsClampedInsideThePage() {
        // VM-D7: tâm 296 và 180 → 238 làm visual rộng 540 tới x = -32: Desktop ghi 0.
        let frames = [Frame(x: 26, y: 296, width: 540, height: 380), Frame(x: 26, y: 687, width: 308, height: 380)]
        let out = G.align(.centerH, frames: frames, page: page)
        #expect(out[0].x == 0 && out[1].x == 84)
    }

    @Test func distributeHorizontallyMakesEqualGaps() {
        // VM-D7: ba thẻ x = 24, 338, 1594 rộng 302 → thẻ giữa 809.
        let frames = [Frame(x: 24, y: 176, width: 302, height: 108), Frame(x: 338, y: 176, width: 302, height: 108), Frame(x: 1594, y: 176, width: 302, height: 108)]
        let out = G.align(.distributeH, frames: frames, page: page)
        #expect(out.map(\.x) == [24, 809, 1594])
        #expect(out.map(\.y) == [176, 176, 176])
    }

    @Test func distributeKeepsInputOrderAndSortsByPosition() {
        let frames = [Frame(x: 400, y: 0, width: 100, height: 50), Frame(x: 40, y: 0, width: 100, height: 50), Frame(x: 200, y: 0, width: 150, height: 50)]
        let out = G.align(.distributeH, frames: frames, page: page)
        #expect(out[0].x == 400 && out[1].x == 40)       // hai đầu giữ nguyên
        #expect(out[2].x == 195)                          // gap = (460 - 350) / 2 = 55
    }

    @Test func distributeVertically() {
        let frames = [Frame(x: 0, y: 0, width: 50, height: 100), Frame(x: 0, y: 130, width: 50, height: 100), Frame(x: 0, y: 500, width: 50, height: 100)]
        #expect(G.align(.distributeV, frames: frames, page: page).map(\.y) == [0, 250, 500])
    }

    @Test func aWideMiddleItemExtendsTheSpan() {
        // A 0..100, B 50..450, C 60..110: nhịp lấy theo mép phải xa nhất (450), khoảng hở không âm.
        let frames = [Frame(x: 0, y: 0, width: 100, height: 10), Frame(x: 50, y: 0, width: 400, height: 10), Frame(x: 60, y: 0, width: 50, height: 10)]
        let out = G.align(.distributeH, frames: frames, page: page)
        #expect(out[0].x == 0 && out[1].x >= out[0].x + out[0].width && out[2].x >= out[1].x + out[1].width - 1 || out[1].x >= 100)
        #expect(out.allSatisfy { $0.x >= 0 })
    }

    @Test func tooFewFramesChangeNothing() {
        let two = [Frame(x: 0, y: 0, width: 10, height: 10), Frame(x: 50, y: 50, width: 10, height: 10)]
        #expect(G.align(.distributeH, frames: two, page: page) == two)
        #expect(G.align(.left, frames: [two[0]], page: page) == [two[0]])
    }
}

@Suite @MainActor struct AlignEditorTests {
    typealias Env = PageSavingTests.Env
    typealias S = SyntheticReport

    @Test func alignLeftIsOneUndoStepAndSavesOnlyChangedParts() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([S.a1, S.a2, S.a3], extend: false)
        #expect(e.align(.left))
        #expect(e.undoDepth == 1)
        #expect(e.visuals(of: "p1").map(\.x) == [40, 40, 40])
        let changes = try e.makeChanges(archive: env.archive)
        #expect(Set(changes.reportParts.keys) == [LayoutEditor.visualPath(page: "p1", id: S.a2), LayoutEditor.visualPath(page: "p1", id: S.a3)])
        _ = try env.save()
        #expect(try env.report().pages[0].visuals.map(\.x) == [40, 40, 40])
        e.undo()
        #expect(e.visuals(of: "p1").map(\.x) == [40, 200, 400])
    }

    @Test func distributeHorizontallyMovesOnlyTheMiddleOne() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([S.a1, S.a2, S.a3], extend: false)
        #expect(e.align(.distributeH))
        #expect(e.visual(S.a2)?.x == 195 && e.visual(S.a1)?.x == 40 && e.visual(S.a3)?.x == 400)
    }

    @Test func nothingToChangeMakesNoStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([S.a1, S.a2], extend: false)
        #expect(e.align(.top) == false)        // cùng y = 40
        #expect(e.undoDepth == 0)
    }

    @Test func blockersExplainWhy() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.select(S.a1)
        #expect(e.alignBlocker(.left) == "Căn lề cần chọn từ 2 visual.")
        e.setSelection([S.a1, S.a2], extend: false)
        #expect(e.alignBlocker(.left) == nil)
        #expect(e.alignBlocker(.distributeH) == "Phân bố cần chọn từ 3 visual.")
        #expect(e.align(.distributeH) == false && e.lockedReason == "Phân bố cần chọn từ 3 visual.")
    }
}
