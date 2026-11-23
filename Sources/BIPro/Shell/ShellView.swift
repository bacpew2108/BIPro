import PBIXKit
import SwiftUI

/// The five-zone window: title bar · ribbon · rail | workspace · status.
struct ShellView: View {
    @State private var state: DocumentState
    @State private var showOnboarding = false
    private let preferences = AppPreferences.shared

    init(state: DocumentState) {
        _state = State(initialValue: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(state: state)
            if state.showBackstage {
                BackstageView(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RibbonView(state: state)
                HStack(spacing: 0) {
                    Rail(state: state)
                    workspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                WindowStatusBar(state: state)
            }
        }
        .background(DS.Palette.chrome)
        .background { DocumentWindowBridge(state: state, isDirty: state.layout.isDirty) }
        .focusedSceneValue(\.documentState, state)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(preferences.preferredColorScheme)
        .tint(DS.Palette.accent)
        .onAppear {
            preferences.applyAppearance()
            if !preferences.onboardingSeen {
                showOnboarding = true
            }
        }
        .onChange(of: preferences.onboardingRequestToken) { _, _ in
            showOnboarding = true
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(preferences: preferences) {
                showOnboarding = false
            }
            .preferredColorScheme(preferences.preferredColorScheme)
        }
        .sheet(isPresented: Binding(get: { state.getDataState != nil }, set: { if !$0 { state.closeGetData() } })) {
            if let navigator = state.getDataState {
                GetDataFlowView(state: navigator, existingTableNames: state.existingTableNames,
                                onLoad: { state.loadFromGetData($0) },
                                onTransform: { tables in
                                    // Sheet Get Data đóng xong mới mở sheet Query Editor (hai sheet cùng lúc thì SwiftUI bỏ sheet sau).
                                    state.closeGetData()
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(400))
                                        state.showQueryEditor(loaded: tables)
                                    }
                                },
                                onClose: { state.closeGetData() })
                    .preferredColorScheme(preferences.preferredColorScheme)
            }
        }
        .sheet(isPresented: Binding(get: { state.enterData != nil }, set: { if !$0 { state.closeEnterData() } })) {
            if let table = state.enterData {
                EnterDataView(table: table, onCommit: { await state.loadEnterData($0) }, onCancel: { state.closeEnterData() })
                    .preferredColorScheme(preferences.preferredColorScheme)
                    .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: Binding(get: { state.showFileOptions }, set: { state.showFileOptions = $0 })) {
            OptionsDialog(options: state.fileOptions, autoDateTimeBlocker: state.autoDateTimeBlocker,
                          onCommit: { state.applyFileOptions($0) }, onCancel: { state.showFileOptions = false })
                .preferredColorScheme(preferences.preferredColorScheme)
        }
        .sheet(isPresented: Binding(get: { state.queryEditorState != nil }, set: { if !$0 { state.closeQueryEditor() } })) {
            if let editor = state.queryEditorState {
                QueryEditorWindow(state: editor, existingTableNames: state.existingTableNames,
                                  onApply: { state.applyQueryEditor() }, onClose: { state.closeQueryEditor() })
                    .frame(minWidth: 1000, idealWidth: 1280, maxWidth: .infinity, minHeight: 640, idealHeight: 800, maxHeight: .infinity)
                    .preferredColorScheme(preferences.preferredColorScheme)
                    // SC-008: chỉ đóng qua nút "Đóng" (Esc), nút này hỏi "Pending changes" khi còn thay đổi chưa áp dụng.
                    .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: Binding(get: { state.exportSheetKind != nil }, set: { if !$0 { state.closeExportSheet() } })) {
            if let kind = state.exportSheetKind {
                ExportSheet(
                    kind: kind,
                    visiblePageCount: state.pages.filter { !$0.isHidden }.count,
                    currentPageName: state.page?.displayName ?? "",
                    isExporting: $state.isExporting,
                    progressText: $state.exportProgress,
                    errorMessage: $state.exportError,
                    onExportPDF: { state.runExportPDF(scope: $0) },
                    onExportPNG: { state.runExportPNG(scale: $0) },
                    onCancel: { state.closeExportSheet() }
                )
                .preferredColorScheme(preferences.preferredColorScheme)
            }
        }
        .sheet(isPresented: Binding(get: { state.refreshProgress != nil }, set: { if !$0 { state.closeRefreshSheet() } })) {
            if let progress = state.refreshProgress {
                RefreshProgressSheet(
                    progress: progress,
                    onCancel: { progress.isCancelled = true },
                    onClose: { state.closeRefreshSheet() }
                )
                .preferredColorScheme(preferences.preferredColorScheme)
                .interactiveDismissDisabled(progress.isRunning)
            }
        }
        .sheet(isPresented: Binding(get: { state.pendingCascadeRename != nil }, set: { if !$0 { state.pendingCascadeRename = nil } })) {
            if let target = state.pendingCascadeRename {
                RenameConfirmationSheet(state: state, initialTarget: target) {
                    state.pendingCascadeRename = nil
                }
                .preferredColorScheme(preferences.preferredColorScheme)
            }
        }
        .modifier(Wave4SheetsModifier(state: state, colorScheme: preferences.preferredColorScheme))
    }

    @ViewBuilder private var workspace: some View {
        if state.mode != .report && state.workspace.metadata == nil {
            EmptyViewState(state: state)
        } else {
            switch state.mode {
            case .report: ReportWorkspace(state: state)
            case .table: TableWorkspace(state: state)
            case .model: ModelWorkspace(state: state)
            case .daxQuery: DAXQueryWorkspace(state: state)
            case .tmdl: TMDLWorkspace(state: state)
            }
        }
    }
}

/// Gom các hộp thoại Wave 4 (v1.2) sang ViewModifier riêng để giữ biểu thức `ShellView.body` gọn và type-check nhanh.
private struct Wave4SheetsModifier: ViewModifier {
    @Bindable var state: DocumentState
    let colorScheme: ColorScheme?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { state.showDataTableVisualID != nil }, set: { if !$0 { state.showDataTableVisualID = nil } })) {
                if let vid = state.showDataTableVisualID,
                   let page = state.page,
                   let visual = page.visuals.first(where: { $0.id == vid }),
                   let view = state.interaction.loadedDataViews[vid] {
                    VisualDataTableSheet(
                        visual: visual,
                        view: view,
                        onExportCSV: { state.exportVisualToCSV(visual: visual, view: view) },
                        onClose: { state.showDataTableVisualID = nil }
                    )
                    .preferredColorScheme(colorScheme)
                }
            }
            .sheet(isPresented: $state.showDataPointTable) {
                if let page = state.page {
                    let selection = state.interaction.state(for: page).selection
                    if let vid = selection.sourceVisualID, let visual = page.visuals.first(where: { $0.id == vid }) {
                        DataPointTableSheet(visual: visual, selection: selection, view: state.interaction.loadedDataViews[vid]) {
                            state.showDataPointTable = false
                        }
                        .preferredColorScheme(colorScheme)
                    }
                }
            }
            .sheet(isPresented: $state.showQuickMeasureSheet) {
                QuickMeasureSheet(state: state) { state.showQuickMeasureSheet = false }
                    .preferredColorScheme(colorScheme)
            }
            .sheet(isPresented: $state.showMarkDateTableSheet) {
                if let tbl = state.table {
                    MarkAsDateTableSheet(state: state, tableName: tbl) { state.showMarkDateTableSheet = false }
                        .preferredColorScheme(colorScheme)
                }
            }
            .sheet(isPresented: $state.showManageRelationshipsSheet) {
                ManageRelationshipsSheet(state: state) { state.showManageRelationshipsSheet = false }
                    .preferredColorScheme(colorScheme)
            }
            .sheet(isPresented: $state.showManageRolesSheet) {
                ManageRolesSheet(state: state) { state.showManageRolesSheet = false }
                    .preferredColorScheme(colorScheme)
            }
            .sheet(isPresented: $state.showViewAsRoleSheet) {
                ViewAsRoleSheet(state: state) { state.showViewAsRoleSheet = false }
                    .preferredColorScheme(colorScheme)
            }
            .sheet(isPresented: Binding(get: { state.pendingDAXModelUpdates != nil }, set: { if !$0 { state.pendingDAXModelUpdates = nil } })) {
                if let items = state.pendingDAXModelUpdates {
                    DAXUpdateModelSheet(state: state, items: items) { state.pendingDAXModelUpdates = nil }
                        .preferredColorScheme(colorScheme)
                }
            }
    }
}
