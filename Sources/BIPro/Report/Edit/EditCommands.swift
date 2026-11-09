import AppKit
import SwiftUI

// MARK: - Tài liệu đang lấy tiêu điểm

private struct DocumentStateKey: FocusedValueKey { typealias Value = DocumentState }

extension FocusedValues {
    /// Tài liệu của cửa sổ đang lấy tiêu điểm, để menu (Lưu, Hoàn tác…) biết tác động lên đâu.
    var documentState: DocumentState? {
        get { self[DocumentStateKey.self] }
        set { self[DocumentStateKey.self] = newValue }
    }
}

extension DocumentState {
    /// Hoàn tác một bước bố cục; trang và vùng chọn đi theo bước đó.
    func undoLayout() {
        layout.undo()
        followLayout()
    }

    func redoLayout() {
        layout.redo()
        followLayout()
    }

    private func followLayout() {
        if let page = layout.currentPageID, page != pageID { pageID = page }
        visualID = layout.primary
    }

    /// ⌘D: nhân bản các visual đang chọn (chỉ ở chế độ Sửa của tab Báo cáo).
    func duplicateSelection() {
        guard mode == .report, editMode, !layout.selection.isEmpty else { return }
        layout.duplicate(layout.selection)
        visualID = layout.primary
    }

    /// Chữ hiện ở huy hiệu cạnh tên file.
    var statusBadge: String {
        if layout.isDirty { return "Chưa lưu" }
        return editMode ? "Đang sửa" : "Chỉ xem"
    }
}

// MARK: - Lệnh menu

/// Hoàn tác / Làm lại thay cho mục hệ thống. Khi đang gõ trong ô văn bản (editor DAX, ô tìm) thì chuyển lệnh
/// cho ô đó, để Hoàn tác của văn bản không bị mất.
struct EditCommands: Commands {
    @FocusedValue(\.documentState) private var state

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Nhân bản visual") { state?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Hoàn tác") { perform(text: Selector(("undo:"))) { $0.undoLayout() } }
                .keyboardShortcut("z", modifiers: .command)
            Button("Làm lại") { perform(text: Selector(("redo:"))) { $0.redoLayout() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    @MainActor private func perform(text selector: Selector, layout: (DocumentState) -> Void) {
        if NSApp.keyWindow?.firstResponder is NSText {
            NSApp.sendAction(selector, to: nil, from: nil)
        } else if let state, state.mode == .report {
            layout(state)
        }
    }
}
