import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("PhaseG — Localization (L10n)")
struct LocalizationTests {
    @Test("100% khoá L10n đều có đủ bản dịch vi và en không rỗng và khớp placeholder")
    func allKeysCompleteAndMatchingPlaceholders() {
        #expect(!L10n.Key.allCases.isEmpty)
        for key in L10n.Key.allCases {
            let vi = L10n.string(key, language: .vi)
            let en = L10n.string(key, language: .en)
            #expect(!vi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Thiếu bản dịch vi cho \(key.rawValue)")
            #expect(!en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Thiếu bản dịch en cho \(key.rawValue)")
            #expect(placeholders(in: vi) == placeholders(in: en), "Lệch placeholder cho \(key.rawValue): vi=\(vi) | en=\(en)")
        }
    }

    @Test("Hàm format trả về đúng ngôn ngữ cho cả vi và en")
    func formatWorksInBothLanguages() {
        let vi = L10n.format(.exportProgressRenderingPageFormat, language: .vi, 2, 5)
        let en = L10n.format(.exportProgressRenderingPageFormat, language: .en, 2, 5)
        #expect(vi == "Đang kết xuất trang 2/5…")
        #expect(en == "Rendering page 2/5…")
    }

    @Test("Nhãn phép gộp ngầm đổi theo ngôn ngữ trong khi nativeQueryRef PBIR giữ bất biến (SC-003)")
    @MainActor
    func implicitAggregationLabelsBilingualAndPBIRInvariant() throws {
        #expect(AggregateFunction.sum.label(column: "Amount", kind: .number, language: .vi) == "Tổng của Amount")
        #expect(AggregateFunction.sum.label(column: "Amount", kind: .number, language: .en) == "Sum of Amount")
        #expect(AggregateFunction.average.label(column: "Price", kind: .number, language: .vi) == "Trung bình của Price")
        #expect(AggregateFunction.average.label(column: "Price", kind: .number, language: .en) == "Average of Price")
        #expect(AggregateFunction.min.label(column: "Name", kind: .text, language: .en) == "First Name")
        #expect(AggregateFunction.min.label(column: "OrderDate", kind: .date, language: .en) == "Earliest OrderDate")

        // Xác nhận đổi AppPreferences.shared.language không làm thay đổi byte PBIR hay truy vấn M
        let prev = AppPreferences.shared.language
        defer { AppPreferences.shared.language = prev }

        let baseVisual = Data(#"{"name":"v1","visual":{"visualType":"clusteredColumnChart","query":{"queryState":{}}}}"#.utf8)
        AppPreferences.shared.language = .vi
        let viAgg = PBIRQueryPatch.newAggregation(entity: "Sales", property: "Amount", function: AggregateFunction.sum.rawValue, role: "Y")
        let viBytes = try PBIRQueryPatch.apply([PBIRQueryPatch.Well(role: "Y", elements: [viAgg])], to: baseVisual)
        let viConn = SQLiteODBC.connectionString(path: "/tmp/sales.sqlite")

        AppPreferences.shared.language = .en
        let enAgg = PBIRQueryPatch.newAggregation(entity: "Sales", property: "Amount", function: AggregateFunction.sum.rawValue, role: "Y")
        let enBytes = try PBIRQueryPatch.apply([PBIRQueryPatch.Well(role: "Y", elements: [enAgg])], to: baseVisual)
        let enConn = SQLiteODBC.connectionString(path: "/tmp/sales.sqlite")

        #expect(viAgg == enAgg)
        #expect(viBytes == enBytes)
        #expect(viConn == enConn)
    }

    @Test("Phase G2: bi(_:_:), Ribbon helpers, NavigatorFormat và QueryEditorFormat đổi đúng ngôn ngữ")
    @MainActor
    func deepViewsBilingualHelpers() {
        let prev = AppPreferences.shared.language
        defer { AppPreferences.shared.language = prev }

        AppPreferences.shared.language = .vi
        #expect(bi("Đóng", "Close") == "Đóng")
        #expect(ConnectorCatalog.entries.first(where: { $0.kind == .excel })?.localizedTitle == "Sổ làm việc Excel")

        AppPreferences.shared.language = .en
        #expect(bi("Đóng", "Close") == "Close")
        #expect(ConnectorCatalog.entries.first(where: { $0.kind == .excel })?.localizedTitle == "Excel Workbook")

        #expect(dataTypeName(.string, language: .vi) == "Văn bản")
        #expect(dataTypeName(.string, language: .en) == "Text")
        #expect(dataTypeName(.int64, language: .en) == "Whole number")

        #expect(NavigatorFormat.kindBadge(.sheet, language: .vi) == "Trang tính")
        #expect(NavigatorFormat.kindBadge(.sheet, language: .en) == "Sheet")
        #expect(NavigatorFormat.selectedSummary(checked: 2, total: 5, language: .en) == "Selected 2 of 5 items")
        #expect(NavigatorFormat.truncationNote(previewRows: 200, rowCountHint: 500, language: .en) == "Preview truncated to first 200 rows.")

        #expect(QueryEditorFormat.statusSummary(columns: 5, rows: 120, language: .en) == "5 columns · 120 rows")
        #expect(QueryEditorFormat.profileCaption(rowsProfiled: 1000, language: .en) == "Based on top 1000 rows")
        #expect(QueryRibbonTab.transform.localizedTitle(language: .en) == "Transform")
        #expect(QueryRibbonCommand.removeDuplicates.localizedTitle(language: .en) == "Remove Duplicates")
    }

    private func placeholders(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(@|d|lld|f|\\.\\df)")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
