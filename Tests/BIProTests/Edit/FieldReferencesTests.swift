import Foundation
import Testing
@testable import BIPro

@Suite struct FieldReferencesTests {
    /// Cấu trúc như visual thật của Nhom6: sắp xếp theo cột, thẻ lọc cấp visual (bí danh `Source` trong `filter`),
    /// định dạng riêng theo trường qua `selector.metadata`.
    static let json = Data(#"""
    {"name":"v1","visual":{"visualType":"lineChart",
     "query":{"queryState":{"Category":{"projections":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"month_name"}},"queryRef":"Dim_Date.month_name","nativeQueryRef":"month_name"}]},
                            "Y":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"Credit"}},"queryRef":"Fact.Credit","nativeQueryRef":"Credit"}]}},
              "sortDefinition":{"sort":[{"field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"month_name"}},"direction":"Ascending"}],"isDefaultSort":true}},
     "objects":{"values":[{"properties":{"fill":{"solid":{"color":{"expr":{"Literal":{"Value":"'#FF0000'"}}}}}},"selector":{"metadata":"Fact.Credit"}},
                          {"properties":{"labelColor":{}},"selector":{"metadata":"Fact.Credit Δ"}}]}},
     "filterConfig":{"filters":[{"name":"f1","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"trans_hour"}},"type":"Categorical",
        "filter":{"Version":2,"From":[{"Name":"x","Entity":"Fact","Type":0}],"Where":[{"Condition":{"Not":{"Expression":{"In":{"Expressions":[{"Column":{"Expression":{"SourceRef":{"Source":"x"}},"Property":"trans_hour"}}],"Values":[[{"Literal":{"Value":"17L"}}]]}}}}}]}}]}}
    """#.utf8)

    @Test func findsSortFilterAndFormatReferences() {
        let month = FieldReferences.find(in: Self.json, entity: "Dim_Date", property: "month_name", queryRef: "Dim_Date.month_name")
        #expect(month.map(\.kind) == [.sort])
        let hour = FieldReferences.find(in: Self.json, entity: "Fact", property: "trans_hour", queryRef: "Fact.trans_hour")
        #expect(hour.map(\.kind) == [.filter])
        let credit = FieldReferences.find(in: Self.json, entity: "Fact", property: "Credit", queryRef: "Fact.Credit")
        #expect(credit.map(\.kind) == [.format])
        #expect(credit.first?.detail.isEmpty == false)
    }

    @Test func otherFieldsAndSimilarNamesAreNotMatched() {
        #expect(FieldReferences.find(in: Self.json, entity: "Fact", property: "month_name", queryRef: "Fact.month_name").isEmpty)
        #expect(FieldReferences.find(in: Self.json, entity: "Dim_Date", property: "month", queryRef: "Dim_Date.month").isEmpty)
        // "Fact.Credit Δ" là một trường khác, không phải "Fact.Credit"
        #expect(FieldReferences.find(in: Self.json, entity: "Fact", property: "Credit Δ", queryRef: "Fact.Credit Δ").map(\.kind) == [.format])
        #expect(FieldReferences.find(in: Self.json, entity: "Nope", property: "x", queryRef: "Nope.x").isEmpty)
    }

    @Test func visualWithoutReferencesAndBadJSONGiveNothing() {
        let plain = Data(#"{"name":"v","visual":{"visualType":"card","query":{"queryState":{"Values":{"projections":[]}}}}}"#.utf8)
        #expect(FieldReferences.find(in: plain, entity: "A", property: "b", queryRef: "A.b").isEmpty)
        #expect(FieldReferences.find(in: Data("oops".utf8), entity: "A", property: "b", queryRef: "A.b").isEmpty)
    }

    @Test func aggregationAndHierarchySortFieldsResolveToTheirColumn() {
        let json = Data(#"{"visual":{"query":{"sortDefinition":{"sort":[{"field":{"Aggregation":{"Expression":{"Column":{"Expression":{"SourceRef":{"Entity":"Fact"}},"Property":"amount"}},"Function":0}},"direction":"Descending"}]}}}}"#.utf8)
        #expect(FieldReferences.find(in: json, entity: "Fact", property: "amount", queryRef: "Sum(Fact.amount)").map(\.kind) == [.sort])
    }
}
