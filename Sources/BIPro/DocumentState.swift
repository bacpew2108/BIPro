import Observation
import PBIXKit
import SwiftUI

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
    case home, insert, modeling, view, help, format, dataDrill, tableTools, columnTools
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Trang chủ"
        case .insert: "Chèn"
        case .modeling: "Mô hình hóa"
        case .view: "Xem"
        case .help: "Trợ giúp"
        case .format: "Định dạng"
        case .dataDrill: "Dữ liệu / Truy sâu"
        case .tableTools: "Công cụ bảng"
        case .columnTools: "Công cụ cột"
        }
    }

    /// Contextual tabs are tinted, as in the design.
    var isContextual: Bool { [.format, .dataDrill, .tableTools, .columnTools].contains(self) }
}

/// Per-window UI state.
@MainActor
@Observable
final class DocumentState {
    let workspace: Workspace
    let fileName: String

    var mode: WorkspaceMode = .report {
        didSet {
            if !tabs.contains(ribbonTab) { ribbonTab = .home }
            UserDefaults.standard.set(mode.rawValue, forKey: "lastWorkspace")
        }
    }
    var ribbonTab: RibbonTab = .home

    // Report
    var pageID: String?
    var visualID: String? { didSet { if visualID == nil, ribbonTab.isContextual, mode == .report { ribbonTab = .home } } }
    var zoom: Double? // nil = fit page
    var showFilters = true
    var showVisualizations = true
    var showData = true
    var showSelection = false
    var showBookmarks = false
    var visualizationsTab: VisualizationsTab = .build

    // Table / model
    var table: String?
    var column: String?
    var relationship: String?
    var diagramName: String?
    var modelZoom: Double = 0.85
    var layoutRevision = 0

    // DAX query
    var daxQueries: [DAXQueryTab] = [DAXQueryTab(title: "Truy vấn 1", text: DAXQueryTab.starter)]
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

    enum VisualizationsTab: Hashable { case build, format }

    init(workspace: Workspace, fileName: String) {
        self.workspace = workspace
        self.fileName = fileName
        pageID = workspace.activePageID.flatMap { id in workspace.report.pages.contains { $0.id == id } ? id : nil }
            ?? workspace.visiblePages.first?.id ?? workspace.report.pages.first?.id
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

    var page: ReportPage? { pageID.flatMap(workspace.page(id:)) }

    var visual: ReportVisual? {
        guard let visualID else { return nil }
        return page?.visuals.first { $0.id == visualID }
    }

    /// `Entity.Property` of every field the selected visual uses.
    var usedFields: Set<String> {
        Set(visual?.fields.map { "\($0.entity).\($0.property)" } ?? [])
    }

    var tabs: [RibbonTab] {
        switch mode {
        case .report: visual == nil ? [.home, .insert, .modeling, .view, .help] : [.home, .insert, .modeling, .view, .help, .format, .dataDrill]
        case .table: [.home, .help, .tableTools, .columnTools]
        case .model: [.home, .modeling, .view, .help]
        case .daxQuery, .tmdl: [.home, .view, .help]
        }
    }

    func select(table: String, column: String? = nil) {
        self.table = table
        self.column = column
        if mode == .table { ribbonTab = column == nil ? .tableTools : .columnTools }
    }

    func zoomIn() { zoom = min(4, (zoom ?? 1) + 0.1) }
    func zoomOut() { zoom = max(0.25, (zoom ?? 1) - 0.1) }
}

struct DAXQueryTab: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var text: String

    static let starter = """
    // Truy vấn DAX mẫu. Bấm Chạy (⌘↵); bôi đen một đoạn để chỉ chạy đoạn đó.
    EVALUATE
    SUMMARIZECOLUMNS(
        'Dim_Date'[year],
        "Số giao dịch", [Trans Count]
    )
    ORDER BY 'Dim_Date'[year]
    """
}
