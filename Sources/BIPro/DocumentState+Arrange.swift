import Foundation

/// Căn lề, phân bố và nhóm visual (D7) ở chế độ Sửa của tab Báo cáo.
extension DocumentState {
    /// Lý do chưa sắp xếp được (chế độ Xem, tab khác, báo cáo định dạng cũ), hoặc nil.
    var arrangeBlocker: String? {
        if mode != .report { return "Chỉ sắp xếp được ở chế độ Báo cáo." }
        if !canEditCanvas { return "Báo cáo này chưa sửa được bố cục." }
        if !editMode { return "Bật chế độ Sửa (⌘E) để căn lề hoặc nhóm visual." }
        return nil
    }

    func alignBlocker(_ command: AlignCommand) -> String? { arrangeBlocker ?? layout.alignBlocker(command) }
    var groupBlocker: String? {
        arrangeBlocker ?? (canEditLayout ? layout.groupBlocker() : "Nhóm visual chưa làm cho báo cáo định dạng cũ (Report/Layout).")
    }
    var ungroupBlocker: String? {
        arrangeBlocker ?? (canEditLayout ? layout.ungroupBlocker() : "Nhóm visual chưa làm cho báo cáo định dạng cũ (Report/Layout).")
    }

    func align(_ command: AlignCommand) {
        guard alignBlocker(command) == nil else { return }
        layout.align(command)
        visualID = layout.primary
    }

    func groupSelection() {
        guard groupBlocker == nil else { return }
        layout.group()
        visualID = layout.primary
    }

    func ungroupSelection() {
        guard ungroupBlocker == nil else { return }
        layout.ungroup()
        visualID = layout.primary
    }
}
