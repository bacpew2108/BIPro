import SwiftUI
import ColumnStore
import MEngine

public struct CustomColumnDialogContent: View {
    @Binding public var name: String
    @Binding public var formula: String
    public var availableColumns: [QueryColumnInfo]
    public var formulaError: String?
    public var rejectionError: String? = nil
    public var scrollable: Bool = true
    public var onCommit: () -> Void
    public var onCancel: () -> Void

    @State private var selectedColumn: String? = nil

    public init(
        name: Binding<String>,
        formula: Binding<String>,
        availableColumns: [QueryColumnInfo],
        formulaError: String?,
        rejectionError: String? = nil,
        scrollable: Bool = true,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._name = name
        self._formula = formula
        self.availableColumns = availableColumns
        self.formulaError = formulaError
        self.rejectionError = rejectionError
        self.scrollable = scrollable
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && formulaError == nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerView

            // Body
            VStack(alignment: .leading, spacing: 14) {
                // Tên cột mới
                VStack(alignment: .leading, spacing: 4) {
                    Text(bi("Tên cột mới", "New column name"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)

                    if scrollable {
                        TextField("Custom", text: $name)
                            .textFieldStyle(.plain)
                            .font(DS.Typeface.body)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: 320, minHeight: 28)
                            .background(DS.Palette.canvas)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                    } else {
                        HStack {
                            Text(name.isEmpty ? "Custom" : name)
                                .font(DS.Typeface.body)
                                .foregroundStyle(name.isEmpty ? DS.Palette.tertiaryLabel : DS.Palette.label)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: 320, minHeight: 28)
                        .background(DS.Palette.canvas)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                    }
                }

                // Split: Formula Editor (Left) & Available Columns (Right)
                HStack(alignment: .top, spacing: 16) {
                    // Left: Formula
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bi("Công thức cột tuỳ chỉnh (=):", "Custom column formula (=):"))
                                .font(DS.Typeface.labelSmall)
                                .foregroundStyle(DS.Palette.secondaryLabel)
                            Spacer()
                            Text("Power Query M")
                                .font(DS.Typeface.mono)
                                .foregroundStyle(DS.Palette.tertiaryLabel)
                        }

                        formulaEditor
                            .frame(height: 140)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(
                                formulaError != nil ? DS.Palette.danger.opacity(0.7) : DS.Palette.separator
                            ))
                    }
                    .frame(maxWidth: .infinity)

                    // Right: Available Columns
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bi("Cột có sẵn:", "Available columns:"))
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.secondaryLabel)

                        columnsList
                            .frame(width: 200, height: 140)
                            .background(DS.Palette.canvas)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))

                        Button {
                            if let col = selectedColumn {
                                insertColumn(col)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("<<")
                                    .font(DS.Typeface.labelSmall)
                                Text(bi("Chèn", "Insert"))
                                    .font(DS.Typeface.bodySmall)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(DS.Palette.canvas)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedColumn == nil)
                        .padding(.top, 2)
                    }
                }

                // Syntax validation strip
                validationStrip

                // Rejection error strip
                if let rej = rejectionError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(DS.Palette.danger)
                            .font(.system(size: 13))
                        Text(rej)
                            .font(DS.Typeface.bodySmall)
                            .foregroundStyle(DS.Palette.danger)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(DS.Palette.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                }
            }

            Spacer(minLength: 0)

            // Footer
            footerView
        }
        .padding(20)
        .frame(width: 720)
        .background(DS.Palette.canvas)
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "plus.rectangle")
                .font(.system(size: 24))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 36, height: 36)
                .background(DS.Palette.selectionSoft)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))

            VStack(alignment: .leading, spacing: 2) {
                Text(bi("Cột tuỳ chỉnh", "Custom column"))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Text(bi("Thêm cột được tính toán từ các cột khác bằng biểu thức.", "Add a column computed from other columns using an expression."))
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var formulaEditor: some View {
        if scrollable {
            TextEditor(text: $formula)
                .font(DS.Typeface.mono)
                .padding(6)
                .background(DS.Palette.canvas)
        } else {
            // Dùng Text khi scrollable == false để ImageRenderer không bị ô trống
            Text(formula.isEmpty ? "= [Cột]" : formula)
                .font(DS.Typeface.mono)
                .foregroundStyle(formula.isEmpty ? DS.Palette.tertiaryLabel : DS.Palette.label)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .background(DS.Palette.canvas)
        }
    }

    private var columnsList: some View {
        Group {
            if scrollable {
                ScrollView {
                    columnsListContent
                }
            } else {
                columnsListContent
            }
        }
    }

    private var columnsListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(availableColumns, id: \.name) { col in
                let isSelected = selectedColumn == col.name
                HStack(spacing: 6) {
                    Text(QueryEditorFormat.typeBadge(col.type))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.secondaryLabel)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.12)))

                    Text(col.name)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? DS.Palette.selectionSoft : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedColumn = col.name
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    insertColumn(col.name)
                })
            }
        }
        .padding(.vertical, 2)
    }

    private var validationStrip: some View {
        HStack(spacing: 6) {
            if let error = formulaError {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.danger)
                Text(error)
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.danger)
                    .lineLimit(2)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.success)
                Text(bi("Không phát hiện lỗi cú pháp.", "No syntax errors detected."))
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.success)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button(bi("Huỷ", "Cancel"), action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

            Button("OK", action: onCommit)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid)
                .opacity(isValid ? 1.0 : 0.4)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
    }

    private func insertColumn(_ colName: String) {
        let snippet = "[\(colName)]"
        if formula.isEmpty || formula.hasSuffix(" ") {
            formula += snippet
        } else {
            formula += " " + snippet
        }
    }
}

public struct CustomColumnDialog: View {
    public let state: QueryEditorState
    public let onCommit: (StepCommand) -> StepCommandOutcome
    public let onCancel: () -> Void
    public var scrollable: Bool = true

    @State private var name: String = "Custom"
    @State private var formula: String = ""
    @State private var rejectionError: String? = nil

    public init(
        state: QueryEditorState,
        scrollable: Bool = true,
        onCommit: @escaping (StepCommand) -> StepCommandOutcome,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.scrollable = scrollable
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    private var availableColumns: [QueryColumnInfo] {
        (state.preview?.columns ?? []).map {
            QueryColumnInfo(name: $0.name, type: $0.data.type)
        }
    }

    private var formulaError: String? {
        state.formulaError(formula)
    }

    public var body: some View {
        CustomColumnDialogContent(
            name: $name,
            formula: $formula,
            availableColumns: availableColumns,
            formulaError: formulaError,
            rejectionError: rejectionError,
            scrollable: scrollable,
            onCommit: {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedFormula = formula.trimmingCharacters(in: .whitespacesAndNewlines)
                let cmd = StepCommand.addCustomColumn(name: trimmedName, formula: trimmedFormula)
                let outcome = onCommit(cmd)
                switch outcome {
                case .applied, .needsInsertConfirmation:
                    rejectionError = nil
                case .rejected(let reason):
                    rejectionError = reason
                }
            },
            onCancel: onCancel
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .popoverElevation()
    }
}
