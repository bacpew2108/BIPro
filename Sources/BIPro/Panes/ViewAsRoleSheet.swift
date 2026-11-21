// Wave 4B (T009): Hộp thoại "Xem dưới vai trò" (View as Roles) áp lọc RLS trực tiếp trên phiên hiện tại.
import PBIXKit
import SwiftUI

struct ViewAsRoleSheet: View {
    @Bindable var state: DocumentState
    let onDismiss: () -> Void

    @State private var selected: Set<String> = []

    private var availableRoles: [ModelMetadata.RoleDefinition] {
        state.workspace.metadata?.roleDefinitions ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.warning)
                Text(bi("Xem báo cáo dưới vai trò (RLS)", "View as Roles (RLS)"))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
            }

            if availableRoles.isEmpty {
                ContentUnavailableView(
                    bi("Chưa có vai trò bảo mật nào", "No security roles defined"),
                    systemImage: "person.badge.shield.checkmark",
                    description: Text(bi("Hãy tạo vai trò ở mục \"Quản lý vai trò\" trước khi mô phỏng xem.",
                                         "Create a role in \"Manage roles\" first before previewing."))
                )
                .frame(height: 150)
            } else {
                Text(bi("Chọn một hoặc nhiều vai trò để kiểm chứng dữ liệu hiển thị (không làm thay đổi tệp):",
                        "Select one or more roles to preview filtered data (does not modify the file):"))
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(availableRoles, id: \.name) { role in
                            let isOn = selected.contains(role.name)
                            Button {
                                if isOn { selected.remove(role.name) } else { selected.insert(role.name) }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    CheckboxMark(isOn: isOn)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(role.name)
                                            .font(DS.Typeface.bodySmall.weight(.medium))
                                            .foregroundStyle(DS.Palette.label)
                                        if role.tablePermissions.isEmpty {
                                            Text(bi("Không có quy tắc lọc bảng", "No table filter rules"))
                                                .font(DS.Typeface.labelSmall)
                                                .foregroundStyle(DS.Palette.tertiaryLabel)
                                        } else {
                                            Text(role.tablePermissions.map { "\($0.tableName): \($0.filterExpression)" }.joined(separator: " · "))
                                                .font(DS.Typeface.mono)
                                                .foregroundStyle(DS.Palette.secondaryLabel)
                                                .lineLimit(2)
                                        }
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
                .frame(maxHeight: 220)
            }

            HStack {
                if !state.interaction.activeRLSRoles.isEmpty {
                    Button(bi("Dừng xem dưới vai trò", "Stop viewing")) {
                        state.setActiveRLSRoles([])
                        onDismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button(bi("Huỷ", "Cancel")) { onDismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(bi("Áp dụng", "Apply")) {
                    state.setActiveRLSRoles(selected)
                    onDismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(availableRoles.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(DS.Palette.canvas)
        .onAppear {
            selected = state.interaction.activeRLSRoles
        }
    }
}
