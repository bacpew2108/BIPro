import PBIXKit
import SwiftUI

// MARK: - DAX query view

struct DAXQueryWorkspace: View {
    @Bindable var state: DocumentState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                QueryTabBar(state: state)
                QueryToolbar(state: state)
                CodeEditor(text: $state.daxQueries[state.daxSelection].text, language: .dax,
                           selection: $state.daxEditorSelection, cursorRequest: $state.daxCursorRequest)
                    .frame(minHeight: 200)
                    .hairline(.bottom)
                QueryResultsView(state: state)
                StatusBar(workspace: state.workspace, detail: statusDetail)
            }
            DataPane(state: state, purpose: .query)
                .frame(width: 270)
                .hairline(.leading)
        }
        .background(Color.white)
    }

    /// "Truy vấn i / n", thêm số dòng và thời gian của lần chạy thành công gần nhất.
    private var statusDetail: String {
        var detail = "Truy vấn \(state.daxSelection + 1) / \(state.daxQueries.count)"
        if let run = state.currentDAXRun, run.status == .done, let result = run.result {
            let rows = result.tables.map(\.rows.count).reduce(0, +)
            detail += " · \(rows.formatted()) dòng · \(StatusPill.seconds(result.elapsedNanoseconds))"
        }
        return detail
    }
}

// MARK: - TMDL view

struct TMDLWorkspace: View {
    @Bindable var state: DocumentState

    var body: some View {
        let docs = state.workspace.tmdlDocuments
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PaneHeader(title: "Định nghĩa", symbol: "folder")
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(docs) { doc in
                            TreeRow(level: doc.path.contains("/") ? 1 : 0,
                                    symbol: doc.path.hasPrefix("tables/") ? "tablecells" : "doc.text",
                                    tint: doc.path.hasPrefix("tables/") ? DS.Palette.table : DS.Palette.secondaryLabel,
                                    title: doc.path, isSelected: state.tmdlPath == doc.path) { state.tmdlPath = doc.path }
                        }
                    }
                }
                PaneFooter(text: "\(docs.count) tệp · chỉ đọc")
            }
            .frame(width: 250)
            .background(DS.Palette.chrome)
            .hairline(.trailing)

            VStack(spacing: 0) {
                HStack {
                    Text(state.tmdlPath ?? "").font(DS.Typeface.monoMedium)
                    Badge(text: "Chỉ đọc · sinh từ metadata")
                    Spacer()
                    Text("TMDL · UTF-8").font(DS.Typeface.mono).foregroundStyle(DS.Palette.tertiaryLabel)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .hairline(.bottom)
                CodeEditor(text: .constant(docs.first { $0.path == state.tmdlPath }?.text ?? ""), language: .tmdl, isEditable: false)
                StatusBar(workspace: state.workspace, detail: "Sửa và áp dụng TMDL: Phase E")
            }
        }
        .background(Color.white)
    }
}
