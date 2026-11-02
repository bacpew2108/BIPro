import PBIXKit
import SwiftUI

// MARK: - DAX query view

struct DAXQueryWorkspace: View {
    @Bindable var state: DocumentState
    @State private var resultsLayout: ResultsLayout = .normal
    /// Chiều cao vùng kết quả ở trạng thái bình thường; người dùng kéo viền trên để đổi.
    @State private var resultsHeight: CGFloat = 300
    @State private var dragStartHeight: CGFloat?
    @State private var showDataPane = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                QueryTabBar(state: state)
                QueryToolbar(state: state)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        if resultsLayout != .expanded {
                            CodeEditor(text: $state.daxQueries[state.daxSelection].text, language: .dax,
                                       measures: state.workspace.metadata?.measures ?? [],
                                       selection: $state.daxEditorSelection, cursorRequest: $state.daxCursorRequest)
                                .frame(maxHeight: .infinity)
                                .hairline(.bottom)
                                .transition(.opacity)
                        }
                        QueryResultsView(state: state, layout: $resultsLayout)
                            .frame(height: resultsFrameHeight(total: geo.size.height))
                            .overlay(alignment: .top) {
                                if resultsLayout == .normal { resizeHandle(total: geo.size.height) }
                            }
                    }
                }
                StatusBar(workspace: state.workspace, detail: statusDetail)
            }
            if showDataPane {
                DataPane(state: state, purpose: .query, collapse: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDataPane = false
                    }
                })
                .frame(width: 270)
                .hairline(.leading)
            } else {
                collapsedDataPaneStrip
            }
        }
        .animation(.easeInOut(duration: 0.2), value: resultsLayout)
        .animation(.easeInOut(duration: 0.2), value: showDataPane)
        .background(Color.white)
    }

    /// Chiều cao vùng kết quả: chỉ thanh tiêu đề khi thu xuống, cả vùng khi phóng to, còn lại theo người dùng kéo.
    private func resultsFrameHeight(total: CGFloat) -> CGFloat {
        switch resultsLayout {
        case .collapsed: return 44
        case .expanded: return max(44, total)
        case .normal: return clampedResultsHeight(resultsHeight, total: total)
        }
    }

    private func clampedResultsHeight(_ height: CGFloat, total: CGFloat) -> CGFloat {
        // Chừa ít nhất 80 pt cho editor; vùng kết quả cao tối thiểu 120 pt.
        min(max(120, height), max(120, total - 80))
    }

    /// Viền trên của vùng kết quả: rê chuột vào thì con trỏ đổi thành mũi tên lên–xuống, kéo để đổi chiều cao.
    private func resizeHandle(total: CGFloat) -> some View {
        Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .offset(y: -4)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartHeight ?? clampedResultsHeight(resultsHeight, total: total)
                        if dragStartHeight == nil { dragStartHeight = start }
                        resultsHeight = clampedResultsHeight(start - value.translation.height, total: total)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }

    private var collapsedDataPaneStrip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDataPane = true
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Text("Dữ liệu")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 14, height: 80)
                Spacer()
            }
            .padding(.top, 10)
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .background(DS.Palette.chrome)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mở lại ô Dữ liệu")
        .hairline(.leading)
    }

    /// Tóm tắt trạng thái theo chuẩn Power BI: "Thành công (ms) · Truy vấn i/n · Kết quả j/m · C cột, R dòng".
    private var statusDetail: String {
        let queryIndex = state.daxSelection + 1
        let queryCount = max(1, state.daxQueries.count)
        guard let run = state.currentDAXRun else {
            return StatusText.summary(status: .idle, queryIndex: queryIndex, queryCount: queryCount)
        }
        let table = (run.result?.tables.indices.contains(run.resultIndex) == true)
            ? run.result!.tables[run.resultIndex] : nil
        let columns = table?.columns.count ?? 0
        let rows = table?.rows.count ?? 0
        let resultIndex = max(1, run.resultIndex + 1)
        let resultCount = max(1, run.result?.tables.count ?? 1)
        return StatusText.summary(
            status: run.status,
            elapsedNanoseconds: run.result?.elapsedNanoseconds ?? 0,
            queryIndex: queryIndex,
            queryCount: queryCount,
            resultIndex: resultIndex,
            resultCount: resultCount,
            columns: columns,
            rows: rows
        )
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
