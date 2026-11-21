// Wave 3C (T020): Hộp xác nhận Đổi tên lan truyền (Cascade Rename) — hiển thị tên mới và toàn bộ
// công thức DAX / visual PBIR sẽ được cập nhật đồng bộ.
import SwiftUI

struct RenameConfirmationSheet: View {
    @Bindable var state: DocumentState
    let initialTarget: CascadeRenameTarget
    let onDismiss: () -> Void

    @State private var newName: String = ""
    @State private var plan: CascadeRenamePlan? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.accent)
                Text(bi("Đổi tên & Cập nhật tham chiếu", "Rename & Update References"))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(bi("Đang đổi tên: \(initialTarget.oldDisplay)", "Renaming: \(initialTarget.oldDisplay)"))
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                TextField(bi("Tên mới", "New name"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typeface.body)
                    .onChange(of: newName) { _, _ in recomputePlan() }
            }

            if let plan {
                if let err = plan.validationError {
                    Text(err)
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.danger)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.totalAffectedCount == 0
                             ? bi("Không có công thức DAX hay visual nào đang tham chiếu trực tiếp.", "No DAX formulas or visuals directly reference this item.")
                             : bi("Sẽ tự động cập nhật \(plan.affectedDAXItems.count) công thức DAX và \(plan.affectedPBIRLabels.count) mục PBIR (có thể hoàn tác ⌘Z):",
                                  "Will automatically update \(plan.affectedDAXItems.count) DAX formulas and \(plan.affectedPBIRLabels.count) PBIR items (undoable with ⌘Z):"))
                            .font(DS.Typeface.bodySmall)
                            .foregroundStyle(DS.Palette.label)

                        if plan.totalAffectedCount > 0 {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(plan.affectedDAXItems, id: \.self) { item in
                                        Label(item, systemImage: "function")
                                            .font(DS.Typeface.labelSmall)
                                            .foregroundStyle(DS.Palette.measure)
                                    }
                                    ForEach(plan.affectedPBIRLabels, id: \.self) { item in
                                        Label(item, systemImage: "chart.bar.doc.horizontal")
                                            .font(DS.Typeface.labelSmall)
                                            .foregroundStyle(DS.Palette.accent)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .frame(maxHeight: 160)
                            .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.chrome))
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(bi("Huỷ", "Cancel")) { onDismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(bi("Đổi tên & Cập nhật", "Rename & Update")) {
                    if let plan, plan.validationError == nil {
                        _ = state.executeCascadeRename(plan)
                        onDismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(plan == nil || plan?.validationError != nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(DS.Palette.canvas)
        .onAppear {
            newName = initialTarget.newName
            recomputePlan()
        }
    }

    private func recomputePlan() {
        guard let model = state.workspace.metadata else { plan = nil; return }
        let target = initialTarget.withNewName(newName)
        plan = CascadeRenamePlanner.buildPlan(target: target, model: model, layout: state.layout, workspace: state.workspace)
    }
}
