import PBIXKit
import SwiftUI

// MARK: - Filters

struct FiltersPane: View {
    let state: DocumentState
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
                        section("Bộ lọc trên visual này", filters: visualLevelFilters(visual), empty: "Visual chưa có field")
                    }
                    section("Bộ lọc trên trang này", filters: state.pageID.flatMap { w.pageFilters[$0] } ?? [], empty: "Chưa có bộ lọc trang")
                    section("Bộ lọc trên mọi trang", filters: w.reportFilters, empty: "Chưa có bộ lọc báo cáo")
                }
                .padding(.bottom, 10)
            }
            PaneFooter(text: "\(activeCount) bộ lọc đang áp dụng")
        }
        .background(DS.Palette.chrome)
    }

    private var activeCount: Int {
        let w = state.workspace
        let page = state.pageID.flatMap { w.pageFilters[$0] } ?? []
        return (w.reportFilters + page).filter(\.isActive).count
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

    @ViewBuilder private func section(_ title: String, filters: [ReportFilter], empty: String) -> some View {
        let shown = filters.filter { search.isEmpty || ($0.field?.label ?? $0.id).localizedCaseInsensitiveContains(search) }
        SectionLabel(text: title)
        if shown.isEmpty {
            Text(empty).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .padding(.horizontal, 10)
        } else {
            VStack(spacing: 6) {
                ForEach(shown) { FilterCard(filter: $0) }
            }
            .padding(.horizontal, 10)
        }
    }
}

struct FilterCard: View {
    let filter: ReportFilter

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.field?.label ?? filter.id)
                    .font(DS.Typeface.headlineSmall)
                    .foregroundStyle(filter.isActive ? DS.Palette.accent : DS.Palette.label)
                    .lineLimit(1)
                Text(filter.summary)
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineLimit(2)
                if let field = filter.field {
                    Text("\(field.entity)[\(field.property)]").font(DS.Typeface.mono).foregroundStyle(DS.Palette.tertiaryLabel).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if filter.isHidden { Image(systemName: "eye.slash").help("Ẩn khi xem báo cáo") }
            if filter.isLocked { Image(systemName: "lock").help("Bị khoá khi xem báo cáo") }
            Image(systemName: "chevron.down").font(.system(size: 9))
        }
        .font(.system(size: 10))
        .foregroundStyle(DS.Palette.tertiaryLabel)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
            .strokeBorder(filter.isActive ? DS.Palette.accent.opacity(0.6) : DS.Palette.separator))
        .opacity(filter.isHidden ? 0.7 : 1)
        .help("Chỉnh bộ lọc có ở Phase C")
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
                        let selected = state.visualID == visual.id
                        Button { state.visualID = visual.id } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(DS.Palette.tertiaryLabel)
                                Image(systemName: VisualCatalog.symbol(visual.type)).font(.system(size: 11))
                                    .foregroundStyle(selected ? .white : DS.Palette.secondaryLabel).frame(width: 14)
                                Text(VisualCatalog.displayTitle(visual)).font(DS.Typeface.bodySmall).lineLimit(1)
                                    .foregroundStyle(selected ? .white : DS.Palette.label)
                                Spacer()
                                Image(systemName: visual.isHidden ? "eye.slash" : "eye").font(.system(size: 10))
                                    .foregroundStyle(selected ? .white : DS.Palette.tertiaryLabel)
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
            PaneFooter(text: "\(state.page?.visuals.count ?? 0) đối tượng trên canvas")
        }
        .background(DS.Palette.chrome)
    }
}

struct BookmarksPane: View {
    let state: DocumentState
    var collapse: (() -> Void)?

    var body: some View {
        let bookmarks = state.workspace.bookmarks
        VStack(spacing: 0) {
            PaneHeader(title: "Bookmark", symbol: "bookmark", collapse: collapse)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups(bookmarks).enumerated()), id: \.offset) { _, group in
                        if let name = group.name { SectionLabel(text: name) }
                        ForEach(group.items) { bookmark in
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark").font(.system(size: 11)).foregroundStyle(DS.Palette.secondaryLabel)
                                Text(bookmark.displayName).font(DS.Typeface.bodySmall).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: DS.Metrics.navRow)
                            .help("Áp dụng bookmark có ở Phase C")
                        }
                    }
                    if bookmarks.isEmpty {
                        Text("Báo cáo chưa có bookmark").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel).padding(12)
                    }
                }
            }
            PaneFooter(text: "\(bookmarks.count) bookmark")
        }
        .background(DS.Palette.chrome)
    }

    private func groups(_ items: [ReportBookmark]) -> [(name: String?, items: [ReportBookmark])] {
        var order: [String?] = []
        var map: [String?: [ReportBookmark]] = [:]
        for b in items {
            if map[b.group] == nil { order.append(b.group) }
            map[b.group, default: []].append(b)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}
