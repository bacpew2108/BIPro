// Wave 4B (T009): Hộp thoại Quản lý vai trò bảo mật cấp dòng (RLS — Manage Roles).
import DAXEngine
import PBIXKit
import SwiftUI

struct ManageRolesSheet: View {
    @Bindable var state: DocumentState
    let onDismiss: () -> Void

    private struct DraftRole: Identifiable, Equatable {
        let id = UUID()
        var originalName: String?
        var name: String
        var description: String
        var filters: [String: String] // tableName -> DAX filter expression
    }

    @State private var roles: [DraftRole] = []
    @State private var selectedRoleID: UUID? = nil
    @State private var selectedTable: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false

    private var userTables: [String] { state.workspace.userTables.map(\.name) }

    private var selectedRoleIndex: Int? {
        roles.firstIndex { $0.id == selectedRoleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.accent)
                Text(bi("Quản lý vai trò bảo mật (RLS)", "Manage Roles (RLS)"))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
            }

            HStack(spacing: 0) {
                // Cột 1: Danh sách vai trò
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(bi("Vai trò", "Roles")).font(DS.Typeface.bodySmall.weight(.semibold))
                        Spacer()
                        Button { addRole() } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain)
                            .help(bi("Tạo vai trò mới", "New role"))
                    }
                    List(selection: $selectedRoleID) {
                        ForEach(roles) { role in
                            HStack {
                                Text(role.name.isEmpty ? bi("(Chưa đặt tên)", "(Untitled)") : role.name)
                                    .font(DS.Typeface.bodySmall)
                                Spacer()
                                let count = role.filters.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                                if count > 0 {
                                    Text("\(count)")
                                        .font(DS.Typeface.labelSmall)
                                        .foregroundStyle(DS.Palette.accent)
                                }
                            }
                            .tag(role.id)
                        }
                    }
                    .listStyle(.bordered)

                    if let idx = selectedRoleIndex {
                        Button(role: .destructive) {
                            let removedID = roles[idx].id
                            roles.remove(at: idx)
                            if selectedRoleID == removedID { selectedRoleID = roles.first?.id }
                        } label: {
                            Label(bi("Xoá vai trò", "Delete role"), systemImage: "trash")
                                .font(DS.Typeface.labelSmall)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Palette.danger)
                    }
                }
                .frame(width: 175)
                .padding(.trailing, 10)

                Divider()

                // Cột 2: Danh sách bảng
                VStack(alignment: .leading, spacing: 6) {
                    Text(bi("Bảng", "Tables")).font(DS.Typeface.bodySmall.weight(.semibold))
                    List(userTables, id: \.self, selection: $selectedTable) { tbl in
                        HStack {
                            Text(tbl).font(DS.Typeface.bodySmall)
                            Spacer()
                            if let idx = selectedRoleIndex,
                               let expr = roles[idx].filters[tbl],
                               !expr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Palette.accent)
                            }
                        }
                        .tag(tbl)
                    }
                    .listStyle(.bordered)
                }
                .frame(width: 175)
                .padding(.horizontal, 10)

                Divider()

                // Cột 3: Chi tiết vai trò + biểu thức lọc DAX cho bảng đang chọn
                VStack(alignment: .leading, spacing: 8) {
                    if let idx = selectedRoleIndex {
                        Text(bi("Tên vai trò:", "Role name:"))
                            .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.secondaryLabel)
                        TextField(bi("Ví dụ: KhuVuc_MienBac", "e.g. NorthRegion"), text: $roles[idx].name)
                            .textFieldStyle(.roundedBorder)

                        Text(bi("Biểu thức lọc DAX cho bảng «\(selectedTable)»:",
                                "Table filter DAX expression for «\(selectedTable)»:"))
                            .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.secondaryLabel)

                        TextEditor(text: Binding(
                            get: { roles[idx].filters[selectedTable] ?? "" },
                            set: { roles[idx].filters[selectedTable] = $0 }
                        ))
                        .font(DS.Typeface.mono)
                        .padding(6)
                        .background(DS.Palette.chrome)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))

                        Text(bi("Ví dụ: \(selectedTable)[Column] = \"Value\" (để trống = không lọc bảng này).",
                                "Example: \(selectedTable)[Column] = \"Value\" (leave empty for no filter on this table)."))
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.tertiaryLabel)
                    } else {
                        ContentUnavailableView(
                            bi("Chưa chọn vai trò", "No role selected"),
                            systemImage: "person.badge.shield.checkmark",
                            description: Text(bi("Bấm dấu + để tạo vai trò bảo mật cấp dòng mới.", "Click + to create a new row-level security role."))
                        )
                    }
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 310)

            if let err = errorMessage {
                Text(err)
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.danger)
            }

            HStack {
                Spacer()
                Button(bi("Huỷ", "Cancel")) { onDismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(bi("Lưu vai trò", "Save Roles")) {
                    Task { await saveAll() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 720)
        .background(DS.Palette.canvas)
        .onAppear {
            let existing = state.workspace.metadata?.roleDefinitions ?? []
            roles = existing.map { r in
                DraftRole(
                    originalName: r.name,
                    name: r.name,
                    description: r.description ?? "",
                    filters: Dictionary(uniqueKeysWithValues: r.tablePermissions.map { ($0.tableName, $0.filterExpression) })
                )
            }
            selectedRoleID = roles.first?.id
            selectedTable = userTables.first ?? ""
        }
    }

    private func addRole() {
        var idx = roles.count + 1
        var candidate = "Role \(idx)"
        while roles.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            idx += 1
            candidate = "Role \(idx)"
        }
        let created = DraftRole(originalName: nil, name: candidate, description: "", filters: [:])
        roles.append(created)
        selectedRoleID = created.id
    }

    private func saveAll() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        // Kiểm hợp lệ tên trùng và cú pháp DAX của từng biểu thức lọc
        var seenNames = Set<String>()
        for role in roles {
            let trimmed = role.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = bi("Tên vai trò không được để trống.", "Role name cannot be empty.")
                return
            }
            guard seenNames.insert(trimmed.lowercased()).inserted else {
                errorMessage = bi("Tên vai trò bị trùng: \(trimmed).", "Duplicate role name: \(trimmed).")
                return
            }
            for (tbl, expr) in role.filters {
                let cleanExpr = expr.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanExpr.isEmpty else { continue }
                let probe = "COUNTROWS(FILTER(\(DAXEngine.formatTableIdentifier(tbl)), \(cleanExpr)))"
                let ws = state.workspace
                let check = await Task.detached(priority: .userInitiated) { () -> MeasureCheck in
                    guard let engine = try? ws.daxEngine() else {
                        return .failed(MeasureProblem(message: ws.modelError ?? "Không có engine DAX"))
                    }
                    return await MeasureTyping.check(probe, using: engine)
                }.value
                if case .failed(let problem) = check {
                    errorMessage = bi("Lỗi DAX ở vai trò «\(trimmed)», bảng «\(tbl)»: \(problem.message)",
                                      "DAX error in role «\(trimmed)», table «\(tbl)»: \(problem.message)")
                    return
                }
            }
        }

        let definitions = roles.map { r -> (previous: String?, role: ModelMetadata.RoleDefinition) in
            let perms = r.filters
                .sorted { $0.key < $1.key }
                .compactMap { tbl, expr -> ModelMetadata.TablePermission? in
                    let clean = expr.trimmingCharacters(in: .whitespacesAndNewlines)
                    return clean.isEmpty ? nil : ModelMetadata.TablePermission(tableName: tbl, filterExpression: clean)
                }
            return (
                previous: r.originalName,
                role: ModelMetadata.RoleDefinition(
                    name: r.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: r.description.isEmpty ? nil : r.description,
                    modelPermission: 2,
                    tablePermissions: perms
                )
            )
        }

        if let reason = state.saveRLSRoles(definitions) {
            errorMessage = reason
            return
        }
        onDismiss()
    }
}
