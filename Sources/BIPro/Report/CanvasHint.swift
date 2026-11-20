// T038 (bấm thử app): gợi ý giữa khung trang khi mô hình đã có bảng mà trang chưa có visual, như "Build visuals with your data /
// Select or drag fields from the Data pane onto the report canvas." của Desktop 2.159 (VM-F11a, ảnh a6). Chỉ là chữ, không có nút,
// không chặn thao tác trên khung.

import SwiftUI

struct CanvasHint: View {
    static func isShown(for state: DocumentState) -> Bool {
        _ = state.modelVersion   // `workspace` không phát thay đổi; đọc bộ đếm để view vẽ lại khi nạp hay hoàn tác bảng
        guard !state.workspace.userTables.isEmpty, let page = state.page else { return false }
        return page.visuals.isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Palette.accent)
            Text(tr(.canvasHintTitle)).font(.system(size: 22, weight: .semibold)).foregroundStyle(DS.Palette.label)
            Text(tr(.canvasHintSubtitle))
                .font(.system(size: 15))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(24)
        .allowsHitTesting(false)
    }
}
