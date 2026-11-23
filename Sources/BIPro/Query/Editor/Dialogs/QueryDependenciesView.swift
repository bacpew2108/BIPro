import SwiftUI
import ColumnStore
import MEngine

public struct QueryDependenciesContent: View {
    public let graph: DependencyGraphModel
    public var scrollable: Bool = true
    public var initialSelectedId: String? = nil
    public var onClose: () -> Void

    @State private var selectedId: String? = nil
    @State private var zoomScale: CGFloat = 1.0

    public init(
        graph: DependencyGraphModel,
        scrollable: Bool = true,
        initialSelectedId: String? = nil,
        onClose: @escaping () -> Void
    ) {
        self.graph = graph
        self.scrollable = scrollable
        self.initialSelectedId = initialSelectedId
        self._selectedId = State(initialValue: initialSelectedId)
        self.onClose = onClose
    }

    private var layout: DependencyLayout {
        DependencyLayout(graph: graph)
    }

    private var selectedUpstream: Set<String> {
        guard let id = selectedId else { return [] }
        return layout.upstream(of: id)
    }

    private var selectedDownstream: Set<String> {
        guard let id = selectedId else { return [] }
        return layout.downstream(of: id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
                .hairline(.bottom)

            // Cycle Warning Banner (if cycle exists)
            if let cycle = graph.cycle, !cycle.isEmpty {
                cycleBanner(cycle: cycle)
                    .hairline(.bottom)
            }

            // Canvas Workspace
            ZStack(alignment: .bottomTrailing) {
                if scrollable {
                    ScrollView([.horizontal, .vertical]) {
                        canvasView
                            .scaleEffect(zoomScale, anchor: .topLeading)
                            .frame(width: canvasWidth * zoomScale, height: canvasHeight * zoomScale)
                    }
                    .background(DS.Palette.chrome)
                } else {
                    canvasView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(DS.Palette.chrome)
                        .clipped()
                }

                // Selection info overlay (bottom right)
                if let id = selectedId, let node = graph.nodes.first(where: { $0.id == id }) {
                    selectionOverlay(node: node)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom Controls Bar
            bottomBar
                .hairline(.top)
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(DS.Palette.canvas)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)

            Text(bi("Phụ thuộc truy vấn", "Query dependencies"))
                .font(DS.Typeface.headlineMedium)
                .foregroundStyle(DS.Palette.label)

            Spacer()

            Text(bi("\(graph.nodes.count) nút · \(graph.edges.count) liên kết", "\(graph.nodes.count) nodes · \(graph.edges.count) links"))
                .font(DS.Typeface.bodySmall)
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(DS.Palette.canvas)
    }

    // MARK: - Cycle Banner

    private func cycleBanner(cycle: [String]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.Palette.danger)

            Text(bi("Vòng tham chiếu: ", "Reference cycle: ") + cycle.joined(separator: " → "))
                .font(DS.Typeface.bodySmall)
                .fontWeight(.medium)
                .foregroundStyle(DS.Palette.danger)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Palette.danger.opacity(0.12))
    }

    // MARK: - Canvas View

    private var canvasWidth: CGFloat {
        let maxCol = layout.maxColumn
        return max(960, CGFloat(maxCol + 1) * 260 + 80)
    }

    private var canvasHeight: CGFloat {
        let maxR = layout.maxRow
        return max(500, CGFloat(maxR + 1) * 110 + 120)
    }

    private var canvasView: some View {
        ZStack(alignment: .topLeading) {
            // Background dot pattern
            dotGridPattern

            // Column Header Labels
            columnHeaders

            // Edge Connector Curves
            edgesLayer

            // Node Cards
            nodesLayer
        }
        .frame(width: canvasWidth, height: canvasHeight)
    }

    private var dotGridPattern: some View {
        Canvas { context, size in
            let step: CGFloat = 20
            var x: CGFloat = 10
            while x < size.width {
                var y: CGFloat = 10
                while y < size.height {
                    let rect = CGRect(x: x, y: y, width: 2, height: 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.gray.opacity(0.2)))
                    y += step
                }
                x += step
            }
        }
    }

    private var columnHeaders: some View {
        let maxCol = layout.maxColumn
        return HStack(spacing: 0) {
            ForEach(0...max(1, maxCol), id: \.self) { col in
                let title = col == 0 ? bi("NGUỒN DỮ LIỆU", "DATA SOURCES") : bi("TRUY VẤN", "QUERIES")
                HStack(spacing: 6) {
                    Circle()
                        .fill(col == 0 ? DS.Palette.series[4] : DS.Palette.accent)
                        .frame(width: 6, height: 6)

                    Text(title)
                        .font(DS.Typeface.labelSmall)
                        .fontWeight(.bold)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .tracking(0.5)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(width: 200, height: 28)
                .position(x: 30 + CGFloat(col) * 260 + 100, y: 20)
            }
        }
    }

    private var edgesLayer: some View {
        Canvas { context, _ in
            for edge in graph.edges {
                guard let fromNode = graph.nodes.first(where: { $0.id == edge.from }),
                      let toNode = graph.nodes.first(where: { $0.id == edge.to }) else { continue }

                let p1 = layout.position(of: fromNode.id)
                let p2 = layout.position(of: toNode.id)

                let startX = 30 + CGFloat(p1.column) * 260 + 200
                let startY = 60 + CGFloat(p1.row) * 110 + 40

                let endX = 30 + CGFloat(p2.column) * 260
                let endY = 60 + CGFloat(p2.row) * 110 + 40

                let isRelated: Bool = {
                    guard let sel = selectedId else { return true }
                    let set = selectedUpstream.union(selectedDownstream).union([sel])
                    return set.contains(edge.from) && set.contains(edge.to)
                }()

                let color: Color = isRelated ? DS.Palette.accent : Color.gray.opacity(0.3)
                let lineWidth: CGFloat = isRelated ? 2.0 : 1.5

                var path = Path()
                path.move(to: CGPoint(x: startX, y: startY))
                let dx = max(30, (endX - startX) / 2)
                path.addCurve(
                    to: CGPoint(x: endX, y: endY),
                    control1: CGPoint(x: startX + dx, y: startY),
                    control2: CGPoint(x: endX - dx, y: endY)
                )
                context.stroke(path, with: .color(color), lineWidth: lineWidth)

                // Arrowhead pointing right at (endX, endY)
                var arrow = Path()
                arrow.move(to: CGPoint(x: endX, y: endY))
                arrow.addLine(to: CGPoint(x: endX - 6, y: endY - 4))
                arrow.addLine(to: CGPoint(x: endX - 6, y: endY + 4))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(color))
            }
        }
    }

    private var nodesLayer: some View {
        ForEach(graph.nodes) { node in
            let pos = layout.position(of: node.id)
            let isSelected = selectedId == node.id
            let isRelated = selectedId == nil || isSelected || selectedUpstream.contains(node.id) || selectedDownstream.contains(node.id)

            nodeCard(node: node, isSelected: isSelected)
                .opacity(isRelated ? 1.0 : 0.35)
                .position(
                    x: 30 + CGFloat(pos.column) * 260 + 100,
                    y: 60 + CGFloat(pos.row) * 110 + 40
                )
                .onTapGesture {
                    if selectedId == node.id {
                        selectedId = nil
                    } else {
                        selectedId = node.id
                    }
                }
        }
    }

    private func nodeCard(node: DependencyNode, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: node.kind == .source ? "doc.text.fill" : "tablecells.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(node.kind == .source ? DS.Palette.series[4] : DS.Palette.accent)
                    .frame(width: 24, height: 24)
                    .background((node.kind == .source ? DS.Palette.series[4] : DS.Palette.accent).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title)
                        .font(DS.Typeface.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(node.kind == .source ? biN("Tệp", "File") : biN("Truy vấn", "Query"))
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.secondaryLabel)

                        if node.kind == .query && !node.enableLoad {
                            Text(bi("(Không nạp)", "(Not loaded)"))
                                .font(DS.Typeface.labelSmall)
                                .italic()
                                .foregroundStyle(DS.Palette.tertiaryLabel)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(width: 200, height: 80)
        .background(DS.Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.tile)
                .strokeBorder(isSelected ? DS.Palette.accent : DS.Palette.separator, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? DS.Palette.accent.opacity(0.15) : Color.black.opacity(0.04), radius: isSelected ? 4 : 2, y: 1)
    }

    // MARK: - Selection Overlay

    private func selectionOverlay(node: DependencyNode) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bi("Đã chọn: \(node.title)", "Selected: \(node.title)"))
                    .font(DS.Typeface.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Palette.label)

                Text(bi("Thượng nguồn: \(selectedUpstream.count) nút · Hạ nguồn: \(selectedDownstream.count) nút", "Upstream: \(selectedUpstream.count) nodes · Downstream: \(selectedDownstream.count) nodes"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }

            Button {
                selectedId = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    // MARK: - Bottom Controls Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Zoom controls
            HStack(spacing: 4) {
                Text(bi("Thu phóng", "Zoom"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                Button {
                    if zoomScale > 0.5 { zoomScale = max(0.5, zoomScale - 0.1) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(SecondaryButtonStyle())

                Text("\(Int(zoomScale * 100))%")
                    .font(DS.Typeface.mono)
                    .frame(width: 44)

                Button {
                    if zoomScale < 2.0 { zoomScale = min(2.0, zoomScale + 0.1) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Button(bi("Vừa khung", "Fit to view")) {
                zoomScale = 1.0
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button(bi("Đóng", "Close"), action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(DS.Palette.chrome)
    }
}

public struct QueryDependenciesView: View {
    public let state: QueryEditorState
    public var scrollable: Bool = true
    public var initialSelectedId: String? = nil
    public let onClose: () -> Void

    public init(
        state: QueryEditorState,
        scrollable: Bool = true,
        initialSelectedId: String? = nil,
        onClose: @escaping () -> Void
    ) {
        self.state = state
        self.scrollable = scrollable
        self.initialSelectedId = initialSelectedId
        self.onClose = onClose
    }

    public var body: some View {
        QueryDependenciesContent(
            graph: state.dependencyGraph,
            scrollable: scrollable,
            initialSelectedId: initialSelectedId,
            onClose: onClose
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .popoverElevation()
    }
}
