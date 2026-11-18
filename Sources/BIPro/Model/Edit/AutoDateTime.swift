import Foundation
import PBIXKit

/// Auto date/time như Power BI Desktop 2.159 (đợt tồn đọng sau Phase F, US2). T025 chốt mẫu; T032 thêm phần sinh `ModelEdit`.
///
/// Desktop lưu, với tuỳ chọn của file bật (chú thích mô hình `__PBI_TimeIntelligenceEnabled = 1`, mặc định cho tài liệu mới):
/// - một `DateTableTemplate_<guid>` cho mỗi mô hình: bảng tính toán ẩn, riêng tư;
/// - một `LocalDateTable_<guid>` cho mỗi cột Date hoặc DateTime của bảng người dùng: bảng tính toán ẩn, chỉ hiện như biến thể;
/// - quan hệ `T[c]` (nhiều) → `LocalDateTable_…[Date]` (một): tên là GUID trần, `JoinOnDateBehavior` 2, một chiều, hoạt động;
/// - một `Variation` "Variation" trên `T[c]`, trỏ quan hệ đó và phân cấp "Date Hierarchy" của bảng cục bộ, `IsDefault`.
/// Tắt tuỳ chọn: xoá hết các thứ trên, chú thích về 0, visual dùng phân cấp được viết lại thành cột thường. Bật lại: GUID mới.
///
/// Nguồn: `docs/phase-f2-evidence/vm-f11/QUAN-SAT.md` mục b; `w8.3.pbix` và `vm-f11/f11-desktop.pbix` cùng mẫu
/// (`Tests/PBIXKitTests/F2AutoDateGoldenTests.swift`; hằng số dưới đây kiểm lại ở `Tests/BIProTests/Model/AutoDateTemplateTests.swift`).
enum AutoDateTime {
    /// Chú thích mô hình: "1" bật, "0" tắt.
    static let modelAnnotation = "__PBI_TimeIntelligenceEnabled"

    static let templateTablePrefix = "DateTableTemplate_"
    static let localTablePrefix = "LocalDateTable_"

    /// Chú thích bảng mẫu (`IsHidden`, `IsPrivate`, không `ShowAsVariationsOnly`).
    static let templateTableAnnotations = ["__PBI_TemplateDateTable": "true", "DefaultItem": "DateHierarchy"]
    /// Chú thích bảng cục bộ (`IsHidden`, `ShowAsVariationsOnly`, không `IsPrivate`).
    static let localTableAnnotations = ["__PBI_LocalDateTable": "true"]

    /// Biểu thức bảng mẫu.
    static let templateExpression = "Calendar(Date(2015,1,1), Date(2015,1,1))"

    /// Biểu thức bảng cục bộ cho cột `table[column]`: lịch đủ các năm có trong cột.
    /// `[SUY ĐOÁN]` tên có `'` hoặc `]` được thoát như DAX thường (`''`, `]]`); hai file Desktop không có tên như vậy.
    static func localExpression(table: String, column: String) -> String {
        let source = "'\(table.replacingOccurrences(of: "'", with: "''"))'[\(column.replacingOccurrences(of: "]", with: "]]"))]"
        return "Calendar(Date(Year(MIN(\(source))), 1, 1), Date(Year(MAX(\(source))), 12, 31))"
    }

    /// Tên bảng mới: tiền tố + GUID chữ thường, như Desktop.
    static func tableName(prefix: String, id: UUID = UUID()) -> String { prefix + id.uuidString.lowercased() }

    /// Tên quan hệ ngày: GUID trần chữ thường (quan hệ tự phát hiện mới có tiền tố `AutoDetected_`).
    static func relationshipName(id: UUID = UUID()) -> String { id.uuidString.lowercased() }

    /// Một cột của bảng ngày (cả bảng mẫu và bảng cục bộ). Mọi cột ẩn, `SummarizeBy` None, chú thích `SummarizationSetBy = User`;
    /// `Date` là cột của `Calendar` (không biểu thức), các cột khác là cột tính toán.
    struct Column: Equatable {
        let name: String
        let expression: String?
        let dataType: ModelMetadata.DataType
        let dataCategory: String
        let formatString: String?
        let sortBy: String?
        /// Chú thích `TemplateId`; `Date` không có.
        let templateId: String?
    }

    static let columns: [Column] = [
        Column(name: "Date", expression: nil, dataType: .dateTime, dataCategory: "PaddedDateTableDates",
               formatString: "General Date", sortBy: nil, templateId: nil),
        Column(name: "Year", expression: "YEAR([Date])", dataType: .int64, dataCategory: "Years",
               formatString: "0", sortBy: nil, templateId: "Year"),
        Column(name: "MonthNo", expression: "MONTH([Date])", dataType: .int64, dataCategory: "MonthOfYear",
               formatString: "0", sortBy: nil, templateId: "MonthNumber"),
        Column(name: "Month", expression: "FORMAT([Date], \"MMMM\")", dataType: .string, dataCategory: "Months",
               formatString: nil, sortBy: "MonthNo", templateId: "Month"),
        Column(name: "QuarterNo", expression: "INT(([MonthNo] + 2) / 3)", dataType: .int64, dataCategory: "QuarterOfYear",
               formatString: "0", sortBy: nil, templateId: "QuarterNumber"),
        Column(name: "Quarter", expression: "\"Qtr \" & [QuarterNo]", dataType: .string, dataCategory: "Quarters",
               formatString: nil, sortBy: "QuarterNo", templateId: "Quarter"),
        Column(name: "Day", expression: "DAY([Date])", dataType: .int64, dataCategory: "DayOfMonth",
               formatString: "0", sortBy: nil, templateId: "Day"),
    ]

    static let columnAnnotations = ["SummarizationSetBy": "User"]

    /// Phân cấp ở bảng mẫu và mỗi bảng cục bộ; không ẩn; chú thích `TemplateId = DateHierarchy`.
    static let hierarchyName = "Date Hierarchy"
    static let hierarchyLevels = ["Year", "Quarter", "Month", "Day"]
    static let hierarchyAnnotations = ["TemplateId": "DateHierarchy"]

    /// Quan hệ ngày: `JoinOnDateBehavior` 2 (DatePartOnly), `CrossFilteringBehavior` 1 (một chiều).
    static let joinOnDateBehavior = 2
    static let crossFilteringBehavior = 1

    static let variationName = "Variation"
}
