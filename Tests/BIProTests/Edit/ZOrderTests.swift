import Testing
@testable import BIPro

/// Thứ tự lớp: hoán vị đúng cho Bring forward / to front / Send backward / to back (ids theo z tăng dần = dưới → trên).
@Suite @MainActor struct ZOrderTests {
    private let ids = ["a", "b", "c", "d", "e"]
    private func run(_ moving: Set<String>, _ command: ZOrderCommand) -> [String] {
        LayoutEditor.reordered(ids, moving: moving, command)
    }

    @Test func bringForwardMovesOneStepAndStopsAtTheTop() {
        #expect(run(["b"], .forward) == ["a", "c", "b", "d", "e"])
        #expect(run(["e"], .forward) == ids)
    }

    @Test func sendBackwardMovesOneStepAndStopsAtTheBottom() {
        #expect(run(["d"], .backward) == ["a", "b", "d", "c", "e"])
        #expect(run(["a"], .backward) == ids)
    }

    @Test func frontAndBackKeepTheRelativeOrderOfTheSelection() {
        #expect(run(["b", "d"], .front) == ["a", "c", "e", "b", "d"])
        #expect(run(["b", "d"], .back) == ["b", "d", "a", "c", "e"])
    }

    @Test func aMultiSelectionMovesTogetherByOneStep() {
        #expect(run(["b", "c"], .forward) == ["a", "d", "b", "c", "e"])
        #expect(run(["c", "d"], .backward) == ["a", "c", "d", "b", "e"])
    }
}
