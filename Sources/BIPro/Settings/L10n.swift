import Foundation

/// Từ điển song ngữ Tiếng Việt / English cho toàn bộ giao diện người dùng BI Pro.
/// Tuyệt đối không được gọi từ tầng ghi `.pbix` (`PBIXKit`, `PBIR*Patch`, `SourceQuery`, `DAXEngine`, `MEngine`).
enum L10n {
    enum Key: String, CaseIterable, Sendable {
        // MARK: - Title bar & Shell
        case untitledDocument
        case statusDirtyBadge
        case statusEditBadge
        case statusViewBadge
        case statusDirtyHelp
        case statusViewHelp
        case searchPlaceholder
        case searchNoResultsFormat
        case searchHitPage
        case searchHitTable
        case searchHitMeasureFormat
        case searchHitColumnFormat
        case searchHitVisualFormat
        case statusNoModel
        case statusVertiPaqReadyFormat

        // MARK: - Workspace modes
        case modeReport
        case modeTable
        case modeModel
        case modeDAX
        case modeTMDL

        // MARK: - Export menu & sheet
        case exportMenu
        case exportHelp
        case exportPDFItem
        case exportPNGItem
        case exportCSVItem
        case exportCSVContextMenu
        case exportCSVDisabledNoSelection
        case exportCSVDisabledNoData
        case exportPDFTitle
        case exportPNGTitle
        case exportScopeLabel
        case exportScopeAllVisible
        case exportScopeCurrentPage
        case exportScaleLabel
        case exportScale1x
        case exportScale2x
        case exportProgressRenderingPageFormat
        case exportProgressPreparing
        case exportActionButton
        case exportErrorTitle
        case exportNoVisiblePages

        // MARK: - Menus & Commands
        case menuNew
        case menuOpen
        case menuOpenRecent
        case menuClearRecent
        case menuClose
        case menuSave
        case menuSaveAs
        case menuFileOptions
        case menuExport
        case menuEditMode
        case menuUndo
        case menuRedo
        case menuDuplicate
        case menuDelete
        case menuGroup
        case menuUngroup
        case menuShowOnboarding

        // MARK: - Ribbon & Panes
        case ribbonHome
        case ribbonInsert
        case ribbonArrange
        case ribbonView
        case ribbonColumnTools
        case ribbonTableTools
        case ribbonGetData
        case ribbonExcel
        case ribbonEnterData
        case ribbonTransformData
        case ribbonNewVisual
        case ribbonTextBox
        case ribbonNewMeasure
        case ribbonNewColumn
        case ribbonNewTable
        case ribbonManageRelationships
        case ribbonNewPage
        case ribbonExportTMDL
        case ribbonRunQuery
        case ribbonApply
        case paneFilters
        case paneVisualizations
        case paneData
        case paneSelection
        case paneBookmarks
        case paneBuild
        case paneFormat
        case zoomFit
        case zoomIn
        case zoomOut
        case editModeSwitchView
        case editModeSwitchEdit
        case addPage

        // MARK: - Settings
        case settingsTitle
        case settingsTooltip
        case settingsTabGeneral
        case settingsTabEditing
        case settingsTabData
        case settingsAppearanceLabel
        case settingsAppearanceSystem
        case settingsAppearanceLight
        case settingsAppearanceDark
        case settingsLanguageLabel
        case settingsLanguageSystem
        case settingsLanguageVi
        case settingsLanguageEn
        case settingsLanguageNote
        case settingsOnboardingLabel
        case settingsShowOnboardingButton
        case settingsSnapToGridLabel
        case settingsSnapToGridHelp
        case settingsGridSizeLabel
        case settingsGridSizeFormat
        case settingsSQLiteDriverLabel
        case settingsSQLiteDriverHelp
        case settingsBackupFolderLabel
        case settingsOpenInFinder
        case settingsResetDefaults

        // MARK: - Onboarding
        case onboardingWindowTitle
        case onboardingBadge
        case onboardingSkip
        case onboardingBack
        case onboardingNext
        case onboardingStart
        case onboardingStepIndicatorFormat
        case onboardingStep1Title
        case onboardingStep1Body
        case onboardingStep2Title
        case onboardingStep2Body
        case onboardingStep3Title
        case onboardingStep3Body

        // MARK: - Common dialogs & actions
        case cancel
        case close
        case done
        case save
        case ok
        case addDataTitle
        case addDataSubtitle
        case canvasHintTitle
        case canvasHintSubtitle
        case fileOptionsTitle
        case autoDateTimeLabel
        case autoDetectRelLabel

        // MARK: - Implicit aggregation labels (UI only — never written to PBIR nativeQueryRef)
        case aggSumOfFormat
        case aggAverageOfFormat
        case aggMinOfFormat
        case aggMaxOfFormat
        case aggCountOfFormat
        case aggDistinctCountOfFormat

        // MARK: - Accessibility & Announcements
        case a11yRailSettings
        case a11yCollapsePaneFormat
        case a11yExpandPaneFormat
        case a11yPageTabFormat
        case a11ySelected
        case a11yHidden
        case a11yVisible
        case a11yTable
        case a11yColumn
        case a11yMeasure
        case a11yHierarchy
        case a11yAnnouncementPageChangedFormat
        case a11yAnnouncementEditModeOn
        case a11yAnnouncementEditModeOff
        case a11yAnnouncementSavedFormat
        case a11yAnnouncementExportedFormat
        case a11yVisualHint
        case a11yVisualDataEmpty
        case a11yVisualCategoriesFormat
        case a11yVisualMatrixFormat
        case a11yVisualSlicerAll
        case a11yVisualSlicerSelectedFormat
        case a11yVisualTypeCard
        case a11yVisualTypeBarChart
        case a11yVisualTypeColumnChart
        case a11yVisualTypeLineChart
        case a11yVisualTypeComboChart
        case a11yVisualTypeAreaChart
        case a11yVisualTypeDonutChart
        case a11yVisualTypePieChart
        case a11yVisualTypeScatterChart
        case a11yVisualTypeGauge
        case a11yVisualTypeKPI
        case a11yVisualTypeMultiRowCard
        case a11yVisualTypeMap
        case a11yVisualTypeTreemap
        case a11yVisualTypeShapeMap
        case a11yVisualTypeRibbonChart
        case a11yVisualTypeWaterfallChart
        case a11yVisualTypeFunnel
        case a11yVisualTypeMatrix
        case a11yVisualTypeTable
        case a11yVisualTypeSlicer
        case a11yVisualTypeTextbox
        case a11yVisualTypeImage
        case a11yVisualTypeShape
        case a11yVisualTypeButton
        case a11yVisualTypeGeneric
    }

    static func entry(for key: Key) -> (vi: String, en: String) {
        switch key {
        // Title bar & Shell
        case .untitledDocument: ("Không tên.pbix", "Untitled.pbix")
        case .statusDirtyBadge: ("Chưa lưu", "Unsaved")
        case .statusEditBadge: ("Đang sửa", "Editing")
        case .statusViewBadge: ("Xem", "View")
        case .statusDirtyHelp: ("Có thay đổi chưa lưu (⌘S)", "Unsaved changes (⌘S)")
        case .statusViewHelp: ("Bật Sửa (⌘E) để kéo, đổi cỡ visual", "Toggle Edit mode (⌘E) to move or resize visuals")
        case .searchPlaceholder: ("Tìm trang, bảng, measure, visual…", "Search pages, tables, measures, visuals…")
        case .searchNoResultsFormat: ("Không tìm thấy “%@”", "No results for “%@”")
        case .searchHitPage: ("Trang", "Page")
        case .searchHitTable: ("Bảng", "Table")
        case .searchHitMeasureFormat: ("Measure · %@", "Measure · %@")
        case .searchHitColumnFormat: ("Cột · %@", "Column · %@")
        case .searchHitVisualFormat: ("Visual %@ · %@", "%@ visual · %@")
        case .statusNoModel: ("Không có mô hình dữ liệu", "No data model")
        case .statusVertiPaqReadyFormat: ("VertiPaq: sẵn sàng (%@ dòng)", "VertiPaq: ready (%@ rows)")

        // Workspace modes
        case .modeReport: ("Báo cáo", "Report")
        case .modeTable: ("Bảng dữ liệu", "Table")
        case .modeModel: ("Mô hình", "Model")
        case .modeDAX: ("Truy vấn DAX", "DAX Query")
        case .modeTMDL: ("TMDL", "TMDL")

        // Export
        case .exportMenu: ("Xuất", "Export")
        case .exportHelp: ("Xuất báo cáo ra PDF, PNG hoặc xuất dữ liệu visual ra CSV", "Export report to PDF, PNG, or export visual data to CSV")
        case .exportPDFItem: ("PDF…", "PDF…")
        case .exportPNGItem: ("Ảnh PNG của trang…", "Page PNG Image…")
        case .exportCSVItem: ("Dữ liệu visual ra CSV…", "Visual Data to CSV…")
        case .exportCSVContextMenu: ("Xuất dữ liệu ra CSV…", "Export Data to CSV…")
        case .exportCSVDisabledNoSelection: ("Chọn một visual có dữ liệu để xuất CSV", "Select a data visual to export CSV")
        case .exportCSVDisabledNoData: ("Visual này không có dữ liệu dạng bảng để xuất", "This visual has no tabular data to export")
        case .exportPDFTitle: ("Xuất báo cáo ra PDF", "Export Report to PDF")
        case .exportPNGTitle: ("Xuất ảnh PNG của trang", "Export Page to PNG")
        case .exportScopeLabel: ("Phạm vi trang", "Page scope")
        case .exportScopeAllVisible: ("Tất cả trang hiển thị", "All visible pages")
        case .exportScopeCurrentPage: ("Trang hiện tại", "Current page")
        case .exportScaleLabel: ("Độ phân giải", "Resolution")
        case .exportScale1x: ("1× (Chuẩn)", "1× (Standard)")
        case .exportScale2x: ("2× (Retina)", "2× (Retina)")
        case .exportProgressRenderingPageFormat: ("Đang kết xuất trang %d/%d…", "Rendering page %d/%d…")
        case .exportProgressPreparing: ("Đang nạp dữ liệu các visual…", "Loading visual data…")
        case .exportActionButton: ("Xuất…", "Export…")
        case .exportErrorTitle: ("Không xuất được tệp", "Export Failed")
        case .exportNoVisiblePages: ("Báo cáo không có trang hiển thị nào để xuất.", "This report has no visible pages to export.")

        // Menus & Commands
        case .menuNew: ("Mới", "New")
        case .menuOpen: ("Mở…", "Open…")
        case .menuOpenRecent: ("Mở gần đây", "Open Recent")
        case .menuClearRecent: ("Xoá danh sách", "Clear Menu")
        case .menuClose: ("Đóng", "Close")
        case .menuSave: ("Lưu", "Save")
        case .menuSaveAs: ("Lưu thành…", "Save As…")
        case .menuFileOptions: ("Tuỳ chọn tệp…", "File Options…")
        case .menuExport: ("Xuất", "Export")
        case .menuEditMode: ("Chế độ Sửa", "Edit Mode")
        case .menuUndo: ("Hoàn tác", "Undo")
        case .menuRedo: ("Làm lại", "Redo")
        case .menuDuplicate: ("Nhân bản", "Duplicate")
        case .menuDelete: ("Xoá", "Delete")
        case .menuGroup: ("Nhóm", "Group")
        case .menuUngroup: ("Bỏ nhóm", "Ungroup")
        case .menuShowOnboarding: ("Hướng dẫn bắt đầu…", "Welcome Guide…")

        // Ribbon & Panes
        case .ribbonHome: ("Trang chủ", "Home")
        case .ribbonInsert: ("Chèn", "Insert")
        case .ribbonArrange: ("Sắp xếp", "Arrange")
        case .ribbonView: ("Xem", "View")
        case .ribbonColumnTools: ("Công cụ cột", "Column tools")
        case .ribbonTableTools: ("Công cụ bảng", "Table tools")
        case .ribbonGetData: ("Lấy dữ liệu", "Get data")
        case .ribbonExcel: ("Excel", "Excel")
        case .ribbonEnterData: ("Nhập dữ liệu", "Enter data")
        case .ribbonTransformData: ("Biến đổi dữ liệu", "Transform data")
        case .ribbonNewVisual: ("Visual mới", "New visual")
        case .ribbonTextBox: ("Hộp văn bản", "Text box")
        case .ribbonNewMeasure: ("Measure mới", "New measure")
        case .ribbonNewColumn: ("Cột mới", "New column")
        case .ribbonNewTable: ("Bảng mới", "New table")
        case .ribbonManageRelationships: ("Quản lý quan hệ", "Manage relationships")
        case .ribbonNewPage: ("Trang mới", "New page")
        case .ribbonExportTMDL: ("Xuất TMDL…", "Export TMDL…")
        case .ribbonRunQuery: ("Chạy", "Run")
        case .ribbonApply: ("Áp dụng", "Apply")
        case .paneFilters: ("Bộ lọc", "Filters")
        case .paneVisualizations: ("Hình ảnh", "Visualizations")
        case .paneData: ("Dữ liệu", "Data")
        case .paneSelection: ("Lựa chọn", "Selection")
        case .paneBookmarks: ("Dấu trang", "Bookmarks")
        case .paneBuild: ("Xây dựng", "Build")
        case .paneFormat: ("Định dạng", "Format")
        case .zoomFit: ("Vừa khung", "Fit to page")
        case .zoomIn: ("Phóng to", "Zoom in")
        case .zoomOut: ("Thu nhỏ", "Zoom out")
        case .editModeSwitchView: ("Xem", "View")
        case .editModeSwitchEdit: ("Sửa", "Edit")
        case .addPage: ("Thêm trang", "Add page")

        // Settings
        case .settingsTitle: ("Cài đặt", "Settings")
        case .settingsTooltip: ("Cài đặt (⌘,)", "Settings (⌘,)")
        case .settingsTabGeneral: ("Chung", "General")
        case .settingsTabEditing: ("Chỉnh sửa", "Editing")
        case .settingsTabData: ("Dữ liệu & Sao lưu", "Data & Backup")
        case .settingsAppearanceLabel: ("Giao diện", "Appearance")
        case .settingsAppearanceSystem: ("Theo hệ thống", "System")
        case .settingsAppearanceLight: ("Sáng", "Light")
        case .settingsAppearanceDark: ("Tối", "Dark")
        case .settingsLanguageLabel: ("Ngôn ngữ", "Language")
        case .settingsLanguageSystem: ("Theo hệ thống", "System")
        case .settingsLanguageVi: ("Tiếng Việt", "Tiếng Việt")
        case .settingsLanguageEn: ("English", "English")
        case .settingsLanguageNote: ("Đổi ngôn ngữ áp dụng ngay cho giao diện và không làm thay đổi cấu trúc tệp .pbix khi lưu.", "Changing language updates the UI immediately and never alters saved .pbix files.")
        case .settingsOnboardingLabel: ("Hướng dẫn lần đầu", "Welcome Guide")
        case .settingsShowOnboardingButton: ("Xem lại hướng dẫn", "Show Welcome Guide")
        case .settingsSnapToGridLabel: ("Bám lưới mặc định khi kéo/đổi cỡ", "Snap to grid by default")
        case .settingsSnapToGridHelp: ("Giữ phím Option (⌥) khi kéo trên canvas để tạm bỏ bám lưới.", "Hold Option (⌥) while dragging to temporarily disable snapping.")
        case .settingsGridSizeLabel: ("Cỡ lưới", "Grid size")
        case .settingsGridSizeFormat: ("%d px", "%d px")
        case .settingsSQLiteDriverLabel: ("Driver ODBC SQLite mặc định", "Default SQLite ODBC Driver")
        case .settingsSQLiteDriverHelp: ("Tên driver ghi vào chuỗi kết nối M để Power BI Desktop trên Windows làm mới được tệp SQLite.", "Driver name written to M connection strings so Power BI Desktop on Windows can refresh SQLite files.")
        case .settingsBackupFolderLabel: ("Thư mục sao lưu tự động", "Automatic Backup Folder")
        case .settingsOpenInFinder: ("Mở trong Finder", "Open in Finder")
        case .settingsResetDefaults: ("Khôi phục mặc định", "Reset to Defaults")

        // Onboarding
        case .onboardingWindowTitle: ("Chào mừng đến với BI Pro", "Welcome to BI Pro")
        case .onboardingBadge: ("BI Pro v1.3 · macOS Native", "BI Pro v1.3 · macOS Native")
        case .onboardingSkip: ("Bỏ qua", "Skip")
        case .onboardingBack: ("Quay lại", "Back")
        case .onboardingNext: ("Tiếp theo", "Next")
        case .onboardingStart: ("Bắt đầu", "Get Started")
        case .onboardingStepIndicatorFormat: ("Bước %d / %d", "Step %d of %d")
        case .onboardingStep1Title: ("Mở & tạo báo cáo .pbix gốc", "Open & Create Native .pbix Reports")
        case .onboardingStep1Body: ("Đọc trực tiếp mô hình VertiPaq, chạy DAX, nạp dữ liệu từ Excel, CSV, JSON, SQLite, Parquet và PostgreSQL mà không cần cài thêm phần mềm trung gian.", "Read VertiPaq models directly, evaluate DAX, and load data from Excel, CSV, JSON, SQLite, Parquet, and PostgreSQL natively on Apple Silicon.")
        case .onboardingStep2Title: ("Xem, Sửa (⌘E) và 5 không gian làm việc", "View, Edit (⌘E) & Five Workspaces")
        case .onboardingStep2Body: ("Chuyển nhanh giữa Báo cáo, Bảng dữ liệu, Mô hình, Truy vấn DAX và TMDL trên thanh trái. Nhấn ⌘E để kéo thả visual, chỉnh trường, định dạng, bộ lọc và dấu trang.", "Switch between Report, Table, Model, DAX Query, and TMDL on the left rail. Press ⌘E to edit layouts, fields, formatting, filters, and bookmarks.")
        case .onboardingStep3Title: ("Lưu an toàn & Xuất PDF / PNG / CSV", "Safe Saving & Export to PDF / PNG / CSV")
        case .onboardingStep3Body: ("Tệp .pbix lưu ra mở lại mượt trên Power BI Desktop, tự sao lưu trước khi ghi đè và không bao giờ sửa tệp gốc trong Downloads. Xuất nhanh báo cáo sang PDF, PNG 2× hoặc CSV.", "Saved .pbix files remain compatible with Power BI Desktop, with automatic backups and read-only protection for Downloads. Export pages to PDF, 2× PNG, or visual data to CSV.")

        // Common dialogs & actions
        case .cancel: ("Huỷ", "Cancel")
        case .close: ("Đóng", "Close")
        case .done: ("Xong", "Done")
        case .save: ("Lưu", "Save")
        case .ok: ("Đồng ý", "OK")
        case .addDataTitle: ("Thêm dữ liệu vào báo cáo", "Add data to your report")
        case .addDataSubtitle: ("Chọn một nguồn dữ liệu để bắt đầu dựng mô hình và biểu đồ.", "Choose a data source to start building your model and visuals.")
        case .canvasHintTitle: ("Dựng visual từ dữ liệu", "Build visuals with your data")
        case .canvasHintSubtitle: ("Chọn hoặc kéo trường từ ngăn Dữ liệu vào trang báo cáo.", "Select or drag fields from the Data pane onto the report canvas.")
        case .fileOptionsTitle: ("Tuỳ chọn tệp", "File Options")
        case .autoDateTimeLabel: ("Ngày/giờ tự động (Auto date/time)", "Auto date/time")
        case .autoDetectRelLabel: ("Tự phát hiện quan hệ khi nạp dữ liệu", "Autodetect new relationships after data is loaded")

        // Aggregations
        case .aggSumOfFormat: ("Tổng của %@", "Sum of %@")
        case .aggAverageOfFormat: ("Trung bình của %@", "Average of %@")
        case .aggMinOfFormat: ("Nhỏ nhất của %@", "Min of %@")
        case .aggMaxOfFormat: ("Lớn nhất của %@", "Max of %@")
        case .aggCountOfFormat: ("Số lượng của %@", "Count of %@")
        case .aggDistinctCountOfFormat: ("Số giá trị duy nhất của %@", "Count (Distinct) of %@")

        // Accessibility
        case .a11yRailSettings: ("Cài đặt ứng dụng", "Application Settings")
        case .a11yCollapsePaneFormat: ("Thu gọn ngăn %@", "Collapse %@ pane")
        case .a11yExpandPaneFormat: ("Mở ngăn %@", "Expand %@ pane")
        case .a11yPageTabFormat: ("Trang %@", "Page %@")
        case .a11ySelected: ("Đang chọn", "Selected")
        case .a11yHidden: ("Đang ẩn", "Hidden")
        case .a11yVisible: ("Đang hiện", "Visible")
        case .a11yTable: ("Bảng", "Table")
        case .a11yColumn: ("Cột", "Column")
        case .a11yMeasure: ("Measure", "Measure")
        case .a11yHierarchy: ("Phân cấp", "Hierarchy")
        case .a11yAnnouncementPageChangedFormat: ("Đã chuyển sang trang %@", "Switched to page %@")
        case .a11yAnnouncementEditModeOn: ("Đã bật chế độ Sửa", "Edit mode enabled")
        case .a11yAnnouncementEditModeOff: ("Đã chuyển về chế độ Xem", "View mode enabled")
        case .a11yAnnouncementSavedFormat: ("Đã lưu %@", "Saved %@")
        case .a11yAnnouncementExportedFormat: ("Đã xuất %@", "Exported %@")
        case .a11yVisualHint: ("Bấm để chọn hoặc lọc chéo", "Click to select or cross-filter")
        case .a11yVisualDataEmpty: ("Không có dữ liệu", "No data")
        case .a11yVisualCategoriesFormat: ("%d danh mục, %d chuỗi", "%d categories, %d series")
        case .a11yVisualMatrixFormat: ("%d hàng, %d cột", "%d rows, %d columns")
        case .a11yVisualSlicerAll: ("Tất cả", "All")
        case .a11yVisualSlicerSelectedFormat: ("Đã chọn %d mục", "%d selected")
        case .a11yVisualTypeCard: ("Thẻ số liệu", "Card")
        case .a11yVisualTypeBarChart: ("Biểu đồ thanh", "Bar chart")
        case .a11yVisualTypeColumnChart: ("Biểu đồ cột", "Column chart")
        case .a11yVisualTypeLineChart: ("Biểu đồ đường", "Line chart")
        case .a11yVisualTypeComboChart: ("Biểu đồ kết hợp", "Combo chart")
        case .a11yVisualTypeAreaChart: ("Biểu đồ vùng", "Area chart")
        case .a11yVisualTypeDonutChart: ("Biểu đồ vòng", "Donut chart")
        case .a11yVisualTypePieChart: ("Biểu đồ tròn", "Pie chart")
        case .a11yVisualTypeScatterChart: ("Biểu đồ phân tán", "Scatter chart")
        case .a11yVisualTypeGauge: ("Đồng hồ đo", "Gauge")
        case .a11yVisualTypeKPI: ("Chỉ số KPI", "KPI")
        case .a11yVisualTypeMultiRowCard: ("Thẻ nhiều hàng", "Multi-row card")
        case .a11yVisualTypeMap: ("Bản đồ", "Map")
        case .a11yVisualTypeTreemap: ("Biểu đồ cây", "Treemap")
        case .a11yVisualTypeShapeMap: ("Bản đồ hình", "Shape map")
        case .a11yVisualTypeRibbonChart: ("Biểu đồ ruy-băng", "Ribbon chart")
        case .a11yVisualTypeWaterfallChart: ("Biểu đồ thác nước", "Waterfall chart")
        case .a11yVisualTypeFunnel: ("Biểu đồ phễu", "Funnel chart")
        case .a11yVisualTypeMatrix: ("Ma trận", "Matrix")
        case .a11yVisualTypeTable: ("Bảng", "Table")
        case .a11yVisualTypeSlicer: ("Bộ cắt lọc", "Slicer")
        case .a11yVisualTypeTextbox: ("Hộp văn bản", "Text box")
        case .a11yVisualTypeImage: ("Hình ảnh", "Image")
        case .a11yVisualTypeShape: ("Hình khối", "Shape")
        case .a11yVisualTypeButton: ("Nút hành động", "Action button")
        case .a11yVisualTypeGeneric: ("Visual", "Visual")
        }
    }

    static func string(_ key: Key, language: ResolvedLanguage) -> String {
        let pair = entry(for: key)
        return language == .en ? pair.en : pair.vi
    }

    static func format(_ key: Key, language: ResolvedLanguage, _ args: CVarArg...) -> String {
        String(format: string(key, language: language), locale: Locale(identifier: language == .en ? "en_US" : "vi_VN"), arguments: args)
    }
}

/// Hàm tiện ích cho SwiftUI `@MainActor`: tự động đọc ngôn ngữ đang chọn trong `AppPreferences.shared`.
@MainActor
func tr(_ key: L10n.Key) -> String {
    L10n.string(key, language: AppPreferences.shared.effectiveLanguage)
}

@MainActor
func trf(_ key: L10n.Key, _ args: CVarArg...) -> String {
    String(format: L10n.string(key, language: AppPreferences.shared.effectiveLanguage),
           locale: Locale(identifier: AppPreferences.shared.effectiveLanguage == .en ? "en_US" : "vi_VN"),
           arguments: args)
}

/// Tiện ích song ngữ gọn cho nhãn UI phụ (Ribbon, Dialog, Pane) tự đổi ngay khi `AppPreferences.shared.language` thay đổi.
@MainActor
func bi(_ vi: String, _ en: String) -> String {
    AppPreferences.shared.effectiveLanguage == .en ? en : vi
}
