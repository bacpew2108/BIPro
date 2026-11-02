import AppKit
import PBIXKit
import SwiftUI

/// Cây "Mô hình" trong ô Dữ liệu (chỉ hiện khi `purpose == .query`).
/// Cây gốc "Mô hình ngữ nghĩa" (mở sẵn), các nút con theo đúng thứ tự:
/// 1. Nhóm tính toán (n)
/// 2. Ngôn ngữ (n)
/// 3. Biểu thức (n)
/// 4. Hàm (n)
/// 5. Measure (n)
/// 6. Phối cảnh (n)
/// 7. Quan hệ (n)
/// 8. Vai trò (n)
/// 9. Bảng (n)
struct ModelTreeView: View {
    let state: DocumentState
    let search: String
    @Binding var expanded: Set<String>
    let openNewQueryTab: (String, String, Bool) -> Void
    let collapseAll: () -> Void
    let expandAll: () -> Void
    let renderTableNode: (ModelMetadata.Table, Int) -> AnyView

    private var metadata: ModelMetadata? {
        state.workspace.metadata
    }

    private func match(_ text: String) -> Bool {
        search.isEmpty || text.lowercased().contains(search.lowercased())
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
        }
    }

    var body: some View {
        let isRootOpen = expanded.contains("model:root") || !search.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            // Cây gốc: "Mô hình ngữ nghĩa"
            TreeRow(
                level: 0,
                isExpanded: isRootOpen,
                hasChildren: true,
                symbol: "cylinder.split.1x2",
                tint: DS.Palette.accent,
                title: "Mô hình ngữ nghĩa",
                isBold: true
            ) {
                toggle("model:root")
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(
                    onCollapseAll: collapseAll,
                    onExpandAll: expandAll
                )
            }

            if isRootOpen {
                groupCalculationGroups
                groupCultures
                groupExpressions
                groupFunctions
                groupMeasures
                groupPerspectives
                groupRelationships
                groupRoles
                groupTables
            }
        }
    }

    // MARK: - 1. Nhóm tính toán (n)
    @ViewBuilder
    private var groupCalculationGroups: some View {
        let allItems = metadata?.calculationGroups ?? []
        let filtered = allItems.filter { match($0) }
        let count = allItems.count
        if search.isEmpty || !filtered.isEmpty || match("Nhóm tính toán") {
            let key = "model:calcGroups"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "slider.horizontal.3",
                tint: DS.Palette.secondaryLabel,
                title: "Nhóm tính toán (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(filtered, id: \.self) { item in
                    TreeRow(
                        level: 2,
                        symbol: "slider.horizontal.3",
                        tint: DS.Palette.tertiaryLabel,
                        title: item
                    ) {}
                }
            }
        }
    }

    // MARK: - 2. Ngôn ngữ (n)
    @ViewBuilder
    private var groupCultures: some View {
        let allItems = metadata?.cultures ?? []
        let filtered = allItems.filter { match($0) }
        let count = allItems.count
        if search.isEmpty || !filtered.isEmpty || match("Ngôn ngữ") {
            let key = "model:cultures"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "globe",
                tint: DS.Palette.secondaryLabel,
                title: "Ngôn ngữ (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(filtered, id: \.self) { item in
                    TreeRow(
                        level: 2,
                        symbol: "globe",
                        tint: DS.Palette.tertiaryLabel,
                        title: item
                    ) {}
                }
            }
        }
    }

    // MARK: - 3. Biểu thức (n)
    @ViewBuilder
    private var groupExpressions: some View {
        let allItems = metadata?.expressions ?? []
        let filtered = allItems.filter { match($0) }
        let count = allItems.count
        if search.isEmpty || !filtered.isEmpty || match("Biểu thức") {
            let key = "model:expressions"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "curlybraces",
                tint: DS.Palette.secondaryLabel,
                title: "Biểu thức (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(filtered, id: \.self) { item in
                    TreeRow(
                        level: 2,
                        symbol: "curlybraces",
                        tint: DS.Palette.tertiaryLabel,
                        title: item
                    ) {}
                }
            }
        }
    }

    // MARK: - 4. Hàm (n)
    @ViewBuilder
    private var groupFunctions: some View {
        let allItems = metadata?.functions ?? []
        let filtered = allItems.filter { match($0) }
        let count = allItems.count
        if search.isEmpty || !filtered.isEmpty || match("Hàm") {
            let key = "model:functions"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "function",
                tint: DS.Palette.secondaryLabel,
                title: "Hàm (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(filtered, id: \.self) { item in
                    TreeRow(
                        level: 2,
                        symbol: "function",
                        tint: DS.Palette.tertiaryLabel,
                        title: item
                    ) {}
                }
            }
        }
    }

    // MARK: - 5. Measure (n)
    @ViewBuilder
    private var groupMeasures: some View {
        let allMeasures = (metadata?.measures ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let filtered = allMeasures.filter { match($0.name) }
        let count = allMeasures.count
        if search.isEmpty || !filtered.isEmpty || match("Measure") {
            let key = "model:measures"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "function",
                tint: DS.Palette.measure,
                title: "Measure (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(filtered, id: \.name) { m in
                    TreeRow(
                        level: 2,
                        symbol: "function",
                        tint: DS.Palette.measure,
                        title: m.name,
                        isHidden: m.isHidden,
                        help: m.expression.trimmingCharacters(in: .whitespacesAndNewlines)
                    ) {
                        state.daxQueries[state.daxSelection].text = DAXSnippets.defineAndEvaluate(m)
                    }
                    .leftContextMenu {
                        LeftMenuBuilder.measureMenuItems(
                            onEvaluate: {
                                openNewQueryTab(m.name, QuickQueries.evaluate(measure: m), true)
                            },
                            onDefineAndEvaluate: {
                                openNewQueryTab(m.name, QuickQueries.defineAndEvaluate(measure: m), true)
                            },
                            onDefineWithReferencesAndEvaluate: {
                                let allM = state.workspace.metadata?.measures ?? []
                                let allC = state.workspace.metadata?.columns ?? []
                                openNewQueryTab(
                                    m.name,
                                    QuickQueries.defineWithReferencesAndEvaluate(
                                        measure: m,
                                        allMeasures: allM,
                                        allColumns: allC
                                    ),
                                    true
                                )
                            },
                            onDefineNewMeasure: {
                                openNewQueryTab(
                                    "Measure mới",
                                    QuickQueries.defineNewMeasure(tableName: m.tableName),
                                    false
                                )
                            },
                            onDefineAllMeasures: {
                                let allM = state.workspace.metadata?.measures ?? []
                                openNewQueryTab(
                                    m.name,
                                    QuickQueries.defineAllMeasures(clickedMeasure: m, allMeasures: allM),
                                    true
                                )
                            },
                            onCollapseAll: collapseAll,
                            onExpandAll: expandAll,
                            onCopyFormula: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(m.expression, forType: .string)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 6. Phối cảnh (n)
    @ViewBuilder
    private var groupPerspectives: some View {
        let allItems = metadata?.perspectives ?? []
        let filtered = allItems.filter { match($0) }
        let count = allItems.count
        if search.isEmpty || !filtered.isEmpty || match("Phối cảnh") {
            let key = "model:perspectives"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "eye",
                tint: DS.Palette.secondaryLabel,
                title: "Phối cảnh (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(filtered, id: \.self) { item in
                    TreeRow(
                        level: 2,
                        symbol: "eye",
                        tint: DS.Palette.tertiaryLabel,
                        title: item
                    ) {}
                }
            }
        }
    }

    // MARK: - 7. Quan hệ (n)
    @ViewBuilder
    private var groupRelationships: some View {
        let allItems = metadata?.relationships ?? []
        let count = allItems.count
        let filtered = allItems.filter { r in
            let line = "'\(r.fromTable)'[\(r.fromColumn)] → '\(r.toTable)'[\(r.toColumn)]"
            return match(line) || match(r.fromTable) || match(r.toTable)
        }
        if search.isEmpty || !filtered.isEmpty || match("Quan hệ") {
            let key = "model:relationships"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "arrow.triangle.swap",
                tint: DS.Palette.secondaryLabel,
                title: "Quan hệ (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(Array(filtered.enumerated()), id: \.offset) { _, r in
                    let line = "'\(r.fromTable)'[\(r.fromColumn)] → '\(r.toTable)'[\(r.toColumn)]"
                    TreeRow(
                        level: 2,
                        symbol: "arrow.right",
                        tint: r.isActive ? DS.Palette.secondaryLabel : DS.Palette.tertiaryLabel,
                        title: line,
                        isDimmed: !r.isActive,
                        help: "\(r.name) (\(r.cardinality))"
                    ) {}
                }
            }
        }
    }

    // MARK: - 8. Vai trò (n)
    @ViewBuilder
    private var groupRoles: some View {
        let allItems = metadata?.roles ?? []
        let filtered = allItems.filter { match($0) }
        let count = allItems.count
        if search.isEmpty || !filtered.isEmpty || match("Vai trò") {
            let key = "model:roles"
            let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
            TreeRow(
                level: 1,
                isExpanded: isOpen,
                hasChildren: count > 0,
                symbol: "person.2",
                tint: DS.Palette.secondaryLabel,
                title: "Vai trò (\(count))",
                isBold: true
            ) {
                if count > 0 { toggle(key) }
            }
            .leftContextMenu {
                LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
            }

            if isOpen {
                ForEach(filtered, id: \.self) { item in
                    TreeRow(
                        level: 2,
                        symbol: "person",
                        tint: DS.Palette.tertiaryLabel,
                        title: item
                    ) {}
                }
            }
        }
    }

    // MARK: - 9. Bảng (n)
    @ViewBuilder
    private var groupTables: some View {
        let userTables = (metadata?.userTables ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let count = userTables.count
        let key = "model:tables"
        let isOpen = (expanded.contains(key) || !search.isEmpty) && count > 0
        TreeRow(
            level: 1,
            isExpanded: isOpen,
            hasChildren: count > 0,
            symbol: "tablecells",
            tint: DS.Palette.table,
            title: "Bảng (\(count))",
            isBold: true
        ) {
            if count > 0 { toggle(key) }
        }
        .leftContextMenu {
            LeftMenuBuilder.modelGroupMenuItems(onCollapseAll: collapseAll, onExpandAll: expandAll)
        }

        if isOpen {
            ForEach(userTables, id: \.id) { table in
                renderTableNode(table, 2)
            }
        }
    }
}
