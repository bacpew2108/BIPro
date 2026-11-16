import SwiftUI
import ColumnStore
import MEngine

extension JoinChoice {
    public var localizedTitle: String {
        switch self {
        case .leftOuter: return "Ngoài trái (tất cả từ bảng đầu, khớp từ bảng thứ hai)"
        case .rightOuter: return "Ngoài phải (tất cả từ bảng thứ hai, khớp từ bảng đầu)"
        case .fullOuter: return "Ngoài đầy đủ (tất cả hàng của cả hai)"
        case .inner: return "Trong (chỉ hàng khớp)"
        case .leftAnti: return "Chống trái (chỉ hàng của bảng đầu không khớp)"
        case .rightAnti: return "Chống phải (chỉ hàng của bảng thứ hai không khớp)"
        }
    }
}

public struct MergeDialogContent: View {
    @Binding public var model: MergeDialogModel
    public var candidates: [QueryModel]
    public var primaryPreview: TableData?
    public var secondaryPreview: TableData?
    public var isSecondaryLoading: Bool = false
    public var secondaryErrorMessage: String? = nil
    public var rejectionError: String? = nil
    public var scrollable: Bool = true
    public var onSelectSecondary: (QueryModel) -> Void
    public var onCommit: () -> Void
    public var onCancel: () -> Void

    public init(
        model: Binding<MergeDialogModel>,
        candidates: [QueryModel],
        primaryPreview: TableData?,
        secondaryPreview: TableData?,
        isSecondaryLoading: Bool = false,
        secondaryErrorMessage: String? = nil,
        rejectionError: String? = nil,
        scrollable: Bool = true,
        onSelectSecondary: @escaping (QueryModel) -> Void,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._model = model
        self.candidates = candidates
        self.primaryPreview = primaryPreview
        self.secondaryPreview = secondaryPreview
        self.isSecondaryLoading = isSecondaryLoading
        self.secondaryErrorMessage = secondaryErrorMessage
        self.rejectionError = rejectionError
        self.scrollable = scrollable
        self.onSelectSecondary = onSelectSecondary
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            headerView

            // Content
            if scrollable {
                ScrollView {
                    tablesSection
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: 520)
            } else {
                tablesSection
            }

            // Rejection error (if any)
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

            Spacer(minLength: 0)

            // Footer / Status bar
            footerView
        }
        .padding(20)
        .frame(width: 900)
        .background(Color.white)
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 24))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 36, height: 36)
                .background(DS.Palette.selectionSoft)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))

            VStack(alignment: .leading, spacing: 2) {
                Text("Gộp truy vấn")
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Text("Chọn bảng và các cột khớp nhau để ghép dữ liệu.")
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            Spacer()
        }
    }

    private var tablesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // NGUỒN CHÍNH
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("NGUỒN CHÍNH")
                        .font(DS.Typeface.labelSmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Palette.secondaryLabel)

                    HStack(spacing: 4) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.accent)
                        Text(model.primaryQueryName)
                            .font(DS.Typeface.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.Palette.label)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(DS.Palette.chrome)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(DS.Palette.separator))

                    Spacer()

                    if !model.leftKeys.isEmpty {
                        Text("\(model.leftKeys.count) cột đã chọn")
                            .font(DS.Typeface.bodySmall)
                            .foregroundStyle(DS.Palette.accent)
                    }
                }

                if let preview = primaryPreview {
                    previewTable(preview: preview, isLeft: true)
                } else {
                    Text("Không có dữ liệu xem trước.")
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
            }

            // BẢNG THỨ HAI
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("BẢNG THỨ HAI")
                        .font(DS.Typeface.labelSmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Palette.secondaryLabel)

                    Spacer()

                    if !model.rightKeys.isEmpty {
                        Text("\(model.rightKeys.count) cột đã chọn")
                            .font(DS.Typeface.bodySmall)
                            .foregroundStyle(DS.Palette.accent)
                    }
                }

                // Dropdown menu chọn bảng thứ hai
                if scrollable {
                    Menu {
                        ForEach(candidates, id: \.id) { q in
                            Button(q.name) {
                                onSelectSecondary(q)
                            }
                        }
                    } label: {
                        secondQueryDropdownLabel
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    secondQueryDropdownLabel
                }

                if isSecondaryLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Đang tải…")
                            .font(DS.Typeface.bodySmall)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    .frame(height: 80)
                } else if let err = secondaryErrorMessage {
                    Text(err)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.danger)
                        .frame(height: 40)
                } else if let secPreview = secondaryPreview {
                    previewTable(preview: secPreview, isLeft: false)
                }
            }

            // KIỂU JOIN
            VStack(alignment: .leading, spacing: 6) {
                Text("KIỂU JOIN")
                    .font(DS.Typeface.labelSmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                if scrollable {
                    Menu {
                        ForEach(JoinChoice.allCases, id: \.self) { choice in
                            Button(choice.localizedTitle) {
                                model.kind = choice
                            }
                        }
                    } label: {
                        joinChoiceDropdownLabel
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    joinChoiceDropdownLabel
                }
            }
        }
    }

    private var secondQueryDropdownLabel: some View {
        HStack {
            Image(systemName: "tablecells")
                .font(.system(size: 11))
                .foregroundStyle(model.secondQuery != nil ? DS.Palette.accent : DS.Palette.tertiaryLabel)
            Text(model.secondQuery ?? "Chọn bảng thứ hai...")
                .font(DS.Typeface.body)
                .foregroundStyle(model.secondQuery != nil ? DS.Palette.label : DS.Palette.tertiaryLabel)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private var joinChoiceDropdownLabel: some View {
        HStack {
            Text(model.kind.localizedTitle)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private func previewTable(preview: TableData, isLeft: Bool) -> some View {
        Group {
            if scrollable {
                ScrollView(.horizontal, showsIndicators: true) {
                    tableContent(preview: preview, isLeft: isLeft)
                }
            } else {
                tableContent(preview: preview, isLeft: isLeft)
            }
        }
    }

    private func tableContent(preview: TableData, isLeft: Bool) -> some View {
        let rowCount = min(3, preview.rowCount)
        return VStack(alignment: .leading, spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                ForEach(preview.columns, id: \.name) { col in
                    let keys = isLeft ? model.leftKeys : model.rightKeys
                    let isKey = keys.contains(col.name)
                    let keyIndex = keys.firstIndex(of: col.name).map { $0 + 1 }

                    HStack(spacing: 4) {
                        Text(QueryEditorFormat.typeBadge(col.data.type))
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(isKey ? DS.Palette.accent : DS.Palette.secondaryLabel)

                        Text(col.name)
                            .font(DS.Typeface.label)
                            .bold()
                            .foregroundStyle(isKey ? DS.Palette.accent : DS.Palette.label)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if let keyIndex {
                            Text("KHOÁ \(keyIndex)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.accent))
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 140, height: 26)
                    .background(isKey ? DS.Palette.selectionSoft : DS.Palette.chrome)
                    .overlay(alignment: .top) {
                        if isKey {
                            Rectangle().fill(DS.Palette.accent).frame(height: 2)
                        }
                    }
                    .hairline(.trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isLeft {
                            model.toggleLeft(col.name)
                        } else {
                            model.toggleRight(col.name)
                        }
                    }
                }
            }
            .hairline(.bottom)

            // 3 rows
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<preview.columns.count, id: \.self) { colIdx in
                        let col = preview.columns[colIdx]
                        let keys = isLeft ? model.leftKeys : model.rightKeys
                        let isKey = keys.contains(col.name)
                        let val = preview.value(row: row, column: colIdx)
                        let text = NavigatorFormat.cell(val)

                        HStack {
                            Text(text)
                                .font(DS.Typeface.bodySmall)
                                .foregroundStyle(DS.Palette.label)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .frame(width: 140, height: 22)
                        .background(isKey ? DS.Palette.selectionSoft.opacity(0.4) : (row % 2 == 1 ? DS.Palette.chrome.opacity(0.3) : Color.white))
                        .hairline(.trailing)
                    }
                }
                .hairline(.bottom)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
    }

    private var footerView: some View {
        HStack(alignment: .center, spacing: 8) {
            // Status Indicator
            Group {
                switch model.statusLevel {
                case .info:
                    Image(systemName: "info.circle")
                        .foregroundStyle(DS.Palette.secondaryLabel)
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.warning)
                case .ok:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Palette.success)
                }
            }
            .font(.system(size: 14))

            Text(model.statusMessage)
                .font(DS.Typeface.bodySmall)
                .foregroundStyle(
                    model.statusLevel == .warning
                        ? DS.Palette.warning
                        : (model.statusLevel == .ok ? DS.Palette.success : DS.Palette.secondaryLabel)
                )

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

public struct MergeDialog: View {
    public let state: QueryEditorState
    public let onCommit: (StepCommand) -> StepCommandOutcome
    public let onCancel: () -> Void
    public var scrollable: Bool = true

    @State private var model: MergeDialogModel
    @State private var secondaryPreview: TableData? = nil
    @State private var isSecondaryLoading: Bool = false
    @State private var secondaryErrorMessage: String? = nil
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

        let leftCols = (state.preview?.columns ?? []).map {
            QueryColumnInfo(name: $0.name, type: $0.data.type)
        }
        self._model = State(initialValue: MergeDialogModel(
            primaryQueryName: state.selectedQuery?.name ?? "Bảng chính",
            leftColumns: leftCols
        ))
    }

    public var body: some View {
        MergeDialogContent(
            model: $model,
            candidates: state.mergeCandidates,
            primaryPreview: state.preview,
            secondaryPreview: secondaryPreview,
            isSecondaryLoading: isSecondaryLoading,
            secondaryErrorMessage: secondaryErrorMessage,
            rejectionError: rejectionError,
            scrollable: scrollable,
            onSelectSecondary: { query in
                loadSecondary(query: query)
            },
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

    private func loadSecondary(query: QueryModel) {
        model.secondQuery = query.name
        model.rightKeys.removeAll()
        model.rightColumns.removeAll()
        secondaryPreview = nil
        isSecondaryLoading = true
        secondaryErrorMessage = nil

        Task {
            async let colsTask = state.resultColumns(ofQuery: query.id)
            async let prevTask = state.resultPreview(ofQuery: query.id, limit: 3)
            let (cols, prev) = await (colsTask, prevTask)

            await MainActor.run {
                self.isSecondaryLoading = false
                if let cols, let prev {
                    self.model.rightColumns = cols
                    self.secondaryPreview = prev
                } else {
                    self.secondaryErrorMessage = "Không thể tải dữ liệu xem trước của truy vấn."
                }
            }
        }
    }
}
