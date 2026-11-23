import SwiftUI

/// Trạng thái nhóm tuỳ chọn "Cards" trên pane Properties của Model view (`v_model_1.png`, T077).
/// Mặc định theo Power BI Desktop: No / Yes / No.
struct ModelCardsSettings: Equatable {
    var showDatabaseInHeader: Bool = false
    var showRelatedWhenCollapsed: Bool = true
    var pinRelatedFieldsToTop: Bool = false
}

struct ModelCardOption: Identifiable, Equatable {
    let id: String
    let title: Bilingual
    let defaultValue: Bool
}

/// Pane Properties nằm giữa canvas sơ đồ và pane Data trong Model view (`v_model_1.png`).
struct ModelPropertiesPanel: View {
    static let cardOptions: [ModelCardOption] = [
        ModelCardOption(
            id: "showDatabaseInHeader",
            title: Bilingual(
                vi: "Hiện cơ sở dữ liệu ở tiêu đề khi áp dụng",
                en: "Show the database in the header when applicable"
            ),
            defaultValue: false
        ),
        ModelCardOption(
            id: "showRelatedWhenCollapsed",
            title: Bilingual(
                vi: "Hiện trường liên quan khi thu gọn thẻ",
                en: "Show related fields when card is collapsed"
            ),
            defaultValue: true
        ),
        ModelCardOption(
            id: "pinRelatedFieldsToTop",
            title: Bilingual(
                vi: "Ghim trường liên quan lên đầu thẻ",
                en: "Pin related fields to top of card"
            ),
            defaultValue: false
        ),
    ]

    @Binding var settings: ModelCardsSettings
    var collapse: (() -> Void)?
    @State private var cardsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: bi("Thuộc tính", "Properties"), symbol: "slider.horizontal.3", collapse: collapse)
                .hairline(.bottom)

            Button { cardsExpanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: cardsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .frame(width: 12)
                    Text(bi("Thẻ bảng", "Cards"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hairline(.bottom)

            if cardsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    toggleRow(Self.cardOptions[0], value: $settings.showDatabaseInHeader)
                    toggleRow(Self.cardOptions[1], value: $settings.showRelatedWhenCollapsed)
                    toggleRow(Self.cardOptions[2], value: $settings.pinRelatedFieldsToTop)
                }
                .padding(12)
            }

            Spacer(minLength: 0)
        }
        .background(DS.Palette.chrome)
    }

    private func toggleRow(_ option: ModelCardOption, value: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(option.title.localized)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.Palette.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { value.wrappedValue.toggle() } label: {
                    SwitchMark(isOn: value.wrappedValue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title.localized)
                .accessibilityValue(value.wrappedValue ? bi("Có", "Yes") : bi("Không", "No"))

                Text(value.wrappedValue ? bi("Có", "Yes") : bi("Không", "No"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
    }
}
