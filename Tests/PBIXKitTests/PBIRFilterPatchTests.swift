import Foundation
import Testing
@testable import PBIXKit

@Suite("D6 PBIRFilterPatch")
struct PBIRFilterPatchTests {
    /// `page.json` thật của Desktop sau khi thêm bộ lọc Basic (VM-D6, `json/page-basic-in.json`).
    let desktopPageBasicIn = #"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json","name":"d3_cskh","displayName":"D3 · Chăm sóc KH","displayOption":"FitToPage","height":1080,"width":1920,"filterConfig":{"filters":[{"name":"544928face53009005b5","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"sex"}},"type":"Categorical","filter":{"Version":2,"From":[{"Name":"d","Entity":"Dim_Client","Type":0}],"Where":[{"Condition":{"In":{"Expressions":[{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"sex"}}],"Values":[[{"Literal":{"Value":"'Female'"}}]]}}}]},"howCreated":"User"}]},"objects":{"background":[{"properties":{"transparency":{"expr":{"Literal":{"Value":"0D"}}}}}]}}"#
    let pageBefore = #"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json","name":"d3_cskh","displayName":"D3 · Chăm sóc KH","displayOption":"FitToPage","height":1080,"width":1920,"objects":{"background":[{"properties":{"transparency":{"expr":{"Literal":{"Value":"0D"}}}}}]}}"#

    func sexCard(values: [FilterLiteral]? = nil, exclude: Bool = false) -> FilterCardSpec {
        let filter = values.map { PBIRFilterPatch.categoricalFilter(entity: "Dim_Client", property: "sex", values: $0, exclude: exclude) }
        return FilterCardSpec(name: "544928face53009005b5", entity: "Dim_Client", property: "sex", type: "Categorical", filter: filter)
    }

    @Test func newBasicCardOnPageMatchesDesktopByteForByte() throws {
        let out = try PBIRFilterPatch.apply([.upsert(sexCard(values: [.string("Female")]))], level: .page, to: Data(pageBefore.utf8))
        #expect(String(decoding: out, as: UTF8.self) == desktopPageBasicIn)
    }

    @Test func emptyBasicCardHasNoFilterKey() throws {
        let out = String(decoding: try PBIRFilterPatch.apply([.upsert(sexCard())], level: .page, to: Data(pageBefore.utf8)), as: UTF8.self)
        #expect(out.contains(#""filterConfig":{"filters":[{"name":"544928face53009005b5","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"sex"}},"type":"Categorical","howCreated":"User"}]},"objects""#))
    }

    @Test func removingTheLastCardRestoresTheOriginalBytes() throws {
        let removed = try PBIRFilterPatch.apply([.remove(name: "544928face53009005b5")], level: .page, to: Data(desktopPageBasicIn.utf8))
        #expect(String(decoding: removed, as: UTF8.self) == pageBefore)
    }

    @Test func upsertSameNameChangesOnlyTypeAndFilterKeepingOtherKeys() throws {
        let locked = desktopPageBasicIn.replacingOccurrences(of: #""howCreated":"User""#, with: #""howCreated":"User","isLockedInViewMode":true"#)
        let out = try PBIRFilterPatch.apply([.upsert(sexCard(values: [.string("Male")], exclude: true))], level: .page, to: Data(locked.utf8))
        let text = String(decoding: out, as: UTF8.self)
        #expect(text.contains(#""isLockedInViewMode":true"#))
        #expect(text.contains(#""Not":{"Expression":{"In":"#))
        #expect(text.contains("'Male'") && !text.contains("'Female'"))
    }

    @Test func clearingTheFilterOfAnExistingCardDropsTheFilterKey() throws {
        let out = String(decoding: try PBIRFilterPatch.apply([.upsert(sexCard())], level: .page, to: Data(desktopPageBasicIn.utf8)), as: UTF8.self)
        #expect(!out.contains("\"filter\":"))
        #expect(out.contains(#""type":"Categorical","howCreated":"User""#))
    }

    @Test func appendsAtTheEndOfAnExistingArrayLeavingOldCardsUntouched() throws {
        let report = #"{"$schema":"s","themeCollection":{"baseTheme":{}},"filterConfig":{"filters":[{"name":"fOld","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"year"}},"type":"Categorical"}]},"objects":{}}"#
        let card = FilterCardSpec(name: "n1", entity: "Dim_Client", property: "sex", type: "Categorical")
        let out = String(decoding: try PBIRFilterPatch.apply([.upsert(card)], level: .report, to: Data(report.utf8)), as: UTF8.self)
        #expect(out.hasPrefix(String(report.dropLast(#"]},"objects":{}}"#.count))))
        #expect(out.hasSuffix(#",{"name":"n1","field":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"sex"}},"type":"Categorical","howCreated":"User"}]},"objects":{}}"#))
    }

    @Test func visualGetsFilterConfigAfterTheVisualKey() throws {
        let visual = #"{"$schema":"s","name":"v","position":{"x":1},"visual":{"visualType":"card"}}"#
        let card = FilterCardSpec(name: "c", kind: .measure, entity: "F", property: "M", type: "Advanced")
        let out = String(decoding: try PBIRFilterPatch.apply([.upsert(card)], level: .visual, to: Data(visual.utf8)), as: UTF8.self)
        #expect(out == #"{"$schema":"s","name":"v","position":{"x":1},"visual":{"visualType":"card"},"filterConfig":{"filters":[{"name":"c","field":{"Measure":{"Expression":{"SourceRef":{"Entity":"F"}},"Property":"M"}},"type":"Advanced","howCreated":"User"}]}}"#)
    }

    @Test func removeOneOfTwoKeepsTheOther() throws {
        let two = try PBIRFilterPatch.apply([.upsert(sexCard()), .upsert(FilterCardSpec(name: "b", entity: "Dim_Date", property: "year", type: "Categorical"))],
                                            level: .page, to: Data(pageBefore.utf8))
        let one = try PBIRFilterPatch.apply([.remove(name: "544928face53009005b5")], level: .page, to: two)
        let obj = try #require(JSONSerialization.jsonObject(with: one) as? [String: Any])
        let filters = try #require((obj["filterConfig"] as? [String: Any])?["filters"] as? [[String: Any]])
        #expect(filters.map { $0["name"] as? String } == ["b"])
    }

    // MARK: Dạng filter theo mẫu Desktop (VM-D6)

    @Test func advancedStartsWithMatchesDesktop() {
        let text = PBIRFilterPatch.advancedTextFilter(entity: "Dim_Client", property: "sex", conditions: [.init(.startsWith, text: "Fem")])
        #expect(text == #"{"Version":2,"From":[{"Name":"d","Entity":"Dim_Client","Type":0}],"Where":[{"Condition":{"StartsWith":{"Left":{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"sex"}},"Right":{"Literal":{"Value":"'Fem'"}}}}}]}"#)
    }

    @Test func advancedContainsAndNotContainsMatchesDesktop() {
        let text = PBIRFilterPatch.advancedTextFilter(entity: "Dim_Client", property: "sex",
                                                      conditions: [.init(.contains, text: "e"), .init(.contains, negated: true, text: "x")])
        #expect(text == #"{"Version":2,"From":[{"Name":"d","Entity":"Dim_Client","Type":0}],"Where":[{"Condition":{"And":{"Left":{"Contains":{"Left":{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"sex"}},"Right":{"Literal":{"Value":"'e'"}}}},"Right":{"Not":{"Expression":{"Contains":{"Left":{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"sex"}},"Right":{"Literal":{"Value":"'x'"}}}}}}}}}]}"#)
    }

    @Test func advancedRejectsMoreThanTwoConditions() {
        let c = PBIRFilterPatch.TextCondition(.contains, text: "a")
        #expect(PBIRFilterPatch.advancedTextFilter(entity: "E", property: "p", conditions: [c, c, c]) == nil)
        #expect(PBIRFilterPatch.advancedTextFilter(entity: "E", property: "p", conditions: []) == nil)
    }

    @Test func topNMatchesDesktopShape() throws {
        let text = PBIRFilterPatch.topNFilter(entity: "Dim_CRM_Issue", property: "product", measureEntity: "Fact_CRM_Complaint", measureProperty: "Complaints", count: 1)
        let expected = #"{"Version":2,"From":[{"Name":"subquery","Expression":{"Subquery":{"Query":{"Version":2,"From":[{"Name":"d","Entity":"Dim_CRM_Issue","Type":0},{"Name":"f","Entity":"Fact_CRM_Complaint","Type":0}],"Select":[{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"product"},"Name":"field"}],"OrderBy":[{"Direction":2,"Expression":{"Measure":{"Expression":{"SourceRef":{"Source":"f"}},"Property":"Complaints"}}}],"Top":1}}},"Type":2},{"Name":"d","Entity":"Dim_CRM_Issue","Type":0}],"Where":[{"Condition":{"In":{"Expressions":[{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"product"}}],"Table":{"SourceRef":{"Source":"subquery"}}}}}]}"#
        #expect(text == expected)
    }

    @Test func literalsFollowPowerBIQuoting() {
        #expect(FilterLiteral.string("It's").text == "'It''s'")
        #expect(FilterLiteral.integer(2016).text == "2016L")
        #expect(FilterLiteral.decimal(1.5).text == "1.5D")
        #expect(FilterLiteral.decimal(3).text == "3D")
        #expect(FilterLiteral.boolean(true).text == "true")
    }

    @Test func aliasesAreFirstLetterAndAvoidClashes() {
        #expect(PBIRFilterPatch.aliases(for: ["Dim_Client", "Fact_Loan"]) == ["Dim_Client": "d", "Fact_Loan": "f"])
        let clash = PBIRFilterPatch.aliases(for: ["Dim_Client", "Dim_Date"])
        #expect(clash["Dim_Client"] == "d" && clash["Dim_Date"] == "d2")
    }

    @Test func multiValueBasicListsEachValueInItsOwnArray() throws {
        let text = PBIRFilterPatch.categoricalFilter(entity: "Dim_Date", property: "year", values: [.integer(2016), .integer(2017)], exclude: false)
        #expect(text.contains(#""Values":[[{"Literal":{"Value":"2016L"}}],[{"Literal":{"Value":"2017L"}}]]"#))
        _ = try JSONSerialization.jsonObject(with: Data(text.utf8))
    }
}
