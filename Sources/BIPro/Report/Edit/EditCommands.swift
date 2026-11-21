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
        if layout.isDirty { return tr(.statusDirtyBadge) }
        return editMode ? tr(.statusEditBadge) : bi("Chỉ xem", "View only")
    }
}

// MARK: - Lệnh menu

/// Hoàn tác / Làm lại thay cho mục hệ thống. Khi đang gõ trong ô văn bản (editor DAX, ô tìm) thì chuyển lệnh
/// cho ô đó, để Hoàn tác của văn bản không bị mất.
struct EditCommands: Commands {
    @FocusedValue(\.documentState) private var state

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button(bi("Cắt visual", "Cut Visual")) {
                perform(text: #selector(NSText.cut(_:))) { st in
                    guard st.mode == .report, st.editMode, !st.layout.selection.isEmpty else { return }
                    st.layout.cut(); st.visualID = st.layout.primary
                }
            }
            .keyboardShortcut("x", modifiers: .command)
            Button(bi("Sao chép visual", "Copy Visual")) {
                perform(text: #selector(NSText.copy(_:))) { st in
                    guard st.mode == .report, st.editMode, !st.layout.selection.isEmpty else { return }
                    st.layout.copy()
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            Button(bi("Dán visual", "Paste Visual")) {
                perform(text: #selector(NSText.paste(_:))) { st in
                    guard st.mode == .report, st.editMode, st.layout.hasClipboard else { return }
                    _ = st.layout.paste(); st.visualID = st.layout.primary
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            Divider()
            Button(bi("Nhân bản visual", "Duplicate Visual")) { state?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
            Menu(bi("Căn lề", "Align")) {
                ForEach(AlignCommand.allCases, id: \.self) { command in
                    Button(command.title) { state?.align(command) }
                        .disabled(state?.alignBlocker(command) != nil)
                }
            }
            Button(bi("Nhóm visual", "Group Visuals")) { state?.groupSelection() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(state?.groupBlocker != nil)
            Button(tr(.menuUngroup)) { state?.ungroupSelection() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(state?.ungroupBlocker != nil)
            Button(bi("Gộp vào nhóm", "Merge into Group")) { state?.mergeSelection() }
                .disabled(state?.mergeBlocker != nil)
            Divider()
            Button(bi("Làm mới dữ liệu", "Refresh Data")) { state?.startRefreshAll() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state?.refreshBlocker != nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(tr(.menuUndo)) { perform(text: Selector(("undo:"))) { $0.undoLayout() } }
                .keyboardShortcut("z", modifiers: .command)
            Button(tr(.menuRedo)) { perform(text: Selector(("redo:"))) { $0.redoLayout() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    @MainActor private func perform(text selector: Selector, layout: (DocumentState) -> Void) {
        if NSApp.keyWindow?.firstResponder is NSText {
            NSApp.sendAction(selector, to: nil, from: nil)
        } else if let state {
            layout(state)
        }
    }
}
