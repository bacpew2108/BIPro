// Đợt tồn đọng sau Phase F, US1 (T014): ghi và đọc trường gộp ngầm (`Aggregation`) đúng dạng Desktop 2.159 lưu ở VM-F10
// (`docs/phase-f2-evidence/vm-f10/QUAN-SAT.md` mục 3).
import Foundation
import Testing
@testable import PBIXKit

@Suite struct PBIRAggregationPatchTests {
    private static let bare = Data(#"{"name":"aaaaaaaaaaaaaaaaaaa1","visual":{"visualType":"clusteredColumnChart","drillFilterOtherVisuals":true}}"#.utf8)

    private func projections(_ data: Data, _ role: String) throws -> [[String: Any]] {
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = ((root["visual"] as? [String: Any])?["query"] as? [String: Any])?["queryState"] as? [String: Any]
        return ((state?[role] as? [String: Any])?["projections"] as? [[String: Any]]) ?? []
    }

    /// Dạng Desktop ghi khi tích `Amount` (Sum mặc định) và `OrderID` (Count mặc định, SummarizeBy 6).
    @Test func phanTuMoiGiongDesktop() throws {
        let sum = PBIRQueryPatch.newAggregation(entity: "Sales", property: "Amount", function: 0, role: "Y")
        let count = PBIRQueryPatch.newAggregation(entity: "Sales", property: "OrderID", function: 5, role: "Y")
        let out = try PBIRQueryPatch.apply([.init(role: "Y", elements: [sum, count])], to: Self.bare)
        let y = try projections(out, "Y")
        let expected: [[String: Any]] = [
            ["field": ["Aggregation": ["Expression": ["Column": ["Expression": ["SourceRef": ["Entity": "Sales"]], "Property": "Amount"]],
                                       "Function": 0]],
             "queryRef": "Sum(Sales.Amount)", "nativeQueryRef": "Sum of Amount"],
            ["field": ["Aggregation": ["Expression": ["Column": ["Expression": ["SourceRef": ["Entity": "Sales"]], "Property": "OrderID"]],
                                       "Function": 5]],
             "queryRef": "CountNonNull(Sales.OrderID)", "nativeQueryRef": "Count of OrderID"],
        ]
        #expect((y as NSArray).isEqual(to: expected))
        // Visual chỉ có Y: sắp xếp mặc định giảm dần theo trường đầu (như measure; f10: `isDefaultSort` theo Sum of Amount).
        #expect(String(decoding: out, as: UTF8.self).contains(#""sortDefinition":{"sort":[{"field":{"Aggregation":"#))
    }

    /// Đổi phép gộp: Desktop giữ `queryRef` lúc thêm, chỉ đổi `Function` và `nativeQueryRef` ("Average of Amount" vẫn `Sum(...)`).
    @Test func doiPhepGopGiuQueryRef() throws {
        let sum = PBIRQueryPatch.newAggregation(entity: "Sales", property: "Amount", function: 0, role: "Y")
        let first = try PBIRQueryPatch.apply([.init(role: "Y", elements: [sum])], to: Self.bare)
        var wells = try PBIRQueryPatch.wells(in: first)
        wells[0].elements[0] = PBIRQueryPatch.changingAggregation(wells[0].elements[0], to: 1)
        let y = try projections(try PBIRQueryPatch.apply(wells, to: first), "Y")
        #expect(y.count == 1)
        #expect(y[0]["queryRef"] as? String == "Sum(Sales.Amount)")
        #expect(y[0]["nativeQueryRef"] as? String == "Average of Amount")
        let aggregation = (y[0]["field"] as? [String: Any])?["Aggregation"] as? [String: Any]
        #expect(aggregation?["Function"] as? Int == 1)
    }

    @Test func docMaPhepGop() throws {
        let card = Data(#"{"name":"b","visual":{"visualType":"cardVisual","query":{"queryState":{"Data":{"projections":[{"field":{"Aggregation":{"Expression":{"Column":{"Expression":{"SourceRef":{"Entity":"Sales"}},"Property":"CustomerID"}},"Function":2}},"queryRef":"CountNonNull(Sales.CustomerID)","nativeQueryRef":"Count of CustomerID1"}]}}}}}"#.utf8)
        let field = try #require(try PBIRQueryPatch.wells(in: card).first?.elements.first?.field)
        #expect(field.kind == .aggregation && field.aggregationFunction == 2)
        #expect(field.entity == "Sales" && field.property == "CustomerID")
        #expect(field.function == "Số lượng (riêng biệt)")
    }
}
