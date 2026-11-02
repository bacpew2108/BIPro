import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

// MARK: - Dropdown Slicer View

struct DropdownSlicerView: View {
    let data: SlicerData
    let title: String?
    let context: VisualRenderContext

    @State private var isPresented: Bool = false
    @State private var expandedPaths: Set<[Value]> = []

    init(data: SlicerData, title: String?, context: VisualRenderContext) {
        self.data = data
        self.title = title
        self.context = context
    }

    var body: some View {
        let showHeader = context.format.slicer.headerShow ?? true
        let headerText = title ?? data.levels.map(\.displayName).joined(separator: ", ")
        let headerSize = ReportUnits.pixels(fromPoints: context.format.slicer.headerTextSize ?? 10)
        let headerColor = context.theme.color(context.format.slicer.headerFontColor) ?? context.theme.foregroundColor
        let summaryText = SlicerTree.summary(selection: context.slicerSelection, roots: data.roots)

        VStack(alignment: .leading, spacing: 4) {
            if showHeader && !headerText.isEmpty {
                Text(headerText)
                    .font(.system(size: headerSize, weight: .semibold))
                    .foregroundStyle(headerColor)
                    .lineLimit(1)
            }

            // Ô viền mảnh xám dropdown
            HStack(spacing: 6) {
                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(context.theme.foregroundColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.gray)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(hex: "#D1D5DB") ?? Color.gray.opacity(0.4), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                isPresented.toggle()
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                SlicerDropdownListView(
                    data: data,
                    context: context,
                    expandedPaths: $expandedPaths,
                    onClose: { isPresented = false }
                )
                .background(Color.white)
                .environment(\.colorScheme, .light)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Dropdown List Content

struct SlicerDropdownListView: View {
    let data: SlicerData
    let context: VisualRenderContext
    @Binding var expandedPaths: Set<[Value]>
    var onClose: () -> Void

    init(
        data: SlicerData,
        context: VisualRenderContext,
        expandedPaths: Binding<Set<[Value]>>,
        onClose: @escaping () -> Void = {}
    ) {
        self.data = data
        self.context = context
        self._expandedPaths = expandedPaths
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Dòng đầu: "Chọn tất cả"
            Button(action: {
                context.actions.slicerChanged(SlicerSelection([]))
            }) {
                HStack(spacing: 8) {
                    Image(systemName: context.slicerSelection.isEmpty ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(context.slicerSelection.isEmpty ? Color.accentColor : Color.gray)
                    Text("Chọn tất cả")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            // Danh sách các cấp giá trị cuộn được (tối đa ~300 pt)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(flattenedNodes, id: \.path) { item in
                        SlicerNodeRow(
                            item: item,
                            selection: context.slicerSelection,
                            roots: data.roots,
                            isExpanded: expandedPaths.contains(item.path),
                            onToggleExpand: {
                                if expandedPaths.contains(item.path) {
                                    expandedPaths.remove(item.path)
                                } else {
                                    expandedPaths.insert(item.path)
                                }
                            },
                            onSelect: { additive in
                                let next = SlicerTree.toggle(
                                    selection: context.slicerSelection,
                                    path: item.path,
                                    additive: additive,
                                    roots: data.roots
                                )
                                context.actions.slicerChanged(next)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
        }
        .frame(minWidth: 220, maxWidth: 360)
        .background(Color.white)
    }

    struct FlattenedItem {
        let node: SlicerNode
        let path: [Value]
        let depth: Int
    }

    private var flattenedNodes: [FlattenedItem] {
        var items: [FlattenedItem] = []
        func collect(nodes: [SlicerNode], prefix: [Value], depth: Int) {
            for node in nodes {
                let currentPath = prefix + [node.value]
                items.append(FlattenedItem(node: node, path: currentPath, depth: depth))
                if !node.children.isEmpty && expandedPaths.contains(currentPath) {
                    collect(nodes: node.children, prefix: currentPath, depth: depth + 1)
                }
            }
        }
        collect(nodes: data.roots, prefix: [], depth: 0)
        return items
    }
}

// MARK: - Row cho từng node

private struct SlicerNodeRow: View {
    let item: SlicerDropdownListView.FlattenedItem
    let selection: SlicerSelection
    let roots: [SlicerNode]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onSelect: (_ additive: Bool) -> Void

    var body: some View {
        let state = SlicerTree.state(of: item.path, in: selection, roots: roots)
        let labelText = item.node.value == .blank
            ? "(Trống)"
            : NumberDisplay.plain(DataCell(item.node.value))

        HStack(spacing: 6) {
            // Thụt lề cấp con 16 pt
            if item.depth > 0 {
                Spacer()
                    .frame(width: CGFloat(item.depth) * 16)
            }

            // Nút mở/đóng cấp con ▸/▾ nếu có con
            if !item.node.children.isEmpty {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.gray)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }

            // Ô vuông trạng thái chọn (.on/.off/.mixed)
            Image(systemName: checkmarkImageName(state))
                .font(.system(size: 13))
                .foregroundStyle(checkmarkColor(state))
                .frame(width: 16, height: 16)

            // Nhãn giá trị
            Text(labelText)
                .font(.system(size: 12))
                .foregroundStyle(Color.black)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            let additive = flags.contains(.command) || flags.contains(.control)
            onSelect(additive)
        }
    }

    private func checkmarkImageName(_ state: SlicerCheckState) -> String {
        switch state {
        case .on: return "checkmark.square.fill"
        case .mixed: return "minus.square.fill"
        case .off: return "square"
        }
    }

    private func checkmarkColor(_ state: SlicerCheckState) -> Color {
        switch state {
        case .on, .mixed: return Color.accentColor
        case .off: return Color.gray.opacity(0.7)
        }
    }
}
