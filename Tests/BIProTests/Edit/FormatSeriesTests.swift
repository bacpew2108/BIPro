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

    @Test func aChartWithALegendFieldOffersNoSeries() throws {
        let env = try Env(chart: Self.chart(series: true)); defer { env.cleanUp() }
        #expect(try dataPoint(env).series.isEmpty)
        #expect(setColor(env, "Fact.Credit")?.contains("Chú giải") == true)
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
        #expect(env.editor.setFormat(.choice("'Outline'"), scope: .objects, object: "general", property: "layout", visual: S.f3) != nil)
    }
}
