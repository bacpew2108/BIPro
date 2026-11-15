import SwiftUI

struct QueryListView: View {
    let state: QueryEditorState
    let existingTableNames: Set<String>
    var scrollable: Bool = true

    @State private var renamingQueryID: UUID? = nil
    @State private var renameText: String = ""
    @State private var renameError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
                .hairline(.bottom)

            if let error = renameError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.danger)
                    Text(error)
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.danger)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        renameError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DS.Palette.danger.opacity(0.08))
                .hairline(.bottom)
            }

            Group {
                if scrollable {
                    ScrollView(.vertical) {
                        queryList
                    }
                } else {
                    queryList
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(width: 250)
        .background(DS.Palette.chrome)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.secondaryLabel)

            Text("Truy vấn [\(state.queries.count)]")
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.label)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var queryList: some View {
        VStack(spacing: 2) {
            ForEach(state.queries) { query in
                queryRow(query: query)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private func queryRow(query: QueryModel) -> some View {
        let isSelected = query.id == state.selectedQueryID
        let hasErrors = query.steps.contains { state.stepErrors[$0.name] != nil }

        return HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : DS.Palette.accent)

            if renamingQueryID == query.id {
                TextField("", text: $renameText, onCommit: {
                    commitRename(query: query)
                })
                .textFieldStyle(.roundedBorder)
                .font(DS.Typeface.body)
            } else {
                Text(query.name)
                    .font(isSelected ? DS.Typeface.headlineSmall : DS.Typeface.body)
                    .foregroundStyle(isSelected ? .white : (query.enableLoad ? DS.Palette.label : DS.Palette.secondaryLabel))
                    .italic(!query.enableLoad)
                    .opacity(query.enableLoad ? 1.0 : 0.7)
                    .lineLimit(1)
            }

            Spacer()

            if hasErrors {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : DS.Palette.warning)
                    .help("Truy vấn có bước lỗi")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control)
            .fill(isSelected ? DS.Palette.accent : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectQuery(query.id)
        }
        .contextMenu {
            Button {
                state.setEnableLoad(query.id, !query.enableLoad)
            } label: {
                if query.enableLoad {
                    Label("Bật tải vào mô hình", systemImage: "checkmark")
                } else {
                    Text("Bật tải vào mô hình")
                }
            }

            Button("Đổi tên…") {
                renamingQueryID = query.id
                renameText = query.name
                renameError = nil
            }
        }
    }

    private func commitRename(query: QueryModel) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != query.name {
            if let error = state.renameQuery(query.id, to: trimmed, existingTableNames: existingTableNames) {
                renameError = error
            } else {
                renameError = nil
            }
        }
        renamingQueryID = nil
    }
}
