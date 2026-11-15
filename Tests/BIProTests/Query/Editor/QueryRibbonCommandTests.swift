import Testing
import ColumnStore
import MEngine
@testable import BIPro

@Suite struct QueryRibbonCommandTests {
    @Test func testRemoveColumns() {
        let cmd = QueryRibbonCommand.removeColumns
        #expect(cmd.tab == .home)
        #expect(cmd.isAvailable)

        // Missing input
        let emptyCtx = QueryRibbonContext(selectedColumns: [])
        #expect(cmd.stepCommand(context: emptyCtx) == nil)
        #expect(!cmd.isEnabled(context: emptyCtx))

        // Valid input
        let validCtx = QueryRibbonContext(selectedColumns: ["Region", "Qty"])
        #expect(cmd.stepCommand(context: validCtx) == .removeColumns(["Region", "Qty"]))
        #expect(cmd.isEnabled(context: validCtx))
    }

    @Test func testSortRows() {
        let asc = QueryRibbonCommand.sortAscending
        let desc = QueryRibbonCommand.sortDescending
        #expect(asc.tab == .home && desc.tab == .home)

        // Missing input
        let emptyCtx = QueryRibbonContext(selectedColumns: [])
        #expect(asc.stepCommand(context: emptyCtx) == nil)
        #expect(desc.stepCommand(context: emptyCtx) == nil)
        #expect(!asc.isEnabled(context: emptyCtx))
        #expect(!desc.isEnabled(context: emptyCtx))

        // Valid input
        let validCtx = QueryRibbonContext(selectedColumns: ["Region", "Qty"])
        #expect(asc.stepCommand(context: validCtx) == .sortRows([
            SortKey(column: "Region", descending: false),
            SortKey(column: "Qty", descending: false)
        ]))
        #expect(desc.stepCommand(context: validCtx) == .sortRows([
            SortKey(column: "Region", descending: true),
            SortKey(column: "Qty", descending: true)
        ]))
        #expect(asc.isEnabled(context: validCtx))
        #expect(desc.isEnabled(context: validCtx))
    }

    @Test func testKeepAndRemoveTopRows() {
        let keep = QueryRibbonCommand.keepTopRows
        let remove = QueryRibbonCommand.removeTopRows

        // Missing input
        let emptyCtx = QueryRibbonContext(rowCount: nil)
        #expect(keep.stepCommand(context: emptyCtx) == nil)
        #expect(remove.stepCommand(context: emptyCtx) == nil)

        let zeroCtx = QueryRibbonContext(rowCount: 0)
        #expect(keep.stepCommand(context: zeroCtx) == nil)
        #expect(remove.stepCommand(context: zeroCtx) == nil)

        // Valid input
        let validCtx = QueryRibbonContext(rowCount: 100)
        #expect(keep.stepCommand(context: validCtx) == .keepTopRows(100))
        #expect(remove.stepCommand(context: validCtx) == .removeTopRows(100))
    }

    @Test func testRemoveDuplicates() {
        let cmd = QueryRibbonCommand.removeDuplicates

        // Missing input
        let emptyCtx = QueryRibbonContext(selectedColumns: [])
        #expect(cmd.stepCommand(context: emptyCtx) == nil)
        #expect(!cmd.isEnabled(context: emptyCtx))

        // Valid input
        let validCtx = QueryRibbonContext(selectedColumns: ["Region"])
        #expect(cmd.stepCommand(context: validCtx) == .removeDuplicates(["Region"]))
        #expect(cmd.isEnabled(context: validCtx))
    }

    @Test func testPromoteHeaders() {
        let cmd = QueryRibbonCommand.promoteHeaders
        let ctx = QueryRibbonContext()
        #expect(cmd.stepCommand(context: ctx) == .promoteHeaders)
        #expect(cmd.isEnabled(context: ctx))
    }

    @Test func testChangeTypes() {
        let validCtx = QueryRibbonContext(selectedColumns: ["Qty"])
        let emptyCtx = QueryRibbonContext(selectedColumns: [])

        #expect(QueryRibbonCommand.changeTypeWholeNumber.stepCommand(context: validCtx) ==
            .changeType([ColumnTypeChange(column: "Qty", type: .wholeNumber)]))
        #expect(QueryRibbonCommand.changeTypeWholeNumber.stepCommand(context: emptyCtx) == nil)

        #expect(QueryRibbonCommand.changeTypeDecimal.stepCommand(context: validCtx) ==
            .changeType([ColumnTypeChange(column: "Qty", type: .decimal)]))
        #expect(QueryRibbonCommand.changeTypeDecimal.stepCommand(context: emptyCtx) == nil)

        #expect(QueryRibbonCommand.changeTypeText.stepCommand(context: validCtx) ==
            .changeType([ColumnTypeChange(column: "Qty", type: .text)]))
        #expect(QueryRibbonCommand.changeTypeText.stepCommand(context: emptyCtx) == nil)

        #expect(QueryRibbonCommand.changeTypeDate.stepCommand(context: validCtx) ==
            .changeType([ColumnTypeChange(column: "Qty", type: .date)]))
        #expect(QueryRibbonCommand.changeTypeDate.stepCommand(context: emptyCtx) == nil)

        #expect(QueryRibbonCommand.changeTypeDateTime.stepCommand(context: validCtx) ==
            .changeType([ColumnTypeChange(column: "Qty", type: .dateTime)]))
        #expect(QueryRibbonCommand.changeTypeDateTime.stepCommand(context: emptyCtx) == nil)

        #expect(QueryRibbonCommand.changeTypeLogical.stepCommand(context: validCtx) ==
            .changeType([ColumnTypeChange(column: "Qty", type: .logical)]))
        #expect(QueryRibbonCommand.changeTypeLogical.stepCommand(context: emptyCtx) == nil)
    }

    @Test func testReplaceValue() {
        let cmd = QueryRibbonCommand.replaceValue

        // Missing column
        let noColCtx = QueryRibbonContext(selectedColumns: [], replaceOld: "North", replaceNew: "Bac")
        #expect(cmd.stepCommand(context: noColCtx) == nil)
        #expect(!cmd.isEnabled(context: noColCtx))

        // Missing old/new
        let missingParamCtx = QueryRibbonContext(selectedColumns: ["Region"], replaceOld: nil, replaceNew: "Bac")
        #expect(cmd.stepCommand(context: missingParamCtx) == nil)

        // Valid
        let validCtx = QueryRibbonContext(selectedColumns: ["Region"], replaceOld: "North", replaceNew: "Bac")
        #expect(cmd.stepCommand(context: validCtx) == .replaceValue(old: .text("North"), new: .text("Bac"), columns: ["Region"]))
        #expect(cmd.isEnabled(context: validCtx))
    }

    @Test func testFilterEquals() {
        let cmd = QueryRibbonCommand.filterEquals

        // Missing column
        let noColCtx = QueryRibbonContext(selectedColumns: [], filterValues: [.number(1)])
        #expect(cmd.stepCommand(context: noColCtx) == nil)
        #expect(!cmd.isEnabled(context: noColCtx))

        // Multiple columns selected (only exactly 1 is allowed)
        let multiColCtx = QueryRibbonContext(selectedColumns: ["A", "B"], filterValues: [.number(1)])
        #expect(cmd.stepCommand(context: multiColCtx) == nil)
        #expect(!cmd.isEnabled(context: multiColCtx))

        // Missing values
        let noValCtx = QueryRibbonContext(selectedColumns: ["Qty"], filterValues: nil)
        #expect(cmd.stepCommand(context: noValCtx) == nil)

        // Valid
        let validCtx = QueryRibbonContext(selectedColumns: ["Qty"], filterValues: [.number(1), .number(2)])
        #expect(cmd.stepCommand(context: validCtx) == .filterEquals(column: "Qty", values: [.number(1), .number(2)]))
        #expect(cmd.isEnabled(context: validCtx))
    }

    @Test func testReverseRows() {
        let cmd = QueryRibbonCommand.reverseRows
        #expect(cmd.tab == .transform)
        let ctx = QueryRibbonContext()
        #expect(cmd.stepCommand(context: ctx) == .reverseRows)
        #expect(cmd.isEnabled(context: ctx))
    }

    @Test func testFill() {
        let down = QueryRibbonCommand.fillDown
        let up = QueryRibbonCommand.fillUp
        #expect(down.tab == .transform && up.tab == .transform)

        // Missing column
        let emptyCtx = QueryRibbonContext(selectedColumns: [])
        #expect(down.stepCommand(context: emptyCtx) == nil)
        #expect(up.stepCommand(context: emptyCtx) == nil)
        #expect(!down.isEnabled(context: emptyCtx))
        #expect(!up.isEnabled(context: emptyCtx))

        // Valid
        let validCtx = QueryRibbonContext(selectedColumns: ["Region"])
        #expect(down.stepCommand(context: validCtx) == .fillDown(["Region"]))
        #expect(up.stepCommand(context: validCtx) == .fillUp(["Region"]))
        #expect(down.isEnabled(context: validCtx))
        #expect(up.isEnabled(context: validCtx))
    }

    @Test func testTextFormats() {
        let lower = QueryRibbonCommand.formatLowercase
        let upper = QueryRibbonCommand.formatUppercase
        let cap = QueryRibbonCommand.formatCapitalizeEachWord
        let trim = QueryRibbonCommand.formatTrim
        let clean = QueryRibbonCommand.formatClean

        // Non-string column -> nil
        let intCtx = QueryRibbonContext(selectedColumns: ["Qty"], columnTypes: ["Qty": .integer])
        #expect(lower.stepCommand(context: intCtx) == nil)
        #expect(upper.stepCommand(context: intCtx) == nil)
        #expect(!lower.isEnabled(context: intCtx))

        // Empty selected columns -> nil
        let emptyCtx = QueryRibbonContext(selectedColumns: [])
        #expect(lower.stepCommand(context: emptyCtx) == nil)

        // Valid string column
        let strCtx = QueryRibbonContext(selectedColumns: ["Product"], columnTypes: ["Product": .string])
        #expect(lower.stepCommand(context: strCtx) == .format(.lowercase, columns: ["Product"]))
        #expect(upper.stepCommand(context: strCtx) == .format(.uppercase, columns: ["Product"]))
        #expect(cap.stepCommand(context: strCtx) == .format(.capitalizeEachWord, columns: ["Product"]))
        #expect(trim.stepCommand(context: strCtx) == .format(.trim, columns: ["Product"]))
        #expect(clean.stepCommand(context: strCtx) == .format(.clean, columns: ["Product"]))
        #expect(lower.isEnabled(context: strCtx))
    }

    @Test func testSplitByDelimiter() {
        let cmd = QueryRibbonCommand.splitByDelimiter
        #expect(cmd.tab == .transform)

        // Valid string column with space delimiter and 2 columns
        let validCtx = QueryRibbonContext(
            selectedColumns: ["Vung"],
            columnTypes: ["Vung": .string],
            delimiter: " ",
            splitColumnCount: 2
        )
        #expect(cmd.stepCommand(context: validCtx) == .splitByDelimiter(column: "Vung", delimiter: " ", into: ["Vung.1", "Vung.2"]))
        #expect(cmd.isEnabled(context: validCtx))

        // On integer column -> nil
        let intCtx = QueryRibbonContext(
            selectedColumns: ["Qty"],
            columnTypes: ["Qty": .integer],
            delimiter: " ",
            splitColumnCount: 2
        )
        #expect(cmd.stepCommand(context: intCtx) == nil)
        #expect(!cmd.isEnabled(context: intCtx))

        // Empty delimiter -> nil
        let emptyDelimCtx = QueryRibbonContext(
            selectedColumns: ["Vung"],
            columnTypes: ["Vung": .string],
            delimiter: "",
            splitColumnCount: 2
        )
        #expect(cmd.stepCommand(context: emptyDelimCtx) == nil)

        // Column count < 2 -> nil
        let invalidCountCtx = QueryRibbonContext(
            selectedColumns: ["Vung"],
            columnTypes: ["Vung": .string],
            delimiter: " ",
            splitColumnCount: 1
        )
        #expect(cmd.stepCommand(context: invalidCountCtx) == nil)
    }

    @Test func testUnavailableCommands() {
        let groupBy = QueryRibbonCommand.groupByCount
        let unpivot = QueryRibbonCommand.unpivotOtherColumns
        let pivot = QueryRibbonCommand.pivot

        #expect(!groupBy.isAvailable)
        #expect(!unpivot.isAvailable)
        #expect(!pivot.isAvailable)

        let ctx = QueryRibbonContext(selectedColumns: ["Product", "Value"])
        #expect(!groupBy.isEnabled(context: ctx))
        #expect(!unpivot.isEnabled(context: ctx))
        #expect(!pivot.isEnabled(context: ctx))
    }

    @Test func testAddIndexColumn() {
        let from0 = QueryRibbonCommand.addIndexColumnFrom0
        let from1 = QueryRibbonCommand.addIndexColumnFrom1
        #expect(from0.tab == .addColumn && from1.tab == .addColumn)

        let ctx = QueryRibbonContext()
        #expect(from0.stepCommand(context: ctx) == .addIndexColumn(start: 0, step: 1))
        #expect(from1.stepCommand(context: ctx) == .addIndexColumn(start: 1, step: 1))
        #expect(from0.isEnabled(context: ctx))
        #expect(from1.isEnabled(context: ctx))
    }

    @Test func testAddCustomColumn() {
        let cmd = QueryRibbonCommand.addCustomColumn
        #expect(cmd.tab == .addColumn)

        // Valid
        let validCtx = QueryRibbonContext(customColumnName: "Custom", customColumnFormula: "[Qty] * 2")
        #expect(cmd.stepCommand(context: validCtx) == .addCustomColumn(name: "Custom", formula: "[Qty] * 2"))

        // Empty name -> nil
        let emptyNameCtx = QueryRibbonContext(customColumnName: "   ", customColumnFormula: "[Qty] * 2")
        #expect(cmd.stepCommand(context: emptyNameCtx) == nil)

        // Empty formula -> nil
        let emptyFormulaCtx = QueryRibbonContext(customColumnName: "Custom", customColumnFormula: "")
        #expect(cmd.stepCommand(context: emptyFormulaCtx) == nil)
    }
}
