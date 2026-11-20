import SwiftUI
import ColumnStore
import MEngine

public struct GroupByDialogContent: View {
    @Binding public var model: GroupByDialogModel
    public var errorMessage: String? = nil
    public var scrollable: Bool = true
    public var onCommit: () -> Void
    public var onCancel: () -> Void

    public init(
        model: Binding<GroupByDialogModel>,
        errorMessage: String? = nil,
        scrollable: Bool = true,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._model = model
        self.errorMessage = errorMessage
        self.scrollable = scrollable
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerView

            // Mode Selector: Cơ bản / Nâng cao
            SegmentedPill(
                selection: $model.mode,
                options: [
                    .init(value: .basic, title: "Cơ bản"),
                    .init(value: .advanced, title: "Nâng cao")
                ]
            )

            // Content
            if scrollable {
                ScrollView {
                    formContent
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: 380)
            } else {
                formContent
            }

            // Error Message (from rejection)
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(DS.Palette.danger)
                        .font(.system(size: 13))
                    Text(err)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.danger)
                        .lineLimit(2)
                }
                .padding(8)
                .background(DS.Palette.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
            }

            Spacer(minLength: 0)

            // Footer
            footerView
        }
        .padding(20)
        .frame(width: 600)
        .background(DS.Palette.canvas)
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 24))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 36, height: 36)
                .background(DS.Palette.selectionSoft)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))

            VStack(alignment: .leading, spacing: 2) {
                Text("Nhóm theo")
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Text("Chọn cột để nhóm các dòng và phép tính tổng hợp trên các cột khác.")
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var formContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.mode {
            case .basic:
                basicSection
            case .advanced:
                advancedSection
            }
        }
    }

    // MARK: - Basic Mode

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cột nhóm")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                if scrollable {
                    Menu {
                        ForEach(model.allColumns, id: \.name) { col in
                            Button(col.name) {
                                model.basicKey = col.name
                            }
                        }
                    } label: {
                        basicKeyDropdownLabel
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    basicKeyDropdownLabel
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Phép tổng hợp")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                HStack(spacing: 8) {
                    // Tên cột mới
                    VStack(alignment: .leading, spacing: 2) {
                        if scrollable {
                            TextField("Tên cột mới", text: $model.basicNewColumnName)
                                .textFieldStyle(.plain)
                                .font(DS.Typeface.body)
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .background(DS.Palette.canvas)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(
                                    isBasicNameClashing ? DS.Palette.danger : DS.Palette.separator
                                ))
                        } else {
                            HStack {
                                Text(model.basicNewColumnName.isEmpty ? "Tên cột mới" : model.basicNewColumnName)
                                    .font(DS.Typeface.body)
                                    .foregroundStyle(model.basicNewColumnName.isEmpty ? DS.Palette.tertiaryLabel : DS.Palette.label)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(DS.Palette.canvas)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(
                                isBasicNameClashing ? DS.Palette.danger : DS.Palette.separator
                            ))
                        }
                    }
                    .frame(width: 140)

                    // Phép tính
                    if scrollable {
                        Menu {
                            ForEach([
                                GroupOperation.countRows,
                                GroupOperation.countDistinctRows,
                                GroupOperation.sum,
                                GroupOperation.average,
                                GroupOperation.median,
                                GroupOperation.min,
                                GroupOperation.max
                            ], id: \.self) { op in
                                Button(op.title) {
                                    model.basicOperation = op
                                    if op.needsColumn {
                                        let valid = model.validColumns(for: op)
                                        if model.basicColumn == nil || !valid.contains(where: { $0.name == model.basicColumn }) {
                                            model.basicColumn = valid.first?.name
                                        }
                                    } else {
                                        model.basicColumn = nil
                                    }
                                }
                            }
                        } label: {
                            basicOperationDropdownLabel
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 170)
                    } else {
                        basicOperationDropdownLabel
                            .frame(width: 170)
                    }

                    // Cột tính (nếu cần)
                    if model.basicOperation.needsColumn {
                        let validCols = model.validColumns(for: model.basicOperation)
                        if scrollable {
                            Menu {
                                ForEach(validCols, id: \.name) { col in
                                    Button(col.name) {
                                        model.basicColumn = col.name
                                    }
                                }
                            } label: {
                                basicColumnDropdownLabel
                            }
                            .menuStyle(.borderlessButton)
                        } else {
                            basicColumnDropdownLabel
                        }
                    }
                }

                if isBasicNameClashing {
                    Text("Tên cột mới không được trùng với cột nhóm.")
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.danger)
                }
            }
        }
    }

    private var basicKeyDropdownLabel: some View {
        HStack {
            Text(model.basicKey.isEmpty ? "Chọn cột" : model.basicKey)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(DS.Palette.canvas)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private var basicOperationDropdownLabel: some View {
        HStack {
            Text(model.basicOperation.title)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DS.Palette.canvas)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private var basicColumnDropdownLabel: some View {
        HStack {
            Text(model.basicColumn ?? "Chọn cột")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DS.Palette.canvas)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private var isBasicNameClashing: Bool {
        let trimmed = model.basicNewColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == model.basicKey
    }

    // MARK: - Advanced Mode

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Danh sách nhóm
            VStack(alignment: .leading, spacing: 6) {
                Text("Nhóm theo")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                ForEach(model.keys.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        if scrollable {
                            Menu {
                                ForEach(model.allColumns, id: \.name) { col in
                                    Button(col.name) {
                                        model.keys[idx] = col.name
                                    }
                                }
                            } label: {
                                advancedKeyDropdownLabel(idx: idx)
                            }
                            .menuStyle(.borderlessButton)
                        } else {
                            advancedKeyDropdownLabel(idx: idx)
                        }

                        Button {
                            model.removeKey(at: idx)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(model.keys.count > 1 ? DS.Palette.danger : DS.Palette.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.keys.count <= 1)
                    }
                }

                Button {
                    let unused = model.allColumns.first(where: { !model.keys.contains($0.name) })?.name ?? model.allColumns.first?.name ?? ""
                    model.addKey(unused)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Thêm nhóm")
                            .font(DS.Typeface.bodySmall)
                    }
                    .foregroundStyle(DS.Palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            // Danh sách phép tổng hợp
            VStack(alignment: .leading, spacing: 6) {
                Text("Phép tổng hợp")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                ForEach(model.aggregates.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        // Tên cột mới
                        if scrollable {
                            TextField("Tên cột", text: $model.aggregates[idx].name)
                                .textFieldStyle(.plain)
                                .font(DS.Typeface.body)
                                .padding(.horizontal, 8)
                                .frame(width: 140, height: 28)
                                .background(DS.Palette.canvas)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                        } else {
                            HStack {
                                Text(model.aggregates[idx].name.isEmpty ? "Tên cột" : model.aggregates[idx].name)
                                    .font(DS.Typeface.body)
                                    .foregroundStyle(model.aggregates[idx].name.isEmpty ? DS.Palette.tertiaryLabel : DS.Palette.label)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .frame(width: 140, height: 28)
                            .background(DS.Palette.canvas)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                        }

                        // Phép tính
                        if scrollable {
                            Menu {
                                ForEach([
                                    GroupOperation.countRows,
                                    GroupOperation.countDistinctRows,
                                    GroupOperation.sum,
                                    GroupOperation.average,
                                    GroupOperation.median,
                                    GroupOperation.min,
                                    GroupOperation.max
                                ], id: \.self) { op in
                                    Button(op.title) {
                                        model.aggregates[idx].operation = op
                                        if op.needsColumn {
                                            let valid = model.validColumns(for: op)
                                            if model.aggregates[idx].column == nil || !valid.contains(where: { $0.name == model.aggregates[idx].column }) {
                                                model.aggregates[idx].column = valid.first?.name
                                            }
                                        } else {
                                            model.aggregates[idx].column = nil
                                        }
                                    }
                                }
                            } label: {
                                advancedOperationDropdownLabel(idx: idx)
                            }
                            .menuStyle(.borderlessButton)
                        } else {
                            advancedOperationDropdownLabel(idx: idx)
                        }

                        // Cột tính
                        if model.aggregates[idx].operation.needsColumn {
                            let validCols = model.validColumns(for: model.aggregates[idx].operation)
                            if scrollable {
                                Menu {
                                    ForEach(validCols, id: \.name) { col in
                                        Button(col.name) {
                                            model.aggregates[idx].column = col.name
                                        }
                                    }
                                } label: {
                                    advancedColumnDropdownLabel(idx: idx)
                                }
                                .menuStyle(.borderlessButton)
                            } else {
                                advancedColumnDropdownLabel(idx: idx)
                            }
                        } else {
                            Spacer()
                        }

                        Button {
                            model.removeAggregate(at: idx)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(model.aggregates.count > 1 ? DS.Palette.danger : DS.Palette.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.aggregates.count <= 1)
                    }
                }

                Button {
                    let baseName = "NewCol"
                    var n = model.aggregates.count + 1
                    var name = "\(baseName)\(n)"
                    while model.aggregates.contains(where: { $0.name == name }) || model.keys.contains(name) {
                        n += 1
                        name = "\(baseName)\(n)"
                    }
                    model.addAggregate(name: name, operation: .countRows, column: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Thêm phép tổng hợp")
                            .font(DS.Typeface.bodySmall)
                    }
                    .foregroundStyle(DS.Palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private func advancedKeyDropdownLabel(idx: Int) -> some View {
        HStack {
            Text(model.keys[idx])
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DS.Palette.canvas)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private func advancedOperationDropdownLabel(idx: Int) -> some View {
        HStack {
            Text(model.aggregates[idx].operation.title)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .frame(width: 170, height: 28)
        .background(DS.Palette.canvas)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private func advancedColumnDropdownLabel(idx: Int) -> some View {
        HStack {
            Text(model.aggregates[idx].column ?? "Chọn cột")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DS.Palette.canvas)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Huỷ", action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

            Button("OK", action: onCommit)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.isValid)
                .opacity(model.isValid ? 1.0 : 0.4)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
    }
}

public struct GroupByDialog: View {
    public let state: QueryEditorState
    public let initialSelectedColumns: [String]
    public let onCommit: (StepCommand) -> StepCommandOutcome
    public let onCancel: () -> Void
    public var scrollable: Bool = true

    @State private var model: GroupByDialogModel
    @State private var rejectionError: String? = nil

    public init(
        state: QueryEditorState,
        initialSelectedColumns: [String] = [],
        scrollable: Bool = true,
        onCommit: @escaping (StepCommand) -> StepCommandOutcome,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.initialSelectedColumns = initialSelectedColumns
        self.scrollable = scrollable
        self.onCommit = onCommit
        self.onCancel = onCancel

        let cols = (state.preview?.columns ?? []).map {
            QueryColumnInfo(name: $0.name, type: $0.data.type)
        }
        self._model = State(initialValue: GroupByDialogModel(
            allColumns: cols,
            initialSelectedColumns: initialSelectedColumns
        ))
    }

    public var body: some View {
        GroupByDialogContent(
            model: $model,
            errorMessage: rejectionError,
            scrollable: scrollable,
            onCommit: {
                if let cmd = model.command() {
                    let outcome = onCommit(cmd)
                    switch outcome {
                    case .applied, .needsInsertConfirmation:
                        rejectionError = nil
                    case .rejected(let reason):
                        rejectionError = reason
                    }
                }
            },
            onCancel: onCancel
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .popoverElevation()
    }
}
