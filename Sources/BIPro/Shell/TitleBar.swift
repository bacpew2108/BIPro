import AppKit
import PBIXKit
import SwiftUI

/// Thanh tiêu đề cửa sổ theo chuẩn Power BI Desktop 2.159 (`UIMetrics.titleBar` = 36 pt).
///
/// Trái → phải: khoảng trống traffic lights (72 pt) · Lưu · Hoàn tác · Làm lại · tên tệp + trạng thái lưu + menu ▾ ·
/// ô Search ở giữa (`⌘K`) · Cài đặt (`⌘,`) · chuyển Sáng/Tối · Share (vô hiệu).
struct TitleBar: View {
    @Bindable var state: DocumentState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.isSnapshotRender) private var isSnapshotRender
    @State private var query = ""
    @State private var showResults = false
    @FocusState private var searchFocused: Bool
    private let preferences = AppPreferences.shared

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                leadingControls
                Spacer(minLength: 12)
                trailingControls
            }
            .padding(.horizontal, 10)

            searchControl
                .frame(width: 340)
        }
        .frame(height: UIMetrics.titleBar)
        .background(DS.Palette.chrome)
        .gesture(WindowDragGesture())
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("k").hidden()
        }
    }

    @ViewBuilder private var leadingControls: some View {
        Color.clear.frame(width: 72) // macOS traffic lights
        titleIconButton(
            symbol: "square.and.arrow.down",
            tip: bi("Lưu (⌘S)", "Save (⌘S)"),
            disabled: !state.layout.isDirty && !state.isUntitled
        ) {
            _ = state.save()
        }
        titleIconButton(
            symbol: "arrow.uturn.backward",
            tip: bi("Hoàn tác (⌘Z)", "Undo (⌘Z)"),
            disabled: !state.layout.canUndo
        ) {
            state.layout.undo()
            state.visualID = state.layout.primary
        }
        titleIconButton(
            symbol: "arrow.uturn.forward",
            tip: bi("Làm lại (⇧⌘Z)", "Redo (⇧⌘Z)"),
            disabled: !state.layout.canRedo
        ) {
            state.layout.redo()
            state.visualID = state.layout.primary
        }
        fileMenuButton
    }

    @ViewBuilder private var fileMenuButton: some View {
        RibbonMenuButton(
            disabled: false,
            help: state.layout.isDirty ? tr(.statusDirtyHelp) : tr(.statusViewHelp),
            accessibilityLabel: "\(displayFileName) \(savedStatusText)"
        ) {
            Button(bi("Lưu", "Save")) { _ = state.save() }
                .disabled(!state.layout.isDirty && !state.isUntitled)
            Button(bi("Lưu thành…", "Save as…")) { _ = state.saveAs() }
            Button(bi("Tuỳ chọn tệp…", "File options…")) { state.showFileOptions = true }
            Divider()
            Button(tr(.exportPDFItem)) { state.openExportSheet(.pdf) }
                .disabled(state.pages.isEmpty)
            Button(tr(.exportPNGItem)) { state.openExportSheet(.png) }
                .disabled(state.page == nil)
            Button(tr(.exportCSVItem)) { state.exportSelectedVisualToCSV() }
                .disabled(state.exportCSVDisabledReason != nil)
        } label: {
            HStack(spacing: 4) {
                Text(displayFileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.label)
                    .lineLimit(1)
                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                Text(savedStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder private var trailingControls: some View {
        titleIconButton(
            symbol: "gearshape",
            tip: tr(.settingsTooltip),
            disabled: false
        ) {
            openSettings()
        }
        .accessibilityLabel(tr(.a11yRailSettings))

        themeMenuButton
        shareButton
    }

    @ViewBuilder private var themeMenuButton: some View {
        let tip = bi("Đổi giao diện Sáng / Tối", "Switch Light / Dark theme")
        RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: tip) {
            Button(bi("Sáng", "Light")) { preferences.appearance = .light }
            Button(bi("Tối", "Dark")) { preferences.appearance = .dark }
            Button(bi("Theo hệ thống", "System")) { preferences.appearance = .system }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: appearanceSymbol)
                    .font(.system(size: 13))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .foregroundStyle(DS.Palette.secondaryLabel)
            .frame(height: 26)
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder private var shareButton: some View {
        Button {} label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                Text(bi("Chia sẻ", "Share"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.Palette.tertiaryLabel)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .help(bi("Chia sẻ lên Power BI Service: chưa hỗ trợ trên BI Pro (máy cục bộ).",
                 "Share to Power BI Service: not supported in BI Pro (local app)."))
        .accessibilityLabel(bi("Chia sẻ", "Share"))
    }

    private var displayFileName: String {
        state.fileName.hasSuffix(".pbix") ? String(state.fileName.dropLast(5)) : state.fileName
    }

    private var savedStatusText: String {
        if state.layout.isDirty {
            return bi("Chưa lưu", "Unsaved changes")
        }
        if let modified = state.openedStamp?.modified {
            let formatted = Self.timeFormatter.string(from: modified)
            return bi("Lưu lúc \(formatted)", "Last saved: \(formatted)")
        }
        return bi("Đã lưu", "Last saved")
    }

    private var appearanceSymbol: String {
        switch preferences.appearance {
        case .dark: "moon"
        case .light, .system: "sun.max"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private func titleIconButton(symbol: String, tip: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(disabled ? DS.Palette.tertiaryLabel.opacity(0.6) : DS.Palette.secondaryLabel)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(tip)
        .accessibilityLabel(tip)
    }

    @ViewBuilder private var searchControl: some View {
        if isSnapshotRender {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                Text(bi("Tìm kiếm", "Search"))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer()
                Text("⌘K")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.canvas))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator.opacity(0.8), lineWidth: 0.75))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                TextField(tr(.searchPlaceholder), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                } else {
                    Text("⌘K")
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.canvas))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator.opacity(0.8), lineWidth: 0.75))
            .accessibilityLabel(tr(.searchPlaceholder))
            .onChange(of: query) { _, text in showResults = !text.isEmpty }
            .popover(isPresented: $showResults, arrowEdge: .bottom) {
                CommandResults(state: state, query: query) { query = ""; showResults = false }
            }
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
