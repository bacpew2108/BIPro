// Hợp đồng Phase C (đợt 0, lead): mô tả trung gian của truy vấn một visual.
//
// visual.json ─► VisualQuerySpecReader ─► VisualQuerySpec ─► DAXQueryBuilder ─► văn bản DAX (khuôn Performance Analyzer)
//
// Spec không chứa DAX, không chứa JSON. Mọi tên đã là tên thật trong model (bảng, cột, measure).
// Khuôn truy vấn tham chiếu: docs/phase-b-evidence/observe2/PA-*.dax (và observe-c1 sau buổi C1).
import Foundation

/// Một cột nhóm (cột thật của model) trong truy vấn.
struct QueryColumn: Hashable, Sendable {
    var table: String
    var column: String

    /// `'Bảng'[cột]` như Power BI viết.
    var dax: String { "'\(table.replacingOccurrences(of: "'", with: "''"))'[\(column.replacingOccurrences(of: "]", with: "]]"))]" }
}

/// Một trường nhóm như visual thấy: cột (hoặc cấp hierarchy đã quy về cột), kèm cột sort-by mà Power BI tự thêm
/// (ví dụ `Dim_Client[age_group_current]` đi cùng `Dim_Client[age_group_order]` trong PA-D1-2).
struct GroupField: Hashable, Sendable {
    var field: FieldInfo
    var column: QueryColumn
    var sortBy: QueryColumn?
}

/// Một cột giá trị của SUMMARIZECOLUMNS.
struct QueryMeasure: Hashable, Sendable {
    var field: FieldInfo
    var table: String
    var measure: String
    /// Tên cột kết quả Power BI đặt, ví dụ "Loan_Count2", "v_Bad_Debt_Ratio_Count_FormatString".
    var resultName: String
    /// Bọc `IGNORE(...)`: không dùng để quyết định dòng nào bị loại vì toàn BLANK (tooltip, màu, định dạng động).
    var ignore: Bool
    /// Mục đích của cột: giá trị chính, tooltip, chuỗi định dạng động của measure khác, màu/icon lấy từ measure.
    var purpose: Purpose

    enum Purpose: Hashable, Sendable {
        case value
        case tooltip
        /// Định dạng động của measure có queryRef này.
        case formatString(of: String)
        /// Thuộc tính định dạng lấy từ measure (`VisualFormat.measureDriven`).
        case formatting(MeasureDrivenProperty)
    }
}

/// Một khoá sắp xếp trong TOPN/ORDER BY.
struct QuerySortKey: Hashable, Sendable {
    enum Target: Hashable, Sendable {
        case column(QueryColumn)
        /// Cột kết quả theo tên, ví dụ `[D4_Complaints]` hoặc `[IsGrandTotalRowTotal]`.
        case result(String)
    }
    var target: Target
    var ascending: Bool
}

/// Cách Power BI giảm dữ liệu cho visual (Microsoft Learn "Data point limits and strategies").
enum DataReduction: Hashable, Sendable {
    case none
    /// `TOPN(n, …)` cửa sổ đầu tiên (bar/column: 1001 dòng trong PA-D2-2/D3-2/D4-x).
    case top(Int)
    /// `SAMPLE(n, …)` (combo trục danh mục số: 3502 trong PA-D2-1).
    case sample(Int)
    /// `SAMPLEAXISWITHLOCALMINMAX(size, …, minResolution, …, maxResolution, maxIterations)` (line trục liên tục: PA-D1-1).
    case binnedLine(size: Int, minResolution: Int, maxResolution: Int, maxIterations: Int)
    /// Hai trục (matrix, hoặc chart có Series): cửa sổ primary × secondary (102 × 102 trong PA-D1-2, 201 × 62 trong PA-D3-1).
    case window(primary: Int, secondary: Int)
}

/// Bộ lọc đã dịch sang biểu thức bảng DAX (gói I làm `FilterTranslator`; đợt 1 chỉ có bộ lọc report/page/visual tĩnh).
struct QueryFilter: Hashable, Sendable {
    /// Biểu thức bảng, ví dụ `FILTER(KEEPFILTERS(VALUES('Dim_Date'[year])), NOT('Dim_Date'[year] IN {9999}))`.
    var tableExpression: String
}

struct VisualQuerySpec: Hashable, Sendable {
    var visualID: String
    var visualType: String
    /// Trục chính: Category (chart), Rows (matrix), Values (slicer).
    var primary: [GroupField]
    /// Trục phụ: Series (chart), Columns (matrix). Rỗng nếu không có.
    var secondary: [GroupField]
    var measures: [QueryMeasure]
    var filters: [QueryFilter]
    /// Matrix: thêm dòng/cột tổng (ROLLUPADDISSUBTOTAL). Tên cờ: "IsGrandTotalRowTotal", "IsGrandTotalColumnTotal".
    var rowTotals: Bool
    var columnTotals: Bool
    /// Thứ tự sắp của trục chính (sortDefinition của visual, mặc định theo cột sort-by rồi cột).
    var primaryOrder: [QuerySortKey]
    var secondaryOrder: [QuerySortKey]
    var reduction: DataReduction
    /// Chart có hai nhóm measure khác phạm vi (combo có Series: cột theo Series, đường không theo Series) thì Power BI
    /// sinh `__ScopedCoreI0` và `__ScopedCoreDM0` rồi NATURALLEFTOUTERJOIN (PA-D3-1). Đây là measure của nhóm thứ hai.
    var scopedMeasures: [QueryMeasure]
    /// Line trục liên tục: thêm `ROW("DS0IntersectionCount", …)` như PA-D1-1.
    var includeIntersectionCount: Bool

    init(visualID: String, visualType: String, primary: [GroupField] = [], secondary: [GroupField] = [],
         measures: [QueryMeasure] = [], filters: [QueryFilter] = [], rowTotals: Bool = false, columnTotals: Bool = false,
         primaryOrder: [QuerySortKey] = [], secondaryOrder: [QuerySortKey] = [], reduction: DataReduction = .none,
         scopedMeasures: [QueryMeasure] = [], includeIntersectionCount: Bool = false) {
        self.visualID = visualID
        self.visualType = visualType
        self.primary = primary
        self.secondary = secondary
        self.measures = measures
        self.filters = filters
        self.rowTotals = rowTotals
        self.columnTotals = columnTotals
        self.primaryOrder = primaryOrder
        self.secondaryOrder = secondaryOrder
        self.reduction = reduction
        self.scopedMeasures = scopedMeasures
        self.includeIntersectionCount = includeIntersectionCount
    }
}
