// Hợp đồng Phase C (đợt 0, lead): dữ liệu đã sẵn sàng để vẽ.
//
// Renderer CHỈ đọc các struct ở đây cùng `VisualFormat`; renderer không biết DAX, không biết engine.
// `DataViewMapper` (lead, gói Q) chuyển `QueryResult` thành `DataView`. Dữ liệu mẫu cho worker nằm ở
// `Visuals/Fixtures/DataViewSamples.swift`.
//
// Quy ước chung:
// - Mọi danh sách đã theo đúng THỨ TỰ HIỂN THỊ (mapper đã sắp theo ORDER BY của truy vấn). Renderer không sắp lại.
// - `queryRef` là khoá ổn định của một trường, ví dụ "Dim_Date.year", "Fact_Loan.Loan Count",
//   "Dim_Date.Thời gian.Năm" (cấp hierarchy). Giống `queryRef` trong visual.json.
import DAXEngine
import Foundation

/// Một trường (cột, cấp hierarchy hoặc measure) như visual thấy.
struct FieldInfo: Hashable, Sendable {
    var queryRef: String
    /// Nhãn hiển thị (displayName trong visual.json, hoặc tên cột/measure).
    var displayName: String
    /// Vai trò trong visual: "Category", "Series", "Y", "Y2", "Values", "Tooltips", "Rows", "Columns", "Group", "Details".
    var role: String
    /// Chuỗi định dạng tĩnh của cột/measure trong model (nil nếu không có). Ô có định dạng động thì xem `DataCell.formatString`.
    var formatString: String?
    var isMeasure: Bool
}

/// Một ô giá trị đã kèm thông tin định dạng có điều kiện lấy từ measure.
struct DataCell: Hashable, Sendable {
    var value: Value
    /// Chuỗi định dạng hiệu lực của ô: định dạng động (cột `v_…_FormatString`) nếu có, không thì định dạng tĩnh.
    var formatString: String?
    /// Màu tô/chữ/icon lấy từ measure (`solid.color` = Measure), dạng "#RRGGBB". nil nếu không có.
    var fillColor: String?
    var fontColor: String?
    var backColor: String?
    /// Giá trị icon lấy từ measure (ví dụ `Peak Hour Top10 Icon`), giữ nguyên chuỗi measure trả về.
    var icon: String?

    init(_ value: Value, formatString: String? = nil, fillColor: String? = nil, fontColor: String? = nil,
         backColor: String? = nil, icon: String? = nil) {
        self.value = value
        self.formatString = formatString
        self.fillColor = fillColor
        self.fontColor = fontColor
        self.backColor = backColor
        self.icon = icon
    }

    static let blank = DataCell(.blank)
}

enum DataView: Hashable, Sendable {
    /// Không có dữ liệu để vẽ (truy vấn ra 0 dòng, hoặc visual chưa được hỗ trợ). `reason` để hiện cho người dùng.
    case empty(reason: String)
    /// Card: một giá trị.
    case single(SingleValueData)
    /// Bar/column/line/combo/donut/treemap/shape map.
    case categorical(CategoricalData)
    /// Matrix (pivotTable).
    case matrix(MatrixData)
    /// Slicer: cây giá trị.
    case slicer(SlicerData)
}

// MARK: - Card

struct SingleValueData: Hashable, Sendable {
    var measure: FieldInfo
    var cell: DataCell
}

// MARK: - Categorical

/// Một điểm trên trục danh mục. `values` có một phần tử cho mỗi cấp trong `CategoricalData.categoryLevels`
/// (khi drill/expand nhiều cấp, ví dụ [2016, "Q1"]).
struct CategoryKey: Hashable, Sendable {
    var values: [Value]
}

struct CategoricalData: Hashable, Sendable {
    /// Các cấp danh mục đang hiện (sau drill/expand). Rỗng với visual không có Category (ví dụ chỉ có Values).
    var categoryLevels: [FieldInfo]
    var categories: [CategoryKey]
    /// Trường Series/Legend (nil nếu không có).
    var seriesField: FieldInfo?
    /// Giá trị series theo thứ tự hiển thị. Rỗng khi `seriesField == nil`.
    var series: [Value]
    /// Mọi measure của visual, kể cả Tooltips; lọc theo `FieldInfo.role` khi vẽ.
    var measures: [FieldInfo]
    /// `values[m][s][c]`: measure `m`, series `s`, danh mục `c`. Khi không có series thì chiều `s` có đúng 1 phần tử.
    /// Measure không chia theo series (ví dụ đường Y2 của combo có Series, PA-D3-1) cũng có chiều `s` đúng 1 phần tử.
    /// Ô không có dữ liệu là `DataCell.blank`.
    var values: [[[DataCell]]]
    /// Tô sáng chéo: cùng kích thước với `values`. nil khi không có tô sáng.
    var highlights: [[[DataCell]]]?
    /// `true` khi dữ liệu đã bị giảm (TOPN/SAMPLE) và không đủ mọi danh mục.
    var isReduced: Bool

    var seriesCount: Int { max(1, series.count) }

    func cell(measure m: Int, series s: Int, category c: Int) -> DataCell {
        guard m < values.count, s < values[m].count, c < values[m][s].count else { return .blank }
        return values[m][s][c]
    }

    func measureIndices(role: String) -> [Int] {
        measures.indices.filter { measures[$0].role == role }
    }
}

// MARK: - Matrix

/// Một tiêu đề hàng hoặc cột của matrix, theo thứ tự hiển thị (đã trải phẳng cây).
struct MatrixHeader: Hashable, Sendable {
    /// Giá trị từ cấp 0 đến cấp `level`. Dòng tổng chung có `path == []`.
    var path: [Value]
    /// Cấp (0 là cấp ngoài cùng). Dòng tổng chung có `level == -1`.
    var level: Int
    var isSubtotal: Bool
    var isGrandTotal: Bool
    /// Nút có cấp con (hiện nút +/−).
    var hasChildren: Bool
    var isExpanded: Bool

    init(path: [Value], level: Int, isSubtotal: Bool = false, isGrandTotal: Bool = false,
         hasChildren: Bool = false, isExpanded: Bool = false) {
        self.path = path
        self.level = level
        self.isSubtotal = isSubtotal
        self.isGrandTotal = isGrandTotal
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
    }
}

struct MatrixData: Hashable, Sendable {
    var rowLevels: [FieldInfo]
    var columnLevels: [FieldInfo]
    var measures: [FieldInfo]
    var rows: [MatrixHeader]
    /// Rỗng khi matrix không có trường Columns (chỉ có các cột giá trị).
    var columns: [MatrixHeader]
    /// `cells[r][c][m]`: hàng `r`, cột `c` (0 khi `columns` rỗng), measure `m`.
    var cells: [[[DataCell]]]
    var isReduced: Bool

    var columnCount: Int { max(1, columns.count) }

    func cell(row r: Int, column c: Int, measure m: Int) -> DataCell {
        guard r < cells.count, c < cells[r].count, m < cells[r][c].count else { return .blank }
        return cells[r][c][m]
    }
}

// MARK: - Slicer

struct SlicerNode: Hashable, Sendable {
    var value: Value
    var children: [SlicerNode]

    init(_ value: Value, children: [SlicerNode] = []) {
        self.value = value
        self.children = children
    }
}

struct SlicerData: Hashable, Sendable {
    /// Một cấp cho mỗi trường trong Values của slicer (ví dụ Năm › Quý › Tháng).
    var levels: [FieldInfo]
    var roots: [SlicerNode]
}
