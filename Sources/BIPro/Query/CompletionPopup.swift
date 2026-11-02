import AppKit
import SwiftUI

/// Cửa sổ danh sách gợi ý tự hoàn thành (IntelliSense) ngay dưới con trỏ.
@MainActor
final class CompletionPopupController {
    private var panel: NSPanel?
    private let state = CompletionState()
    private weak var textView: NSTextView?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var replaceRange: NSRange {
        state.replaceRange
    }

    func show(result: CompletionResult, at charIndex: Int, in textView: NSTextView) {
        guard !result.items.isEmpty, let window = textView.window else {
            hide()
            return
        }

        self.textView = textView
        state.items = result.items
        state.selectedIndex = 0
        state.replaceRange = result.replaceRange

        let panel = getOrCreatePanel()

        // Tính vị trí màn hình của con trỏ
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            hide()
            return
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(charIndex, max(0, (textView.string as NSString).length - 1)))
        var glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        glyphRect.origin.x += textView.textContainerInset.width
        glyphRect.origin.y += textView.textContainerInset.height

        let windowRect = textView.convert(glyphRect, to: nil)
        let screenRect = window.convertToScreen(windowRect)

        let count = min(result.items.count, 7)
        let popupHeight = CGFloat(count * 28 + 12)
        let popupWidth: CGFloat = 320

        var popupOrigin = NSPoint(x: screenRect.minX, y: screenRect.minY - popupHeight - 4)

        if let screen = window.screen {
            if popupOrigin.y < screen.visibleFrame.minY {
                popupOrigin.y = screenRect.maxY + 4
            }
            popupOrigin.x = max(screen.visibleFrame.minX, min(popupOrigin.x, screen.visibleFrame.maxX - popupWidth))
        }

        panel.setFrame(NSRect(origin: popupOrigin, size: NSSize(width: popupWidth, height: popupHeight)), display: true)

        if !panel.isVisible {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        if let panel, panel.isVisible {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        state.items = []
        state.selectedIndex = 0
    }

    func selectNext() {
        guard isVisible, !state.items.isEmpty else { return }
        state.selectedIndex = (state.selectedIndex + 1) % state.items.count
    }

    func selectPrevious() {
        guard isVisible, !state.items.isEmpty else { return }
        state.selectedIndex = (state.selectedIndex - 1 + state.items.count) % state.items.count
    }

    func commitSelected() {
        guard isVisible, state.items.indices.contains(state.selectedIndex), textView != nil else { return }
        let item = state.items[state.selectedIndex]
        insert(item: item)
    }

    func insert(item: CompletionItem) {
        guard let textView else { return }
        let range = state.replaceRange
        hide()
        textView.insertText(item.insertText, replacementRange: range)
    }

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false   // giữ bằng tham chiếu mạnh; AppKit không được tự release
        panel.appearance = NSAppearance(named: .aqua)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let hosting = NSHostingView(rootView: CompletionListView(state: state, onSelect: { [weak self] item in
            self?.insert(item: item)
        }))
        panel.contentView = hosting

        self.panel = panel
        return panel
    }
}

@Observable
final class CompletionState {
    var items: [CompletionItem] = []
    var selectedIndex: Int = 0
    var replaceRange: NSRange = NSRange(location: 0, length: 0)
}

struct CompletionListView: View {
    let state: CompletionState
    let onSelect: (CompletionItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                        let isSelected = index == state.selectedIndex
                        HStack(spacing: 8) {
                            kindIcon(item.kind)
                                .font(.system(size: 11))
                                .frame(width: 16, height: 16)
                                .foregroundStyle(iconColor(item.kind))

                            Text(item.label)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13))

                            Spacer()

                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                        .contentShape(Rectangle())
                        .id(index)
                        .onTapGesture {
                            onSelect(item)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: state.selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.18), lineWidth: 1))
        .environment(\.colorScheme, .light)
    }

    private func kindIcon(_ kind: CompletionItemKind) -> Image {
        switch kind {
        case .function:
            return Image(systemName: "function")
        case .table:
            return Image(systemName: "tablecells")
        case .column:
            return Image(systemName: "textformat.abc")
        case .measure:
            return Image(systemName: "sum")
        case .keyword:
            return Image(systemName: "textformat")
        }
    }

    private func iconColor(_ kind: CompletionItemKind) -> Color {
        switch kind {
        case .function:
            return Color(red: 0.29, green: 0.28, blue: 0.82) // indigo
        case .table:
            return Color(red: 0.60, green: 0.25, blue: 0.0)  // tertiary/brown
        case .column:
            return Color(red: 0.0, green: 0.45, blue: 0.8)   // blue
        case .measure:
            return Color(red: 0.10, green: 0.55, blue: 0.25) // green
        case .keyword:
            return Color(red: 0.0, green: 0.35, blue: 0.70)  // keyword blue
        }
    }
}
