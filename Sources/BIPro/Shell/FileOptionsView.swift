// Đợt tồn đọng sau Phase F, T033: hộp "Tuỳ chọn tệp" (Options ▸ Current File ▸ Data Load của Desktop, VM-F11 ảnh b4). Chỉ hai tuỳ chọn
// BI Pro làm theo: Auto date/time (mục Time intelligence) và tự phát hiện quan hệ (mục Relationships).

import SwiftUI

struct FileOptionsView: View {
    @State var options: FileOptions
    /// Lý do Auto date/time chưa đổi được (ô bị tắt), nil khi đổi được.
    var autoDateTimeBlocker: String?
    var onCommit: (FileOptions) -> String?
    var onCancel: () -> Void

    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tuỳ chọn tệp").font(DS.Typeface.headlineMedium)
            section("Trí tuệ thời gian") {
                Toggle("Tự động ngày/giờ", isOn: $options.autoDateTime)
                    .disabled(autoDateTimeBlocker != nil)
                    .help(autoDateTimeBlocker ?? "Mỗi cột ngày có một bảng ngày ẩn và phân cấp Năm, Quý, Tháng, Ngày.")
                if let autoDateTimeBlocker { note(autoDateTimeBlocker) }
            }
            section("Quan hệ") {
                Toggle("Tự phát hiện quan hệ mới sau khi nạp dữ liệu", isOn: $options.autodetectRelationships)
            }
            if let message { note(message, color: DS.Palette.danger) }
            HStack {
                Spacer()
                Button("OK") {
                    if let refusal = onCommit(options) { message = refusal } else { onCancel() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Button("Huỷ", role: .cancel) { onCancel() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        // Nền trắng như hộp Tạo bảng: không đặt thì sheet theo giao diện tối của hệ thống, chữ tối trên nền tối (T038).
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(DS.Typeface.headlineSmall)
            content().toggleStyle(.checkbox)
        }
    }

    private func note(_ text: String, color: Color = DS.Palette.secondaryLabel) -> some View {
        Text(text).font(DS.Typeface.bodySmall).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}
