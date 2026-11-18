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
    /// Cột hoặc bảng tính toán chờ xác nhận xoá (T116; Desktop hỏi "Are you sure you want to delete '…'?" Yes/Cancel).
    @State private var deleting: PendingDeletion?
    /// Lý do không xoá được (còn được dùng…), hiện thành hộp báo.
    @State private var refusal: String?

    private struct PendingDeletion {
        let table: String
        let column: String?
        var title: String { column == nil ? "Xoá bảng" : "Xoá cột" }
        var name: String { column ?? table }
    }

    var body: some View {
        let _ = state.modelVersion   // vẽ lại khi mô hình đổi (Phase E)
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
        .alert(deleting?.title ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Có", role: .destructive) {
                if let target = deleting {
                    let reason = target.column.map { state.deleteCalculatedColumn(table: target.table, name: $0) }
                        ?? state.deleteCalculatedTable(name: target.table)
                    refusal = reason
                }
                deleting = nil
            }
            Button("Huỷ", role: .cancel) { deleting = nil }
        } message: {
            Text("Bạn có chắc muốn xoá '\(deleting?.name ?? "")'? Có thể hoàn tác bằng ⌘Z.")
        }
        .alert("Không xoá được", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
            Button("OK", role: .cancel) { refusal = nil }
        } message: {
            Text(refusal ?? "")
        }
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
                symbol: table.isCalculatedUserTable ? "tablecells.badge.ellipsis" : (table.name.lowercased().hasPrefix("fact") ? "tablecells.fill" : "tablecells"),
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
                    onExpandAll: { expandAll() },
                    onNewMeasure: purpose != .query && state.modelEditingBlocker == nil
                        ? { purpose == .table ? state.beginNewMeasure(table: table.name) : state.newMeasureInTableView(table: table.name) } : nil,
                    onDelete: purpose != .query && state.modelEditingBlocker == nil && table.isCalculatedUserTable
                        ? { deleting = PendingDeletion(table: table.name, column: nil) } : nil
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
                                   isSelected: purpose == .table && state.measure == m.name && state.table == table,
                                   help: m.expression.trimmingCharacters(in: .whitespacesAndNewlines),
                                   dragField: purpose == .report && !m.isHidden ? FieldRef(measure: m) : nil,
                                   onCheck: purpose == .report ? { toggleUsage(FieldRef(measure: m)) } : nil) {
                if purpose == .query {
                    state.daxQueries[state.daxSelection].text = DAXSnippets.defineAndEvaluate(m)
                }
                if purpose == .table { state.selectMeasure(table: table, name: m.name) }
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
                    },
                    onEdit: purpose != .query && state.modelEditingBlocker == nil
                        ? { purpose == .table ? state.selectMeasure(table: table, name: m.name) : state.editMeasureInTableView(table: table, name: m.name) } : nil,
                    onDelete: purpose != .query && state.modelEditingBlocker == nil ? { state.deleteMeasure(table: table, name: m.name) } : nil,
                    onToggleHidden: purpose != .query && state.modelEditingBlocker == nil
                        ? { state.updateMeasure(table: table, name: m.name, patch: MeasurePatch(isHidden: !m.isHidden)) } : nil,
                    hiddenTitle: m.isHidden ? "Hiện trong chế độ báo cáo" : "Ẩn trong chế độ báo cáo"
                )
            })
        case .column(let c):
            // Cột ngày có bảng ngày Auto date/time (VM-F11b ảnh b5): biểu tượng lịch, mở ra "Date Hierarchy"; tick hay kéo thì thêm cả
            // phân cấp như Desktop.
            let dateHierarchy = state.workspace.dateHierarchy(table: table, column: c.name)
            let dateKey = "\(table)/d/\(c.name)"
            let ref = dateHierarchy ?? FieldRef(column: c)
            let row = TreeRow(level: level, isExpanded: dateHierarchy != nil && expanded.contains(dateKey), hasChildren: dateHierarchy != nil,
                              symbol: dateHierarchy != nil ? "calendar.day.timeline.leading" : columnSymbol(c),
                              tint: c.kind == .calculated ? DS.Palette.indigo : DS.Palette.secondaryLabel,
                              title: c.name, isHidden: c.isHidden,
                              checkbox: dateHierarchy.map { fieldChecked($0) } ?? checkbox(table, c.name),
                              isSelected: purpose == .table && state.table == table && state.column == c.name,
                              help: c.expression,
                              dragField: purpose == .report ? ref : nil,
                              onCheck: purpose == .report ? { toggleUsage(ref) } : nil) {
                if dateHierarchy != nil { toggle(dateKey) }
                if purpose == .table { state.select(table: table, column: c.name) }
            }
            let menu = row.leftContextMenu {
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
                    },
                    onDelete: purpose != .query && state.modelEditingBlocker == nil && c.kind == .calculated
                        ? { deleting = PendingDeletion(table: table, column: c.name) } : nil
                )
            }
            guard let dateHierarchy, expanded.contains(dateKey) else { return AnyView(menu) }
            let hierarchyKey = dateKey + "/h"
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                menu
                TreeRow(level: level + 1, isExpanded: expanded.contains(hierarchyKey), hasChildren: true, symbol: "list.bullet.indent",
                        tint: DS.Palette.secondaryLabel, title: dateHierarchy.property, checkbox: fieldChecked(dateHierarchy),
                        dragField: purpose == .report ? dateHierarchy : nil,
                        onCheck: purpose == .report ? { toggleUsage(dateHierarchy) } : nil) { toggle(hierarchyKey) }
                if expanded.contains(hierarchyKey) {
                    ForEach(dateHierarchy.levels, id: \.self) { name in
                        TreeRow(level: level + 2, symbol: "smallcircle.filled.circle", tint: DS.Palette.tertiaryLabel, title: name,
                                checkbox: purpose == .report ? state.visual?.fields.contains { $0.queryRef == dateHierarchy.queryRef + "." + name } ?? false : nil) {}
                    }
                }
            })
        case .hierarchy(let h):
            let key = "\(table)/h/\(h.name)"
            let isOpen = expanded.contains(key)
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                TreeRow(level: level, isExpanded: isOpen, hasChildren: true, symbol: "list.bullet.indent", tint: DS.Palette.secondaryLabel,
                        title: h.name, isHidden: h.isHidden, checkbox: hierarchyChecked(table, h),
                        dragField: purpose == .report && !h.isHidden ? FieldRef(hierarchy: h) : nil,
                        onCheck: purpose == .report ? { toggleUsage(FieldRef(hierarchy: h)) } : nil) { toggle(key) }
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

    /// Phân cấp (kể cả phân cấp ngày) đang dùng trong visual đã chọn: có cấp nào của nó trong các ô.
    private func fieldChecked(_ ref: FieldRef) -> Bool? {
        guard purpose == .report else { return nil }
        let prefix = ref.queryRef + "."
        return state.visual?.fields.contains { $0.kind == .hierarchyLevel && $0.queryRef.hasPrefix(prefix) } ?? false
    }

    /// Phân cấp đang dùng trong visual đã chọn: có cấp nào của nó trong các ô.
    private func hierarchyChecked(_ table: String, _ h: ModelMetadata.Hierarchy) -> Bool? {
        guard purpose == .report else { return nil }
        let prefix = "\(table).\(h.name)."
        return state.visual?.fields.contains { $0.kind == .hierarchyLevel && $0.queryRef.hasPrefix(prefix) } ?? false
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    /// Ô tick: bỏ trường khỏi visual đang chọn nếu đã dùng, ngược lại thêm vào ô mặc định (D2).
    private func toggleUsage(_ ref: FieldRef) {
        let layout = state.layout
        guard state.editMode, let visual = state.visual, layout.selection.count <= 1 else {
            layout.noteFieldRefusal("Bật chế độ Sửa (⌘E) và chọn một visual để thêm hoặc bỏ trường.")
            return
        }
        if ref.kind == .hierarchy {
            if visual.fields.contains(where: { $0.kind == .hierarchyLevel && $0.queryRef.hasPrefix(ref.queryRef + ".") }) {
                layout.removeHierarchy(ref, visual: visual.id)
            } else if let role = WellRules.defaultRole(for: ref, in: visual) {
                layout.addField(ref, to: role, visual: visual.id)
            } else {
                layout.noteFieldRefusal("Visual này chưa có ô nhận phân cấp \"\(ref.property)\".")
            }
            return
        }
        // Trường gộp ngầm có `queryRef` dạng `Sum(Bảng.Cột)`: so theo bảng và cột (US1).
        let implicit = layout.allowsImplicitMeasures
        if let used = visual.fields.first(where: { field in
               field.kind != .hierarchyLevel && (field.queryRef == ref.queryRef
                   || (field.kind == .aggregation && ref.kind == .column && field.entity == ref.entity && field.property == ref.property))
           }),
           let index = visual.fields.filter({ $0.role == used.role }).firstIndex(of: used) {
            layout.removeField(role: used.role, index: index, visual: visual.id)
        } else if let role = WellRules.defaultRole(for: ref, in: visual, implicitMeasures: implicit) {
            layout.addField(ref, to: role, visual: visual.id)
        } else {
            layout.noteFieldRefusal("Visual này chưa có ô nhận \"\(ref.property)\".")
        }
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
    /// Trường kéo được sang Build pane. Hàng kéo được dùng cử chỉ chạm thay cho `Button`, vì `Button` nuốt thao tác kéo.
    var dragField: FieldRef?
    /// Bấm vào ô tick (chỉ pane Dữ liệu của báo cáo): thêm hoặc bỏ trường khỏi visual đang chọn.
    var onCheck: (() -> Void)?
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        if let dragField {
            row
                .onTapGesture(perform: action)
                .onDrag { dragField.itemProvider }
                .onHover { hovering = $0 }
                .help(help ?? title)
        } else {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(help ?? title)
        }
    }

    private var row: some View {
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
                if let checkbox {
                    if let onCheck {
                        Button(action: onCheck) { CheckboxMark(isOn: checkbox).frame(width: 18, height: 18).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .help("Thêm hoặc bỏ khỏi visual đang chọn")
                    } else {
                        CheckboxMark(isOn: checkbox)
                    }
                }
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
}

enum DAXSnippets {
    /// Power BI's "Define and evaluate" quick query (mẫu 2).
    static func defineAndEvaluate(_ m: ModelMetadata.Measure) -> String {
        QuickQueries.defineAndEvaluate(measure: m)
    }
}
