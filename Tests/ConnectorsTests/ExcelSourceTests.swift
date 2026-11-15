import Testing
import Foundation
import ColumnStore
@testable import Connectors

@Suite struct ExcelSourceTests {

    // MARK: - Sample Fixture Tests

    @Test func sales2026ExcelItemsListOrder() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let source = ExcelSource(url: url)
        let items = try await source.items()

        #expect(items.count == 4)
        #expect(items[0].name == "Sales")
        #expect(items[0].kind == .sheet)

        #expect(items[1].name == "Customers")
        #expect(items[1].kind == .sheet)

        #expect(items[2].name == "Notes")
        #expect(items[2].kind == .sheet)

        #expect(items[3].name == "SalesTable")
        #expect(items[3].kind == .namedTable)
    }

    /// Navigator hiện số dòng từng trang tính (lấy từ `<dimension>`, không phải đọc hết ô). Sales: 500 dòng dữ liệu, Customers: 50.
    @Test func sheetRowCountHintTuDimension() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let items = try await ExcelSource(url: url).items()
        #expect(items[0].rowCountHint == 500)
        #expect(items[1].rowCountHint == 50)
        let noHeader = try await ExcelSource(url: url, options: .init(promoteHeaders: false)).items()
        #expect(noHeader[0].rowCountHint == 501)
        // Gợi ý khớp số dòng thật khi nạp.
        let loaded = try await items[0].load(progress: nil)
        #expect(items[0].rowCountHint == loaded.rowCount)
    }

    @Test func salesSheetLoadAndPreview() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let source = ExcelSource(url: url)
        let items = try await source.items()
        let salesItem = items[0]

        // Preview limit 5
        let preview = try await salesItem.preview(limit: 5)
        #expect(preview.rowCount == 5)
        #expect(preview.columns.map(\.name) == ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"])
        #expect(preview.value(row: 0, column: 0) == .integer(1))
        #expect(preview.value(row: 0, column: 1) == .dateTime(46083.0))
        #expect(preview.value(row: 0, column: 2) == .string("Trung tâm"))
        #expect(preview.value(row: 0, column: 3) == .integer(7))
        #expect(preview.value(row: 0, column: 4) == .string("Đồng hồ"))
        #expect(preview.value(row: 0, column: 5) == .integer(11))
        #expect(preview.value(row: 0, column: 6) == .double(120.0))
        #expect(preview.value(row: 0, column: 7) == .double(1320.0))

        // Load full
        let table = try await salesItem.load(progress: nil)
        #expect(table.rowCount == 500)
        #expect(table.columns[0].data.type == .integer)
        #expect(table.columns[1].data.type == .dateTime)
        #expect(table.columns[2].data.type == .string)
        #expect(table.columns[3].data.type == .integer)
        #expect(table.columns[4].data.type == .string)
        #expect(table.columns[5].data.type == .integer)
        #expect(table.columns[6].data.type == .double)
        #expect(table.columns[7].data.type == .double)

        // First row
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 1) == .dateTime(46083.0))
        #expect(table.value(row: 0, column: 2) == .string("Trung tâm"))
        #expect(table.value(row: 0, column: 3) == .integer(7))
        #expect(table.value(row: 0, column: 4) == .string("Đồng hồ"))
        #expect(table.value(row: 0, column: 5) == .integer(11))
        #expect(table.value(row: 0, column: 6) == .double(120.0))
        #expect(table.value(row: 0, column: 7) == .double(1320.0))

        // Last row (row 499)
        #expect(table.value(row: 499, column: 0) == .integer(500))
        #expect(table.value(row: 499, column: 2) == .string("North"))
        #expect(table.value(row: 499, column: 3) == .integer(5))
        #expect(table.value(row: 499, column: 4) == .string("Mũ"))
        #expect(table.value(row: 499, column: 5) == .integer(2))
        #expect(table.value(row: 499, column: 6) == .double(9.99))
        #expect(table.value(row: 499, column: 7) == .double(19.98))
    }

    @Test func customersSheetLoad() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let source = ExcelSource(url: url)
        let items = try await source.items()
        let custItem = items[1]

        let table = try await custItem.load(progress: nil)
        #expect(table.rowCount == 50)
        #expect(table.columns.map(\.name) == ["CustomerID", "Name", "Segment"])
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 1) == .string("Khách 1"))
        #expect(table.value(row: 0, column: 2) == .string("Wholesale"))
    }

    @Test func notesSheetWithTrimLeadingEmpty() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let options = ExcelSource.Options(promoteHeaders: true, detectTypes: true, trimLeadingEmpty: true)
        let source = ExcelSource(url: url, options: options)
        let items = try await source.items()
        let notesItem = items[2]

        let table = try await notesItem.load(progress: nil)
        #expect(table.rowCount == 3)
        #expect(table.columns.map(\.name) == ["Key", "Value"])
        #expect(table.columns[0].data.type == .string)
        #expect(table.columns[1].data.type == .integer)

        #expect(table.value(row: 0, column: 0) == .string("a"))
        #expect(table.value(row: 0, column: 1) == .integer(1))

        #expect(table.value(row: 1, column: 0) == .string("b"))
        #expect(table.value(row: 1, column: 1) == .blank)

        #expect(table.value(row: 2, column: 0) == .string("c"))
        #expect(table.value(row: 2, column: 1) == .integer(3))
    }

    @Test func salesNamedTableLoad() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let source = ExcelSource(url: url)
        let items = try await source.items()
        let tableItem = items[3]

        #expect(tableItem.name == "SalesTable")
        #expect(tableItem.kind == .namedTable)

        let table = try await tableItem.load(progress: nil)
        #expect(table.rowCount == 500)
        #expect(table.columns.map(\.name) == ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"])
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 0, column: 1) == .dateTime(46083.0))
        #expect(table.value(row: 499, column: 0) == .integer(500))
        #expect(table.value(row: 499, column: 7) == .double(19.98))
    }

    // MARK: - Edge Cases

    @Test func excelErrorCellsProduceBlankAndErrorMask() throws {
        let grid: [[ExcelCellType?]] = [
            [.integer(1), .error("#N/A")],
            [.integer(2), .string("OK")]
        ]
        let headers = ["ID", "Status"]
        let options = ExcelSource.Options(promoteHeaders: false, detectTypes: true)
        let table = try ExcelDataLoader.buildTable(grid: grid, headers: headers, options: options)

        #expect(table.rowCount == 2)
        #expect(table.value(row: 0, column: 1) == .blank)
        #expect(table.error(row: 0, column: 1)?.contains("#N/A") == true)
        #expect(table.value(row: 1, column: 1) == .string("OK"))
    }

    @Test func excelMixedTypesInColumnProduceString() throws {
        let grid: [[ExcelCellType?]] = [
            [.integer(42)],
            [.string("text")],
            [.double(3.14)]
        ]
        let headers = ["MixedCol"]
        let options = ExcelSource.Options(promoteHeaders: false, detectTypes: true)
        let table = try ExcelDataLoader.buildTable(grid: grid, headers: headers, options: options)

        #expect(table.columns[0].data.type == .string)
        #expect(table.value(row: 0, column: 0) == .string("42"))
        #expect(table.value(row: 1, column: 0) == .string("text"))
        #expect(table.value(row: 2, column: 0) == .string("3.14"))
    }

    @Test func sheetParserHandlesDate1904AndErrors() {
        let xmlData = """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <sheetData>
                <row r="1">
                    <c r="A1" t="e"><v>#REF!</v></c>
                    <c r="B1" s="1"><v>40000</v></c>
                </row>
            </sheetData>
        </worksheet>
        """.data(using: .utf8)!

        let parser = SheetParser(sharedStrings: [], isDateStyle: [1: true], date1904: true)
        let xml = XMLParser(data: xmlData)
        xml.delegate = parser
        xml.parse()

        #expect(parser.cells.count == 2)
        if case .error(let code) = parser.cells[0].value {
            #expect(code == "#REF!")
        } else {
            #expect(Bool(false), "Lẽ ra phải là error")
        }
        if case .dateTime(let d) = parser.cells[1].value {
            #expect(d == 40000 + 1462)
        } else {
            #expect(Bool(false), "Lẽ ra phải là dateTime 1904")
        }
    }

    @Test func stylesParserDetectsCustomDateFormats() {
        #expect(StylesParser.isDateNumFmt(id: 14, customCode: nil) == true)
        #expect(StylesParser.isDateNumFmt(id: 20, customCode: nil) == true)
        #expect(StylesParser.isDateNumFmt(id: 45, customCode: nil) == true)
        #expect(StylesParser.isDateNumFmt(id: 0, customCode: nil) == false)
        #expect(StylesParser.isDateNumFmt(id: 164, customCode: "yyyy-mm-dd") == true)
        #expect(StylesParser.isDateNumFmt(id: 165, customCode: "hh:mm:ss") == true)
        #expect(StylesParser.isDateNumFmt(id: 166, customCode: "#,##0.00") == false)
        #expect(StylesParser.isDateNumFmt(id: 167, customCode: "[Red]0.00") == false)
    }

    @Test func nonExistentExcelFileThrowsUnreadable() async throws {
        let badURL = URL(fileURLWithPath: "/tmp/non_existent_\(UUID().uuidString).xlsx")
        let source = ExcelSource(url: badURL)
        await #expect(throws: SourceError.self) {
            try await source.items()
        }
    }
}
