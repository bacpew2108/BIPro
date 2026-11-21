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

    @Test func comboToLineKeepsFrameAndY2AndIsOneUndoStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try #require(env.editor.visual(S.c1))
        let depth = env.editor.undoDepth
        #expect(env.editor.changeType(of: S.c1, to: "lineChart") == nil)
        let after = try #require(env.editor.visual(S.c1))
        #expect(after.type == "lineChart" && after.raw["visual"]?["visualType"]?.string == "lineChart")
        #expect(after.x == before.x && after.y == before.y && after.width == before.width && after.height == before.height && after.z == before.z)
        #expect(props(env, "Y") == ["Credit", "Debit"] && props(env, "Y2") == ["Net"])   // VM-D3: Desktop giữ Y2
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

    // MARK: sắp xếp mặc định khi đổi sang cột/thanh (VM-D9 mục 1)

    private static var lineWithoutSort: Data {
        Data(#"{"$schema":"s","name":"\#(S.c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"lineChart","query":{"queryState":{"Category":{"projections":[\#(S.proj("Column", "Dim_Date", "month_start", extra: #","active":true"#))]},"Y":{"projections":[\#(S.proj("Measure", "Fact", "Credit"))]}}},"drillFilterOtherVisuals":true}}"#.utf8)
    }

    @Test func aClusteredColumnKeepsTheTooltipsLikeDesktop() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.changeType(of: S.c1, to: "clusteredColumnChart") == nil)
        #expect(props(env, "Tooltips") == ["Avg"])
        #expect(env.editor.notice?.contains("Avg") != true)   // Y2 (Net) không có ở loại mới; Tooltips thì còn
    }

    @Test func aLineOverADateColumnBecomesAColumnChartSortedAscendingByIt() throws {
        let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
        env.editor.dateColumns = ["Dim_Date[month_start]"]
        #expect(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["sortDefinition"] == nil)
        #expect(env.editor.changeType(of: S.c1, to: "clusteredColumnChart") == nil)
        let sort = try #require(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["sortDefinition"])
        #expect(sort["isDefaultSort"]?.bool == true)
        #expect(sort["sort"]?[0]?["direction"]?.string == "Ascending")
        #expect(sort["sort"]?[0]?["field"]?["Column"]?["Property"]?.string == "month_start")
        env.editor.undo()
        #expect(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["sortDefinition"] == nil)
    }

    /// Lỗi gặp khi thử trong app: sắp xếp chỉ có ở bản trong bộ nhớ, lúc lưu (dựng lại từ file gốc) thì mất.
    @Test func theDateSortSurvivesSavingAndALaterCategoryReplacement() throws {
        let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
        env.editor.dateColumns = ["Dim_Date[month_start]", "Dim_Date[full_date]"]
        #expect(env.editor.changeType(of: S.c1, to: "clusteredColumnChart") == nil)
        func saved() throws -> JSONValue {
            let changes = try env.editor.makeChanges(archive: env.archive)
            let data = try #require(changes.reportParts[LayoutEditor.visualPath(page: "p1", id: S.c1)])
            return try JSONValue.parse(data)
        }
        var sort = try #require(try saved()["visual"]?["query"]?["sortDefinition"])
        #expect(sort["sort"]?[0]?["field"]?["Column"]?["Property"]?.string == "month_start" && sort["isDefaultSort"]?.bool == true)
        // Thay cột Category bằng cột ngày khác: sắp xếp đi theo cột mới.
        #expect(env.editor.addField(FieldRef(kind: .column, entity: "Dim_Date", property: "full_date", family: .date), to: "Category", visual: S.c1) == nil)
        sort = try #require(try saved()["visual"]?["query"]?["sortDefinition"])
        #expect(sort["sort"]?[0]?["field"]?["Column"]?["Property"]?.string == "full_date")
    }

    @Test func noSortIsAddedForTextCategories() throws {
        let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
        // Cột chữ (không biết Desktop sắp thế nào): không đoán.
        #expect(env.editor.changeType(of: S.c1, to: "clusteredColumnChart") == nil)
        #expect(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["sortDefinition"] == nil)
    }

    /// VM-D12: combo, donut và slicer (và vùng, ruy-băng, thác nước, phễu khi BI Pro hỗ trợ làm đích) cũng thêm sắp xếp mặc định; treemap thì không.
    @Test func everySupportedAxisTargetSortsAscendingByTheDateColumnExceptTreemap() throws {
        for type in ["lineClusteredColumnComboChart", "lineStackedColumnComboChart", "donutChart", "slicer", "treemap"] {
            let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
            env.editor.dateColumns = ["Dim_Date[month_start]"]
            #expect(env.editor.changeType(of: S.c1, to: type) == nil, "\(type)")
            let sort = env.editor.visual(S.c1)?.raw["visual"]?["query"]?["sortDefinition"]
            if type == "treemap" {
                #expect(sort == nil, "\(type)")
            } else {
                #expect(sort?["isDefaultSort"]?.bool == true, "\(type)")
                #expect(sort?["sort"]?[0]?["direction"]?.string == "Ascending", "\(type)")
                #expect(sort?["sort"]?[0]?["field"]?["Column"]?["Property"]?.string == "month_start", "\(type)")
            }
        }
    }

    /// VM-D12: đường có Category ngày và Y, Chú giải công cụ (`Tooltips`) đổi sang matrix hoặc slicer như Desktop.
    @Test func aLineBecomesAMatrixWithRowsAndAllMeasuresLikeDesktop() throws {
        let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
        #expect(env.editor.changeType(of: S.c1, to: "pivotTable") == nil)
        #expect(props(env, "Rows") == ["month_start"] && props(env, "Values") == ["Credit"])
    }

    @Test func aLineBecomesASlicerOverItsCategory() throws {
        let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
        #expect(env.editor.changeType(of: S.c1, to: "slicer") == nil)
        #expect(props(env, "Values") == ["month_start"])
    }

    // MARK: bản đồ hình (VM-D12)

    private static let shapeReport = Data(#"{"resourcePackages":[{"name":"SharedResources","type":"SharedResources","items":[{"name":"usa.states.topo","path":"Shapemaps/usa.states.topo.json","type":"ShapeMap"}]}]}"#.utf8)

    private func shapeEditor(_ env: Env, withResource: Bool) throws -> LayoutEditor {
        let archive = env.archive
        let report = try PBIXFile(url: env.source).loadReport()
        let editor = LayoutEditor(report: report, sourceJSON: { page, id in try? archive.read(LayoutEditor.visualPath(page: page, id: id)) },
                                  openedParts: { prefix in
            withResource && prefix == LayoutEditor.reportJSONPath ? [(LayoutEditor.reportJSONPath, Self.shapeReport)] : []
        })
        editor.showPage("p1")
        return editor
    }

    @Test func aLineBecomesAShapeMapWithSeriesValueAndTheShapeObjects() throws {
        let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
        let editor = try shapeEditor(env, withResource: true)
        #expect(editor.changeType(of: S.c1, to: "shapeMap") == nil)
        let fields = editor.visual(S.c1)?.fields ?? []
        #expect(fields.filter { $0.role == "Series" }.map(\.property) == ["month_start"])
        #expect(fields.filter { $0.role == "Value" }.map(\.property) == ["Credit"])
        #expect(fields.filter { $0.role == "Category" }.isEmpty)
        let objects = try #require(editor.visual(S.c1)?.raw["visual"]?["objects"])
        #expect(objects["shape"]?[0]?["properties"]?["map"]?["geoJson"]?["name"]?["expr"]?["Literal"]?["Value"]?.string == "'usa.states.topo'")
        #expect(objects["dataPoint"]?[0]?["properties"]?["fillRule"]?["linearGradient2"] != nil)
        editor.undo()
        #expect(editor.visual(S.c1)?.raw["visual"]?["objects"]?["shape"] == nil)
    }

    @Test func aShapeMapNeedsTheMapResourceInTheFile() throws {
        let env = try Env(chart: Self.lineWithoutSort); defer { env.cleanUp() }
        let editor = try shapeEditor(env, withResource: false)
        #expect(editor.changeType(of: S.c1, to: "shapeMap")?.contains("usa.states.topo") == true)
        #expect(editor.visual(S.c1)?.type == "lineChart")
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
        for type in ["textbox", "shape", "actionButton", "madeUp"] {
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

    @Test func onlyObjectKeysThatStopMakingSenseAreDroppedWhenRetyping() throws {
        let objects = #""objects":{"dataPoint":[{"properties":{}}],"labels":[{"properties":{}}],"legend":[{"properties":{}}],"valueAxis":[{"properties":{}}]}"#
        let chart = Data(#"{"name":"\#(S.c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"lineClusteredColumnComboChart","query":{"queryState":{"Category":{"projections":[\#(S.proj("Column", "Dim_Date", "month_name"))]},"Y":{"projections":[\#(S.proj("Measure", "Fact", "Credit"))]}}},\#(objects)}}"#.utf8)
        let dir = S.temporaryDirectory("retype-objects"); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try S.make(in: dir, withChart: true, chart: chart)
        let archive = try ZipArchive(url: source)
        let report = try PBIXFile(url: source).loadReport()
        let editor = LayoutEditor(report: report, sourceJSON: { page, id in try? archive.read(LayoutEditor.visualPath(page: page, id: id)) })
        editor.showPage("p1")
        // combo → đường: giữ hết (VM-D3: Desktop không bỏ gì)
        #expect(editor.changeType(of: S.c1, to: "lineChart") == nil)
        #expect(Set(editor.visual(S.c1)?.raw["visual"]?["objects"]?.object.keys.map { $0 } ?? []) == ["dataPoint", "labels", "legend", "valueAxis"])
        #expect(editor.notice == nil)
        // đường → donut: chỉ bỏ valueAxis
        #expect(editor.changeType(of: S.c1, to: "donutChart") == nil)
        #expect(Set(editor.visual(S.c1)?.raw["visual"]?["objects"]?.object.keys.map { $0 } ?? []) == ["dataPoint", "labels", "legend"])
        #expect(editor.notice?.contains("valueAxis") == true)
        editor.undo(); editor.undo()
        #expect(Set(editor.visual(S.c1)?.raw["visual"]?["objects"]?.object.keys.map { $0 } ?? []) == ["dataPoint", "labels", "legend", "valueAxis"])
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
        #expect(props(env, "Y") == ["Credit", "Debit", "Balance"] && props(env, "Y2") == ["Net"])
        // nhân bản sau khi đổi loại mang đúng loại
        env.editor.select(S.c1)
        let copy = try #require(env.editor.duplicate([S.c1]).first)
        #expect(env.editor.visual(copy)?.raw["visual"]?["visualType"]?.string == "lineChart")
    }
}

/// VM-D11 mục 1: thả phân cấp (ngày) vào visual.
@Suite @MainActor struct HierarchyFieldTests {
    typealias S = SyntheticReport
    typealias Env = FieldEditingTests.Env

    static let time = FieldRef(kind: .hierarchy, entity: "Dim_Date", property: "Thời gian", family: .date, levels: ["Năm", "Quý", "Tháng"])

    static var line: Data {
        Data(#"{"$schema":"s","name":"\#(S.c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"lineChart","query":{"queryState":{"Category":{"projections":[\#(S.proj("Column", "Dim_Date", "month_start", extra: #","active":true"#))]},"Y":{"projections":[\#(S.proj("Measure", "Fact", "Credit"))]}}},"drillFilterOtherVisuals":true}}"#.utf8)
    }

    func levels(_ env: Env) -> [String] { env.editor.visual(S.c1)?.fields.filter { $0.role == "Category" }.map(\.queryRef) ?? [] }

    @Test func aHierarchyReplacesTheSingleCategoryWithAllItsLevels() throws {
        let env = try Env(chart: Self.line); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.addField(Self.time, to: "Category", visual: S.c1) == nil)
        #expect(levels(env) == ["Dim_Date.Thời gian.Năm", "Dim_Date.Thời gian.Quý", "Dim_Date.Thời gian.Tháng"])
        #expect(env.editor.undoDepth == depth + 1)
        let changes = try env.editor.makeChanges(archive: env.archive)
        let text = String(decoding: try #require(changes.reportParts[LayoutEditor.visualPath(page: "p1", id: S.c1)]), as: UTF8.self)
        #expect(text.contains(#""nativeQueryRef":"Thời gian Tháng","active":true}"#) && !text.contains("month_start"))
        env.editor.undo()
        #expect(levels(env) == ["Dim_Date.month_start"])
    }

    @Test func removingTheHierarchyDropsEveryLevelInOneStep() throws {
        let env = try Env(chart: Self.line); defer { env.cleanUp() }
        #expect(env.editor.addField(Self.time, to: "Category", visual: S.c1) == nil)
        let depth = env.editor.undoDepth
        #expect(env.editor.removeHierarchy(Self.time, visual: S.c1) == nil)
        #expect(levels(env).isEmpty && env.editor.undoDepth == depth + 1)
        env.editor.undo()
        #expect(levels(env).count == 3)
    }

    @Test func aHierarchyIsRefusedByWellsThatTakeOnlyMeasures() throws {
        let env = try Env(chart: Self.line); defer { env.cleanUp() }
        #expect(env.editor.addField(Self.time, to: "Y", visual: S.c1) != nil)
    }
}
