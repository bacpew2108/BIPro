import AppKit
import Connectors
import Foundation
import PBIXKit

/// Phân loại một `RibbonCommandID` có hành động thực thi hay không có hành động (`X`/`P`/container).
enum RibbonActionKind: Equatable, Sendable {
    case active
    case noop
}

/// Kết quả thực thi một lệnh Ribbon.
enum RibbonActionResult: Equatable, Sendable {
    case performed
    case noop
}

/// Ánh xạ `RibbonCommandID` sang các hàm `DocumentState` / `LayoutEditor` hiện có.
/// KHÔNG viết lại logic nghiệp vụ; chỉ gọi lại hàm hiện có để bảo toàn hành vi v1.2 (kể cả hoàn tác ⌘Z và lưu T2).
enum RibbonActions {
    static func actionKind(for id: RibbonCommandID) -> RibbonActionKind {
        switch id {
        case .paste, .cut, .copy, .formatPainter,
             .getData, .excelWorkbook, .sqlServer, .enterData, .transformData, .refresh,
             .newPage, .newVisual, .textBox, .moreVisuals, .buttons, .shapes, .image,
             .manageRelationships, .newMeasure, .quickMeasure, .newColumn, .newTable,
             .markAsDateTable, .manageRoles, .viewAs,
             .themeGallery6, .downloadTheme, .importTheme,
             .pageView, .snapToGrid, .showFilters, .showBookmarks, .showSelection,
             .refreshVisuals, .performanceAnalyzer,
             .about, .guidedLearning,
             .editInteractions, .selectionPane, .align, .group, .bringForward, .sendBackward,
             .visualTable, .expandNextLevel, .drillUp, .drillDown,
             .tableName, .columnName, .format, .currencyFormat, .percentFormat, .thousandsFormat, .decimalFormat,
             .summarization, .dataCategory, .sortByColumn,
             .daxFormat, .comment, .uncomment:
            return .active

        case .clipboardStack, .themeActionsStack, .drillActionsStackLeft, .drillActionsStackRight, .formattingQuickRow,
             .oneLakeCatalog, .dataverse, .recentSources,
             .keyInfluencers, .decompositionTree, .narrative,
             .paginatedReport, .powerApps, .powerAutomate, .addSparkline,
             .newVisualCalculation, .calculationGroup, .changeDetection, .newParameter,
             .qnaSetup, .language, .linguisticSchema,
             .sensitivity, .publish, .prepDataForAI, .copilot,
             .themeGallery, .customizeTheme, .pageSize, .pageBackground, .wallpaper, .howToCreateTheme,
             .mobileLayout, .gridlines, .lockObjects, .syncSlicers,
             .pauseVisuals, .optimizationPresets, .applyAllSlicers,
             .trainingVideos, .documentation, .support,
             .powerBIBlog, .community, .powerBIForDevelopers, .submitAnIdea, .externalTools,
             .examples, .consultingServices,
             .applyDrillFiltersTo,
             .dataPointTable, .switchToNextLevel, .drillThrough, .groups, .findAnomalies,
             .dataType, .decimalPlaces, .dataGroups,
             .tmdlFormat, .find, .replace, .commandPalette:
            return .noop
        }
    }

    @MainActor
    @discardableResult
    static func perform(_ id: RibbonCommandID, state: DocumentState, tab: RibbonTabID? = nil) -> RibbonActionResult {
        switch id {
        // MARK: Clipboard
        case .paste:
            guard state.editMode && state.canEditCanvas && state.layout.hasClipboard else { return .noop }
            _ = state.layout.paste()
            state.visualID = state.layout.primary
            return .performed

        case .cut:
            guard state.editMode && state.canEditCanvas && !state.layout.selection.isEmpty else { return .noop }
            state.layout.cut()
            state.visualID = state.layout.primary
            return .performed

        case .copy:
            if state.mode == .tmdl {
                guard let doc = state.workspace.tmdlDocuments.first(where: { $0.path == state.tmdlPath }) else { return .noop }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(doc.text, forType: .string)
                return .performed
            }
            guard state.editMode && state.canEditCanvas && !state.layout.selection.isEmpty else { return .noop }
            state.layout.copy()
            return .performed

        case .formatPainter:
            if state.layout.isFormatPainterActive {
                state.layout.cancelFormatPainter()
                return .performed
            }
            guard state.editMode && state.canEditCanvas && state.layout.selection.count == 1 else { return .noop }
            state.layout.beginFormatPainter()
            return .performed

        // MARK: Data & Queries
        case .getData:
            state.showGetData()
            return .performed

        case .excelWorkbook:
            state.showGetData(kind: .excel)
            return .performed

        case .sqlServer:
            // Mở luồng kết nối CSDL (PostgreSQL) làm hành động chính khi bấm trực tiếp; menu chi tiết chọn PostgreSQL / SQLite.
            state.showGetData(kind: .postgres)
            return .performed

        case .enterData:
            state.showEnterData()
            return .performed

        case .transformData:
            state.showQueryEditor()
            return .performed

        case .refresh:
            state.startRefreshAll()
            return .performed

        // MARK: Insert
        case .newPage:
            state.addPage()
            return .performed

        case .newVisual:
            let visualType = (tab == .insert) ? "clusteredColumnChart" : "cardVisual"
            state.insertVisual(visualType)
            return .performed

        case .textBox:
            state.insertVisual("textbox")
            return .performed

        case .image:
            state.pickAndInsertImage()
            return .performed

        case .moreVisuals, .buttons, .shapes:
            // Mở qua menu / popover trong RibbonItemViews & RibbonMenus.
            return .performed

        // MARK: Modeling & Calculations
        case .manageRelationships:
            state.showManageRelationshipsSheet = true
            return .performed

        case .newMeasure:
            guard let table = state.table ?? state.workspace.userTables.first?.name else { return .noop }
            if state.mode == .report {
                state.newMeasureInTableView(table: table)
            } else {
                state.beginNewMeasure(table: table)
            }
            return .performed

        case .quickMeasure:
            guard state.modelEditingBlocker == nil,
                  !(state.workspace.metadata?.measures.isEmpty ?? true) else { return .noop }
            state.showQuickMeasureSheet = true
            return .performed

        case .newColumn:
            guard let table = state.table else { return .noop }
            state.beginNewColumn(table: table)
            return .performed

        case .newTable:
            state.beginNewTable()
            return .performed

        case .markAsDateTable:
            guard state.modelEditingBlocker == nil, state.table != nil else { return .noop }
            state.showMarkDateTableSheet = true
            return .performed

        case .manageRoles:
            guard state.modelEditingBlocker == nil else { return .noop }
            state.showManageRolesSheet = true
            return .performed

        case .viewAs:
            guard state.workspace.metadata != nil else { return .noop }
            state.showViewAsRoleSheet = true
            return .performed

        // MARK: Design
        case .themeGallery6, .downloadTheme, .importTheme:
            // Xử lý trực tiếp bởi điều khiển thư viện / file panel ở Catalog+Design & ThemePickerPopover.
            return .performed

        // MARK: View & Optimize
        case .pageView:
            state.fitsWidth = false
            state.zoom = nil
            return .performed

        case .snapToGrid:
            AppPreferences.shared.snapToGrid.toggle()
            return .performed

        case .showFilters:
            state.showFilters.toggle()
            return .performed

        case .showBookmarks:
            state.showBookmarks.toggle()
            return .performed

        case .showSelection, .selectionPane:
            state.showSelection.toggle()
            return .performed

        case .performanceAnalyzer:
            state.showPerformanceAnalyzer.toggle()
            return .performed

        case .refreshVisuals:
            state.interaction.modelVersion += 1
            return .performed

        // MARK: Help
        case .about:
            // Popover About được mở ở RibbonView / Catalog+ViewOptimizeHelp.
            return .performed

        case .guidedLearning:
            AppPreferences.shared.requestShowOnboarding()
            return .performed

        // MARK: Format & Data / Drill
        case .editInteractions:
            state.layout.isEditingInteractions.toggle()
            return .performed

        case .align:
            // Mở qua menu AlignCommand.
            return .performed

        case .bringForward:
            state.reorder(.forward)
            return .performed

        case .sendBackward:
            state.reorder(.backward)
            return .performed

        case .group:
            state.groupSelection()
            return .performed

        case .visualTable:
            guard let visual = state.visual,
                  state.interaction.loadedDataViews[visual.id] != nil else { return .noop }
            state.showDataTableVisualID = visual.id
            return .performed

        case .drillUp:
            guard let page = state.page, let visual = state.visual else { return .noop }
            state.interaction.drillUp(page: page, visual: visual)
            return .performed

        case .drillDown, .expandNextLevel:
            guard let visual = state.visual,
                  let spec = state.interaction.loadedSpecs[visual.id] else { return .noop }
            state.interaction.nextLevel(visual: visual, spec: spec)
            return .performed

        // MARK: Table / Column Tools (chủ yếu qua field control; nút nhanh format gọi ColumnFormatShortcut)
        case .currencyFormat:
            return applyColumnQuickFormat(state: state) { ColumnFormatShortcut.currency(current: $0) }

        case .percentFormat:
            return applyColumnQuickFormat(state: state) { ColumnFormatShortcut.percent(current: $0) }

        case .thousandsFormat:
            return applyColumnQuickFormat(state: state) { ColumnFormatShortcut.toggleThousandsSeparator(current: $0) }

        case .decimalFormat:
            return applyColumnQuickFormat(state: state) { ColumnFormatShortcut.toggleTwoDecimals(current: $0) }

        case .tableName, .columnName, .format, .summarization, .dataCategory, .sortByColumn:
            return .performed

        // MARK: DAX Editing
        case .daxFormat:
            guard state.daxQueries.indices.contains(state.daxSelection) else { return .noop }
            state.formatActiveDAXQuery()
            return .performed

        case .comment:
            guard state.daxQueries.indices.contains(state.daxSelection) else { return .noop }
            let lines = state.daxQueries[state.daxSelection].text.components(separatedBy: "\n")
            state.daxQueries[state.daxSelection].text = lines.map { line in
                line.isEmpty ? line : "// " + line
            }.joined(separator: "\n")
            return .performed

        case .uncomment:
            guard state.daxQueries.indices.contains(state.daxSelection) else { return .noop }
            let lines = state.daxQueries[state.daxSelection].text.components(separatedBy: "\n")
            state.daxQueries[state.daxSelection].text = lines.map { line in
                if line.hasPrefix("// ") { return String(line.dropFirst(3)) }
                if line.hasPrefix("//") { return String(line.dropFirst(2)) }
                return line
            }.joined(separator: "\n")
            return .performed

        // MARK: No-op (X / P / Stack containers)
        case .clipboardStack, .themeActionsStack, .drillActionsStackLeft, .drillActionsStackRight, .formattingQuickRow,
             .oneLakeCatalog, .dataverse, .recentSources,
             .keyInfluencers, .decompositionTree, .narrative,
             .paginatedReport, .powerApps, .powerAutomate, .addSparkline,
             .newVisualCalculation, .calculationGroup, .changeDetection, .newParameter,
             .qnaSetup, .language, .linguisticSchema,
             .sensitivity, .publish, .prepDataForAI, .copilot,
             .themeGallery, .customizeTheme, .pageSize, .pageBackground, .wallpaper, .howToCreateTheme,
             .mobileLayout, .gridlines, .lockObjects, .syncSlicers,
             .pauseVisuals, .optimizationPresets, .applyAllSlicers,
             .trainingVideos, .documentation, .support,
             .powerBIBlog, .community, .powerBIForDevelopers, .submitAnIdea, .externalTools,
             .examples, .consultingServices,
             .applyDrillFiltersTo,
             .dataPointTable, .switchToNextLevel, .drillThrough, .groups, .findAnomalies,
             .dataType, .decimalPlaces, .dataGroups,
             .tmdlFormat, .find, .replace, .commandPalette:
            return .noop
        }
    }

    @MainActor
    private static func applyColumnQuickFormat(state: DocumentState, transform: (String?) -> String) -> RibbonActionResult {
        guard state.modelEditingBlocker == nil,
              let table = state.table,
              let colName = state.column,
              let col = state.workspace.column(table: table, name: colName),
              col.dataType.isNumeric else { return .noop }
        let next = transform(col.formatString)
        if let reason = state.updateColumn(table: col.tableName, name: col.name, patch: ColumnPatch(formatString: .set(next)),
                                           coalesceKey: "column-\(col.id)-format") {
            state.layout.noteFieldRefusal(reason)
        }
        return .performed
    }
}
