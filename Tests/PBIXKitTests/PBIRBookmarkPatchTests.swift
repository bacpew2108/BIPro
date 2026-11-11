import Foundation
import Testing
@testable import PBIXKit

@Suite("D6 PBIRBookmarkPatch")
struct PBIRBookmarkPatchTests {
    /// Bản chụp bookmark Display-only thật của Nhom6 (Desktop ghi nhận, không ghi lại).
    let nhom6 = """
    {"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json","displayName":"Q1.3","name":"Bookmark_Q13_GioThu","options":{"applyOnlyToTargetVisuals":true,"targetVisualNames":["a","b"],"suppressActiveSection":true,"suppressData":true},"explorationState":{"version":"1.0","activeSection":"d1_giaodich","sections":{"d1_giaodich":{"visualContainers":{"a":{"singleVisual":{"visualType":"pivotTable"}},"b":{"singleVisual":{"visualType":"lineChart","display":{"mode":"hidden"}}}}}}}}
    """

    @Test func newBookmarkMatchesNhom6ShapeByteForByte() throws {
        let spec = BookmarkSpec(name: "Bookmark_Q13_GioThu", displayName: "Q1.3", page: "d1_giaodich",
                                visuals: [.init(id: "a", type: "pivotTable", hidden: false), .init(id: "b", type: "lineChart", hidden: true)],
                                suppressActiveSection: true, suppressData: true, suppressDisplay: false)
        #expect(String(decoding: PBIRBookmarkPatch.newBookmarkJSON(spec), as: UTF8.self) == nhom6)
    }

    @Test func optionsFollowDesktopOrderAndSuppressDisplayDropsHiddenMarks() throws {
        let spec = BookmarkSpec(name: "n", displayName: "N", page: "p", visuals: [.init(id: "v", type: "card", hidden: true)],
                                suppressActiveSection: true, suppressData: true, suppressDisplay: true)
        let text = String(decoding: PBIRBookmarkPatch.newBookmarkJSON(spec), as: UTF8.self)
        #expect(text.contains("\"options\":{\"applyOnlyToTargetVisuals\":true,\"targetVisualNames\":[\"v\"],\"suppressActiveSection\":true,\"suppressData\":true,\"suppressDisplay\":true}"))
        #expect(!text.contains("\"display\":{\"mode\":\"hidden\"}"))
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
        #expect(parsed is [String: Any])
    }

    @Test func displayNameWithQuotesAndUnicodeEscapes() throws {
        let spec = BookmarkSpec(name: "n", displayName: "Tên \"x\" · Giờ", page: "p", visuals: [])
        let parsed = try #require(JSONSerialization.jsonObject(with: PBIRBookmarkPatch.newBookmarkJSON(spec)) as? [String: Any])
        #expect(parsed["displayName"] as? String == "Tên \"x\" · Giờ")
    }

    @Test func renameChangesOnlyTheDisplayNameBytes() throws {
        let data = Data(nhom6.utf8)
        let renamed = try PBIRBookmarkPatch.renamingDisplayName("Mới", in: data)
        #expect(String(decoding: renamed, as: UTF8.self) == nhom6.replacingOccurrences(of: "\"Q1.3\"", with: "\"Mới\""))
        #expect(PBIRBookmarkPatch.identity(of: renamed)?.displayName == "Mới")
        #expect(PBIRBookmarkPatch.identity(of: renamed)?.name == "Bookmark_Q13_GioThu")
    }

    let index = #"{"$schema":"https://x/bookmarksMetadata/1.0.0/schema.json","items":[{"name":"A"},{"name":"B"},{"name":"C"}]}"#

    @Test func addingItemAppendsAtTheEndKeepingEverythingElse() throws {
        let out = String(decoding: try PBIRBookmarkPatch.addingItem("D", to: Data(index.utf8)), as: UTF8.self)
        #expect(out == index.replacingOccurrences(of: #"{"name":"C"}]"#, with: #"{"name":"C"},{"name":"D"}]"#))
    }

    @Test func addingItemToEmptyItemsAndToMissingFile() throws {
        let empty = #"{"$schema":"s","items":[]}"#
        #expect(String(decoding: try PBIRBookmarkPatch.addingItem("X", to: Data(empty.utf8)), as: UTF8.self) == #"{"$schema":"s","items":[{"name":"X"}]}"#)
        let fresh = String(decoding: try PBIRBookmarkPatch.addingItem("X", to: nil), as: UTF8.self)
        #expect(fresh == "{\"$schema\":\"\(PBIRBookmarkPatch.indexSchema)\",\"items\":[{\"name\":\"X\"}]}")
    }

    @Test func reorderingMovesItemsAsByteRanges() throws {
        let out = String(decoding: try PBIRBookmarkPatch.reorderingItems(["C", "A", "B"], in: Data(index.utf8)), as: UTF8.self)
        #expect(out == #"{"$schema":"https://x/bookmarksMetadata/1.0.0/schema.json","items":[{"name":"C"},{"name":"A"},{"name":"B"}]}"#)
        #expect(PBIRBookmarkPatch.itemNames(in: Data(out.utf8)) == ["C", "A", "B"])
    }

    @Test func reorderingUnlistedKeepsTheirOrderAtTheEndAndSameOrderIsUntouched() throws {
        let out = try PBIRBookmarkPatch.reorderingItems(["B"], in: Data(index.utf8))
        #expect(PBIRBookmarkPatch.itemNames(in: out) == ["B", "A", "C"])
        let same = try PBIRBookmarkPatch.reorderingItems(["A", "B", "C"], in: Data(index.utf8))
        #expect(same == Data(index.utf8))
    }

    @Test func reorderingKeepsGroupsAndIndentedLayout() throws {
        let grouped = "{\n  \"items\": [\n    {\"name\": \"G\", \"children\": [\"A\", \"B\"]},\n    {\"name\": \"C\"}\n  ]\n}"
        let out = try PBIRBookmarkPatch.reorderingItems(["C", "G"], in: Data(grouped.utf8))
        let text = String(decoding: out, as: UTF8.self)
        #expect(text == "{\n  \"items\": [\n    {\"name\": \"C\"},\n    {\"name\": \"G\", \"children\": [\"A\", \"B\"]}\n  ]\n}")
    }

    @Test func nhom6IndexRoundTripsNames() throws {
        let nhom6Index = #"{"$schema":"s","items":[{"name":"Bookmark_Q13_GioThu"},{"name":"Bookmark_Q13_MuaVu"}]}"#
        #expect(PBIRBookmarkPatch.itemNames(in: Data(nhom6Index.utf8)) == ["Bookmark_Q13_GioThu", "Bookmark_Q13_MuaVu"])
    }

    // MARK: Bookmark có Data (VM-D6 vòng 2: Desktop áp đúng dạng này)

    @Test func dataBookmarkWithASlicerSelectionMatchesTheFileDesktopAccepted() throws {
        let spec = BookmarkSpec(name: "d6data000000000000aa", displayName: "Data thu", page: "d1_giaodich",
                                visuals: [.init(id: "83b988953b0219bc8d85", type: "slicer", hidden: false)], suppressData: false,
                                slicers: ["83b988953b0219bc8d85": .init(entity: "Dim_Trans_Type", property: "trans_type", values: [.string("Credit")])])
        let text = String(decoding: PBIRBookmarkPatch.newBookmarkJSON(spec), as: UTF8.self)
        let expected = #"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json","displayName":"Data thu","name":"d6data000000000000aa","options":{"targetVisualNames":[],"preserveNewVisualVisibility":true},"explorationState":{"version":"1.3","activeSection":"d1_giaodich","sections":{"d1_giaodich":{"visualContainers":{"83b988953b0219bc8d85":{"singleVisual":{"visualType":"slicer","objects":{"merge":{"general":[{"properties":{"filter":{"filter":{"Version":2,"From":[{"Name":"d","Entity":"Dim_Trans_Type","Type":0}],"Where":[{"Condition":{"In":{"Expressions":[{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"trans_type"}}],"Values":[[{"Literal":{"Value":"'Credit'"}}]]}}}]}}}}]}}}}}}}}}"#
        #expect(text == expected)
    }

    @Test func dataBookmarkResetsSlicersWithoutSelectionAndHidesVisuals() throws {
        let spec = BookmarkSpec(name: "n", displayName: "N", page: "p", visuals: [.init(id: "s", type: "slicer", hidden: false), .init(id: "c", type: "card", hidden: true)],
                                suppressActiveSection: true, suppressData: false, suppressDisplay: false)
        let text = String(decoding: PBIRBookmarkPatch.newBookmarkJSON(spec), as: UTF8.self)
        #expect(text.contains(#""options":{"targetVisualNames":[],"suppressActiveSection":true,"preserveNewVisualVisibility":true}"#))
        #expect(text.contains(#""s":{"singleVisual":{"visualType":"slicer"}}"#))
        #expect(text.contains(#""c":{"singleVisual":{"visualType":"card","display":{"mode":"hidden"}}}"#))
        let parsed = try JSONValue.parse(Data(text.utf8))
        #expect(parsed["explorationState"]?["version"]?.string == "1.3")
    }

    @Test func dataBookmarkWithTwoValuesUsesOneArrayPerValue() throws {
        let spec = BookmarkSpec(name: "n", displayName: "N", page: "p", visuals: [.init(id: "s", type: "slicer", hidden: false)], suppressData: false,
                                slicers: ["s": .init(entity: "E", property: "p", values: [.string("Credit"), .string("Debit")])])
        let text = String(decoding: PBIRBookmarkPatch.newBookmarkJSON(spec), as: UTF8.self)
        #expect(text.contains(#""Values":[[{"Literal":{"Value":"'Credit'"}}],[{"Literal":{"Value":"'Debit'"}}]]"#))
    }
}
