import Foundation
import Testing
import ColumnStore
import MEngine
@testable import BIPro

@Suite struct DialogModelsTests {

    // MARK: - MergeDialogModel Tests

    @Test func testMergeDialogModelKeysAndValidation() {
        let leftCols = [
            QueryColumnInfo(name: "ID", type: .integer),
            QueryColumnInfo(name: "Name", type: .string),
            QueryColumnInfo(name: "Code", type: .string)
        ]
        let rightCols = [
            QueryColumnInfo(name: "CustID", type: .integer),
            QueryColumnInfo(name: "Amount", type: .double)
        ]

        var model = MergeDialogModel(
            primaryQueryName: "Customers",
            leftColumns: leftCols
        )
        model.rightColumns = rightCols

        // Initial state: no second query selected
        #expect(!model.isValid)
        #expect(model.statusLevel == .info)
        #expect(model.statusMessage == "Chọn bảng thứ hai và cột khớp ở cả hai bảng.")
        #expect(model.command() == nil)

        // Select second query
        model.secondQuery = "Orders"
        #expect(!model.isValid)
        #expect(model.statusMessage == "Chọn bảng thứ hai và cột khớp ở cả hai bảng.")

        // Toggle left key: ID
        model.toggleLeft("ID")
        #expect(model.leftKeys == ["ID"])
        #expect(!model.isValid)
        #expect(model.statusMessage == "Số cột khoá hai bên phải bằng nhau (trái 1, phải 0).")

        // Toggle left key: Code
        model.toggleLeft("Code")
        #expect(model.leftKeys == ["ID", "Code"])
        #expect(model.statusMessage == "Số cột khoá hai bên phải bằng nhau (trái 2, phải 0).")

        // Un-toggle ID: Code should shift to first
        model.toggleLeft("ID")
        #expect(model.leftKeys == ["Code"])
        #expect(model.statusMessage == "Số cột khoá hai bên phải bằng nhau (trái 1, phải 0).")

        // Re-set left keys to ["ID"]
        model.toggleLeft("Code") // now empty
        model.toggleLeft("ID")   // now ["ID"]

        // Toggle right key: CustID
        model.toggleRight("CustID")
        #expect(model.rightKeys == ["CustID"])
        #expect(model.isValid)
        #expect(model.statusLevel == .ok)
        #expect(model.statusMessage == "Đã chọn 1 cặp cột khoá.")

        // Test JoinChoice default & command
        #expect(model.kind == .leftOuter)
        model.kind = .inner
        let cmd = model.command()
        #expect(cmd == .merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["CustID"], kind: .inner, newColumn: "Orders"))
    }

    @Test func testMergeDialogModelTypeMismatchWarning() {
        let leftCols = [
            QueryColumnInfo(name: "ID", type: .string),
            QueryColumnInfo(name: "Code", type: .integer)
        ]
        let rightCols = [
            QueryColumnInfo(name: "Cust", type: .integer)
        ]

        var model = MergeDialogModel(
            primaryQueryName: "Customers",
            leftColumns: leftCols
        )
        model.rightColumns = rightCols
        model.secondQuery = "Orders"

        // Pair string "ID" with integer "Cust" -> type mismatch warning
        model.toggleLeft("ID")
        model.toggleRight("Cust")

        #expect(model.isValid) // Mismatch does not block OK
        #expect(model.statusLevel == .warning)
        #expect(model.statusMessage == "Cột khoá \"ID\" (văn bản) và \"Cust\" (số) khác kiểu nên sẽ không khớp dòng nào.")

        // Same numeric types (integer and double) should match without warning
        let numLeftCols = [QueryColumnInfo(name: "ID", type: .integer)]
        let numRightCols = [QueryColumnInfo(name: "Cust", type: .double)]
        var model2 = MergeDialogModel(primaryQueryName: "A", leftColumns: numLeftCols)
        model2.rightColumns = numRightCols
        model2.secondQuery = "B"
        model2.toggleLeft("ID")
        model2.toggleRight("Cust")
        #expect(model2.isValid)
        #expect(model2.statusLevel == .ok)
        #expect(model2.statusMessage == "Đã chọn 1 cặp cột khoá.")
    }

    // MARK: - AppendDialogModel Tests

    @Test func testAppendDialogModelTwoTablesMode() {
        var model = AppendDialogModel(
            primaryQueryName: "Customers",
            candidates: ["Orders", "Archive", "More"]
        )
        #expect(model.mode == .twoTables)
        #expect(!model.isValid)
        #expect(model.command() == nil)

        // Select a table
        model.selectTwoTablesQuery("Orders")
        #expect(model.selectedQueries == ["Orders"])
        #expect(model.isValid)
        #expect(model.command() == .append(queries: ["Orders"]))

        // Select another table in twoTables mode: replaces previous
        model.selectTwoTablesQuery("Archive")
        #expect(model.selectedQueries == ["Archive"])
        #expect(model.command() == .append(queries: ["Archive"]))
    }

    @Test func testAppendDialogModelThreeOrMoreMode() {
        var model = AppendDialogModel(
            primaryQueryName: "Customers",
            candidates: ["B", "C", "D"]
        )
        model.mode = .threeOrMore

        #expect(!model.isValid)
        #expect(model.command() == nil)

        // Select B, then C
        model.toggleSelection("B")
        model.toggleSelection("C")
        #expect(model.selectedQueries == ["B", "C"])
        #expect(model.order(of: "B") == 1)
        #expect(model.order(of: "C") == 2)
        #expect(model.order(of: "D") == nil)
        #expect(model.isValid)
        #expect(model.command() == .append(queries: ["B", "C"]))

        // Unselect B -> C becomes first
        model.toggleSelection("B")
        #expect(model.selectedQueries == ["C"])
        #expect(model.order(of: "B") == nil)
        #expect(model.order(of: "C") == 1)
        #expect(model.command() == .append(queries: ["C"]))

        // Switch to twoTables mode: retains only the first query
        model.toggleSelection("D")
        #expect(model.selectedQueries == ["C", "D"])
        model.mode = .twoTables
        #expect(model.selectedQueries == ["C"])

        // Column comparison helper
        let comp = AppendDialogModel.columnComparison(
            primaryColumns: ["ID", "Name", "Date"],
            secondaryColumns: ["ID", "Name", "Extra", "Extra2"]
        )
        #expect(comp.commonCount == 2)
        #expect(comp.secondaryOnlyCount == 2)
    }

    // MARK: - GroupByDialogModel Tests

    @Test func testGroupByDialogModelBasic() {
        let cols = [
            QueryColumnInfo(name: "Region", type: .string),
            QueryColumnInfo(name: "Amt", type: .double),
            QueryColumnInfo(name: "Qty", type: .integer)
        ]
        var model = GroupByDialogModel(
            allColumns: cols,
            initialSelectedColumns: ["Region"]
        )

        #expect(model.mode == .basic)
        #expect(model.basicKey == "Region")
        #expect(model.basicNewColumnName == "Count")
        #expect(model.basicOperation == .countRows)
        #expect(model.basicColumn == nil)
        #expect(model.isValid)
        #expect(model.command() == .groupBy(keys: ["Region"], aggregates: [GroupAggregate(name: "Count", operation: .countRows)]))

        // Change operation to sum on numeric column Amt
        model.basicOperation = .sum
        model.basicColumn = "Amt"
        model.basicNewColumnName = "Total"
        #expect(model.isValid)
        #expect(model.command() == .groupBy(keys: ["Region"], aggregates: [GroupAggregate(name: "Total", operation: .sum, column: "Amt")]))

        // Invalid: sum on string column
        model.basicColumn = "Region"
        #expect(!model.isValid)
        #expect(model.command() == nil)

        // Invalid: empty new column name
        model.basicColumn = "Amt"
        model.basicNewColumnName = "   "
        #expect(!model.isValid)

        // Invalid: new column name identical to key
        model.basicNewColumnName = "Region"
        #expect(!model.isValid)
    }

    @Test func testGroupByDialogModelAdvancedAndModeSwitch() {
        let cols = [
            QueryColumnInfo(name: "Region", type: .string),
            QueryColumnInfo(name: "City", type: .string),
            QueryColumnInfo(name: "Amt", type: .double),
            QueryColumnInfo(name: "Qty", type: .integer)
        ]
        var model = GroupByDialogModel(
            allColumns: cols,
            initialSelectedColumns: ["Region"]
        )
        model.basicOperation = .sum
        model.basicColumn = "Amt"
        model.basicNewColumnName = "TotalAmt"

        // Switch to advanced mode
        model.mode = .advanced
        #expect(model.keys == ["Region"])
        #expect(model.aggregates.count == 1)
        #expect(model.aggregates[0].name == "TotalAmt")
        #expect(model.aggregates[0].operation == .sum)
        #expect(model.aggregates[0].column == "Amt")
        #expect(model.isValid)

        // Add key
        model.addKey("City")
        #expect(model.keys == ["Region", "City"])

        // Add aggregate: Count Rows
        model.addAggregate(name: "RowCount", operation: .countRows, column: nil)
        #expect(model.aggregates.count == 2)
        #expect(model.isValid)
        #expect(model.command() == .groupBy(
            keys: ["Region", "City"],
            aggregates: [
                GroupAggregate(name: "TotalAmt", operation: .sum, column: "Amt"),
                GroupAggregate(name: "RowCount", operation: .countRows, column: nil)
            ]
        ))

        // Invalid: duplicate aggregate names
        model.aggregates[1].name = "TotalAmt"
        #expect(!model.isValid)
        #expect(model.command() == nil)

        // Invalid: aggregate name clashing with key
        model.aggregates[1].name = "City"
        #expect(!model.isValid)

        // Restore valid aggregate name
        model.aggregates[1].name = "RowCount"
        #expect(model.isValid)

        // Invalid: duplicate keys
        model.keys.append("City")
        #expect(!model.isValid)

        // Remove duplicate key
        model.removeKey(at: 2)
        #expect(model.isValid)

        // Switch back to basic: should pick first key and first aggregate
        model.mode = .basic
        #expect(model.basicKey == "Region")
        #expect(model.basicNewColumnName == "TotalAmt")
        #expect(model.basicOperation == .sum)
        #expect(model.basicColumn == "Amt")
        #expect(model.isValid)
    }

    // MARK: - ExpandColumnModel Tests

    @Test func testExpandColumnModel() {
        let cols = ["Cust", "Amt", "Region"]
        var model = ExpandColumnModel(
            sourceColumn: "Orders",
            allColumns: cols
        )

        // Default state: all selected, prefix true
        #expect(model.isAllSelected)
        #expect(model.usePrefix)
        #expect(model.orderedSelectedColumns == ["Cust", "Amt", "Region"])
        #expect(model.isValid)
        #expect(model.command() == .expandColumn(column: "Orders", names: ["Cust", "Amt", "Region"], prefixed: true))

        // Deselect one column: "Amt"
        model.toggle("Amt")
        #expect(!model.isAllSelected)
        #expect(model.orderedSelectedColumns == ["Cust", "Region"])
        #expect(model.isValid)
        #expect(model.command() == .expandColumn(column: "Orders", names: ["Cust", "Region"], prefixed: true))

        // Toggle prefix off
        model.usePrefix = false
        #expect(model.command() == .expandColumn(column: "Orders", names: ["Cust", "Region"], prefixed: false))

        // Deselect all
        model.deselectAll()
        #expect(model.orderedSelectedColumns.isEmpty)
        #expect(!model.isValid)
        #expect(model.command() == nil)

        // Select all
        model.selectAll()
        #expect(model.isAllSelected)
        #expect(model.orderedSelectedColumns == ["Cust", "Amt", "Region"])
        #expect(model.isValid)
    }
}
