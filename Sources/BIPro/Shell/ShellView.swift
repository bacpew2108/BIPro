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
            RibbonView(state: state)
            HStack(spacing: 0) {
                Rail(state: state)
                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            FileOptionsView(options: state.fileOptions, autoDateTimeBlocker: state.autoDateTimeBlocker,
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
    }

    @ViewBuilder private var workspace: some View {
        switch state.mode {
        case .report: ReportWorkspace(state: state)
        case .table: TableWorkspace(state: state)
        case .model: ModelWorkspace(state: state)
        case .daxQuery: DAXQueryWorkspace(state: state)
        case .tmdl: TMDLWorkspace(state: state)
        }
    }
}

// MARK: - Title bar

struct TitleBar: View {
    @Bindable var state: DocumentState
    @State private var query = ""
    @State private var showResults = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Color.clear.frame(width: 72) // traffic lights
                Image(systemName: "doc.text.fill").foregroundStyle(DS.Palette.accent)
                Text(state.fileName).font(DS.Typeface.headlineSmall).foregroundStyle(DS.Palette.label).lineLimit(1)
                Badge(text: state.statusBadge)
                    .help(state.layout.isDirty ? tr(.statusDirtyHelp) : tr(.statusViewHelp))
                Spacer()
                Menu {
                    Button(tr(.exportPDFItem)) { state.openExportSheet(.pdf) }
                        .disabled(state.pages.isEmpty)
                    Button(tr(.exportPNGItem)) { state.openExportSheet(.png) }
                        .disabled(state.page == nil)
                    Divider()
                    Button(tr(.exportCSVItem)) { state.exportSelectedVisualToCSV() }
                        .disabled(state.exportCSVDisabledReason != nil)
                        .help(state.exportCSVDisabledReason ?? tr(.exportCSVItem))
                } label: {
                    Label(tr(.exportMenu), systemImage: "square.and.arrow.up")
                }
                .menuStyle(.button)
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
                .help(tr(.exportHelp))
                .accessibilityLabel(tr(.exportMenu))
            }
            .padding(.horizontal, 14)

            SearchField(text: $query, prompt: tr(.searchPlaceholder), shortcut: "⌘K")
                .focused($searchFocused)
                .frame(width: 420)
                .accessibilityLabel(tr(.searchPlaceholder))
                .onChange(of: query) { _, text in showResults = !text.isEmpty }
                .popover(isPresented: $showResults, arrowEdge: .bottom) {
                    CommandResults(state: state, query: query) { query = ""; showResults = false }
                }
        }
        .frame(height: DS.Metrics.titleBar)
        .background(.regularMaterial)
        .hairline(.bottom)
        .gesture(WindowDragGesture())
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("k").hidden()
        }
    }
}

/// ⌘K results: jump to pages, visuals, tables, columns and measures.
struct CommandResults: View {
    let state: DocumentState
    let query: String
    let dismiss: () -> Void

    private struct Hit: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
        let action: @MainActor () -> Void
    }

    private var hits: [Hit] {
        let q = query.lowercased()
        let w = state.workspace
        var result: [Hit] = []
        for page in state.pages where page.displayName.lowercased().contains(q) {
            result.append(Hit(symbol: "doc.richtext", title: page.displayName, detail: tr(.searchHitPage)) { [state] in
                state.mode = .report; state.pageID = page.id
            })
        }
        for table in w.userTables where table.name.lowercased().contains(q) {
            result.append(Hit(symbol: "tablecells", title: table.name, detail: tr(.searchHitTable)) { [state] in
                state.mode = .table; state.select(table: table.name)
            })
        }
        for m in w.metadata?.measures ?? [] where m.name.lowercased().contains(q) {
            result.append(Hit(symbol: "function", title: m.name, detail: trf(.searchHitMeasureFormat, m.tableName)) { [state] in
                state.mode = .daxQuery
                state.daxQueries[state.daxSelection].text = DAXSnippets.defineAndEvaluate(m)
            })
        }
        for c in w.metadata?.columns ?? [] where c.kind != .rowNumber && w.userTables.contains(where: { $0.name == c.tableName }) && c.name.lowercased().contains(q) {
            result.append(Hit(symbol: "textformat", title: c.name, detail: trf(.searchHitColumnFormat, c.tableName)) { [state] in
                state.mode = .table; state.select(table: c.tableName, column: c.name)
            })
        }
        for page in state.pages {
            for v in page.visuals where v.fields.contains(where: { $0.label.lowercased().contains(q) }) {
                result.append(Hit(symbol: "chart.bar", title: v.fields.map(\.label).joined(separator: ", "), detail: trf(.searchHitVisualFormat, v.type, page.displayName)) { [state] in
                    state.mode = .report; state.pageID = page.id; state.visualID = v.id
                })
            }
        }
        return Array(result.prefix(40))
    }

    var body: some View {
        let hits = hits
        VStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty {
                Text(trf(.searchNoResultsFormat, query)).font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel).padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hits) { hit in
                            Button {
                                hit.action()
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: hit.symbol).foregroundStyle(DS.Palette.accent).frame(width: 18)
                                    Text(hit.title).font(DS.Typeface.body).lineLimit(1)
                                    Spacer()
                                    Text(hit.detail).font(DS.Typeface.label).foregroundStyle(DS.Palette.tertiaryLabel).lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: DS.Metrics.navRow)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 420)
    }
}

// MARK: - Rail

struct Rail: View {
    @Bindable var state: DocumentState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 6) {
            ForEach(WorkspaceMode.allCases) { mode in
                let selected = state.mode == mode
                Button { state.mode = mode } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 16, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : DS.Palette.secondaryLabel)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(selected ? DS.Palette.accent : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.localizedTitle)
                .accessibilityLabel(mode.localizedTitle)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .disabled(mode != .report && state.workspace.metadata == nil)
            }
            Spacer()
            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .help(tr(.settingsTooltip))
            .accessibilityLabel(tr(.a11yRailSettings))
        }
        .padding(.vertical, 10)
        .frame(width: DS.Metrics.rail)
        .frame(maxHeight: .infinity)
        .background(DS.Palette.chrome)
        .hairline(.trailing)
    }
}

// MARK: - Status bar

struct StatusBar<Trailing: View>: View {
    let workspace: Workspace
    var detail: String = ""
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(workspace.metadata == nil ? DS.Palette.warning : DS.Palette.success).frame(width: 7, height: 7)
            Text(workspace.metadata == nil ? tr(.statusNoModel) : trf(.statusVertiPaqReadyFormat, workspace.totalRows.formatted()))
            if !detail.isEmpty {
                Text("·").foregroundStyle(DS.Palette.tertiaryLabel)
                Text(detail)
            }
            Spacer()
            trailing
        }
        .font(DS.Typeface.label)
        .foregroundStyle(DS.Palette.secondaryLabel)
        .padding(.horizontal, 12)
        .frame(height: DS.Metrics.statusBar)
        .background(DS.Palette.chrome)
        .hairline(.top)
    }
}

extension StatusBar where Trailing == EmptyView {
    init(workspace: Workspace, detail: String = "") {
        self.init(workspace: workspace, detail: detail) { EmptyView() }
    }
}

/// Zoom control: `− 85% +` and fit.
struct ZoomControl: View {
    let percent: Int
    let zoomOut: () -> Void
    let zoomIn: () -> Void
    let fit: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: zoomOut) { Image(systemName: "minus") }
                .buttonStyle(GhostIconButtonStyle())
                .help(tr(.zoomOut))
                .accessibilityLabel(tr(.zoomOut))
            Text("\(percent)%").font(DS.Typeface.label.monospacedDigit()).frame(width: 40)
                .accessibilityLabel("\(percent)%")
            Button(action: zoomIn) { Image(systemName: "plus") }
                .buttonStyle(GhostIconButtonStyle())
                .help(tr(.zoomIn))
                .accessibilityLabel(tr(.zoomIn))
            Button(action: fit) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(GhostIconButtonStyle())
                .help(tr(.zoomFit))
                .accessibilityLabel(tr(.zoomFit))
        }
    }
}
