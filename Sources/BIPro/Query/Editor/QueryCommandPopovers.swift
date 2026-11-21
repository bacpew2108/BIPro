import SwiftUI
import ColumnStore
import MEngine

// MARK: - Popover Parameter Sheet / View

enum PopoverCommandType {
    case keepTopRows
    case removeTopRows
    case replaceValue
    case replaceErrors
    case splitByDelimiter
    case splitByNumberOfChars
    case charCount
    case singleDelimiter
    case betweenDelimiters
    case filterEquals(distribution: [ProfileBucket], columnType: DAXType)
}

struct QueryCommandPopoverView: View {
    let command: QueryRibbonCommand
    let type: PopoverCommandType
    let selectedColumns: [String]
    let columnTypes: [String: DAXType]
    let allColumns: [String]
    let onCommit: (StepCommand) -> Void
    let onCancel: () -> Void

    // Local form states
    @State private var rowCountText: String = "10"
    @State private var replaceOldText: String = ""
    @State private var replaceNewText: String = ""
    @State private var replaceErrorText: String = "0"
    @State private var delimiterText: String = " "
    @State private var endDelimiterText: String = ")"
    @State private var charCountText: String = "3"
    @State private var splitCountText: String = "2"
    @State private var selectedFilterLabels: Set<String> = []

    init(
        command: QueryRibbonCommand,
        type: PopoverCommandType,
        selectedColumns: [String],
        columnTypes: [String: DAXType],
        allColumns: [String],
        onCommit: @escaping (StepCommand) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.command = command
        self.type = type
        self.selectedColumns = selectedColumns
        self.columnTypes = columnTypes
        self.allColumns = allColumns
        self.onCommit = onCommit
        self.onCancel = onCancel

        if case .filterEquals(let distribution, _) = type {
            _selectedFilterLabels = State(initialValue: Set(distribution.prefix(20).map(\.label)))
        }
    }

    private var currentContext: QueryRibbonContext {
        var ctx = QueryRibbonContext(
            selectedColumns: selectedColumns,
            columnTypes: columnTypes,
            allColumns: allColumns
        )
        switch type {
        case .keepTopRows, .removeTopRows:
            ctx.rowCount = Int(rowCountText)
        case .replaceValue:
            ctx.replaceOld = replaceOldText
            ctx.replaceNew = replaceNewText
        case .replaceErrors:
            ctx.replaceErrorText = replaceErrorText
        case .splitByDelimiter:
            ctx.delimiter = delimiterText
            ctx.splitColumnCount = Int(splitCountText)
        case .splitByNumberOfChars:
            ctx.charCount = Int(charCountText)
            ctx.splitColumnCount = Int(splitCountText)
        case .charCount:
            ctx.charCount = Int(charCountText)
        case .singleDelimiter:
            ctx.delimiter = delimiterText
        case .betweenDelimiters:
            ctx.delimiter = delimiterText
            ctx.endDelimiter = endDelimiterText
        case .filterEquals(_, let colType):
            let literals = buildFilterLiterals(colType: colType)
            ctx.filterValues = literals.isEmpty ? nil : literals
        }
        return ctx
    }

    private var stepCommand: StepCommand? {
        command.stepCommand(context: currentContext)
    }

    private func buildFilterLiterals(colType: DAXType) -> [MLiteral] {
        var literals: [MLiteral] = []
        for label in selectedFilterLabels {
            if colType == .integer || colType == .double {
                if let d = Double(label) {
                    literals.append(.number(d))
                }
            } else {
                literals.append(.text(label))
            }
        }
        return literals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(command.title)
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.label)

            contentFields

            HStack {
                Spacer()
                Button("Huỷ") {
                    onCancel()
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    if let cmd = stepCommand {
                        onCommit(cmd)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(stepCommand == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: popoverWidth)
        .background(DS.Palette.canvas)
        .popoverElevation()
    }

    private var popoverWidth: CGFloat {
        switch type {
        case .filterEquals: return 280
        default: return 240
        }
    }

    @ViewBuilder
    private var contentFields: some View {
        switch type {
        case .keepTopRows, .removeTopRows:
            VStack(alignment: .leading, spacing: 4) {
                Text("Số dòng:")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                TextField("Ví dụ: 10", text: $rowCountText)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typeface.body)
            }

        case .replaceValue:
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tìm:")
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField("", text: $replaceOldText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thay bằng:")
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField("", text: $replaceNewText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
            }

        case .replaceErrors:
            VStack(alignment: .leading, spacing: 4) {
                Text(bi("Giá trị thay thế lỗi (để trống = null):", "Value to replace errors (empty = null):"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                TextField("0", text: $replaceErrorText)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typeface.body)
            }

        case .splitByDelimiter:
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Dấu phân cách:", "Delimiter:"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField(bi("Dấu phân cách", "Delimiter"), text: $delimiterText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Số cột (tối thiểu 2):", "Number of columns (min 2):"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField("2", text: $splitCountText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
            }

        case .splitByNumberOfChars:
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Số ký tự mỗi phần:", "Characters per split:"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField("3", text: $charCountText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Số cột (tối thiểu 2):", "Number of columns (min 2):"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField("2", text: $splitCountText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
            }

        case .charCount:
            VStack(alignment: .leading, spacing: 4) {
                Text(bi("Số ký tự:", "Count:"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                TextField("3", text: $charCountText)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typeface.body)
            }

        case .singleDelimiter:
            VStack(alignment: .leading, spacing: 4) {
                Text(bi("Dấu phân cách:", "Delimiter:"))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                TextField("-", text: $delimiterText)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typeface.body)
            }

        case .betweenDelimiters:
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Dấu phân cách đầu:", "Start delimiter:"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField("(", text: $delimiterText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Dấu phân cách cuối:", "End delimiter:"))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    TextField(")", text: $endDelimiterText)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typeface.body)
                }
            }

        case .filterEquals(let distribution, _):
            VStack(alignment: .leading, spacing: 6) {
                Text("Chọn giá trị để giữ lại:")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                let items = Array(distribution.prefix(20))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items.indices, id: \.self) { i in
                            let bucket = items[i]
                            let isChecked = selectedFilterLabels.contains(bucket.label)
                            Button {
                                if isChecked {
                                    selectedFilterLabels.remove(bucket.label)
                                } else {
                                    selectedFilterLabels.insert(bucket.label)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    CheckboxMark(isOn: isChecked)
                                    Text(bucket.label.isEmpty ? "(Trống)" : bucket.label)
                                        .font(DS.Typeface.bodySmall)
                                        .foregroundStyle(DS.Palette.label)
                                    Spacer()
                                    Text("\(bucket.count)")
                                        .font(DS.Typeface.mono)
                                        .foregroundStyle(DS.Palette.tertiaryLabel)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator))

                HStack {
                    Button("Chọn tất cả") {
                        selectedFilterLabels = Set(items.map(\.label))
                    }
                    .buttonStyle(.plain)
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.accent)

                    Spacer()

                    Button("Bỏ chọn") {
                        selectedFilterLabels.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
        }
    }
}
