import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Màu theo từng chuỗi (`objects.dataPoint` có `selector.metadata`) và bố cục matrix: `docs/phase-d-evidence/vm-d8/QUAN-SAT.md`
/// mục 6, `specs/006-d4-format-pane/contracts/format-editing.md`.
@Suite @MainActor struct FormatSeriesTests {
    typealias S = SyntheticReport
    typealias Env = FormatEditingTests.Env

    static let theme4 = #"{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":4,"Percent":0}}}}}"#

    func bytes(_ env: Env, _ id: String) throws -> String {
        let base = try #require(env.editor.jsonBeforeFormats(of: id, page: "p1"))
        return String(decoding: try env.editor.withFormats(base, page: "p1", id: id), as: UTF8.self)
    }

    func dataPoint(_ env: Env, _ id: String = S.c1) throws -> FormatCardState {
        try #require(env.editor.formatState(of: id)?.objects.first { $0.card.objectKey == "dataPoint" })
    }

    func setColor(_ env: Env, _ series: String?, _ color: FormatColor = .theme(id: 4, percent: 0), visual: String = S.c1) -> String? {
        env.editor.setFormat(.color(color), scope: .objects, object: "dataPoint", property: "fill", visual: visual, series: series)
    }

    /// Combo như `S.chartJSON` nhưng có sẵn `objects` và (tuỳ chọn) trường ở ô Chú giải.
    static func chart(objects: String? = nil, series: Bool = false) -> Data {
        var text = String(decoding: S.chartJSON, as: UTF8.self)
        if series {
            text = text.replacingOccurrences(of: #""Y":{"#, with: #""Series":{"projections":[\#(S.proj("Column", "Dim", "region"))]},"Y":{"#)
        }
        if let objects { text = text.replacingOccurrences(of: #"}}}}"#, with: #"}},"objects":\#(objects)}}"#) }
        return Data(text.utf8)
    }

    // MARK: Danh sách chuỗi

    @Test func theSeriesAreTheMeasuresOfTheValueWells() throws {
        let env = try Env(); defer { env.cleanUp() }
        let card = try dataPoint(env)
        #expect(card.series.map(\.queryRef) == ["Fact.Credit", "Fact.Debit", "Fact.Net"])
        #expect(card.series.map(\.title) == ["Tiền vào", "Debit", "Net"])
        #expect(card.series.allSatisfy { $0.values.isEmpty && $0.blocker == nil })
        #expect(card.card.seriesProperties.map(\.key) == ["fill"] && card.isEditable)
    }

    @Test func aChartWithALegendFieldAndNoEntriesOffersNoSeries() throws {
        let env = try Env(chart: Self.chart(series: true)); defer { env.cleanUp() }
        #expect(try dataPoint(env).series.isEmpty)
        #expect(setColor(env, "Fact.Credit")?.contains("Chú giải") == true)
        #expect(setColor(env, "data:'North'")?.contains("Chú giải") == true)
    }

    // MARK: Màu theo giá trị Chú giải (VM-D8c mục 2)

    /// Mục của một giá trị Chú giải, đúng dạng Desktop ghi: `selector.data[0].scopeId.Comparison` trên cột ở ô Chú giải.
    static func legendEntry(_ value: String, color: String, property: String = "region") -> String {
        let left = #"{"Column":{"Expression":{"SourceRef":{"Entity":"Dim"}},"Property":"\#(property)"}}"#
        return #"{"properties":{"fill":{"solid":{"color":{"expr":{"Literal":{"Value":"'\#(color)'"}}}}}},"selector":{"data":[{"scopeId":{"Comparison":{"ComparisonKind":0,"Left":\#(left),"Right":{"Literal":{"Value":"\#(value)"}}}}}]}}"#
    }
    static let legendObjects = "{\"dataPoint\":[\(legendEntry("'North'", color: "#111111")),\(legendEntry("'South'", color: "#222222"))]}"

    @Test func legendValuesWithAnEntryAreTheSeries() throws {
        let env = try Env(chart: Self.chart(objects: Self.legendObjects, series: true)); defer { env.cleanUp() }
        let card = try dataPoint(env)
        #expect(card.series.map(\.title) == ["North", "South"] && card.series.map(\.queryRef) == ["data:'North'", "data:'South'"])
        #expect(card.series[0].values["fill"] == .color(.hex("#111111")) && card.series.allSatisfy { $0.blocker == nil })
        #expect(card.isEditable == false)   // mục chung cạnh mục theo Chú giải chưa quan sát
        #expect(!(env.editor.formatState(of: S.c1)?.readOnly.contains { $0.object == "dataPoint" } ?? true))
    }

    @Test func aLegendValueColourIsChangedInPlaceLikeDesktop() throws {
        let env = try Env(chart: Self.chart(objects: Self.legendObjects, series: true)); defer { env.cleanUp() }
        let before = try bytes(env, S.c1)
        let depth = env.editor.undoDepth
        #expect(setColor(env, "data:'North'") == nil)
        let after = try bytes(env, S.c1)
        #expect(after == before.replacingOccurrences(of: #"{"solid":{"color":{"expr":{"Literal":{"Value":"'#111111'"}}}}}"#, with: Self.theme4))
        #expect(env.editor.undoDepth == depth + 1)
        #expect(try dataPoint(env).series[0].values["fill"] == .color(.theme(id: 4, percent: 0)))
        #expect(try dataPoint(env).series[1].values["fill"] == .color(.hex("#222222")))
        env.editor.undo()
        #expect(try bytes(env, S.c1) == before)
    }

    @Test func legendValuesWithoutAnEntryOrOnAnotherColumnAreRefused() throws {
        let objects = "{\"dataPoint\":[\(Self.legendEntry("'North'", color: "#111111")),\(Self.legendEntry("'East'", color: "#333333", property: "other"))]}"
        let env = try Env(chart: Self.chart(objects: objects, series: true)); defer { env.cleanUp() }
        #expect(try dataPoint(env).series.map(\.title) == ["North"])
        let depth = env.editor.undoDepth
        #expect(setColor(env, "data:'East'") != nil)     // mục của cột khác
        #expect(setColor(env, "data:'West'") != nil)     // không có trong dữ liệu đang hiện (không có `legendValuesProvider`)
        #expect(setColor(env, "Fact.Credit") != nil)     // chuỗi measure không thuộc visual có Chú giải
        #expect(env.editor.undoDepth == depth)
    }

    // MARK: Màu theo điểm dữ liệu (VM-D10): cột nhóm, không Chú giải, một measure

    /// Cột nhóm (`clusteredColumnChart`) có Category `Dim[region]` và một measure; `extra` thêm vào `queryState` (ví dụ một ô khác).
    static func column(type: String = "clusteredColumnChart", extra: String = "", objects: String? = nil) -> Data {
        let state = #""Category":{"projections":[\#(S.proj("Column", "Dim", "region", extra: #","active":true"#))]},"Y":{"projections":[\#(S.proj("Measure", "Fact", "Credit"))]}\#(extra)"#
        let tail = objects.map { #","objects":\#($0)"# } ?? ""
        return Data(#"{"$schema":"s","name":"\#(S.c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"\#(type)","query":{"queryState":{\#(state)}}\#(tail),"drillFilterOtherVisuals":true}}"#.utf8)
    }

    @Test func aSingleMeasureColumnChartColoursItsCategories() throws {
        let env = try Env(chart: Self.column()); defer { env.cleanUp() }
        env.editor.legendValuesProvider = { _ in ["'North'", "'South'"] }
        let card = try dataPoint(env)
        // Desktop: "Apply settings to" liệt kê giá trị của Category, không phải measure (VM-D10).
        #expect(card.series.map(\.title) == ["North", "South"] && card.series.map(\.queryRef) == ["data:'North'", "data:'South'"])
        let before = try bytes(env, S.c1)
        #expect(setColor(env, "data:'South'") == nil)
        let after = try bytes(env, S.c1)
        // Mục mới theo đúng dạng Desktop: selector.data[0].scopeId.Comparison trên cột Category.
        #expect(after.contains(#""dataPoint":[{"properties":{"fill":\#(Self.theme4)},"selector":{"data":[{"scopeId":{"Comparison":{"ComparisonKind":0,"Left":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim"}},"Property":"region"}},"Right":{"Literal":{"Value":"'South'"}}}}}]}}]"#))
        env.editor.undo()
        #expect(try bytes(env, S.c1) == before)
    }

    @Test func otherShapesKeepTheirMeasureSeries() throws {
        // Hai measure: chuỗi là các measure như trước.
        let credit = S.proj("Measure", "Fact", "Credit")
        let twoText = String(decoding: Self.column(), as: UTF8.self).replacingOccurrences(of: credit, with: credit + "," + S.proj("Measure", "Fact", "Debit"))
        let env = try Env(chart: Data(twoText.utf8)); defer { env.cleanUp() }
        env.editor.legendValuesProvider = { _ in ["'North'"] }
        #expect(try dataPoint(env).series.map(\.queryRef) == ["Fact.Credit", "Fact.Debit"])
        #expect(setColor(env, "data:'North'") != nil)
        // Measure ở Chú thích công cụ không phải chuỗi: vẫn tô theo danh mục.
        let tip = try Env(chart: Self.column(extra: #","Tooltips":{"projections":[\#(S.proj("Measure", "Fact", "Debit"))]}"#)); defer { tip.cleanUp() }
        tip.editor.legendValuesProvider = { _ in ["'North'"] }
        #expect(try dataPoint(tip).series.map(\.queryRef) == ["data:'North'"])
        // Loại khác chưa quan sát "Categories": thanh nhóm giữ chuỗi measure.
        let bar = try Env(chart: Self.column(type: "clusteredBarChart")); defer { bar.cleanUp() }
        bar.editor.legendValuesProvider = { _ in ["'North'"] }
        #expect(try dataPoint(bar).series.map(\.queryRef) == ["Fact.Credit"])
    }

    // MARK: Giá trị Chú giải chưa có mục (VM-D9 mục 2)

    @Test func legendValuesOfTheLiveDataAreTheSeriesEvenWithoutAnEntry() throws {
        let env = try Env(chart: Self.chart(objects: Self.legendObjects, series: true)); defer { env.cleanUp() }
        env.editor.legendValuesProvider = { _ in ["'North'", "'West'"] }
        let card = try dataPoint(env)
        // Giá trị đang hiện trước (theo dữ liệu), rồi giá trị chỉ có mục trong file.
        #expect(card.series.map(\.title) == ["North", "West", "South"])
        #expect(card.series[1].values.isEmpty && card.series[1].blocker == nil)
    }

    @Test func aLegendValueWithoutAnEntryGetsOneLikeDesktopAndUndoRemovesIt() throws {
        let env = try Env(chart: Self.chart(objects: Self.legendObjects, series: true)); defer { env.cleanUp() }
        env.editor.legendValuesProvider = { _ in ["'North'", "'West'", "'O''Neil'"] }
        let before = try bytes(env, S.c1)
        let depth = env.editor.undoDepth
        #expect(setColor(env, "data:'West'") == nil)
        let after = try bytes(env, S.c1)
        // Mục mới ở cuối mảng, theo đúng dạng Desktop ghi (selector.data[0].scopeId.Comparison); hai mục cũ giữ nguyên.
        let west = Self.legendEntry("'West'", color: "x").replacingOccurrences(of: #"{"solid":{"color":{"expr":{"Literal":{"Value":"'x'"}}}}}"#, with: Self.theme4)
        #expect(after == before.replacingOccurrences(of: "]}", with: ",\(west)]}", options: [], range: before.range(of: "]}", options: .backwards)))
        #expect(env.editor.undoDepth == depth + 1)
        #expect(try dataPoint(env).series.first { $0.title == "West" }?.values["fill"] == .color(.theme(id: 4, percent: 0)))
        // Giá trị có dấu nháy đơn: literal nhân đôi nháy như Desktop.
        #expect(setColor(env, "data:'O''Neil'") == nil)
        #expect(try bytes(env, S.c1).contains(#""Value":"'O''Neil'""#))
        env.editor.undo(); env.editor.undo()
        #expect(try bytes(env, S.c1) == before)
    }

    @Test func aLegendChartWithoutAnyColourObjectGetsTheFirstEntry() throws {
        let env = try Env(chart: Self.chart(series: true)); defer { env.cleanUp() }
        env.editor.legendValuesProvider = { _ in ["'North'"] }
        #expect(setColor(env, "data:'North'") == nil)
        let text = try bytes(env, S.c1)
        #expect(text.contains(#""dataPoint":[{"properties":{"fill":"#) && text.contains(#""Right":{"Literal":{"Value":"'North'"}}"#))
        // Giá trị không có trong dữ liệu đang hiện vẫn bị từ chối.
        #expect(setColor(env, "data:'Nowhere'") != nil)
    }

    @Test func resettingALegendValueColourDropsItsEntry() throws {
        let env = try Env(chart: Self.chart(objects: Self.legendObjects, series: true)); defer { env.cleanUp() }
        #expect(env.editor.resetFormat(scope: .objects, object: "dataPoint", property: "fill", visual: S.c1, series: "data:'North'") == nil)
        let text = try bytes(env, S.c1)
        #expect(!text.contains("'North'") && text.contains("'South'"))
    }

    // MARK: Ghi

    @Test func aSeriesColourThenACommonTransparencyAreSavedAsDesktopWritesThem() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(setColor(env, "Fact.Credit") == nil)
        #expect(env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "dataPoint", property: "fillTransparency", visual: S.c1) == nil)
        // Cùng dạng với `docs/phase-d-evidence/vm-d8/json/datapoint-thanh.visual.json`: mục của chuỗi rồi mục chung ở cuối.
        #expect(try bytes(env, S.c1).contains(#""objects":{"dataPoint":[{"properties":{"fill":\#(Self.theme4)},"selector":{"metadata":"Fact.Credit"}},{"properties":{"fillTransparency":\#(S.lit("30D"))}}]}"#))
        #expect(env.editor.undoDepth == depth + 2)
        let card = try dataPoint(env)
        #expect(card.series[0].values["fill"] == .color(.theme(id: 4, percent: 0)) && card.series[1].values.isEmpty)
        #expect(card.values["fillTransparency"] == .number(30, tail: .d))
        // Đường vẽ đọc đúng màu vừa đặt.
        let format = VisualFormat(objects: try #require(env.editor.visual(S.c1)).objects)
        #expect(format.dataPoint.fillByMeasure["Fact.Credit"] == .themeColor(id: 4, percent: 0))
        #expect(format.dataPoint.defaultFill == nil)
    }

    @Test func consecutiveColoursOfOneSeriesAreOneUndoStepAndSeriesAreSeparate() throws {
        let env = try Env(); defer { env.cleanUp() }
        let original = try bytes(env, S.c1)
        let depth = env.editor.undoDepth
        #expect(setColor(env, "Fact.Credit") == nil)
        #expect(setColor(env, "Fact.Credit", .hex("#112233")) == nil)
        #expect(env.editor.undoDepth == depth + 1)
        #expect(setColor(env, "Fact.Net", .hex("#445566")) == nil)
        #expect(env.editor.undoDepth == depth + 2)
        let text = try bytes(env, S.c1)
        #expect(text.contains(#""selector":{"metadata":"Fact.Credit"}},{"properties":{"fill":{"solid":{"color":{"expr":{"Literal":{"Value":"'#445566'"}}}}}},"selector":{"metadata":"Fact.Net"}}]"#))
        env.editor.undo(); env.editor.undo()
        #expect(try bytes(env, S.c1) == original && !env.editor.isDirty)
    }

    // MARK: Từ chối

    @Test func coloursNeedASeriesOfThisVisualAndOtherPropertiesDoNot() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        // Series = All: Desktop khoá ô màu ("Select a specific series to change the color").
        #expect(setColor(env, nil)?.contains("Chọn một chuỗi") == true)
        #expect(setColor(env, "Fact.KhongCo") != nil)
        #expect(setColor(env, "Fact.Avg") != nil)   // measure ở ô Chú thích công cụ không phải chuỗi
        #expect(env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "dataPoint", property: "fillTransparency",
                                     visual: S.c1, series: "Fact.Credit") != nil)   // theo chuỗi chưa quan sát
        // Thẻ khác không có thuộc tính theo chuỗi.
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1, series: "Fact.Credit") != nil)
        #expect(env.editor.undoDepth == depth)
    }

    @Test func aSeriesColouredByAFormulaIsLeftAloneButOthersCanBeSet() throws {
        let conditional = #"{"properties":{"fill":{"solid":{"color":{"expr":{"Measure":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"Alert"}}}}}},"selector":{"data":[{"dataViewWildcard":{"matchingOption":1}}],"metadata":"Fact.Credit"}}"#
        let env = try Env(chart: Self.chart(objects: #"{"dataPoint":[\#(conditional)]}"#)); defer { env.cleanUp() }
        let card = try dataPoint(env)
        #expect(card.series[0].blocker?.contains("công thức") == true && card.series[1].blocker == nil)
        #expect(setColor(env, "Fact.Credit")?.contains("công thức") == true)
        #expect(setColor(env, "Fact.Debit") == nil)
        #expect(try bytes(env, S.c1).contains(conditional + #",{"properties":{"fill":\#(Self.theme4)},"selector":{"metadata":"Fact.Debit"}}]"#))
        // Mục chung thì chưa quan sát cạnh mục theo điểm dữ liệu: vẫn từ chối, và không đặt lại cả thẻ.
        #expect(env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "dataPoint", property: "fillTransparency", visual: S.c1) != nil)
        #expect(env.editor.resetFormat(scope: .objects, object: "dataPoint", visual: S.c1) != nil)
    }

    // MARK: Đặt lại

    @Test func resettingOneSeriesOrTheWholeCard() throws {
        let env = try Env(); defer { env.cleanUp() }
        let original = try bytes(env, S.c1)
        #expect(setColor(env, "Fact.Credit") == nil)
        #expect(setColor(env, "Fact.Debit", .hex("#445566")) == nil)
        let depth = env.editor.undoDepth
        #expect(env.editor.resetFormat(scope: .objects, object: "dataPoint", property: "fill", visual: S.c1, series: "Fact.Credit") == nil)
        #expect(try !bytes(env, S.c1).contains("Fact.Credit\"}}") && bytes(env, S.c1).contains(#""selector":{"metadata":"Fact.Debit"}"#))
        #expect(env.editor.undoDepth == depth + 1)
        // Chuỗi chưa có màu: không tạo bước.
        #expect(env.editor.resetFormat(scope: .objects, object: "dataPoint", property: "fill", visual: S.c1, series: "Fact.Net") == nil)
        #expect(env.editor.undoDepth == depth + 1)
        // Cả thẻ ở "Tất cả": chỉ bỏ phần chung, màu riêng của chuỗi nằm lại.
        #expect(setColor(env, "Fact.Credit") == nil)
        #expect(env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "dataPoint", property: "fillTransparency", visual: S.c1) == nil)
        let steps = env.editor.undoDepth
        #expect(env.editor.resetFormat(scope: .objects, object: "dataPoint", visual: S.c1) == nil)
        #expect(env.editor.undoDepth == steps + 1)
        let kept = try bytes(env, S.c1)
        #expect(!kept.contains("fillTransparency") && kept.contains(#""selector":{"metadata":"Fact.Credit"}"#) && kept.contains(#""selector":{"metadata":"Fact.Debit"}"#))
        // Hoàn tác trả cả phần chung; đặt lại từng chuỗi rồi cả thẻ thì về như ban đầu.
        env.editor.undo()
        #expect(try bytes(env, S.c1).contains("fillTransparency"))
        env.editor.undo()
        #expect(env.editor.resetFormat(scope: .objects, object: "dataPoint", property: "fill", visual: S.c1, series: "Fact.Credit") == nil)
        #expect(env.editor.resetFormat(scope: .objects, object: "dataPoint", property: "fill", visual: S.c1, series: "Fact.Debit") == nil)
        #expect(try bytes(env, S.c1) == original)
    }

    @Test func seriesEntriesAreNotListedAsReadOnly() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(setColor(env, "Fact.Credit") == nil)
        let state = try #require(env.editor.formatState(of: S.c1))
        #expect(!state.readOnly.contains { $0.object == "dataPoint" })
        // Thẻ không có thuộc tính theo chuỗi vẫn coi mục `metadata` là chỉ-đọc (như trước).
        let card = try #require(env.editor.formatState(of: S.f5))
        #expect(card.readOnly.contains { $0.object == "labels" && $0.property == nil })
    }

    // MARK: Bố cục matrix

    @Test func theMatrixLayoutIsSavedAsDesktopWritesIt() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.setFormat(.choice("'Tabular'"), scope: .objects, object: "general", property: "layout", visual: S.f3) == nil)
        #expect(try bytes(env, S.f3).contains(#""general":[{"properties":{"layout":\#(S.lit("'Tabular'"))}}]"#))
        #expect(env.editor.setFormat(.choice("'Outline'"), scope: .objects, object: "general", property: "layout", visual: S.f3) == nil)
        #expect(try bytes(env, S.f3).contains(#""general":[{"properties":{"layout":\#(S.lit("'Outline'"))}}]"#))
        #expect(env.editor.setFormat(.choice("'Compact'"), scope: .objects, object: "general", property: "layout", visual: S.f3) == nil)
        #expect(env.editor.setFormat(.choice("'Staggered'"), scope: .objects, object: "general", property: "layout", visual: S.f3) != nil)
    }
}
