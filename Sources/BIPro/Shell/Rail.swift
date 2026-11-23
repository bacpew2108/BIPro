import SwiftUI

/// Rail điều hướng bên trái 5 biểu tượng theo Power BI Desktop (`UIMetrics.rail` = 42 pt).
/// Luôn bật cả 5 biểu tượng kể cả khi tệp chưa có mô hình (FR-016); bỏ nút Cài đặt ở đáy rail.
struct Rail: View {
    @Bindable var state: DocumentState
    private let preferences = AppPreferences.shared

    static let modes: [WorkspaceMode] = WorkspaceMode.allCases

    static func tooltip(for mode: WorkspaceMode, language: ResolvedLanguage) -> String {
        switch (mode, language) {
        case (.report, .en): "Report view"
        case (.table, .en): "Table view"
        case (.model, .en): "Model view"
        case (.daxQuery, .en): "DAX query view"
        case (.tmdl, .en): "TMDL View"
        case (.report, .vi): "Chế độ Báo cáo"
        case (.table, .vi): "Chế độ Bảng"
        case (.model, .vi): "Chế độ Mô hình"
        case (.daxQuery, .vi): "Chế độ truy vấn DAX"
        case (.tmdl, .vi): "Chế độ TMDL"
        }
    }

    var body: some View {
        let lang = preferences.effectiveLanguage
        VStack(spacing: 2) {
            ForEach(Self.modes) { mode in
                let selected = state.mode == mode
                let tip = Self.tooltip(for: mode, language: lang)
                Button { state.mode = mode } label: {
                    ZStack(alignment: .leading) {
                        if selected {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.Palette.selectionSoft)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                            Rectangle()
                                .fill(DS.Palette.accentTeal)
                                .frame(width: 3, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        }
                        Image(systemName: mode.symbol)
                            .font(.system(size: 16, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? DS.Palette.accentTeal : DS.Palette.secondaryLabel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: UIMetrics.rail, height: UIMetrics.railIconHit)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tip)
                .accessibilityLabel(tip)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, 6)
        .frame(width: UIMetrics.rail)
        .frame(maxHeight: .infinity)
        .background(DS.Palette.chrome)
        .hairline(.trailing)
    }
}

/// Trạng thái trống song ngữ khi chọn Table / Model / DAX / TMDL trên tệp chưa có mô hình dữ liệu (FR-016).
struct EmptyViewState: View {
    @Bindable var state: DocumentState

    static let message = Bilingual(
        vi: "Chưa có dữ liệu. Thêm dữ liệu để dùng chế độ này.",
        en: "No data yet. Add data to use this view."
    )

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: state.mode.symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DS.Palette.tertiaryLabel)
            Text(Self.message.localized)
                .font(DS.Typeface.bodyLarge)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .multilineTextAlignment(.center)
            Button(bi("Lấy dữ liệu…", "Get data…")) {
                state.showGetData()
            }
            .buttonStyle(PrimaryButtonStyle(compact: false))
            .disabled(state.getDataBlocker != nil)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.canvasWell)
    }
}
