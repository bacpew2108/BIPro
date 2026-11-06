import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Gói A: Advanced và Top N")
@MainActor
struct FilterRuleTests {
    private let region = QueryColumn(table: "Dim_Client", column: "client_region")
    private let year = QueryColumn(table: "Dim_Date", column: "year")

    @Test func advancedChuMotDieuKien() {
        let rule = FilterRule.advanced(first: .init(kind: .contains, operand: "east"), second: nil, useOr: false, numeric: false)
        #expect(rule.predicate(column: region) == "CONTAINSSTRING('Dim_Client'[client_region], \"east\")")
        #expect(rule.summary == "chứa east")
    }

    @Test func advancedHaiDieuKienVaToanHangSai() {
        let and = FilterRule.advanced(first: .init(kind: .greaterOrEqual, operand: "2014"), second: .init(kind: .lessThan, operand: "2017"),
                                      useOr: false, numeric: true)
        #expect(and.predicate(column: year) == "AND('Dim_Date'[year] >= 2014, 'Dim_Date'[year] < 2017)")
        let or = FilterRule.advanced(first: .init(kind: .isEqual, operand: "2011"), second: .init(kind: .isBlank, operand: ""), useOr: true, numeric: true)
        #expect(or.predicate(column: year) == "OR('Dim_Date'[year] = 2011, ISBLANK('Dim_Date'[year]))")
        #expect(or.summary == "là 2011 hoặc trống")
        // Cột số mà toán hạng không phải số, hoặc điều kiện thứ hai còn dở: chưa lọc, không lọc nửa vời.
        let bad = FilterRule.advanced(first: .init(kind: .isEqual, operand: "abc"), second: nil, useOr: false, numeric: true)
        #expect(bad.predicate(column: year) == nil)
        let half = FilterRule.advanced(first: .init(kind: .isEqual, operand: "1"), second: .init(kind: .contains, operand: ""), useOr: false, numeric: true)
        #expect(half.predicate(column: year) == nil)
    }

    @Test func chuoiCoDauNhayKep() {
        let c = FilterCondition(kind: .startsWith, operand: "a\"b")
        #expect(c.predicate(column: region, numeric: false) == "LEFT('Dim_Client'[client_region], 3) = \"a\"\"b\"")
        #expect(FilterCondition(kind: .doesNotContain, operand: "x").predicate(column: region, numeric: false)
                == "NOT(CONTAINSSTRING('Dim_Client'[client_region], \"x\"))")
    }

    @Test func topN() {
        let rule = FilterRule.topN(TopNRule(count: 3, top: true, measureTable: "Fact_Transaction", measureName: "Trans Count"))
        #expect(rule.predicate(column: region)
                == "'Dim_Client'[client_region] IN TOPN(3, FILTER(ALL('Dim_Client'[client_region]), NOT(ISBLANK('Fact_Transaction'[Trans Count]))), 'Fact_Transaction'[Trans Count], DESC)")
        #expect(rule.summary == "Top 3 theo Trans Count")
        let bottom = TopNRule(count: 2, top: false, measureTable: "T", measureName: "M")
        #expect(bottom.predicate(column: region)?.hasSuffix("'T'[M], ASC)") == true)
        #expect(TopNRule(count: 0, top: true, measureTable: "T", measureName: "M").predicate(column: region) == nil)
    }

    @Test func userFilterDungRule() {
        var f = UserFilter(column: region)
        #expect(!f.isActive && f.predicate == nil)
        f.rule = .advanced(first: .init(kind: .isNot, operand: "West"), second: nil, useOr: false, numeric: false)
        #expect(f.isActive)
        #expect(f.predicate == "'Dim_Client'[client_region] <> \"West\"")
        #expect(f.summary == "không phải West")
    }

    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    @Test func docAdvancedTuFile() throws {
        let condition = try json("""
        {"And":{"Left":{"Comparison":{"ComparisonKind":2,"Left":{},"Right":{"Literal":{"Value":"2014L"}}}},
                "Right":{"Comparison":{"ComparisonKind":3,"Left":{},"Right":{"Literal":{"Value":"2017L"}}}}}}
        """)
        let rule = try #require(FilterRule.parseAdvanced(condition))
        #expect(rule.predicate(column: year) == "AND('Dim_Date'[year] >= 2014, 'Dim_Date'[year] < 2017)")
        let notContains = try json("""
        {"Not":{"Expression":{"Contains":{"Left":{},"Right":{"Literal":{"Value":"'abc'"}}}}}}
        """)
        #expect(FilterRule.parseAdvanced(notContains)?.predicate(column: region) == "NOT(CONTAINSSTRING('Dim_Client'[client_region], \"abc\"))")
        let isNull = try json("""
        {"Comparison":{"ComparisonKind":0,"Left":{},"Right":{"Literal":{"Value":"null"}}}}
        """)
        #expect(FilterRule.parseAdvanced(isNull)?.predicate(column: region) == "ISBLANK('Dim_Client'[client_region])")
        #expect(FilterRule.parseAdvanced(try json(#"{"In":{"Values":[]}}"#)) == nil, "dạng lạ thì không đọc")
    }

    @Test func themVaBoThe() {
        let key = UserFilterKey(level: .page, scope: "p1", filterID: "added-Dim_Client.client_region")
        let withAdded = ReportInteraction.mergeStatics(
            visual: [], visualID: "v1", page: [], pageID: "p1", report: [],
            user: [key: UserFilter(column: region, rule: .advanced(first: .init(kind: .contains, operand: "x"), second: nil, useOr: false, numeric: false))])
        #expect(withAdded.count == 1 && withAdded[0].scope == .page)
        let removedFile = ReportFilter(id: "f1", level: .report, field: nil, type: "Categorical", summary: "", isHidden: false, isLocked: false)
        let rkey = UserFilterKey(level: .report, scope: "", filterID: "f1")
        let kept = ReportInteraction.mergeStatics(visual: [], visualID: "v1", page: [], pageID: "p1", report: [removedFile], user: [:], removed: [rkey])
        #expect(kept.isEmpty)
    }
}
