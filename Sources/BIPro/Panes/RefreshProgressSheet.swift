// Wave 3C (T019): Hộp tiến trình Làm mới dữ liệu (One-Click Refresh — ⇧⌘R).
import SwiftUI

struct RefreshProgressSheet: View {
    @Bindable var progress: RefreshProgressState
    let onCancel: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: progress.isRunning ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(progress.applyError != nil ? DS.Palette.danger : DS.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Làm mới dữ liệu", "Refresh Data"))
                        .font(DS.Typeface.headlineMedium)
                        .foregroundStyle(DS.Palette.label)
                    Text(progress.isRunning
                         ? bi("Đang đọc lại dữ liệu từ nguồn Power Query…", "Reloading tables from Power Query sources…")
                         : bi("Hoàn tất làm mới (\(progress.completedCount)/\(progress.items.count) bảng).",
                              "Refresh complete (\(progress.completedCount)/\(progress.items.count) tables)."))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                Spacer()
            }

            ProgressView(value: progress.progressFraction)
                .progressViewStyle(.linear)

            if let err = progress.applyError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.danger)
                    Text(err)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.danger)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.danger.opacity(0.08)))
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(progress.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            statusIcon(for: item.status)
                                .frame(width: 18, alignment: .center)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.tableName)
                                    .font(DS.Typeface.bodySmall.weight(.medium))
                                    .foregroundStyle(DS.Palette.label)
                                Text(statusDetail(for: item.status))
                                    .font(DS.Typeface.labelSmall)
                                    .foregroundStyle(statusColor(for: item.status))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.chrome))
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 300)

            HStack {
                Spacer()
                if progress.isRunning {
                    Button(bi("Huỷ", "Cancel")) { onCancel() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button(bi("Đóng", "Close")) { onClose() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(18)
        .frame(width: 480)
        .background(DS.Palette.canvas)
    }

    @ViewBuilder
    private func statusIcon(for status: TableRefreshStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(DS.Palette.tertiaryLabel)
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.success)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(DS.Palette.secondaryLabel)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(DS.Palette.danger)
        }
    }

    private func statusDetail(for status: TableRefreshStatus) -> String {
        switch status {
        case .pending:
            return bi("Đang chờ…", "Pending…")
        case .running:
            return bi("Đang tải từ nguồn…", "Loading from source…")
        case .succeeded(let rows, let changed):
            return changed
                ? bi("Đã cập nhật (\(rows) dòng)", "Updated (\(rows) rows)")
                : bi("Không thay đổi (\(rows) dòng)", "Up to date (\(rows) rows)")
        case .skipped(let reason):
            return bi("Bỏ qua: \(reason)", "Skipped: \(reason)")
        case .failed(let reason):
            return bi("Lỗi (giữ dữ liệu cũ): \(reason)", "Failed (kept previous data): \(reason)")
        }
    }

    private func statusColor(for status: TableRefreshStatus) -> Color {
        switch status {
        case .pending, .running, .skipped: DS.Palette.secondaryLabel
        case .succeeded: DS.Palette.success
        case .failed: DS.Palette.danger
        }
    }
}
