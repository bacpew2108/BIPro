import Testing
import Foundation
import ColumnStore
import Connectors
@testable import BIPro

@Suite struct NavigatorFormatTests {

    @Test func rowCountFormatting() {
        #expect(NavigatorFormat.rowCount(nil) == "")
        #expect(NavigatorFormat.rowCount(0) == "0")
        #expect(NavigatorFormat.rowCount(50) == "50")
        #expect(NavigatorFormat.rowCount(890) == "890")
        #expect(NavigatorFormat.rowCount(4210) == "4,210")
        #expect(NavigatorFormat.rowCount(9999) == "9,999")
        #expect(NavigatorFormat.rowCount(10000) == "10k")
        #expect(NavigatorFormat.rowCount(18430) == "18.4k")
        #expect(NavigatorFormat.rowCount(1_200_000) == "1.2M")
    }

    @Test func cellFormatting() {
        #expect(NavigatorFormat.cell(.blank) == "null")
        #expect(NavigatorFormat.cell(.integer(12345)) == "12345")
        #expect(NavigatorFormat.cell(.integer(-42)) == "-42")
        #expect(NavigatorFormat.cell(.integer(0)) == "0")
        #expect(NavigatorFormat.cell(.double(120)) == "120")
        #expect(NavigatorFormat.cell(.double(9.99)) == "9.99")
        #expect(NavigatorFormat.cell(.double(0)) == "0")
        #expect(NavigatorFormat.cell(.double(-15.5)) == "-15.5")
        #expect(NavigatorFormat.cell(.currency(12345678)) == "1234.57")
        #expect(NavigatorFormat.cell(.currency(120000)) == "12.00")
        #expect(NavigatorFormat.cell(.currency(0)) == "0.00")
        #expect(NavigatorFormat.cell(.currency(-50000)) == "-5.00")
        #expect(NavigatorFormat.cell(.string("a\nb")) == "a↵b")
        #expect(NavigatorFormat.cell(.string("line1\r\nline2\rline3")) == "line1↵line2↵line3")
        #expect(NavigatorFormat.cell(.string("normal text")) == "normal text")
        #expect(NavigatorFormat.cell(.boolean(true)) == "TRUE")
        #expect(NavigatorFormat.cell(.boolean(false)) == "FALSE")
        #expect(NavigatorFormat.cell(.dateTime(46083)) == "2026-03-02")
        #expect(NavigatorFormat.cell(.dateTime(46083.5)) == "2026-03-02 12:00:00")
    }

    @Test func kindBadgeLabels() {
        #expect(NavigatorFormat.kindBadge(.sheet) == "Trang tính")
        #expect(NavigatorFormat.kindBadge(.namedTable) == "Bảng đặt tên")
        #expect(NavigatorFormat.kindBadge(.table) == "Bảng")
        #expect(NavigatorFormat.kindBadge(.view) == "Khung nhìn")
        #expect(NavigatorFormat.kindBadge(.file) == "Tệp")
        #expect(NavigatorFormat.kindBadge(.record) == "Bản ghi")
    }

    @Test func selectedSummaryText() {
        #expect(NavigatorFormat.selectedSummary(checked: 0, total: 4) == "Đã chọn 0 / 4 mục")
        #expect(NavigatorFormat.selectedSummary(checked: 2, total: 4) == "Đã chọn 2 / 4 mục")
        #expect(NavigatorFormat.selectedSummary(checked: 1, total: 1) == "Đã chọn 1 / 1 mục")
    }

    @Test func truncationNoteRules() {
        #expect(NavigatorFormat.truncationNote(previewRows: 200, rowCountHint: 10_000) == "Xem trước bị cắt ở 200 dòng đầu.")
        #expect(NavigatorFormat.truncationNote(previewRows: 200, rowCountHint: nil) == "Xem trước bị cắt ở 200 dòng đầu.")
        #expect(NavigatorFormat.truncationNote(previewRows: 200, rowCountHint: 201) == "Xem trước bị cắt ở 200 dòng đầu.")
        #expect(NavigatorFormat.truncationNote(previewRows: 5, rowCountHint: 5) == nil)
        #expect(NavigatorFormat.truncationNote(previewRows: 200, rowCountHint: 200) == nil)
        #expect(NavigatorFormat.truncationNote(previewRows: 199, rowCountHint: 10_000) == nil)
        #expect(NavigatorFormat.truncationNote(previewRows: 50, rowCountHint: nil) == nil)
    }
}
