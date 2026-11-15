import AppKit
import SwiftUI
import ColumnStore
import MEngine

struct PreviewGridView: View {
    let state: QueryEditorState
    @Binding var selectedColumns: [String]
    var showColumnQuality: Bool = true
    var showColumnDistribution: Bool = true
    var scrollable: Bool = true
    var onFilterColumn: ((String) -> Void)? = nil

    @State private var renamingColumn: String? = nil
    @State private var renameText: String = ""
    @State private var selectedError: String? = nil

    private var previewTable: TableData? {
        state.preview
    }

    var body: some View {
        VStack(spacing: 0) {
            topContextBar
                .hairline(.bottom)

            gridContainer
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let selectedError {
                errorDetailBar(error: selectedError)
                    .hairline(.top)
            }
        }
        .background(Color.white)
    }

    // MARK: - Top Context Bar

    private var topContextBar: some View {
        HStack(spacing: 8) {
            Text(state.selectedQuery?.name ?? "")
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.label)
                .lineLimit(1)

            if !selectedColumns.isEmpty {
                let badgeText = "Cột đang chọn: " + selectedColumns.joined(separator: ", ")
                Badge(text: badgeText, color: DS.Palette.accent)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(DS.Palette.chrome)
    }

    // MARK: - Main Grid Content

    @ViewBuilder
    private var gridContainer: some View {
        if let error = state.errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(DS.Palette.danger)

                Text(error)
                    .font(DS.Typeface.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Palette.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Chọn bước trước đó trong Các bước đã áp dụng hoặc sửa biểu thức")
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        } else if let table = previewTable {
            if scrollable {
                ScrollView([.horizontal, .vertical]) {
                    gridContent(table: table, rowLimit: table.rowCount)
                }
                // Không để bề rộng của 11+ cột (dựng lười) đẩy rộng cả cửa sổ: lưới cuộn trong phần được cấp.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
            } else {
                gridContent(table: table, rowLimit: min(table.rowCount, 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Đang tính xem trước…")
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Grid Content

    /// Hàng dựng lười khi cuộn được (1000 dòng × nhiều cột dựng hết một lần làm đứng cửa sổ hơn 10 s). `ImageRenderer` không vẽ được
    /// `LazyVStack` nên ảnh PNG (không cuộn, 16 dòng) dùng `VStack`.
    @ViewBuilder
    private func gridContent(table: TableData, rowLimit: Int) -> some View {
        if scrollable {
            LazyVStack(alignment: .leading, spacing: 0) { gridRows(table: table, rowLimit: rowLimit) }
        } else {
            VStack(alignment: .leading, spacing: 0) { gridRows(table: table, rowLimit: rowLimit) }
        }
    }

    @ViewBuilder
    private func gridRows(table: TableData, rowLimit: Int) -> some View {
        Group {
            // Header Row
            HStack(spacing: 0) {
                // # Column header
                Text("#")
                    .font(DS.Typeface.mono)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                    .frame(width: 40, height: headerHeight)
                    .background(DS.Palette.chrome)
                    .hairline(.trailing)

                ForEach(0..<table.columns.count, id: \.self) { (colIdx: Int) in
                    let col = table.columns[colIdx]
                    let isSelected = selectedColumns.contains(col.name)
                    let profile = state.profiles.first { $0.columnName == col.name }

                    columnHeader(name: col.name, type: col.data.type, profile: profile, isSelected: isSelected)
                        .frame(width: 140, height: headerHeight)
                        .background(isSelected ? DS.Palette.selectionSoft : DS.Palette.chrome)
                        .overlay(alignment: .top) {
                            if isSelected {
                                Rectangle().fill(DS.Palette.accent).frame(height: 2)
                            }
                        }
                        .hairline(.trailing)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleColumnTap(col.name)
                        }
                }
            }
            .hairline(.bottom)

            // Data Rows
            ForEach(0..<rowLimit, id: \.self) { rowIdx in
                let isOdd = rowIdx % 2 == 1
                HStack(spacing: 0) {
                    // Row number
                    Text("\(rowIdx + 1)")
                        .font(DS.Typeface.mono)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .frame(width: 40, height: 26)
                        .background(isOdd ? DS.Palette.chrome.opacity(0.3) : Color.white)
                        .hairline(.trailing)

                    // Columns
                    ForEach(0..<table.columns.count, id: \.self) { colIdx in
                        let col = table.columns[colIdx]
                        let val = table.value(row: rowIdx, column: colIdx)
                        let error = table.error(row: rowIdx, column: colIdx)
                        let isSelected = selectedColumns.contains(col.name)
                        let isNumeric = isNumericType(col.data.type)

                        dataCell(value: val, error: error, isNumeric: isNumeric, isSelected: isSelected, isOdd: isOdd)
                            .frame(width: 140, height: 26)
                            .hairline(.trailing)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let error {
                                    selectedError = error
                                }
                            }
                    }
                }
                .hairline(.bottom)
            }
        }
    }

    private var headerHeight: CGFloat {
        if showColumnQuality && showColumnDistribution {
            return 56
        } else if showColumnQuality || showColumnDistribution {
            return 44
        } else {
            return 28
        }
    }

    // MARK: - Column Header View

    private func columnHeader(name: String, type: DAXType, profile: ColumnProfile?, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Top: Type badge, Name, Arrow
            HStack(spacing: 4) {
                Text(QueryEditorFormat.typeBadge(type))
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.secondaryLabel)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.8)))

                if renamingColumn == name {
                    TextField("", text: $renameText, onCommit: {
                        commitRename(oldName: name)
                    })
                    .textFieldStyle(.plain)
                    .font(DS.Typeface.label)
                    .frame(maxWidth: .infinity)
                } else {
                    Text(name)
                        .font(DS.Typeface.label)
                        .bold()
                        .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.label)
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            renamingColumn = name
                            renameText = name
                        }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                    .onTapGesture {
                        onFilterColumn?(name)
                    }
            }

            // Quality bar
            if showColumnQuality, let profile {
                let total = QueryEditorFormat.countLine(profile)
                qualityBar(profile: profile, total: total)

                HStack(spacing: 0) {
                    Text(QueryEditorFormat.percent(profile.valid, of: total))
                        .foregroundStyle(DS.Palette.success)
                    Spacer()
                    Text(QueryEditorFormat.percent(profile.error, of: total))
                        .foregroundStyle(profile.error > 0 ? DS.Palette.danger : DS.Palette.tertiaryLabel)
                    Spacer()
                    Text(QueryEditorFormat.percent(profile.empty, of: total))
                        .foregroundStyle(profile.empty > 0 ? DS.Palette.warning : DS.Palette.tertiaryLabel)
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
            }

            // Distribution summary
            if showColumnDistribution, let profile {
                HStack(spacing: 3) {
                    miniHistogram(distribution: profile.distribution)
                    Text("\(profile.distinct) giá trị khác nhau")
                        .font(.system(size: 8))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private func qualityBar(profile: ColumnProfile, total: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let validW = total > 0 ? w * CGFloat(profile.valid) / CGFloat(total) : 0
            let errorW = total > 0 ? w * CGFloat(profile.error) / CGFloat(total) : 0
            let emptyW = total > 0 ? w * CGFloat(profile.empty) / CGFloat(total) : w

            HStack(spacing: 0) {
                if validW > 0 {
                    Rectangle().fill(DS.Palette.success).frame(width: validW)
                }
                if errorW > 0 {
                    Rectangle().fill(DS.Palette.danger).frame(width: errorW)
                }
                if emptyW > 0 {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: emptyW)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 3)
    }

    private func miniHistogram(distribution: [ProfileBucket]) -> some View {
        let maxCount = distribution.map(\.count).max() ?? 1
        return HStack(alignment: .bottom, spacing: 1) {
            ForEach(distribution.prefix(5).indices, id: \.self) { i in
                let fraction = maxCount > 0 ? CGFloat(distribution[i].count) / CGFloat(maxCount) : 0
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(DS.Palette.accent.opacity(0.7))
                    .frame(width: 2, height: max(2, 8 * fraction))
            }
        }
        .frame(height: 8)
    }

    // MARK: - Data Cell

    @ViewBuilder
    private func dataCell(value: StoredValue, error: String?, isNumeric: Bool, isSelected: Bool, isOdd: Bool) -> some View {
        let bg: Color = {
            if error != nil {
                return DS.Palette.danger.opacity(0.12)
            } else if isSelected {
                return DS.Palette.selectionSoft.opacity(0.4)
            } else if isOdd {
                return DS.Palette.chrome.opacity(0.3)
            } else {
                return Color.white
            }
        }()

        HStack {
            if error != nil {
                Text("Lỗi")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DS.Palette.danger))
                Spacer()
            } else if case .blank = value {
                Text("null")
                    .font(DS.Typeface.bodySmall)
                    .italic()
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer()
            } else {
                let text = NavigatorFormat.cell(value)
                if isNumeric {
                    Spacer(minLength: 0)
                    Text(text)
                        .font(DS.Typeface.mono)
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)
                } else {
                    Text(text)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
        .background(bg)
    }

    // MARK: - Error Detail Bar

    private func errorDetailBar(error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.Palette.danger)

            Text(error)
                .font(DS.Typeface.mono)
                .foregroundStyle(DS.Palette.danger)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer()

            Button {
                selectedError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DS.Palette.danger.opacity(0.08))
    }

    // MARK: - Actions

    private func handleColumnTap(_ columnName: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            if let idx = selectedColumns.firstIndex(of: columnName) {
                selectedColumns.remove(at: idx)
            } else {
                selectedColumns.append(columnName)
            }
        } else {
            selectedColumns = [columnName]
        }
    }

    private func commitRename(oldName: String) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != oldName {
            state.perform(.renameColumns([ColumnRename(old: oldName, new: trimmed)]))
        }
        renamingColumn = nil
    }

    private func isNumericType(_ type: DAXType) -> Bool {
        switch type {
        case .integer, .double, .currency: return true
        default: return false
        }
    }
}
