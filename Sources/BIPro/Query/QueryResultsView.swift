import AppKit
import DAXEngine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Vùng kết quả của DAX Query View (UI1)

/// Thanh tiêu đề theo mẫu Power BI Desktop (Kết quả, menu kết quả i/n, Copy/Export, Huỷ, Phóng to/Thu nhỏ)
/// và phần thân theo trạng thái chạy. Lỗi hiển thị dạng `Query (dòng, cột) thông báo` như Power BI (O3).
/// Ba trạng thái của vùng kết quả: thu xuống chỉ còn thanh tiêu đề, bình thường (kéo viền trên để đổi cao), phóng to.
enum ResultsLayout: Equatable { case collapsed, normal, expanded }

struct QueryResultsView: View {
    @Bindable var state: DocumentState
    @Binding var layout: ResultsLayout
    /// Thứ tự dòng đang xem (sau khi sắp xếp trên lưới), để Copy và Export đúng thứ tự.
    @State private var order: [Int]?
    @State private var copied = false

    init(state: DocumentState, layout: Binding<ResultsLayout> = .constant(.normal)) {
        self.state = state
        self._layout = layout
    }

    var body: some View {
        let run = state.currentDAXRun
        VStack(spacing: 0) {
            header(run)
            if layout != .collapsed {
                content(run)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Palette.canvas)
            }
        }
        .background(DS.Palette.canvas)
    }

    // MARK: Thanh tiêu đề

    private func header(_ run: DAXQueryState?) -> some View {
        let table = currentTable(run)
        let hasTable = table != nil
        let tableCount = max(1, run?.result?.tables.count ?? 1)
        let tableIndex = hasTable ? min(tableCount, (run?.resultIndex ?? 0) + 1) : 1

        return HStack(spacing: 10) {
            Text(bi("Kết quả", "Results"))
                .font(DS.Typeface.headlineMedium)
                .foregroundStyle(DS.Palette.label)

            Rectangle()
                .fill(DS.Palette.separator)
                .frame(width: 1, height: 16)

            Menu {
                if let result = run?.result, !result.tables.isEmpty {
                    ForEach(result.tables.indices, id: \.self) { i in
                        Button {
                            run?.resultIndex = i
                            order = nil
                        } label: {
                            if i == run?.resultIndex {
                                Label(bi("Kết quả \(i + 1)/\(result.tables.count)", "Result \(i + 1)/\(result.tables.count)"), systemImage: "checkmark")
                            } else {
                                Text(bi("Kết quả \(i + 1)/\(result.tables.count)", "Result \(i + 1)/\(result.tables.count)"))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(bi("Kết quả \(tableIndex)/\(tableCount)", "Result \(tableIndex)/\(tableCount)"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            .menuStyle(.button)
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
            .disabled(!hasTable)

            Menu {
                Button {
                    if let table = currentTable(run) {
                        copy(table)
                    }
                } label: {
                    Label(bi("Sao chép", "Copy"), systemImage: "doc.on.doc")
                }
                Button {
                    if let table = currentTable(run) {
                        export(table)
                    }
                } label: {
                    Label(bi("Xuất CSV…", "Export CSV…"), systemImage: "square.and.arrow.up")
                }
            } label: {
                Label(copied ? bi("Đã chép", "Copied") : bi("Sao chép", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()   // Menu borderless tự giãn hết chiều ngang nếu không cố định kích thước.
            .disabled(!hasTable)
            .help(bi("Sao chép bảng kết quả hoặc xuất CSV", "Copy result table or export CSV"))

            if run?.status == .running {
                Button { state.cancelDAXQuery() } label: { Label(bi("Huỷ", "Cancel"), systemImage: "stop.fill") }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(".", modifiers: .command)
            }

            Spacer()

            // ⌃⌃ đẩy vùng kết quả lên một nấc, ⌄⌄ hạ xuống một nấc: thu xuống ↔ bình thường ↔ phóng to.
            if layout != .expanded {
                layoutButton(symbol: "chevron.up.2",
                             help: layout == .collapsed ? bi("Hiện lại kết quả", "Show results") : bi("Phóng to kết quả", "Maximize results"),
                             to: layout == .collapsed ? .normal : .expanded)
            }
            if layout != .collapsed {
                layoutButton(symbol: "chevron.down.2",
                             help: layout == .expanded ? bi("Thu nhỏ kết quả", "Restore results") : bi("Thu kết quả xuống dưới", "Collapse results"),
                             to: layout == .expanded ? .normal : .collapsed)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(DS.Palette.canvas)
    }

    private func layoutButton(symbol: String, help: String, to target: ResultsLayout) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { layout = target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .buttonStyle(GhostIconButtonStyle())
        .help(help)
    }

    // MARK: Phần thân

    @ViewBuilder
    private func content(_ run: DAXQueryState?) -> some View {
        switch run?.status {
        case nil, .idle?:
            ContentUnavailableView {
                Label(bi("Chưa chạy truy vấn", "No query run yet"), systemImage: "play.circle")
            } description: {
                Text(state.workspace.metadata == nil
                     ? bi("File này không có mô hình dữ liệu nên không chạy được truy vấn.", "This file has no data model, so queries cannot run.")
                     : bi("Bấm Chạy (⌘↵). Nếu đang bôi đen một đoạn, chỉ đoạn đó được chạy.", "Press Run (⌘↵). Select a range to run only that selection."))
            }
        case .running?:
            VStack(spacing: 10) {
                ProgressView()
                Text(bi("Đang chạy truy vấn…", "Running query…")).font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel)
                Button(bi("Huỷ", "Cancel")) { state.cancelDAXQuery() }.buttonStyle(SecondaryButtonStyle())
            }
        case .cancelled?:
            ContentUnavailableView(bi("Đã huỷ truy vấn", "Query cancelled"), systemImage: "stop.circle",
                                   description: Text(bi("Bấm Chạy để chạy lại.", "Press Run to execute again.")))
        case .failed?:
            if let run, let error = run.error { errorView(error, run: run) }
        case .done?:
            if let run, let table = currentTable(run) {
                if table.rows.isEmpty {
                    VStack(spacing: 6) {
                        Text(bi("Truy vấn không trả về dòng nào", "Query returned no rows")).font(DS.Typeface.body)
                        Text(table.columns.joined(separator: " · ")).font(DS.Typeface.mono)
                            .foregroundStyle(DS.Palette.tertiaryLabel).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ResultGrid(table: table, key: gridKey(run), onOrderChange: { order = $0 })
                        .padding(.leading, 12)
                        .padding(.top, 12)
                }
            }
        }
    }

    private func errorView(_ error: DAXError, run: DAXQueryState) -> some View {
        let text = Self.errorText(error)
        return VStack(alignment: .leading, spacing: 10) {
            Label(bi("Lỗi truy vấn", "Query error"), systemImage: "exclamationmark.triangle.fill")
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.danger)
            Text(text)
                .font(DS.Typeface.monoMedium)
                .foregroundStyle(DS.Palette.label)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let range = error.range {
                    Button {
                        state.daxCursorRequest = run.ranOffset + range.start
                    } label: { Label(bi("Đi tới dòng \(range.line), cột \(range.column)", "Go to line \(range.line), col \(range.column)"), systemImage: "arrow.right.to.line") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Label(bi("Chép lỗi", "Copy error"), systemImage: "doc.on.doc") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Spacer()
        }
        .padding(16)
    }

    /// `Query (dòng, cột) thông báo` như Power BI (O3); không có vị trí thì chỉ có thông báo.
    static func errorText(_ error: DAXError) -> String {
        if let range = error.range {
            return "Query (\(range.line), \(range.column)) \(error.message)"
        }
        return error.message
    }

    // MARK: Hỗ trợ

    private func currentTable(_ run: DAXQueryState?) -> ResultTable? {
        guard let run, run.status == .done, let result = run.result, result.tables.indices.contains(run.resultIndex) else {
            return nil
        }
        return result.tables[run.resultIndex]
    }

    private func gridKey(_ run: DAXQueryState) -> String {
        "\(run.id)-\(run.startedAt?.timeIntervalSince1970 ?? 0)-\(run.resultIndex)"
    }

    static func validOrder(_ order: [Int]?, rowCount: Int) -> [Int]? {
        guard let order else { return nil }
        let validRange = 0..<rowCount
        var seen = Set<Int>()
        for index in order {
            guard validRange.contains(index), seen.insert(index).inserted else { return nil }
        }
        return order
    }

    private func validOrder(for table: ResultTable) -> [Int]? {
        Self.validOrder(order, rowCount: table.rows.count)
    }

    private func copy(_ table: ResultTable) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ResultFormat.tsv(table, order: validOrder(for: table)), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func export(_ table: ResultTable) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = (state.currentDAXTab?.title ?? "Ket qua") + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ResultFormat.csv(table, order: validOrder(for: table)).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
