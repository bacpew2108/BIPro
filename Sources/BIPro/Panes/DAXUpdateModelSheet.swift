// Wave 4C (T011): Hộp xác nhận "Cập nhật mô hình" từ DAX Query View (`DEFINE MEASURE ...`).
import PBIXKit
import SwiftUI

struct DAXUpdateModelSheet: View {
    @Bindable var state: DocumentState
    let items: [DAXDefinedMeasure]
    let onDismiss: () -> Void

    @State private var selectedIDs: Set<String> = []
    @State private var errorMessage: String? = nil
    @State private var isApplying: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.measure)
                Text(bi("Cập nhật mô hình từ DAX Query", "Update Model from DAX Query"))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
            }

            if items.isEmpty {
                Text(bi("Không tìm thấy khối `DEFINE MEASURE Bảng[Tên] = ...` nào mới hoặc thay đổi so với mô hình hiện tại.",
                        "No new or modified `DEFINE MEASURE Table[Name] = ...` definitions found compared to the current model."))
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            } else {
                Text(bi("Chọn các measure muốn thêm/cập nhật vào mô hình (có thể hoàn tác ⌘Z):",
                        "Select measures to add or update in the model (undoable with ⌘Z):"))
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            let isOn = selectedIDs.contains(item.id)
                            Button {
                                if isOn { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    CheckboxMark(isOn: isOn).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(item.id)
                                                .font(DS.Typeface.bodySmall.weight(.semibold))
                                                .foregroundStyle(DS.Palette.label)
                                            Badge(
                                                text: item.kind == .create ? bi("Mới", "New") : bi("Cập nhật", "Update"),
                                                color: item.kind == .create ? DS.Palette.success : DS.Palette.accent
                                            )
                                        }
                                        Text(item.expression)
                                            .font(DS.Typeface.mono)
                                            .foregroundStyle(DS.Palette.secondaryLabel)
                                            .lineLimit(3)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.chrome))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            if let err = errorMessage {
                Text(err)
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.danger)
            }

            HStack {
                Spacer()
                Button(bi("Đóng", "Close")) { onDismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if !items.isEmpty {
                    Button(bi("Cập nhật mô hình", "Update Model")) {
                        Task { await applySelected() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedIDs.isEmpty || isApplying)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(18)
        .frame(width: 540)
        .background(DS.Palette.canvas)
        .onAppear {
            selectedIDs = Set(items.map(\.id))
        }
    }

    private func applySelected() async {
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        let chosen = items.filter { selectedIDs.contains($0.id) }
        if let err = await state.applyDAXDefinedMeasures(chosen) {
            errorMessage = err
            return
        }
        onDismiss()
    }
}
