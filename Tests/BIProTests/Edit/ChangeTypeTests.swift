import CoreGraphics
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Đổi loại visual (D3): `contracts/insert-and-retype.md`.
@Suite @MainActor struct ChangeTypeTests {
    typealias S = SyntheticReport
    typealias Env = FieldEditingTests.Env

    func props(_ env: Env, _ role: String, id: String = S.c1) -> [String] {
        env.editor.visual(id)?.fields.filter { $0.role == role }.map(\.property) ?? []
    }

    // MARK: đổi loại giữ trường và khung

    @Test func comboToLineKeepsFrameMovesY2IntoYAndIsOneUndoStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try #require(env.editor.visual(S.c1))
        let depth = env.editor.undoDepth
        #expect(env.editor.changeType(of: S.c1, to: "lineChart") == nil)
        let after = try #require(env.editor.visual(S.c1))
        #expect(after.type == "lineChart" && after.raw["visual"]?["visualType"]?.string == "lineChart")
        #expect(after.x == before.x && after.y == before.y && after.width == before.width && after.height == before.height && after.z == before.z)
        #expect(props(env, "Y") == ["Credit", "Debit", "Net"] && props(env, "Y2").isEmpty)
        #expect(props(env, "Category") == ["month_name"] && props(env, "Tooltips") == ["Avg"])
        #expect(env.editor.notice == nil && env.editor.fieldRefusal == nil)
        #expect(env.editor.undoDepth == depth + 1)
        env.editor.undo()
        #expect(env.editor.visual(S.c1) == before && !env.editor.isDirty)
        env.editor.redo()
        #expect(env.editor.visual(S.c1) == after)
    }

    @Test func barKeepsEverythingAndColumn100DropsTooltipsWithANotice() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.changeType(of: S.c1, to: "clusteredBarChart") == nil)
        #expect(env.editor.visual(S.c1)?.type == "clusteredBarChart" && env.editor.notice == nil)
        #expect(env.editor.changeType(of: S.c1, to: "hundredPercentStackedColumnChart") == nil)
        #expect(props(env, "Tooltips").isEmpty && props(env, "Y") == ["Credit", "Debit", "Net"])
        #expect(env.editor.notice?.contains("Avg") == true)
        // hoàn tác từng bước
        env.editor.undo()
        #expect(env.editor.visual(S.c1)?.type == "clusteredBarChart" && props(env, "Tooltips") == ["Avg"])
        env.editor.undo()
        #expect(env.editor.visual(S.c1)?.type == "lineClusteredColumnComboChart" && props(env, "Y2") == ["Net"])
    }

    // MARK: chặn, không đổi, từ chối

    @Test func isBlockedWhenADroppedFieldStillDrivesTheSort() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try #require(env.editor.visual(S.c1))
        let depth = env.editor.undoDepth
        let reason = env.editor.changeType(of: S.c1, to: "card")    // card chỉ nhận một measure: month_name (sắp xếp) bị bỏ
        #expect(reason?.contains("sắp xếp") == true && env.editor.fieldRefusal == reason)
        #expect(env.editor.visual(S.c1) == before && env.editor.undoDepth == depth)
    }

    @Test func sameTypeAndRefusedTargetsChangeNothing() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try #require(env.editor.visual(S.c1))
        let depth = env.editor.undoDepth
        #expect(env.editor.changeType(of: S.c1, to: "lineClusteredColumnComboChart") == nil)
        #expect(env.editor.undoDepth == depth)
        for type in ["scatterChart", "textbox", "clusteredColumnChart", "madeUp"] {
            #expect(env.editor.changeType(of: S.c1, to: type) != nil, Comment(rawValue: type))
        }
        #expect(env.editor.changeType(of: "zzzzzzzzzzzzzzzzzzzz", to: "lineChart") != nil)
        #expect(env.editor.visual(S.c1) == before && env.editor.undoDepth == depth)
        // visual nguồn là hộp văn bản: không đổi loại
        let box = try #require(env.editor.insertVisual(type: "textbox", visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600)))
        #expect(env.editor.changeType(of: box, to: "card")?.contains("Hộp văn bản") == true)
        #expect(env.editor.visual(box)?.type == "textbox")
    }

    @Test func cardToSlicerDropsTheMeasureAndSaysSo() throws {
        let env = try Env(); defer { env.cleanUp() }
        let card = try #require(env.editor.insertVisual(type: "card", visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600)))
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Net"), to: "Values", visual: card)
        #expect(env.editor.changeType(of: card, to: "slicer") == nil)
        #expect(env.editor.visual(card)?.type == "slicer" && env.editor.visual(card)?.fields.isEmpty == true)
        #expect(env.editor.notice?.contains("Net") == true)
        env.editor.undo()
        #expect(env.editor.visual(card)?.type == "card" && env.editor.visual(card)?.fields.map(\.property) == ["Net"])
    }

    // MARK: định dạng (objects)

    @Test func objectKeysAreKeptOnlyWhenAVisualOfTheTargetTypeInTheReportHasThem() throws {
        let objects = #""objects":{"dataPoint":[{"properties":{}}],"labels":[{"properties":{}}],"legend":[{"properties":{}}]}"#
        let chart = Data(#"{"name":"\#(S.c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"lineClusteredColumnComboChart","query":{"queryState":{"Category":{"projections":[\#(S.proj("Column", "Dim_Date", "month_name"))]},"Y":{"projections":[\#(S.proj("Measure", "Fact", "Credit"))]}}},\#(objects)}}"#.utf8)
        let dir = S.temporaryDirectory("retype-objects"); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try S.make(in: dir, withChart: true, chart: chart)
        let archive = try ZipArchive(url: source)
        var report = try PBIXFile(url: source).loadReport()
        // Một visual đường có sẵn trong báo cáo với khoá labels và valueAxis.
        let sample = try JSONValue.parse(Data(#"{"visual":{"visualType":"lineChart","objects":{"labels":[{}],"valueAxis":[{}]}}}"#.utf8))
        report.pages[0].visuals.append(ReportVisual(id: "ddddddddddddddddddd1", type: "lineChart", raw: sample))
        let editor = LayoutEditor(report: report, sourceJSON: { page, id in try? archive.read(LayoutEditor.visualPath(page: page, id: id)) })
        editor.showPage("p1")
        #expect(editor.changeType(of: S.c1, to: "lineChart") == nil)
        let keys = Set(editor.visual(S.c1)?.raw["visual"]?["objects"]?.object.keys.map { $0 } ?? [])
        #expect(keys == ["labels"], "chỉ giữ khoá thấy trên visual đường trong báo cáo")
        #expect(editor.notice?.contains("dataPoint") == true && editor.notice?.contains("legend") == true)
        // Loại đích không có visual nào trong báo cáo: bỏ hết.
        #expect(editor.changeType(of: S.c1, to: "donutChart") == nil)
        #expect(editor.visual(S.c1)?.raw["visual"]?["objects"]?.object.isEmpty == true)
        editor.undo(); editor.undo()
        #expect(Set(editor.visual(S.c1)?.raw["visual"]?["objects"]?.object.keys.map { $0 } ?? []) == ["dataPoint", "labels", "legend"])
    }

    // MARK: visual mới và sửa trường sau khi đổi loại

    @Test func retypingANewVisualMovesItsFieldsAndKeepsTheTypeAcrossLaterFieldEdits() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "lineChart", visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 600)))
        env.editor.addField(FieldRef(kind: .column, entity: "Dim_Date", property: "month_name", family: .text), to: "Category", visual: id)
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Credit"), to: "Y", visual: id)
        #expect(env.editor.changeType(of: id, to: "clusteredBarChart") == nil)
        #expect(env.editor.visual(id)?.type == "clusteredBarChart" && props(env, "Y", id: id) == ["Credit"])
        // sửa trường tiếp: loại giữ nguyên (ghép từ byte đã đổi loại)
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Debit"), to: "Y", visual: id)
        #expect(env.editor.visual(id)?.type == "clusteredBarChart" && env.editor.visual(id)?.raw["visual"]?["visualType"]?.string == "clusteredBarChart")
        #expect(props(env, "Y", id: id) == ["Credit", "Debit"])
    }

    @Test func fieldEditsAfterRetypingAFileVisualKeepTheNewType() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.changeType(of: S.c1, to: "lineChart") == nil)
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Balance"), to: "Y", visual: S.c1)
        #expect(env.editor.visual(S.c1)?.type == "lineChart" && env.editor.visual(S.c1)?.raw["visual"]?["visualType"]?.string == "lineChart")
        #expect(props(env, "Y") == ["Credit", "Debit", "Net", "Balance"])
        // nhân bản sau khi đổi loại mang đúng loại
        env.editor.select(S.c1)
        let copy = try #require(env.editor.duplicate([S.c1]).first)
        #expect(env.editor.visual(copy)?.raw["visual"]?["visualType"]?.string == "lineChart")
    }
}
