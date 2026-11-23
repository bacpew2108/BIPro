import Foundation

/// Dịch nhãn tiếng Việt cố định (Format pane, tên loại visual) sang tiếng Anh khi giao diện là English.
/// Các danh mục này (`FormatCatalog`, `VisualCatalog`) viết nhãn tiếng Việt trực tiếp và nằm trong khoá/test nên không đổi nguồn;
/// việc dịch làm ở lớp hiển thị bằng `ui(_:)`. Chuỗi không có trong bảng giữ nguyên.
enum UITranslator {
    static let table: [String: String] = [
        "Tự động": "Auto", "Ảnh": "Image", "Danh mục": "Category", "Không": "None", "Hành động": "Action", "Bật hành động": "Action on", "Loại hành động": "Action type",
        "Điều hướng trang": "Page navigation", "Dấu trang": "Bookmark", "Trang đích": "Destination page", "Mã dấu trang": "Bookmark ID",
        "Tiêu đề": "Title", "Hiện tiêu đề": "Show title", "Nội dung": "Content", "Cỡ chữ": "Text size", "Phông chữ": "Font",
        "Cấp tiêu đề": "Heading level", "Ngắt dòng": "Word wrap", "Đậm": "Bold", "Căn lề": "Alignment", "Trái": "Left", "Giữa": "Center",
        "Phải": "Right", "Màu chữ": "Font color", "Phụ đề": "Subtitle", "Hiện phụ đề": "Show subtitle", "Đường kẻ dưới tiêu đề": "Divider",
        "Hiện đường kẻ": "Show divider", "Nền": "Background", "Hiện nền": "Show background", "Màu": "Color", "Độ trong suốt (%)": "Transparency (%)",
        "Viền": "Border", "Hiện viền": "Show border", "Bo góc (px)": "Rounded corners (px)", "Độ dày (px)": "Width (px)", "Đổ bóng": "Shadow",
        "Hiện bóng": "Show shadow", "Độ nhoè (px)": "Blur (px)", "Kích thước (px)": "Size (px)", "Khoảng cách (px)": "Distance (px)", "Góc (độ)": "Angle (°)",
        "Khoảng đệm": "Padding", "Trên (px)": "Top (px)", "Dưới (px)": "Bottom (px)", "Trái (px)": "Left (px)", "Phải (px)": "Right (px)",
        "Biểu tượng tiêu đề": "Visual header icons", "Hiện biểu tượng": "Show icons", "Giá trị": "Values", "Đơn vị hiển thị": "Display units",
        "Số chữ số thập phân": "Decimal places", "Hiện nhãn": "Show label", "Ảnh thẻ": "Image", "Hiện ảnh": "Show image", "Tiêu đề slicer": "Slicer header",
        "Mục": "Items", "Khoảng đệm (px)": "Padding (px)", "Chú giải": "Legend", "Hiện chú giải": "Show legend", "Vị trí": "Position", "Dưới": "Bottom",
        "Trên": "Top", "Nhãn dữ liệu": "Data labels", "Hướng": "Orientation", "Dọc": "Vertical", "Trục Y": "Y axis", "Hiện giá trị trục": "Show axis values",
        "Hiện tiêu đề trục": "Show axis title", "Đảo trục": "Invert axis", "Làm tròn miền": "Round domain", "Nhỏ nhất": "Minimum", "Lớn nhất": "Maximum",
        "Trục X": "X axis", "Thanh thu phóng": "Zoom slider", "Hiện thanh thu phóng": "Show zoom slider", "Vùng tô và đường": "Shaded area and line",
        "Tô vùng dưới đường": "Shade area under line", "Cột và thanh": "Columns and bars", "Kiểu nhãn": "Label style", "Phần trăm tổng": "Percent of total",
        "Tiêu đề cột": "Column headers", "Lưới": "Grid", "Đệm hàng (px)": "Row padding (px)", "Nhãn giá trị": "Value labels", "Giá trị chỉ số": "Metric value",
        "Hình khối": "Shapes", "Kiểu hình": "Shape type", "Hình chữ nhật": "Rectangle", "Hình tròn / Ôvan": "Circle / Oval", "Đường thẳng": "Line",
        "Tô màu": "Fill", "Hiện màu tô": "Show fill", "Viền ngoài": "Outline", "Góc xoay (độ)": "Rotation (°)", "Tự co độ rộng cột": "Auto-size column width",
        "Tiêu đề hàng": "Row headers", "Bỏ cố định tiêu đề hàng": "Don't stick row headers", "Đường kẻ ngang": "Horizontal gridlines", "Đường kẻ dọc": "Vertical gridlines",
        "Bố cục": "Layout", "Kiểu bố cục": "Layout type", "Gọn (Compact)": "Compact", "Phác thảo (Outline)": "Outline", "Dạng bảng (Tabular)": "Tabular",
        "Tổng phụ": "Subtotals", "Tổng phụ theo hàng": "Row subtotals", "Tổng phụ theo cột": "Column subtotals", "Văn bản": "Text", "Hiện văn bản": "Show text",
        "Chưa quan sát ở Power BI Desktop": "Not yet observed in Power BI Desktop",
        "Theo chuỗi, chưa quan sát ở Power BI Desktop": "Per series, not yet observed in Power BI Desktop",
        "Định dạng riêng theo trường hoặc điểm dữ liệu, chưa sửa được": "Per-field or per-data-point formatting can't be edited yet",
        // Menu chuột phải ở pane Dữ liệu
        "Ẩn trong chế độ báo cáo": "Hide in report view", "Measure mới": "New measure", "Truy vấn nhanh": "Quick queries",
        "Hiện 100 dòng đầu": "Show top 100 rows", "Định nghĩa measure mới": "Define new measure", "Đổi tên": "Rename",
        "Xoá khỏi mô hình": "Delete from model", "Thu gọn tất cả": "Collapse all", "Mở rộng tất cả": "Expand all",
        "Sửa công thức": "Edit formula", "Đánh giá": "Evaluate", "Định nghĩa và đánh giá": "Define and evaluate",
        "Định nghĩa kèm tham chiếu và đánh giá": "Define with references and evaluate",
        "Định nghĩa mọi measure trong mô hình": "Define all measures in model", "Hiện tất cả": "Unhide all",
        "Sao chép công thức": "Copy formula", "Xem trước dữ liệu": "Preview data",
        // Tên loại visual
        "Biểu đồ thanh xếp chồng": "Stacked bar chart", "Biểu đồ cột xếp chồng": "Stacked column chart", "Biểu đồ thanh nhóm": "Clustered bar chart",
        "Biểu đồ cột nhóm": "Clustered column chart", "Thanh xếp chồng 100%": "100% stacked bar chart", "Cột xếp chồng 100%": "100% stacked column chart",
        "Biểu đồ đường": "Line chart", "Biểu đồ vùng": "Area chart", "Vùng xếp chồng": "Stacked area chart", "Vùng xếp chồng 100%": "100% stacked area chart",
        "Đường và cột xếp chồng": "Line and stacked column chart", "Đường và cột nhóm": "Line and clustered column chart", "Biểu đồ ruy băng": "Ribbon chart",
        "Biểu đồ thác nước": "Waterfall chart", "Biểu đồ phễu": "Funnel chart", "Biểu đồ phân tán": "Scatter chart", "Biểu đồ tròn": "Pie chart",
        "Biểu đồ vành khuyên": "Donut chart", "Bản đồ": "Map", "Bản đồ tô màu": "Filled map", "Bản đồ hình": "Shape map", "Đồng hồ đo": "Gauge",
        "Thẻ": "Card", "Thẻ (cũ)": "Card (legacy)", "Thẻ nhiều hàng": "Multi-row card", "Slicer nút": "Button slicer", "Slicer danh sách": "List slicer",
        "Slicer văn bản": "Text slicer", "Bảng": "Table", "Ma trận": "Matrix", "Hộp văn bản": "Text box", "Nút": "Button", "Điều hướng bookmark": "Bookmark navigator",
        "Hình": "Shape",
        // Ô (wells) và thuộc tính khác
        "Trục Y (cột)": "Column y-axis", "Trục Y (đường)": "Line y-axis", "Chú giải cột": "Column legend", "Chia nhỏ": "Small multiples",
        "Trục Y phụ": "Secondary y-axis", "Chi tiết": "Details", "Dữ liệu": "Data", "Cột": "Columns", "Hàng": "Rows", "Độ bão hoà màu": "Color saturation",
        "Chú thích công cụ": "Tooltips", "Kích thước bong bóng": "Bubble size", "Kích thước": "Size", "Trục": "Axis", "Mục tiêu": "Target",
        "Màu dữ liệu": "Data colors", "Tiêu đề phụ": "Subtitle", "Biểu tượng": "Icons", "Hình dạng": "Shape", "Co giãn ảnh": "Image scaling",
        "Kiểu đường": "Line style", "Vùng vẽ": "Plot area", "Đường lưới": "Gridlines", "Tổng": "Totals", "Kiểu mẫu": "Style presets", "Lựa chọn": "Selection",
        "Thanh trượt": "Slider", "Ngày": "Date", "Ô nhập số": "Numeric input", "Điểm đánh dấu": "Markers", "Nghiêng": "Italic", "Độ trong suốt": "Transparency",
        "Bo góc": "Rounded corners", "Độ dày": "Width", "Màu tô": "Fill color", "Màu đường": "Line color", "Kiểu": "Style", "Loại": "Type", "Co giãn": "Scaling",
        "Căn dọc": "Vertical alignment", "Căn ngang": "Horizontal alignment", "Tiêu đề trục": "Axis title", "Màu nhãn": "Label color", "Bắt đầu": "Start", "Kết thúc": "End",
    ]

    /// Bản tiếng Anh của `vi` khi giao diện là English và có trong bảng; ngược lại giữ nguyên.
    @MainActor static func ui(_ vi: String) -> String {
        guard AppPreferences.shared.effectiveLanguage == .en else { return vi }
        return table[vi] ?? vi
    }
}

@MainActor func ui(_ vi: String) -> String { UITranslator.ui(vi) }

/// Như `bi` nhưng gọi được từ ngữ cảnh không thuộc main actor (thông báo trong mô hình, trình lưu…). Đọc thẳng cài đặt ngôn ngữ.
func biN(_ vi: String, _ en: String) -> String { appPrefersEnglish() ? en : vi }

/// Ngôn ngữ đã chốt của ứng dụng, dùng ở chỗ không ở MainActor.
func appResolvedLanguage() -> ResolvedLanguage { appPrefersEnglish() ? .en : .vi }

/// `true` khi cài đặt ngôn ngữ của ứng dụng (hoặc ngôn ngữ hệ thống nếu để "Theo hệ thống") là tiếng Anh.
func appPrefersEnglish() -> Bool {
    switch UserDefaults.standard.string(forKey: "bipro.language") {
    case "en": return true
    case "vi": return false
    default: return Locale.preferredLanguages.first?.lowercased().hasPrefix("en") ?? false
    }
}
