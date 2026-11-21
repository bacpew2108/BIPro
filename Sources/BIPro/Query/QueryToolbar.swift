import SwiftUI

// MARK: - Thanh công cụ truy vấn DAX

/// Thanh công cụ phía trên editor DAX: Chạy (⌘↵, chạy vùng chọn nếu có), Huỷ (⌘.) khi đang chạy,
/// Định dạng (chờ UI4), Chú thích // và nhãn kiểu tệp ở bên phải.
struct QueryToolbar: View {
    @Bindable var state: DocumentState

    var body: some View {
        HStack(spacing: 8) {
            if state.isRunningDAX {
                Button { state.cancelDAXQuery() } label: { Label(bi("Huỷ", "Cancel"), systemImage: "stop.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(".", modifiers: .command)
                    .help(bi("Huỷ truy vấn đang chạy (⌘.)", "Cancel running query (⌘.)"))
            } else {
                Button { state.runDAXQuery() } label: {
                    Label(state.daxEditorSelection.length > 0 ? bi("Chạy vùng chọn", "Run selection") : bi("Chạy", "Run"), systemImage: "play.fill")
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!state.canRunDAX)
                    .opacity(state.canRunDAX ? 1 : 0.5)
                    .help(state.workspace.metadata == nil ? bi("File không có mô hình dữ liệu", "No data model in file") : bi("Chạy truy vấn (⌘↵)", "Run query (⌘↵)"))
            }
            Button {} label: { Label(bi("Định dạng", "Format"), systemImage: "text.alignleft") }
                .buttonStyle(SecondaryButtonStyle()).disabled(true).opacity(0.6)
                .help(bi("Định dạng truy vấn: sắp có", "Format query: coming soon"))
            Button {
                let text = state.daxQueries[state.daxSelection].text
                let lines = text.components(separatedBy: "\n")
                let allCommented = lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") || $0.isEmpty }
                state.daxQueries[state.daxSelection].text = lines.map { line in
                    allCommented ? line.replacingOccurrences(of: "// ", with: "", options: .anchored) : (line.isEmpty ? line : "// " + line)
                }.joined(separator: "\n")
            } label: { Label(bi("Chú thích //", "Comment //"), systemImage: "text.bubble") }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Text("DAX · Tabular Model Script · UTF-8").font(DS.Typeface.mono).foregroundStyle(DS.Palette.tertiaryLabel)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .hairline(.bottom)
    }
}
