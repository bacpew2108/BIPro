import SwiftUI

/// Hộp thoại hướng dẫn lần đầu 3 bước ngắn gọn (US6, FR-051).
struct OnboardingView: View {
    @Bindable var preferences: AppPreferences
    var onDismiss: () -> Void

    @State private var step = 0

    private struct StepInfo {
        let symbol: String
        let accent: Color
        let titleKey: L10n.Key
        let bodyKey: L10n.Key
    }

    private static let steps: [StepInfo] = [
        StepInfo(symbol: "doc.richtext.fill", accent: DS.Palette.accent,
                 titleKey: .onboardingStep1Title, bodyKey: .onboardingStep1Body),
        StepInfo(symbol: "rectangle.3.group.fill", accent: DS.Palette.indigo,
                 titleKey: .onboardingStep2Title, bodyKey: .onboardingStep2Body),
        StepInfo(symbol: "square.and.arrow.up.fill", accent: DS.Palette.success,
                 titleKey: .onboardingStep3Title, bodyKey: .onboardingStep3Body),
    ]

    var body: some View {
        let lang = preferences.effectiveLanguage
        let current = Self.steps[step]

        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                HStack {
                    Badge(text: L10n.string(.onboardingBadge, language: lang), color: DS.Palette.accent)
                    Spacer()
                    Text(L10n.format(.onboardingStepIndicatorFormat, language: lang, step + 1, Self.steps.count))
                        .font(DS.Typeface.label)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: [current.accent.opacity(0.18), current.accent.opacity(0.06)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(current.accent.opacity(0.25), lineWidth: 1))
                    Image(systemName: current.symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(current.accent)
                }
                .padding(.top, 8)

                Text(L10n.string(.onboardingWindowTitle, language: lang))
                    .font(DS.Typeface.headlineLarge)
                    .foregroundStyle(DS.Palette.label)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 16)

            // Step content card
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string(current.titleKey, language: lang))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Text(L10n.string(current.bodyKey, language: lang))
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.large).fill(DS.Palette.canvas))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Palette.separator))
            .padding(.horizontal, 28)

            // Step dots
            HStack(spacing: 8) {
                ForEach(0..<Self.steps.count, id: \.self) { idx in
                    Circle()
                        .fill(idx == step ? DS.Palette.accent : DS.Palette.checkboxBorder)
                        .frame(width: idx == step ? 8 : 6, height: idx == step ? 8 : 6)
                        .onTapGesture { step = idx }
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 16)

            // Footer actions
            HStack(spacing: 10) {
                Button(L10n.string(.onboardingSkip, language: lang)) {
                    finish()
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Spacer()

                if step > 0 {
                    Button(L10n.string(.onboardingBack, language: lang)) {
                        step -= 1
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if step + 1 < Self.steps.count {
                    Button(L10n.string(.onboardingNext, language: lang)) {
                        step += 1
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: false))
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.string(.onboardingStart, language: lang)) {
                        finish()
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: false))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(DS.Palette.chrome)
            .hairline(.top)
        }
        .frame(width: 540, height: 390)
        .background(DS.Palette.backdrop)
        .preferredColorScheme(preferences.preferredColorScheme)
    }

    private func finish() {
        preferences.onboardingSeen = true
        onDismiss()
    }
}
