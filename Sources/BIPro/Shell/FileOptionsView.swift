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
            Text(tr(.fileOptionsTitle)).font(DS.Typeface.headlineMedium).foregroundStyle(DS.Palette.label)
            section(bi("Trí tuệ thời gian", "Time intelligence")) {
                checkboxRow(title: tr(.autoDateTimeLabel), isOn: $options.autoDateTime, disabled: autoDateTimeBlocker != nil)
                    .help(autoDateTimeBlocker ?? bi("Mỗi cột ngày có một bảng ngày ẩn và phân cấp Năm, Quý, Tháng, Ngày.",
                                                    "Creates a hidden date table and Year/Quarter/Month/Day hierarchy for each date column."))
                if let autoDateTimeBlocker { note(autoDateTimeBlocker) }
            }
            section(bi("Quan hệ", "Relationships")) {
                checkboxRow(title: tr(.autoDetectRelLabel), isOn: $options.autodetectRelationships, disabled: false)
            }
            if let message { note(message, color: DS.Palette.danger) }
            HStack {
                Spacer()
                Button(tr(.ok)) {
                    if let refusal = onCommit(options) { message = refusal } else { onCancel() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Button(tr(.cancel), role: .cancel) { onCancel() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(DS.Palette.canvas)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(DS.Typeface.headlineSmall).foregroundStyle(DS.Palette.label)
            content()
        }
    }

    private func checkboxRow(title: String, isOn: Binding<Bool>, disabled: Bool) -> some View {
        Button {
            if !disabled { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 8) {
                CheckboxMark(isOn: isOn.wrappedValue)
                Text(title)
                    .font(DS.Typeface.body)
                    .foregroundStyle(disabled ? DS.Palette.tertiaryLabel : DS.Palette.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private func note(_ text: String, color: Color = DS.Palette.secondaryLabel) -> some View {
        Text(text).font(DS.Typeface.bodySmall).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}
