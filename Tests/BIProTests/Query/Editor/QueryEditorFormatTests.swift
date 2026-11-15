import Testing
import ColumnStore
@testable import BIPro

@Suite struct QueryEditorFormatTests {
    @Test func testPercent() {
        #expect(QueryEditorFormat.percent(93, of: 100) == "93%")
        #expect(QueryEditorFormat.percent(1, of: 3) == "33%")
        #expect(QueryEditorFormat.percent(2, of: 3) == "67%")
        #expect(QueryEditorFormat.percent(0, of: 0) == "0%")
        #expect(QueryEditorFormat.percent(0, of: 50) == "0%")
        #expect(QueryEditorFormat.percent(50, of: 50) == "100%")
    }

    @Test func testStatusSummary() {
        #expect(QueryEditorFormat.statusSummary(columns: 9, rows: 500) == "9 cột · 500 dòng")
        #expect(QueryEditorFormat.statusSummary(columns: 9, rows: 999) == "9 cột · 999 dòng")
        #expect(QueryEditorFormat.statusSummary(columns: 9, rows: 1000) == "9 cột · 999+ dòng")
        #expect(QueryEditorFormat.statusSummary(columns: 9, rows: 1500) == "9 cột · 999+ dòng")
        #expect(QueryEditorFormat.statusSummary(columns: 1, rows: 0) == "1 cột · 0 dòng")
    }

    @Test func testProfileCaption() {
        #expect(QueryEditorFormat.profileCaption(rowsProfiled: 1000) == "Dựa trên 1000 dòng đầu")
        #expect(QueryEditorFormat.profileCaption(rowsProfiled: 1200) == "Dựa trên 1000 dòng đầu")
        #expect(QueryEditorFormat.profileCaption(rowsProfiled: 500) == "Dựa trên 500 dòng")
        #expect(QueryEditorFormat.profileCaption(rowsProfiled: 0) == "Dựa trên 0 dòng")
    }

    @Test func testTypeBadge() {
        #expect(QueryEditorFormat.typeBadge(.integer) == "123")
        #expect(QueryEditorFormat.typeBadge(.double) == "123")
        #expect(QueryEditorFormat.typeBadge(.currency) == "123")
        #expect(QueryEditorFormat.typeBadge(.string) == "ABC")
        #expect(QueryEditorFormat.typeBadge(.dateTime) == "Ngày")
        #expect(QueryEditorFormat.typeBadge(.boolean) == "T/F")
    }

    @Test func testCountLine() {
        let profile = ColumnProfile(columnName: "Qty", valid: 93, error: 0, empty: 7, distinct: 5, unique: 0)
        #expect(QueryEditorFormat.countLine(profile) == 100)

        let profileWithErrors = ColumnProfile(columnName: "Amount", valid: 80, error: 15, empty: 5, distinct: 10, unique: 2)
        #expect(QueryEditorFormat.countLine(profileWithErrors) == 100)
    }
}
