import Foundation
import Testing
@testable import PBIXKit

@Suite struct PBIRVisualPatchTests {
    // MARK: Mẫu

    /// Biểu đồ đường: `objects` có valueAxis, labels, categoryAxis; `visualContainerObjects` và `query` ở ngoài.
    static let lineChart = Data(#"{"$schema":"s","name":"aaaaaaaaaaaaaaaaaaa1","position":{"x":1,"y":2,"z":3,"height":4,"width":5,"tabOrder":3},"visual":{"visualType":"lineChart","query":{"queryState":{"Y":{"projections":[]}}},"objects":{"valueAxis":[{"properties":{"show":true}}],"labels":[{"properties":{"fontSize":9}}],"categoryAxis":[{"properties":{"show":false}}]},"visualContainerObjects":{"title":[{"properties":{"text":"T"}}]},"drillFilterOtherVisuals":true}}"#.utf8)

    /// Hộp văn bản như Nhom6: đoạn một lượt có kiểu chữ và căn lề, đoạn hai lượt, đoạn một lượt.
    static let textbox = Data(##"{"$schema":"s","name":"bbbbbbbbbbbbbbbbbbb1","position":{"x":0,"y":0,"z":1,"height":88,"width":1920,"tabOrder":1},"visual":{"visualType":"textbox","objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":"Tiêu đề","textStyle":{"fontWeight":"bold","fontSize":"22pt"}}],"horizontalTextAlignment":"center"},{"textRuns":[{"value":"Dòng ","textStyle":{"color":"#FF0000"}},{"value":"hai","textStyle":{"color":"#00FF00"}}]},{"textRuns":[{"value":"Cuối","textStyle":{"fontSize":"10pt"}}]}]}}]}}}"##.utf8)

    func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }
    func expectInvalid(_ message: String, _ body: () throws -> Void) {
        do { try body(); Issue.record("expected WriteError.invalid: \(message)") }
        catch let error as WriteError { if case .invalid = error { return }; Issue.record("expected .invalid, got \(error): \(message)") }
        catch { Issue.record("unexpected error \(error): \(message)") }
    }

    // MARK: visualType

    @Test func setVisualTypeChangesOnlyTheTypeString() throws {
        #expect(try PBIRVisualPatch.visualType(in: Self.lineChart) == "lineChart")
        let out = try PBIRVisualPatch.setVisualType(in: Self.lineChart, to: "clusteredBarChart", dropObjectKeys: [])
        #expect(text(out) == text(Self.lineChart).replacingOccurrences(of: #""visualType":"lineChart""#, with: #""visualType":"clusteredBarChart""#))
        // Đổi lại ra đúng byte gốc.
        #expect(try PBIRVisualPatch.setVisualType(in: out, to: "lineChart", dropObjectKeys: []) == Self.lineChart)
        // Cùng loại: giữ nguyên byte.
        #expect(try PBIRVisualPatch.setVisualType(in: Self.lineChart, to: "lineChart", dropObjectKeys: []) == Self.lineChart)
    }

    @Test func dropObjectKeysRemovesExactlyThoseKeys() throws {
        for (drop, keep) in [(["valueAxis"], ["labels", "categoryAxis"]), (["labels"], ["valueAxis", "categoryAxis"]),
                             (["categoryAxis"], ["valueAxis", "labels"]), (["valueAxis", "categoryAxis"], ["labels"]),
                             (["nope"], ["valueAxis", "labels", "categoryAxis"])] {
            let out = try PBIRVisualPatch.setVisualType(in: Self.lineChart, to: "lineChart", dropObjectKeys: Set(drop))
            #expect(try PBIRVisualPatch.objectKeys(in: out) == keep, Comment(rawValue: "\(drop)"))
            let root = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
            let visual = try #require(root["visual"] as? [String: Any])
            #expect(visual["visualContainerObjects"] != nil && visual["query"] != nil && visual["drillFilterOtherVisuals"] as? Bool == true)
            #expect((root["position"] as? [String: Any])?["x"] as? Int == 1)
        }
    }

    @Test func droppingEveryKeyLeavesEmptyObjectsAndNothingElseChanges() throws {
        let out = try PBIRVisualPatch.setVisualType(in: Self.lineChart, to: "donutChart", dropObjectKeys: ["valueAxis", "labels", "categoryAxis"])
        #expect(try PBIRVisualPatch.objectKeys(in: out).isEmpty)
        #expect(text(out).contains(#""objects":{}"#))
        #expect(text(out).contains(#""visualType":"donutChart""#) && text(out).contains(#""visualContainerObjects":{"title""#))
    }

    @Test func objectKeysAndParagraphsReadTheFile() throws {
        #expect(try PBIRVisualPatch.objectKeys(in: Self.lineChart) == ["valueAxis", "labels", "categoryAxis"])
        #expect(try PBIRVisualPatch.objectKeys(in: Data(#"{"visual":{"visualType":"card"}}"#.utf8)).isEmpty)
        #expect(try PBIRVisualPatch.paragraphs(in: Self.textbox) == ["Tiêu đề", "Dòng hai", "Cuối"])
        expectInvalid("không có paragraphs") { _ = try PBIRVisualPatch.paragraphs(in: Self.lineChart) }
        expectInvalid("không có visualType") { _ = try PBIRVisualPatch.setVisualType(in: Data(#"{"visual":{}}"#.utf8), to: "card", dropObjectKeys: []) }
        expectInvalid("không phải JSON object") { _ = try PBIRVisualPatch.visualType(in: Data("[1]".utf8)) }
    }

    // MARK: setText

    @Test func unchangedTextGivesIdenticalBytes() throws {
        #expect(try PBIRVisualPatch.setText(in: Self.textbox, lines: ["Tiêu đề", "Dòng hai", "Cuối"]) == Self.textbox)
    }

    @Test func singleRunParagraphKeepsItsStyleAndAlignment() throws {
        let out = try PBIRVisualPatch.setText(in: Self.textbox, lines: ["Tiêu đề mới", "Dòng hai", "Cuối"])
        #expect(try PBIRVisualPatch.paragraphs(in: out) == ["Tiêu đề mới", "Dòng hai", "Cuối"])
        #expect(text(out) == text(Self.textbox).replacingOccurrences(of: #""value":"Tiêu đề""#, with: #""value":"Tiêu đề mới""#))
    }

    @Test func multiRunParagraphKeepsFirstRunOnly() throws {
        let out = try PBIRVisualPatch.setText(in: Self.textbox, lines: ["Tiêu đề", "Một dòng", "Cuối"])
        #expect(try PBIRVisualPatch.paragraphs(in: out) == ["Tiêu đề", "Một dòng", "Cuối"])
        let t = text(out)
        #expect(t.contains(##"{"value":"Một dòng","textStyle":{"color":"#FF0000"}}"##) && !t.contains("hai") && !t.contains("00FF00"))
    }

    @Test func addingAndRemovingLines() throws {
        let more = try PBIRVisualPatch.setText(in: Self.textbox, lines: ["Tiêu đề", "Dòng hai", "Cuối", "Thêm \"một\" dòng \\ ñ"])
        #expect(try PBIRVisualPatch.paragraphs(in: more) == ["Tiêu đề", "Dòng hai", "Cuối", "Thêm \"một\" dòng \\ ñ"])
        // đoạn mới nhân bản byte của đoạn cuối (giữ textStyle)
        #expect(text(more).contains(#"{"textRuns":[{"value":"Thêm \"một\" dòng \\ ñ","textStyle":{"fontSize":"10pt"}}]}"#))
        let fewer = try PBIRVisualPatch.setText(in: Self.textbox, lines: ["Chỉ một"])
        #expect(try PBIRVisualPatch.paragraphs(in: fewer) == ["Chỉ một"])
        #expect(text(fewer).contains(#""horizontalTextAlignment":"center""#))
        // rỗng hoàn toàn: còn một đoạn rỗng
        let empty = try PBIRVisualPatch.setText(in: Self.textbox, lines: [])
        #expect(try PBIRVisualPatch.paragraphs(in: empty) == [""])
    }

    @Test func textRoundTripsThroughTheSameLines() throws {
        let changed = try PBIRVisualPatch.setText(in: Self.textbox, lines: ["A", "B", "C", "D"])
        let back = try PBIRVisualPatch.setText(in: changed, lines: ["Tiêu đề", "Dòng hai", "Cuối"])
        #expect(try PBIRVisualPatch.paragraphs(in: back) == ["Tiêu đề", "Dòng hai", "Cuối"])
        #expect(try JSONSerialization.jsonObject(with: back) is [String: Any])
    }

    @Test func setTextRejectsNonTextboxes() {
        expectInvalid("không có paragraphs") { _ = try PBIRVisualPatch.setText(in: Self.lineChart, lines: ["x"]) }
    }
}
