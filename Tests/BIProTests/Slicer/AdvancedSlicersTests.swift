import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite("US3 — Advanced Slicers & FilterTranslator Range/Text")
struct AdvancedSlicersTests {

    @Test("FilterTranslator generates numeric and date range predicates for SlicerRange")
    func rangeFilterTranslation() {
        let numCol = QueryColumn(table: "Dim_Client", column: "birth_year")
        var state = FilterState(slicerOrder: ["s1"])
        state.setSlicer(visualID: "s1", columns: [numCol], selection: SlicerSelection(range: SlicerRange(min: .integer(1970), max: .integer(1995))))

        let assembled = FilterTranslator.assemble(
            for: InteractionTarget(visualID: "v1", visualType: "card"),
            staticFilters: [],
            state: state
        )
        #expect(assembled.filters.count == 1)
        let expr = assembled.filters[0].tableExpression
        #expect(expr.contains("'Dim_Client'[birth_year] >= 1970"))
        #expect(expr.contains("'Dim_Client'[birth_year] <= 1995"))
        #expect(expr.contains("AND("))
    }

    @Test("FilterTranslator generates CONTAINSSTRING predicate for textSlicer")
    func textSlicerFilterTranslation() {
        let col = QueryColumn(table: "Dim_District", column: "region")
        var state = FilterState(slicerOrder: ["s2"])
        state.setSlicer(visualID: "s2", columns: [col], selection: SlicerSelection(searchText: "North"))

        let assembled = FilterTranslator.assemble(
            for: InteractionTarget(visualID: "v1", visualType: "card"),
            staticFilters: [],
            state: state
        )
        #expect(assembled.filters.count == 1)
        #expect(assembled.filters[0].tableExpression.contains(#"CONTAINSSTRING('Dim_District'[region], "North")"#))
    }

    @Test("Slicer targets do not self-filter across advancedSlicerVisual, listSlicer, textSlicer")
    func slicerTargetsIsolated() {
        let col = QueryColumn(table: "Sales", column: "Region")
        var state = FilterState(slicerOrder: ["s1"])
        state.setSlicer(visualID: "s1", columns: [col], selection: SlicerSelection(searchText: "East"))

        for slicerType in ["slicer", "advancedSlicerVisual", "listSlicer", "textSlicer"] {
            let assembled = FilterTranslator.assemble(
                for: InteractionTarget(visualID: "s2", visualType: slicerType),
                staticFilters: [],
                state: state
            )
            #expect(assembled.filters.isEmpty)
        }
    }

    @MainActor
    @Test("Tile, List, Text, and Range slicers render cleanly in export mode")
    func renderAdvancedSlicers() {
        let level = FieldInfo(queryRef: "Sales.Region", displayName: "Region", role: "Values", formatString: nil, isMeasure: false)
        let data = SlicerData(
            levels: [level],
            roots: [SlicerNode(.string("North")), SlicerNode(.string("South")), SlicerNode(.string("East"))],
            domainRange: SlicerRange(min: .integer(1960), max: .integer(2005)),
            isDateColumn: false
        )
        let ctx = VisualRenderContext(
            theme: ReportTheme.fallback,
            format: VisualFormat(objects: ObjectProperties(nil)),
            selection: [],
            slicerSelection: SlicerSelection([[.string("North")]]),
            actions: .none,
            visualSize: CGSize(width: 280, height: 180),
            isExporting: true
        )

        let views: [AnyView] = [
            AnyView(TileSlicerView(data: data, context: ctx, scrollable: false)),
            AnyView(ListSlicerView(data: data, context: ctx, scrollable: false)),
            AnyView(TextSlicerView(data: data, context: ctx, interactive: false)),
            AnyView(RangeSlicerView(data: data, context: ctx, interactive: false)),
        ]
        for view in views {
            let renderer = ImageRenderer(content: view.frame(width: 280, height: 180).background(Color.white))
            renderer.scale = 1
            let cg = renderer.cgImage
            #expect(cg != nil)
            #expect((cg?.width ?? 0) > 0 && (cg?.height ?? 0) > 0)
        }
    }
}
