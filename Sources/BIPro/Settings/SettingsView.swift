import AppKit
import SwiftUI

/// Cửa sổ Cài đặt ứng dụng (⌘, hoặc nút bánh răng ở Rail trái).
struct SettingsView: View {
    enum SectionTab: String, CaseIterable, Identifiable {
        case general, editing, data
        var id: String { rawValue }
    }

    @Bindable var preferences: AppPreferences
    var backupDirectory: URL = DocumentSaver.defaultBackupDirectory()
    @State private var tab: SectionTab = .general

    var body: some View {
        let lang = preferences.effectiveLanguage
        VStack(spacing: 0) {
            // Header + Tab switcher
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Palette.accent)
                    Text(L10n.string(.settingsTitle, language: lang))
                        .font(DS.Typeface.headlineMedium)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                }
                SegmentedPill(selection: $tab, options: [
                    .init(value: .general, title: L10n.string(.settingsTabGeneral, language: lang), symbol: "gearshape"),
                    .init(value: .editing, title: L10n.string(.settingsTabEditing, language: lang), symbol: "square.grid.2x2"),
                    .init(value: .data, title: L10n.string(.settingsTabData, language: lang), symbol: "externaldrive"),
                ], fill: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(DS.Palette.chrome)
            .hairline(.bottom)

            // Tab body
            VStack(alignment: .leading, spacing: 14) {
                switch tab {
                case .general: generalTab(lang: lang)
                case .editing: editingTab(lang: lang)
                case .data: dataTab(lang: lang)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DS.Palette.backdrop)
        }
        .frame(width: 540, height: 370)
        .preferredColorScheme(preferences.preferredColorScheme)
    }

    // MARK: - Card container

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
    }

    // MARK: - Chung

    @ViewBuilder
    private func generalTab(lang: ResolvedLanguage) -> some View {
        card {
            HStack {
                Text(L10n.string(.settingsAppearanceLabel, language: lang))
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                SegmentedPill(selection: $preferences.appearance, options: [
                    .init(value: .system, title: L10n.string(.settingsAppearanceSystem, language: lang)),
                    .init(value: .light, title: L10n.string(.settingsAppearanceLight, language: lang)),
                    .init(value: .dark, title: L10n.string(.settingsAppearanceDark, language: lang)),
                ])
            }

            Divider()

            HStack {
                Text(L10n.string(.settingsLanguageLabel, language: lang))
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                SegmentedPill(selection: $preferences.language, options: [
                    .init(value: .system, title: L10n.string(.settingsLanguageSystem, language: lang)),
                    .init(value: .vi, title: L10n.string(.settingsLanguageVi, language: lang)),
                    .init(value: .en, title: L10n.string(.settingsLanguageEn, language: lang)),
                ])
            }

            Text(L10n.string(.settingsLanguageNote, language: lang))
                .font(DS.Typeface.label)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }

        card {
            HStack {
                Text(L10n.string(.settingsOnboardingLabel, language: lang))
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Button(L10n.string(.settingsShowOnboardingButton, language: lang)) {
                    preferences.requestShowOnboarding()
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.string(.settingsResetDefaults, language: lang)) {
                    preferences.resetToDefaults()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: - Chỉnh sửa

    @ViewBuilder
    private func editingTab(lang: ResolvedLanguage) -> some View {
        card {
            HStack {
                Text(L10n.string(.settingsSnapToGridLabel, language: lang))
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Button { preferences.snapToGrid.toggle() } label: {
                    SwitchMark(isOn: preferences.snapToGrid)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string(.settingsSnapToGridLabel, language: lang))
            }

            Divider()

            HStack {
                Text(L10n.string(.settingsGridSizeLabel, language: lang))
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                SegmentedPill(selection: $preferences.gridSize, options: AppPreferences.allowedGridSizes.map { size in
                    .init(value: size, title: L10n.format(.settingsGridSizeFormat, language: lang, size))
                })
                .opacity(preferences.snapToGrid ? 1 : 0.5)
                .disabled(!preferences.snapToGrid)
            }

            Text(L10n.string(.settingsSnapToGridHelp, language: lang))
                .font(DS.Typeface.label)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Dữ liệu & Sao lưu

    @ViewBuilder
    private func dataTab(lang: ResolvedLanguage) -> some View {
        card {
            Text(L10n.string(.settingsSQLiteDriverLabel, language: lang))
                .font(DS.Typeface.bodySmall.weight(.medium))
                .foregroundStyle(DS.Palette.label)

            HStack(spacing: 8) {
                TextField(SQLiteODBC.defaultDriver, text: $preferences.sqliteOdbcDriver)
                    .textFieldStyle(.plain)
                    .font(DS.Typeface.bodySmall)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.searchFill))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator))

                Menu {
                    ForEach(SQLiteODBC.commonDrivers, id: \.self) { driver in
                        Button(driver) { preferences.sqliteOdbcDriver = driver }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text(L10n.string(.settingsSQLiteDriverHelp, language: lang))
                .font(DS.Typeface.label)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }

        card {
            Text(L10n.string(.settingsBackupFolderLabel, language: lang))
                .font(DS.Typeface.bodySmall.weight(.medium))
                .foregroundStyle(DS.Palette.label)

            HStack(spacing: 8) {
                Text(backupDirectory.path)
                    .font(DS.Typeface.mono)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.string(.settingsOpenInFinder, language: lang)) {
                    openBackupFolder()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func openBackupFolder() {
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupDirectory)
    }
}
