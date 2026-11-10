import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Hoàn tác chung một lịch sử với D1 đến D5 (D4): `specs/006-d4-format-pane/contracts/format-editing.md` mục "Bước hoàn tác".
@Suite @MainActor struct FormatUndoTests {
    typealias S = SyntheticReport
    typealias Env = FormatEditingTests.Env

    /// Dấu vân tay của toàn bộ trạng thái sửa: thứ tự trang, mọi visual (vị trí, trường, định dạng).
    func signature(_ editor: LayoutEditor) -> String {
        editor.pages.map { page in
            let visuals = editor.visuals(of: page.id).sorted { $0.id < $1.id }.map { v in
                "\(v.id)|\(v.type)|\(v.x),\(v.y)|\(v.fields.map { "\($0.role).\($0.property)" })|\(v.objects.json)|\(v.containerObjects.json)"
            }
            return "\(page.id):\(page.displayName)\n" + visuals.joined(separator: "\n")
        }.joined(separator: "\n--\n")
    }

    // MARK: (a) chuỗi hỗn hợp

    @Test func aMixedHistoryUndoesAndRedoesStepByStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let tick = Box(Date(timeIntervalSince1970: 1_000))
        e.now = { tick.advance(); return tick.date }       // mỗi thao tác cách nhau 1 s: không gộp theo thời gian
        var states = [signature(e)]
        func step(_ body: () -> Void) { body(); states.append(signature(e)) }

        step { e.move([S.a1], dx: 40, dy: 24, snap: true) }                                                                                  // D1
        step { e.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1) }                   // D4
        step { e.addField(FieldRef(kind: .measure, entity: "Fact", property: "Balance"), to: "Y", visual: S.c1) }                           // D2
        step { e.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1) }                                  // D4
        step { _ = e.insertVisual(type: "card", visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600)) }                                  // D3
        step { e.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: S.f2) }                               // D4
        step { _ = e.addPage() }                                                                                                              // D5
        step { e.openPage("p1"); e.resetFormat(scope: .objects, object: "labels", visual: S.f1) }                                            // D4 (đặt lại)
        let steps = states.count - 1
        #expect(e.undoDepth >= steps)
        for index in stride(from: steps - 1, through: 0, by: -1) {
            e.undo()
            e.openPage("p1")
            #expect(signature(e) == states[index], Comment(rawValue: "sau hoàn tác về bước \(index)"))
        }
        #expect(!e.isDirty)
        for index in 1...steps {
            e.redo()
            e.openPage("p1")
            #expect(signature(e) == states[index], Comment(rawValue: "sau làm lại tới bước \(index)"))
        }
    }

    // MARK: (b) gộp bước

    @Test func repeatedEditsOfOnePropertyAreOneStepAndAnotherPropertyIsAnotherStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let now = Date(timeIntervalSince1970: 5_000)
        e.now = { now }                                           // thời gian đứng yên: mọi lần gọi trong cửa sổ gộp
        let depth = e.undoDepth
        for size in [21.0, 22, 23, 24, 25] {
            #expect(e.setFormat(.number(size, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1) == nil)
        }
        #expect(e.undoDepth == depth + 1)
        #expect(e.visual(S.f1)?.objects.number("labels", "fontSize") == 25)
        e.setFormat(.bool(true), scope: .objects, object: "labels", property: "bold", visual: S.f1)
        #expect(e.undoDepth == depth + 2)
        e.setFormat(.number(30, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        #expect(e.undoDepth == depth + 3, "đổi thuộc tính khác rồi quay lại là bước mới")
        e.undo()
        #expect(e.visual(S.f1)?.objects.number("labels", "fontSize") == 25 && e.visual(S.f1)?.objects.bool("labels", "bold") == true)
        e.undo(); e.undo()
        #expect(e.visual(S.f1)?.objects.number("labels", "fontSize") == 20 && !e.isDirty)
    }

    @Test func editsFarApartInTimeAreSeparateSteps() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let clock = Box(Date(timeIntervalSince1970: 100))
        e.now = { clock.date }
        e.setFormat(.number(21, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        clock.date = clock.date.addingTimeInterval(2)
        e.setFormat(.number(22, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        #expect(e.undoDepth == 2)
    }

    // MARK: (c) về trạng thái đã lưu

    @Test func undoingBackToTheStartIsCleanAndLeavesNothingToSave() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let tick = Box(Date(timeIntervalSince1970: 1_000))
        e.now = { tick.advance(); return tick.date }
        e.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1)
        e.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: S.f1)
        e.resetFormat(scope: .objects, object: "categoryLabels", visual: S.f1)
        #expect(e.isDirty)
        e.undo(); e.undo(); e.undo()
        #expect(!e.isDirty)
        #expect(try e.makeChanges(archive: env.archive).reportParts.isEmpty)
    }

    // MARK: (d) đổi loại

    @Test func undoingATypeChangeBringsBackTheFormatItDropped() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let tick = Box(Date(timeIntervalSince1970: 1_000))
        e.now = { tick.advance(); return tick.date }
        e.setFormat(.bool(true), scope: .objects, object: "zoom", property: "show", visual: S.c1)
        e.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1)
        let before = signature(e)
        let reason = e.changeType(of: S.c1, to: "donutChart")
        try #require(reason == nil, "\(reason ?? "")")
        #expect(e.visual(S.c1)?.objects.has("zoom") == false)
        e.undo()
        #expect(signature(e) == before && e.visual(S.c1)?.objects.has("zoom") == true)
        e.redo()
        #expect(e.visual(S.c1)?.objects.has("zoom") == false && e.visual(S.c1)?.objects.has("legend") == true)
    }

    // MARK: (e) giới hạn lịch sử

    @Test func historyLimitStillHoldsWithFormatSteps() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let tick = Box(Date(timeIntervalSince1970: 1_000))
        e.now = { tick.advance(); return tick.date }
        for index in 0..<(LayoutEditor.historyLimit + 5) {
            e.setFormat(.number(Double(1 + index % 50), tail: .d), scope: .container, object: "padding", property: index.isMultiple(of: 2) ? "top" : "left", visual: S.f1)
        }
        #expect(e.undoDepth <= LayoutEditor.historyLimit)
    }
}

/// Đồng hồ giả: mỗi lần `advance` tiến 1 giây.
private final class Box: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
    func advance() { date = date.addingTimeInterval(1) }
}
