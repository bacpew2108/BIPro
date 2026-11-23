import Connectors
import PBIXKit
import SwiftUI

private struct SnapshotRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Đặt `true` khi render tĩnh bằng `ImageRenderer` (tránh `Menu`/`NSViewRepresentable` bị vẽ thành biểu tượng cấm).
    var isSnapshotRender: Bool {
        get { self[SnapshotRenderKey.self] }
        set { self[SnapshotRenderKey.self] = newValue }
    }
}

/// Nút menu dùng `Menu` native trong app thật và vẽ thẳng `label` khi chụp `ImageRenderer`.
struct RibbonMenuButton<Label: View, MenuContent: View>: View {
    @Environment(\.isSnapshotRender) private var isSnapshotRender
    let disabled: Bool
    let help: String
    let accessibilityLabel: String
    @ViewBuilder let menuContent: () -> MenuContent
    @ViewBuilder let label: () -> Label

    var body: some View {
        if isSnapshotRender || disabled {
            label()
                .opacity(disabled ? 0.45 : 1)
                .help(help)
                .accessibilityLabel(accessibilityLabel)
        } else {
            Menu {
                menuContent()
            } label: {
                label()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(help)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// Bộ vẽ các mục/nút trên thanh Ribbon từ `RibbonItemSpec` (T017).
/// Dùng SF Symbols hai màu (`.symbolRenderingMode(.palette)`), nhãn song ngữ, trạng thái vô hiệu mờ đồng nhất kèm `.help`, và VoiceOver.
struct RibbonItemView: View {
    @Bindable var state: DocumentState
    let item: RibbonItemSpec
    let context: RibbonContext
    let tabID: RibbonTabID
    var onOpenAbout: () -> Void = {}

    @State private var showMoreVisuals = false
    @State private var showShapesPopover = false
    @State private var showThemePopover = false

    var body: some View {
        switch item.kind {
        case .large:
            largeControl(isToggle: false)
        case .toggle:
            largeControl(isToggle: true)
        case .smallStack(let children):
            if item.id == .formattingQuickRow {
                RibbonColumnQuickFormatRow(state: state)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(children) { child in
                        smallControl(child)
                    }
                }
                .padding(.horizontal, 2)
            }
        case .checkbox:
            checkboxControl
        case .field(let control):
            fieldPlaceholderControl(control)
        case .gallery(let gallery):
            galleryPlaceholderControl(gallery)
        }
    }

    // MARK: - Toggle state

    private func isOnState(for command: RibbonCommandID) -> Bool {
        switch command {
        case .formatPainter: return state.layout.isFormatPainterActive
        case .showFilters: return state.showFilters
        case .showBookmarks: return state.showBookmarks
        case .showSelection, .selectionPane: return state.showSelection
        case .editInteractions: return state.layout.isEditingInteractions
        case .viewAs: return !state.interaction.activeRLSRoles.isEmpty
        case .markAsDateTable: return context.isSelectedTableDateTable
        case .snapToGrid: return AppPreferences.shared.snapToGrid
        default: return false
        }
    }

    // MARK: - Large / Toggle button

    @ViewBuilder
    private func largeControl(isToggle: Bool) -> some View {
        let enabled = item.availability.isEnabled(in: context)
        let reason = item.availability.disabledReason(in: context)
        let isOn = isToggle && isOnState(for: item.id)
        let tip = tooltipText(for: item, reason: reason)

        if item.id == .sqlServer && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                Button("PostgreSQL…") { state.showGetData(kind: .postgres) }
                Button("SQLite…") { state.showGetData(kind: .sqlite) }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .refresh && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                ForEach(RibbonMenus.refreshEntries) { entry in
                    Button(entry.title.localized) {
                        if entry.id == "schemaAndData" { state.startRefreshAll() }
                    }
                    .disabled(!entry.enabled)
                }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .newPage && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                ForEach(RibbonMenus.newPageEntries) { entry in
                    Button {
                        RibbonMenus.performNewPage(entry.id, state: state)
                    } label: {
                        Label(entry.title.localized, systemImage: entry.symbol)
                    }
                    .disabled(!entry.enabled)
                }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .buttons && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                ForEach(RibbonMenus.buttonsEntries) { entry in
                    if entry.id == "navigator" {
                        Menu {
                            ForEach(RibbonMenus.navigatorSubmenuEntries) { sub in
                                Button {
                                    RibbonMenus.performButton(sub.id, state: state)
                                } label: {
                                    Label(sub.title.localized, systemImage: sub.symbol)
                                }
                            }
                        } label: {
                            Label(entry.title.localized, systemImage: entry.symbol)
                        }
                    } else {
                        Button {
                            RibbonMenus.performButton(entry.id, state: state)
                        } label: {
                            Label(entry.title.localized, systemImage: entry.symbol)
                        }
                        .disabled(!entry.enabled)
                    }
                }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .shapes && enabled {
            Button {
                showShapesPopover.toggle()
            } label: {
                largeLabel(item: item, isOn: showShapesPopover, enabled: true)
            }
            .buttonStyle(.plain)
            .help(tip)
            .accessibilityLabel(item.title.localized)
            .popover(isPresented: $showShapesPopover, arrowEdge: .bottom) {
                ShapesGalleryPopoverView(state: state) {
                    showShapesPopover = false
                }
            }
        } else if item.id == .pageView && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                ForEach(RibbonMenus.pageViewEntries) { entry in
                    Button {
                        RibbonMenus.performPageView(entry.id, state: state)
                    } label: {
                        Label(entry.title.localized, systemImage: entry.symbol)
                    }
                }
                Divider()
                // T034: Chế độ chỉ xem lưu theo ứng dụng (`AppPreferences.viewOnlyDefault`); mặc định chỉ đổi khi spike R-02 (T052) đạt.
                Button {
                    let nextViewOnly = !AppPreferences.shared.viewOnlyDefault
                    AppPreferences.shared.viewOnlyDefault = nextViewOnly
                    state.editMode = !nextViewOnly
                } label: {
                    Label(
                        bi("Chế độ chỉ xem", "View-only mode"),
                        systemImage: AppPreferences.shared.viewOnlyDefault ? "checkmark" : "eye"
                    )
                }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .align && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                ForEach(AlignCommand.allCases, id: \.self) { command in
                    Button {
                        state.align(command)
                    } label: {
                        Label(command.title, systemImage: command.systemImage)
                    }
                    .disabled(state.alignBlocker(command) != nil)
                }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .group && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                Button {
                    state.groupSelection()
                } label: {
                    Label(tr(.menuGroup), systemImage: "square.on.square.dashed")
                }
                .disabled(state.groupBlocker != nil)

                Button {
                    state.ungroupSelection()
                } label: {
                    Label(tr(.menuUngroup), systemImage: "square.on.square")
                }
                .disabled(state.ungroupBlocker != nil)

                Button {
                    state.mergeSelection()
                } label: {
                    Label(bi("Gộp vào nhóm", "Merge"), systemImage: "plus.square.on.square")
                }
                .disabled(state.mergeBlocker != nil)
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .sortByColumn && enabled {
            let selectedCol = state.table.flatMap { t in state.column.flatMap { state.workspace.column(table: t, name: $0) } }
            let siblings = selectedCol.map { col in
                state.workspace.columns(of: col.tableName).filter { $0.id != col.id && $0.kind != .rowNumber }
            } ?? []
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                if let col = selectedCol {
                    Button(bi("Chính nó", "Itself")) {
                        if let reason = state.updateColumn(table: col.tableName, name: col.name, patch: ColumnPatch(sortBy: .clear)) {
                            state.layout.noteFieldRefusal(reason)
                        }
                    }
                    if !siblings.isEmpty {
                        Divider()
                        ForEach(siblings, id: \.id) { sibling in
                            Button(sibling.name) {
                                if let reason = state.updateColumn(table: col.tableName, name: col.name, patch: ColumnPatch(sortBy: .set(sibling.name))) {
                                    state.layout.noteFieldRefusal(reason)
                                }
                            }
                        }
                    }
                }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .getData && enabled {
            RibbonMenuButton(disabled: false, help: tip, accessibilityLabel: item.title.localized) {
                Button(bi("Lấy dữ liệu…", "Get data…")) { state.showGetData() }
                Divider()
                Button(bi("Sổ làm việc Excel", "Excel workbook")) { state.showGetData(kind: .excel) }
                Button("PostgreSQL…") { state.showGetData(kind: .postgres) }
                Button("SQLite…") { state.showGetData(kind: .sqlite) }
            } label: {
                largeLabel(item: item, isOn: false, enabled: true)
            }
        } else if item.id == .moreVisuals && enabled {
            Button {
                showMoreVisuals.toggle()
            } label: {
                largeLabel(item: item, isOn: showMoreVisuals, enabled: true)
            }
            .buttonStyle(.plain)
            .help(tip)
            .accessibilityLabel(item.title.localized)
            .popover(isPresented: $showMoreVisuals, arrowEdge: .bottom) {
                MoreVisualsPopoverView(state: state) {
                    showMoreVisuals = false
                }
            }
        } else {
            Button {
                if item.id == .about {
                    onOpenAbout()
                } else {
                    RibbonActions.perform(item.id, state: state, tab: tabID)
                }
            } label: {
                largeLabel(item: item, isOn: isOn, enabled: enabled)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
            .help(tip)
            .accessibilityLabel(item.title.localized)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }

    private func largeLabel(item: RibbonItemSpec, isOn: Bool, enabled: Bool) -> some View {
        let formattedTitle = Self.balancedTwoLineTitle(item.title.localized, hasMenu: item.hasMenu)
        let chevronBelow = item.hasMenu && !formattedTitle.contains("\n") && item.title.localized.count >= 7

        return VStack(spacing: 2) {
            Image(systemName: item.symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    enabled ? item.tint.primary : DS.Palette.secondaryLabel,
                    enabled ? item.tint.secondary : DS.Palette.tertiaryLabel
                )
                .font(.system(size: 20, weight: .regular))
                .frame(width: UIMetrics.ribbonIcon, height: UIMetrics.ribbonIcon)

            if chevronBelow {
                VStack(spacing: 1) {
                    Text(formattedTitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(formattedTitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DS.Palette.label)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize()
                    if item.hasMenu {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(minWidth: 44, minHeight: 68, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isOn ? DS.Palette.accentTeal.opacity(0.14) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isOn ? DS.Palette.accentTeal.opacity(0.4) : .clear, lineWidth: 0.75)
        )
        .contentShape(Rectangle())
    }

    /// Chia nhãn nhiều từ thành 2 dòng cân bằng giống Power BI Desktop (không cắt chữ giữa từ, không hiện dấu `…`).
    static func balancedTwoLineTitle(_ title: String, hasMenu: Bool) -> String {
        let words = title.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return title }
        if title.count <= 8 && !hasMenu { return title }
        var bestSplit = 1
        var bestDiff = Int.max
        for i in 1..<words.count {
            let left = words[0..<i].joined(separator: " ")
            let right = words[i...].joined(separator: " ")
            let diff = abs(left.count - right.count)
            if diff < bestDiff {
                bestDiff = diff
                bestSplit = i
            }
        }
        let line1 = words[0..<bestSplit].joined(separator: " ")
        let line2 = words[bestSplit...].joined(separator: " ")
        return "\(line1)\n\(line2)"
    }

    // MARK: - Small button (inside smallStack)

    @ViewBuilder
    private func smallControl(_ child: RibbonItemSpec) -> some View {
        let enabled = child.availability.isEnabled(in: context)
        let reason = child.availability.disabledReason(in: context)
        let isToggle: Bool = {
            if case .toggle = child.kind { return true }
            return false
        }()
        let isOn = isToggle && isOnState(for: child.id)
        let tip = tooltipText(for: child, reason: reason)

        Button {
            if child.id == .downloadTheme {
                ThemePickerPopover.exportCurrentTheme(state: state)
            } else if child.id == .importTheme {
                _ = ThemePickerPopover.importCustomTheme(state: state)
            } else {
                RibbonActions.perform(child.id, state: state, tab: tabID)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: child.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        enabled ? child.tint.primary : DS.Palette.secondaryLabel,
                        enabled ? child.tint.secondary : DS.Palette.tertiaryLabel
                    )
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 15, height: 15)
                Text(child.title.localized)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DS.Palette.label)
                    .lineLimit(1)
                    .fixedSize()
                if child.hasMenu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 20, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(isOn ? DS.Palette.accentTeal.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .help(tip)
        .accessibilityLabel(child.title.localized)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Checkbox

    private var checkboxControl: some View {
        let enabled = item.availability.isEnabled(in: context)
        let reason = item.availability.disabledReason(in: context)
        let checked = isOnState(for: item.id)
        let tip = tooltipText(for: item, reason: reason)

        return Button {
            RibbonActions.perform(item.id, state: state, tab: tabID)
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(checked ? DS.Palette.accentTeal : DS.Palette.canvas)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(checked ? Color.clear : DS.Palette.checkboxBorder, lineWidth: 1)
                    )
                    .overlay {
                        if checked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 13, height: 13)
                Text(item.title.localized)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.label)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 4)
            .frame(height: 20, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .help(tip)
        .accessibilityLabel(item.title.localized)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    // MARK: - Field / Gallery controls

    private func fieldPlaceholderControl(_ control: FieldControl) -> some View {
        RibbonColumnFieldControlView(state: state, control: control, item: item)
    }

    private func galleryPlaceholderControl(_ gallery: GalleryKind) -> some View {
        switch gallery {
        case .themes6:
            ThemesRibbonGallery(state: state)
        }
    }

    // MARK: - Helpers

    private func tooltipText(for item: RibbonItemSpec, reason: Bilingual?) -> String {
        if let reason {
            return reason.localized
        }
        if item.id == .sqlServer {
            return bi(
                "SQL Server (BI Pro hỗ trợ kết nối PostgreSQL và SQLite)",
                "SQL Server (BI Pro supports PostgreSQL and SQLite connections)"
            )
        }
        return item.title.localized
    }
}

/// Popover `More visuals ▾` dùng `VisualCatalog` hiện có để chèn nhanh bất kỳ visual nào BI Pro hỗ trợ.
struct MoreVisualsPopoverView: View {
    let state: DocumentState
    let dismiss: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bi("Thêm visual", "More visuals"))
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.label)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(VisualCatalog.gallery, id: \.type) { entry in
                        Button {
                            state.insertVisual(entry.type)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: entry.symbol)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(DS.Palette.accentTeal, DS.Palette.secondaryLabel)
                                    .font(.system(size: 16))
                                    .frame(height: 20)
                                Text(entry.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(DS.Palette.label)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.chrome))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.name)
                    }
                }
            }
            .frame(width: 340, height: 260)
        }
        .padding(12)
    }
}
