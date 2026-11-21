import AppKit
import PBIXKit
import SwiftUI

// MARK: - Filters

struct FiltersPane: View {
    @Bindable var state: DocumentState
    var collapse: (() -> Void)?
    @State private var search = ""

    var body: some View {
        let w = state.workspace
        VStack(spacing: 0) {
            PaneHeader(title: tr(.paneFilters), symbol: "line.3.horizontal.decrease", collapse: collapse)
            SearchField(text: $search, prompt: bi("Tìm bộ lọc", "Search filters")).padding(.horizontal, 10).padding(.bottom, 6)
            if let reason = state.reportEditingBlocker {
                Text(reason).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let visual = state.visual {
                        section(bi("Bộ lọc trên visual này", "Filters on this visual"), filters: visualLevelFilters(visual), scope: visual.id, level: .visual, empty: bi("Visual chưa có field", "Visual has no fields"))
                    }
                    section(bi("Bộ lọc trên trang này", "Filters on this page"), filters: state.pageID.map { state.interaction.pageFilters(of: $0) } ?? [], scope: state.pageID ?? "",
                            level: .page, empty: bi("Chưa có bộ lọc trang", "No page filters"))
                    section(bi("Bộ lọc trên mọi trang", "Filters on all pages"), filters: w.reportFilters, scope: "", level: .report, empty: bi("Chưa có bộ lọc báo cáo", "No report filters"))
                }
                .padding(.bottom, 10)
            }
            PaneFooter(text: bi("\(activeCount) bộ lọc đang áp dụng", "\(activeCount) active filters"))
        }
        .background(DS.Palette.chrome)
    }

    private var activeCount: Int {
        let w = state.workspace, interaction = state.interaction
        let pageID = state.pageID ?? ""
        let page = pageID.isEmpty ? [] : state.interaction.pageFilters(of: pageID)
        func count(_ filters: [ReportFilter], _ level: ReportFilter.Level, _ scope: String) -> Int {
            filters.filter { !interaction.effectiveRemovedFilters.contains(key($0, level, scope)) }
                .filter { FilterEditing.isActive($0, key: key($0, level, scope), interaction: interaction) }.count
        }
        let added = interaction.effectiveUserFilters.filter {
            $0.key.filterID.hasPrefix("added-") && $0.value.isActive
                && (($0.key.level == .report) || ($0.key.level == .page && $0.key.scope == pageID))
        }.count
        return count(w.reportFilters, .report, "") + count(page, .page, pageID) + added
    }

    /// Tiêu đề thẻ lọc: cấp phân cấp ngày Auto date/time ghi kèm cột ngày, như "OrderDate - Year" của Desktop (VM-F11b, T038).
    private func cardTitle(_ field: ReportField) -> String {
        let label = state.layout.label(of: field)
        return field.variationColumn.map { "\($0) - \(label)" } ?? label
    }

    private func key(_ filter: ReportFilter, _ level: ReportFilter.Level, _ scope: String) -> UserFilterKey {
        UserFilterKey(level: level, scope: scope, filterID: filter.id)
    }

    /// Power BI lists every field of the selected visual as a filter card, plus explicit visual filters.
    private func visualLevelFilters(_ visual: ReportVisual) -> [ReportFilter] {
        let explicit = state.interaction.visualFilters(of: visual)
        let implicit = visual.fields.filter { field in !explicit.contains { $0.field?.property == field.property } }
            .map { ReportFilter(id: "implicit-\($0.queryRef)-\($0.role)", level: .visual, field: $0,
                                type: "Categorical", summary: "là (Tất cả)", isHidden: false, isLocked: false) }
        var seen = Set<String>()
        return (explicit + implicit).filter { seen.insert($0.field?.queryRef ?? $0.id).inserted }
    }

    /// Thẻ của một nhóm: bộ lọc trong file (trừ cái đã bỏ), rồi thẻ người dùng thêm.
    private func cards(_ filters: [ReportFilter], scope: String, level: ReportFilter.Level) -> [ReportFilter] {
        let interaction = state.interaction
        let kept = filters.filter { !interaction.effectiveRemovedFilters.contains(key($0, level, scope)) }
        let added = interaction.effectiveUserFilters
            .filter { $0.key.level == level && $0.key.scope == scope && $0.key.filterID.hasPrefix("added-") }
            .sorted { $0.key.filterID < $1.key.filterID }
            .map { entry -> ReportFilter in
                let column = entry.value.column
                let field = ReportField(role: "Filter", kind: .column, entity: column.table, property: column.column,
                                        function: nil, displayName: nil, queryRef: "\(column.table).\(column.column)")
                return ReportFilter(id: entry.key.filterID, level: level, field: field, type: "Categorical",
                                    summary: "là (Tất cả)", isHidden: false, isLocked: false)
            }
        return kept + added
    }

    @ViewBuilder private func section(_ title: String, filters: [ReportFilter], scope: String, level: ReportFilter.Level,
                                      empty: String) -> some View {
        let shown = cards(filters, scope: scope, level: level)
            .filter { search.isEmpty || ($0.field.map(cardTitle) ?? $0.id).localizedCaseInsensitiveContains(search) }
        Text(title).font(.system(size: 12)).foregroundStyle(DS.Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
        VStack(spacing: 6) {
            ForEach(shown) { filter in
                FilterCard(filter: filter, key: key(filter, level, scope), interaction: state.interaction,
                           title: filter.field.map(cardTitle) ?? filter.id,
                           removable: !filter.id.hasPrefix("implicit-"))
            }
            AddFieldMenu(interaction: state.interaction, level: level, scope: scope)
                .disabled(state.reportEditingBlocker != nil)
        }
        .padding(.horizontal, 10)
    }
}

/// Ô "Thêm field dữ liệu vào đây": chọn cột từ danh sách (Power BI kéo field từ pane Dữ liệu; kéo thả chưa làm).
struct AddFieldMenu: View {
    let interaction: ReportInteraction
    let level: ReportFilter.Level
    let scope: String

    var body: some View {
        Menu {
            ForEach(interaction.filterableColumns(), id: \.table) { entry in
                Menu(entry.table) {
                    ForEach(entry.columns, id: \.self) { name in
                        Button(name) { interaction.addFilter(column: QueryColumn(table: entry.table, column: name), level: level, scope: scope) }
                    }
                }
            }
        } label: {
            Text(bi("Thêm field dữ liệu vào đây", "Add data fields here")).font(.system(size: 12)).foregroundStyle(DS.Palette.secondaryLabel)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.canvas))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(DS.Palette.separator))
        }
        .menuStyle(.button).buttonStyle(.plain)
        .help(bi("Chọn cột để thêm bộ lọc", "Choose a column to add a filter"))
    }
}

/// Thẻ bộ lọc theo Power BI: chưa lọc thì nền trắng, chữ thường; đang lọc hoặc đang mở thì nền xám, tên đậm.
struct FilterCard: View {
    let filter: ReportFilter
    let key: UserFilterKey
    let interaction: ReportInteraction
    /// Nhãn thẻ (theo `LayoutEditor.label(of:)`, cùng nhãn ở Build pane).
    var title: String? = nil
    var removable = false
    @State private var open = false

    var body: some View {
        let editable = FilterEditing.column(of: filter)
        let active = FilterEditing.isActive(filter, key: key, interaction: interaction)
        let grey = active || open
        let blocker = interaction.editing?.blocker()
        VStack(alignment: .leading, spacing: 0) {
            Button { if editable != nil { open.toggle() } } label: { header(active: grey) }
                .buttonStyle(.plain)
            if open, let column = editable {
                FilterEditorBody(interaction: interaction, key: key, filter: filter, column: column, measure: filter.field?.kind == .measure)
                    .disabled(blocker != nil)
                    .opacity(blocker == nil ? 1 : 0.6)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 3).fill(grey ? Color.dynamic(light: 0xD2D2D7, dark: 0x3A3A3C) : DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(grey ? Color.clear : DS.Palette.separator))
        .opacity(filter.isHidden ? 0.7 : 1)
        .help(filter.field.map { "\($0.entity)[\($0.property)]" } ?? "")
    }

    /// Lý do thẻ (đã sửa ở lớp tài liệu) chưa lưu vào file được, hoặc nil.
    private var unsavedReason: String? {
        guard case .set(let edit) = interaction.documentEdits.filters[key] else { return nil }
        return FilterExport.card(for: edit, key: key).reason
    }

    private func header(active: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title ?? filter.field?.label ?? filter.id)
                    .font(.system(size: 13, weight: active ? .bold : .regular))
                    .foregroundStyle(DS.Palette.label).lineLimit(1)
                Text(FilterEditing.summary(of: filter, key: key, interaction: interaction))
                    .font(.system(size: 12)).foregroundStyle(DS.Palette.label).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let reason = unsavedReason {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(bi("Chưa lưu được vào file: \(reason)", "Cannot save to file: \(reason)"))
            }
            if interaction.effectiveUserFilters[key] != nil, !key.filterID.hasPrefix("added-") {
                Button { interaction.setUserFilter(nil, for: key) } label: { Image(systemName: "eraser") }
                    .buttonStyle(.plain).help(bi("Đặt lại về bộ lọc trong file", "Reset to file filter")).disabled(interaction.editing?.blocker() != nil)
            }
            if removable {
                Button { interaction.removeFilter(key) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help(bi("Bỏ bộ lọc này", "Remove this filter")).disabled(interaction.editing?.blocker() != nil)
            }
            if filter.isHidden { Image(systemName: "eye.slash").help(bi("Ẩn khi xem báo cáo", "Hidden in report view")) }
            if filter.isLocked { Image(systemName: "lock").help(bi("Bị khoá khi xem báo cáo", "Locked in report view")) }
        }
        .font(.system(size: 11))
        .foregroundStyle(DS.Palette.secondaryLabel)
        .contentShape(Rectangle())
    }
}

// MARK: - Visualizations (Build / Format)

struct VisualizationsPane: View {
    @Bindable var state: DocumentState
    var collapse: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: tr(.paneVisualizations), symbol: "chart.bar.xaxis", collapse: collapse)
            SegmentedPill(selection: $state.visualizationsTab, options: [
                .init(value: .build, title: tr(.paneBuild), symbol: "chart.bar"),
                .init(value: .format, title: tr(.paneFormat), symbol: "paintbrush"),
            ], fill: true)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            ScrollView {
                if state.visualizationsTab == .build { build } else { format }
            }
            PaneFooter(text: state.visual.map { VisualCatalog.name($0.type) } ?? bi("Chưa chọn visual", "No visual selected"))
        }
        .background(DS.Palette.chrome)
    }

    // MARK: Build

    /// Biểu tượng của thư viện: không chọn visual thì thêm visual mới, chọn một visual thì đổi loại (D3).
    @ViewBuilder private func galleryButton(_ entry: VisualCatalog.Entry) -> some View {
        let selected = state.visual.map { VisualCatalog.matches($0.type, entry.type) } ?? false
        let supported = VisualTypes.isSupported(entry.type)
        let blocker = state.visualEditingBlocker
        let enabled = supported && blocker == nil
        let help = blocker ?? (supported ? (state.layout.selection.isEmpty ? bi("Thêm \(entry.name)", "Add \(entry.name)") : (selected ? entry.name : bi("Đổi thành \(entry.name)", "Change to \(entry.name)")))
                                         : VisualTypes.refusal(for: entry.type))
        Button { galleryTap(entry.type) } label: {
            Image(systemName: entry.symbol)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.white : DS.Palette.secondaryLabel)
                .frame(width: 32, height: 28)
                .background(RoundedRectangle(cornerRadius: 5).fill(selected ? DS.Palette.accent : DS.Palette.canvas))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.Palette.separator, lineWidth: selected ? 0 : 1))
                .opacity(enabled || selected ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func galleryTap(_ type: String) {
        if let blocker = state.visualEditingBlocker { state.layout.noteFieldRefusal(blocker); return }
        guard VisualTypes.isSupported(type) else { state.layout.noteFieldRefusal(VisualTypes.refusal(for: type)); return }
        if state.layout.selection.isEmpty { state.insertVisual(type) } else { state.changeType(type) }
    }

    private var build: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 6), spacing: 4) {
                ForEach(VisualCatalog.gallery, id: \.type) { entry in
                    galleryButton(entry)
                }
            }
            .padding(.horizontal, 10)
            FieldMessages(layout: state.layout)

            if let visual = state.visual {
                BuildWells(state: state, visual: visual)
            } else {
                Text(bi("Chọn một visual trên trang để xem các field của nó.", "Select a visual on the page to view its fields."))
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(12)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: Format

    private var format: some View { FormatPane(state: state) }
}

/// Thông báo của các thao tác sửa visual: lý do từ chối (đỏ, bấm để ẩn) và thông báo sau thao tác (D2, D3).
struct FieldMessages: View {
    let layout: LayoutEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = layout.fieldRefusal {
                Text(message).font(DS.Typeface.bodySmall).foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { layout.clearFieldRefusal() }
                    .help(bi("Bấm để ẩn", "Click to dismiss"))
            }
            if let notice = layout.notice {
                Text(notice).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, layout.fieldRefusal == nil && layout.notice == nil ? 0 : 8)
    }
}

// MARK: - Selection & bookmarks

struct SelectionPane: View {
    @Bindable var state: DocumentState
    var collapse: (() -> Void)?

    /// Một dòng của Selection pane: visual, nhóm, hoặc visual con của nhóm (thụt vào).
    struct Row: Identifiable {
        let item: ReportVisual
        let indent: Int
        let children: [ReportVisual]
        var id: String { item.id }

        /// Mắt của nhóm áp lên từng visual bên trong (mọi cấp): nhóm ẩn khi mọi visual đó đang ẩn.
        @MainActor func isHidden(_ interaction: ReportInteraction) -> Bool {
            item.isGroup ? !children.isEmpty && children.allSatisfy { interaction.isHidden($0) } : interaction.isHidden(item)
        }

        @MainActor func toggleHidden(_ interaction: ReportInteraction) {
            guard item.isGroup else { interaction.toggleHidden(item); return }
            let hide = !isHidden(interaction)
            for child in children where interaction.isHidden(child) != hide { interaction.toggleHidden(child) }
        }
    }

    /// Theo thứ tự lớp (`z` giảm dần); thành viên của nhóm nằm ngay dưới nhóm, nhóm lồng nhau thụt thêm một cấp (VM-D8).
    private var rows: [Row] {
        let page = state.page
        let groups = page?.groups ?? []
        let all = (page?.visuals ?? []) + groups
        let known = Set(groups.map(\.id))
        var out: [Row] = []
        func add(_ item: ReportVisual, indent: Int) {
            guard indent < 32 else { return }   // chặn vòng `parentGroupName` trong file hỏng
            let inside = item.isGroup ? LayoutEditor.descendantIDs(of: item.id, in: all) : []
            out.append(Row(item: item, indent: indent, children: all.filter { inside.contains($0.id) && !$0.isGroup }))
            guard item.isGroup else { return }
            for member in all.filter({ $0.parentGroup == item.id }).sorted(by: { $0.z > $1.z }) { add(member, indent: indent + 1) }
        }
        for item in all.filter({ $0.parentGroup.map { !known.contains($0) } ?? true }).sorted(by: { $0.z > $1.z }) { add(item, indent: 0) }
        return out
    }

    var body: some View {
        let total = state.page?.visuals.count ?? 0
        let hiddenCount = (state.page?.visuals ?? []).filter { state.interaction.isHidden($0) }.count
        VStack(spacing: 0) {
            PaneHeader(title: tr(.paneSelection), symbol: "square.3.layers.3d", collapse: collapse)
            SectionLabel(text: bi("Thứ tự lớp", "Layer order"))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        let visual = row.item
                        let selected = state.layout.selection.contains(visual.id) || state.visualID == visual.id
                        let hidden = row.isHidden(state.interaction)
                        Button {
                            // Shift-bấm thêm/bớt khỏi vùng chọn (nhiều visual); bấm thường chọn riêng.
                            if NSEvent.modifierFlags.contains(.shift) {
                                state.layout.select(visual.id, extend: true)
                                state.visualID = state.layout.primary
                            } else if visual.isGroup {
                                state.layout.select(visual.id)
                                state.visualID = state.layout.primary
                            } else {
                                state.visualID = visual.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(DS.Palette.tertiaryLabel)
                                Image(systemName: visual.isGroup ? "square.on.square.dashed" : VisualCatalog.symbol(visual.type)).font(.system(size: 11))
                                    .foregroundStyle(selected ? .white : DS.Palette.secondaryLabel).frame(width: 14)
                                Text(visual.isGroup ? (visual.groupDisplayName ?? bi("Nhóm", "Group")) : VisualCatalog.displayTitle(visual)).font(DS.Typeface.bodySmall).lineLimit(1)
                                    .foregroundStyle(selected ? .white : DS.Palette.label)
                                Spacer()
                                Image(systemName: hidden ? "eye.slash" : "eye").font(.system(size: 10))
                                    .foregroundStyle(selected ? .white : DS.Palette.tertiaryLabel)
                                    .frame(width: 24, height: DS.Metrics.navRow)
                                    .contentShape(Rectangle())
                                    .onTapGesture { row.toggleHidden(state.interaction) }
                                    .help(hidden ? bi("Hiện visual", "Show visual") : bi("Ẩn visual", "Hide visual"))
                                    .accessibilityLabel(hidden ? tr(.a11yHidden) : tr(.a11yVisible))
                                    .accessibilityAddTraits(.isButton)
                            }
                            .padding(.leading, 10 + CGFloat(row.indent) * 16)
                            .padding(.trailing, 10)
                            .frame(height: DS.Metrics.navRow)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(selected ? DS.Palette.accent : .clear).padding(.horizontal, 4))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            PaneFooter(text: bi("\(total) đối tượng, \(hiddenCount) ẩn", "\(total) objects, \(hiddenCount) hidden"))
        }
        .background(DS.Palette.chrome)
    }
}

struct BookmarksPane: View {
    @Bindable var state: DocumentState
    var collapse: (() -> Void)?
    @State private var renaming: String?
    @State private var newName = ""
    /// Bookmark đánh dấu để nhóm (Shift-bấm), ngoài bookmark đang áp.
    @State private var selectedBookmarks: Set<String> = []

    var body: some View {
        let interaction = state.interaction
        let rows = interaction.bookmarkRows
        VStack(spacing: 0) {
            PaneHeader(title: tr(.paneBookmarks), symbol: "bookmark", collapse: collapse) {
                Button {
                    state.addBookmark()
                } label: { Image(systemName: "plus") }
                    .buttonStyle(GhostIconButtonStyle())
                    .disabled(state.reportEditingBlocker != nil)
                    .help(state.reportEditingBlocker ?? bi("Thêm bookmark từ trạng thái hiện tại", "Add bookmark from current state"))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups(rows).enumerated()), id: \.offset) { _, group in
                        if let name = group.name {
                            SectionLabel(text: name)
                                .contextMenu {
                                    if let id = group.items.first?.groupID {
                                        Button(bi("Bỏ nhóm", "Ungroup")) { state.ungroupBookmarks(groupID: id) }.disabled(state.reportEditingBlocker != nil)
                                    }
                                }
                        }
                        ForEach(group.items) { row in row_(row, interaction: interaction) }
                    }
                    if rows.isEmpty {
                        Text(bi("Báo cáo chưa có bookmark. Bấm + để thêm.", "No bookmarks yet. Click + to add one.")).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel).padding(12)
                    }
                }
            }
            PaneFooter(text: state.layout.fieldRefusal ?? bi("\(rows.count) bookmark", "\(rows.count) bookmarks"))
        }
        .background(DS.Palette.chrome)
        .alert(bi("Đổi tên bookmark", "Rename bookmark"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(bi("Tên", "Name"), text: $newName)
            Button(bi("Đổi tên", "Rename")) { if let id = renaming { state.renameBookmark(id: id, to: newName) }; renaming = nil }
            Button(bi("Huỷ", "Cancel"), role: .cancel) { renaming = nil }
        }
    }

    private func row_(_ row: ReportInteraction.BookmarkRow, interaction: ReportInteraction) -> some View {
        let active = interaction.visibility.activeBookmarkID == row.id
        let mine = interaction.userBookmark(id: row.id)
        let blocker = state.reportEditingBlocker
        let unsaved = row.isUser ? state.bookmarkSaveBlocker(id: row.id) : nil
        return Button {
            if NSEvent.modifierFlags.contains(.shift) {
                // Shift-bấm chọn nhiều bookmark để nhóm, không áp.
                if selectedBookmarks.contains(row.id) { selectedBookmarks.remove(row.id) } else { selectedBookmarks.insert(row.id) }
            } else if let page = interaction.applyAnyBookmark(id: row.id) {
                selectedBookmarks = []
                state.pageID = page; state.visualID = nil
            } else {
                selectedBookmarks = []
            }
            // Bỏ khỏi vùng chọn các bookmark không còn (đã xoá).
            selectedBookmarks.formIntersection(Set(interaction.bookmarkRows.map(\.id)))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: active ? "bookmark.fill" : "bookmark").font(.system(size: 11))
                    .foregroundStyle(active ? DS.Palette.accent : DS.Palette.secondaryLabel)
                Text(row.name).font(DS.Typeface.bodySmall).lineLimit(1)
                Spacer()
                if let unsaved {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(.orange)
                        .help(bi("Chưa lưu được vào file: \(unsaved)", "Cannot save to file: \(unsaved)"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: DS.Metrics.navRow)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(selectedBookmarks.contains(row.id) ? DS.Palette.accent.opacity(0.25) : (active ? DS.Palette.accent.opacity(0.12) : .clear))
                .padding(.horizontal, 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(row.suppressData ? bi("Áp dụng bookmark (không đổi bộ lọc, slicer)", "Apply bookmark (keep filters & slicers)") : bi("Áp dụng bookmark", "Apply bookmark"))
        .contextMenu {
            Button(bi("Cập nhật", "Update")) { state.updateBookmark(id: row.id) }.disabled(blocker != nil)
            Button(bi("Đổi tên…", "Rename…")) { newName = row.name; renaming = row.id }.disabled(blocker != nil)
            Button(bi("Xoá", "Delete"), role: .destructive) { state.deleteBookmark(id: row.id) }.disabled(blocker != nil)
            Divider()
            Button(selectedBookmarks.count >= 2 && selectedBookmarks.contains(row.id) ? bi("Nhóm \(selectedBookmarks.count) bookmark", "Group \(selectedBookmarks.count) bookmarks") : bi("Nhóm với bookmark đang chọn", "Group with selected bookmarks")) {
                state.groupBookmarks(Array(selectedBookmarks.union([row.id])))
            }
            .disabled(blocker != nil || row.groupID != nil)
            if row.groupID != nil { Button(bi("Bỏ nhóm", "Ungroup")) { if let id = row.groupID { state.ungroupBookmarks(groupID: id) } }.disabled(blocker != nil) }
            Divider()
            Button(bi("Chuyển lên", "Move up")) { state.moveBookmark(id: row.id, by: -1) }.disabled(blocker != nil)
            Button(bi("Chuyển xuống", "Move down")) { state.moveBookmark(id: row.id, by: 1) }.disabled(blocker != nil)
            if let mine {
                Divider()
                Toggle(bi("Data (bộ lọc, slicer, drill)", "Data (filters, slicers, drill)"), isOn: Binding(get: { mine.data }, set: { state.setBookmarkOption(id: row.id, data: $0) })).disabled(blocker != nil)
                Toggle(bi("Display (ẩn/hiện visual)", "Display (visual visibility)"), isOn: Binding(get: { mine.display }, set: { state.setBookmarkOption(id: row.id, display: $0) })).disabled(blocker != nil)
                Toggle(bi("Current page (chuyển về trang đã lưu)", "Current page (switch to saved page)"), isOn: Binding(get: { mine.currentPage }, set: { state.setBookmarkOption(id: row.id, currentPage: $0) })).disabled(blocker != nil)
            }
        }
    }

    private func groups(_ items: [ReportInteraction.BookmarkRow]) -> [(name: String?, items: [ReportInteraction.BookmarkRow])] {
        var order: [String?] = []
        var map: [String?: [ReportInteraction.BookmarkRow]] = [:]
        for b in items {
            if map[b.group] == nil { order.append(b.group) }
            map[b.group, default: []].append(b)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}
