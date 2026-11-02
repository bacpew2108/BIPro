import PBIXKit
import SwiftUI

struct ModelWorkspace: View {
    @Bindable var state: DocumentState
    @State private var positions: [String: CGPoint] = [:]
    @State private var sidebar: Sidebar = .model

    enum Sidebar: Hashable { case tables, model }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        diagram
                        if let r = selectedRelationship {
                            RelationshipPanel(relationship: r) { state.relationship = nil }
                                .frame(width: 280)
                                .padding(12)
                        }
                    }
                    bottomBar
                }
                sidebarPane
                    .frame(width: 280)
                    .hairline(.leading)
            }
            StatusBar(workspace: state.workspace,
                      detail: "\(layout.count) bảng · \(state.workspace.metadata?.relationships.count ?? 0) quan hệ" + (state.workspace.diagramLayout == nil ? " · bố cục tự động" : " · bố cục từ DiagramLayout"))
        }
        .onChange(of: state.layoutRevision) { _, _ in positions = [:] }
        .onChange(of: state.diagramName) { _, _ in positions = [:] }
    }

    private var selectedRelationship: ModelMetadata.Relationship? {
        state.workspace.metadata?.relationships.first { key($0) == state.relationship }
    }

    private func key(_ r: ModelMetadata.Relationship) -> String {
        r.name.isEmpty ? "\(r.fromTable).\(r.fromColumn)->\(r.toTable).\(r.toColumn)" : r.name
    }

    // MARK: Layout

    /// Card frames in diagram coordinates: Power BI's saved layout if present, else a star layout.
    private var layout: [String: CGRect] {
        let tables = state.workspace.userTables.map(\.name)
        var frames: [String: CGRect] = [:]
        if let diagram = state.workspace.diagramLayout?.diagrams.first(where: { $0.name == state.diagramName }) {
            for node in diagram.nodes where tables.contains(node.table) {
                frames[node.table] = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
            }
        }
        let missing = tables.filter { frames[$0] == nil }
        if !missing.isEmpty { frames.merge(autoLayout(missing, avoiding: frames)) { a, _ in a } }
        for (table, point) in positions { frames[table]?.origin = point }
        return frames
    }

    private func cardHeight(_ table: String) -> CGFloat {
        let rows = state.workspace.columns(of: table).count + state.workspace.measures(of: table).count
        return min(300, 46 + CGFloat(min(rows, 11)) * 22)
    }

    private func autoLayout(_ tables: [String], avoiding existing: [String: CGRect]) -> [String: CGRect] {
        let relationships = state.workspace.metadata?.relationships ?? []
        let facts = tables.filter { t in relationships.contains { $0.fromTable == t } }
        let dims = tables.filter { !facts.contains($0) }
        let width: CGFloat = 234, gapX: CGFloat = 90, gapY: CGFloat = 140
        let originY = (existing.values.map(\.maxY).max() ?? 0) + (existing.isEmpty ? 40 : 80)
        var frames: [String: CGRect] = [:]
        let top = Array(dims.prefix((dims.count + 1) / 2)), bottom = Array(dims.dropFirst((dims.count + 1) / 2))
        let columns = max(top.count, bottom.count, facts.count)
        func row(_ items: [String], y: CGFloat) {
            let offset = CGFloat(columns - items.count) * (width + gapX) / 2
            for (i, t) in items.enumerated() {
                frames[t] = CGRect(x: 40 + offset + CGFloat(i) * (width + gapX), y: y, width: width, height: cardHeight(t))
            }
        }
        row(top, y: originY)
        let factY = originY + (top.map(cardHeight).max() ?? 0) + gapY
        row(facts, y: factY)
        row(bottom, y: factY + (facts.map(cardHeight).max() ?? 0) + gapY)
        return frames
    }

    // MARK: Diagram

    private var diagram: some View {
        let frames = layout
        let size = CGSize(width: (frames.values.map(\.maxX).max() ?? 800) + 120, height: (frames.values.map(\.maxY).max() ?? 600) + 120)
        let zoom = state.modelZoom
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                DotGrid().frame(width: size.width, height: size.height)
                    .onTapGesture { state.relationship = nil }
                ForEach(state.workspace.metadata?.relationships ?? [], id: \.self) { r in
                    if let from = frames[r.fromTable], let to = frames[r.toTable] {
                        RelationshipLine(relationship: r, from: from, to: to,
                                         fromRow: rowOffset(r.fromTable, r.fromColumn), toRow: rowOffset(r.toTable, r.toColumn),
                                         isSelected: state.relationship == key(r),
                                         isRelated: state.table == r.fromTable || state.table == r.toTable)
                            .onTapGesture { state.relationship = key(r) }
                    }
                }
                ForEach(state.workspace.userTables, id: \.id) { table in
                    if let frame = frames[table.name] {
                        TableCard(state: state, table: table, keys: keyColumns(table.name),
                                  isSelected: state.table == table.name, selectedRelationship: selectedRelationship)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .gesture(DragGesture()
                                .onChanged { value in
                                    let base = frames[table.name]?.origin ?? .zero
                                    positions[table.name] = CGPoint(x: max(0, base.x + value.translation.width / zoom),
                                                                    y: max(0, base.y + value.translation.height / zoom))
                                }
                                .onEnded { _ in })
                            .onTapGesture { state.table = table.name; state.relationship = nil }
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
        }
        .background(Color(hex: "#FAFAFC")!)
    }

    /// Vertical offset of a column row inside its card, so lines meet the key column like in Power BI.
    private func rowOffset(_ table: String, _ column: String) -> CGFloat? {
        guard let index = state.workspace.columns(of: table).firstIndex(where: { $0.name == column }) else { return nil }
        return 46 + CGFloat(index) * 22 + 11
    }

    private func keyColumns(_ table: String) -> (pk: Set<String>, fk: Set<String>) {
        let rels = state.workspace.metadata?.relationships ?? []
        return (Set(rels.filter { $0.toTable == table }.map(\.toColumn)), Set(rels.filter { $0.fromTable == table }.map(\.fromColumn)))
    }

    // MARK: Bottom bar & sidebar

    private var bottomBar: some View {
        HStack(spacing: 4) {
            let names = state.workspace.diagramLayout?.diagrams.map(\.name) ?? ["Tất cả bảng"]
            ForEach(names, id: \.self) { name in
                let selected = (state.diagramName ?? "Tất cả bảng") == name
                Button { state.diagramName = name } label: {
                    Text(name == "All tables" ? "Tất cả bảng" : name)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.secondaryLabel)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(selected ? Color.white : .clear))
                }
                .buttonStyle(.plain)
            }
            Button {} label: { Image(systemName: "plus") }.buttonStyle(GhostIconButtonStyle()).disabled(true).help("Bố cục mới: Phase E")
            Spacer()
            Button { positions = [:] } label: { Label("Đặt lại bố cục", systemImage: "wand.and.stars") }
                .buttonStyle(.plain).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            Slider(value: $state.modelZoom, in: 0.3...2).frame(width: 120).controlSize(.small)
            Text("\(Int(state.modelZoom * 100))%").font(DS.Typeface.label.monospacedDigit()).frame(width: 40)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(DS.Palette.chrome)
        .hairline(.top)
    }

    @ViewBuilder private var sidebarPane: some View {
        VStack(spacing: 0) {
            SegmentedPill(selection: $sidebar, options: [.init(value: .tables, title: "Bảng"), .init(value: .model, title: "Mô hình")], fill: true)
                .padding(10)
            if sidebar == .tables {
                DataPane(state: state, purpose: .table)
            } else {
                SemanticModelTree(state: state)
            }
        }
        .background(DS.Palette.chrome)
    }
}

// MARK: - Pieces

struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(Color.black.opacity(0.10)))
                    x += 16
                }
                y += 16
            }
        }
    }
}

struct TableCard: View {
    let state: DocumentState
    let table: ModelMetadata.Table
    let keys: (pk: Set<String>, fk: Set<String>)
    let isSelected: Bool
    let selectedRelationship: ModelMetadata.Relationship?

    var body: some View {
        let columns = state.workspace.columns(of: table.name)
        let measures = state.workspace.measures(of: table.name)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: table.name.lowercased().hasPrefix("fact") ? "tablecells.fill" : "tablecells")
                    .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.table)
                Text(table.name).font(DS.Typeface.headlineSmall).lineLimit(1)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isSelected ? DS.Palette.selectionSoft : DS.Palette.chrome)
            .hairline(.bottom)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(columns, id: \.id) { column in
                        let highlighted = selectedRelationship.map {
                            ($0.fromTable == table.name && $0.fromColumn == column.name) || ($0.toTable == table.name && $0.toColumn == column.name)
                        } ?? false
                        row(symbol: keys.pk.contains(column.name) || keys.fk.contains(column.name) ? "key.horizontal" : columnSymbol(column),
                            tint: keys.pk.contains(column.name) || keys.fk.contains(column.name) ? DS.Palette.danger : DS.Palette.secondaryLabel,
                            title: column.name, mono: keys.pk.contains(column.name) || keys.fk.contains(column.name),
                            badge: keys.pk.contains(column.name) ? "PK" : (keys.fk.contains(column.name) ? "FK" : (column.kind == .calculated ? "DAX" : nil)),
                            hidden: column.isHidden, highlighted: highlighted)
                    }
                    ForEach(measures, id: \.name) { m in
                        row(symbol: "function", tint: DS.Palette.measure, title: m.name, mono: false, badge: nil, hidden: m.isHidden, highlighted: false)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(isSelected ? DS.Palette.accent : DS.Palette.separator, lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: .black.opacity(isSelected ? 0.10 : 0.05), radius: isSelected ? 10 : 2, y: isSelected ? 4 : 1)
    }

    private func row(symbol: String, tint: Color, title: String, mono: Bool, badge: String?, hidden: Bool, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(tint).frame(width: 14)
            Text(title).font(mono ? DS.Typeface.mono : DS.Typeface.bodySmall)
                .foregroundStyle(highlighted ? DS.Palette.accent : (hidden ? DS.Palette.tertiaryLabel : DS.Palette.label))
                .lineLimit(1)
            if hidden { Image(systemName: "eye.slash").font(.system(size: 8)).foregroundStyle(DS.Palette.tertiaryLabel) }
            Spacer(minLength: 0)
            if let badge { Text(badge).font(DS.Typeface.labelSmall).foregroundStyle(badge == "DAX" ? DS.Palette.indigo : DS.Palette.accent) }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(highlighted ? DS.Palette.selectionSoft : .clear)
    }
}

/// A relationship drawn as a curve between two cards: `*` on the many side, `1` on the one side,
/// arrows pointing in the filter direction, dashed when inactive.
struct RelationshipLine: View {
    let relationship: ModelMetadata.Relationship
    let from: CGRect
    let to: CGRect
    let fromRow: CGFloat?
    let toRow: CGFloat?
    let isSelected: Bool
    let isRelated: Bool

    var body: some View {
        let (start, end, startSide, endSide) = anchors
        let path = curve(start, end, startSide, endSide)
        let color = isSelected ? DS.Palette.accent : (isRelated ? DS.Palette.accent.opacity(0.6) : Color(hex: "#8E8E93")!)
        ZStack {
            path.stroke(color, style: StrokeStyle(lineWidth: isSelected ? 2.2 : 1.4, lineCap: .round,
                                                  dash: relationship.isActive ? [] : [6, 4]))
            arrow(on: path, color: color)
            marker(relationship.cardinality.hasPrefix("M") ? "*" : "1", at: start, side: startSide, color: color)
            marker(relationship.cardinality.hasSuffix("M") ? "*" : "1", at: end, side: endSide, color: color)
        }
        .contentShape(path.strokedPath(StrokeStyle(lineWidth: 12)))
        .help("\(relationship.fromTable)[\(relationship.fromColumn)] \(relationship.cardinality.replacingOccurrences(of: "M", with: "*")) \(relationship.toTable)[\(relationship.toColumn)]")
    }

    /// Connect facing edges at the key column rows.
    private var anchors: (CGPoint, CGPoint, CGFloat, CGFloat) {
        func y(_ rect: CGRect, _ row: CGFloat?) -> CGFloat {
            guard let row, row < rect.height - 8 else { return rect.midY }
            return rect.minY + row
        }
        if from.midX <= to.midX {
            return (CGPoint(x: from.maxX, y: y(from, fromRow)), CGPoint(x: to.minX, y: y(to, toRow)), 1, -1)
        }
        return (CGPoint(x: from.minX, y: y(from, fromRow)), CGPoint(x: to.maxX, y: y(to, toRow)), -1, 1)
    }

    private func curve(_ a: CGPoint, _ b: CGPoint, _ sa: CGFloat, _ sb: CGFloat) -> Path {
        let bend = max(60, abs(b.x - a.x) * 0.4)
        var p = Path()
        p.move(to: a)
        p.addCurve(to: b, control1: CGPoint(x: a.x + sa * bend, y: a.y), control2: CGPoint(x: b.x + sb * bend, y: b.y))
        return p
    }

    /// Filter flows from the one side (`to`) to the many side (`from`); both ways when bidirectional.
    private func arrow(on path: Path, color: Color) -> some View {
        let mid = path.trimmedPath(from: 0.48, to: 0.52)
        let points = (mid.currentPoint, path.trimmedPath(from: 0, to: 0.48).currentPoint)
        return Canvas { context, _ in
            guard let tip = points.1, let tail = points.0 else { return }
            func head(_ from: CGPoint, _ to: CGPoint) {
                let angle = atan2(to.y - from.y, to.x - from.x)
                var p = Path()
                p.move(to: to)
                p.addLine(to: CGPoint(x: to.x - 9 * cos(angle - 0.45), y: to.y - 9 * sin(angle - 0.45)))
                p.addLine(to: CGPoint(x: to.x - 9 * cos(angle + 0.45), y: to.y - 9 * sin(angle + 0.45)))
                p.closeSubpath()
                context.fill(p, with: .color(color))
            }
            head(tail, tip)
            if relationship.crossFilteringBehavior == 2 { head(tip, tail) }
        }
        .allowsHitTesting(false)
    }

    private func marker(_ text: String, at point: CGPoint, side: CGFloat, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 15, height: 15)
            .background(Circle().fill(Color.white))
            .overlay(Circle().strokeBorder(color, lineWidth: 1))
            .position(x: point.x + side * 12, y: point.y)
    }
}

struct RelationshipPanel: View {
    let relationship: ModelMetadata.Relationship
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(DS.Palette.accent)
                Text("Thuộc tính quan hệ").font(DS.Typeface.headlineSmall)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(GhostIconButtonStyle())
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Từ:").foregroundStyle(DS.Palette.secondaryLabel); Spacer()
                    Text("\(relationship.fromTable).\(relationship.fromColumn)").font(DS.Typeface.mono).foregroundStyle(DS.Palette.accent)
                    Text(relationship.cardinality.hasPrefix("M") ? "(Nhiều)" : "(Một)").foregroundStyle(DS.Palette.tertiaryLabel) }
                HStack { Text("Đến:").foregroundStyle(DS.Palette.secondaryLabel); Spacer()
                    Text("\(relationship.toTable).\(relationship.toColumn)").font(DS.Typeface.mono).foregroundStyle(DS.Palette.accent)
                    Text(relationship.cardinality.hasSuffix("M") ? "(Nhiều)" : "(Một)").foregroundStyle(DS.Palette.tertiaryLabel) }
            }
            .font(DS.Typeface.bodySmall)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bản số").font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
                    Text(cardinalityText).font(DS.Typeface.body)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hướng lọc chéo").font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
                    Text(relationship.crossFilteringBehavior == 2 ? "Hai chiều" : "Một chiều").font(DS.Typeface.body)
                }
            }
            HStack {
                Text("Quan hệ đang hoạt động").font(DS.Typeface.body)
                Spacer()
                SwitchMark(isOn: relationship.isActive)
            }
            HStack {
                Spacer()
                Button("Sửa") {}.buttonStyle(SecondaryButtonStyle()).disabled(true).help("Phase E")
                Button("Xong", action: close).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(Color.white)
        .popoverElevation()
    }

    private var cardinalityText: String {
        switch relationship.cardinality {
        case "M:1": "Nhiều – một (*:1)"
        case "1:M": "Một – nhiều (1:*)"
        case "1:1": "Một – một (1:1)"
        default: "Nhiều – nhiều (*:*)"
        }
    }
}

/// "Semantic model" tree, as in the Model view sidebar.
struct SemanticModelTree: View {
    @Bindable var state: DocumentState
    @State private var open: Set<String> = ["root", "relationships"]

    var body: some View {
        let w = state.workspace
        let m = w.metadata
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TreeRow(level: 0, isExpanded: open.contains("root"), hasChildren: true, symbol: "point.3.connected.trianglepath.dotted",
                        tint: DS.Palette.accent, title: "Mô hình ngữ nghĩa") { toggle("root") }
                if open.contains("root") {
                    group("tables", "Bảng", "tablecells", w.userTables.count) {
                        ForEach(w.userTables, id: \.id) { t in
                            TreeRow(level: 2, symbol: "tablecells", tint: DS.Palette.table, title: t.name, isSelected: state.table == t.name) {
                                state.table = t.name; state.relationship = nil
                            }
                        }
                    }
                    group("relationships", "Quan hệ", "arrow.left.arrow.right", m?.relationships.count ?? 0) {
                        ForEach(m?.relationships ?? [], id: \.self) { r in
                            let key = r.name.isEmpty ? "\(r.fromTable).\(r.fromColumn)->\(r.toTable).\(r.toColumn)" : r.name
                            TreeRow(level: 2, symbol: r.crossFilteringBehavior == 2 ? "arrow.triangle.2.circlepath" : "arrow.left.arrow.right",
                                    tint: r.isActive ? DS.Palette.secondaryLabel : DS.Palette.warning,
                                    title: "\(r.fromTable) ↔ \(r.toTable) (\(r.cardinality.replacingOccurrences(of: "M", with: "*"))\(r.crossFilteringBehavior == 2 ? ", hai chiều" : ""))",
                                    isSelected: state.relationship == key) { state.relationship = key }
                        }
                    }
                    group("measures", "Measure", "function", m?.measures.count ?? 0) {
                        ForEach(m?.measures ?? [], id: \.self) { measure in
                            TreeRow(level: 2, symbol: "function", tint: DS.Palette.measure, title: measure.name,
                                    help: measure.expression) {}
                        }
                    }
                    group("hierarchies", "Phân cấp", "list.bullet.indent", m?.hierarchies.count ?? 0) {
                        ForEach(m?.hierarchies ?? [], id: \.self) { h in
                            TreeRow(level: 2, symbol: "list.bullet.indent", tint: DS.Palette.secondaryLabel,
                                    title: "\(h.tableName) · \(h.name)", help: h.levels.map(\.name).joined(separator: " › ")) {}
                        }
                    }
                    group("roles", "Vai trò", "person.badge.shield.checkmark", m?.roles.count ?? 0) {
                        ForEach(m?.roles ?? [], id: \.self) { TreeRow(level: 2, symbol: "person", tint: DS.Palette.secondaryLabel, title: $0) {} }
                    }
                    group("perspectives", "Phối cảnh", "eye", m?.perspectives.count ?? 0) {
                        ForEach(m?.perspectives ?? [], id: \.self) { TreeRow(level: 2, symbol: "eye", tint: DS.Palette.secondaryLabel, title: $0) {} }
                    }
                    group("cultures", "Ngôn ngữ", "character.book.closed", m?.cultures.count ?? 0) {
                        ForEach(m?.cultures ?? [], id: \.self) { TreeRow(level: 2, symbol: "globe", tint: DS.Palette.secondaryLabel, title: $0) {} }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        PaneFooter(text: "\(w.userTables.count) bảng · \(m?.relationships.count ?? 0) quan hệ · hợp lệ")
    }

    @ViewBuilder private func group<Content: View>(_ key: String, _ title: String, _ symbol: String, _ count: Int,
                                                   @ViewBuilder content: () -> Content) -> some View {
        TreeRow(level: 1, isExpanded: open.contains(key), hasChildren: count > 0, symbol: symbol, tint: DS.Palette.secondaryLabel,
                title: "\(title) (\(count))") { toggle(key) }
        if open.contains(key) { content() }
    }

    private func toggle(_ key: String) {
        if open.contains(key) { open.remove(key) } else { open.insert(key) }
    }
}
