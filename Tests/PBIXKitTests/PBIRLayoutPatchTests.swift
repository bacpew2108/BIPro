import Foundation
import Testing
@testable import PBIXKit

@Suite struct PBIRLayoutPatchTests {
    static let id1 = "aaaaaaaaaaaaaaaaaaa1"
    static let id2 = "aaaaaaaaaaaaaaaaaaa2"
    static let id3 = "aaaaaaaaaaaaaaaaaaa3"

    static var visual: Data { Data(SyntheticPBIX.visualJSON(name: id1, x: 1594, y: 176, z: 24000, w: 302, h: 108).utf8) }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    private func expectInvalid(_ message: String, _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("expected WriteError.invalid: \(message)")
        } catch let error as WriteError {
            if case .invalid = error { return }
            Issue.record("expected .invalid, got \(error): \(message)")
        } catch {
            Issue.record("unexpected error \(error): \(message)")
        }
    }

    // MARK: position

    @Test func readsPosition() throws {
        let p = try PBIRLayoutPatch.position(in: Self.visual)
        #expect(p.x == 1594 && p.y == 176 && p.z == 24000 && p.width == 302 && p.height == 108 && p.tabOrder == 24000)
    }

    @Test func setPositionChangesOnlyTheRequestedNumbers() throws {
        let patched = try PBIRLayoutPatch.setPosition(in: Self.visual, x: 1600, y: 8)
        let expected = text(Self.visual)
            .replacingOccurrences(of: #""x":1594"#, with: #""x":1600"#)
            .replacingOccurrences(of: #""y":176"#, with: #""y":8"#)
        #expect(text(patched) == expected)
        // Đổi lại thì ra đúng byte gốc.
        let back = try PBIRLayoutPatch.setPosition(in: patched, x: 1594, y: 176)
        #expect(back == Self.visual)
    }

    @Test func setPositionKeepsFormattingOfPrettyPrintedJSON() throws {
        let pretty = """
        {
          "name": "\(Self.id1)",
          "position": {
            "x": 10,
            "y": 20,
            "z": 1000,
            "height": 30,
            "width": 40,
            "tabOrder": 1000
          },
          "visual": { "visualType": "card" }
        }
        """
        let patched = try PBIRLayoutPatch.setPosition(in: Data(pretty.utf8), x: 12345, width: 8, height: 9)
        let expected = pretty
            .replacingOccurrences(of: "\"x\": 10", with: "\"x\": 12345")
            .replacingOccurrences(of: "\"height\": 30", with: "\"height\": 9")
            .replacingOccurrences(of: "\"width\": 40", with: "\"width\": 8")
        #expect(text(patched) == expected)
    }

    @Test func setPositionCanChangeEverything() throws {
        let patched = try PBIRLayoutPatch.setPosition(in: Self.visual, x: 0, y: 0, width: 16, height: 16, z: 25000, tabOrder: 25000)
        let p = try PBIRLayoutPatch.position(in: patched)
        #expect(p.x == 0 && p.y == 0 && p.width == 16 && p.height == 16 && p.z == 25000 && p.tabOrder == 25000)
        // Phần còn lại của tài liệu không đổi.
        let a = try JSONSerialization.jsonObject(with: Self.visual) as? [String: Any]
        let b = try JSONSerialization.jsonObject(with: patched) as? [String: Any]
        #expect(a?["visual"] as? NSDictionary == b?["visual"] as? NSDictionary)
        #expect(a?["name"] as? String == b?["name"] as? String)
    }

    @Test func invalidValuesAreRejected() {
        expectInvalid("x âm") { _ = try PBIRLayoutPatch.setPosition(in: Self.visual, x: -1) }
        expectInvalid("y âm") { _ = try PBIRLayoutPatch.setPosition(in: Self.visual, y: -8) }
        expectInvalid("width 0") { _ = try PBIRLayoutPatch.setPosition(in: Self.visual, width: 0) }
        expectInvalid("height âm") { _ = try PBIRLayoutPatch.setPosition(in: Self.visual, height: -3) }
        expectInvalid("không có position") { _ = try PBIRLayoutPatch.setPosition(in: Data(#"{"name":"x","visual":{}}"#.utf8), x: 1) }
        expectInvalid("không phải JSON object") { _ = try PBIRLayoutPatch.setPosition(in: Data("[1]".utf8), x: 1) }
    }

    // MARK: duplicate

    @Test func duplicateChangesNameAndPositionOnly() throws {
        let newName = "0123456789abcdef0123"
        let copy = try PBIRLayoutPatch.duplicated(Self.visual, newName: newName, x: 1610, y: 192, width: 302, height: 108, z: 38000)
        let expected = text(Self.visual)
            .replacingOccurrences(of: #""name":"\#(Self.id1)""#, with: #""name":"\#(newName)""#)
            .replacingOccurrences(of: #""x":1594"#, with: #""x":1610"#)
            .replacingOccurrences(of: #""y":176"#, with: #""y":192"#)
            .replacingOccurrences(of: #""z":24000"#, with: #""z":38000"#)
            .replacingOccurrences(of: #""tabOrder":24000"#, with: #""tabOrder":38000"#)
        #expect(text(copy) == expected)
    }

    @Test func duplicateRejectsBadNames() {
        for bad in ["", "short", "ZZZZZZZZZZZZZZZZZZZZ", "0123456789abcdef01234", "0123456789abcdef012\""] {
            expectInvalid("tên \(bad)") {
                _ = try PBIRLayoutPatch.duplicated(Self.visual, newName: bad, x: 0, y: 0, width: 10, height: 10, z: 1)
            }
        }
        #expect(PBIRLayoutPatch.isValidVisualName("0123456789abcdef0123"))
        #expect(!PBIRLayoutPatch.isValidVisualName("0123456789ABCDEF0123"))
    }

    @Test func newVisualNamesAreValidAndAvoidTakenOnes() {
        var taken = Set<String>()
        for _ in 0..<1000 {
            let name = PBIRLayoutPatch.makeVisualName(avoiding: taken)
            #expect(PBIRLayoutPatch.isValidVisualName(name))
            #expect(!taken.contains(name))
            taken.insert(name)
        }
    }

    // MARK: bookmark and page references

    static var bookmark: Data { Data(SyntheticPBIX.members().first { $0.path.hasSuffix("bm1.bookmark.json") }!.data) }

    @Test func removingReferencesFromBookmark() throws {
        let patched = try PBIRLayoutPatch.removingVisualReferences([Self.id1], fromBookmark: Self.bookmark)
        let root = try #require(try JSONSerialization.jsonObject(with: patched) as? [String: Any])
        // Như Power BI Desktop (đo trên VM): bỏ khỏi visualContainers, còn targetVisualNames giữ nguyên.
        let options = try #require(root["options"] as? [String: Any])
        #expect(options["targetVisualNames"] as? [String] == [Self.id1, Self.id2])
        #expect(options["suppressData"] == nil)
        let sections = try #require((root["explorationState"] as? [String: Any])?["sections"] as? [String: Any])
        let containers = try #require((sections["page_a"] as? [String: Any])?["visualContainers"] as? [String: Any])
        #expect(Set(containers.keys) == [Self.id2])
        #expect(text(patched).contains(#""targetVisualNames":["\#(Self.id1)","\#(Self.id2)"]"#))
    }

    @Test func removingAllReferencesLeavesValidEmptyContainers() throws {
        let patched = try PBIRLayoutPatch.removingVisualReferences([Self.id1, Self.id2], fromBookmark: Self.bookmark)
        let root = try #require(try JSONSerialization.jsonObject(with: patched) as? [String: Any])
        let sections = try #require((root["explorationState"] as? [String: Any])?["sections"] as? [String: Any])
        #expect(((sections["page_a"] as? [String: Any])?["visualContainers"] as? [String: Any])?.isEmpty == true)
    }

    @Test func unrelatedIDsLeaveBookmarkBytesUntouched() throws {
        let same = try PBIRLayoutPatch.removingVisualReferences([Self.id3, "zzzz"], fromBookmark: Self.bookmark)
        #expect(same == Self.bookmark)
        let none = try PBIRLayoutPatch.removingVisualReferences([], fromBookmark: Self.bookmark)
        #expect(none == Self.bookmark)
    }

    @Test func removingReferencesKeepsPrettyFormatting() throws {
        let pretty = """
        {
          "options": {
            "targetVisualNames": [
              "\(Self.id1)",
              "\(Self.id2)",
              "\(Self.id3)"
            ]
          },
          "explorationState": { "sections": { "p": { "visualContainers": {
            "\(Self.id1)": { "singleVisual": { "visualType": "card" } },
            "\(Self.id2)": { "singleVisual": { "visualType": "card" } }
          } } } }
        }
        """
        let patched = try PBIRLayoutPatch.removingVisualReferences([Self.id2], fromBookmark: Data(pretty.utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: patched) as? [String: Any])
        #expect(((root["options"] as? [String: Any])?["targetVisualNames"] as? [String]) == [Self.id1, Self.id2, Self.id3])
        let sections = try #require((root["explorationState"] as? [String: Any])?["sections"] as? [String: Any])
        let containers = try #require(((sections["p"] as? [String: Any])?["visualContainers"]) as? [String: Any])
        #expect(Set(containers.keys) == [Self.id1])
        #expect(text(patched).contains("\"\(Self.id1)\",\n"))
    }

    @Test func removingReferencesFromPageInteractions() throws {
        let page = #"{"name":"p","displayName":"P","width":1280,"height":720,"visualInteractions":[{"source":"\#(Self.id1)","target":"\#(Self.id2)","type":"NoFilter"},{"source":"\#(Self.id2)","target":"\#(Self.id3)","type":"NoFilter"},{"source":"\#(Self.id3)","target":"\#(Self.id1)","type":"DataFilter"}]}"#
        let patched = try PBIRLayoutPatch.removingVisualReferences([Self.id1], fromPage: Data(page.utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: patched) as? [String: Any])
        let rows = try #require(root["visualInteractions"] as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows.first?["source"] as? String == Self.id2)
        // Trang không có visualInteractions: trả đúng byte vào.
        let plain = Data(#"{"name":"p","width":1}"#.utf8)
        #expect(try PBIRLayoutPatch.removingVisualReferences([Self.id1], fromPage: plain) == plain)
        // Không nhắc tới mã: không đổi.
        #expect(try PBIRLayoutPatch.removingVisualReferences(["x"], fromPage: Data(page.utf8)) == Data(page.utf8))
    }

    @Test func idsAreMatchedExactlyNotAsSubstrings() throws {
        let json = #"{"explorationState":{"sections":{"p":{"visualContainers":{"\#(Self.id1)":{},"\#(Self.id1)x":{}}}}}}"#
        let patched = try PBIRLayoutPatch.removingVisualReferences([Self.id1], fromBookmark: Data(json.utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: patched) as? [String: Any])
        let sections = try #require((root["explorationState"] as? [String: Any])?["sections"] as? [String: Any])
        let containers = try #require((sections["p"] as? [String: Any])?["visualContainers"] as? [String: Any])
        #expect(Set(containers.keys) == ["\(Self.id1)x"])
    }
}
