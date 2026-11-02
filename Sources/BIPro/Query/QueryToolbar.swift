import SwiftUI

// MARK: - Thanh công cụ truy vấn DAX

/// Thanh công cụ phía trên editor DAX: Chạy (⌘↵, chạy vùng chọn nếu có), Huỷ (⌘.) khi đang chạy,
/// Định dạng (chờ UI4), Chú thích // và nhãn kiểu tệp ở bên phải.
struct QueryToolbar: View {
    @Bindable var state: DocumentState

    var body: some View {
        HStack(spacing: 8) {
            if state.isRunningDAX {
                Button { state.cancelDAXQuery() } label: { Label("Huỷ", systemImage: "stop.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Huỷ truy vấn đang chạy (⌘.)")
            } else {
                Button { state.runDAXQuery() } label: {
                    Label(state.daxEditorSelection.length > 0 ? "Chạy vùng chọn" : "Chạy", systemImage: "play.fill")
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!state.canRunDAX)
                    .opacity(state.canRunDAX ? 1 : 0.5)
                    .help(state.workspace.metadata == nil ? "File không có mô hình dữ liệu" : "Chạy truy vấn (⌘↵)")
            }
            Button {} label: { Label("Định dạng", systemImage: "text.alignleft") }
                .buttonStyle(SecondaryButtonStyle()).disabled(true).opacity(0.6)
                .help("Định dạng truy vấn: chưa có (UI4)")
            Button {
                let text = state.daxQueries[state.daxSelection].text
                let lines = text.components(separatedBy: "\n")
                let allCommented = lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") || $0.isEmpty }
                state.daxQueries[state.daxSelection].text = lines.map { line in
                    allCommented ? line.replacingOccurrences(of: "// ", with: "", options: .anchored) : (line.isEmpty ? line : "// " + line)
                }.joined(separator: "\n")
            } label: { Label("Chú thích //", systemImage: "text.bubble") }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Text("DAX · Tabular Model Script · UTF-8").font(DS.Typeface.mono).foregroundStyle(DS.Palette.tertiaryLabel)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .hairline(.bottom)
    }
}
