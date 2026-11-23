import DAXEngine
import PBIXKit
import SwiftUI

// MARK: - DAX query view

struct DAXQueryWorkspace: View {
    static let usesInnerStatusBar = false

    @Bindable var state: DocumentState
    @State private var resultsLayout: ResultsLayout = .normal
    /// Chiều cao vùng kết quả ở trạng thái bình thường; người dùng kéo viền trên để đổi.
    @State private var resultsHeight: CGFloat = 300
    @State private var dragStartHeight: CGFloat?
    @State private var showDataPane = true
    @State private var showInfoBanner = true
    @State private var diagnostics: [EditorDiagnostic] = []
    @State private var completionModel: CompletionModel?

    private struct TabValidationKey: Equatable {
        let tabId: UUID
        let text: String
    }

    var body: some View {
        let currentTab = state.daxQueries.indices.contains(state.daxSelection) ? state.daxQueries[state.daxSelection] : nil
        let currentText = currentTab?.text ?? ""
        let currentTabId = currentTab?.id ?? UUID()

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if showInfoBanner {
                    DAXInfoBanner { showInfoBanner = false }
                }
                DAXCodeActionBar(state: state)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        if resultsLayout != .expanded {
                            if state.daxQueries.indices.contains(state.daxSelection) {
                                CodeEditor(
                                    text: $state.daxQueries[state.daxSelection].text,
                                    language: .dax,
                                    measures: state.workspace.metadata?.measures ?? [],
                                    diagnostics: diagnostics,
                                    completionModel: completionModel,
                                    selection: $state.daxEditorSelection,
                                    cursorRequest: $state.daxCursorRequest
                                )
                                .frame(maxHeight: .infinity)
                                .hairline(.bottom)
                                .transition(.opacity)
                            }
                        }
                        resultsArea
                            .frame(height: resultsFrameHeight(total: geo.size.height))
                            .overlay(alignment: .top) {
                                if resultsLayout == .normal { resizeHandle(total: geo.size.height) }
                            }
                    }
                }
                daxBottomTabBar
            }
            if showDataPane {
                DataPane(state: state, purpose: .query, collapse: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDataPane = false
                    }
                })
                .frame(width: 240)
                .hairline(.leading)
            } else {
                CollapsedPaneStrip(title: tr(.paneData), symbol: "cylinder.split.1x2") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDataPane = true
                    }
                }
                .hairline(.leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: resultsLayout)
        .animation(.easeInOut(duration: 0.2), value: showDataPane)
        .background(DS.Palette.canvas)
        .onAppear {
            updateCompletionModel()
        }
        .task(id: state.workspace.metadata?.userTables.map(\.name)) {
            updateCompletionModel()
        }
        .task(id: TabValidationKey(tabId: currentTabId, text: currentText)) {
            guard state.workspace.metadata != nil else {
                diagnostics = []
                return
            }
            do {
                // Chờ khoảng 500 ms (debounce)
                try await Task.sleep(nanoseconds: 500_000_000)
                let workspace = state.workspace
                let errors = try await Task.detached(priority: .userInitiated) {
                    let engine = try workspace.daxEngine()
                    return engine.validate(currentText)
                }.value
                // Văn bản đã đổi trong lúc kiểm thì lượt này bị huỷ: bỏ kết quả cũ để không gạch sai chỗ.
                guard !Task.isCancelled else { return }
                diagnostics = EditorDiagnostics.from(errors: errors, text: currentText)
            } catch {
                if Task.isCancelled { return }
                diagnostics = []
            }
        }
    }

    @ViewBuilder private var resultsArea: some View {
        if state.currentDAXRun == nil {
            VStack(spacing: 0) {
                HStack {
                    Text(bi("Kết quả", "Results"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Button {
                        resultsLayout = (resultsLayout == .collapsed) ? .normal : .collapsed
                    } label: {
                        Image(systemName: resultsLayout == .collapsed ? "chevron.up.2" : "chevron.down.2")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(DS.Palette.canvas)
                .hairline(.bottom)

                if resultsLayout != .collapsed {
                    DAXEmptyResultsIllustration()
                }
            }
        } else {
            QueryResultsView(state: state, layout: $resultsLayout)
        }
    }

    private var daxBottomTabBar: some View {
        let lang = AppPreferences.shared.effectiveLanguage
        return HStack(spacing: 1) {
            ForEach(Array(state.daxQueries.enumerated()), id: \.element.id) { index, tab in
                let selected = state.daxSelection == index
                Button {
                    state.daxSelection = index
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
                        .padding(.horizontal, 12)
                        .frame(height: UIMetrics.pageTabs)
                        .background(selected ? DS.Palette.canvas : .clear)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(DS.Palette.accentBrand).frame(height: 2.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                let nextIndex = state.daxQueries.count + 1
                state.daxQueries.append(DAXQueryTab(title: DAXQueryChrome.defaultTabTitle(index: nextIndex, language: lang), text: ""))
                state.daxSelection = state.daxQueries.count - 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.accentBrand))
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .help(bi("Thêm truy vấn mới", "New query"))
            .accessibilityLabel(bi("Thêm truy vấn mới", "New query"))
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: UIMetrics.pageTabs)
        .background(DS.Palette.chrome)
        .hairline(.top)
    }

    private func updateCompletionModel() {
        guard let meta = state.workspace.metadata else {
            completionModel = nil
            return
        }
        let tables = meta.userTables.map(\.name)
        var columnsByTable: [String: [String]] = [:]
        var measuresByTable: [String: [ModelMetadata.Measure]] = [:]
        for t in tables {
            columnsByTable[t] = state.workspace.columns(of: t).map(\.name)
            measuresByTable[t] = state.workspace.measures(of: t)
        }
        completionModel = CompletionModel(
            // Hàm của engine cộng các dạng truy vấn engine xử lý riêng (không có trong registry).
            functions: Array(Set(FunctionRegistry.all.map(\.name) + DAXCompletion.queryForms)).sorted(),
            tables: tables,
            columnsByTable: columnsByTable,
            measuresByTable: measuresByTable
        )
    }

    /// Chiều cao vùng kết quả: chỉ thanh tiêu đề khi thu xuống, cả vùng khi phóng to, còn lại theo người dùng kéo.
    private func resultsFrameHeight(total: CGFloat) -> CGFloat {
        switch resultsLayout {
        case .collapsed: return 44
        case .expanded: return max(44, total)
        case .normal: return clampedResultsHeight(resultsHeight, total: total)
        }
    }

    private func clampedResultsHeight(_ height: CGFloat, total: CGFloat) -> CGFloat {
        // Chừa ít nhất 80 pt cho editor; vùng kết quả cao tối thiểu 120 pt.
        min(max(120, height), max(120, total - 80))
    }

    /// Viền trên của vùng kết quả: rê chuột vào thì con trỏ đổi thành mũi tên lên–xuống, kéo để đổi chiều cao.
    private func resizeHandle(total: CGFloat) -> some View {
        Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .offset(y: -4)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartHeight ?? clampedResultsHeight(resultsHeight, total: total)
                        if dragStartHeight == nil { dragStartHeight = start }
                        resultsHeight = clampedResultsHeight(start - value.translation.height, total: total)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }

    private var collapsedDataPaneStrip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDataPane = true
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Text(bi("Dữ liệu", "Data"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 14, height: 80)
                Spacer()
            }
            .padding(.top, 10)
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .background(DS.Palette.chrome)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(bi("Mở lại ô Dữ liệu", "Expand Data pane"))
        .hairline(.leading)
    }

    /// Tóm tắt trạng thái theo chuẩn Power BI: "Thành công (ms) · Truy vấn i/n · Kết quả j/m · C cột, R dòng".
    private var statusDetail: String {
        let queryIndex = state.daxSelection + 1
        let queryCount = max(1, state.daxQueries.count)
        guard let run = state.currentDAXRun else {
            return StatusText.summary(status: .idle, queryIndex: queryIndex, queryCount: queryCount)
        }
        let table = (run.result?.tables.indices.contains(run.resultIndex) == true)
            ? run.result!.tables[run.resultIndex] : nil
        let columns = table?.columns.count ?? 0
        let rows = table?.rows.count ?? 0
        let resultIndex = max(1, run.resultIndex + 1)
        let resultCount = max(1, run.result?.tables.count ?? 1)
        return StatusText.summary(
            status: run.status,
            elapsedNanoseconds: run.result?.elapsedNanoseconds ?? 0,
            queryIndex: queryIndex,
            queryCount: queryCount,
            resultIndex: resultIndex,
            resultCount: resultCount,
            columns: columns,
            rows: rows
        )
    }
}

// MARK: - TMDL view

struct TMDLWorkspace: View {
    static let usesInnerStatusBar = false

    enum BottomTab { case problems, output }

    @Bindable var state: DocumentState
    /// Phần đang sửa chưa áp dụng: đường dẫn → văn bản.
    @State private var drafts: [String: String] = [:]
    @State private var issues: [TMDLIssue] = []
    @State private var bottomTab: BottomTab = .problems
    @State private var outputLog: String = ""
    @State private var showDataPane = true
    @State private var showIntro = false

    var body: some View {
        let docs = state.workspace.tmdlDocuments
        let blocker = state.modelEditingBlocker
        let path = state.tmdlPath ?? ""
        let original = docs.first { $0.path == path }?.text ?? ""
        let activeIdx = (docs.firstIndex(where: { $0.path == state.tmdlPath }) ?? 0) + 1
        HStack(spacing: 0) {
            tmdlDefinitionsSidebar
            VStack(spacing: 0) {
                TMDLCodeActionBar(
                    state: state,
                    path: path,
                    changed: changed,
                    onDiscard: { drafts = [:]; issues = [] },
                    onApply: { apply() }
                )
                CodeEditor(text: Binding(get: { drafts[path] ?? original }, set: { drafts[path] = $0; issues = [] }),
                           language: .tmdl, isEditable: blocker == nil && !path.isEmpty)
                    .frame(maxHeight: .infinity)
                tmdlProblemsOutputPanel
                tmdlBottomScriptBar(activeIndex: activeIdx)
            }
            tmdlDataSidebar
        }
        .background(DS.Palette.canvas)
        .onAppear {
            if TMDLViewChrome.shouldShowIntro() {
                showIntro = true
            }
        }
        .sheet(isPresented: $showIntro) {
            tmdlIntroSheet
        }
        .onChange(of: state.modelVersion) { _, _ in drafts = [:]; issues = []; state.tmdlHasPendingChanges = false }
        .onChange(of: drafts) { _, _ in state.tmdlHasPendingChanges = changed }
        .onChange(of: state.tmdlApplyRequestToken) { _, _ in
            if changed && state.modelEditingBlocker == nil { apply() }
        }
    }

    private var tmdlDefinitionsSidebar: some View {
        let docs = state.workspace.tmdlDocuments
        return VStack(spacing: 0) {
            PaneHeader(title: bi("Định nghĩa", "Definitions"), symbol: "folder")
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(docs) { doc in
                        TreeRow(level: doc.path.contains("/") ? 1 : 0,
                                symbol: doc.path.hasPrefix("tables/") ? "tablecells" : "doc.text",
                                tint: doc.path.hasPrefix("tables/") ? DS.Palette.table : DS.Palette.secondaryLabel,
                                title: doc.path + (drafts[doc.path].map { $0 != doc.text } == true ? " •" : ""),
                                isSelected: state.tmdlPath == doc.path) { state.tmdlPath = doc.path }
                    }
                }
            }
        }
        .frame(width: 210)
        .background(DS.Palette.chrome)
        .hairline(.trailing)
    }

    @ViewBuilder private var tmdlDataSidebar: some View {
        if showDataPane {
            DataPane(state: state, purpose: .query, collapse: { showDataPane = false }, initialTab: .model)
                .frame(width: 220)
                .hairline(.leading)
        } else {
            CollapsedPaneStrip(title: tr(.paneData), symbol: "cylinder.split.1x2") {
                showDataPane = true
            }
            .hairline(.leading)
        }
    }

    private var tmdlIntroSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(TMDLViewChrome.introTitle.localized)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.Palette.label)
            Text(TMDLViewChrome.introBody.localized)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(bi("Bắt đầu", "Get started")) {
                    TMDLViewChrome.markIntroSeen()
                    showIntro = false
                }
                .buttonStyle(PrimaryButtonStyle(compact: false))
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(DS.Palette.canvas)
    }

    private var tmdlProblemsOutputPanel: some View {
        let lang = AppPreferences.shared.effectiveLanguage
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Button { bottomTab = .problems } label: {
                    Text(TMDLViewChrome.problemsTabTitle(count: issues.count, language: lang))
                        .font(.system(size: 11.5, weight: bottomTab == .problems ? .semibold : .regular))
                        .foregroundStyle(bottomTab == .problems ? DS.Palette.label : DS.Palette.secondaryLabel)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            if bottomTab == .problems {
                                Rectangle().fill(DS.Palette.accentBrand).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)

                Button { bottomTab = .output } label: {
                    Text(TMDLViewChrome.outputTabTitle.localized)
                        .font(.system(size: 11.5, weight: bottomTab == .output ? .semibold : .regular))
                        .foregroundStyle(bottomTab == .output ? DS.Palette.label : DS.Palette.secondaryLabel)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            if bottomTab == .output {
                                Rectangle().fill(DS.Palette.accentBrand).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .background(DS.Palette.canvas)
            .hairline(.top)
            .hairline(.bottom)

            if bottomTab == .problems {
                if issues.isEmpty {
                    Text(bi("Không có sự cố nào.", "No problems detected."))
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
                                    Text(issue.description).font(DS.Typeface.bodySmall).foregroundStyle(Color.red)
                                }
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 96)
                }
            } else {
                Text(outputLog.isEmpty ? bi("Chưa có đầu ra áp dụng TMDL.", "No TMDL output yet.") : outputLog)
                    .font(DS.Typeface.mono)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DS.Palette.canvas)
    }

    private func tmdlBottomScriptBar(activeIndex idx: Int) -> some View {
        let lang = AppPreferences.shared.effectiveLanguage
        return HStack(spacing: 4) {
            Text(TMDLViewChrome.defaultScriptTabTitle(index: idx, language: lang))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.label)
                .padding(.horizontal, 12)
                .frame(height: UIMetrics.pageTabs)
                .background(DS.Palette.canvas)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DS.Palette.accentBrand).frame(height: 2.5)
                }
            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.accentBrand.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help(bi("Tạo kịch bản TMDL rời chưa hỗ trợ; chọn tệp ở cây Định nghĩa bên trái.", "Additional detached TMDL scripts are not supported yet; pick a file in Definitions."))
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: UIMetrics.pageTabs)
        .background(DS.Palette.chrome)
        .hairline(.top)
    }

    private var changed: Bool {
        let docs = state.workspace.tmdlDocuments
        return drafts.contains { path, text in docs.first { $0.path == path }.map { $0.text != text } ?? !text.isEmpty }
    }

    private func apply() {
        let result = state.applyTMDL(drafts: drafts)
        issues = result
        if result.isEmpty {
            drafts = [:]
            outputLog = bi("Đã áp dụng thay đổi TMDL thành công.", "Applied TMDL changes successfully.")
        } else {
            bottomTab = .problems
        }
    }
}
