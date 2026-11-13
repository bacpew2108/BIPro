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

    func adv(_ kind: ComparisonKind, _ operand: String = "a", second: FilterCondition? = nil, or: Bool = false, numeric: Bool = false,
             measure: Bool = false) -> UserFilter {
        UserFilter(column: measure ? QueryColumn(table: "Fact", column: "Total") : sex,
                   rule: .advanced(first: FilterCondition(kind: kind, operand: operand), second: second, useOr: or, numeric: numeric), isMeasure: measure)
    }
    func json(_ filter: UserFilter, id: String = "added-x") -> String? { FilterExport.card(for: filter, key: key(id)).value?.filter }

    @Test func advancedTextKinds() {
        #expect(FilterExport.card(for: adv(.contains), key: key("added-x")).value?.type == "Advanced")
        #expect(json(adv(.doesNotStartWith))?.contains(#""Not":{"Expression":{"StartsWith""#) == true)
        #expect(json(adv(.contains, second: FilterCondition(kind: .doesNotContain, operand: "b")))?.contains(#""And""#) == true)
        #expect(FilterExport.card(for: UserFilter(column: sex, rule: .advanced(first: FilterCondition(kind: .contains, operand: " "), second: nil, useOr: false, numeric: false)),
                                  key: key("added-x")).value?.filter == nil)
    }

    @Test func twoConditionsJoinedByOrAreWritten() {
        let text = json(adv(.contains, second: FilterCondition(kind: .contains, operand: "b"), or: true))
        #expect(text?.contains(#""Condition":{"Or":{"Left":{"Contains""#) == true)
    }

    @Test func isAndIsNotOnTextCompareWithAQuotedValue() {
        #expect(json(adv(.isEqual, "Other"))?.contains(#""Condition":{"Comparison":{"ComparisonKind":0,"Left":{"Column""#) == true)
        #expect(json(adv(.isEqual, "Other"))?.contains(#""Right":{"Literal":{"Value":"'Other'"}}"#) == true)
        #expect(json(adv(.isNot, "Other"))?.contains(#""Condition":{"Not":{"Expression":{"Comparison":{"ComparisonKind":0"#) == true)
    }

    @Test func blankAndNotBlankAreWrittenWithNull() {
        #expect(json(adv(.isBlank, ""))?.contains(#""ComparisonKind":0"#) == true)
        #expect(json(adv(.isBlank, ""))?.contains(#""Right":{"Literal":{"Value":"null"}}"#) == true)
        #expect(json(adv(.isNotBlank, "", numeric: true))?.contains(#""Not":{"Expression":{"Comparison""#) == true)
    }

    @Test func numericComparisonsWriteWholeNumbersAsLAndOthersAsD() {
        let range = json(adv(.greaterThan, "1980", second: FilterCondition(kind: .lessOrEqual, operand: "1990.5"), numeric: true))
        #expect(range?.contains(#""ComparisonKind":1"#) == true && range?.contains(#""Value":"1980L""#) == true)
        #expect(range?.contains(#""ComparisonKind":4"#) == true && range?.contains(#""Value":"1990.5D""#) == true)
        #expect(json(adv(.greaterOrEqual, "2", numeric: true))?.contains(#""ComparisonKind":2"#) == true)
        #expect(json(adv(.lessThan, "2", numeric: true))?.contains(#""ComparisonKind":3"#) == true)
        #expect(json(adv(.isNot, "2", numeric: true))?.contains(#""Value":"2L""#) == true)
    }

    @Test func aWholeNumberOnADecimalColumnIsWrittenAsD() {
        let filter = adv(.greaterThan, "5", second: FilterCondition(kind: .lessThan, operand: "9"), numeric: true)
        let card = FilterExport.card(for: filter, key: key("added-x"), decimal: true).value?.filter
        #expect(card?.contains(#""Value":"5D""#) == true && card?.contains(#""Value":"9D""#) == true && card?.contains("L\"") == false)
        #expect(FilterExport.card(for: filter, key: key("added-x")).value?.filter?.contains(#""Value":"5L""#) == true)
    }

    /// VM-D10: cột tiền tệ (Fixed decimal number) ghi toán hạng số nguyên là `…M`.
    @Test func aNumberOnACurrencyColumnIsWrittenAsM() {
        let filter = adv(.greaterThan, "1500", second: FilterCondition(kind: .lessThan, operand: "2500.5"), numeric: true)
        let card = FilterExport.card(for: filter, key: key("added-x"), currency: true).value?.filter
        #expect(card?.contains(#""Value":"1500M""#) == true && card?.contains(#""Value":"2500.5M""#) == true)
        #expect(card?.contains("L\"") == false && card?.contains("D\"") == false)
    }

    @Test func aNumericConditionWithoutANumberIsACardThatFiltersNothing() {
        let card = FilterExport.card(for: adv(.greaterThan, "abc", numeric: true), key: key("added-x")).value
        #expect(card?.type == "Advanced" && card?.filter == nil)
        let half = FilterExport.card(for: adv(.greaterThan, "1", second: FilterCondition(kind: .lessThan, operand: ""), numeric: true), key: key("added-x")).value
        #expect(half?.type == "Advanced" && half?.filter == nil)
    }

    @Test func topAndBottomNAreWritten() {
        let top = UserFilter(column: sex, rule: .topN(TopNRule(count: 3, top: true, measureTable: "F", measureName: "M")))
        let bottom = UserFilter(column: sex, rule: .topN(TopNRule(count: 3, top: false, measureTable: "F", measureName: "M")))
        #expect(FilterExport.card(for: top, key: key("added-x")).value?.type == "TopN")
        #expect(json(top)?.contains(#""Direction":2"#) == true)
        #expect(FilterExport.card(for: bottom, key: key("added-x")).value?.type == "TopN")
        #expect(json(bottom)?.contains(#""Direction":1"#) == true)
    }

    @Test func aMeasureCardIsAnAdvancedCardOnTheMeasure() {
        let key = key("implicit-Fact.Total-Y", level: .visual, scope: "v1")
        let card = FilterExport.card(for: adv(.lessThan, "500", second: FilterCondition(kind: .greaterThan, operand: "2000"), or: true, numeric: true, measure: true), key: key).value
        #expect(card?.kind == .measure && card?.type == "Advanced" && card?.entity == "Fact" && card?.property == "Total")
        #expect(card?.filter == #"{"Version":2,"From":[{"Name":"f","Entity":"Fact","Type":0}],"Where":[{"Condition":{"Or":{"Left":{"Comparison":{"ComparisonKind":3,"Left":{"Measure":{"Expression":{"SourceRef":{"Source":"f"}},"Property":"Total"}},"Right":{"Literal":{"Value":"500L"}}}},"Right":{"Comparison":{"ComparisonKind":1,"Left":{"Measure":{"Expression":{"SourceRef":{"Source":"f"}},"Property":"Total"}},"Right":{"Literal":{"Value":"2000L"}}}}}}}]}"#)
        // Thẻ measure chưa đặt điều kiện: Desktop ghi `type:"Advanced"`, không có `filter` (VM-D6, VM-D8).
        let empty = FilterExport.card(for: UserFilter(column: QueryColumn(table: "Fact", column: "Total"), isMeasure: true), key: key).value
        #expect(empty?.kind == .measure && empty?.type == "Advanced" && empty?.filter == nil)
    }

    // MARK: Ghi rồi đọc lại (lưu xong mở lại không được mất điều kiện)

    /// Thẻ BI Pro ghi, đọc lại bằng bộ đọc của app, như lúc mở file vừa lưu.
    func reread(_ filter: UserFilter, level: ReportFilter.Level = .visual, id: String = "added-x") throws -> ReportFilter {
        let card = try #require(FilterExport.card(for: filter, key: key(id, level: level, scope: "v1")).value)
        let json = try JSONValue.parse(Data(PBIRFilterPatch.cardJSON(card).utf8))
        return try #require(PBIXFile.filters(.array([json]), level: level).first)
    }

    @Test func whatIsWrittenReadsBackAsTheSameFilter() throws {
        let filters: [UserFilter] = [
            adv(.contains, second: FilterCondition(kind: .startsWith, operand: "b"), or: true),
            adv(.isEqual, "Other", second: FilterCondition(kind: .isNot, operand: "Late fee"), or: true),
            adv(.isBlank, ""), adv(.isNotBlank, ""),
            adv(.greaterThan, "1980", second: FilterCondition(kind: .lessOrEqual, operand: "1990.5"), numeric: true),
            adv(.isNot, "7", numeric: true),
            UserFilter(column: sex, rule: .topN(TopNRule(count: 5, top: true, measureTable: "Fact", measureName: "Total"))),
            UserFilter(column: sex, rule: .topN(TopNRule(count: 3, top: false, measureTable: "Dim_Client", measureName: "Clients"))),
            adv(.lessThan, "500", second: FilterCondition(kind: .greaterThan, operand: "2000"), or: true, numeric: true, measure: true),
            adv(.isBlank, "", numeric: true, measure: true),
            UserFilter(column: QueryColumn(table: "Fact", column: "Total"), isMeasure: true),
        ]
        for filter in filters {
            #expect(UserFilter.from(try reread(filter)) == filter, "\(filter.summary)")
        }
    }

    @Test func aTopNCardInTheFileFiltersTheQuery() throws {
        let bottom = UserFilter(column: sex, rule: .topN(TopNRule(count: 3, top: false, measureTable: "Fact", measureName: "Total")))
        let applied = VisualQuerySpecReader.staticFilter(try reread(bottom, level: .page), scope: .page)
        #expect(applied?.column == sex)
        #expect(applied?.predicate == bottom.predicate)
        #expect(bottom.predicate?.contains("TOPN(3") == true)
    }

    @Test func aMeasureCardInTheFileFiltersTheRowsOfItsVisualAndIsNotAColumnFilter() throws {
        let edit = adv(.lessThan, "500", numeric: true, measure: true)
        let inFile = try reread(edit, id: "implicit-Fact.Total-Y")
        #expect(VisualQuerySpecReader.staticFilter(inFile, scope: .visual) == nil)
        let rule = try #require(edit.rule)
        #expect(ReportInteraction.valueFilters(visual: [inFile], visualID: "v1", user: [:]) == [ValueFilter(table: "Fact", measure: "Total", rule: rule)])
        // Thẻ trong file mà người dùng đã sửa hoặc đã bỏ thì theo phần sửa.
        let cardKey = UserFilterKey(level: .visual, scope: "v1", filterID: inFile.id)
        let other = adv(.greaterThan, "9", numeric: true, measure: true)
        #expect(ReportInteraction.valueFilters(visual: [inFile], visualID: "v1", user: [cardKey: other]).map(\.rule) == [try #require(other.rule)])
        #expect(ReportInteraction.valueFilters(visual: [inFile], visualID: "v1", user: [:], removed: [cardKey]).isEmpty)
        #expect(ReportInteraction.valueFilters(visual: [inFile], visualID: "v2", user: [cardKey: other]).map(\.rule) == [rule])
    }
}
