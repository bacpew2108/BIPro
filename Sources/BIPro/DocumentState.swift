import ColumnStore
import AppKit
import Observation
import PBIXKit
import SwiftUI
import UniformTypeIdentifiers

/// The five workspaces on the left rail.
enum WorkspaceMode: String, CaseIterable, Identifiable {
    case report, table, model, daxQuery, tmdl
    var id: String { rawValue }

    var title: String {
        switch self {
        case .report: "Báo cáo"
        case .table: "Bảng"
        case .model: "Mô hình"
        case .daxQuery: "Truy vấn DAX"
        case .tmdl: "TMDL"
        }
    }

    @MainActor
    var localizedTitle: String {
        switch self {
        case .report: tr(.modeReport)
        case .table: tr(.modeTable)
        case .model: tr(.modeModel)
        case .daxQuery: tr(.modeDAX)
        case .tmdl: tr(.modeTMDL)
        }
    }

    var symbol: String {
        switch self {
        case .report: "chart.bar.xaxis"
        case .table: "tablecells"
        case .model: "point.3.connected.trianglepath.dotted"
        case .daxQuery: "terminal"
        case .tmdl: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum RibbonTab: String, Identifiable {
    case file, home, insert, modeling, design, view, optimize, help, format, dataDrill, tableTools, columnTools
    var id: String { rawValue }

    var tabID: RibbonTabID {
        RibbonTabID(rawValue: rawValue) ?? .home
    }

    init(tabID: RibbonTabID) {
        self = RibbonTab(rawValue: tabID.rawValue) ?? .home
    }

    var title: String {
        tabID.title.vi
    }

    @MainActor
    var localizedTitle: String {
        tabID.title.localized
    }

    /// Contextual tabs are tinted, as in the design.
    var isContextual: Bool { tabID.isContextual }
}

/// Per-window UI state.
@MainActor
@Observable
final class DocumentState {
    let workspace: Workspace
    let fileName: String
    /// File đang mở (nil nếu không biết). Dùng khi lưu.
    let fileURL: URL?
    /// Dấu vết của file lúc mở hoặc lúc lưu gần nhất, để phát hiện file bị đổi ngoài app.
    var openedStamp: FileStamp?
    /// Cửa sổ chứa tài liệu (đặt bởi `DocumentWindowBridge`).
    @ObservationIgnored weak var window: NSWindow?
    /// Chỉ báo cáo định dạng PBIR sửa được bố cục (`Report/definition/**`); định dạng cũ (`Report/Layout`) chưa hỗ trợ.
    var canEditLayout: Bool { workspace.pbix.reportFormat == .pbir }
    /// Sửa được bố cục trên canvas: PBIR, và báo cáo định dạng cũ (D7: chỉ di chuyển, đổi cỡ, căn, xoá, nhân bản, chép dán).
    var canEditCanvas: Bool { workspace.pbix.reportFormat == .pbir || workspace.pbix.reportFormat == .legacyLayout }
    /// Bố cục sửa được của báo cáo (D1). `page` trả về trang đã áp phần sửa.
    let layout: LayoutEditor
    /// Chế độ Sửa (⌘E): kéo thả visual. Mặc định là Xem: lọc chéo, drill như trước.
    /// Vùng trang đang nhìn thấy trong canvas (toạ độ trang); nil = cả trang. Dùng khi thêm visual mới (D3).
    var visibleRect: CGRect?
    /// Chế độ Sửa (⌘E): mặc định bật như Power BI Desktop (Phase H / R-02), trừ khi người dùng bật `viewOnlyDefault`.
    var editMode = true {
        didSet {
            if !editMode { layout.clearSelection(); if visualID != nil { visualID = nil } }
            if editMode != oldValue {
                AccessibilityAnnouncer.announce(tr(editMode ? .a11yAnnouncementEditModeOn : .a11yAnnouncementEditModeOff))
            }
        }
    }
    /// Trạng thái lọc/tương tác và nạp dữ liệu của các visual trong báo cáo (gói G).
    let interaction: ReportInteraction

    // Export sheet state (Phase G, US1)
    var exportSheetKind: ExportSheetKind?
    var isExporting = false
    var exportProgress = ""
    var exportError: String?

    var mode: WorkspaceMode = .report {
        didSet {
            let resolved = RibbonCatalog.resolvedTab(ribbonTab.tabID, mode: mode, visualSelected: visual != nil)
            ribbonTab = RibbonTab(tabID: resolved)
            UserDefaults.standard.set(mode.rawValue, forKey: "lastWorkspace")
        }
    }
    var ribbonTab: RibbonTab = .home
    /// Mở màn hình File backstage (US7); tab `.file` bật cờ này thay vì hiện Ribbon.
    var showBackstage = false

    func selectRibbonTab(_ tab: RibbonTab) {
        if tab == .file {
            showBackstage = true
            return
        }
        showBackstage = false
        let resolved = RibbonCatalog.resolvedTab(tab.tabID, mode: mode, visualSelected: visual != nil)
        ribbonTab = RibbonTab(tabID: resolved)
    }

    // Report
    var pageID: String? {
        didSet {
            if pageID != oldValue {
                layout.showPage(pageID)
                if let name = page?.displayName, oldValue != nil {
                    AccessibilityAnnouncer.announce(trf(.a11yAnnouncementPageChangedFormat, name))
                }
            }
        }
    }
    var visualID: String? {
        didSet {
            if visualID == nil, ribbonTab.isContextual, mode == .report { ribbonTab = .home }
            // Giữ vùng chọn của bộ sửa khớp với visual chọn từ bên ngoài (Selection pane, chế độ Xem).
            if visualID != layout.primary {
                if let visualID { layout.select(visualID) } else { layout.clearSelection() }
            }
        }
    }
    var zoom: Double? // nil = fit page (hoặc fit width khi `fitsWidth`)
    /// Với `zoom == nil`: `true` = vừa chiều rộng (trang cuộn dọc), `false` = vừa cả trang. Mọi nơi đặt `zoom` đều đặt lại về vừa trang.
    var fitsWidth = false
    /// Tỉ lệ đang vẽ thật của trang (để thanh trạng thái ghi đúng % khi `zoom == nil`).
    var renderedScale: Double = 1
    var showFilters = true
    var showVisualizations = true
    var showData = true
    var showSelection = false
    var showBookmarks = false
    /// Trạng thái thu gọn pane theo cửa sổ (Phase H / US5, không lưu). Filters thu gọn mặc định như Desktop.
    var filtersCollapsed = true
    var visualizationsCollapsed = false
    var dataCollapsed = false
    enum PaneKind: Hashable { case filters, visualizations, data }
    private var paneWidths: [PaneKind: CGFloat] = [
        .filters: UIMetrics.pane,
        .visualizations: UIMetrics.pane,
        .data: UIMetrics.pane,
    ]
    func paneWidth(for kind: PaneKind) -> CGFloat { paneWidths[kind] ?? UIMetrics.pane }
    func setPaneWidth(_ width: CGFloat, for kind: PaneKind) {
        paneWidths[kind] = min(320, max(160, width))
    }
    var visualizationsTab: VisualizationsTab = .build

    /// Tên chủ đề đang áp dụng (Wave 3B: chủ đề mới chọn trong phiên hoặc chủ đề gốc của báo cáo).
    var currentThemeName: String? {
        layout.customTheme?.name ?? workspace.sessionCustomThemeName ?? workspace.report.customThemeName
    }

    /// Áp dụng chủ đề JSON cho toàn báo cáo (Wave 3B): đổi màu live + ghi undoable vào `LayoutEditor`.
    func applyTheme(name: String, data: Data) {
        guard workspace.applySessionTheme(name: name, data: data) else { return }
        layout.setCustomTheme(name: name, data: data)
        interaction.modelVersion += 1
    }

    // Table / model
    var table: String?
    var column: String?
    /// Measure đang chọn ở Table/Model view (Phase E); `column` là nil khi chọn measure.
    var measure: String?
    /// Bản nháp công thức measure đang sửa ở thanh công thức (Phase E).
    var measureDraft: MeasureDraft?
    /// Đề xuất quan hệ mới đang chờ xác nhận (kéo cột thả lên cột ở Model view, Phase E).
    var relationshipDraft: RelationshipDraft?
    /// Thông báo gần nhất về việc tạo hoặc xoá quan hệ (lý do bị từ chối), nil khi không có.
    var relationshipNotice: String?
    var relationship: String?
    var diagramName: String?
    var modelZoom: Double = 0.85
    var layoutRevision = 0
    /// Tăng mỗi khi mô hình hiệu lực đổi (sửa, hoàn tác, làm lại); view và visual đọc nó để vẽ lại (Phase E).
    private(set) var modelVersion = 0
    /// Hộp thoại Get Data đang mở (Phase F); nil khi đóng.
    var getDataState: NavigatorState?
    /// Cửa sổ Query Editor đang mở (Phase F, T060); nil khi đóng.
    var queryEditorState: QueryEditorState?
    /// Hộp "Tạo bảng" (Enter Data) đang mở (đợt tồn đọng sau Phase F, T028); nil khi đóng.
    var enterData: EnterDataTable?
    /// Hộp "Tuỳ chọn tệp" đang mở (T033).
    var showFileOptions = false
    /// Tiến trình Làm mới dữ liệu (Wave 3C / T019); nil khi đóng.
    var refreshProgress: RefreshProgressState? = nil
    /// Yêu cầu xác nhận Đổi tên lan truyền (Wave 3C / T020); nil khi đóng.
    var pendingCascadeRename: CascadeRenameTarget? = nil
    /// Wave 4 (v1.2): các hộp thoại Ribbon mới mở khoá (Show as a table, Quick Measure, Mark as Date Table, RLS, DAX Update Model).
    var showDataTableVisualID: String? = nil
    var showQuickMeasureSheet = false
    var showMarkDateTableSheet = false
    var showManageRolesSheet = false
    var showManageRelationshipsSheet = false
    var showViewAsRoleSheet = false
    var pendingDAXModelUpdates: [DAXDefinedMeasure]? = nil
    /// Trạng thái đồng bộ nút "Áp dụng thay đổi" trên TMDL Ribbon với `TMDLWorkspace`.
    var tmdlHasPendingChanges = false
    var tmdlApplyRequestToken = 0
    /// Cổng sửa mô hình (Phase E); mọi lệnh sửa Table/Model/TMDL View đi qua đây.
    @ObservationIgnored private(set) var modelEditor: ModelEditor!

    // DAX query
    var daxQueries: [DAXQueryTab] = [DAXQueryTab(title: bi("Truy vấn 1", "Query 1"), text: DAXQueryTab.starter)]
    var daxSelection = 0
    /// Trạng thái chạy và kết quả theo tab (khoá là `DAXQueryTab.id`). Tạo khi tab được chạy lần đầu.
    var daxRuns: [UUID: DAXQueryState] = [:]
    /// Task đang chạy của từng tab, để Huỷ. Không cần quan sát.
    @ObservationIgnored var daxTasks: [UUID: Task<Void, Never>] = [:]
    /// Vùng chọn hiện tại của editor DAX (UTF-16), để chạy riêng vùng chọn.
    var daxEditorSelection = NSRange(location: 0, length: 0)
    /// Yêu cầu đưa con trỏ editor tới offset UTF-16 này (đi tới vị trí lỗi). Editor đặt lại về nil sau khi áp.
    var daxCursorRequest: Int?

    // TMDL
    var tmdlPath: String?

    enum VisualizationsTab: Hashable, CaseIterable { case build, format, analytics }

    init(workspace: Workspace, fileName: String, fileURL: URL? = nil) {
        self.workspace = workspace
        self.fileName = fileName
        self.fileURL = fileURL
        self.openedStamp = fileURL.flatMap { try? FileStamp.of($0) }
        let canEdit = workspace.pbix.reportFormat == .pbir || workspace.pbix.reportFormat == .legacyLayout
        self.editMode = canEdit && !AppPreferences.shared.viewOnlyDefault
        let archive = workspace.pbix.archive
        self.layout = workspace.pbix.reportFormat == .legacyLayout
            ? LayoutEditor.readingLegacy(archive: archive, report: workspace.report)
            : LayoutEditor.reading(archive: archive, report: workspace.report)
        self.interaction = ReportInteraction(workspace: workspace)
        let layout = self.layout
        Self.applyColumnKinds(to: layout, metadata: workspace.metadata)
        let interaction = self.interaction
        layout.legendValuesProvider = { [weak interaction] id in interaction?.legendValues[id] ?? [] }
        layout.customThemeChanged = { [weak workspace, weak interaction] edit in
            if let edit {
                workspace?.applySessionTheme(name: edit.name, data: edit.data)
            } else {
                workspace?.resetSessionTheme()
            }
            interaction?.modelVersion += 1
        }
        self.interaction.pagesProvider = { layout.pages }
        self.interaction.removedBookmarksProvider = { layout.structure.removedBookmarks }
        self.interaction.pageJSONProvider = { layout.structure.created[$0]?.pageJSON }
        wireReportEditing()
        let runtime = workspace.runtime
        layout.modelBase = runtime?.base
        modelEditor = ModelEditor(layout: layout) { [weak workspace] edits in
            guard let runtime else { throw ModelEditError("File không có mô hình dữ liệu để sửa") }
            try runtime.validate(edits)
            // Cột/bảng tính toán phải tính lại: không vòng phụ thuộc, cột có sẵn trong file lưu lại được (T116).
            try runtime.validateCalculations(edits)
            // Gỡ bảng đã nạp (tắt "Enable load", T098 FR-004) mà báo cáo còn dùng trường của nó: chặn kèm nơi dùng.
            func drops(_ list: ModelEdits) -> Set<String> {
                Set(list.items.compactMap { if case .dropTable(let name) = $0 { name } else { nil } })
            }
            guard let workspace else { return }
            let newDrops = drops(edits).subtracting(drops(layout.modelEdits))
            guard !newDrops.isEmpty else { return }
            let documents = ModelReferences.documents(layout: layout, workspace: workspace)
            for name in newDrops.sorted() {
                let usages = ModelReferences.documentUsages(ofTable: name, documents: documents)
                if !usages.isEmpty { throw ModelEditError("Không thể gỡ bảng \(name): " + ModelReferences.message(usages, what: "bảng \(name)")) }
            }
        } expand: { current, new in
            // Auto date/time (T032): bảng ngày cục bộ theo cột ngày thêm, đổi hay bỏ khi tuỳ chọn của file bật.
            guard let runtime, let model = try? runtime.base.applying(current) else { return new }
            // Tự phát hiện quan hệ (T035) sau khi nạp bảng mới, khi tuỳ chọn của file bật; cùng bước ⌘Z với lần nạp. Chạy trước Auto date/time
            // để cột ngày vừa thành phía nhiều không được bảng ngày cục bộ (review T061).
            let related = layout.autodetectRelationships
                ? RelationshipDetector.expand(new, before: model, isUnique: { ref in Self.isUnique(ref, runtime: runtime, workspace: workspace) })
                : new
            return AutoDateTime.expand(related, model: model)
        }
        layout.diagramSource = { [weak workspace] in
            guard let archive = workspace?.pbix.archive, let entry = archive.entry("DiagramLayout") else { return nil }
            return try? archive.read(entry)
        }
        layout.calculatedValues = { edits in
            guard let runtime else { return [:] }
            return try runtime.calculatedValues(for: edits)
        }
        // Cột/bảng tính toán có sẵn trong file phụ thuộc phần đổi của lần lưu: ghi lại dữ liệu của chúng (T116).
        layout.recalculationEdits = { edits in
            guard let runtime else { return [] }
            return CalculationPlan.recalculationEdits(for: edits, metadata: runtime.metadata)
        }
        layout.diagramSelected = { [weak self] in self?.currentDiagram }
        layout.diagramFileNames = { [weak self] in self?.workspace.diagramLayout?.diagrams.map(\.name) ?? [] }
        layout.diagramLineageTag = { [weak workspace] table in workspace?.userTables.first { $0.name == table }?.lineageTag }
        layout.modelEditsChanged = { [weak self] edits in
            do { try runtime?.setEdits(edits) } catch {
                self?.layout.noteFieldRefusal("Không áp lại được thay đổi mô hình: \(error)")
            }
            self?.modelVersion += 1
            if let self { Self.applyColumnKinds(to: self.layout, metadata: self.workspace.metadata) }
            self?.interaction.modelDidChange()
        }
        pageID = workspace.activePageID.flatMap { id in workspace.report.pages.contains { $0.id == id } ? id : nil }
            ?? workspace.visiblePages.first?.id ?? workspace.report.pages.first?.id
        layout.showPage(pageID)
        DocumentRegistry.shared.add(self)
        if UntitledDocuments.isUntitled(fileURL), let action = UntitledDocuments.pendingFirstAction {
            UntitledDocuments.pendingFirstAction = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if let self { action(self) }
            }
        }
        if let fileURL, !UntitledDocuments.isUntitled(fileURL) { RecentFiles.record(fileURL) }
        table = workspace.userTables.first?.name
        diagramName = workspace.diagramLayout?.defaultDiagram ?? workspace.diagramLayout?.diagrams.first?.name
        tmdlPath = workspace.tmdlDocuments.first?.path
        // Power BI stores the model view zoom per layout tab (zoomValue, percent).
        if let zoom = workspace.diagramLayout?.diagrams.first(where: { $0.name == diagramName })?.zoom, zoom > 0 {
            modelZoom = min(2, max(0.3, zoom / 100))
        }
        // Reopen the last workspace (also settable with `--args -lastWorkspace table`).
        if let saved = UserDefaults.standard.string(forKey: "lastWorkspace").flatMap(WorkspaceMode.init(rawValue:)),
           saved == .report || workspace.metadata != nil {
            mode = saved
        }
    }

    /// Cột của bảng đã có không có giá trị trùng: bảng nạp trong phiên đọc từ dữ liệu phiên, bảng của file so số giá trị khác nhau với
    /// số dòng (như hộp tạo quan hệ).
    nonisolated static func isUnique(_ ref: RelationshipDraft.ColumnRef, runtime: ModelRuntime, workspace: Workspace) -> Bool {
        if let table = runtime.overlay(named: ref.table) { return RelationshipDetector.isUnique(table, column: ref.column) }
        guard let storage = runtime.base.storage(table: ref.table, column: ref.column) else { return false }
        return storage.cardinality >= workspace.rowCount(ref.table)
    }

    /// Trang đang xem, với bố cục đã sửa (nếu có). Mọi nơi cần bố cục hiện tại phải đọc qua đây.
    var page: ReportPage? { pageID.flatMap(layout.page(_:)) }

    /// Các trang theo thứ tự tab, với thêm, xoá, đổi tên, đổi thứ tự và bố cục đã sửa (D5). Mọi nơi liệt kê trang đọc qua đây.
    var pages: [ReportPage] { layout.pages }

    var visual: ReportVisual? {
        guard let visualID else { return nil }
        return page?.visuals.first { $0.id == visualID }
    }

    /// `Entity.Property` of every field the selected visual uses.
    var usedFields: Set<String> {
        Set(visual?.fields.map { "\($0.entity).\($0.property)" } ?? [])
    }

    /// Lý do chưa thêm hoặc đổi loại visual được (chế độ Xem, báo cáo định dạng cũ), hoặc nil.
    var visualEditingBlocker: String? {
        if mode != .report { return "Chỉ thêm visual được ở chế độ Báo cáo." }
        if !canEditLayout { return "Báo cáo định dạng cũ (Report/Layout) chưa sửa được." }
        if !editMode { return "Bật chế độ Sửa (⌘E) để thêm hoặc đổi loại visual." }
        return nil
    }

    /// Thêm một visual mới của `type` vào trang đang mở và chọn nó (D3). Trả mã visual mới, hoặc nil kèm lý do ở
    /// `layout.fieldRefusal`.
    @discardableResult
    func insertVisual(_ type: String) -> String? {
        if let blocker = visualEditingBlocker { layout.noteFieldRefusal(blocker); return nil }
        guard let id = layout.insertVisual(type: type, visibleRect: visibleRect) else { return nil }
        visualID = id
        return id
    }

    /// Chèn hình khối (`rectangle`, `oval`, `line`) vào trang hiện tại (US4).
    @discardableResult
    func insertShape(_ shapeKind: String) -> String? {
        if let blocker = visualEditingBlocker { layout.noteFieldRefusal(blocker); return nil }
        guard let id = layout.insertVisual(type: "shape", visibleRect: visibleRect, shapeKind: shapeKind) else { return nil }
        visualID = id
        return id
    }

    /// Chèn ảnh nhúng từ dữ liệu sẵn có vào trang hiện tại (US4).
    @discardableResult
    func insertImage(data: Data, filename: String) -> String? {
        if let blocker = visualEditingBlocker { layout.noteFieldRefusal(blocker); return nil }
        guard let result = layout.insertImage(data: data, filename: filename, visibleRect: visibleRect) else { return nil }
        workspace.registerSessionImage(data, named: result.itemName)
        visualID = result.id
        return result.id
    }

    /// Mở hộp chọn tệp PNG/JPEG/SVG và chèn vào trang hiện tại (US4).
    func pickAndInsertImage() {
        if let blocker = visualEditingBlocker { layout.noteFieldRefusal(blocker); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = bi("Chèn ảnh vào báo cáo", "Insert Image into Report")
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        insertImage(data: data, filename: url.lastPathComponent)
    }

    /// Đổi loại visual đang chọn sang `type` (D3). Trả lý do từ chối hoặc nil.
    @discardableResult
    func changeType(_ type: String) -> String? {
        if let blocker = visualEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        guard layout.selection.count == 1, let id = layout.primary else {
            let message = "Chọn đúng một visual để đổi loại."
            layout.noteFieldRefusal(message)
            return message
        }
        return layout.changeType(of: id, to: type)
    }

    // MARK: Định dạng (D4)

    /// Lý do chưa sửa định dạng của visual đang chọn (chế độ Xem, báo cáo cũ, nhiều visual, visual trong nhóm), hoặc nil.
    var formatEditingBlocker: String? {
        if mode != .report { return "Chỉ sửa định dạng được ở chế độ Báo cáo." }
        if !canEditLayout { return "Báo cáo định dạng cũ (Report/Layout) chưa sửa được." }
        if !editMode { return "Bật chế độ Sửa (⌘E) để sửa định dạng." }
        if layout.selection.count > 1 { return "Chọn đúng một visual để sửa định dạng." }
        guard let id = visual?.id else { return "Chọn một visual để sửa định dạng." }
        return layout.formatEditingBlocker(for: id)
    }

    /// Thẻ, giá trị và phần chỉ-đọc của định dạng visual đang chọn.
    var formatState: FormatState? { visual.flatMap { layout.formatState(of: $0.id) } }

    /// Đặt một thuộc tính định dạng của visual đang chọn. Trả lý do từ chối hoặc nil.
    @discardableResult
    func setFormat(_ value: FormatValue, scope: FormatScope, object: String, property: String, series: String? = nil) -> String? {
        if let blocker = formatEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        guard let id = visual?.id else { return nil }
        return layout.setFormat(value, scope: scope, object: object, property: property, visual: id, series: series)
    }

    /// Đặt lại về mặc định cả thẻ (`property` nil) hoặc một thuộc tính của visual đang chọn.
    @discardableResult
    func resetFormat(scope: FormatScope, object: String, property: String? = nil, series: String? = nil) -> String? {
        if let blocker = formatEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        guard let id = visual?.id else { return nil }
        return layout.resetFormat(scope: scope, object: object, property: property, visual: id, series: series)
    }

    var tabs: [RibbonTab] {
        RibbonCatalog.tabs(mode: mode, visualSelected: visual != nil).map(RibbonTab.init(tabID:))
    }

    func select(table: String, column: String? = nil) {
        self.table = table
        self.column = column
        measure = nil
        measureDraft = calculatedDraft(table: table, column: column)
        if mode == .table { ribbonTab = column == nil ? .tableTools : .columnTools }
    }

    /// Thanh công thức sửa được khi chọn cột hoặc bảng tính toán (T116, như Desktop); nil khi không sửa được mô hình hay là cột dữ liệu.
    private func calculatedDraft(table: String, column: String?) -> MeasureDraft? {
        guard modelEditingBlocker == nil else { return nil }
        if let column {
            guard let c = workspace.column(table: table, name: column), c.kind == .calculated, let expression = c.expression else { return nil }
            return MeasureDraft(mode: .editColumn(table: table, name: column), text: "\(column) = \(expression)")
        }
        guard workspace.userTables.contains(where: { $0.name == table && $0.isCalculatedUserTable }),
              let expression = workspace.metadata?.calculatedTableExpressions[table] else { return nil }
        return MeasureDraft(mode: .editTable(name: table), text: "\(table) = \(expression)")
    }

    func zoomIn() { zoom = min(4, (zoom ?? 1) + 0.1) }
    func zoomOut() { zoom = max(0.25, (zoom ?? 1) - 0.1) }
}

struct DAXQueryTab: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var text: String

    @MainActor static var starter: String { """
    \(bi("// Truy vấn DAX mẫu. Bấm Chạy (⌘↵); bôi đen một đoạn để chỉ chạy đoạn đó.", "// Sample DAX query. Press Run (⌘↵); select a range to run only that selection."))
    EVALUATE
    SUMMARIZECOLUMNS(
        'Dim_Date'[year],
        "Số giao dịch", [Trans Count]
    )
    ORDER BY 'Dim_Date'[year]
    """ }
}
