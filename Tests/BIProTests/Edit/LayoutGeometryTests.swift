import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Hình học sửa bố cục, theo `specs/002-d1-canvas-luu-t1/contracts/layout-editing.md`.
@Suite struct LayoutGeometryTests {
    private let page = PageBounds(width: 1920, height: 1080)
    private typealias G = LayoutGeometry

    private func visual(_ id: String, x: Double, y: Double, w: Double, h: Double, z: Double, hidden: Bool = false) -> ReportVisual {
        ReportVisual(id: id, type: "card", x: x, y: y, z: z, width: w, height: h, isHidden: hidden)
    }

    // MARK: snap

    @Test func snapRoundsToNearestMultipleOfGrid() {
        #expect(G.snap(0) == 0)
        #expect(G.snap(3) == 0)
        #expect(G.snap(4) == 8)   // nửa lưới làm tròn lên
        #expect(G.snap(11) == 8)
        #expect(G.snap(12) == 16)
        #expect(G.snap(1594) == 1592)
        #expect(G.snap(-3) == 0)
        #expect(G.snap(-5) == -8)
    }

    // MARK: move

    @Test func moveSnapsOriginAndKeepsSize() {
        let f = Frame(x: 100, y: 100, width: 302, height: 108)
        let m = G.move(f, dx: 45, dy: -13, page: page, snap: true)
        #expect(m == Frame(x: 144, y: 88, width: 302, height: 108))   // 145 → 144, 87 → 88
    }

    @Test func moveWithoutSnapIsFree() {
        let f = Frame(x: 100, y: 100, width: 50, height: 50)
        #expect(G.move(f, dx: 3, dy: 5, page: page, snap: false) == Frame(x: 103, y: 105, width: 50, height: 50))
    }

    @Test func moveIsClampedInsideThePageOnAllFourSides() {
        let f = Frame(x: 100, y: 100, width: 200, height: 100)
        #expect(G.move(f, dx: -500, dy: 0, page: page, snap: true).x == 0)
        #expect(G.move(f, dx: 0, dy: -500, page: page, snap: true).y == 0)
        #expect(G.move(f, dx: 5000, dy: 0, page: page, snap: true).x == 1920 - 200)
        #expect(G.move(f, dx: 0, dy: 5000, page: page, snap: true).y == 1080 - 100)
        // Visual lớn hơn trang: dính góc trên trái, không âm.
        let big = Frame(x: 0, y: 0, width: 3000, height: 2000)
        let m = G.move(big, dx: 50, dy: 50, page: page, snap: true)
        #expect(m.x == 0 && m.y == 0)
    }

    @Test func moveGroupKeepsRelativePositionsAndClampsByBoundingBox() {
        let a = Frame(x: 1594, y: 176, width: 302, height: 108)   // lệch lưới
        let b = Frame(x: 1606, y: 198, width: 40, height: 40)
        let moved = G.move([a, b], dx: -40, dy: 16, page: page, snap: true)
        #expect(moved.count == 2)
        #expect(moved[1].x - moved[0].x == b.x - a.x)
        #expect(moved[1].y - moved[0].y == b.y - a.y)
        // Khung bao có gốc trên lưới.
        let box = G.boundingBox(moved)!
        #expect(box.x % 8 == 0 && box.y % 8 == 0)
        // Kéo quá phải: khung bao dừng ở mép trang, vị trí tương đối giữ nguyên.
        let edge = G.move([a, b], dx: 4000, dy: 0, page: page, snap: true)
        let edgeBox = G.boundingBox(edge)!
        #expect(edgeBox.x + edgeBox.width == 1920)
        #expect(edge[1].x - edge[0].x == b.x - a.x)
    }

    @Test func moveSingleEqualsMoveGroupOfOne() {
        let f = Frame(x: 37, y: 91, width: 120, height: 60)
        for (dx, dy) in [(5, 5), (-100, 40), (4000, -4000), (3, 0)] {
            #expect(G.move([f], dx: dx, dy: dy, page: page, snap: true) == [G.move(f, dx: dx, dy: dy, page: page, snap: true)])
        }
    }

    // MARK: resize

    @Test func resizeEastAndSouthChangeOnlyTheirEdge() {
        let f = Frame(x: 100, y: 100, width: 200, height: 100)
        let e = G.resize(f, handle: .e, dx: 37, dy: 999, page: page, snap: true)
        #expect(e.x == 100 && e.y == 100 && e.height == 100)
        #expect((e.x + e.width) % 8 == 0 && e.width == 236)   // cạnh phải 337 → 336
        let s = G.resize(f, handle: .s, dx: 999, dy: 21, page: page, snap: true)
        #expect(s.x == 100 && s.width == 200)
        #expect((s.y + s.height) % 8 == 0 && s.height == 124)  // cạnh dưới 221 → 224
    }

    @Test func resizeWestAndNorthKeepOppositeEdgeStill() {
        let f = Frame(x: 100, y: 100, width: 200, height: 100)
        let w = G.resize(f, handle: .w, dx: -30, dy: 0, page: page, snap: true)
        #expect(w.x + w.width == 300)           // cạnh phải đứng yên
        #expect(w.x % 8 == 0 && w.x == 72)      // 70 → 72
        let n = G.resize(f, handle: .n, dx: 0, dy: -30, page: page, snap: true)
        #expect(n.y + n.height == 200)
        #expect(n.y % 8 == 0 && n.y == 72)
    }

    @Test func resizeCornersCombineTwoEdges() {
        let f = Frame(x: 100, y: 100, width: 200, height: 100)
        let se = G.resize(f, handle: .se, dx: 40, dy: 40, page: page, snap: true)
        #expect(se.x == 100 && se.y == 100)
        #expect(se.width == 244 && se.height == 140)   // 340 → 344 (nửa lưới làm tròn lên)
        let nw = G.resize(f, handle: .nw, dx: -40, dy: -40, page: page, snap: true)
        #expect(nw.x + nw.width == 300 && nw.y + nw.height == 200)
        #expect(nw.x == 64 && nw.y == 64)
        let ne = G.resize(f, handle: .ne, dx: 40, dy: -40, page: page, snap: true)
        #expect(ne.x == 100 && ne.y + ne.height == 200 && ne.y == 64 && ne.width == 244)
        let sw = G.resize(f, handle: .sw, dx: -40, dy: 40, page: page, snap: true)
        #expect(sw.x + sw.width == 300 && sw.y == 100 && sw.x == 64 && sw.height == 140)
    }

    @Test func resizeNeverFlipsAndKeepsMinimumSize() {
        let f = Frame(x: 100, y: 100, width: 200, height: 100)
        // Kéo cạnh phải quá cạnh trái.
        let e = G.resize(f, handle: .e, dx: -1000, dy: 0, page: page, snap: true)
        #expect(e.x == 100 && e.width == G.minSize)
        // Kéo cạnh trái quá cạnh phải.
        let w = G.resize(f, handle: .w, dx: 1000, dy: 0, page: page, snap: true)
        #expect(w.x + w.width == 300 && w.width == G.minSize)
        let n = G.resize(f, handle: .n, dx: 0, dy: 1000, page: page, snap: true)
        #expect(n.y + n.height == 200 && n.height == G.minSize)
        let s = G.resize(f, handle: .s, dx: 0, dy: -1000, page: page, snap: true)
        #expect(s.y == 100 && s.height == G.minSize)
    }

    @Test func resizeIsClampedInsideThePage() {
        let f = Frame(x: 1800, y: 1000, width: 100, height: 60)
        let se = G.resize(f, handle: .se, dx: 500, dy: 500, page: page, snap: true)
        #expect(se.x + se.width == 1920 && se.y + se.height == 1080)
        let nw = G.resize(f, handle: .nw, dx: -5000, dy: -5000, page: page, snap: true)
        #expect(nw.x == 0 && nw.y == 0 && nw.x + nw.width == 1900 && nw.y + nw.height == 1060)
    }

    @Test func resizeWithoutSnapGivesExactIntegers() {
        let f = Frame(x: 100, y: 100, width: 200, height: 100)
        let r = G.resize(f, handle: .se, dx: 3, dy: 5, page: page, snap: false)
        #expect(r == Frame(x: 100, y: 100, width: 203, height: 105))
    }

    @Test func everyHandleLeavesTheFrameValid() {
        let f = Frame(x: 100, y: 100, width: 200, height: 100)
        for handle in ResizeHandle.allCases {
            for (dx, dy) in [(0, 0), (13, -7), (-900, 900), (4000, 4000), (-4000, -4000)] {
                for snap in [true, false] {
                    let r = G.resize(f, handle: handle, dx: dx, dy: dy, page: page, snap: snap)
                    #expect(r.x >= 0 && r.y >= 0 && r.x + r.width <= 1920 && r.y + r.height <= 1080, "\(handle) \(dx),\(dy)")
                    #expect(r.width >= G.minSize && r.height >= G.minSize, "\(handle) \(dx),\(dy)")
                }
            }
        }
    }

    // MARK: bounding box, hit, marquee

    @Test func boundingBoxCoversAllFrames() {
        let box = G.boundingBox([Frame(x: 10, y: 20, width: 30, height: 40), Frame(x: 100, y: 5, width: 10, height: 10)])
        #expect(box == Frame(x: 10, y: 5, width: 100, height: 55))
        #expect(G.boundingBox([]) == nil)
    }

    @Test func hitPicksTopmostVisibleVisual() {
        let visuals = [visual("low", x: 0, y: 0, w: 100, h: 100, z: 1000),
                       visual("high", x: 50, y: 50, w: 100, h: 100, z: 2000),
                       visual("hidden", x: 50, y: 50, w: 100, h: 100, z: 3000, hidden: true)]
        #expect(G.hit(x: 60, y: 60, in: visuals, isHidden: { $0.isHidden }) == "high")
        #expect(G.hit(x: 10, y: 10, in: visuals, isHidden: { $0.isHidden }) == "low")
        #expect(G.hit(x: 500, y: 500, in: visuals, isHidden: { $0.isHidden }) == nil)
        // Cạnh phải/dưới nằm ngoài (nửa mở).
        #expect(G.hit(x: 100, y: 10, in: visuals, isHidden: { $0.isHidden }) == nil)
    }

    @Test func marqueeSelectsVisibleVisualsThatIntersect() {
        let visuals = [visual("a", x: 0, y: 0, w: 100, h: 100, z: 1000),
                       visual("b", x: 200, y: 200, w: 100, h: 100, z: 2000),
                       visual("c", x: 90, y: 90, w: 50, h: 50, z: 3000),
                       visual("h", x: 0, y: 0, w: 500, h: 500, z: 4000, hidden: true)]
        let ids = G.marquee(Frame(x: 80, y: 80, width: 30, height: 30), visuals: visuals, isHidden: { $0.isHidden })
        #expect(Set(ids) == ["a", "c"])
        #expect(G.marquee(Frame(x: 600, y: 600, width: 10, height: 10), visuals: visuals, isHidden: { $0.isHidden }).isEmpty)
        // Chỉ chạm cạnh thì không tính giao.
        #expect(G.marquee(Frame(x: 100, y: 0, width: 50, height: 50), visuals: visuals, isHidden: { $0.isHidden }).isEmpty)
    }

    @Test func frameRoundTripsThroughVisual() {
        let v = visual("v", x: 12.4, y: 7.6, w: 99.5, h: 40, z: 1000)
        let f = Frame(v)
        #expect(f == Frame(x: 12, y: 8, width: 100, height: 40))
    }
}
