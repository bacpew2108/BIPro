// Wave 3C (T019): Nối One-Click Refresh (⇧⌘R) vào DocumentState.
import ColumnStore
import Foundation
import PBIXKit

extension DocumentState {
    /// Lý do nút "Làm mới" bị vô hiệu hoá; nil khi sẵn sàng làm mới.
    var refreshBlocker: String? {
        if workspace.metadata == nil { return bi("File không có mô hình dữ liệu để làm mới", "File has no data model to refresh") }
        if refreshProgress?.isRunning == true { return bi("Đang làm mới dữ liệu…", "Refresh already in progress…") }
        return nil
    }

    /// Kích hoạt làm mới toàn bộ bảng từ Ribbon hoặc phím tắt ⇧⌘R (mở `RefreshProgressSheet`).
    func startRefreshAll() {
        guard refreshBlocker == nil else { return }
        let progress = RefreshProgressState()
        refreshProgress = progress
        Task { @MainActor in
            _ = await performRefreshAll(progress: progress)
        }
    }

    /// Đóng hộp tiến trình làm mới (khi đã xong).
    func closeRefreshSheet() {
        if refreshProgress?.isRunning == true {
            refreshProgress?.isCancelled = true
        } else {
            refreshProgress = nil
        }
    }

    /// Thực thi làm mới tất cả bảng (dùng cho cả UI lẫn test tự động).
    @discardableResult
    func performRefreshAll(progress: RefreshProgressState? = nil) async -> RefreshSummary {
        guard let metadata = workspace.metadata else {
            return RefreshSummary(applyError: bi("File không có mô hình dữ liệu.", "File has no data model."))
        }
        let ws = self.workspace
        let (refreshed, initialSummary) = await RefreshCoordinator.evaluateAll(
            metadata: metadata,
            existingTable: { name in
                (try? ws.table(name)).flatMap(TableDataEncoding.tableData(from:))
            },
            progress: progress
        )
        var summary = initialSummary
        if !refreshed.isEmpty {
            let edits = TableLoader.edits(for: refreshed)
            if let reason = modelEditor.apply(edits) {
                summary.applyError = reason
                progress?.applyError = reason
            } else {
                // `modelEditor.apply` đã gọi `layout.commitModel` → `modelEditsChanged` → cập nhật runtime + modelVersion + reload visual.
                interaction.modelVersion += 1
            }
        }
        return summary
    }
}
