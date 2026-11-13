import Foundation
import Testing
@testable import PBIXKit

/// Ghép byte định dạng của `visual.json` (D4): `specs/006-d4-format-pane/contracts/format-save.md`.
@Suite struct PBIRFormatPatchTests {
    static func lit(_ value: String) -> String { #"{"expr":{"Literal":{"Value":"\#(value)"}}}"# }

    /// Visual có `objects` và `visualContainerObjects` (một dòng, như Desktop và Nhom6 ghi).
    static let card = #"{"$schema":"s","name":"c1","position":{"x":0,"y":0,"z":0,"height":10,"width":10,"tabOrder":0},"visual":{"visualType":"card","query":{"queryState":{}},"objects":{"labels":[{"properties":{"fontSize":\#(lit("20D"))}}],"categoryLabels":[{"properties":{"show":\#(lit("true"))}}]},"visualContainerObjects":{"title":[{"properties":{"show":\#(lit("true"))}}]},"drillFilterOtherVisuals":true}}"#
    static let noObjects = #"{"$schema":"s","name":"c1","visual":{"visualType":"cardVisual","query":{"queryState":{}},"visualContainerObjects":{"title":[{"properties":{"show":\#(lit("true"))}}]},"drillFilterOtherVisuals":true}}"#
    static let bare = #"{"$schema":"s","name":"c1","visual":{"visualType":"cardVisual","query":{"queryState":{}},"drillFilterOtherVisuals":true}}"#
    static let onlyType = #"{"$schema":"s","name":"c1","visual":{"visualType":"textbox"}}"#

    func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }
    func apply(_ edits: [FormatEdit], _ json: String) throws -> String { text(try PBIRFormatPatch.apply(edits, to: Data(json.utf8))) }
    func set(_ scope: FormatScope, _ object: String, _ property: String, _ value: String, selectorDefault: Bool = false) -> FormatEdit {
        FormatEdit(scope: scope, object: object, action: .set(property: property, value: value), selectorDefault: selectorDefault)
    }
    func object(_ s: String) throws -> NSDictionary { try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? NSDictionary) }

    // MARK: (a), (b), (c) thêm và sửa

    @Test func settingAnExistingPropertyReplacesOnlyItsValue() throws {
        let out = try apply([set(.objects, "labels", "fontSize", Self.lit("28D"))], Self.card)
        #expect(out == Self.card.replacingOccurrences(of: Self.lit("20D"), with: Self.lit("28D")))
    }

    @Test func aNewPropertyGoesAtTheEndOfTheEntry() throws {
        let out = try apply([set(.objects, "labels", "bold", Self.lit("true"))], Self.card)
        #expect(out == Self.card.replacingOccurrences(of: #""fontSize":\#(Self.lit("20D"))}}]"#, with: #""fontSize":\#(Self.lit("20D")),"bold":\#(Self.lit("true"))}}]"#))
    }

    @Test func aNewObjectGoesAtTheEndOfTheScope() throws {
        let out = try apply([set(.objects, "legend", "show", Self.lit("true"))], Self.card)
        let expected = Self.card.replacingOccurrences(of: #"]},"visualContainerObjects""#, with: #"],"legend":[{"properties":{"show":\#(Self.lit("true"))}}]},"visualContainerObjects""#)
        #expect(out == expected)
    }

    @Test func aNewContainerObjectGoesAtTheEndOfVisualContainerObjects() throws {
        let out = try apply([set(.container, "visualHeader", "show", Self.lit("false"))], Self.card)
        let expected = Self.card.replacingOccurrences(of: #"]},"drillFilterOtherVisuals""#, with: #"],"visualHeader":[{"properties":{"show":\#(Self.lit("false"))}}]},"drillFilterOtherVisuals""#)
        #expect(out == expected)
    }

    // MARK: (d) tạo phạm vi mới, đúng chỗ

    @Test func objectsAreCreatedBeforeVisualContainerObjects() throws {
        let out = try apply([set(.objects, "cardImage", "show", Self.lit("true"))], Self.noObjects)
        let expected = Self.noObjects.replacingOccurrences(of: #""visualContainerObjects""#, with: #""objects":{"cardImage":[{"properties":{"show":\#(Self.lit("true"))}}]},"visualContainerObjects""#)
        #expect(out == expected)
    }

    @Test func containerObjectsAreCreatedBeforeDrillFilterOtherVisuals() throws {
        let out = try apply([set(.container, "title", "show", Self.lit("false"))], Self.bare)
        let expected = Self.bare.replacingOccurrences(of: #","drillFilterOtherVisuals""#, with: #","visualContainerObjects":{"title":[{"properties":{"show":\#(Self.lit("false"))}}]},"drillFilterOtherVisuals""#)
        #expect(out == expected)
    }

    @Test func bothScopesInDesktopOrderWhenCreatedTogether() throws {
        let out = try apply([set(.container, "title", "show", Self.lit("false")),
                             set(.objects, "labels", "show", Self.lit("true"))], Self.bare)
        let root = try object(out)
        let visual = try #require(root["visual"] as? NSDictionary)
        #expect(visual["objects"] != nil && visual["visualContainerObjects"] != nil)
        let text = out
        #expect(text.range(of: #""objects""#)!.lowerBound < text.range(of: #""visualContainerObjects""#)!.lowerBound)
        #expect(text.range(of: #""visualContainerObjects""#)!.lowerBound < text.range(of: #""drillFilterOtherVisuals""#)!.lowerBound)
    }

    @Test func scopesAreAppendedWhenThereAreNoNeighbours() throws {
        let out = try apply([set(.objects, "labels", "show", Self.lit("true"))], Self.onlyType)
        #expect(out == #"{"$schema":"s","name":"c1","visual":{"visualType":"textbox","objects":{"labels":[{"properties":{"show":\#(Self.lit("true"))}}]}}}"#)
    }

    @Test func selectorDefaultFollowsPropertiesInANewEntry() throws {
        let out = try apply([set(.objects, "cardImage", "show", Self.lit("true"), selectorDefault: true)], Self.noObjects)
        #expect(out.contains(#""cardImage":[{"properties":{"show":\#(Self.lit("true"))},"selector":{"id":"default"}}]"#))
    }

    // MARK: (e) bỏ

    @Test func removingTheLastPropertyRemovesTheEntryObjectAndScope() throws {
        let only = #"{"visual":{"visualType":"card","objects":{"labels":[{"properties":{"fontSize":\#(Self.lit("20D"))}}]},"drillFilterOtherVisuals":true}}"#
        let out = try apply([FormatEdit(scope: .objects, object: "labels", action: .removeProperty("fontSize"), selectorDefault: false)], only)
        #expect(out == #"{"visual":{"visualType":"card","drillFilterOtherVisuals":true}}"#)
    }

    @Test func removingOnePropertyKeepsTheOthers() throws {
        let json = #"{"visual":{"objects":{"title":[{"properties":{"show":\#(Self.lit("true")),"fontSize":\#(Self.lit("16D")),"bold":\#(Self.lit("false"))}}]}}}"#
        let out = try apply([FormatEdit(scope: .objects, object: "title", action: .removeProperty("fontSize"), selectorDefault: false)], json)
        #expect(out == #"{"visual":{"objects":{"title":[{"properties":{"show":\#(Self.lit("true")),"bold":\#(Self.lit("false"))}}]}}}"#)
        let first = try apply([FormatEdit(scope: .objects, object: "title", action: .removeProperty("show"), selectorDefault: false)], json)
        #expect(first == #"{"visual":{"objects":{"title":[{"properties":{"fontSize":\#(Self.lit("16D")),"bold":\#(Self.lit("false"))}}]}}}"#)
    }

    @Test func removingAnObjectKeepsTheOthersAndDropsAnEmptyScope() throws {
        let out = try apply([FormatEdit(scope: .objects, object: "labels", action: .removeObject, selectorDefault: false)], Self.card)
        #expect(out == Self.card.replacingOccurrences(of: #""labels":[{"properties":{"fontSize":\#(Self.lit("20D"))}}],"#, with: ""))
        let both = try apply([FormatEdit(scope: .objects, object: "labels", action: .removeObject, selectorDefault: false),
                              FormatEdit(scope: .objects, object: "categoryLabels", action: .removeObject, selectorDefault: false)], Self.card)
        #expect(!both.contains(#""objects""#) && both.contains(#""visualContainerObjects""#))
        #expect(try object(both) != nil)
    }

    @Test func removingSomethingThatIsNotThereChangesNothing() throws {
        let edits = [FormatEdit(scope: .objects, object: "legend", action: .removeObject, selectorDefault: false),
                     FormatEdit(scope: .objects, object: "labels", action: .removeProperty("nope"), selectorDefault: false),
                     FormatEdit(scope: .container, object: "border", action: .removeProperty("show"), selectorDefault: false)]
        #expect(try apply(edits, Self.card) == Self.card)
        #expect(try apply(edits, Self.bare) == Self.bare)
    }

    // MARK: (f) selector

    @Test func entriesWithOtherSelectorsAreLeftAlone() throws {
        let json = #"{"visual":{"objects":{"dataPoint":[{"properties":{"fill":\#(Self.lit("x"))},"selector":{"metadata":"T.c"}},{"properties":{"w":\#(Self.lit("1D"))},"selector":{"id":"default"}}]}}}"#
        let out = try apply([set(.objects, "dataPoint", "w", Self.lit("2D"))], json)
        #expect(out == json.replacingOccurrences(of: Self.lit("1D"), with: Self.lit("2D")))
        let added = try apply([set(.objects, "dataPoint", "extra", Self.lit("true"))], json)
        #expect(added.contains(#""w":\#(Self.lit("1D")),"extra":\#(Self.lit("true"))}"#))
    }

    /// VM-D8 mục 6: khoá chỉ có mục theo chuỗi thì mục chung (Series = All) được thêm vào **cuối** mảng.
    @Test func aCommonEntryIsAppendedAfterSeriesEntries() throws {
        let json = #"{"visual":{"objects":{"dataPoint":[{"properties":{"fill":\#(Self.lit("x"))},"selector":{"metadata":"T.c"}}]}}}"#
        let out = try apply([set(.objects, "dataPoint", "w", Self.lit("2D"))], json)
        #expect(out == json.replacingOccurrences(of: #""T.c"}}]"#, with: #""T.c"}},{"properties":{"w":\#(Self.lit("2D"))}}]"#))
        // Bỏ thuộc tính của mục chung không đụng tới mục theo chuỗi.
        let same = try apply([FormatEdit(scope: .objects, object: "dataPoint", action: .removeProperty("fill"), selectorDefault: false)], json)
        #expect(same == json)
    }

    // MARK: (f2) theo chuỗi (`selector.metadata`, VM-D8 mục 6)

    static let theme4 = #"{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":4,"Percent":0}}}}}"#
    static let chart = #"{"$schema":"s","name":"c1","visual":{"visualType":"clusteredBarChart","query":{"queryState":{}},"drillFilterOtherVisuals":true}}"#
    func series(_ ref: String, _ property: String, _ value: String) -> FormatEdit {
        FormatEdit(scope: .objects, object: "dataPoint", action: .set(property: property, value: value), selectorMetadata: ref)
    }

    @Test func aSeriesColourThenACommonTransparencyMatchWhatDesktopWrote() throws {
        let out = try apply([series("Fact_CRM_Complaint.Relief Rate", "fill", Self.theme4),
                             set(.objects, "dataPoint", "fillTransparency", Self.lit("30D"))], Self.chart)
        // Nguyên văn `docs/phase-d-evidence/vm-d8/json/datapoint-thanh.visual.json`.
        let desktop = #""objects":{"dataPoint":[{"properties":{"fill":{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":4,"Percent":0}}}}}},"selector":{"metadata":"Fact_CRM_Complaint.Relief Rate"}},{"properties":{"fillTransparency":{"expr":{"Literal":{"Value":"30D"}}}}}]},"drillFilterOtherVisuals":true"#
        #expect(out.contains(desktop))
    }

    @Test func eachSeriesHasItsOwnEntry() throws {
        let one = try apply([series("T.a", "fill", Self.theme4)], Self.chart)
        let two = try apply([series("T.b", "fill", Self.lit("y"))], one)
        #expect(two.contains(#""selector":{"metadata":"T.a"}},{"properties":{"fill":\#(Self.lit("y"))},"selector":{"metadata":"T.b"}}]"#))
        // Đổi màu chuỗi đã có: chỉ thay giá trị của mục đó.
        let changed = try apply([series("T.a", "fill", Self.lit("z"))], two)
        #expect(changed == two.replacingOccurrences(of: Self.theme4, with: Self.lit("z")))
        // Mục chung có sẵn không bị coi là mục của chuỗi.
        let common = try apply([set(.objects, "dataPoint", "fillTransparency", Self.lit("30D"))], one)
        let both = try apply([series("T.b", "fill", Self.lit("y"))], common)
        #expect(both.contains(#"{"properties":{"fillTransparency":\#(Self.lit("30D"))}},{"properties":{"fill":\#(Self.lit("y"))},"selector":{"metadata":"T.b"}}]"#))
    }

    @Test func resettingASeriesRemovesOnlyItsEntry() throws {
        let two = try apply([series("T.a", "fill", Self.theme4), series("T.b", "fill", Self.lit("y"))], Self.chart)
        func reset(_ ref: String) -> FormatEdit {
            FormatEdit(scope: .objects, object: "dataPoint", action: .removeProperty("fill"), selectorMetadata: ref)
        }
        let one = try apply([reset("T.a")], two)
        #expect(one.contains(#""dataPoint":[{"properties":{"fill":\#(Self.lit("y"))},"selector":{"metadata":"T.b"}}]"#))
        // Bỏ mục cuối cùng: bỏ luôn khoá và phạm vi, file về như chưa định dạng.
        #expect(try apply([reset("T.b")], one) == Self.chart)
        #expect(try apply([reset("T.khong_co")], two) == two)
    }

    @Test func aSeriesNameWithQuotesIsEscaped() throws {
        let out = try apply([series(#"T.a "b""#, "fill", Self.theme4)], Self.chart)
        #expect(out.contains(#""selector":{"metadata":"T.a \"b\""}"#))
    }

    @Test func mergingKeepsSeriesApart() {
        var list: [FormatEdit] = []
        list = FormatEdit.merging(list, adding: series("T.a", "fill", Self.lit("1")))
        list = FormatEdit.merging(list, adding: series("T.b", "fill", Self.lit("2")))
        list = FormatEdit.merging(list, adding: set(.objects, "dataPoint", "fill", Self.lit("3")))
        list = FormatEdit.merging(list, adding: series("T.a", "fill", Self.lit("4")))
        #expect(list.count == 3)
        #expect(list.contains(series("T.a", "fill", Self.lit("4"))) && !list.contains(series("T.a", "fill", Self.lit("1"))))
    }

    // MARK: (g) khoảng trắng, (h) ký tự

    @Test func prettyPrintedFilesKeepEverythingBeforeTheChange() throws {
        let pretty = """
        {
          "visual": {
            "visualType": "card",
            "objects": {
              "labels": [
                {
                  "properties": {
                    "fontSize": \(Self.lit("20D"))
                  }
                }
              ]
            }
          }
        }
        """
        let out = try apply([set(.objects, "labels", "fontSize", Self.lit("30D")),
                             set(.objects, "labels", "bold", Self.lit("true")),
                             set(.container, "title", "show", Self.lit("false"))], pretty)
        let root = try object(out)
        let visual = try #require(root["visual"] as? NSDictionary)
        let labels = try #require(((visual["objects"] as? NSDictionary)?["labels"] as? [NSDictionary])?.first?["properties"] as? NSDictionary)
        #expect(labels.count == 2 && labels["bold"] != nil)
        #expect(visual["visualContainerObjects"] != nil)
        #expect(out.hasPrefix(String(pretty[..<pretty.range(of: #"20D"#)!.lowerBound])))
    }

    @Test func vietnameseTextAndQuotesAreWrittenAsGiven() throws {
        let value = Self.lit("'Doanh thu ''lạ'' \\\\ ñ'")
        let out = try apply([set(.container, "title", "text", value)], Self.card)
        let root = try object(out)
        let props = (((root["visual"] as? NSDictionary)?["visualContainerObjects"] as? NSDictionary)?["title"] as? [NSDictionary])?.first?["properties"] as? NSDictionary
        let literal = ((props?["text"] as? NSDictionary)?["expr"] as? NSDictionary)?["Literal"] as? NSDictionary
        #expect(literal?["Value"] as? String == "'Doanh thu ''lạ'' \\ ñ'")
    }

    // MARK: (i) khớp bản Desktop ghi ở VM-D4

    static func evidence(_ name: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        url.appendPathComponent("docs/phase-d-evidence/vm-d4/json/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Desktop thêm `title.show=false` rồi `cardImage.show=true` (selector default) vào cardVisual trống:
    /// cùng thao tác thì cùng từng byte, kể cả chỗ chèn `objects` và `visualContainerObjects`.
    @Test func theNewCardVisualMatchesWhatDesktopWrote() throws {
        let desktop = try Self.evidence("new-cardvisual.visual.json")
        var start = desktop
        for part in [#""objects":{"cardImage":[{"properties":{"show":\#(Self.lit("true"))},"selector":{"id":"default"}}]},"#,
                     #""visualContainerObjects":{"title":[{"properties":{"show":\#(Self.lit("false"))}}]},"#] {
            #expect(start.contains(part))
            start = start.replacingOccurrences(of: part, with: "")
        }
        let out = try apply([set(.container, "title", "show", Self.lit("false")),
                             set(.objects, "cardImage", "show", Self.lit("true"), selectorDefault: true)], start)
        #expect(out == desktop)
    }

    /// Các khoá Desktop thêm vào biểu đồ Q3.4 (zoom, lineStyles, visualHeader, background, dropShadow, border) theo đúng thứ tự.
    @Test func theComboChartMatchesWhatDesktopWrote() throws {
        let desktop = try Self.evidence("combo-q34.visual.json")
        let root = try object(desktop)
        let visual = try #require(root["visual"] as? NSDictionary)
        #expect((visual["objects"] as? NSDictionary)?.allKeys.count == 5)
        // Bản gốc: bỏ các khoá thêm bằng chính `removeObject`, rồi thêm lại đúng thứ tự Desktop đã làm.
        let added: [(FormatScope, String)] = [(.objects, "zoom"), (.objects, "lineStyles"),
                                               (.container, "visualHeader"), (.container, "background"),
                                               (.container, "dropShadow"), (.container, "border")]
        let stripped = try apply(added.map { FormatEdit(scope: $0.0, object: $0.1, action: .removeObject, selectorDefault: false) }, desktop)
        let tests = try object(stripped)
        let v2 = try #require(tests["visual"] as? NSDictionary)
        #expect((v2["objects"] as? NSDictionary)?["zoom"] == nil && (v2["visualContainerObjects"] as? NSDictionary)?["border"] == nil)
        let back = try apply([
            set(.container, "visualHeader", "show", Self.lit("false")),
            set(.container, "background", "transparency", Self.lit("25D")),
            set(.container, "dropShadow", "show", Self.lit("true")),
            set(.container, "border", "show", Self.lit("true")),
            set(.container, "border", "radius", Self.lit("20D")),
            set(.container, "border", "width", Self.lit("3D")),
            set(.objects, "zoom", "show", Self.lit("true")),
            set(.objects, "lineStyles", "areaShow", Self.lit("true")),
        ], stripped)
        #expect(try object(back) == object(desktop))
        #expect(back == desktop)
    }

    // MARK: (j) cấu trúc lạ

    @Test func unexpectedShapesAreRefused() throws {
        let edit = [set(.objects, "labels", "show", Self.lit("true"))]
        #expect(throws: WriteError.self) { try PBIRFormatPatch.apply(edit, to: Data(#"{"name":"x"}"#.utf8)) }
        #expect(throws: WriteError.self) { try PBIRFormatPatch.apply(edit, to: Data(#"{"visual":{"objects":{"labels":[]}}}"#.utf8)) }
        #expect(throws: WriteError.self) { try PBIRFormatPatch.apply(edit, to: Data(#"{"visual":{"objects":[]}}"#.utf8)) }
        #expect(throws: WriteError.self) { try PBIRFormatPatch.apply(edit, to: Data("not json".utf8)) }
    }

    @Test func noEditsReturnsTheSameBytes() throws {
        #expect(try apply([], Self.card) == Self.card)
    }

    // MARK: gộp edit

    @Test func mergingKeepsTheLastValuePerProperty() {
        var list: [FormatEdit] = []
        list = FormatEdit.merging(list, adding: set(.objects, "labels", "fontSize", Self.lit("20D")))
        list = FormatEdit.merging(list, adding: set(.objects, "labels", "fontSize", Self.lit("22D")))
        list = FormatEdit.merging(list, adding: set(.objects, "labels", "bold", Self.lit("true")))
        #expect(list.count == 2)
        #expect(list.contains { $0.action == .set(property: "fontSize", value: Self.lit("22D")) })
        // Bỏ thuộc tính huỷ set cùng khoá nhưng vẫn giữ một lệnh bỏ (thuộc tính có thể đã có trong file).
        list = FormatEdit.merging(list, adding: FormatEdit(scope: .objects, object: "labels", action: .removeProperty("fontSize"), selectorDefault: false))
        #expect(list.contains { $0.action == .removeProperty("fontSize") } && !list.contains { $0.action == .set(property: "fontSize", value: Self.lit("22D")) })
        // Bỏ cả khoá xoá mọi edit con của khoá và chỉ để lại một lệnh bỏ.
        list = FormatEdit.merging(list, adding: FormatEdit(scope: .objects, object: "labels", action: .removeObject, selectorDefault: false))
        #expect(list.count == 1 && list[0].action == .removeObject)
        // Đặt lại sau khi bỏ cả khoá: giữ lệnh bỏ rồi lệnh đặt.
        list = FormatEdit.merging(list, adding: set(.objects, "labels", "show", Self.lit("true")))
        #expect(list.count == 2 && list[0].action == .removeObject)
    }

    @Test func mergingNeverMixesObjectsOrScopes() {
        var list: [FormatEdit] = []
        list = FormatEdit.merging(list, adding: set(.objects, "title", "show", Self.lit("true")))
        list = FormatEdit.merging(list, adding: set(.container, "title", "show", Self.lit("false")))
        list = FormatEdit.merging(list, adding: FormatEdit(scope: .objects, object: "title", action: .removeObject, selectorDefault: false))
        #expect(list.filter { $0.scope == .container }.count == 1 && list.filter { $0.scope == .objects }.count == 1)
    }

    // MARK: Mục theo giá trị Chú giải (VM-D8c mục 2)

    static func legendEntry(_ literal: String, fill: String) -> String {
        #"{"properties":{"fill":\#(fill)},"selector":{"data":[{"scopeId":{"Comparison":{"ComparisonKind":0,"Left":{"Column":{"Expression":{"SourceRef":{"Entity":"D"}},"Property":"sex"}},"Right":{"Literal":{"Value":"\#(literal)"}}}}}]}}"#
    }

    @Test func aLegendValueEntryIsEditedInPlaceAndNeedsItsColumnToBeCreated() throws {
        let doc = #"{"visual":{"objects":{"dataPoint":[\#(Self.legendEntry("'Female'", fill: "1")),\#(Self.legendEntry("'Male'", fill: "2"))]}}}"#
        let edit = FormatEdit(scope: .objects, object: "dataPoint", action: .set(property: "fill", value: "9"), selectorMetadata: "data:'Male'")
        // Mục có sẵn: thay đúng giá trị, giữ từng byte còn lại (cả hai đường byte và mô hình cho cùng kết quả).
        let want = doc.replacingOccurrences(of: Self.legendEntry("'Male'", fill: "2"), with: Self.legendEntry("'Male'", fill: "9"))
        #expect(try apply([edit], doc) == want)
        #expect(try PBIRFormatPatch.apply([edit], to: Data(doc.utf8)).count == want.utf8.count)
        // Giá trị chưa có mục mà không biết cột Chú giải: từ chối thay vì ghi `selector.metadata` sai.
        let missing = FormatEdit(scope: .objects, object: "dataPoint", action: .set(property: "fill", value: "9"), selectorMetadata: "data:'Other'")
        #expect(throws: (any Error).self) { try PBIRFormatPatch.apply([missing], to: Data(doc.utf8)) }
        // Bỏ thuộc tính duy nhất của mục: bỏ cả mục, mục còn lại ở nguyên.
        let remove = FormatEdit(scope: .objects, object: "dataPoint", action: .removeProperty("fill"), selectorMetadata: "data:'Female'")
        #expect(try apply([remove], doc) == #"{"visual":{"objects":{"dataPoint":[\#(Self.legendEntry("'Male'", fill: "2"))]}}}"#)
    }

    /// VM-D9 mục 2: Desktop tạo mục mới `selector.data[0].scopeId.Comparison` khi đổi màu một giá trị Chú giải chưa có mục.
    @Test func aLegendValueWithoutAnEntryGetsOneLikeDesktop() throws {
        let column = FormatEdit.LegendColumn(entity: "D", property: "sex")
        let edit = FormatEdit(scope: .objects, object: "dataPoint", action: .set(property: "fill", value: "9"),
                              selectorMetadata: "data:'Other'", legendColumn: column)
        let doc = #"{"visual":{"objects":{"dataPoint":[\#(Self.legendEntry("'Female'", fill: "1"))]}}}"#
        let appended = #"{"visual":{"objects":{"dataPoint":[\#(Self.legendEntry("'Female'", fill: "1")),\#(Self.legendEntry("'Other'", fill: "9"))]}}}"#
        #expect(try apply([edit], doc) == appended)
        // Hai đường (byte và mô hình) cho cùng độ dài.
        #expect(try PBIRFormatPatch.apply([edit], to: Data(doc.utf8)).count == appended.utf8.count)
        // Khoá `dataPoint` chưa có: tạo cả mảng, một mục.
        let none = #"{"visual":{"objects":{"labels":[{"properties":{}}]}}}"#
        let created = try apply([edit], none)
        #expect(created.contains(Self.legendEntry("'Other'", fill: "9")) && created.contains(#""labels":[{"properties":{}}],"dataPoint":["#))
        // Giá trị có dấu nháy đơn: literal Desktop nhân đôi nháy; người gọi đã truyền literal hoàn chỉnh.
        let quoted = FormatEdit(scope: .objects, object: "dataPoint", action: .set(property: "fill", value: "9"),
                                selectorMetadata: "data:'O''Neil'", legendColumn: column)
        #expect(try apply([quoted], doc).contains(#""Right":{"Literal":{"Value":"'O''Neil'"}}"#))
    }
}
