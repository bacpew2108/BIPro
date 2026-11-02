import PBIXKit
import SwiftUI

/// The Data pane field list, following Power BI's conventions observed in the model metadata:
/// tables A–Z; display folders first, then fields A–Z; hidden fields omitted in report view;
/// Σ for numeric columns that summarize by default; geo icons from the data category.
struct DataPane: View {
    enum Purpose { case report, table, query }
    enum DataTab { case tables, model }

    let state: DocumentState
    var purpose: Purpose = .report
    var collapse: (() -> Void)?

    @State private var selectedTab: DataTab = .tables
    @State private var search = ""
    @State private var expanded: Set<String> = ["model:root"]

    var body: some View {
        VStack(spacing: 0) {
            headerView
            if purpose == .query {
                tabBar
            }
            SearchField(text: $search, prompt: "Tìm field…")
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if purpose == .query && selectedTab == .model {
                        ModelTreeView(
                            state: state,
                            search: search,
                            expanded: $expanded,
                            openNewQueryTab: { title, text, run in
                                openNewQueryTab(title: title, text: text, run: run)
                            },
                            collapseAll: { collapseAll() },
                            expandAll: { expandAll() },
                            renderTableNode: { table, level in
                                AnyView(tableNode(table, baseLevel: level))
                            }
                        )
                    } else {
                        ForEach(tables, id: \.id) { table in
                            tableNode(table, baseLevel: 0)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            PaneFooter(text: "\(tables.count) bảng · \(state.workspace.metadata?.measures.count ?? 0) measure")
        }
        .background(DS.Palette.chrome)
        .onAppear {
            if let table = state.table, purpose != .report { expanded.insert(table) }
            if purpose == .query { expanded.insert("model:root") }
        }
    }

    // MARK: - Header & Tabs

    @ViewBuilder
    private var headerView: some View {
        if purpose == .query {
            HStack(spacing: 6) {
                Text("Dữ liệu")
                    .font(DS.Typeface.headlineSmall)
                    .fontWeight(.bold)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                if let collapse {
                    Button(action: collapse) {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(GhostIconButtonStyle())
                    .help("Thu gọn")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
        } else {
            PaneHeader(title: "Dữ liệu", symbol: "cylinder.split.1x2", collapse: collapse)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 16) {
            tabButton(title: "Bảng", tab: .tables)
            tabButton(title: "Mô hình", tab: .model)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func tabButton(title: String, tab: DataTab) -> some View {
        Button(action: { selectedTab = tab }) {
            VStack(spacing: 4) {
                Text(title)
                    .font(DS.Typeface.bodySmall.weight(selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? DS.Palette.label : DS.Palette.secondaryLabel)
                Rectangle()
                    .fill(selectedTab == tab ? DS.Palette.accent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var tables: [ModelMetadata.Table] {
        state.workspace.userTables
            .filter { purpose != .report || !$0.isHidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var showHidden: Bool { purpose != .report }

    // MARK: - Nodes

    private enum Item: Identifiable {
        case folder(String, [Item])
        case measure(ModelMetadata.Measure)
        case column(ModelMetadata.Column)
        case hierarchy(ModelMetadata.Hierarchy)

        var id: String {
            switch self {
            case .folder(let name, _): "folder:" + name
            case .measure(let m): "m:" + m.name
            case .column(let c): "c:" + c.name
            case .hierarchy(let h): "h:" + h.name
            }
        }

        var sortName: String {
            switch self {
            case .folder(let name, _): name
            case .measure(let m): m.name
            case .column(let c): c.name
            case .hierarchy(let h): h.name
            }
        }

        var isFolder: Bool { if case .folder = self { true } else { false } }
    }

    private func items(for table: String) -> [Item] {
        let w = state.workspace
        let q = search.lowercased()
        func match(_ name: String) -> Bool { q.isEmpty || name.lowercased().contains(q) }

        var leaves: [(folder: String?, item: Item)] = []
        for m in w.measures(of: table) where (showHidden || !m.isHidden) && match(m.name) {
            leaves.append((m.displayFolder, .measure(m)))
        }
        for c in w.columns(of: table) where (showHidden || !c.isHidden) && match(c.name) {
            leaves.append((c.displayFolder, .column(c)))
        }
        for h in w.hierarchies(of: table) where (showHidden || !h.isHidden) && match(h.name) {
            leaves.append((h.displayFolder, .hierarchy(h)))
        }

        var folders: [String: [Item]] = [:]
        var root: [Item] = []
        for leaf in leaves {
            if let folder = leaf.folder { folders[folder, default: []].append(leaf.item) } else { root.append(leaf.item) }
        }
        let byName: (Item, Item) -> Bool = { $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }
        let folderItems = folders.map { Item.folder($0.key, $0.value.sorted(by: byName)) }.sorted(by: byName)
        return folderItems + root.sorted(by: byName)
    }

    @ViewBuilder
    private func tableNode(_ table: ModelMetadata.Table, baseLevel: Int = 0) -> some View {
        let isOpen = expanded.contains(table.name) || !search.isEmpty
        let children = items(for: table.name)
        if search.isEmpty || !children.isEmpty || table.name.lowercased().contains(search.lowercased()) {
            TreeRow(
                level: baseLevel,
                isExpanded: isOpen,
                hasChildren: true,
                symbol: table.name.lowercased().hasPrefix("fact") ? "tablecells.fill" : "tablecells",
                tint: DS.Palette.table,
                title: table.name,
                isHidden: table.isHidden,
                isSelected: purpose == .table && state.table == table.name && state.column == nil,
                trailing: purpose == .report ? nil : state.workspace.rowCount(table.name).formatted(.number.notation(.compactName))
            ) {
                toggle(table.name)
                if purpose == .table { state.select(table: table.name) }
            }
            .leftContextMenu {
                LeftMenuBuilder.tableMenuItems(
                    tableName: table.name,
                    onTop100: {
                        let cols = state.workspace.columns(of: table.name)
                        openNewQueryTab(title: table.name, text: QuickQueries.top100Rows(table: table.name, columns: cols), run: true)
                    },
                    onDefineNewMeasure: {
                        openNewQueryTab(title: "Measure mới", text: QuickQueries.defineNewMeasure(tableName: table.name), run: false)
                    },
                    onCollapseAll: { collapseAll() },
                    onExpandAll: { expandAll() }
                )
            }
            if isOpen {
                ForEach(children) { item in
                    node(item, table: table.name, level: baseLevel + 1)
                }
            }
        }
    }

    private func node(_ item: Item, table: String, level: Int) -> AnyView {
        switch item {
        case .folder(let name, let children):
            let key = "\(table)/\(name)"
            let isOpen = expanded.contains(key) || !search.isEmpty
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                TreeRow(level: level, isExpanded: isOpen, hasChildren: true, symbol: "folder", tint: DS.Palette.secondaryLabel,
                        title: name) { toggle(key) }
                if isOpen {
                    ForEach(children) { child in node(child, table: table, level: level + 1) }
                }
            })
        case .measure(let m):
            return AnyView(TreeRow(level: level, symbol: "function", tint: DS.Palette.measure, title: m.name,
                                   isHidden: m.isHidden, checkbox: checkbox(table, m.name),
                                   help: m.expression.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if purpose == .query {
                    state.daxQueries[state.daxSelection].text = DAXSnippets.defineAndEvaluate(m)
                }
            }
            .leftContextMenu {
                LeftMenuBuilder.measureMenuItems(
                    onEvaluate: {
                        openNewQueryTab(title: m.name, text: QuickQueries.evaluate(measure: m), run: true)
                    },
                    onDefineAndEvaluate: {
                        openNewQueryTab(title: m.name, text: QuickQueries.defineAndEvaluate(measure: m), run: true)
                    },
                    onDefineWithReferencesAndEvaluate: {
                        let allMeasures = state.workspace.metadata?.measures ?? []
                        let allColumns = state.workspace.metadata?.columns ?? []
                        openNewQueryTab(
                            title: m.name,
                            text: QuickQueries.defineWithReferencesAndEvaluate(
                                measure: m,
                                allMeasures: allMeasures,
                                allColumns: allColumns
                            ),
                            run: true
                        )
                    },
                    onDefineNewMeasure: {
                        openNewQueryTab(
                            title: "Measure mới",
                            text: QuickQueries.defineNewMeasure(tableName: m.tableName),
                            run: false
                        )
                    },
                    onDefineAllMeasures: {
                        let allMeasures = state.workspace.metadata?.measures ?? []
                        openNewQueryTab(
                            title: m.name,
                            text: QuickQueries.defineAllMeasures(clickedMeasure: m, allMeasures: allMeasures),
                            run: true
                        )
                    },
                    onCollapseAll: { collapseAll() },
                    onExpandAll: { expandAll() },
                    onCopyFormula: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(m.expression, forType: .string)
                    }
                )
            })
        case .column(let c):
            return AnyView(TreeRow(level: level, symbol: columnSymbol(c), tint: c.kind == .calculated ? DS.Palette.indigo : DS.Palette.secondaryLabel,
                                   title: c.name, isHidden: c.isHidden, checkbox: checkbox(table, c.name),
                                   isSelected: purpose == .table && state.table == table && state.column == c.name,
                                   help: c.expression) {
                if purpose == .table { state.select(table: table, column: c.name) }
            }
            .leftContextMenu {
                LeftMenuBuilder.columnMenuItems(
                    isCalculated: c.kind == .calculated,
                    hasExpression: !(c.expression?.isEmpty ?? true),
                    onPreviewData: {
                        openNewQueryTab(title: c.name, text: QuickQueries.previewData(tableName: table, columnName: c.name), run: true)
                    },
                    onCollapseAll: { collapseAll() },
                    onExpandAll: { expandAll() },
                    onCopyFormula: {
                        if let expr = c.expression, !expr.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(expr, forType: .string)
                        }
                    }
                )
            })
        case .hierarchy(let h):
            let key = "\(table)/h/\(h.name)"
            let isOpen = expanded.contains(key)
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                TreeRow(level: level, isExpanded: isOpen, hasChildren: true, symbol: "list.bullet.indent", tint: DS.Palette.secondaryLabel,
                        title: h.name, isHidden: h.isHidden, checkbox: checkbox(table, h.name)) { toggle(key) }
                if isOpen {
                    ForEach(h.levels, id: \.name) { level2 in
                        TreeRow(level: level + 1, symbol: "smallcircle.filled.circle", tint: DS.Palette.tertiaryLabel, title: level2.name,
                                checkbox: checkbox(table, level2.name)) {}
                    }
                }
            })
        }
    }

    private func openNewQueryTab(title: String, text: String, run: Bool = true) {
        state.daxQueries.append(DAXQueryTab(title: title, text: text))
        state.daxSelection = state.daxQueries.count - 1
        state.mode = .daxQuery
        state.daxEditorSelection = NSRange(location: 0, length: 0)
        if run && state.canRunDAX {
            state.runDAXQuery()
        }
    }

    private func collapseAll() {
        expanded.removeAll()
    }

    private func expandAll() {
        for table in tables {
            expanded.insert(table.name)
            for item in items(for: table.name) {
                if case .folder(let name, _) = item {
                    expanded.insert("\(table.name)/\(name)")
                } else if case .hierarchy(let h) = item {
                    expanded.insert("\(table.name)/h/\(h.name)")
                }
            }
        }
        expanded.insert("model:root")
        expanded.insert("model:calcGroups")
        expanded.insert("model:cultures")
        expanded.insert("model:expressions")
        expanded.insert("model:functions")
        expanded.insert("model:measures")
        expanded.insert("model:perspectives")
        expanded.insert("model:relationships")
        expanded.insert("model:roles")
        expanded.insert("model:tables")
    }

    private func checkbox(_ table: String, _ field: String) -> Bool? {
        guard purpose == .report else { return nil }
        return state.usedFields.contains("\(table).\(field)")
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }
}

func columnSymbol(_ c: ModelMetadata.Column) -> String {
    if let category = c.dataCategory?.lowercased(),
       ["city", "country", "stateorprovince", "county", "continent", "postalcode", "latitude", "longitude", "place", "address"].contains(category) {
        return "globe.americas"
    }
    if c.kind == .calculated { return "f.cursive" }
    if c.isSummarizable { return "sum" }
    switch c.dataType {
    case .dateTime: return "calendar"
    case .boolean: return "checkmark.square"
    case .int64, .double, .decimal: return "number"
    default: return "textformat.abc"
    }
}

/// One row of a tree: 12 px indent per level, 24 px tall, SF Symbol disclosure.
struct TreeRow: View {
    var level: Int
    var isExpanded = false
    var hasChildren = false
    var symbol: String
    var tint: Color
    var title: String
    var isHidden = false
    var isDimmed = false
    var isBold = false
    var checkbox: Bool?
    var isSelected = false
    var trailing: String?
    var help: String?
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Group {
                    if hasChildren {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                    } else {
                        Color.clear
                    }
                }
                .foregroundStyle(DS.Palette.tertiaryLabel)
                .frame(width: 10)
                if let checkbox { CheckboxMark(isOn: checkbox) }
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white : (isDimmed ? DS.Palette.tertiaryLabel : tint))
                    .frame(width: 15)
                Text(title)
                    .font(DS.Typeface.bodySmall)   // chữ thường cho mọi cấp, kể cả tên bảng và nhóm mô hình (yêu cầu người dùng)
                    .foregroundStyle(isSelected ? .white : (isDimmed || isHidden ? DS.Palette.tertiaryLabel : DS.Palette.label))
                    .lineLimit(1)
                if isHidden { Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(DS.Palette.tertiaryLabel) }
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing).font(DS.Typeface.labelSmall.monospacedDigit()).foregroundStyle(isSelected ? .white.opacity(0.85) : DS.Palette.tertiaryLabel)
                }
            }
            .padding(.leading, 8 + CGFloat(level) * 12)
            .padding(.trailing, 8)
            .frame(height: DS.Metrics.treeRow)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(isSelected ? DS.Palette.accent : (hovering ? Color.black.opacity(0.04) : .clear))
                .padding(.horizontal, 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? title)
    }
}

enum DAXSnippets {
    /// Power BI's "Define and evaluate" quick query (mẫu 2).
    static func defineAndEvaluate(_ m: ModelMetadata.Measure) -> String {
        QuickQueries.defineAndEvaluate(measure: m)
    }
}
