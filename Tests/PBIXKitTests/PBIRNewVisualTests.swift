import Foundation
import Testing
@testable import PBIXKit

@Suite struct PBIRNewVisualTests {
    static let name = "0123456789abcdef0123"
    static let schema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.14.0/schema.json"

    func make(_ type: String, schema: String? = schema, x: Int = 10, y: Int = 20, w: Int = 300, h: Int = 100, z: Int = 5000) throws -> Data {
        try PBIRNewVisual.makeJSON(name: Self.name, type: type, x: x, y: y, width: w, height: h, z: z, schema: schema)
    }
    func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    func expectInvalid(_ message: String, _ body: () throws -> Void) {
        do { try body(); Issue.record("expected WriteError.invalid: \(message)") }
        catch let error as WriteError { if case .invalid = error { return }; Issue.record("expected .invalid, got \(error): \(message)") }
        catch { Issue.record("unexpected error \(error): \(message)") }
    }

    @Test func dataVisualHasObservedKeysInOrderOnOneLine() throws {
        let out = text(try make("card", w: 302, h: 108))
        let expected = #"{"$schema":"\#(Self.schema)","name":"\#(Self.name)","position":{"x":10,"y":20,"z":5000,"height":108,"width":302,"tabOrder":5000},"visual":{"visualType":"card","drillFilterOtherVisuals":true}}"#
        #expect(out == expected)
        #expect(!out.contains("\n"))
        for type in ["slicer", "clusteredBarChart", "lineChart", "pivotTable", "donutChart"] {
            let json = text(try make(type))
            #expect(json.contains(#""visual":{"visualType":"\#(type)","drillFilterOtherVisuals":true}}"#), Comment(rawValue: type))
        }
    }

    @Test func textboxHasOneDefaultParagraphAndNoDrillFilter() throws {
        let out = text(try make("textbox", w: 400, h: 100))
        #expect(out.contains(#""visual":{"visualType":"textbox","objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":"Hộp văn bản"}]}]}}]}}"#))
        #expect(!out.contains("drillFilterOtherVisuals"))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        #expect(root["name"] as? String == Self.name)
    }

    @Test func schemaIsTakenFromAnExistingVisualAndDefaultsTo213() throws {
        let existing = [Data(#"{"$schema":"\#(Self.schema)","name":"x"}"#.utf8), Data(#"{"name":"y"}"#.utf8)]
        #expect(PBIRNewVisual.schemaURL(from: existing) == Self.schema)
        #expect(PBIRNewVisual.schemaURL(from: []) == "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.13.0/schema.json")
        #expect(PBIRNewVisual.schemaURL(from: [Data("not json".utf8)]).hasSuffix("2.13.0/schema.json"))
        // không truyền schema: dùng mặc định
        #expect(text(try make("card", schema: nil)).contains("/2.13.0/schema.json"))
    }

    @Test func invalidRequestsAreRejected() {
        expectInvalid("tên sai") { _ = try PBIRNewVisual.makeJSON(name: "ZZ", type: "card", x: 0, y: 0, width: 10, height: 10, z: 1, schema: nil) }
        expectInvalid("loại không hỗ trợ") { _ = try make("madeUpType") }
        expectInvalid("rộng 0") { _ = try make("card", w: 0) }
        expectInvalid("cao âm") { _ = try make("card", h: -3) }
        expectInvalid("x âm") { _ = try make("card", x: -1) }
        expectInvalid("y âm") { _ = try make("card", y: -8) }
    }

    @Test func resultReadsBackThroughTheReportLoaderAndPositionPatch() throws {
        let id = "aaaaaaaaaaaaaaaaaaa9"
        var members = SyntheticPBIX.members()
        let path = SyntheticPBIX.visualPath(SyntheticPBIX.pageA, id)
        let json = try PBIRNewVisual.makeJSON(name: id, type: "clusteredBarChart", x: 40, y: 48, width: 616, height: 380, z: 9000, schema: nil)
        let at = members.firstIndex { $0.path == SyntheticPBIX.visualPath(SyntheticPBIX.pageA, SyntheticPBIX.visualsA[2]) }! + 1
        members.insert((path, json, 8), at: at)
        let list = members.map { (path: $0.path, source: ZipWriter.Source.bytes($0.data, method: $0.method)) }
        let pbix = try PBIXFile(data: try ZipWriter.write(list, modified: nil))
        let visual = try #require(try pbix.loadReport().pages.first { $0.id == SyntheticPBIX.pageA }?.visuals.first { $0.id == id })
        #expect(visual.type == "clusteredBarChart" && visual.x == 40 && visual.y == 48 && visual.width == 616 && visual.height == 380 && visual.z == 9000)
        #expect(visual.fields.isEmpty)
        let position = try PBIRLayoutPatch.position(in: json)
        #expect(position.tabOrder == 9000 && position.z == 9000)
        // vị trí sửa được bằng ghép byte như visual thường
        let moved = try PBIRLayoutPatch.setPosition(in: json, x: 48, y: 56)
        #expect(try PBIRLayoutPatch.position(in: moved).x == 48)
    }

    @Test func defaultSizesFollowTheObservedTable() {
        #expect(PBIRNewVisual.defaultSize(for: "card")! == (302, 108))
        #expect(PBIRNewVisual.defaultSize(for: "slicer")! == (364, 64))
        #expect(PBIRNewVisual.defaultSize(for: "textbox")! == (400, 100))
        for type in ["clusteredBarChart", "lineChart", "donutChart", "treemap", "shapeMap", "pivotTable",
                     "lineClusteredColumnComboChart", "lineStackedColumnComboChart", "hundredPercentStackedColumnChart"] {
            #expect(PBIRNewVisual.defaultSize(for: type)! == (616, 380), Comment(rawValue: type))
        }
        #expect(PBIRNewVisual.defaultSize(for: "image")! == (320, 240))
        #expect(PBIRNewVisual.defaultSize(for: "scatterChart")! == (616, 380))
        #expect(PBIRNewVisual.defaultSize(for: "madeUpType") == nil)
    }
}
