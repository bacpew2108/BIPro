import SwiftUI

// MARK: - Thanh tab truy vấn DAX

/// Thanh tab phía trên editor DAX: danh sách tab, nút thêm tab và tên mô hình ở bên phải.
/// Tách khỏi `DAXQueryWorkspace` để bố cục chính gọn hơn. Hành vi giữ nguyên.
struct QueryTabBar: View {
    @Bindable var state: DocumentState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(state.daxQueries.enumerated()), id: \.element.id) { index, query in
                let selected = index == state.daxSelection
                HStack(spacing: 6) {
                    Image(systemName: "terminal").font(.system(size: 10))
                    Text(query.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    if state.daxQueries.count > 1 {
                        Button {
                            state.daxQueries.remove(at: index)
                            state.daxSelection = min(state.daxSelection, state.daxQueries.count - 1)
                        } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(selected ? Color.white : Color.clear)
                .overlay(alignment: .bottom) { if selected { Rectangle().fill(DS.Palette.accent).frame(height: 2) } }
                .onTapGesture { state.daxSelection = index }
            }
            Button {
                state.daxQueries.append(DAXQueryTab(title: "Truy vấn \(state.daxQueries.count + 1)", text: "EVALUATE\n"))
                state.daxSelection = state.daxQueries.count - 1
            } label: { Image(systemName: "plus") }
                .buttonStyle(GhostIconButtonStyle())
            Spacer()
            Text("Mô hình: \(state.fileName) · Import").font(DS.Typeface.mono).foregroundStyle(DS.Palette.tertiaryLabel).padding(.trailing, 12)
        }
        .padding(.leading, 8)
        .background(DS.Palette.chrome)
        .hairline(.bottom)
    }
}
