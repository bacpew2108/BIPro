import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct FilterExportTests {
    let sex = QueryColumn(table: "Dim_Client", column: "sex")
    func key(_ id: String, level: ReportFilter.Level = .page, scope: String = "p1") -> UserFilterKey { UserFilterKey(level: level, scope: scope, filterID: id) }

    @Test func fileCardsKeepTheirNameAndGeneratedOnesGetAStableHex() {
        #expect(FilterExport.cardName(for: key("fSex"), column: sex) == "fSex")
        let a = FilterExport.cardName(for: key("added-Dim_Client.sex"), column: sex)
        let b = FilterExport.cardName(for: key("implicit-Dim_Client.sex-Category"), column: sex)
        #expect(a == b && a.count == 20 && a.allSatisfy(\.isHexDigit))
        #expect(a != FilterExport.cardName(for: key("added-Dim_Client.sex", scope: "p2"), column: sex))
        #expect(a != FilterExport.cardName(for: key("added-Dim_Client.sex", level: .report, scope: ""), column: sex))
        #expect(a == FilterExport.cardName(for: key("added-Dim_Client.sex"), column: sex))
    }

    @Test func emptyBasicIsACardWithoutFilter() {
        let card = FilterExport.card(for: UserFilter(column: sex), key: key("added-Dim_Client.sex")).value
        #expect(card?.type == "Categorical" && card?.filter == nil)
    }

    @Test func basicValuesAreWrittenSortedWithNotIn() {
        let filter = UserFilter(column: QueryColumn(table: "Dim_Date", column: "year"), values: [.integer(2017), .integer(2016)], exclude: true)
        let json = FilterExport.card(for: filter, key: key("added-Dim_Date.year")).value?.filter
        #expect(json?.contains(#""Not":{"Expression":{"In""#) == true)
        #expect(json?.contains(#""Values":[[{"Literal":{"Value":"2016L"}}],[{"Literal":{"Value":"2017L"}}]]"#) == true)
    }

    @Test func dateValuesAreSessionOnly() {
        let filter = UserFilter(column: sex, values: [.dateTime(1)])
        #expect(FilterExport.card(for: filter, key: key("added-x")).reason != nil)
    }

    @Test func advancedKindsAndLimits() {
        func adv(_ kind: ComparisonKind, second: FilterCondition? = nil, or: Bool = false, numeric: Bool = false) -> UserFilter {
            UserFilter(column: sex, rule: .advanced(first: FilterCondition(kind: kind, operand: "a"), second: second, useOr: or, numeric: numeric))
        }
        #expect(FilterExport.card(for: adv(.contains), key: key("added-x")).value?.type == "Advanced")
        #expect(FilterExport.card(for: adv(.doesNotStartWith), key: key("added-x")).value?.filter?.contains(#""Not":{"Expression":{"StartsWith""#) == true)
        #expect(FilterExport.card(for: adv(.contains, second: FilterCondition(kind: .doesNotContain, operand: "b")), key: key("added-x")).value?.filter?.contains(#""And""#) == true)
        #expect(FilterExport.card(for: adv(.contains, second: FilterCondition(kind: .contains, operand: "b"), or: true), key: key("added-x")).reason != nil)
        #expect(FilterExport.card(for: adv(.isEqual), key: key("added-x")).reason != nil)
        #expect(FilterExport.card(for: adv(.greaterThan, numeric: true), key: key("added-x")).reason != nil)
        #expect(FilterExport.card(for: UserFilter(column: sex, rule: .advanced(first: FilterCondition(kind: .contains, operand: " "), second: nil, useOr: false, numeric: false)),
                                  key: key("added-x")).value?.filter == nil)
    }

    @Test func topNTopOnlyAndMeasureCardsAreSessionOnly() {
        let top = UserFilter(column: sex, rule: .topN(TopNRule(count: 3, top: true, measureTable: "F", measureName: "M")))
        let bottom = UserFilter(column: sex, rule: .topN(TopNRule(count: 3, top: false, measureTable: "F", measureName: "M")))
        #expect(FilterExport.card(for: top, key: key("added-x")).value?.type == "TopN")
        #expect(FilterExport.card(for: bottom, key: key("added-x")).reason != nil)
        #expect(FilterExport.card(for: UserFilter(column: sex, isMeasure: true), key: key("added-x")).reason != nil)
    }
}
