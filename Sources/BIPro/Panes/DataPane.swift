import PBIXKit
import SwiftUI

/// The Data pane field list, following Power BI's conventions observed in the model metadata:
/// tables A–Z; display folders first, then fields A–Z; hidden fields omitted in report view;
/// Σ for numeric columns that summarize by default; geo icons from the data category.
struct DataPane: View {
    enum Purpose { case report, table, query }

    let state: DocumentState
    var purpose: Purpose = .report
    var collapse: (() -> Void)?

    @State private var search = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: purpose == .query ? "Mô hình dữ liệu" : "Dữ liệu", symbol: "cylinder.split.1x2", collapse: collapse)
            SearchField(text: $search, prompt: "Tìm field…").padding(.horizontal, 10).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tables, id: \.id) { table in
                        tableNode(table)
                    }
                }
                .padding(.bottom, 8)
            }
            PaneFooter(text: "\(tables.count) bảng · \(state.workspace.metadata?.measures.count ?? 0) measure")
        }
        .background(DS.Palette.chrome)
        .onAppear {
            if let table = state.table, purpose != .report { expanded.insert(table) }
        }
    }

    private var tables: [ModelMetadata.Table] {
        state.workspace.userTables
            .filter { purpose != .report || !$0.isHidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var showHidden: Bool { purpose != .report }

    // MARK: Nodes

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

    @ViewBuilder private func tableNode(_ table: ModelMetadata.Table) -> some View {
        let isOpen = expanded.contains(table.name) || !search.isEmpty
        let children = items(for: table.name)
        if search.isEmpty || !children.isEmpty || table.name.lowercased().contains(search.lowercased()) {
            TreeRow(level: 0, isExpanded: isOpen, hasChildren: true,
                    symbol: table.name.lowercased().hasPrefix("fact") ? "tablecells.fill" : "tablecells",
                    tint: DS.Palette.table, title: table.name, isHidden: table.isHidden,
                    isSelected: purpose == .table && state.table == table.name && state.column == nil,
                    trailing: purpose == .report ? nil : state.workspace.rowCount(table.name).formatted(.number.notation(.compactName))) {
                toggle(table.name)
                if purpose == .table { state.select(table: table.name) }
            }
            if isOpen {
                ForEach(children) { item in node(item, table: table.name, level: 1) }
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
            .contextMenu { measureMenu(m) })
        case .column(let c):
            return AnyView(TreeRow(level: level, symbol: columnSymbol(c), tint: c.kind == .calculated ? DS.Palette.indigo : DS.Palette.secondaryLabel,
                                   title: c.name, isHidden: c.isHidden, checkbox: checkbox(table, c.name),
                                   isSelected: purpose == .table && state.table == table && state.column == c.name,
                                   help: c.expression) {
                if purpose == .table { state.select(table: table, column: c.name) }
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

    @ViewBuilder private func measureMenu(_ m: ModelMetadata.Measure) -> some View {
        Button("Định nghĩa và đánh giá (DAX)") {
            state.mode = .daxQuery
            state.daxQueries[state.daxSelection].text = DAXSnippets.defineAndEvaluate(m)
        }
        Button("Sao chép công thức") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(m.expression, forType: .string)
        }
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
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(isSelected ? .white : tint).frame(width: 15)
                Text(title)
                    .font(level == 0 ? DS.Typeface.headlineSmall : DS.Typeface.bodySmall)
                    .foregroundStyle(isSelected ? .white : (isHidden ? DS.Palette.tertiaryLabel : DS.Palette.label))
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
    /// Power BI's "Define and evaluate" quick query.
    static func defineAndEvaluate(_ m: ModelMetadata.Measure) -> String {
        let body = m.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\t\t" + $0 }.joined(separator: "\n")
        let ref = "'\(m.tableName.replacingOccurrences(of: "'", with: "''"))'[\(m.name)]"
        return "DEFINE\n\tMEASURE \(ref) =\n\(body)\n\nEVALUATE\n\t{ \(ref) }\n"
    }
}
