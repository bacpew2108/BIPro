import Foundation
import Testing
@testable import PBIXKit

@Suite("Wave 3A (v1.1b) — PBIR Patch: visualInteractions, Date Filter & Row Expansion")
struct V11BPBIRPatchTests {
    @Test("PBIRPagePatch.settingVisualInteractions ghi đủ NoFilter/DataFilter/HighlightFilter và giữ nguyên byte phần khác")
    func visualInteractionsRoundTrip() throws {
        let base = Data(#"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json","name":"p1","displayName":"Page 1","displayOption":"FitToPage","height":1080,"width":1920}"#.utf8)
        let list = [
            PageVisualInteraction(source: "aaa", target: "bbb", type: .noFilter),
            PageVisualInteraction(source: "aaa", target: "ccc", type: .highlightFilter),
            PageVisualInteraction(source: "aaa", target: "ddd", type: .dataFilter),
        ]
        let patched = try PBIRPagePatch.settingVisualInteractions(list, in: base)
        let parsed = try JSONValue.parse(patched)
        #expect(parsed["displayName"]?.string == "Page 1")
        let arr = parsed["visualInteractions"]?.array ?? []
        #expect(arr.count == 3)
        #expect(arr[0]["type"]?.string == "NoFilter")
        #expect(arr[1]["type"]?.string == "HighlightFilter")
        #expect(arr[2]["type"]?.string == "DataFilter")

        // Cập nhật lại thành 1 mục rồi xoá hết -> sạch khoá visualInteractions
        let one = try PBIRPagePatch.settingVisualInteractions([list[0]], in: patched)
        #expect((try JSONValue.parse(one))["visualInteractions"]?.array.count == 1)
        let empty = try PBIRPagePatch.settingVisualInteractions([], in: one)
        #expect((try JSONValue.parse(empty))["visualInteractions"] == nil)
    }

    @Test("FilterLiteral.dateTime tạo điều kiện Advanced PBIR chuẩn datetime'YYYY-MM-DDT00:00:00'")
    func dateAdvancedFilterPBIR() throws {
        let cond = PBIRFilterPatch.AdvancedCondition(.greaterThan, literal: .dateTime("1970-01-01T00:00:00"))
        let json = try #require(PBIRFilterPatch.advancedFilter(kind: .column, entity: "Dim_Client", property: "birth_date",
                                                               conditions: [cond], useOr: false))
        #expect(json.contains("datetime'1970-01-01T00:00:00'"))
        #expect(json.contains("\"ComparisonKind\":1"))
    }
}
