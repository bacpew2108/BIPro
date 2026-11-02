import AppKit
import DAXEngine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Vùng kết quả của DAX Query View (UI1)

/// Thanh tiêu đề (pill trạng thái, chọn kết quả i/n, Copy, Export CSV, Huỷ) và phần thân theo trạng thái chạy.
/// Lỗi hiển thị dạng `Query (dòng, cột) thông báo` như Power BI (O3), có nút đưa con trỏ tới vị trí lỗi.
struct QueryResultsView: View {
    @Bindable var state: DocumentState
    /// Thứ tự dòng đang xem (sau khi sắp xếp trên lưới), để Copy và Export đúng thứ tự.
    @State private var order: [Int]?
    @State private var copied = false

    var body: some View {
        let run = state.currentDAXRun
        VStack(spacing: 0) {
            header(run)
            content(run)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 200, idealHeight: 300)
    }

    // MARK: Thanh tiêu đề

    private func header(_ run: DAXQueryState?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tablecells").foregroundStyle(DS.Palette.secondaryLabel)
            Text("KẾT QUẢ").font(DS.Typeface.labelSmall).tracking(0.5).foregroundStyle(DS.Palette.secondaryLabel)
            if let run { StatusPill(run: run) }
            if let run, let result = run.result, result.tables.count > 1 {
                Picker("", selection: Binding(get: { run.resultIndex }, set: { run.resultIndex = $0; order = nil })) {
                    ForEach(result.tables.indices, id: \.self) { i in
                        Text("Kết quả \(i + 1) / \(result.tables.count)").tag(i)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            Spacer()
            if run?.status == .running {
                Button { state.cancelDAXQuery() } label: { Label("Huỷ", systemImage: "stop.fill") }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(".", modifiers: .command)
            }
            if let table = currentTable(run) {
                Button { copy(table) } label: { Label(copied ? "Đã chép" : "Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Chép kết quả dạng TSV có tiêu đề, cùng định dạng Copy của Power BI")
                Button { export(table) } label: { Label("Xuất CSV", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(DS.Palette.chrome)
        .hairline(.bottom)
    }

    // MARK: Phần thân

    @ViewBuilder
    private func content(_ run: DAXQueryState?) -> some View {
        switch run?.status {
        case nil, .idle?:
            ContentUnavailableView {
                Label("Chưa chạy truy vấn", systemImage: "play.circle")
            } description: {
                Text(state.workspace.metadata == nil
                     ? "File này không có mô hình dữ liệu nên không chạy được truy vấn."
                     : "Bấm Chạy (⌘↵). Nếu đang bôi đen một đoạn, chỉ đoạn đó được chạy.")
            }
        case .running?:
            VStack(spacing: 10) {
                ProgressView()
                Text("Đang chạy truy vấn…").font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel)
                Button("Huỷ") { state.cancelDAXQuery() }.buttonStyle(SecondaryButtonStyle())
            }
        case .cancelled?:
            ContentUnavailableView("Đã huỷ truy vấn", systemImage: "stop.circle",
                                   description: Text("Bấm Chạy để chạy lại."))
        case .failed?:
            if let run, let error = run.error { errorView(error, run: run) }
        case .done?:
            if let run, let table = currentTable(run) {
                if table.rows.isEmpty {
                    VStack(spacing: 6) {
                        Text("Truy vấn không trả về dòng nào").font(DS.Typeface.body)
                        Text(table.columns.joined(separator: " · ")).font(DS.Typeface.mono)
                            .foregroundStyle(DS.Palette.tertiaryLabel).lineLimit(2)
                    }
                } else {
                    ResultGrid(table: table, key: gridKey(run), onOrderChange: { order = $0 })
                }
            }
        }
    }

    private func errorView(_ error: DAXError, run: DAXQueryState) -> some View {
        let text = Self.errorText(error)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Lỗi truy vấn", systemImage: "exclamationmark.triangle.fill")
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
                    } label: { Label("Đi tới dòng \(range.line), cột \(range.column)", systemImage: "arrow.right.to.line") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Label("Chép lỗi", systemImage: "doc.on.doc") }
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

    private func validOrder(for table: ResultTable) -> [Int]? {
        guard let order, order.count == table.rows.count else { return nil }
        return order
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

/// Pill trạng thái: "Thành công · N dòng · 0,24 s", "Lỗi", "Đang chạy…", "Đã huỷ".
struct StatusPill: View {
    let run: DAXQueryState

    var body: some View {
        let (text, color) = describe()
        Text(text)
            .font(DS.Typeface.label)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func describe() -> (String, Color) {
        switch run.status {
        case .idle: return ("Chưa chạy", DS.Palette.secondaryLabel)
        case .running: return ("Đang chạy…", DS.Palette.accent)
        case .cancelled: return ("Đã huỷ", DS.Palette.warning)
        case .failed: return ("Lỗi", DS.Palette.danger)
        case .done:
            let rows = run.result?.tables.indices.contains(run.resultIndex) == true
                ? run.result!.tables[run.resultIndex].rows.count : 0
            return ("Thành công · \(rows.formatted()) dòng · \(Self.seconds(run.result?.elapsedNanoseconds ?? 0))",
                    DS.Palette.success)
        }
    }

    static func seconds(_ nanoseconds: UInt64) -> String {
        String(format: "%.2f s", Double(nanoseconds) / 1e9).replacingOccurrences(of: ".", with: ",")
    }
}
