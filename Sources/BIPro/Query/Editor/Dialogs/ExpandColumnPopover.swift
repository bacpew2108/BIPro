import SwiftUI
import ColumnStore
import MEngine

public struct ExpandColumnContent: View {
    @Binding public var model: ExpandColumnModel
    public var columnTypes: [String: DAXType] = [:]
    public var scrollable: Bool = true
    public var onCommit: () -> Void
    public var onCancel: () -> Void

    public init(
        model: Binding<ExpandColumnModel>,
        columnTypes: [String: DAXType] = [:],
        scrollable: Bool = true,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._model = model
        self.columnTypes = columnTypes
        self.scrollable = scrollable
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right.square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)

                Text("Mở rộng cột")
                    .font(DS.Typeface.headlineSmall)
                    .foregroundStyle(DS.Palette.label)

                Spacer()
            }

            // "Chọn tất cả cột"
            Button {
                if model.isAllSelected {
                    model.deselectAll()
                } else {
                    model.selectAll()
                }
            } label: {
                HStack(spacing: 8) {
                    CheckboxMark(isOn: model.isAllSelected)
                    Text("(Chọn tất cả cột)")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                }
            }
            .buttonStyle(.plain)

            // Columns list
            Group {
                if scrollable {
                    ScrollView {
                        columnsList
                    }
                    .frame(maxHeight: 180)
                } else {
                    columnsList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(DS.Palette.canvas)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))

            // Use prefix checkbox
            Button {
                model.usePrefix.toggle()
            } label: {
                HStack(spacing: 8) {
                    CheckboxMark(isOn: model.usePrefix)
                    Text("Dùng tên cột gốc làm tiền tố")
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.label)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // Footer
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
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 320)
        .background(DS.Palette.canvas)
    }

    private var columnsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.allColumns, id: \.self) { col in
                let isChecked = model.selectedColumns.contains(col)
                Button {
                    model.toggle(col)
                } label: {
                    HStack(spacing: 8) {
                        CheckboxMark(isOn: isChecked)

                        if let type = columnTypes[col] {
                            Text(QueryEditorFormat.typeBadge(type))
                                .font(DS.Typeface.labelSmall)
                                .foregroundStyle(isChecked ? DS.Palette.accent : DS.Palette.secondaryLabel)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.12)))
                        }

                        Text(col)
                            .font(DS.Typeface.bodySmall)
                            .foregroundStyle(DS.Palette.label)
                            .lineLimit(1)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
    }
}

public struct ExpandColumnPopover: View {
    public let sourceColumn: String
    public let columns: [QueryColumnInfo]
    public let onCommit: (StepCommand) -> Void
    public let onCancel: () -> Void
    public var scrollable: Bool = true

    @State private var model: ExpandColumnModel

    public init(
        sourceColumn: String,
        columns: [QueryColumnInfo],
        kind: ExpandColumnModel.Kind = .table,
        scrollable: Bool = true,
        onCommit: @escaping (StepCommand) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceColumn = sourceColumn
        self.columns = columns
        self.scrollable = scrollable
        self.onCommit = onCommit
        self.onCancel = onCancel

        let names = columns.map(\.name)
        var model = ExpandColumnModel(sourceColumn: sourceColumn, allColumns: names)
        model.kind = kind
        self._model = State(initialValue: model)
    }

    private var typeMap: [String: DAXType] {
        Dictionary(uniqueKeysWithValues: columns.map { ($0.name, $0.type) })
    }

    public var body: some View {
        ExpandColumnContent(
            model: $model,
            columnTypes: typeMap,
            scrollable: scrollable,
            onCommit: {
                if let cmd = model.command() {
                    onCommit(cmd)
                }
            },
            onCancel: onCancel
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        .popoverElevation()
    }
}
