import Foundation

/// Căn lề, phân bố và nhóm visual (D7) ở chế độ Sửa của tab Báo cáo.
extension DocumentState {
    /// Lý do chưa sắp xếp được (chế độ Xem, tab khác, báo cáo định dạng cũ), hoặc nil.
    var arrangeBlocker: String? {
        if mode != .report { return biN("Chỉ sắp xếp được ở chế độ Báo cáo.", "Arranging is only available in Report view.") }
        if !canEditCanvas { return biN("Báo cáo này chưa sửa được bố cục.", "This report's layout can't be edited yet.") }
        if !editMode { return biN("Bật chế độ Sửa (⌘E) để căn lề hoặc nhóm visual.", "Turn on Edit mode (⌘E) to align or group visuals.") }
        return nil
    }

    func alignBlocker(_ command: AlignCommand) -> String? { arrangeBlocker ?? layout.alignBlocker(command) }
    var groupBlocker: String? {
        arrangeBlocker ?? (canEditLayout ? layout.groupBlocker() : biN("Nhóm visual chưa làm cho báo cáo định dạng cũ (Report/Layout).", "Grouping visuals isn't available for legacy-format reports (Report/Layout) yet."))
    }
    var ungroupBlocker: String? {
        arrangeBlocker ?? (canEditLayout ? layout.ungroupBlocker() : biN("Nhóm visual chưa làm cho báo cáo định dạng cũ (Report/Layout).", "Grouping visuals isn't available for legacy-format reports (Report/Layout) yet."))
    }

    var mergeBlocker: String? {
        arrangeBlocker ?? (canEditLayout ? layout.mergeBlocker() : biN("Nhóm visual chưa làm cho báo cáo định dạng cũ (Report/Layout).", "Grouping visuals isn't available for legacy-format reports (Report/Layout) yet."))
    }

    func zOrderBlocker(_ command: ZOrderCommand) -> String? {
        arrangeBlocker ?? (canEditLayout ? layout.zOrderBlocker(command) : biN("Đổi thứ tự lớp chưa làm cho báo cáo định dạng cũ (Report/Layout).", "Changing layer order isn't available for legacy-format reports (Report/Layout) yet."))
    }

    func reorder(_ command: ZOrderCommand) {
        guard zOrderBlocker(command) == nil else { return }
        layout.reorder(command)
        visualID = layout.primary
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

    /// Gộp các visual đang chọn vào nhóm đang chọn (lệnh Merge của Desktop).
    func mergeSelection() {
        guard mergeBlocker == nil else { return }
        layout.mergeIntoGroup()
        visualID = layout.primary
    }

    func ungroupSelection() {
        guard ungroupBlocker == nil else { return }
        layout.ungroup()
        visualID = layout.primary
    }
}
