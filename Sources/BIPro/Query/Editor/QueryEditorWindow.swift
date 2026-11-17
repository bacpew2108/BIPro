import SwiftUI
import ColumnStore
import MEngine

public struct QueryEditorWindow: View {
    public let state: QueryEditorState
    public let existingTableNames: Set<String>
    public let onApply: () -> Void
    public let onClose: () -> Void
    public var scrollable: Bool = true

    // UI State
    @State private var activeTab: QueryRibbonTab = .home
    @State private var selectedColumns: [String] = []

    // View toggles
    @State private var showFormulaBar: Bool = true
    @State private var showQueriesPane: Bool = true
    @State private var showQuerySettingsPane: Bool = true
    @State private var showColumnQuality: Bool = true
    @State private var showColumnDistribution: Bool = true
    @State private var showColumnProfile: Bool = true

    // Popover / Sheet / Modal states
    @State private var activePopover: PopoverInfo? = nil
    @State private var activeSheet: ActiveSheet? = nil
    @State private var activeExpandColumn: String? = nil
    @State private var isAdvancedEditorPresented: Bool = false
    @State private var pendingInsertConfirmation: StepCommand? = nil
    @State private var showUnappliedChangesDialog: Bool = false
    @State private var ribbonErrorMessage: String? = nil

    private enum ActiveSheet: Identifiable {
        case merge
        case append
        case groupBy
        case customColumn
        case dependencies

        var id: Int {
            switch self {
            case .merge: return 1
            case .append: return 2
            case .groupBy: return 3
            case .customColumn: return 4
            case .dependencies: return 5
            }
        }
    }

    private struct PopoverInfo: Identifiable {
        let id = UUID()
        let command: QueryRibbonCommand
        let type: PopoverCommandType
    }

    public init(
        state: QueryEditorState,
        existingTableNames: Set<String>,
        onApply: @escaping () -> Void,
        onClose: @escaping () -> Void,
        scrollable: Bool = true,
        initialTab: QueryRibbonTab = .home,
        initialSelectedColumns: [String] = []
    ) {
        self.state = state
        self.existingTableNames = existingTableNames
        self.onApply = onApply
        self.onClose = onClose
        self.scrollable = scrollable
        self._activeTab = State(initialValue: initialTab)
        self._selectedColumns = State(initialValue: initialSelectedColumns)
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Window Title Bar
                windowTitleBar
                    .hairline(.bottom)

                // Ribbon
                QueryRibbonView(
                    activeTab: $activeTab,
                    context: ribbonContext,
                    onCommand: handleRibbonCommand,
                    onOpenAdvancedEditor: { isAdvancedEditorPresented = true },
                    onOpenMerge: { activeSheet = .merge },
                    onOpenAppend: { activeSheet = .append },
                    onOpenDependencies: { activeSheet = .dependencies },
                    onRefreshSource: handleRefreshSource,
                    hasMergeCandidates: !state.mergeCandidates.isEmpty,
                    onApply: onApply,
                    onApplyAndClose: handleApplyAndClose,
                    onCloseAttempt: handleCloseAttempt,
                    showFormulaBar: $showFormulaBar,
                    showQueriesPane: $showQueriesPane,
                    showQuerySettingsPane: $showQuerySettingsPane,
                    showColumnQuality: $showColumnQuality,
                    showColumnDistribution: $showColumnDistribution,
                    showColumnProfile: $showColumnProfile,
                    scrollable: scrollable
                )

                // Ribbon Error message strip
                if let err = ribbonErrorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.danger)

                        Text(err)
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.danger)
                            .lineLimit(2)

                        Spacer()

                        Button {
                            ribbonErrorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Palette.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(DS.Palette.danger.opacity(0.08))
                    .hairline(.bottom)
                }

                // Formula Bar
                if showFormulaBar {
                    FormulaBarView(state: state, scrollable: scrollable)
                }

                // Main 3-Column Layout
                HStack(spacing: 0) {
                    // Left Column: Queries Pane
                    if showQueriesPane {
                        QueryListView(
                            state: state,
                            existingTableNames: existingTableNames,
                            scrollable: scrollable
                        )
                        .hairline(.trailing)
                    }

                    // Center Column: Grid + Column Profile
                    VStack(spacing: 0) {
                        PreviewGridView(
                            state: state,
                            selectedColumns: $selectedColumns,
                            showColumnQuality: showColumnQuality,
                            showColumnDistribution: showColumnDistribution,
                            scrollable: scrollable,
                            onFilterColumn: { col in
                                openFilterPopover(for: col)
                            },
                            onExpandColumn: { col in
                                // Cột danh sách: mở thành dòng mới ngay (Desktop: "Expand to New Rows"); bảng/bản ghi: hộp chọn cột.
                                if state.expandableKind(of: col) == .list {
                                    executeCommand(.expandList(column: col))
                                } else {
                                    activeExpandColumn = col
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if showColumnProfile, let singleCol = singleSelectedColumnProfile {
                            ColumnProfileView(
                                profile: singleCol,
                                previewRows: state.preview?.rowCount ?? 0,
                                scrollable: scrollable,
                                onClose: {
                                    showColumnProfile = false
                                }
                            )
                            .padding(8)
                            .background(DS.Palette.chrome)
                            .hairline(.top)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    // Right Column: Query Settings / Applied Steps
                    if showQuerySettingsPane {
                        AppliedStepsView(
                            state: state,
                            existingTableNames: existingTableNames,
                            scrollable: scrollable
                        )
                        .hairline(.leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Status Bar
                statusBar
                    .hairline(.top)
            }
            // Kích thước cố định chỉ để xuất ảnh PNG; trong cửa sổ thật (sheet) bố cục co giãn theo khung.
            .modifier(FixedImageFrame(enabled: !scrollable))
            .background(Color.white)

            // Overlays / Dialogs
            if let popover = activePopover {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        activePopover = nil
                    }

                QueryCommandPopoverView(
                    command: popover.command,
                    type: popover.type,
                    selectedColumns: selectedColumns,
                    columnTypes: ribbonContext.columnTypes,
                    allColumns: ribbonContext.allColumns,
                    onCommit: { cmd in
                        activePopover = nil
                        executeCommand(cmd)
                    },
                    onCancel: {
                        activePopover = nil
                    }
                )
            }

            if let colName = activeExpandColumn, let nestedCols = state.nestedColumns(of: colName) {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        activeExpandColumn = nil
                    }

                ExpandColumnPopover(
                    sourceColumn: colName,
                    columns: nestedCols,
                    kind: state.expandableKind(of: colName) == .record ? .record : .table,
                    scrollable: scrollable,
                    onCommit: { cmd in
                        activeExpandColumn = nil
                        executeCommand(cmd)
                    },
                    onCancel: {
                        activeExpandColumn = nil
                    }
                )
            }

            if let pending = pendingInsertConfirmation {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                insertStepDialog(command: pending)
            }

            if showUnappliedChangesDialog {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                unappliedChangesDialog
            }
        }
        .sheet(isPresented: $isAdvancedEditorPresented) {
            AdvancedEditorSheet(state: state, scrollable: scrollable) {
                isAdvancedEditorPresented = false
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .merge:
                MergeDialog(
                    state: state,
                    scrollable: scrollable,
                    onCommit: { cmd in
                        let outcome = executeCommand(cmd)
                        if case .applied = outcome { activeSheet = nil }
                        if case .needsInsertConfirmation = outcome { activeSheet = nil }
                        return outcome
                    },
                    onCancel: { activeSheet = nil }
                )
            case .append:
                AppendDialog(
                    state: state,
                    scrollable: scrollable,
                    onCommit: { cmd in
                        let outcome = executeCommand(cmd)
                        if case .applied = outcome { activeSheet = nil }
                        if case .needsInsertConfirmation = outcome { activeSheet = nil }
                        return outcome
                    },
                    onCancel: { activeSheet = nil }
                )
            case .groupBy:
                GroupByDialog(
                    state: state,
                    initialSelectedColumns: selectedColumns,
                    scrollable: scrollable,
                    onCommit: { cmd in
                        let outcome = executeCommand(cmd)
                        if case .applied = outcome { activeSheet = nil }
                        if case .needsInsertConfirmation = outcome { activeSheet = nil }
                        return outcome
                    },
                    onCancel: { activeSheet = nil }
                )
            case .customColumn:
                CustomColumnDialog(
                    state: state,
                    scrollable: scrollable,
                    onCommit: { cmd in
                        let outcome = executeCommand(cmd)
                        if case .applied = outcome { activeSheet = nil }
                        if case .needsInsertConfirmation = outcome { activeSheet = nil }
                        return outcome
                    },
                    onCancel: { activeSheet = nil }
                )
            case .dependencies:
                QueryDependenciesView(
                    state: state,
                    scrollable: scrollable,
                    onClose: { activeSheet = nil }
                )
            }
        }
        .onAppear {
            initDefaultColumnSelection()
        }
        .onChange(of: state.preview?.columns.map(\.name)) { _, _ in
            initDefaultColumnSelection()
        }
    }

    // MARK: - Window Title Bar

    private var windowTitleBar: some View {
        HStack(spacing: 8) {
            // Ba nút đèn chỉ vẽ trong ảnh PNG (không có thanh tiêu đề hệ thống); trong sheet thật không vẽ nút giả.
            if !scrollable {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "#FF5F57")!).frame(width: 12, height: 12)
                    Circle().fill(Color(hex: "#FEBC2E")!).frame(width: 12, height: 12)
                    Circle().fill(Color(hex: "#28C840")!).frame(width: 12, height: 12)
                }
                .padding(.leading, 8)
            }

            Spacer()

            // Window title
            HStack(spacing: 6) {
                Text("\(state.selectedQuery?.name ?? "Truy vấn") — Trình chỉnh sửa truy vấn")
                    .font(DS.Typeface.headlineSmall)
                    .foregroundStyle(DS.Palette.label)

                if state.hasPendingChanges {
                    Badge(text: "Đã sửa", color: DS.Palette.warning)
                }
            }

            Spacer()

            if !scrollable { Color.clear.frame(width: 48, height: 12) }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(DS.Palette.chrome)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 0) {
            if let applyMsg = state.applyMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.danger)
                    Text(applyMsg)
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.danger)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        state.applyMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(DS.Palette.danger.opacity(0.08))
                .hairline(.bottom)
            }

            HStack(spacing: 12) {
                // Status icon & summary
                HStack(spacing: 6) {
                    Circle()
                        .fill(DS.Palette.success)
                        .frame(width: 7, height: 7)

                    let cols = state.preview?.columns.count ?? 0
                    let rows = state.preview?.rowCount ?? 0
                    Text(QueryEditorFormat.statusSummary(columns: cols, rows: rows))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.label)
                }

                Text("•")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.tertiaryLabel)

                Text("Phân tích cột dựa trên 1000 dòng đầu")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                Spacer()

                if state.isApplying {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang áp dụng…")
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }

                // Action buttons
                Button("Đóng và áp dụng") {
                    handleApplyAndClose()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(state.isApplying)

                Button("Đóng") {
                    handleCloseAttempt()
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(DS.Palette.chrome)
        }
    }

    // MARK: - Dialogs

    private func insertStepDialog(command: StepCommand) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DS.Palette.warning)

                Text("Chèn bước")
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
            }

            Text("Bạn có chắc muốn chèn một bước không? Chèn bước ở giữa có thể ảnh hưởng đến các bước sau và làm truy vấn bị lỗi.")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("Huỷ") {
                    pendingInsertConfirmation = nil
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Chèn") {
                    pendingInsertConfirmation = nil
                    executeCommand(command, confirmInsert: true)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 440)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .popoverElevation()
    }

    private var unappliedChangesDialog: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DS.Palette.warning)

                Text("Thay đổi chưa áp dụng")
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
            }

            Text("Có thay đổi trong truy vấn chưa được áp dụng vào mô hình.")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.secondaryLabel)

            HStack(spacing: 8) {
                Spacer()

                Button("Huỷ") {
                    showUnappliedChangesDialog = false
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Bỏ thay đổi") {
                    showUnappliedChangesDialog = false
                    onClose()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Áp dụng") {
                    showUnappliedChangesDialog = false
                    onApply()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 440)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .popoverElevation()
    }

    // MARK: - Context & Helpers

    private var ribbonContext: QueryRibbonContext {
        let cols = state.preview?.columns ?? []
        var types: [String: DAXType] = [:]
        for c in cols {
            types[c.name] = c.data.type
        }
        return QueryRibbonContext(
            selectedColumns: selectedColumns,
            columnTypes: types,
            allColumns: cols.map(\.name)
        )
    }

    private var singleSelectedColumnProfile: ColumnProfile? {
        guard selectedColumns.count == 1,
              let name = selectedColumns.first else { return nil }
        return state.profiles.first { $0.columnName == name }
    }

    private func initDefaultColumnSelection() {
        if selectedColumns.isEmpty, let firstCol = state.preview?.columns.first?.name {
            selectedColumns = [firstCol]
        }
    }

    private func handleRibbonCommand(_ command: QueryRibbonCommand) {
        ribbonErrorMessage = nil

        if command.needsParameters {
            switch command {
            case .keepTopRows:
                activePopover = PopoverInfo(command: command, type: .keepTopRows)
            case .removeTopRows:
                activePopover = PopoverInfo(command: command, type: .removeTopRows)
            case .replaceValue:
                activePopover = PopoverInfo(command: command, type: .replaceValue)
            case .splitByDelimiter:
                activePopover = PopoverInfo(command: command, type: .splitByDelimiter)
            case .addCustomColumn:
                activeSheet = .customColumn
            case .groupByCount:
                activeSheet = .groupBy
            case .filterEquals:
                if let name = selectedColumns.first,
                   let profile = state.profiles.first(where: { $0.columnName == name }),
                   let colType = ribbonContext.columnTypes[name] {
                    activePopover = PopoverInfo(command: command, type: .filterEquals(distribution: profile.distribution, columnType: colType))
                }
            default:
                break
            }
        } else {
            if let cmd = command.stepCommand(context: ribbonContext) {
                executeCommand(cmd)
            }
        }
    }

    private func openFilterPopover(for columnName: String) {
        selectedColumns = [columnName]
        if let profile = state.profiles.first(where: { $0.columnName == columnName }),
           let colType = ribbonContext.columnTypes[columnName] {
            activePopover = PopoverInfo(command: .filterEquals, type: .filterEquals(distribution: profile.distribution, columnType: colType))
        }
    }

    @discardableResult
    private func executeCommand(_ command: StepCommand, confirmInsert: Bool = false) -> StepCommandOutcome {
        let outcome = state.perform(command, confirmInsert: confirmInsert)
        switch outcome {
        case .applied:
            ribbonErrorMessage = nil
        case .needsInsertConfirmation:
            pendingInsertConfirmation = command
        case .rejected(let reason):
            ribbonErrorMessage = reason
        }
        return outcome
    }

    private func handleApplyAndClose() {
        onApply()
    }

    /// "Làm mới nguồn": đọc lại tệp nguồn của truy vấn đang chọn; không đọc được thì hiện lý do ở dải lỗi, dữ liệu đã lưu giữ nguyên.
    private func handleRefreshSource() {
        guard let id = state.selectedQueryID else { return }
        Task { @MainActor in ribbonErrorMessage = await state.refreshSource(of: id) }
    }

    private func handleCloseAttempt() {
        if state.hasPendingChanges || state.hasUnappliedQueries {
            showUnappliedChangesDialog = true
        } else {
            onClose()
        }
    }
}

/// 1280 × 800 pt khi xuất ảnh; ngược lại lấp đầy khung được cấp.
private struct FixedImageFrame: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.frame(width: 1280, height: 800) } else { content.frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
}
