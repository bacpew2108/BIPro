import Foundation

/// Ảnh chụp bất biến trạng thái tài liệu dùng để tính bật/tắt nút Ribbon thuần hàm (R-06).
struct RibbonContext: Equatable, Sendable {
    let mode: WorkspaceMode
    let hasModel: Bool
    let hasData: Bool
    let canEditModel: Bool
    let canEditCanvas: Bool
    let viewOnly: Bool
    let visualSelected: Bool
    let multiSelected: Bool
    let groupSelected: Bool
    let tableSelected: Bool
    let columnSelected: Bool
    let measureSelected: Bool
    let clipboardHasVisual: Bool
    let pageCount: Int

    // Ngữ cảnh chi tiết phục vụ các quy tắc đặc thù của BI Pro (mặc định suy ra hợp lý cho test dựng context giả).
    let canEditLayout: Bool
    let hasBaseMeasures: Bool
    let isFormatPainterActive: Bool
    let isEditingInteractions: Bool
    let canDrillUp: Bool
    let canDrillDown: Bool
    let visualHasData: Bool
    let isSelectedTableDateTable: Bool
    let isNumericColumnSelected: Bool
    let hasActiveDAXQuery: Bool
    let hasTMDLDocument: Bool
    let canUngroup: Bool
    let canMerge: Bool
    let isRefreshing: Bool

    init(
        mode: WorkspaceMode = .report,
        hasModel: Bool = true,
        hasData: Bool = true,
        canEditModel: Bool = true,
        canEditCanvas: Bool = true,
        viewOnly: Bool = false,
        visualSelected: Bool = false,
        multiSelected: Bool = false,
        groupSelected: Bool = false,
        tableSelected: Bool = false,
        columnSelected: Bool = false,
        measureSelected: Bool = false,
        clipboardHasVisual: Bool = false,
        pageCount: Int = 1,
        canEditLayout: Bool? = nil,
        hasBaseMeasures: Bool? = nil,
        isFormatPainterActive: Bool = false,
        isEditingInteractions: Bool = false,
        canDrillUp: Bool = false,
        canDrillDown: Bool = false,
        visualHasData: Bool? = nil,
        isSelectedTableDateTable: Bool = false,
        isNumericColumnSelected: Bool = false,
        hasActiveDAXQuery: Bool = true,
        hasTMDLDocument: Bool = true,
        canUngroup: Bool? = nil,
        canMerge: Bool? = nil,
        isRefreshing: Bool = false
    ) {
        self.mode = mode
        self.hasModel = hasModel
        self.hasData = hasData
        self.canEditModel = canEditModel
        self.canEditCanvas = canEditCanvas
        self.viewOnly = viewOnly
        self.visualSelected = visualSelected
        self.multiSelected = multiSelected
        self.groupSelected = groupSelected
        self.tableSelected = tableSelected
        self.columnSelected = columnSelected
        self.measureSelected = measureSelected
        self.clipboardHasVisual = clipboardHasVisual
        self.pageCount = pageCount
        self.canEditLayout = canEditLayout ?? canEditCanvas
        self.hasBaseMeasures = hasBaseMeasures ?? hasData
        self.isFormatPainterActive = isFormatPainterActive
        self.isEditingInteractions = isEditingInteractions
        self.canDrillUp = canDrillUp
        self.canDrillDown = canDrillDown
        self.visualHasData = visualHasData ?? (visualSelected && hasData)
        self.isSelectedTableDateTable = isSelectedTableDateTable
        self.isNumericColumnSelected = isNumericColumnSelected
        self.hasActiveDAXQuery = hasActiveDAXQuery
        self.hasTMDLDocument = hasTMDLDocument
        self.canUngroup = canUngroup ?? groupSelected
        self.canMerge = canMerge ?? (groupSelected && multiSelected)
        self.isRefreshing = isRefreshing
    }

    @MainActor
    init(state: DocumentState) {
        let metadata = state.workspace.metadata
        let hasModel = state.workspace.runtime != nil
        let hasData = metadata != nil && !state.workspace.userTables.isEmpty
        let selection = state.layout.selection
        let visual = state.visual
        let spec = visual.flatMap { state.interaction.loadedSpecs[$0.id] }
        let depth = visual.map { state.interaction.depth(of: $0) } ?? 0
        let maxLevels = spec?.drillLevels.count ?? 0
        let selectedColumn = state.table.flatMap { t in
            state.column.flatMap { state.workspace.column(table: t, name: $0) }
        }
        let isDateTable = state.table.flatMap { name in
            metadata?.tables.first { $0.name == name }?.dataCategory?.caseInsensitiveCompare("Time") == .orderedSame
        } ?? false

        self.init(
            mode: state.mode,
            hasModel: hasModel,
            hasData: hasData,
            canEditModel: state.modelEditingBlocker == nil,
            canEditCanvas: state.canEditCanvas,
            viewOnly: !state.editMode,
            visualSelected: visual != nil || !selection.isEmpty,
            multiSelected: selection.count >= 2,
            groupSelected: state.ungroupBlocker == nil,
            tableSelected: state.table != nil,
            columnSelected: selectedColumn != nil,
            measureSelected: state.measure != nil,
            clipboardHasVisual: state.layout.hasClipboard,
            pageCount: state.pages.count,
            canEditLayout: state.canEditLayout,
            hasBaseMeasures: !(metadata?.measures.isEmpty ?? true),
            isFormatPainterActive: state.layout.isFormatPainterActive,
            isEditingInteractions: state.layout.isEditingInteractions,
            canDrillUp: state.page != nil && visual != nil && depth > 0,
            canDrillDown: visual != nil && spec != nil && depth + 1 < maxLevels,
            visualHasData: visual.flatMap { state.interaction.loadedDataViews[$0.id] } != nil,
            isSelectedTableDateTable: isDateTable,
            isNumericColumnSelected: selectedColumn?.dataType.isNumeric == true,
            hasActiveDAXQuery: state.daxQueries.indices.contains(state.daxSelection),
            hasTMDLDocument: state.workspace.tmdlDocuments.contains(where: { $0.path == state.tmdlPath }),
            canUngroup: state.ungroupBlocker == nil,
            canMerge: state.mergeBlocker == nil,
            isRefreshing: state.refreshProgress?.isRunning == true
        )
    }

    /// Có thể sửa bố cục canvas hiện tại (chế độ Sửa + hỗ trợ sửa canvas).
    var canEditCanvasNow: Bool {
        mode == .report && canEditCanvas && !viewOnly
    }

    /// Có thể thêm/đổi visual trên báo cáo PBIR (khớp `DocumentState.visualEditingBlocker`).
    var canEditPBIRVisualsNow: Bool {
        mode == .report && canEditLayout && !viewOnly
    }

    /// Có thể thêm/sửa trang (khớp `DocumentState.pageEditingBlocker`).
    var canEditPagesNow: Bool {
        mode == .report && canEditLayout && !viewOnly
    }
}
