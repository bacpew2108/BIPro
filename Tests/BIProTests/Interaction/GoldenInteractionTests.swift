import DAXEngine
import Foundation
import Testing
@testable import BIPro

private let interactDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/phase-c-evidence/observe-c1/interact")

private func loadDAX(_ filename: String) throws -> String {
    let url = interactDir.appendingPathComponent(filename)
    let data = try Data(contentsOf: url)
    guard let str = String(data: data, encoding: .utf8) else {
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return str.replacingOccurrences(of: "\r", with: "")
}

private func extractVar(from fileText: String, varName: String) -> String {
    let cleanText = fileText.replacingOccurrences(of: "\r", with: "")
    let pattern = "VAR\\s+" + NSRegularExpression.escapedPattern(for: varName) + "\\s*=\\s*"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
    let nsText = cleanText as NSString
    guard let match = regex.firstMatch(in: cleanText, range: NSRange(location: 0, length: nsText.length)) else {
        return ""
    }
    let bodyStart = match.range.location + match.range.length
    let restOfText = nsText.substring(from: bodyStart)

    let endPattern = "\\n\\s*(VAR\\s+\\w+|EVALUATE)"
    if let endRegex = try? NSRegularExpression(pattern: endPattern),
       let endMatch = endRegex.firstMatch(in: restOfText, range: NSRange(location: 0, length: (restOfText as NSString).length)) {
        let body = (restOfText as NSString).substring(to: endMatch.range.location)
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return restOfText.trimmingCharacters(in: .whitespacesAndNewlines)
}

@Suite("Golden Interaction Tests (Observe C1)")
struct GoldenInteractionTests {
    let colYear = QueryColumn(table: "Dim_Date", column: "year")
    let colQuarter = QueryColumn(table: "Dim_Date", column: "quarter_name")
    let colRegion = QueryColumn(table: "Dim_Client", column: "client_region")
    let colAgeLoan = QueryColumn(table: "Fact_Loan", column: "age_group_at_loan")
    let colDistrictState = QueryColumn(table: "Dim_District", column: "state_name")

    var reportStaticFilters: [StaticFilter] {
        [
            StaticFilter(column: colYear, predicate: "NOT('Dim_Date'[year] IN {9999})", scope: .report),
            StaticFilter(column: colRegion, predicate: "NOT('Dim_Client'[client_region] IN {\"Unknown\"})", scope: .report)
        ]
    }

    // 1. slicer1-card: slicer năm [[2016]] + 2 bộ lọc report
    @Test func testSlicer1Card() throws {
        let daxText = try loadDAX("slicer1-card.dax")
        let expectedFilter1 = extractVar(from: daxText, varName: "__DS0FilterTable")
        let expectedFilter2 = extractVar(from: daxText, varName: "__DS0FilterTable2")

        var state = FilterState()
        state.setSlicer(
            visualID: "slicer_year",
            columns: [colYear],
            selection: SlicerSelection([[.integer(2016)]])
        )

        let target = InteractionTarget(visualID: "card1", visualType: "card")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: reportStaticFilters, state: state)

        #expect(assembled.filters.count == 2)
        #expect(DAXQueryBuilder.normalized(assembled.filters[0].tableExpression) == DAXQueryBuilder.normalized(expectedFilter1))
        #expect(DAXQueryBuilder.normalized(assembled.filters[1].tableExpression) == DAXQueryBuilder.normalized(expectedFilter2))
        #expect(assembled.highlight == nil)
    }

    // 2. slicer2-card: slicer năm [[2016],[2017]]
    @Test func testSlicer2Card() throws {
        let daxText = try loadDAX("slicer2-card.dax")
        let expectedFilter1 = extractVar(from: daxText, varName: "__DS0FilterTable")
        let expectedFilter2 = extractVar(from: daxText, varName: "__DS0FilterTable2")

        var state = FilterState()
        state.setSlicer(
            visualID: "slicer_year",
            columns: [colYear],
            selection: SlicerSelection([[.integer(2016)], [.integer(2017)]])
        )

        let target = InteractionTarget(visualID: "card1", visualType: "card")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: reportStaticFilters, state: state)

        #expect(assembled.filters.count == 2)
        #expect(DAXQueryBuilder.normalized(assembled.filters[0].tableExpression) == DAXQueryBuilder.normalized(expectedFilter1))
        #expect(DAXQueryBuilder.normalized(assembled.filters[1].tableExpression) == DAXQueryBuilder.normalized(expectedFilter2))
        #expect(assembled.highlight == nil)
    }

    // 3. slicer3-quy: slicer Năm › Quý với [[2016, "Q1"]], cột Dim_Date[year], Dim_Date[quarter_name]
    @Test func testSlicer3Quy() throws {
        let daxText = try loadDAX("slicer3-quy.dax")
        let expectedFilter1 = extractVar(from: daxText, varName: "__DS0FilterTable")
        let expectedFilter2 = extractVar(from: daxText, varName: "__DS0FilterTable2")

        var state = FilterState()
        state.setSlicer(
            visualID: "slicer_y_q",
            columns: [colYear, colQuarter],
            selection: SlicerSelection([[.integer(2016), .string("Q1")]])
        )

        let target = InteractionTarget(visualID: "card1", visualType: "card")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: reportStaticFilters, state: state)

        #expect(assembled.filters.count == 2)
        #expect(DAXQueryBuilder.normalized(assembled.filters[0].tableExpression) == DAXQueryBuilder.normalized(expectedFilter1))
        #expect(DAXQueryBuilder.normalized(assembled.filters[1].tableExpression) == DAXQueryBuilder.normalized(expectedFilter2))
        #expect(assembled.highlight == nil)
    }

    // 4. xf-card: nguồn clusteredBarChart chọn Fact_Loan.age_group_at_loan = "35-49", đích card
    @Test func testXFCard() throws {
        let daxText = try loadDAX("xf-card.dax")
        let expectedFilter1 = extractVar(from: daxText, varName: "__DS0FilterTable")
        let expectedFilter2 = extractVar(from: daxText, varName: "__DS0FilterTable2")
        let expectedFilter3 = extractVar(from: daxText, varName: "__DS0FilterTable3")

        var state = FilterState()
        let source = InteractionTarget(visualID: "bar1", visualType: "clusteredBarChart")
        let crossCol = CrossColumn(queryRef: "Fact_Loan.age_group_at_loan", column: colAgeLoan)
        let pt = DataPointID(["Fact_Loan.age_group_at_loan": .string("35-49")])
        state.selection.select(pt, additive: false, from: source, columns: [crossCol])

        let target = InteractionTarget(visualID: "card1", visualType: "card")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: reportStaticFilters, state: state)

        #expect(assembled.filters.count == 3)
        #expect(DAXQueryBuilder.normalized(assembled.filters[0].tableExpression) == DAXQueryBuilder.normalized(expectedFilter1))
        #expect(DAXQueryBuilder.normalized(assembled.filters[1].tableExpression) == DAXQueryBuilder.normalized(expectedFilter2))
        #expect(DAXQueryBuilder.normalized(assembled.filters[2].tableExpression) == DAXQueryBuilder.normalized(expectedFilter3))
        #expect(assembled.highlight == nil)
    }

    // 5. xf-combo, xf-combo2, xf-100pct, xf-donut: đích tô sáng
    @Test func testXFHighlightVisuals() throws {
        var state = FilterState()
        let source = InteractionTarget(visualID: "bar1", visualType: "clusteredBarChart")
        let crossCol = CrossColumn(queryRef: "Fact_Loan.age_group_at_loan", column: colAgeLoan)
        let pt = DataPointID(["Fact_Loan.age_group_at_loan": .string("35-49")])
        state.selection.select(pt, additive: false, from: source, columns: [crossCol])

        let cases: [(filename: String, targetType: String, visualID: String)] = [
            ("xf-combo.dax", "lineClusteredColumnComboChart", "combo1"),
            ("xf-combo2.dax", "lineClusteredColumnComboChart", "combo2"),
            ("xf-100pct.dax", "hundredPercentStackedColumnChart", "pct1"),
            ("xf-donut.dax", "donutChart", "donut1")
        ]

        for (filename, targetType, visualID) in cases {
            let daxText = try loadDAX(filename)
            let expectedHighlight = extractVar(from: daxText, varName: "__H0FilterTable")
            let expectedFilter1 = extractVar(from: daxText, varName: "__DS0FilterTable")
            let expectedFilter2 = extractVar(from: daxText, varName: "__DS0FilterTable2")

            let target = InteractionTarget(visualID: visualID, visualType: targetType)
            let assembled = FilterTranslator.assemble(for: target, staticFilters: reportStaticFilters, state: state)

            #expect(assembled.filters.count == 2)
            #expect(DAXQueryBuilder.normalized(assembled.filters[0].tableExpression) == DAXQueryBuilder.normalized(expectedFilter1))
            #expect(DAXQueryBuilder.normalized(assembled.filters[1].tableExpression) == DAXQueryBuilder.normalized(expectedFilter2))
            #expect(assembled.highlight != nil)
            if let h = assembled.highlight {
                #expect(DAXQueryBuilder.normalized(h.tableExpression) == DAXQueryBuilder.normalized(expectedHighlight))
            }
        }
    }

    // 6. dt-card, dt-line, dt-subtitle: drillthrough New Mexico trên Dim_District[state_name]
    @Test func testDrillthroughVisuals() throws {
        var state = FilterState()
        state.drillthrough = [ColumnValues(column: colDistrictState, values: [.string("New Mexico")])]

        let cases: [(filename: String, targetType: String, visualID: String)] = [
            ("dt-card.dax", "card", "card1"),
            ("dt-line.dax", "lineChart", "line1"),
            ("dt-subtitle.dax", "card", "subtitle1")
        ]

        for (filename, targetType, visualID) in cases {
            let daxText = try loadDAX(filename)
            let expectedFilter1 = extractVar(from: daxText, varName: "__DS0FilterTable")
            let expectedFilter2 = extractVar(from: daxText, varName: "__DS0FilterTable2")
            let expectedFilter3 = extractVar(from: daxText, varName: "__DS0FilterTable3")

            let target = InteractionTarget(visualID: visualID, visualType: targetType)
            let assembled = FilterTranslator.assemble(for: target, staticFilters: reportStaticFilters, state: state)

            #expect(assembled.filters.count == 3)
            #expect(DAXQueryBuilder.normalized(assembled.filters[0].tableExpression) == DAXQueryBuilder.normalized(expectedFilter1))
            #expect(DAXQueryBuilder.normalized(assembled.filters[1].tableExpression) == DAXQueryBuilder.normalized(expectedFilter2))
            #expect(DAXQueryBuilder.normalized(assembled.filters[2].tableExpression) == DAXQueryBuilder.normalized(expectedFilter3))
            #expect(assembled.highlight == nil)
        }
    }

    // 7. drill-down-2016: drillFilters cho đúng visual; visual khác không nhận
    @Test func testDrillDown2016() throws {
        let daxText = try loadDAX("drill-down-2016.dax")
        let expectedFilter1 = extractVar(from: daxText, varName: "__DS0FilterTable")
        let expectedFilter2 = extractVar(from: daxText, varName: "__DS0FilterTable2")

        var state = FilterState()
        state.drillFilters["chart1"] = [ColumnValues(column: colYear, values: [.integer(2016)])]

        let target = InteractionTarget(visualID: "chart1", visualType: "clusteredColumnChart")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: reportStaticFilters, state: state)

        #expect(assembled.filters.count == 2)
        #expect(DAXQueryBuilder.normalized(assembled.filters[0].tableExpression) == DAXQueryBuilder.normalized(expectedFilter1))
        #expect(DAXQueryBuilder.normalized(assembled.filters[1].tableExpression) == DAXQueryBuilder.normalized(expectedFilter2))

        // Visual khác không nhận drill down
        let otherTarget = InteractionTarget(visualID: "chart2", visualType: "clusteredColumnChart")
        let otherAssembled = FilterTranslator.assemble(for: otherTarget, staticFilters: reportStaticFilters, state: state)
        #expect(otherAssembled.filters.count == 2)
        // Không chứa year IN {2016}
        #expect(!otherAssembled.filters[0].tableExpression.contains("2016"))
        #expect(DAXQueryBuilder.normalized(otherAssembled.filters[0].tableExpression) == "FILTER(KEEPFILTERS(VALUES('Dim_Date'[year])), NOT('Dim_Date'[year] IN {9999}))")
    }
}
