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
            PaneHeader(title: "Bộ lọc", symbol: "line.3.horizontal.decrease", collapse: collapse)
            SearchField(text: $search, prompt: "Tìm bộ lọc").padding(.horizontal, 10).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let visual = state.visual {
                        section("Bộ lọc trên visual này", filters: visualLevelFilters(visual), scope: visual.id, level: .visual, empty: "Visual chưa có field")
                    }
                    section("Bộ lọc trên trang này", filters: state.pageID.flatMap { w.pageFilters[$0] } ?? [], scope: state.pageID ?? "",
                            level: .page, empty: "Chưa có bộ lọc trang")
                    section("Bộ lọc trên mọi trang", filters: w.reportFilters, scope: "", level: .report, empty: "Chưa có bộ lọc báo cáo")
                }
                .padding(.bottom, 10)
            }
            PaneFooter(text: "\(activeCount) bộ lọc đang áp dụng")
        }
        .background(DS.Palette.chrome)
    }

    private var activeCount: Int {
        let w = state.workspace, interaction = state.interaction
        let pageID = state.pageID ?? ""
        let page = pageID.isEmpty ? [] : (w.pageFilters[pageID] ?? [])
        func count(_ filters: [ReportFilter], _ level: ReportFilter.Level, _ scope: String) -> Int {
            filters.filter { !interaction.removedFilters.contains(key($0, level, scope)) }
                .filter { FilterEditing.isActive($0, key: key($0, level, scope), interaction: interaction) }.count
        }
        let added = interaction.userFilters.filter {
            $0.key.filterID.hasPrefix("added-") && $0.value.isActive
                && (($0.key.level == .report) || ($0.key.level == .page && $0.key.scope == pageID))
        }.count
        return count(w.reportFilters, .report, "") + count(page, .page, pageID) + added
    }

    private func key(_ filter: ReportFilter, _ level: ReportFilter.Level, _ scope: String) -> UserFilterKey {
        UserFilterKey(level: level, scope: scope, filterID: filter.id)
    }

    /// Power BI lists every field of the selected visual as a filter card, plus explicit visual filters.
    private func visualLevelFilters(_ visual: ReportVisual) -> [ReportFilter] {
        let explicit = state.workspace.visualFilters[visual.id] ?? []
        let implicit = visual.fields.filter { field in !explicit.contains { $0.field?.property == field.property } }
            .map { ReportFilter(id: "implicit-\($0.queryRef)-\($0.role)", level: .visual, field: $0,
                                type: "Categorical", summary: "là (Tất cả)", isHidden: false, isLocked: false) }
        var seen = Set<String>()
        return (explicit + implicit).filter { seen.insert($0.field?.queryRef ?? $0.id).inserted }
    }

    /// Thẻ của một nhóm: bộ lọc trong file (trừ cái đã bỏ), rồi thẻ người dùng thêm.
    private func cards(_ filters: [ReportFilter], scope: String, level: ReportFilter.Level) -> [ReportFilter] {
        let interaction = state.interaction
        let kept = filters.filter { !interaction.removedFilters.contains(key($0, level, scope)) }
        let added = interaction.userFilters
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
            .filter { search.isEmpty || ($0.field?.label ?? $0.id).localizedCaseInsensitiveContains(search) }
        Text(title).font(.system(size: 12)).foregroundStyle(DS.Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
        VStack(spacing: 6) {
            ForEach(shown) { filter in
                FilterCard(filter: filter, key: key(filter, level, scope), interaction: state.interaction,
                           removable: !filter.id.hasPrefix("implicit-"))
            }
            AddFieldMenu(interaction: state.interaction, level: level, scope: scope)
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
            Text("Thêm field dữ liệu vào đây").font(.system(size: 12)).foregroundStyle(DS.Palette.secondaryLabel)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(DS.Palette.separator))
        }
        .menuStyle(.button).buttonStyle(.plain)
        .help("Chọn cột để thêm bộ lọc")
    }
}

/// Thẻ bộ lọc theo Power BI: chưa lọc thì nền trắng, chữ thường; đang lọc hoặc đang mở thì nền xám, tên đậm.
struct FilterCard: View {
    let filter: ReportFilter
    let key: UserFilterKey
    let interaction: ReportInteraction
    var removable = false
    @State private var open = false

    var body: some View {
        let editable = FilterEditing.column(of: filter)
        let active = FilterEditing.isActive(filter, key: key, interaction: interaction)
        let grey = active || open
        VStack(alignment: .leading, spacing: 0) {
            Button { if editable != nil { open.toggle() } } label: { header(active: grey) }
                .buttonStyle(.plain)
            if open, let column = editable {
                FilterEditorBody(interaction: interaction, key: key, filter: filter, column: column, measure: filter.field?.kind == .measure)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 3).fill(grey ? Color(hex: "#D2D2D7")! : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(grey ? Color.clear : DS.Palette.separator))
        .opacity(filter.isHidden ? 0.7 : 1)
        .help(filter.field.map { "\($0.entity)[\($0.property)]" } ?? "")
    }

    private func header(active: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(filter.field?.label ?? filter.id)
                    .font(.system(size: 13, weight: active ? .bold : .regular))
                    .foregroundStyle(DS.Palette.label).lineLimit(1)
                Text(FilterEditing.summary(of: filter, key: key, interaction: interaction))
                    .font(.system(size: 12)).foregroundStyle(DS.Palette.label).lineLimit(2)
            }
            Spacer(minLength: 0)
            if interaction.userFilters[key] != nil, !key.filterID.hasPrefix("added-") {
                Button { interaction.setUserFilter(nil, for: key) } label: { Image(systemName: "eraser") }
                    .buttonStyle(.plain).help("Đặt lại về bộ lọc trong file")
            }
            if removable {
                Button { interaction.removeFilter(key) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Bỏ bộ lọc này")
            }
            if filter.isHidden { Image(systemName: "eye.slash").help("Ẩn khi xem báo cáo") }
            if filter.isLocked { Image(systemName: "lock").help("Bị khoá khi xem báo cáo") }
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
            PaneHeader(title: "Trực quan hóa", symbol: "chart.bar.xaxis", collapse: collapse)
            SegmentedPill(selection: $state.visualizationsTab, options: [
                .init(value: .build, title: "Xây dựng", symbol: "chart.bar"),
                .init(value: .format, title: "Định dạng", symbol: "paintbrush"),
            ], fill: true)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            ScrollView {
                if state.visualizationsTab == .build { build } else { format }
            }
            PaneFooter(text: state.visual.map { VisualCatalog.name($0.type) } ?? "Chưa chọn visual")
        }
        .background(DS.Palette.chrome)
    }

    // MARK: Build

    private var build: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 6), spacing: 4) {
                ForEach(VisualCatalog.gallery, id: \.type) { entry in
                    let selected = state.visual.map { VisualCatalog.matches($0.type, entry.type) } ?? false
                    Image(systemName: entry.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? Color.white : DS.Palette.secondaryLabel)
                        .frame(width: 32, height: 28)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? DS.Palette.accent : Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.Palette.separator, lineWidth: selected ? 0 : 1))
                        .help(entry.name + (selected ? "" : " (đổi loại visual: Phase D)"))
                }
            }
            .padding(.horizontal, 10)

            if let visual = state.visual {
                ForEach(VisualCatalog.wells(for: visual), id: \.role) { well in
                    SectionLabel(text: well.label)
                    VStack(spacing: 4) {
                        let fields = visual.fields.filter { $0.role == well.role }
                        if fields.isEmpty {
                            Text("+ Thêm field").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel)
                                .frame(maxWidth: .infinity).frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        ForEach(fields, id: \.self) { field in
                            FieldChip(symbol: fieldSymbol(field), tint: field.kind == .measure ? DS.Palette.measure : DS.Palette.secondaryLabel,
                                      title: field.label, subtitle: field.label == field.property ? field.entity : "\(field.entity)[\(field.property)]")
                        }
                    }
                    .padding(.horizontal, 10)
                }
            } else {
                Text("Chọn một visual trên trang để xem các field của nó.")
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(12)
            }
        }
        .padding(.bottom, 12)
    }

    private func fieldSymbol(_ field: ReportField) -> String {
        switch field.kind {
        case .measure: return "function"
        case .aggregation: return "sum"
        case .hierarchyLevel: return "list.bullet.indent"
        case .column, .other:
            return state.workspace.column(table: field.entity, name: field.property).map(columnSymbol) ?? "textformat.abc"
        }
    }

    // MARK: Format

    @State private var formatScope: FormatScope = .visual
    enum FormatScope: Hashable { case visual, general }

    @ViewBuilder private var format: some View {
        if let visual = state.visual {
            VStack(spacing: 8) {
                SegmentedPill(selection: $formatScope, options: [
                    .init(value: .visual, title: "Visual"),
                    .init(value: .general, title: "Chung"),
                ], fill: true)
                let objects = formatScope == .visual ? visual.objects : visual.containerObjects
                let keys = (objects.json.object.keys).sorted()
                if keys.isEmpty {
                    Text("Đang dùng định dạng mặc định của theme.")
                        .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).padding(.top, 8)
                }
                ForEach(keys, id: \.self) { key in
                    FormatCard(title: FormatNames.object(key), properties: objects.json[key]?.array ?? [], theme: state.workspace.theme)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        } else {
            Text("Chọn một visual để xem định dạng của nó.")
                .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).padding(12)
        }
    }
}

/// One collapsible card in the Format pane (read-only until Phase D).
struct FormatCard: View {
    let title: String
    let properties: [JSONValue]
    let theme: ReportTheme
    @State private var open = true

    var body: some View {
        let merged = mergedProperties
        VStack(alignment: .leading, spacing: 0) {
            Button { open.toggle() } label: {
                HStack {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel).frame(width: 10)
                    Text(title).font(DS.Typeface.headlineSmall).foregroundStyle(DS.Palette.label)
                    Spacer()
                    if let show = merged.first(where: { $0.key == "show" }), case .bool(let on)? = ReportLiteral(expression: show.value["expr"]) {
                        SwitchMark(isOn: on)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(spacing: 0) {
                    ForEach(merged.filter { $0.key != "show" }, id: \.key) { property in
                        HStack {
                            Text(FormatNames.property(property.key)).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                            Spacer(minLength: 8)
                            valueView(property.value)
                        }
                        .frame(minHeight: 24)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
    }

    private var mergedProperties: [(key: String, value: JSONValue)] {
        var merged: [String: JSONValue] = [:]
        for instance in properties {
            if let id = instance["selector"]?["id"]?.string, id != "default" { continue }
            for (k, v) in instance["properties"]?.object ?? [:] { merged[k] = v }
        }
        return merged.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    @ViewBuilder private func valueView(_ value: JSONValue) -> some View {
        if let color = value["solid"]?["color"]?["expr"], let literal = ReportLiteral(expression: color) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(theme.color(literal) ?? .gray).frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.1)))
                Text(colorText(literal)).font(DS.Typeface.mono).foregroundStyle(DS.Palette.secondaryLabel)
            }
            .valueBox()
        } else if let literal = ReportLiteral(expression: value["expr"]) {
            switch literal {
            case .bool(let on): SwitchMark(isOn: on)
            case .number(let n): Text(n == n.rounded() ? String(Int(n)) : String(n)).font(DS.Typeface.bodySmall).valueBox()
            case .string(let s): Text(s).font(DS.Typeface.bodySmall).lineLimit(1).valueBox()
            case .resource(let r): Text(r).font(DS.Typeface.bodySmall).lineLimit(1).valueBox()
            default: Text("—").valueBox()
            }
        } else {
            Text("…").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel).valueBox()
        }
    }

    private func colorText(_ literal: ReportLiteral) -> String {
        switch literal {
        case .string(let hex): hex.uppercased()
        case .themeColor(let id, let percent): "Theme \(id)" + (percent == 0 ? "" : " \(Int(percent * 100))%")
        default: "—"
        }
    }
}

private extension View {
    func valueBox() -> some View {
        self.padding(.horizontal, 6).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.chrome))
            .frame(maxWidth: 130, alignment: .trailing)
    }
}

// MARK: - Selection & bookmarks

struct SelectionPane: View {
    @Bindable var state: DocumentState
    var collapse: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Lựa chọn", symbol: "square.3.layers.3d", collapse: collapse)
            SectionLabel(text: "Thứ tự lớp")
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach((state.page?.visuals ?? []).sorted { $0.z > $1.z }) { visual in
                        let selected = state.layout.selection.contains(visual.id) || state.visualID == visual.id
                        let hidden = state.interaction.isHidden(visual)
                        Button {
                            // Shift-bấm thêm/bớt khỏi vùng chọn (nhiều visual); bấm thường chọn riêng.
                            if NSEvent.modifierFlags.contains(.shift) {
                                state.layout.select(visual.id, extend: true)
                                state.visualID = state.layout.primary
                            } else {
                                state.visualID = visual.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(DS.Palette.tertiaryLabel)
                                Image(systemName: VisualCatalog.symbol(visual.type)).font(.system(size: 11))
                                    .foregroundStyle(selected ? .white : DS.Palette.secondaryLabel).frame(width: 14)
                                Text(VisualCatalog.displayTitle(visual)).font(DS.Typeface.bodySmall).lineLimit(1)
                                    .foregroundStyle(selected ? .white : DS.Palette.label)
                                Spacer()
                                Image(systemName: hidden ? "eye.slash" : "eye").font(.system(size: 10))
                                    .foregroundStyle(selected ? .white : DS.Palette.tertiaryLabel)
                                    .frame(width: 24, height: DS.Metrics.navRow)
                                    .contentShape(Rectangle())
                                    .onTapGesture { state.interaction.toggleHidden(visual) }
                                    .help(hidden ? "Hiện visual" : "Ẩn visual")
                            }
                            .padding(.horizontal, 10)
                            .frame(height: DS.Metrics.navRow)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(selected ? DS.Palette.accent : .clear).padding(.horizontal, 4))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            PaneFooter(text: "\(state.page?.visuals.count ?? 0) đối tượng, \((state.page?.visuals ?? []).filter { state.interaction.isHidden($0) }.count) ẩn")
        }
        .background(DS.Palette.chrome)
    }
}

struct BookmarksPane: View {
    @Bindable var state: DocumentState
    var collapse: (() -> Void)?
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        let interaction = state.interaction
        let rows = interaction.bookmarkRows
        VStack(spacing: 0) {
            PaneHeader(title: "Bookmark", symbol: "bookmark", collapse: collapse) {
                Button {
                    interaction.addBookmark(currentPageID: state.pageID)
                } label: { Image(systemName: "plus") }
                    .buttonStyle(GhostIconButtonStyle())
                    .help("Thêm bookmark từ trạng thái hiện tại")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups(rows).enumerated()), id: \.offset) { _, group in
                        if let name = group.name { SectionLabel(text: name) }
                        ForEach(group.items) { row in row_(row, interaction: interaction) }
                    }
                    if rows.isEmpty {
                        Text("Báo cáo chưa có bookmark. Bấm + để thêm.").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel).padding(12)
                    }
                }
            }
            PaneFooter(text: "\(rows.count) bookmark")
        }
        .background(DS.Palette.chrome)
        .alert("Đổi tên bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên", text: $newName)
            Button("Đổi tên") { if let id = renaming { interaction.renameBookmark(id: id, to: newName) }; renaming = nil }
            Button("Huỷ", role: .cancel) { renaming = nil }
        }
    }

    private func row_(_ row: ReportInteraction.BookmarkRow, interaction: ReportInteraction) -> some View {
        let active = interaction.visibility.activeBookmarkID == row.id
        let mine = interaction.userBookmarks.first { $0.id == row.id }
        return Button {
            if let page = interaction.applyAnyBookmark(id: row.id) { state.pageID = page; state.visualID = nil }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: active ? "bookmark.fill" : "bookmark").font(.system(size: 11))
                    .foregroundStyle(active ? DS.Palette.accent : DS.Palette.secondaryLabel)
                Text(row.name).font(DS.Typeface.bodySmall).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: DS.Metrics.navRow)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(active ? DS.Palette.accent.opacity(0.12) : .clear).padding(.horizontal, 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(row.suppressData ? "Áp dụng bookmark (không đổi bộ lọc, slicer)" : "Áp dụng bookmark")
        .contextMenu {
            Button("Cập nhật") { interaction.updateBookmark(id: row.id, currentPageID: state.pageID) }
            Button("Đổi tên…") { newName = row.name; renaming = row.id }
            Button("Xoá", role: .destructive) { interaction.deleteBookmark(id: row.id) }
            if let mine {
                Divider()
                Toggle("Data (bộ lọc, slicer, drill)", isOn: Binding(get: { mine.data }, set: { interaction.setBookmarkOption(id: row.id, data: $0) }))
                Toggle("Display (ẩn/hiện visual)", isOn: Binding(get: { mine.display }, set: { interaction.setBookmarkOption(id: row.id, display: $0) }))
                Toggle("Current page (chuyển về trang đã lưu)", isOn: Binding(get: { mine.currentPage }, set: { interaction.setBookmarkOption(id: row.id, currentPage: $0) }))
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
