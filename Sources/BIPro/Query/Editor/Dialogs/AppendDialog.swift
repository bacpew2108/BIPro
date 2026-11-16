import SwiftUI
import ColumnStore
import MEngine

public struct AppendDialogContent: View {
    @Binding public var model: AppendDialogModel
    public var primaryColumns: [String]
    public var secondaryColumnsMap: [String: [String]] // Query Name -> Column names
    public var rejectionError: String? = nil
    public var scrollable: Bool = true
    public var onCommit: () -> Void
    public var onCancel: () -> Void

    @State private var selectedAvailable: String? = nil
    @State private var selectedToAppend: String? = nil

    public init(
        model: Binding<AppendDialogModel>,
        primaryColumns: [String] = [],
        secondaryColumnsMap: [String: [String]] = [:],
        rejectionError: String? = nil,
        scrollable: Bool = true,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._model = model
        self.primaryColumns = primaryColumns
        self.secondaryColumnsMap = secondaryColumnsMap
        self.rejectionError = rejectionError
        self.scrollable = scrollable
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerView

            // Mode selector
            SegmentedPill(
                selection: $model.mode,
                options: [
                    .init(value: .twoTables, title: "Hai bảng"),
                    .init(value: .threeOrMore, title: "Từ ba bảng")
                ]
            )

            // Content
            if scrollable {
                ScrollView {
                    formContent
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: 340)
            } else {
                formContent
            }

            // Column comparison info strip
            columnComparisonSection

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

            // Footer
            footerView
        }
        .padding(20)
        .frame(width: 640)
        .background(Color.white)
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 24))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 36, height: 36)
                .background(DS.Palette.selectionSoft)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))

            VStack(alignment: .leading, spacing: 2) {
                Text("Nối truy vấn")
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Text("Nối các dòng từ hai hoặc nhiều bảng có cấu trúc tương tự vào một bảng duy nhất.")
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
            case .twoTables:
                twoTablesSection
            case .threeOrMore:
                threeOrMoreSection
            }
        }
    }

    private var twoTablesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bảng chính (bảng hiện tại)")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                HStack {
                    Image(systemName: "tablecells")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    Text(model.primaryQueryName)
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(DS.Palette.chrome)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bảng thứ hai")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                if scrollable {
                    Menu {
                        ForEach(model.candidates, id: \.self) { candidate in
                            Button(candidate) {
                                model.selectTwoTablesQuery(candidate)
                            }
                        }
                    } label: {
                        twoTablesDropdownLabel
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    twoTablesDropdownLabel
                }
            }
        }
    }

    private var twoTablesDropdownLabel: some View {
        HStack {
            Image(systemName: "tablecells")
                .font(.system(size: 11))
                .foregroundStyle(model.selectedQueries.first != nil ? DS.Palette.accent : DS.Palette.tertiaryLabel)
            Text(model.selectedQueries.first ?? "Chọn một bảng...")
                .font(DS.Typeface.body)
                .foregroundStyle(model.selectedQueries.first != nil ? DS.Palette.label : DS.Palette.tertiaryLabel)
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

    private var availableCandidates: [String] {
        model.candidates.filter { !model.selectedQueries.contains($0) }
    }

    private var threeOrMoreSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left Box: Bảng có sẵn
            VStack(alignment: .leading, spacing: 4) {
                Text("Bảng có sẵn:")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                VStack(alignment: .leading, spacing: 0) {
                    if availableCandidates.isEmpty {
                        Text("Không còn bảng nào")
                            .font(DS.Typeface.bodySmall)
                            .foregroundStyle(DS.Palette.tertiaryLabel)
                            .padding(8)
                    } else {
                        ForEach(availableCandidates, id: \.self) { candidate in
                            let isSel = selectedAvailable == candidate
                            HStack(spacing: 6) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 11))
                                    .foregroundStyle(isSel ? DS.Palette.accent : DS.Palette.secondaryLabel)
                                Text(candidate)
                                    .font(DS.Typeface.bodySmall)
                                    .foregroundStyle(DS.Palette.label)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(isSel ? DS.Palette.selectionSoft : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedAvailable = candidate
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
            }

            // Middle Buttons: Thêm >> / << Xoá
            VStack(spacing: 8) {
                Spacer(minLength: 24)

                Button {
                    if let sel = selectedAvailable {
                        model.selectedQueries.append(sel)
                        selectedAvailable = availableCandidates.first(where: { $0 != sel })
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Thêm")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(DS.Typeface.bodySmall)
                    .frame(width: 80, height: 26)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                }
                .buttonStyle(.plain)
                .disabled(selectedAvailable == nil)

                Button {
                    if let sel = selectedToAppend, let idx = model.selectedQueries.firstIndex(of: sel) {
                        model.selectedQueries.remove(at: idx)
                        selectedToAppend = model.selectedQueries.first
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        Text("Xoá")
                    }
                    .font(DS.Typeface.bodySmall)
                    .frame(width: 80, height: 26)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
                }
                .buttonStyle(.plain)
                .disabled(selectedToAppend == nil)

                Spacer(minLength: 0)
            }
            .frame(width: 90)

            // Right Box: Bảng để nối
            VStack(alignment: .leading, spacing: 4) {
                Text("Bảng để nối:")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)

                VStack(alignment: .leading, spacing: 0) {
                    // Primary Table (Header item, fixed)
                    HStack(spacing: 6) {
                        Image(systemName: "tablecells.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.accent)
                        Text(model.primaryQueryName)
                            .font(DS.Typeface.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.Palette.label)
                        Spacer()
                        Text("Chính")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Palette.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DS.Palette.selectionSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DS.Palette.chrome.opacity(0.4))
                    .hairline(.bottom)

                    // Added Tables
                    ForEach(model.selectedQueries, id: \.self) { query in
                        let isSel = selectedToAppend == query
                        let order = model.order(of: query)
                        HStack(spacing: 6) {
                            if let order {
                                Text("\(order)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Circle().fill(DS.Palette.accent))
                            }
                            Text(query)
                                .font(DS.Typeface.bodySmall)
                                .foregroundStyle(DS.Palette.label)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isSel ? DS.Palette.selectionSoft : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedToAppend = query
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))
            }
        }
    }

    @ViewBuilder
    private var columnComparisonSection: some View {
        if !model.selectedQueries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.selectedQueries, id: \.self) { queryName in
                    if let secCols = secondaryColumnsMap[queryName] {
                        let comp = AppendDialogModel.columnComparison(
                            primaryColumns: primaryColumns,
                            secondaryColumns: secCols
                        )
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Palette.secondaryLabel)
                            Text("\(queryName): \(comp.commonCount) cột chung, \(comp.secondaryOnlyCount) cột chỉ có ở bảng này")
                                .font(DS.Typeface.bodySmall)
                                .foregroundStyle(DS.Palette.secondaryLabel)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
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

public struct AppendDialog: View {
    public let state: QueryEditorState
    public let onCommit: (StepCommand) -> StepCommandOutcome
    public let onCancel: () -> Void
    public var scrollable: Bool = true

    @State private var model: AppendDialogModel
    @State private var secondaryColumnsMap: [String: [String]] = [:]
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

        let candidateNames = state.mergeCandidates.map(\.name)
        self._model = State(initialValue: AppendDialogModel(
            primaryQueryName: state.selectedQuery?.name ?? "Bảng chính",
            candidates: candidateNames
        ))
    }

    private var primaryColumns: [String] {
        state.preview?.columns.map(\.name) ?? []
    }

    public var body: some View {
        AppendDialogContent(
            model: $model,
            primaryColumns: primaryColumns,
            secondaryColumnsMap: secondaryColumnsMap,
            rejectionError: rejectionError,
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
        .task {
            loadColumnsForCandidates()
        }
    }

    private func loadColumnsForCandidates() {
        for candidate in state.mergeCandidates {
            Task {
                if let cols = await state.resultColumns(ofQuery: candidate.id) {
                    await MainActor.run {
                        secondaryColumnsMap[candidate.name] = cols.map(\.name)
                    }
                }
            }
        }
    }
}
