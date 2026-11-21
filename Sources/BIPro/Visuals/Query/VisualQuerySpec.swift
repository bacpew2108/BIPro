// Hợp đồng Phase C (đợt 0, lead): mô tả trung gian của truy vấn một visual.
//
// visual.json ─► VisualQuerySpecReader ─► VisualQuerySpec ─► DAXQueryBuilder ─► văn bản DAX (khuôn Performance Analyzer)
//
// Spec không chứa DAX, không chứa JSON. Mọi tên đã là tên thật trong model (bảng, cột, measure).
// Khuôn truy vấn tham chiếu: docs/phase-b-evidence/observe2/PA-*.dax (và observe-c1 sau buổi C1).
import DAXEngine
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

/// Phép gộp ngầm của một cột trong ô giá trị (đợt tồn đọng sau Phase F, US1). `rawValue` là mã `Aggregation.Function` Desktop lưu
/// trong PBIR; hàm DAX và tiền tố tên cột kết quả theo Performance Analyzer (VM-F10, `docs/phase-f2-evidence/vm-f10/QUAN-SAT.md`).
enum AggregateFunction: Int, CaseIterable, Hashable, Sendable {
    case sum = 0, average = 1, countDistinct = 2, min = 3, max = 4, count = 5, median = 6, standardDeviation = 7, variance = 8

    var daxFunction: String {
        switch self {
        case .sum: "SUM"
        case .average: "AVERAGE"
        case .countDistinct: "DISTINCTCOUNT"
        case .min: "MIN"
        case .max: "MAX"
        case .count: "COUNTA"
        case .median: "MEDIAN"
        case .standardDeviation: "STDEV.P"
        case .variance: "VAR.P"
        }
    }

    /// Tiền tố tên cột kết quả: `"AverageAmount"`, `"DistinctCountCustomerID"`.
    var resultPrefix: String {
        switch self {
        case .sum: "Sum"
        case .average: "Average"
        case .countDistinct: "DistinctCount"
        case .min: "Min"
        case .max: "Max"
        case .count: "Count"
        case .median: "Median"
        case .standardDeviation: "StandardDeviation"
        case .variance: "Variance"
        }
    }

    /// Nhãn hiển thị theo ngôn ngữ UI (Tiếng Việt: "Tổng của Amount", English: "Sum of Amount").
    /// Chỉ dùng hiển thị UI; `nativeQueryRef` ghi vào `.pbix` luôn bất biến theo Power BI Desktop.
    func label(column: String, kind: ColumnKind, language: ResolvedLanguage = .vi) -> String {
        switch language {
        case .vi:
            return "\(name(kind: kind, language: .vi)) của \(column)"
        case .en:
            switch (self, kind) {
            case (.min, .text): return "First \(column)"
            case (.max, .text): return "Last \(column)"
            case (.min, .date): return "Earliest \(column)"
            case (.max, .date): return "Latest \(column)"
            default: return "\(name(kind: kind, language: .en)) of \(column)"
            }
        }
    }

    /// Tên phép gộp trong menu của trường ("Tổng" / "Sum", "Đầu tiên" / "First"…).
    func name(kind: ColumnKind, language: ResolvedLanguage = .vi) -> String {
        switch language {
        case .vi:
            switch (self, kind) {
            case (.min, .text): return "Đầu tiên"
            case (.max, .text): return "Cuối cùng"
            case (.min, .date): return "Sớm nhất"
            case (.max, .date): return "Muộn nhất"
            case (.sum, _): return "Tổng"
            case (.average, _): return "Trung bình"
            case (.countDistinct, _): return "Số lượng (riêng biệt)"
            case (.min, _): return "Nhỏ nhất"
            case (.max, _): return "Lớn nhất"
            case (.count, _): return "Số lượng"
            case (.median, _): return "Trung vị"
            case (.standardDeviation, _): return "Độ lệch chuẩn"
            case (.variance, _): return "Phương sai"
            }
        case .en:
            switch (self, kind) {
            case (.min, .text): return "First"
            case (.max, .text): return "Last"
            case (.min, .date): return "Earliest"
            case (.max, .date): return "Latest"
            case (.sum, _): return "Sum"
            case (.average, _): return "Average"
            case (.countDistinct, _): return "Count (Distinct)"
            case (.min, _): return "Minimum"
            case (.max, _): return "Maximum"
            case (.count, _): return "Count"
            case (.median, _): return "Median"
            case (.standardDeviation, _): return "Standard deviation"
            case (.variance, _): return "Variance"
            }
        }
    }

    /// Nhóm kiểu cột quyết định nhãn và danh sách phép gộp (VM-F10: cột chữ chỉ có First, Last, Count (Distinct), Count).
    enum ColumnKind: Sendable {
        case number, text, date

        init(_ family: FieldRef.Family) {
            switch family {
            case .text, .boolean: self = .text
            case .date: self = .date
            case .numeric, .other: self = .number
            }
        }
    }

    /// Phép gộp khi cột vào ô giá trị (VM-F10): theo `SummarizeBy` của cột (3 Sum, 4 Min, 5 Max, 6 Count, 7 Average, 8 Distinct);
    /// cột chữ, ngày không gộp (None) thành First/Earliest (Min). [SUY ĐOÁN] Cột số đặt None thành Count.
    static func defaultFunction(for field: FieldRef) -> AggregateFunction {
        switch field.summarizeBy {
        case 3?: return .sum
        case 4?: return .min
        case 5?: return .max
        case 6?: return .count
        case 7?: return .average
        case 8?: return .countDistinct
        default: return field.family == .numeric ? .count : .min
        }
    }

    /// Nhãn tiếng Anh cho `nativeQueryRef` khi Desktop đổi tên phép gộp theo kiểu cột ("First Region"); nil: dạng "<Phép> of <cột>".
    /// [SUY ĐOÁN] dạng "First X"/"Earliest X" theo nhãn hiện trên Desktop; tệp VM-F10 chỉ có trường dời từ ô khác (giữ tên cột trần).
    func nativeQueryRef(column: String, kind: ColumnKind) -> String? {
        switch (self, kind) {
        case (.min, .text): "First \(column)"
        case (.max, .text): "Last \(column)"
        case (.min, .date): "Earliest \(column)"
        case (.max, .date): "Latest \(column)"
        default: nil
        }
    }

    /// Phép gộp trong menu của trường, theo thứ tự Desktop.
    static func menu(for kind: ColumnKind) -> [AggregateFunction] {
        switch kind {
        case .number: [.sum, .average, .min, .max, .countDistinct, .count, .standardDeviation, .variance, .median]
        // [SUY ĐOÁN] Cột ngày: Earliest, Latest, Count (Distinct), Count như cột chữ (menu cột ngày chưa mở được ở VM-F10).
        case .text, .date: [.min, .max, .countDistinct, .count]
        }
    }
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
    /// Phép gộp ngầm: `measure` là tên cột, biểu thức là `CALCULATE(<HÀM>('Bảng'[cột]))`. `nil`: measure thật.
    var aggregation: AggregateFunction? = nil
}

/// Bộ lọc theo measure của visual (Filters pane, thẻ measure): giữ các dòng mà measure thoả điều kiện.
/// Văn bản `__ValueFilterDM0` lấy từ Power BI (VM C2): xem `DAXQueryBuilder.valueFilterVariable`.
struct ValueFilter: Hashable, Sendable {
    var table: String
    var measure: String
    var rule: FilterRule
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

/// Khuôn truy vấn theo loại visual (C1.md §2.3).
enum QueryShape: Hashable, Sendable {
    /// `EVALUATE SUMMARIZECOLUMNS(lọc…, "X", IGNORE(m))`, không có `__DS0Core`.
    case card
    /// `CALCULATETABLE(VALUES(cột) | SUMMARIZE(VALUES(bảng), cột, sort), KEEPFILTERS(lọc)…)` + `TOPN(n, …)`.
    case slicer(top: Int)
    /// Bar/column/line/combo một hoặc hai trục.
    case chart
    /// `ROLLUPADDISSUBTOTAL(cột, "IsGrandTotalRowTotal")` + `TOPN(1002, …)`.
    case donut
    /// `TOPN(1002, core, [giá trị], 0, cột, 1)`.
    case treemap
    /// `FILTER(KEEPFILTERS(SUMMARIZECOLUMNS(...)), NOT(ISBLANK(cột)))` + `TOPN(3502, …)`.
    case shapeMap
    case matrix
    /// Cột chồng 100%: giảm dữ liệu động viết bằng DAX (D2-100pct).
    case hundredPercent
    /// Bảng phẳng (`tableEx`): cột danh mục + measure + dòng tổng cuối bảng.
    case table
    /// Biểu đồ phân tán (`scatterChart`): Category × Series × (X, Y, Size, Tooltips).
    case scatter
    /// Đồng hồ đo (`gauge`): 1 dòng tổng scalar (Y, MinValue, MaxValue, TargetValue).
    case gauge
    /// Chỉ số KPI (`kpi`): chuỗi Indicator (và Goal) tăng dần theo TrendLine.
    case kpi
    /// Thẻ nhiều hàng (`multiRowCard`): các cột & measure ở ô `Values` không dòng tổng.
    case multiRowCard
}

struct VisualQuerySpec: Hashable, Sendable {
    var visualID: String
    var visualType: String
    var shape: QueryShape = .chart
    /// Thứ tự nguyên gốc các trường trong ô `Values` cho `tableEx` và `multiRowCard` (cột và measure xen kẽ).
    var orderedFields: [FieldInfo] = []
    /// Trục chính: Category (chart), Rows (matrix), Values (slicer).
    var primary: [GroupField]
    /// Trục phụ: Series (chart), Columns (matrix). Rỗng nếu không có.
    var secondary: [GroupField]
    var measures: [QueryMeasure]
    var filters: [QueryFilter]
    /// Bộ lọc theo measure; mỗi bộ lọc thành một biến `__ValueFilterDMn` đứng sau các bảng lọc thường và được đưa vào lõi.
    var valueFilters: [ValueFilter] = []
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
    /// Matrix có thang màu: tên cột kết quả cần min/max qua `GROUPBY … MINX/MAXX(CURRENTGROUP())` (PA-D1-2).
    var gradientInputs: [String] = []
    /// Tô sáng chéo: bảng lọc `__H0FilterTable` (TREATAS…). Khi có, mỗi measure giá trị/tooltip kèm một cột
    /// `CALCULATE(<measure>, KEEPFILTERS(__H0FilterTable))` (C1.md §2.2).
    var highlight: QueryFilter?
    /// Mọi cấp của hierarchy ở trục danh mục (Năm › Quý › Tháng) khi có hơn một cấp, để drill. Rỗng nếu không drill được.
    var drillLevels: [GroupField] = []
    /// Slicer hierarchy: giá trị cấp gốc đang mở nút (expansionStates). Chỉ có nghĩa khi `drillLevels.count >= 2`.
    var expanded: [Value] = []
    /// Matrix: các nút cột đang mở, mỗi nút là đường giá trị từ cấp gốc ([vùng], [vùng, bang]…). Mở nút nhiều cấp.
    var expandedPaths: [[Value]] = []
    /// Matrix phân cấp hàng (Wave 3A, VM-V11B): danh sách cấp trong ô `Rows` khi có ≥ 2 trường.
    var rowDrillLevels: [GroupField] = []
    /// Matrix: các nút hàng đang mở (`expansionStates` với `roles: ["Rows"]`), mỗi nút là đường giá trị từ cấp gốc.
    var rowExpandedPaths: [[Value]] = []
    /// Số cấp cột đang hiện của matrix khi có nút mở (1 = chưa mở gì).
    var matrixColumnDepth: Int {
        guard drillLevels.count >= 2, !expandedPaths.isEmpty, secondary.count == 1 else { return 1 }
        return min(drillLevels.count, (expandedPaths.map(\.count).max() ?? 1) + 1)
    }
    /// Số cấp hàng đang hiện của matrix khi có nút hàng mở (1 = chưa mở gì).
    var matrixRowDepth: Int {
        guard rowDrillLevels.count >= 2, !rowExpandedPaths.isEmpty, primary.count == 1 else { return 1 }
        return min(rowDrillLevels.count, (rowExpandedPaths.map(\.count).max() ?? 1) + 1)
    }
    /// Tên cờ tổng của cấp cột thứ `j` khi mở nút: cấp 0 là tổng chung, các cấp sau `IsDM2Total`, `IsDM4Total`… (VM C2 b5-1, b5-2).
    static func columnFlagName(_ j: Int) -> String { j == 0 ? "IsGrandTotalColumnTotal" : "IsDM\(2 * j)Total" }
    /// Tên cờ tổng của cấp hàng thứ `j` khi mở nút hàng: cấp 0 là `IsGrandTotalRowTotal`, các cấp sau `IsDM1Total`, `IsDM3Total`…
    static func rowFlagName(_ j: Int) -> String { j == 0 ? "IsGrandTotalRowTotal" : "IsDM\(2 * j - 1)Total" }

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
