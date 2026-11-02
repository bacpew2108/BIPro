import AppKit
import SwiftUI

// MARK: - Thanh tab truy vấn DAX

/// Thanh tab phía trên editor DAX: danh sách tab, nút thêm tab và tên mô hình ở bên phải.
/// Hỗ trợ nhấp đúp đổi tên tại chỗ và menu chuột phải (Đổi tên, Nhân bản, Đóng, Đóng các tab khác).
struct QueryTabBar: View {
    @Bindable var state: DocumentState
    @State private var editingIndex: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(state.daxQueries.enumerated()), id: \.element.id) { index, query in
                tabView(index: index, query: query)
            }

            Button {
                state.daxQueries.append(DAXQueryTab(title: "Truy vấn \(state.daxQueries.count + 1)", text: "EVALUATE\n"))
                state.daxSelection = state.daxQueries.count - 1
            } label: { Image(systemName: "plus") }
                .buttonStyle(GhostIconButtonStyle())

            Spacer()
            Text("Mô hình: \(state.fileName) · Import")
                .font(DS.Typeface.mono)
                .foregroundStyle(DS.Palette.tertiaryLabel)
                .padding(.trailing, 12)
        }
        .padding(.leading, 8)
        .background(DS.Palette.chrome)
        .hairline(.bottom)
    }

    @ViewBuilder
    private func tabView(index: Int, query: DAXQueryTab) -> some View {
        let selected = index == state.daxSelection
        HStack(spacing: 6) {
            Image(systemName: "terminal").font(.system(size: 10))

            if editingIndex == index {
                InlineRenameField(
                    text: query.title,
                    onCommit: { newTitle in
                        state.daxQueries[index].title = newTitle
                        editingIndex = nil
                    },
                    onCancel: {
                        editingIndex = nil
                    }
                )
                .frame(minWidth: 60, maxWidth: 160)
                .frame(height: 20)
            } else {
                Text(query.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
            }

            if state.daxQueries.count > 1 && editingIndex != index {
                Button {
                    closeTab(at: index)
                } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(selected ? Color.white : Color.clear)
        .overlay(alignment: .bottom) {
            if selected { Rectangle().fill(DS.Palette.accent).frame(height: 2) }
        }
        .onTapGesture(count: 2) {
            editingIndex = index
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if editingIndex != index {
                    state.daxSelection = index
                }
            }
        )
        .contextMenu {
            Button("Đổi tên") {
                editingIndex = index
            }
            Button("Nhân bản") {
                let current = state.daxQueries[index]
                let newTab = DAXQueryTab(title: "\(current.title) (bản sao)", text: current.text)
                state.daxQueries.insert(newTab, at: index + 1)
                state.daxSelection = index + 1
            }
            Button("Đóng") {
                closeTab(at: index)
            }
            .disabled(state.daxQueries.count <= 1)

            Button("Đóng các tab khác") {
                closeOtherTabs(keeping: index)
            }
            .disabled(state.daxQueries.count <= 1)
        }
    }

    private func closeTab(at index: Int) {
        guard state.daxQueries.count > 1 else { return }
        if editingIndex == index { editingIndex = nil }
        state.daxQueries.remove(at: index)
        state.daxSelection = min(state.daxSelection, state.daxQueries.count - 1)
    }

    private func closeOtherTabs(keeping index: Int) {
        guard state.daxQueries.count > 1 else { return }
        let keep = state.daxQueries[index]
        editingIndex = nil
        state.daxQueries = [keep]
        state.daxSelection = 0
    }
}

// MARK: - Ô sửa tên tab tại chỗ

struct InlineRenameField: NSViewRepresentable {
    var text: String
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .white
        field.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        field.stringValue = text
        field.delegate = context.coordinator
        field.focusRingType = .none

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.selectText(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineRenameField
        var hasFinished = false

        init(_ parent: InlineRenameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                guard !hasFinished else { return true }
                hasFinished = true
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !hasFinished else { return }
            hasFinished = true
            guard let field = obj.object as? NSTextField else {
                parent.onCancel()
                return
            }
            let reason = (obj.userInfo?["NSTextMovement"] as? Int) ?? 0
            if reason == NSReturnTextMovement {
                let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parent.onCommit(trimmed)
                } else {
                    parent.onCancel()
                }
            } else {
                // Esc hoặc mất focus
                parent.onCancel()
            }
        }
    }
}
