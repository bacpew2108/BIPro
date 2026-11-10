import Foundation
import Testing
@testable import PBIXKit

@Suite struct PBIRPagePatchTests {
    // MARK: Mẫu (đúng dạng Desktop và Nhom6 ghi: một dòng, không BOM)

    static let schema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json"

    static let pagesJSON = Data(#"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json","pageOrder":["d1_giaodich","d2_khoanvay","d3_cskh","d4_chinhanh"],"activePageName":"d3_cskh"}"#.utf8)

    static let prettyPages = Data("""
    {
      "pageOrder": [
        "a",
        "b"
      ],
      "activePageName": "a"
    }
    """.utf8)

    static let pageJSON = Data(#"{"$schema":"\#(schema)","name":"d1_giaodich","displayName":"D1 · Giao dịch","displayOption":"FitToPage","height":1080,"width":1920,"objects":{"background":[{"properties":{}}]}}"#.utf8)

    /// Trang drillthrough như `d4_chinhanh`: có `filterConfig`, `pageBinding`, `visualInteractions`.
    static let drillPage = Data(#"{"$schema":"\#(schema)","name":"d4","displayName":"Chi tiết","displayOption":"FitToPage","height":1080,"width":1920,"filterConfig":{"filters":[{"name":"f"}]},"visualInteractions":[{"source":"v1","target":"v2","type":"NoFilter"},{"source":"v3","target":"v1","type":"Filter"}],"pageBinding":{"name":"b","type":"Drillthrough","parameters":[]},"visibility":"HiddenInViewMode"}"#.utf8)

    static let visualJSON = Data(#"{"$schema":"s","name":"aaaaaaaaaaaaaaaaaaa1","position":{"x":218.8235294117647,"y":145.41176470588235,"z":3000,"height":300,"width":300,"tabOrder":3000},"parentGroupName":"ggggggggggggggggggg1","visual":{"visualType":"card"}}"#.utf8)

    static func bookmark(active: String, sections: [String]) -> Data {
        let body = sections.map { #""\#($0)":{"visualContainers":{}}"# }.joined(separator: ",")
        return Data(#"{"displayName":"B","name":"b1","options":{"targetVisualNames":["v1"]},"explorationState":{"version":"1.3","activeSection":"\#(active)","sections":{\#(body)}}}"#.utf8)
    }

    func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }
    func object(_ d: Data) throws -> [String: Any] { try #require(try JSONSerialization.jsonObject(with: d) as? [String: Any]) }

    // MARK: (a) trang mới

    @Test func newPageIsTheExactDesktopLine() throws {
        let out = PBIRPagePatch.newPageJSON(id: "83844fc7b91c3cea8089", displayName: "Page 1", schema: nil)
        #expect(text(out) == #"{"$schema":"\#(Self.schema)","name":"83844fc7b91c3cea8089","displayName":"Page 1","displayOption":"FitToPage","height":1080,"width":1920}"#)
        let tricky = PBIRPagePatch.newPageJSON(id: "83844fc7b91c3cea8089", displayName: "Tên \"lạ\" \\ ñ", schema: "custom-schema")
        let root = try object(tricky)
        #expect(root["displayName"] as? String == "Tên \"lạ\" \\ ñ" && root["$schema"] as? String == "custom-schema")
        #expect(!tricky.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    // MARK: (b) pages.json

    @Test func pageOrderAndActivePageChangeNothingElse() throws {
        let order = ["d2_khoanvay", "d1_giaodich", "d3_cskh", "d4_chinhanh", "83844fc7b91c3cea8089"]
        let out = try PBIRPagePatch.setPageOrder(order, activePage: "83844fc7b91c3cea8089", in: Self.pagesJSON)
        #expect(text(out) == text(Self.pagesJSON)
            .replacingOccurrences(of: #""pageOrder":["d1_giaodich","d2_khoanvay","d3_cskh","d4_chinhanh"]"#,
                                  with: #""pageOrder":["d2_khoanvay","d1_giaodich","d3_cskh","d4_chinhanh","83844fc7b91c3cea8089"]"#)
            .replacingOccurrences(of: #""activePageName":"d3_cskh""#, with: #""activePageName":"83844fc7b91c3cea8089""#))
        // activePage nil: giữ nguyên khoá
        let keep = try PBIRPagePatch.setPageOrder(["d1_giaodich"], activePage: nil, in: Self.pagesJSON)
        #expect(try object(keep)["activePageName"] as? String == "d3_cskh" && (try object(keep)["pageOrder"] as? [String]) == ["d1_giaodich"])
    }

    @Test func prettyPagesKeepTheirLayout() throws {
        let out = try PBIRPagePatch.setPageOrder(["b", "a", "c"], activePage: "c", in: Self.prettyPages)
        let root = try object(out)
        #expect(root["pageOrder"] as? [String] == ["b", "a", "c"] && root["activePageName"] as? String == "c")
        #expect(text(out).contains("\n    \"b\",\n    \"a\",\n    \"c\"\n  ]"))
    }

    @Test func aLandingPageThatIsGoneIsDroppedAndOneThatStaysIsKept() throws {
        // VM-D5 R-D5-g: "Set as landing page" ghi `landingPageName` vào pages.json
        let withLanding = Data(#"{"pageOrder":["a","b"],"activePageName":"a","landingPageName":"b"}"#.utf8)
        let kept = try PBIRPagePatch.setPageOrder(["b", "a"], activePage: nil, in: withLanding)
        #expect(text(kept) == #"{"pageOrder":["b","a"],"activePageName":"a","landingPageName":"b"}"#)
        let dropped = try PBIRPagePatch.setPageOrder(["a"], activePage: "a", in: withLanding)
        #expect(text(dropped) == #"{"pageOrder":["a"],"activePageName":"a"}"#)
        let middle = Data(#"{"pageOrder":["a","b"],"landingPageName":"b","activePageName":"a"}"#.utf8)
        #expect(text(try PBIRPagePatch.setPageOrder(["a"], activePage: nil, in: middle)) == #"{"pageOrder":["a"],"activePageName":"a"}"#)
    }

    @Test func missingActivePageIsAddedWhenAskedFor() throws {
        let bare = Data(#"{"pageOrder":["a"]}"#.utf8)
        let out = try PBIRPagePatch.setPageOrder(["a", "b"], activePage: "b", in: bare)
        #expect(text(out) == #"{"pageOrder":["a","b"],"activePageName":"b"}"#)
        #expect(throws: WriteError.self) { _ = try PBIRPagePatch.setPageOrder(["a"], activePage: nil, in: Data("[1]".utf8)) }
    }

    // MARK: (c) đổi tên

    @Test func displayNameSplicesAndRestores() throws {
        let renamed = try PBIRPagePatch.setPageDisplayName("Tên \"mới\" ñ", in: Self.pageJSON)
        #expect(try object(renamed)["displayName"] as? String == "Tên \"mới\" ñ")
        #expect(text(renamed).contains(#""displayOption":"FitToPage","height":1080"#))
        let back = try PBIRPagePatch.setPageDisplayName("D1 · Giao dịch", in: renamed)
        #expect(back == Self.pageJSON)
        // không có displayName: được thêm sau name
        let noName = Data(#"{"name":"x","height":1}"#.utf8)
        #expect(text(try PBIRPagePatch.setPageDisplayName("T", in: noName)) == #"{"name":"x","displayName":"T","height":1}"#)
    }

    // MARK: (d) nhân bản trang

    @Test func duplicatedPageDropsDrillthroughAndMapsInteractions() throws {
        let out = try PBIRPagePatch.duplicatedPageJSON(Self.drillPage, newName: "8168f8c98a608d3500ba",
                                                       displayName: "Duplicate of Chi tiết", visualIDMap: ["v1": "n1", "v2": "n2", "v3": "n3"])
        let root = try object(out)
        #expect(root["name"] as? String == "8168f8c98a608d3500ba" && root["displayName"] as? String == "Duplicate of Chi tiết")
        #expect(root["pageBinding"] == nil)
        #expect(root["filterConfig"] != nil && root["visibility"] as? String == "HiddenInViewMode")
        let interactions = try #require(root["visualInteractions"] as? [[String: Any]])
        #expect(interactions.map { $0["source"] as? String } == ["n1", "n3"] && interactions.map { $0["target"] as? String } == ["n2", "n1"])
        // trang thường: chỉ đổi name và displayName
        let plain = try PBIRPagePatch.duplicatedPageJSON(Self.pageJSON, newName: "8168f8c98a608d3500ba", displayName: "Duplicate of D1 · Giao dịch", visualIDMap: [:])
        #expect(text(plain) == text(Self.pageJSON)
            .replacingOccurrences(of: #""name":"d1_giaodich""#, with: #""name":"8168f8c98a608d3500ba""#)
            .replacingOccurrences(of: #""displayName":"D1 · Giao dịch""#, with: #""displayName":"Duplicate of D1 · Giao dịch""#))
    }

    // MARK: (e) visual của bản sao

    @Test func renamedVisualOnlyChangesNameAndGroup() throws {
        let out = try PBIRPagePatch.renamedVisualJSON(Self.visualJSON, newName: "5ddeb9a55602da2225ee", parentGroupName: "hhhhhhhhhhhhhhhhhhh2")
        #expect(text(out) == text(Self.visualJSON)
            .replacingOccurrences(of: "aaaaaaaaaaaaaaaaaaa1", with: "5ddeb9a55602da2225ee")
            .replacingOccurrences(of: "ggggggggggggggggggg1", with: "hhhhhhhhhhhhhhhhhhh2"))
        #expect(text(out).contains(#""x":218.8235294117647,"y":145.41176470588235"#))   // số thực giữ nguyên chữ
        // không có parentGroupName: chỉ đổi name
        let ungrouped = Data(#"{"name":"aaaaaaaaaaaaaaaaaaa1","position":{"x":1}}"#.utf8)
        #expect(text(try PBIRPagePatch.renamedVisualJSON(ungrouped, newName: "bbbbbbbbbbbbbbbbbbb2", parentGroupName: nil))
                == #"{"name":"bbbbbbbbbbbbbbbbbbb2","position":{"x":1}}"#)
        #expect(throws: WriteError.self) { _ = try PBIRPagePatch.renamedVisualJSON(Data(#"{"x":1}"#.utf8), newName: "b", parentGroupName: nil) }
    }

    // MARK: (f) bookmark

    @Test func bookmarkOutcomeFollowsTheActiveSection() throws {
        let removed: Set<String> = ["d1"]
        // activeSection là trang xoá: cả bookmark bị gỡ
        guard case .remove = try PBIRPagePatch.removingPageReferences(removed, fromBookmark: Self.bookmark(active: "d1", sections: ["d1"])) else {
            Issue.record("phải gỡ cả bookmark"); return
        }
        // activeSection khác, sections nhắc trang xoá: chỉ bỏ mục
        let multi = Self.bookmark(active: "d2", sections: ["d1", "d2"])
        guard case .trimmed(let trimmed) = try PBIRPagePatch.removingPageReferences(removed, fromBookmark: multi) else {
            Issue.record("phải bỏ mục"); return
        }
        let sections = try #require((try object(trimmed)["explorationState"] as? [String: Any])?["sections"] as? [String: Any])
        #expect(Set(sections.keys) == ["d2"])
        #expect(text(trimmed).contains(#""targetVisualNames":["v1"]"#))
        // không nhắc: giữ nguyên byte
        let other = Self.bookmark(active: "d2", sections: ["d2"])
        guard case .unchanged = try PBIRPagePatch.removingPageReferences(removed, fromBookmark: other) else {
            Issue.record("phải giữ nguyên"); return
        }
    }

    @Test func bookmarkItemsLoseTheirEntries() throws {
        let json = Data(#"{"$schema":"s","items":[{"name":"a"},{"name":"b"},{"name":"c"}]}"#.utf8)
        #expect(text(try PBIRPagePatch.bookmarkItemsRemoving(["b"], from: json)) == #"{"$schema":"s","items":[{"name":"a"},{"name":"c"}]}"#)
        #expect(text(try PBIRPagePatch.bookmarkItemsRemoving(["a", "c"], from: json)) == #"{"$schema":"s","items":[{"name":"b"}]}"#)
        #expect(try PBIRPagePatch.bookmarkItemsRemoving([], from: json) == json)
        #expect(try PBIRPagePatch.bookmarkItemsRemoving(["x"], from: json) == json)
    }

    // MARK: (h) nút điều hướng

    @Test func pageNavigationTargetsAreReadFromVisualLinks() {
        let button = Data(#"{"visual":{"visualType":"actionButton","visualContainerObjects":{"visualLink":[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"type":{"expr":{"Literal":{"Value":"'PageNavigation'"}}},"navigationSection":{"expr":{"Literal":{"Value":"'d2_khoanvay'"}}}}}]}}}"#.utf8)
        #expect(PBIRPagePatch.pageNavigationTargets(in: button, knownPages: ["d1", "d2_khoanvay"]) == ["d2_khoanvay"])
        #expect(PBIRPagePatch.pageNavigationTargets(in: button, knownPages: ["d1"]).isEmpty)
        // loại Bookmark và Back không là điều hướng trang
        let bookmark = Data(#"{"visual":{"visualContainerObjects":{"visualLink":[{"properties":{"type":{"expr":{"Literal":{"Value":"'Bookmark'"}}},"bookmark":{"expr":{"Literal":{"Value":"'d2_khoanvay'"}}}}}]}}}"#.utf8)
        #expect(PBIRPagePatch.pageNavigationTargets(in: bookmark, knownPages: ["d2_khoanvay"]).isEmpty)
        #expect(PBIRPagePatch.pageNavigationTargets(in: Data("oops".utf8), knownPages: ["a"]).isEmpty)
    }

    // MARK: (i) đầu vào hỏng

    @Test func invalidInputIsRejected() {
        #expect(throws: WriteError.self) { _ = try PBIRPagePatch.setPageDisplayName("x", in: Data("[1]".utf8)) }
        #expect(throws: WriteError.self) { _ = try PBIRPagePatch.duplicatedPageJSON(Data("oops".utf8), newName: "a", displayName: "b", visualIDMap: [:]) }
        #expect(throws: WriteError.self) { _ = try PBIRPagePatch.removingPageReferences(["a"], fromBookmark: Data("[1]".utf8)) }
        #expect(throws: WriteError.self) { _ = try PBIRPagePatch.bookmarkItemsRemoving(["a"], from: Data("oops".utf8)) }
    }

    @Test func bookmarkGroupsLoseRemovedChildrenAndGoWhenEmpty() throws {
        let json = Data(#"{"items":[{"name":"b1"},{"name":"g1","children":["b2","b3"]},{"name":"g2","children":["b4"]},{"name":"b5"}]}"#.utf8)
        let out = try PBIRPagePatch.bookmarkItemsRemoving(["b1", "b3", "b4"], from: json)
        #expect(text(out) == #"{"items":[{"name":"g1","children":["b2"]},{"name":"b5"}]}"#)
        // Không đụng tới nhóm không nhắc tên bị bỏ.
        let same = try PBIRPagePatch.bookmarkItemsRemoving(["zzz"], from: json)
        #expect(same == json)
        let pretty = Data("""
        {
          "items": [
            { "name": "g1", "children": [ "b2", "b3" ] }
          ]
        }
        """.utf8)
        let trimmed = try PBIRPagePatch.bookmarkItemsRemoving(["b3"], from: pretty)
        let root = try object(trimmed)
        #expect(((root["items"] as? [[String: Any]])?.first?["children"] as? [String]) == ["b2"])
    }
}
