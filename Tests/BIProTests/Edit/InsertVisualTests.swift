import CoreGraphics
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Thêm visual mới (D3): `contracts/insert-and-retype.md`.
@Suite @MainActor struct InsertVisualTests {
    typealias S = SyntheticReport
    typealias Env = FieldEditingTests.Env

    static let view = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func frame(_ env: Env, _ id: String) -> Frame? { env.editor.visual(id).map(Frame.init) }

    // MARK: thêm

    @Test func insertAddsAVisualWithNewIdDefaultSizeTopZAndSelectsIt() throws {
        let env = try Env(); defer { env.cleanUp() }
        let ids = Set(env.editor.visuals(of: "p1").map(\.id))
        let depth = env.editor.undoDepth
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        #expect(!ids.contains(id) && PBIRLayoutPatch.isValidVisualName(id))
        let visual = try #require(env.editor.visual(id))
        #expect(visual.type == "card" && visual.width == 302 && visual.height == 108)
        #expect(visual.z == (env.editor.visuals(of: "p1").filter { $0.id != id }.map(\.z).max() ?? 0) + 1000)
        #expect(env.editor.visuals(of: "p1").last?.id == id, "nằm trên cùng")
        #expect(env.editor.selection == [id] && env.editor.primary == id)
        #expect(env.editor.undoDepth == depth + 1 && env.editor.isDirty)
        #expect(visual.fields.isEmpty && visual.raw["visual"]?["query"] == nil)
        #expect(visual.raw["visual"]?["visualType"]?.string == "card")
        #expect(env.editor.fieldRefusal == nil && env.editor.notice == nil)
    }

    @Test func insertCentersOnTheVisibleRectOnTheGridAndStepsWhenCovered() throws {
        let env = try Env(); defer { env.cleanUp() }
        let first = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        // tâm vùng nhìn (500, 300), card 302×108: x = 349 → 352, y = 246 → 248
        #expect(frame(env, first) == Frame(x: 352, y: 248, width: 302, height: 108))
        // thêm lần hai vào cùng vùng: bị che gần hết thì lệch +16
        let second = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        #expect(frame(env, second) == Frame(x: 368, y: 264, width: 302, height: 108))
        // không có vùng nhìn: tâm trang 1920×1080
        let third = try #require(env.editor.insertVisual(type: "slicer", visibleRect: nil))
        #expect(frame(env, third) == Frame(x: 776, y: 512, width: 364, height: 64))
    }

    @Test func insertClampsToThePageEvenWhenTheViewIsAtTheEdge() throws {
        let env = try Env(); defer { env.cleanUp() }
        let corner = CGRect(x: 1700, y: 900, width: 220, height: 180)      // góc phải dưới của trang 1920×1080
        let id = try #require(env.editor.insertVisual(type: "clusteredBarChart", visibleRect: corner))
        let f = try #require(frame(env, id))
        #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1920 && f.y + f.height <= 1080)
        #expect(f.width == 616 && f.height == 380)
    }

    @Test func unsupportedTypesAreRefusedWithAReasonAndNothingChanges() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth, count = env.editor.visuals(of: "p1").count
        for type in ["scatterChart", "image", "clusteredColumnChart", "madeUpType"] {
            #expect(env.editor.insertVisual(type: type, visibleRect: Self.view) == nil, Comment(rawValue: type))
            #expect(env.editor.fieldRefusal?.isEmpty == false)
        }
        #expect(env.editor.undoDepth == depth && env.editor.visuals(of: "p1").count == count)
        // lần thêm hợp lệ kế tiếp xoá thông báo cũ
        #expect(env.editor.insertVisual(type: "card", visibleRect: Self.view) != nil)
        #expect(env.editor.fieldRefusal == nil)
    }

    // MARK: nhận trường

    @Test func aNewDataVisualAcceptsFieldsAndCreatesItsQueryState() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        #expect(env.editor.fieldEditingBlocker(for: id) == nil)
        #expect(env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Net"), to: "Values", visual: id) == nil)
        let visual = try #require(env.editor.visual(id))
        #expect(visual.fields.map(\.property) == ["Net"])
        #expect(visual.raw["visual"]?["query"]?["queryState"]?["Values"]?["projections"]?.array.count == 1)
        // chart mới: đủ ô để thả
        let chart = try #require(env.editor.insertVisual(type: "lineChart", visibleRect: Self.view))
        #expect(env.editor.addField(FieldRef(kind: .column, entity: "Dim_Date", property: "month_name", family: .text), to: "Category", visual: chart) == nil)
        #expect(env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Credit"), to: "Y", visual: chart) == nil)
        #expect(env.editor.visual(chart)?.fields.map(\.role).sorted() == ["Category", "Y"])
        // visual có trong file mà không có query vẫn bị từ chối (D2)
        #expect(env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Net"), to: "Values", visual: S.a1) != nil)
    }

    // MARK: xoá, nhân bản, mã không dùng lại

    @Test func deleteDuplicateAndUndoWorkOnNewVisualsAndIdsAreNeverReused() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Net"), to: "Values", visual: id)
        env.editor.select(id)
        let copy = try #require(env.editor.duplicate([id]).first)
        #expect(env.editor.visual(copy)?.fields.map(\.property) == ["Net"])
        env.editor.delete([id, copy])
        #expect(env.editor.visual(id) == nil && env.editor.visual(copy) == nil)
        env.editor.undo()
        #expect(env.editor.visual(id) != nil && env.editor.visual(copy) != nil)
        // hoàn tác thao tác thêm: mã cũ không bao giờ được dùng lại
        while env.editor.canUndo { env.editor.undo() }
        #expect(env.editor.visual(id) == nil && !env.editor.isDirty)
        var seen: Set<String> = [id, copy]
        for _ in 0..<30 {
            let new = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
            #expect(!seen.contains(new)); seen.insert(new)
            env.editor.undo()
        }
    }

    @Test func insertingFromTheRibbonStillSelectsTheNewVisualWhenAnotherIsSelected() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.select(S.a1)
        let id = try #require(env.editor.insertVisual(type: "textbox", visibleRect: Self.view))
        #expect(env.editor.selection == [id] && env.editor.primary == id)
        #expect(env.editor.visual(id)?.type == "textbox")
    }

    // MARK: vùng nhìn

    @Test func canvasViewportMathMatchesTheScrollGeometry() {
        let page = CGSize(width: 1920, height: 1080)
        // Cuộn về 0 ở zoom 50%, container 800×600, lề 16: trang bắt đầu ở (16, 16)... nằm trong container
        let top = CanvasViewport.visibleRect(offset: .zero, container: CGSize(width: 800, height: 600), pageSize: page, scale: 0.5, margin: 16)
        #expect(top.minX == 0 && top.minY == 0)
        #expect(abs(top.width - 1568) < 0.5 && abs(top.height - 1080) < 0.5)   // (800 - 16) / 0.5 = 1568, giao với trang
        // Cuộn sang phải 400 điểm ở zoom 100%: bắt đầu tại (400 - 16) / 1 = 384; phía trên bị lề 16 cắt (584 cao)
        let right = CanvasViewport.visibleRect(offset: CGPoint(x: 400, y: 0), container: CGSize(width: 800, height: 600), pageSize: page, scale: 1, margin: 16)
        #expect(abs(right.minX - 384) < 0.5 && right.minY == 0 && right.width == 800 && right.height == 584)
        // Trang bé hơn container: cả trang
        let small = CanvasViewport.visibleRect(offset: .zero, container: CGSize(width: 4000, height: 3000), pageSize: page, scale: 1, margin: 16)
        #expect(small == CGRect(origin: .zero, size: page))
        // Dữ liệu không tính được: cả trang
        #expect(CanvasViewport.visibleRect(offset: .zero, container: .zero, pageSize: page, scale: 1, margin: 16) == CGRect(origin: .zero, size: page))
    }
}
