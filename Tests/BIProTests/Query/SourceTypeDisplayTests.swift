// specs/011, US6 (T045): cột có kiểu Power Query Time, Duration, Binary (PostgreSQL, VM-F15) hiện trong xem trước như Desktop, và vào mô hình
// như Desktop: Binary bị bỏ, Time định dạng "Long Time", Duration là số (ngày).
import ColumnStore
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct SourceTypeDisplayTests {
    @Test func hienODurationVaTime() {
        // Desktop xem trước: 1.02:03:04, -02:30:00, 32.00:00:00, -417.00:00:00, 0.00:00:00.5000000.
        let days: [(Double, String)] = [(1 + 7384.0 / 86_400, "1.02:03:04"), (-2.5 / 24, "-02:30:00"), (32, "32.00:00:00"),
                                        (-417, "-417.00:00:00"), (0.5 / 86_400, "0.00:00:00.5000000")]
        for (value, text) in days { #expect(NavigatorFormat.sourceCell(.double(value), .duration) == text) }
        #expect(NavigatorFormat.sourceCell(.dateTime(8.5 / 24), .time) == "08:30:00")
        #expect(NavigatorFormat.sourceCell(.dateTime(86_399.5 / 86_400), .time) == "23:59:59.5")
        #expect(NavigatorFormat.sourceCell(.string("\\x00ff"), .binary) == "Binary")
        #expect(NavigatorFormat.sourceCell(.double(1), nil) == nil)
        #expect(QueryEditorFormat.typeBadge(.dateTime, source: .time) == "Giờ")
        #expect(QueryEditorFormat.typeBadge(.double, source: .duration) == "TG")
    }

    @Test func vaoMoHinhBoBinaryVaDinhDangTime() throws {
        let data = try TableData(columns: [
            TableColumn(name: "id", data: ColumnBuilder.integers([1, 2])),
            TableColumn(name: "t", data: ColumnBuilder.dateTimes([0.5, 0.25]), sourceType: .time),
            TableColumn(name: "iv", data: ColumnBuilder.doubles([1, -2]), sourceType: .duration),
            TableColumn(name: "b", data: ColumnBuilder.strings(["\\x00", nil]), sourceType: .binary),
            TableColumn(name: "r", data: ColumnBuilder.strings(["Record", nil]), sourceType: .record),
            TableColumn(name: "l", data: ColumnBuilder.strings(["List", "List"]), sourceType: .list),
        ])
        let edits = TableLoader.edits(for: [LoadedTable(name: "pg", data: data, status: .new)])
        guard case .addTable(let table)? = edits.first else { Issue.record("phải có addTable"); return }
        #expect(table.columns.map(\.name) == ["id", "t", "iv"])
        #expect(table.columns.map(\.dataType) == [.int64, .dateTime, .double])
        #expect(edits.dropFirst().contains(.updateColumn(table: "pg", name: "t", patch: ColumnPatch(formatString: .set("Long Time")))))
    }
}
