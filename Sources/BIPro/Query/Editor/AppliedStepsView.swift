import SwiftUI

struct AppliedStepsView: View {
    let state: QueryEditorState
    let existingTableNames: Set<String>
    var scrollable: Bool = true

    @State private var queryNameText: String = ""
    @State private var queryNameError: String? = nil
    @State private var noticeMessage: String? = nil
    @State private var renamingStepIndex: Int? = nil
    @State private var stepRenameText: String = ""
    /// Lưới Enter Data đang sửa qua bánh răng bước Source (T028); nil khi hộp đóng.
    @State private var editingEnterData: EnterDataTable?

    private var currentQuery: QueryModel? {
        state.selectedQuery
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .hairline(.bottom)

            if let notice = noticeMessage {
                noticeStrip(message: notice)
                    .hairline(.bottom)
            }

            Group {
                if scrollable {
                    ScrollView(.vertical) {
                        contentBody
                    }
                } else {
                    contentBody
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }

            footerActions
                .hairline(.top)
        }
        .frame(width: 290)
        .background(DS.Palette.chrome)
        .sheet(isPresented: Binding(get: { editingEnterData != nil }, set: { if !$0 { editingEnterData = nil } })) {
            if let table = editingEnterData {
                EnterDataView(table: table, mode: .edit, onCommit: { edited in
                    if let reason = state.setEnterData(edited) { return reason }
                    editingEnterData = nil
                    return nil
                }, onCancel: { editingEnterData = nil })
                .preferredColorScheme(AppPreferences.shared.preferredColorScheme)
                .interactiveDismissDisabled()
            }
        }
        .onAppear {
            syncQueryName()
        }
        .onChange(of: state.selectedQueryID) { _, _ in
            syncQueryName()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.secondaryLabel)

            Text(bi("Cài đặt truy vấn", "Query Settings"))
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.label)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func noticeStrip(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.danger)

            Text(message)
                .font(DS.Typeface.labelSmall)
                .foregroundStyle(DS.Palette.danger)
                .lineLimit(2)

            Spacer()

            Button {
                noticeMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DS.Palette.danger.opacity(0.08))
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section 1: Thuộc tính
            VStack(alignment: .leading, spacing: 6) {
                Text(bi("THUỘC TÍNH", "PROPERTIES"))
                    .font(DS.Typeface.labelSmall)
                    .tracking(0.5)
                    .foregroundStyle(DS.Palette.tertiaryLabel)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bi("Tên", "Name"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)

                    if !scrollable {
                        Text(queryNameText.isEmpty ? (currentQuery?.name ?? "") : queryNameText)
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.canvas))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                    } else {
                        TextField("", text: $queryNameText, onCommit: {
                            commitQueryName()
                        })
                        .textFieldStyle(.plain)
                        .font(DS.Typeface.body)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.canvas))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                    }

                    if let err = queryNameError {
                        Text(err)
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.danger)
                            .padding(.top, 1)
                    }
                }
            }

            // Section 2: Các bước đã áp dụng
            VStack(alignment: .leading, spacing: 6) {
                Text(bi("CÁC BƯỚC ĐÃ ÁP DỤNG", "APPLIED STEPS"))
                    .font(DS.Typeface.labelSmall)
                    .tracking(0.5)
                    .foregroundStyle(DS.Palette.tertiaryLabel)

                if let query = currentQuery {
                    VStack(spacing: 2) {
                        ForEach(query.steps.indices, id: \.self) { idx in
                            stepRow(step: query.steps[idx], index: idx, lockedCount: query.lockedStepCount)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func stepRow(step: QueryStep, index: Int, lockedCount: Int) -> some View {
        let isSelected = index == state.selectedStepIndex
        let isLocked = index < lockedCount
        let error = state.stepErrors[step.name]

        return HStack(spacing: 8) {
            // Icon
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : DS.Palette.tertiaryLabel)
                    .help(bi("Bước do nguồn tạo, chưa sửa được", "Source-generated step, cannot be edited"))
            } else if scrollable, let enterData = state.enterDataSource(at: index) {
                // Enter Data (VM-F11a, ảnh a7): bánh răng bước Source mở lại hộp "Tạo bảng" (OK / Huỷ, không có ô Tên).
                Button { editingEnterData = enterData } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : DS.Palette.accent)
                }
                .buttonStyle(.plain)
                .help(bi("Sửa bảng nhập tay", "Edit entered table"))
            } else {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : DS.Palette.secondaryLabel)
            }

            // Name
            if renamingStepIndex == index && scrollable {
                TextField("", text: $stepRenameText, onCommit: {
                    commitStepRename(index: index)
                })
                .textFieldStyle(.plain)
                .font(DS.Typeface.body)
            } else {
                Text(step.name)
                    .font(isSelected ? DS.Typeface.headlineSmall : DS.Typeface.body)
                    .foregroundStyle(isSelected ? .white : DS.Palette.label)
                    .lineLimit(1)
            }

            Spacer()

            // Warning icon if step has error
            if let error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : DS.Palette.danger)
                    .help(error)
            }

            // Delete button on selected unlocked step
            if isSelected && !isLocked {
                Button {
                    if let reason = state.deleteStep(at: index) {
                        noticeMessage = reason
                    } else {
                        noticeMessage = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(bi("Xoá bước này", "Delete this step"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control)
            .fill(isSelected ? DS.Palette.accent : DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
            .strokeBorder(isSelected ? Color.clear : DS.Palette.separator))
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectStep(index)
        }
        .contextMenu {
            if !isLocked {
                Button(bi("Đổi tên…", "Rename…")) {
                    renamingStepIndex = index
                    stepRenameText = step.name
                    noticeMessage = nil
                }

                Button(bi("Xoá", "Delete")) {
                    if let reason = state.deleteStep(at: index) {
                        noticeMessage = reason
                    } else {
                        noticeMessage = nil
                    }
                }

                Button(bi("Chuyển lên", "Move up")) {
                    if let reason = state.moveStep(at: index, by: -1) {
                        noticeMessage = reason
                    } else {
                        noticeMessage = nil
                    }
                }

                Button(bi("Chuyển xuống", "Move down")) {
                    if let reason = state.moveStep(at: index, by: 1) {
                        noticeMessage = reason
                    } else {
                        noticeMessage = nil
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button {
                state.undo()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                    Text(bi("Hoàn tác", "Undo"))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!state.canUndo)
            .keyboardShortcut("z", modifiers: .command)

            Button {
                state.redo()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.forward")
                    Text(bi("Làm lại", "Redo"))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!state.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(DS.Palette.chrome)
    }

    private func syncQueryName() {
        queryNameText = currentQuery?.name ?? ""
        queryNameError = nil
    }

    private func commitQueryName() {
        guard let query = currentQuery else { return }
        let trimmed = queryNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != query.name {
            if let err = state.renameQuery(query.id, to: trimmed, existingTableNames: existingTableNames) {
                queryNameError = err
            } else {
                queryNameError = nil
            }
        }
    }

    private func commitStepRename(index: Int) {
        let trimmed = stepRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason = state.renameStep(at: index, to: trimmed) {
            noticeMessage = reason
        } else {
            noticeMessage = nil
        }
        renamingStepIndex = nil
    }
}
