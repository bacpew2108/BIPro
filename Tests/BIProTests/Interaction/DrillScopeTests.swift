import DAXEngine
import Foundation
import Testing
@testable import BIPro

/// "Apply drill down filters to" (VM 2026-11-23): Entire page (mặc định) lọc các visual khác theo đường drill; Selected visual thì không.
@Suite("Drill down filter scope")
struct DrillScopeTests {
    private let product = QueryColumn(table: "Dim_CRM_Issue", column: "product")
    private let other = InteractionTarget(visualID: "kpi", visualType: "card")
    private let source = InteractionTarget(visualID: "tree", visualType: "treemap")

    private func state(selectedOnly: Bool = false, overrides: [InteractionOverride] = []) -> FilterState {
        var s = FilterState()
        s.drillFilters["tree"] = [ColumnValues(column: product, values: [.string("Bank account or service")])]
        if selectedOnly { s.drillSelectedOnly.insert("tree") }
        s.overrides = overrides
        return s
    }

    private func expressions(_ target: InteractionTarget, _ state: FilterState) -> [String] {
        FilterTranslator.assemble(for: target, staticFilters: [], state: state).filters.map(\.tableExpression)
    }

    @Test func entirePageFiltersOtherVisualsByTheDrillPath() {
        let out = expressions(other, state())
        #expect(out.contains { $0.contains("TREATAS") && $0.contains("Bank account or service") && $0.contains("product") })
    }

    @Test func selectedVisualOnlyDoesNotTouchOtherVisuals() {
        #expect(expressions(other, state(selectedOnly: true)).isEmpty)
    }

    @Test func theDrilledVisualStillFiltersItselfInBothScopes() {
        let own = FilterTranslator.assemble(for: source, staticFilters: [], state: state()).filters
        let ownSelected = FilterTranslator.assemble(for: source, staticFilters: [], state: state(selectedOnly: true)).filters
        #expect(own.count == 1 && ownSelected.count == 1)
        #expect(own.map(\.tableExpression) == ownSelected.map(\.tableExpression))
    }

    @Test func aNoFilterOverrideExcludesTheTarget() {
        let none = InteractionOverride(sourceID: "tree", targetID: "kpi", effect: .none)
        #expect(expressions(other, state(overrides: [none])).isEmpty)
    }

    @Test func slicersNeverReceiveDrillFilters() {
        let slicer = InteractionTarget(visualID: "s1", visualType: "slicer")
        #expect(expressions(slicer, state()).isEmpty)
    }
}

/// Treemap drill (VM 2026-11-23): sau khi xuống cấp chỉ vẽ cấp con (như donut); chart giữ các cấp lồng nhau.
@Suite("Drill spec per shape")
struct DrillSpecShapeTests {
    private func level(_ ref: String, _ column: String) -> GroupField {
        GroupField(field: FieldInfo(queryRef: ref, displayName: column, role: "Group", isMeasure: false),
                   column: QueryColumn(table: "T", column: column), sortBy: nil)
    }

    @Test func treemapDrillShowsOnlyTheChildLevel() {
        var spec = VisualQuerySpec(visualID: "t", visualType: "treemap")
        spec.shape = .treemap
        spec.drillLevels = [level("T.product", "product"), level("T.sub", "sub")]
        spec.primary = [spec.drillLevels[0]]
        VisualQuerySpecReader.applyDrill(&spec, depth: 1)
        #expect(spec.primary.map(\.column.column) == ["sub"])
    }

    @Test func chartDrillKeepsNestedLevels() {
        var spec = VisualQuerySpec(visualID: "c", visualType: "clusteredColumnChart")
        spec.shape = .chart
        spec.drillLevels = [level("T.year", "year"), level("T.quarter", "quarter")]
        spec.primary = [spec.drillLevels[0]]
        VisualQuerySpecReader.applyDrill(&spec, depth: 1)
        #expect(spec.primary.map(\.column.column) == ["year", "quarter"])
    }
}
