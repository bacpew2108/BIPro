import DAXEngine
import Foundation
import Testing
@testable import BIPro

@Suite("Behavior Interaction Tests")
struct BehaviorInteractionTests {
    // 8. literal: ít nhất 8 ca (số nguyên, chuỗi có dấu nháy, bool, blank, double, currency, ngày không giờ, ngày có giờ)
    @Test func testLiterals() {
        // 1. Số nguyên
        #expect(FilterTranslator.literal(.integer(2016)) == "2016")
        #expect(FilterTranslator.literal(.integer(-42)) == "-42")

        // 2. Chuỗi có dấu nháy
        #expect(FilterTranslator.literal(.string("a\"b")) == "\"a\"\"b\"")
        #expect(FilterTranslator.literal(.string("plain text")) == "\"plain text\"")

        // 3. Boolean
        #expect(FilterTranslator.literal(.boolean(true)) == "TRUE")
        #expect(FilterTranslator.literal(.boolean(false)) == "FALSE")

        // 4. Blank
        #expect(FilterTranslator.literal(.blank) == "BLANK()")

        // 5. Double: ngắn nhất đọc được, không có e với số thường
        #expect(FilterTranslator.literal(.double(123.45)) == "123.45")
        #expect(FilterTranslator.literal(.double(2016.0)) == "2016")
        #expect(FilterTranslator.literal(.double(0.5)) == "0.5")

        // 6. Currency: n / 10000
        #expect(FilterTranslator.literal(.currency(1234500)) == "123.45")
        #expect(FilterTranslator.literal(.currency(10000)) == "1")
        #expect(FilterTranslator.literal(.currency(-5000)) == "-0.5")

        // 7. Ngày không giờ (2016-01-01, OLE 42370.0 UTC)
        #expect(FilterTranslator.literal(.dateTime(42370.0)) == "DATE(2016, 1, 1)")

        // 8. Ngày có giờ (2016-01-01 12:30:45 UTC, OLE 42370 + 45045/86400)
        let fractionalDay = (12.0 * 3600.0 + 30.0 * 60.0 + 45.0) / 86400.0
        #expect(FilterTranslator.literal(.dateTime(42370.0 + fractionalDay)) == "DATETIME(2016, 1, 1, 12, 30, 45)")
    }

    // 9. Sắp xếp giá trị: tập hỗn hợp số/chuỗi/blank cho ra thứ tự đúng
    @Test func testValueSorting() {
        let values: [Value] = [
            .string("zebra"),
            .integer(10),
            .blank,
            .double(2.5),
            .string("apple"),
            .integer(1),
            .currency(50000), // 5.0
            .boolean(true)
        ]

        let sorted = values.sorted(by: FilterTranslator.valuePrecedes)

        // BLANK đứng đầu, số theo số, bool, chuỗi theo từ điển
        #expect(sorted[0] == .blank)
        #expect(sorted[1] == .integer(1))
        #expect(sorted[2] == .double(2.5))
        #expect(sorted[3] == .currency(50000))
        #expect(sorted[4] == .integer(10))
        #expect(sorted[5] == .boolean(true))
        #expect(sorted[6] == .string("apple"))
        #expect(sorted[7] == .string("zebra"))
    }

    // 10. Slicer: selection rỗng → không có bảng lọc; cột chưa có bộ lọc tĩnh → bảng thuộc nhóm tương tác;
    // hai slicer theo slicerOrder; slicer không tự lọc chính nó.
    @Test func testSlicerRules() {
        let colA = QueryColumn(table: "T", column: "colA")
        let colB = QueryColumn(table: "T", column: "colB")
        let colStatic = QueryColumn(table: "T", column: "colStatic")

        let visualFilter = StaticFilter(column: colStatic, predicate: "colStatic = 1", scope: .visual)
        let pageFilter = StaticFilter(column: colStatic, predicate: "colStatic = 2", scope: .page)

        var state = FilterState()
        // Slicer 1 rỗng
        state.setSlicer(visualID: "slicer_empty", columns: [colA], selection: SlicerSelection([]))
        // Slicer 2 và 3 có dữ liệu
        state.setSlicer(visualID: "slicer_B", columns: [colB], selection: SlicerSelection([[.string("valB")]]))
        state.setSlicer(visualID: "slicer_A", columns: [colA], selection: SlicerSelection([[.string("valA")]]))
        state.slicerOrder = ["slicer_A", "slicer_B"]

        let target = InteractionTarget(visualID: "chart1", visualType: "clusteredColumnChart")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: [visualFilter, pageFilter], state: state)

        // filters gồm: visualFilter, rồi nhóm tương tác (slicer_A, slicer_B), rồi pageFilter
        #expect(assembled.filters.count == 4)
        #expect(assembled.filters[0].tableExpression.contains("colStatic = 1"))
        #expect(assembled.filters[1].tableExpression.contains("valA")) // slicer_A trước do slicerOrder
        #expect(assembled.filters[2].tableExpression.contains("valB")) // slicer_B sau
        #expect(assembled.filters[3].tableExpression.contains("colStatic = 2"))

        // Đích chính là slicer_A → không tự lọc chính nó
        let slicerATarget = InteractionTarget(visualID: "slicer_A", visualType: "slicer")
        let slicerAAssembled = FilterTranslator.assemble(for: slicerATarget, staticFilters: [visualFilter, pageFilter], state: state)
        // Slicer target chỉ nhận bộ lọc tĩnh
        #expect(slicerAAssembled.filters.count == 2)
        #expect(!slicerAAssembled.filters.contains(where: { $0.tableExpression.contains("valA") }))
    }

    // 11. Slicer phân cấp: đường dẫn hỗn hợp độ dài 1 và 2 cho OR(…); một cột bị lọc tĩnh thì gộp, đứng trước.
    @Test func testHierarchicalSlicerMixedLengths() {
        let colY = QueryColumn(table: "Dim_Date", column: "year")
        let colQ = QueryColumn(table: "Dim_Date", column: "quarter_name")

        let staticYear = StaticFilter(column: colY, predicate: "NOT('Dim_Date'[year] IN {9999})", scope: .report)

        var state = FilterState()
        state.setSlicer(
            visualID: "slicer_hier",
            columns: [colY, colQ],
            selection: SlicerSelection([[.integer(2016)], [.integer(2017), .string("Q1")]])
        )

        let target = InteractionTarget(visualID: "card1", visualType: "card")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: [staticYear], state: state)

        #expect(assembled.filters.count == 1)
        let expr = assembled.filters[0].tableExpression
        #expect(expr.contains("SUMMARIZE(VALUES('Dim_Date'), 'Dim_Date'[year], 'Dim_Date'[quarter_name])"))
        // Vị từ tĩnh đứng trước
        #expect(expr.contains("AND(NOT('Dim_Date'[year] IN {9999}), OR('Dim_Date'[year] IN {2016}, ('Dim_Date'[year], 'Dim_Date'[quarter_name]) IN {(2017, \"Q1\")})))"))
    }

    // 12. Nhiều điểm lọc chéo cùng cột → {a, b}; nhiều cột → tuple; nguồn không phải là đích
    @Test func testCrossFilterMultiPointMultiColumn() {
        let colCat = QueryColumn(table: "Fact", column: "category")
        let colSeries = QueryColumn(table: "Fact", column: "series")

        // Ca 1 cột, nhiều điểm
        var state1 = FilterState()
        let source = InteractionTarget(visualID: "chart_src", visualType: "clusteredBarChart")
        let crossCol1 = CrossColumn(queryRef: "Fact.category", column: colCat)
        state1.selection.select(DataPointID(["Fact.category": .string("CatB")]), additive: false, from: source, columns: [crossCol1])
        state1.selection.select(DataPointID(["Fact.category": .string("CatA")]), additive: true, from: source, columns: [crossCol1])

        let target = InteractionTarget(visualID: "card_tgt", visualType: "card")
        let assembled1 = FilterTranslator.assemble(for: target, staticFilters: [], state: state1)
        #expect(assembled1.filters.count == 1)
        #expect(assembled1.filters[0].tableExpression == "TREATAS({\"CatA\", \"CatB\"}, 'Fact'[category])")

        // Ca nhiều cột: category và series
        var state2 = FilterState()
        let crossCols = [crossCol1, CrossColumn(queryRef: "Fact.series", column: colSeries)]
        state2.selection.select(
            DataPointID(["Fact.category": .string("CatA"), "Fact.series": .integer(1)]),
            additive: false,
            from: source,
            columns: crossCols
        )
        state2.selection.select(
            DataPointID(["Fact.category": .string("CatB"), "Fact.series": .integer(2)]),
            additive: true,
            from: source,
            columns: crossCols
        )

        let assembled2 = FilterTranslator.assemble(for: target, staticFilters: [], state: state2)
        #expect(assembled2.filters.count == 1)
        #expect(assembled2.filters[0].tableExpression == "TREATAS({(\"CatA\", 1), (\"CatB\", 2)}, 'Fact'[category], 'Fact'[series])")

        // Nguồn chính là đích → không lọc
        let assembledSelf = FilterTranslator.assemble(for: source, staticFilters: [], state: state2)
        #expect(assembledSelf.filters.isEmpty)
        #expect(assembledSelf.highlight == nil)
    }

    // 13. Thứ tự filters đủ bốn nhóm (visual, tương tác, page, report) trong một ca
    @Test func testFilterOrderingAllFourGroups() {
        let colV = QueryColumn(table: "T", column: "colV")
        let colP = QueryColumn(table: "T", column: "colP")
        let colR = QueryColumn(table: "T", column: "colR")
        let colDT = QueryColumn(table: "T", column: "colDT")
        let colXF = QueryColumn(table: "T", column: "colXF")
        let colSl = QueryColumn(table: "T", column: "colSl")

        let staticFilters = [
            StaticFilter(column: colV, predicate: "colV = 1", scope: .visual),
            StaticFilter(column: colP, predicate: "colP = 2", scope: .page),
            StaticFilter(column: colR, predicate: "colR = 3", scope: .report)
        ]

        var state = FilterState()
        state.drillthrough = [ColumnValues(column: colDT, values: [.string("DT_Val")])]
        let source = InteractionTarget(visualID: "src", visualType: "clusteredBarChart")
        state.selection.select(
            DataPointID(["T.colXF": .string("XF_Val")]),
            additive: false,
            from: source,
            columns: [CrossColumn(queryRef: "T.colXF", column: colXF)]
        )
        state.setSlicer(visualID: "slicer1", columns: [colSl], selection: SlicerSelection([[.string("SL_Val")]]))

        let target = InteractionTarget(visualID: "tgt", visualType: "card")
        let assembled = FilterTranslator.assemble(for: target, staticFilters: staticFilters, state: state)

        #expect(assembled.filters.count == 6)
        // 1. Visual
        #expect(assembled.filters[0].tableExpression.contains("colV = 1"))
        // 2. Nhóm tương tác: drillthrough, rồi lọc chéo, rồi slicer chưa gộp
        #expect(assembled.filters[1].tableExpression == "TREATAS({\"DT_Val\"}, 'T'[colDT])")
        #expect(assembled.filters[2].tableExpression == "TREATAS({\"XF_Val\"}, 'T'[colXF])")
        #expect(assembled.filters[3].tableExpression == "FILTER(KEEPFILTERS(VALUES('T'[colSl])), 'T'[colSl] IN {\"SL_Val\"})")
        // 3. Page
        #expect(assembled.filters[4].tableExpression.contains("colP = 2"))
        // 4. Report
        #expect(assembled.filters[5].tableExpression.contains("colR = 3"))
    }

    // 14. SelectionState: mọi nhánh của quy tắc select
    @Test func testSelectionStateRules() {
        var state = SelectionState()
        let src1 = InteractionTarget(visualID: "v1", visualType: "clusteredBarChart")
        let src2 = InteractionTarget(visualID: "v2", visualType: "clusteredBarChart")
        let cols = [CrossColumn(queryRef: "ref1", column: QueryColumn(table: "T", column: "c1"))]

        let ptA = DataPointID(["ref1": .integer(1)])
        let ptB = DataPointID(["ref1": .integer(2)])
        let ptC = DataPointID(["ref1": .integer(3)])

        // 1. Chọn mới
        state.select(ptA, additive: false, from: src1, columns: cols)
        #expect(state.sourceVisualID == "v1")
        #expect(state.points == [ptA])
        #expect(state.points(forVisual: "v1") == [ptA])
        #expect(state.points(forVisual: "v2").isEmpty)

        // 2. Bỏ chọn điểm duy nhất (nhấn thường cùng visual)
        state.select(ptA, additive: false, from: src1, columns: cols)
        #expect(state.sourceVisualID == nil)
        #expect(state.points.isEmpty)

        // 3. Chọn mới điểm khác
        state.select(ptA, additive: false, from: src1, columns: cols)
        // Nhấn kèm Ctrl thêm điểm B, C
        state.select(ptB, additive: true, from: src1, columns: cols)
        state.select(ptC, additive: true, from: src1, columns: cols)
        #expect(state.points == [ptA, ptB, ptC])

        // 4. Chọn lại giữa nhiều điểm (nhấn thường vào ptB) → chỉ giữ ptB
        state.select(ptB, additive: false, from: src1, columns: cols)
        #expect(state.points == [ptB])

        // 5. Ctrl bớt điểm duy nhất → tập rỗng xoá nguồn
        state.select(ptB, additive: true, from: src1, columns: cols)
        #expect(state.sourceVisualID == nil)
        #expect(state.points.isEmpty)

        // 6. Ctrl từ visual khác → thay thế như nhấn thường
        state.select(ptA, additive: false, from: src1, columns: cols)
        state.select(ptC, additive: true, from: src2, columns: cols)
        #expect(state.sourceVisualID == "v2")
        #expect(state.points == [ptC])

        // 7. Bấm trống (point == nil) → xoá lựa chọn
        state.select(nil, additive: false, from: src2, columns: cols)
        #expect(state.sourceVisualID == nil)
        #expect(state.points.isEmpty)
    }

    // 15. InteractionRules.effect: bảng đầy đủ nguồn × đích cho các visualType của Nhom6
    @Test func testInteractionRulesEffectMatrix() {
        let types = [
            "clusteredBarChart", "clusteredColumnChart", "stackedColumnChart",
            "hundredPercentStackedColumnChart", "lineChart",
            "lineClusteredColumnComboChart", "lineStackedColumnComboChart",
            "donutChart", "treemap", "shapeMap", "card", "slicer", "pivotTable", "textbox"
        ]

        for srcType in types {
            for tgtType in types {
                let src = InteractionTarget(visualID: "src_\(srcType)", visualType: srcType)
                let tgt = InteractionTarget(visualID: "tgt_\(tgtType)", visualType: tgtType)
                let effect = InteractionRules.effect(of: src, on: tgt)

                if !InteractionRules.canSelect(visualType: srcType) {
                    // Nguồn không thể phát lựa chọn
                    #expect(effect == .none)
                } else if ["slicer", "textbox"].contains(tgtType) {
                    #expect(effect == .none)
                } else if InteractionRules.supportsHighlight(visualType: tgtType) {
                    #expect(effect == .highlight)
                } else {
                    #expect(effect == .filter)
                }
            }
        }

        // Tự lọc bản thân → .none
        let same = InteractionTarget(visualID: "same_id", visualType: "clusteredBarChart")
        #expect(InteractionRules.effect(of: same, on: same) == .none)

        // Ghi đè:
        let src = InteractionTarget(visualID: "src1", visualType: "clusteredBarChart")
        let tgtCard = InteractionTarget(visualID: "tgt1", visualType: "card")
        let tgtDonut = InteractionTarget(visualID: "tgt2", visualType: "donutChart")

        // Ghi đè .none
        let ovNone = InteractionOverride(sourceID: "src1", targetID: "tgt1", effect: .none)
        #expect(InteractionRules.effect(of: src, on: tgtCard, overrides: [ovNone]) == .none)

        // Ghi đè .filter lên donut
        let ovFilter = InteractionOverride(sourceID: "src1", targetID: "tgt2", effect: .filter)
        #expect(InteractionRules.effect(of: src, on: tgtDonut, overrides: [ovFilter]) == .filter)

        // Ghi đè .highlight lên card (không supportsHighlight) → thành .filter
        let ovHighlight = InteractionOverride(sourceID: "src1", targetID: "tgt1", effect: .highlight)
        #expect(InteractionRules.effect(of: src, on: tgtCard, overrides: [ovHighlight]) == .filter)
    }

    // 16. assemble là hàm thuần: gọi hai lần với cùng đầu vào cho cùng kết quả, FilterState không bị đổi
    @Test func testAssembleIsPureFunction() {
        let col = QueryColumn(table: "Dim", column: "col")
        let staticFilters = [StaticFilter(column: col, predicate: "col > 0", scope: .page)]

        var state = FilterState()
        state.drillthrough = [ColumnValues(column: col, values: [.integer(10)])]
        state.setSlicer(visualID: "sl1", columns: [col], selection: SlicerSelection([[.integer(5)]]))

        let stateCopy = state
        let target = InteractionTarget(visualID: "v1", visualType: "card")

        let res1 = FilterTranslator.assemble(for: target, staticFilters: staticFilters, state: state)
        let res2 = FilterTranslator.assemble(for: target, staticFilters: staticFilters, state: state)

        #expect(res1 == res2)
        #expect(state == stateCopy)
    }
}
