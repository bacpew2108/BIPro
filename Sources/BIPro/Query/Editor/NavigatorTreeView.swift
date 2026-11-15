import Foundation
import SwiftUI
import ColumnStore
import Connectors

struct NavigatorTreeView: View {
    let state: NavigatorState
    var scrollable: Bool = true
    @Binding var searchText: String
    @State private var isRootExpanded: Bool = true

    private var fileName: String {
        let name = URL(fileURLWithPath: state.location).lastPathComponent
        return name.isEmpty ? "Nguồn dữ liệu" : name
    }

    private var filteredItems: [NavigatorItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return state.items }
        return state.items.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var standardItems: [NavigatorItem] {
        filteredItems.filter {
            $0.kind == .file || $0.kind == .sheet || $0.kind == .table || $0.kind == .record
        }
    }

    private var namedItems: [NavigatorItem] {
        filteredItems.filter {
            $0.kind == .namedTable || $0.kind == .view
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterHeader
                .padding(8)

            if scrollable {
                ScrollView {
                    treeContent
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            } else {
                treeContent
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }

            statusBar
                .hairline(.top)
        }
        .frame(width: 285, height: 518)
        .background(DS.Palette.chrome.opacity(0.6))
    }

    // MARK: - Filter Header

    private var filterHeader: some View {
        Group {
            if scrollable {
                SearchField(text: $searchText, prompt: "Tìm bảng và trang tính")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                    Text("Tìm bảng và trang tính...")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.searchFill))
            }
        }
    }

    // MARK: - Tree Content

    private var treeContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Root file node
            Button {
                isRootExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRootExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)

                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.orange)

                    Text(fileName)
                        .font(DS.Typeface.body)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)

                    Spacer()

                    Text("\(filteredItems.count)")
                        .font(DS.Typeface.mono)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
                .padding(.horizontal, 6)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRootExpanded {
                // Group 1: File, Sheet, Table, Record
                if !standardItems.isEmpty {
                    VStack(spacing: 1) {
                        ForEach(standardItems) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.leading, 16)
                }

                // Group 2: Named Tables and Views
                if !namedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BẢNG ĐẶT TÊN VÀ KHUNG NHÌN")
                            .font(DS.Typeface.labelSmall)
                            .tracking(0.5)
                            .foregroundStyle(DS.Palette.tertiaryLabel)
                            .padding(.top, 8)
                            .padding(.horizontal, 6)

                        ForEach(namedItems) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func itemRow(_ item: NavigatorItem) -> some View {
        let isSelected = item.id == state.previewItemID
        let isChecked = state.checkedItemIDs.contains(item.id)

        return HStack(spacing: 6) {
            Button {
                state.toggle(item.id)
            } label: {
                CheckboxMark(isOn: isChecked)
            }
            .buttonStyle(.plain)

            itemIcon(for: item.kind, isSelected: isSelected)
                .frame(width: 16)

            Text(item.name)
                .font(isSelected ? DS.Typeface.headlineSmall : DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let hint = item.rowCountHint {
                Text(NavigatorFormat.rowCount(hint))
                    .font(DS.Typeface.mono)
                    .foregroundStyle(isSelected ? DS.Palette.secondaryLabel : DS.Palette.tertiaryLabel)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .fill(DS.Palette.selectionSoft)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await state.showPreview(item.id)
            }
        }
    }

    @ViewBuilder
    private func itemIcon(for kind: SourceItemKind, isSelected: Bool) -> some View {
        switch kind {
        case .sheet, .table:
            Image(systemName: "tablecells")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.secondaryLabel)
        case .namedTable:
            Image(systemName: "tablecells.fill")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.table)
        case .view:
            Image(systemName: "tablecells.badge.rule")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.secondaryLabel)
        case .file:
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.secondaryLabel)
        case .record:
            Image(systemName: "list.bullet")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.secondaryLabel)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.Palette.accent)
                .frame(width: 8, height: 8)

            Text(NavigatorFormat.selectedSummary(checked: state.checkedItemIDs.count, total: state.items.count))
                .font(DS.Typeface.labelSmall)
                .foregroundStyle(DS.Palette.secondaryLabel)

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(DS.Palette.chrome.opacity(0.8))
    }
}
