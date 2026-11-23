import PBIXKit
import SwiftUI

struct ModelWorkspace: View {
    static let usesInnerStatusBar = false

    @Bindable var state: DocumentState
    /// Vị trí thẻ lúc bắt đầu kéo (để một lần kéo là một bước hoàn tác với đúng vị trí gốc).
    @State private var dragOrigin: [String: CGPoint] = [:]
    @State private var cardsSettings = ModelCardsSettings()
    @State private var propertiesCollapsed = false
    @State private var dataCollapsed = false
    /// Tab bố cục đang đổi tên (ô sửa ngay trong thanh tab, như Desktop).
    @State private var renaming: String?
    @State private var renameText = ""
    /// Tab bố cục chờ xác nhận xoá (như hộp "Delete Layout" của Desktop).
    @State private var deleting: String?
    @FocusState private var renameFocused: Bool

    var body: some View {
        let _ = state.modelVersion   // vẽ lại khi mô hình đổi (Phase E)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    diagram
                    if state.diagramTables(state.currentDiagram) != nil, layout.isEmpty {
                        emptyLayoutHint.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let r = selectedRelationship {
                        RelationshipPanel(state: state, relationship: r) { state.relationship = nil }
                            .frame(width: 280)
                            .padding(12)
                    } else if let draft = state.relationshipDraft {
                        RelationshipDraftPanel(state: state, draft: draft)
                            .frame(width: 320)
                            .padding(12)
                    } else if let table = state.table, let name = state.measure, let measure = state.workspace.measure(table: table, name: name),
                              let draft = state.measureDraft {
                        MeasureInspector(state: state, measure: measure, draft: draft)
                            .frame(width: 380)
                            .padding(12)
                    }
                }
                if let notice = state.relationshipNotice {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
                        Text(notice).font(DS.Typeface.bodySmall).foregroundStyle(Color.red).lineLimit(2)
                        Spacer()
                        Button { state.relationshipNotice = nil } label: { Image(systemName: "xmark") }.buttonStyle(GhostIconButtonStyle())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(DS.Palette.chrome).hairline(.top)
                }
                bottomBar
            }
            if propertiesCollapsed {
                CollapsedPaneStrip(title: bi("Thuộc tính", "Properties"), symbol: "slider.horizontal.3") {
                    propertiesCollapsed = false
                }
                .hairline(.leading)
            } else {
                ModelPropertiesPanel(settings: $cardsSettings) { propertiesCollapsed = true }
                    .frame(width: UIMetrics.pane)
                    .hairline(.leading)
            }
            if dataCollapsed {
                CollapsedPaneStrip(title: tr(.paneData), symbol: "cylinder.split.1x2") {
                    dataCollapsed = false
                }
                .hairline(.leading)
            } else {
                DataPane(state: state, purpose: .query, collapse: { dataCollapsed = true }, initialTab: .tables)
                    .frame(width: 220)
                    .hairline(.leading)
            }
        }
        .onChange(of: state.modelZoom) { _, _ in
            // thu phóng ghi vào DiagramLayout của tab đang xem khi người dùng đổi (không ghi khi vừa mở file)
            if abs(state.modelZoom * 100 - (state.layout.diagramEdits.zoom[state.currentDiagram] ?? state.fileDiagram(for: state.currentDiagram)?.zoom ?? 100)) > 0.5 {
                state.commitDiagramZoom()
            }
        }
    }

    private var selectedRelationship: ModelMetadata.Relationship? {
        state.workspace.metadata?.relationships.first { key($0) == state.relationship }
    }

    private func key(_ r: ModelMetadata.Relationship) -> String {
        r.name.isEmpty ? "\(r.fromTable).\(r.fromColumn)->\(r.toTable).\(r.toColumn)" : r.name
    }

    // MARK: Layout

    /// Card frames in diagram coordinates: Power BI's saved layout if present, else a star layout. Tab khác "All tables" chỉ hiện
    /// các bảng đã có nút trong tab.
    private var layout: [String: CGRect] {
        let tables = state.workspace.userTables.map(\.name)
        let tab = state.currentDiagram
        let visible = state.diagramTables(tab)
        var frames: [String: CGRect] = [:]
        if let diagram = state.fileDiagram(for: tab) {
            for node in diagram.nodes where tables.contains(node.table) && (visible?.contains(node.table) ?? true) {
                frames[node.table] = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
            }
        }
        let moved = state.layout.diagramEdits.positions[tab] ?? [:]
        for (table, point) in moved {
            if frames[table] != nil { frames[table]?.origin = point }
            else if tables.contains(table) { frames[table] = CGRect(x: point.x, y: point.y, width: 234, height: state.cardHeight(table)) }
        }
        if visible == nil {
            let missing = tables.filter { frames[$0] == nil }
            if !missing.isEmpty { frames.merge(state.autoLayout(missing, avoiding: frames)) { a, _ in a } }
        }
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
                            // Chỉ thanh tiêu đề kéo được thẻ; hàng cột dành cho kéo thả tạo quan hệ.
                            .overlay(alignment: .top) {
                                // Vùng kéo chừa lại nút "…" ở bên phải để bấm được menu của thẻ.
                                HStack(spacing: 0) {
                                    Color.clear.contentShape(Rectangle())
                                        .gesture(DragGesture()
                                            .onChanged { value in
                                                let origin = dragOrigin[table.name] ?? frames[table.name]?.origin ?? .zero
                                                if dragOrigin[table.name] == nil { dragOrigin[table.name] = origin }
                                                state.moveCard(table: table.name,
                                                               to: CGPoint(x: max(0, origin.x + value.translation.width / zoom),
                                                                           y: max(0, origin.y + value.translation.height / zoom)),
                                                               original: origin, coalesce: true)
                                            }
                                            .onEnded { _ in dragOrigin[table.name] = nil })
                                    Color.clear.frame(width: 34).allowsHitTesting(false)
                                }
                                .frame(height: 36)
                            }
                            .offset(x: frame.minX, y: frame.minY)
                            .onTapGesture { state.select(table: table.name); state.relationship = nil }
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
        }
        .background(DS.Palette.backdrop)
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
            let names = state.diagramTabs.isEmpty ? ["All tables"] : state.diagramTabs
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                let selected = state.currentDiagram == name
                if renaming == name && index > 0 {
                    TextField(bi("Tên bố cục", "Layout name"), text: $renameText)
                        .textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8).frame(width: 130, height: 24)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.canvas))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).stroke(DS.Palette.accent, lineWidth: 1))
                        .focused($renameFocused)
                        .onSubmit { commitRename(name) }
                        .onExitCommand { renaming = nil }
                } else {
                    Text(name == "All tables" ? bi("Tất cả bảng", "All tables") : name)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
                        .padding(.horizontal, 12).frame(height: UIMetrics.pageTabs)
                        .background(selected ? DS.Palette.canvas : .clear)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(DS.Palette.accentBrand).frame(height: 2.5)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if index > 0 { startRename(name) } else { state.selectDiagram(name) } }
                        .onTapGesture { state.selectDiagram(name) }
                        .contextMenu {
                            if index > 0 { Button(bi("Đổi tên", "Rename")) { state.selectDiagram(name); startRename(name) } }
                            Button(bi("Bố cục mới", "New layout")) { state.addDiagramTab() }
                            if index > 0 { Button(bi("Xoá bố cục", "Delete layout"), role: .destructive) { deleting = name } }
                        }
                }
            }
            Button { state.addDiagramTab() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 3).fill(state.workspace.diagramLayout != nil ? DS.Palette.accentBrand : DS.Palette.tertiaryLabel.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .help(bi("Thêm bố cục mới", "Add new layout"))
            .disabled(state.workspace.diagramLayout == nil)
            if state.diagramTables(state.currentDiagram) != nil {
                Menu {
                    let shown = Set(layout.keys)
                    ForEach(state.workspace.userTables.map(\.name).filter { !shown.contains($0) }, id: \.self) { table in
                        Button(table) { state.addTableToCurrentDiagram(table, frames: layout) }
                    }
                } label: { Label(bi("Thêm bảng", "Add table"), systemImage: "rectangle.badge.plus") }
                    .menuStyle(.borderlessButton).fixedSize().font(DS.Typeface.bodySmall)
                    .disabled(layout.count >= state.workspace.userTables.count)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: UIMetrics.pageTabs)
        .background(DS.Palette.chrome)
        .hairline(.top)
        .confirmationDialog(bi("Xoá bố cục “\(deleting ?? "")”?", "Delete layout “\(deleting ?? "")”?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(bi("Xoá bố cục", "Delete layout"), role: .destructive) { if let name = deleting { state.deleteDiagramTab(name) }; deleting = nil }
            Button(bi("Huỷ", "Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(bi("Các bảng vẫn ở trong mô hình. Có thể hoàn tác bằng ⌘Z.", "Tables remain in the model. You can undo with ⌘Z."))
        }
    }

    private func startRename(_ name: String) {
        renameText = name
        renaming = name
        renameFocused = true
    }

    private func commitRename(_ name: String) {
        renaming = nil
        if renameText != name { state.renameDiagramTab(name, to: renameText) }
    }

    /// Tab trống: hướng dẫn như Desktop ("Set up your layout") với nút Auto layout.
    private var emptyLayoutHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.3.group").font(.system(size: 34)).foregroundStyle(DS.Palette.secondaryLabel)
            Text(bi("Thiết lập bố cục", "Set up your layout")).font(.system(size: 15, weight: .semibold))
            Text(bi("Chọn “Thêm bảng” ở thanh dưới, hoặc để BI Pro tự xếp tất cả bảng.", "Choose “Add table” below, or let BI Pro auto-arrange all tables."))
                .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).multilineTextAlignment(.center)
            Button(bi("Tự xếp bố cục", "Auto layout")) { state.autoLayoutCurrentDiagram(frames: layout) }.buttonStyle(.borderedProminent)
        }
        .padding(24)
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
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(DS.Palette.tertiaryLabel.opacity(0.28)))
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
                Menu {
                    Button(table.isHidden ? bi("Hiện bảng trong chế độ báo cáo", "Unhide in report view") : bi("Ẩn bảng trong chế độ báo cáo", "Hide in report view")) {
                        state.setTableHidden(table.name, hidden: !table.isHidden)
                    }
                    .disabled(state.modelEditingBlocker != nil)
                    if state.diagramTables(state.currentDiagram) != nil {
                        Divider()
                        Button(bi("Gỡ khỏi bố cục này", "Remove from this layout")) { state.removeTableFromCurrentDiagram(table.name) }
                    }
                } label: {
                    Image(systemName: table.isHidden ? "eye.slash" : "ellipsis").font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryLabel)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
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
                            // Kéo cột này thả lên cột của bảng khác để tạo quan hệ (Phase E). NSItemProvider vì `.draggable` không chạy (R9).
                            .onDrag { NSItemProvider(object: Self.dragPayload(table: table.name, column: column.name) as NSString) }
                            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                                guard let provider = providers.first else { return false }
                                let target = RelationshipDraft.ColumnRef(table: table.name, column: column.name)
                                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                                    guard let text = object as? String, let source = Self.parseDragPayload(text) else { return }
                                    DispatchQueue.main.async { state.proposeRelationship(drag: source, drop: target) }
                                }
                                return true
                            }
                    }
                    ForEach(measures, id: \.name) { m in
                        row(symbol: "function", tint: DS.Palette.measure, title: m.name, mono: false, badge: nil, hidden: m.isHidden, highlighted: false)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(DS.Palette.canvas)
        .opacity(table.isHidden ? 0.55 : 1)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(isSelected ? DS.Palette.accent : DS.Palette.separator, lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: .black.opacity(isSelected ? 0.10 : 0.05), radius: isSelected ? 10 : 2, y: isSelected ? 4 : 1)
    }

    static func dragPayload(table: String, column: String) -> String { "bipro-column\t\(table)\t\(column)" }

    static func parseDragPayload(_ text: String) -> RelationshipDraft.ColumnRef? {
        let parts = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 3 && parts[0] == "bipro-column" ? RelationshipDraft.ColumnRef(table: parts[1], column: parts[2]) : nil
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
            .background(Circle().fill(DS.Palette.canvas))
            .overlay(Circle().strokeBorder(color, lineWidth: 1))
            .position(x: point.x + side * 12, y: point.y)
    }
}

struct RelationshipPanel: View {
    let state: DocumentState
    let relationship: ModelMetadata.Relationship
    let close: () -> Void
    @State private var message: String?

    var body: some View {
        let blocker = state.modelEditingBlocker
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(DS.Palette.accent)
                Text(bi("Thuộc tính quan hệ", "Relationship properties")).font(DS.Typeface.headlineSmall)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(GhostIconButtonStyle())
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(bi("Từ:", "From:")).foregroundStyle(DS.Palette.secondaryLabel); Spacer()
                    Text("\(relationship.fromTable).\(relationship.fromColumn)").font(DS.Typeface.mono).foregroundStyle(DS.Palette.accent)
                    Text(relationship.cardinality.hasPrefix("M") ? bi("(Nhiều)", "(Many)") : bi("(Một)", "(One)")).foregroundStyle(DS.Palette.tertiaryLabel) }
                HStack { Text(bi("Đến:", "To:")).foregroundStyle(DS.Palette.secondaryLabel); Spacer()
                    Text("\(relationship.toTable).\(relationship.toColumn)").font(DS.Typeface.mono).foregroundStyle(DS.Palette.accent)
                    Text(relationship.cardinality.hasSuffix("M") ? bi("(Nhiều)", "(Many)") : bi("(Một)", "(One)")).foregroundStyle(DS.Palette.tertiaryLabel) }
            }
            .font(DS.Typeface.bodySmall)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Bản số", "Cardinality")).font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
                    Text(cardinalityText).font(DS.Typeface.body)
                    Text(bi("(chưa sửa được)", "(read-only)")).font(DS.Typeface.label).foregroundStyle(DS.Palette.tertiaryLabel)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Hướng lọc chéo", "Cross-filter direction")).font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
                    Picker("", selection: Binding(get: { relationship.crossFilteringBehavior == 2 ? 2 : 1 },
                                                  set: { message = state.updateRelationship(name: relationship.name, patch: RelationshipPatch(crossFilteringBehavior: $0)) })) {
                        Text(bi("Một chiều", "Single")).tag(1)
                        Text(bi("Hai chiều", "Both")).tag(2)
                    }
                    .labelsHidden().frame(width: 120).disabled(blocker != nil)
                }
            }
            HStack {
                Text(bi("Quan hệ đang hoạt động", "Active relationship")).font(DS.Typeface.body)
                Spacer()
                Toggle("", isOn: Binding(get: { relationship.isActive },
                                         set: { message = state.updateRelationship(name: relationship.name, patch: RelationshipPatch(isActive: $0)) }))
                    .labelsHidden().toggleStyle(.switch).disabled(blocker != nil)
            }
            if let text = message ?? blocker {
                Text(text).font(DS.Typeface.bodySmall).foregroundStyle(message != nil ? Color.red : DS.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(bi("Xoá quan hệ", "Delete relationship"), role: .destructive) { message = state.deleteRelationship(name: relationship.name) }
                    .buttonStyle(SecondaryButtonStyle()).disabled(blocker != nil)
                Spacer()
                Button(bi("Xong", "Done"), action: close).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(DS.Palette.canvas)
        .popoverElevation()
    }

    private var cardinalityText: String {
        switch relationship.cardinality {
        case "M:1": bi("Nhiều – một (*:1)", "Many to one (*:1)")
        case "1:M": bi("Một – nhiều (1:*)", "One to many (1:*)")
        case "1:1": bi("Một – một (1:1)", "One to one (1:1)")
        default: bi("Nhiều – nhiều (*:*)", "Many to many (*:*)")
        }
    }
}

/// Hộp xác nhận quan hệ mới (Phase E): từ, đến, bản số đã dò, hướng lọc, hoạt động.
struct RelationshipDraftPanel: View {
    let state: DocumentState
    let draft: RelationshipDraft
    @State private var crossFiltering = 1
    @State private var isActive = true

    var body: some View {
        let r = draft.relationship
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "plus.circle").foregroundStyle(DS.Palette.accent)
                Text(bi("Quan hệ mới", "New relationship")).font(DS.Typeface.headlineSmall)
                Spacer()
                Button { state.cancelRelationshipDraft() } label: { Image(systemName: "xmark") }.buttonStyle(GhostIconButtonStyle())
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(bi("Từ:", "From:")).foregroundStyle(DS.Palette.secondaryLabel); Spacer()
                    Text("\(r.fromTable).\(r.fromColumn)").font(DS.Typeface.mono).foregroundStyle(DS.Palette.accent)
                    Text(bi("(Nhiều)", "(Many)")).foregroundStyle(DS.Palette.tertiaryLabel) }
                HStack { Text(bi("Đến:", "To:")).foregroundStyle(DS.Palette.secondaryLabel); Spacer()
                    Text("\(r.toTable).\(r.toColumn)").font(DS.Typeface.mono).foregroundStyle(DS.Palette.accent)
                    Text(bi("(Một)", "(One)")).foregroundStyle(DS.Palette.tertiaryLabel) }
            }
            .font(DS.Typeface.bodySmall)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
            HStack {
                Text(bi("Bản số", "Cardinality")).font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
                Spacer()
                Text(bi("Nhiều – một (*:1)", "Many to one (*:1)")).font(DS.Typeface.body)
            }
            HStack {
                Text(bi("Hướng lọc chéo", "Cross-filter direction")).font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
                Spacer()
                Picker("", selection: $crossFiltering) { Text(bi("Một chiều", "Single")).tag(1); Text(bi("Hai chiều", "Both")).tag(2) }
                    .labelsHidden().frame(width: 120)
            }
            HStack {
                Text(bi("Quan hệ hoạt động", "Active relationship")).font(DS.Typeface.body)
                Spacer()
                Toggle("", isOn: Binding(get: { draft.forcedInactive ? false : isActive }, set: { isActive = $0 }))
                    .labelsHidden().toggleStyle(.switch).disabled(draft.forcedInactive)
            }
            ForEach(draft.notes, id: \.self) { note in
                Text(note).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            }
            if let notice = state.relationshipNotice {
                Text(notice).font(DS.Typeface.bodySmall).foregroundStyle(Color.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(bi("Huỷ", "Cancel")) { state.cancelRelationshipDraft() }.buttonStyle(SecondaryButtonStyle())
                Button(bi("Tạo", "Create")) { state.confirmRelationshipDraft(crossFiltering: crossFiltering, isActive: isActive) }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(DS.Palette.canvas)
        .popoverElevation()
    }
}

/// "Semantic model" tree, as in the Model view sidebar.
struct SemanticModelTree: View {
    @Bindable var state: DocumentState
    @State private var open: Set<String> = ["root", "relationships"]

    var body: some View {
        let _ = state.modelVersion
        let w = state.workspace
        let m = w.metadata
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TreeRow(level: 0, isExpanded: open.contains("root"), hasChildren: true, symbol: "point.3.connected.trianglepath.dotted",
                        tint: DS.Palette.accent, title: bi("Mô hình ngữ nghĩa", "Semantic model")) { toggle("root") }
                if open.contains("root") {
                    group("tables", bi("Bảng", "Tables"), "tablecells", w.userTables.count) {
                        ForEach(w.userTables, id: \.id) { t in
                            TreeRow(level: 2, symbol: "tablecells", tint: DS.Palette.table, title: t.name,
                                    isSelected: state.table == t.name && state.measure == nil) {
                                state.select(table: t.name); state.relationship = nil
                            }
                        }
                    }
                    group("relationships", bi("Quan hệ", "Relationships"), "arrow.left.arrow.right", m?.relationships.count ?? 0) {
                        ForEach(m?.relationships ?? [], id: \.self) { r in
                            let key = r.name.isEmpty ? "\(r.fromTable).\(r.fromColumn)->\(r.toTable).\(r.toColumn)" : r.name
                            TreeRow(level: 2, symbol: r.crossFilteringBehavior == 2 ? "arrow.triangle.2.circlepath" : "arrow.left.arrow.right",
                                    tint: r.isActive ? DS.Palette.secondaryLabel : DS.Palette.warning,
                                    title: "\(r.fromTable) ↔ \(r.toTable) (\(r.cardinality.replacingOccurrences(of: "M", with: "*"))\(r.crossFilteringBehavior == 2 ? bi(", hai chiều", ", both") : ""))",
                                    isSelected: state.relationship == key) {
                                state.relationship = key; state.measure = nil; state.measureDraft = nil
                            }
                        }
                    }
                    group("measures", bi("Measure", "Measures"), "function", m?.measures.count ?? 0) {
                        ForEach(m?.measures ?? [], id: \.self) { measure in
                            TreeRow(level: 2, symbol: "function", tint: DS.Palette.measure, title: measure.name,
                                    isSelected: state.measure == measure.name && state.table == measure.tableName,
                                    help: measure.expression) {
                                state.relationship = nil
                                state.selectMeasure(table: measure.tableName, name: measure.name)
                            }
                        }
                    }
                    group("hierarchies", bi("Phân cấp", "Hierarchies"), "list.bullet.indent", m?.hierarchies.count ?? 0) {
                        ForEach(m?.hierarchies ?? [], id: \.self) { h in
                            TreeRow(level: 2, symbol: "list.bullet.indent", tint: DS.Palette.secondaryLabel,
                                    title: "\(h.tableName) · \(h.name)", help: h.levels.map(\.name).joined(separator: " › ")) {}
                        }
                    }
                    group("roles", bi("Vai trò", "Roles"), "person.badge.shield.checkmark", m?.roles.count ?? 0) {
                        ForEach(m?.roles ?? [], id: \.self) { TreeRow(level: 2, symbol: "person", tint: DS.Palette.secondaryLabel, title: $0) {} }
                    }
                    group("perspectives", biN("Phối cảnh", "Perspectives"), "eye", m?.perspectives.count ?? 0) {
                        ForEach(m?.perspectives ?? [], id: \.self) { TreeRow(level: 2, symbol: "eye", tint: DS.Palette.secondaryLabel, title: $0) {} }
                    }
                    group("cultures", biN("Ngôn ngữ", "Cultures"), "character.book.closed", m?.cultures.count ?? 0) {
                        ForEach(m?.cultures ?? [], id: \.self) { TreeRow(level: 2, symbol: "globe", tint: DS.Palette.secondaryLabel, title: $0) {} }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        PaneFooter(text: biN("\(w.userTables.count) bảng · \(m?.relationships.count ?? 0) quan hệ · hợp lệ", "\(w.userTables.count) tables · \(m?.relationships.count ?? 0) relationships · valid"))
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
