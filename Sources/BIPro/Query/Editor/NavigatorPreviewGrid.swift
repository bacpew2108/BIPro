import Foundation
import SwiftUI
import ColumnStore
import Connectors

struct NavigatorPreviewGrid: View {
    let state: NavigatorState
    var scrollable: Bool = true

    private var currentItem: NavigatorItem? {
        guard let id = state.previewItemID else { return state.items.first }
        return state.items.first(where: { $0.id == id })
    }

    private var previewTable: TableData? {
        state.preview
    }

    var body: some View {
        VStack(spacing: 0) {
            previewSubheader
                .hairline(.bottom)

            gridBody
                .frame(width: 675, height: 474)
                .clipped()
        }
        .frame(width: 675, height: 518)
        .background(Color.white)
    }

    // MARK: - Subheader (44 pt)

    private var previewSubheader: some View {
        HStack(spacing: 8) {
            if let item = currentItem {
                itemHeaderIcon(for: item.kind)

                Text(item.name)
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                    .lineLimit(1)

                Badge(text: NavigatorFormat.kindBadge(item.kind), color: DS.Palette.secondaryLabel)

                if let table = previewTable {
                    Text("•")
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.tertiaryLabel)

                    Text(previewSubtitle(rowCount: table.rowCount, hint: item.rowCountHint))
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .lineLimit(1)
                }
            } else {
                Text("Chọn một mục để xem trước")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.white)
    }

    private func previewSubtitle(rowCount: Int, hint: Int?) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        if let hint = hint {
            let hintFormatted = formatter.string(from: NSNumber(value: hint)) ?? "\(hint)"
            return "Xem trước \(rowCount) dòng đầu · tổng \(hintFormatted) dòng"
        } else {
            return "Xem trước \(rowCount) dòng đầu"
        }
    }

    @ViewBuilder
    private func itemHeaderIcon(for kind: SourceItemKind) -> some View {
        switch kind {
        case .sheet, .table:
            Image(systemName: "tablecells")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.accent)
        case .namedTable:
            Image(systemName: "tablecells.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.accent)
        case .view:
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.accent)
        case .file:
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.accent)
        case .record:
            Image(systemName: "list.bullet")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.accent)
        case .query:
            Image(systemName: "terminal")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.accent)
        }
    }

    // MARK: - Grid Body

    @ViewBuilder
    private var gridBody: some View {
        if let error = state.previewError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DS.Palette.danger)
                Text(error)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let table = previewTable {
            if scrollable {
                ScrollView([.horizontal, .vertical]) {
                    gridView(table: table, rowLimit: table.rowCount)
                }
            } else {
                gridView(table: table, rowLimit: min(table.rowCount, 16))
                    .frame(width: 675, height: 474, alignment: .topLeading)
                    .clipped()
            }
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Đang tải xem trước...")
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func gridView(table: TableData, rowLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                // # Header column
                Text("#")
                    .font(DS.Typeface.mono)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                    .frame(width: 40, height: 28)
                    .background(DS.Palette.chrome)
                    .hairline(.trailing)

                ForEach(table.columns.indices, id: \.self) { colIndex in
                    let column = table.columns[colIndex]
                    HStack(spacing: 4) {
                        columnTypeIcon(for: column.data.type, source: column.sourceType)
                            .lineLimit(1)
                            .fixedSize()

                        Text(column.name)
                            .font(DS.Typeface.labelSmall)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.Palette.label)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 140, height: 28)
                    .background(DS.Palette.chrome)
                    .hairline(.trailing)
                }
            }
            .hairline(.bottom)

            // Data Rows
            ForEach(0..<rowLimit, id: \.self) { rowIndex in
                let isOdd = rowIndex % 2 == 1
                HStack(spacing: 0) {
                    // Row number
                    Text("\(rowIndex + 1)")
                        .font(DS.Typeface.mono)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .frame(width: 40, height: 28)
                        .background(isOdd ? DS.Palette.chrome.opacity(0.3) : Color.white)
                        .hairline(.trailing)

                    // Columns
                    ForEach(table.columns.indices, id: \.self) { colIndex in
                        let val = table.value(row: rowIndex, column: colIndex)
                        let error = table.error(row: rowIndex, column: colIndex)
                        let isNumeric = isNumericType(table.columns[colIndex].data.type)

                        Group {
                            if error != nil {
                                Text("Error")
                                    .font(DS.Typeface.bodySmall)
                                    .foregroundStyle(DS.Palette.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if case .blank = val {
                                Text("null")
                                    .font(DS.Typeface.bodySmall)
                                    .italic()
                                    .foregroundStyle(DS.Palette.tertiaryLabel)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                let text = NavigatorFormat.sourceCell(val, table.columns[colIndex].sourceType) ?? NavigatorFormat.cell(val)
                                Text(text)
                                    .font(isNumeric ? DS.Typeface.mono : DS.Typeface.bodySmall)
                                    .foregroundStyle(DS.Palette.label)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: isNumeric ? .trailing : .leading)
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(width: 140, height: 28)
                        .background(isOdd ? DS.Palette.chrome.opacity(0.3) : Color.white)
                        .hairline(.trailing)
                    }
                }
                .hairline(.bottom)
            }
        }
    }

    private func isNumericType(_ type: DAXType) -> Bool {
        switch type {
        case .integer, .double, .currency: return true
        default: return false
        }
    }

    @ViewBuilder
    private func columnTypeIcon(for type: DAXType, source: MSourceType?) -> some View {
        if let source, [.time, .duration, .binary].contains(source) {
            Text(QueryEditorFormat.typeBadge(type, source: source))
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DS.Palette.secondaryLabel)
        } else {
            columnTypeIcon(for: type)
        }
    }

    @ViewBuilder
    private func columnTypeIcon(for type: DAXType) -> some View {
        switch type {
        case .integer:
            Text("#")
                .font(DS.Typeface.labelSmall)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DS.Palette.secondaryLabel)
        case .double:
            Text("1.2")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DS.Palette.secondaryLabel)
        case .dateTime:
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.secondaryLabel)
        case .string:
            Text("ABC")
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DS.Palette.secondaryLabel)
        case .boolean:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Palette.secondaryLabel)
        case .currency:
            Text("$")
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
    }
}
