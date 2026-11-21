import AppKit
import PBIXKit
import SwiftUI
import UniformTypeIdentifiers

/// Popover chọn chủ đề báo cáo (Wave 3B / T017): 6 preset dựng sẵn + Nhập chủ đề `.json` + Xuất chủ đề hiện tại.
struct ThemePickerPopover: View {
    @Bindable var state: DocumentState
    @Binding var isPresented: Bool
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bi("Chủ đề báo cáo", "Report Themes"))
                .font(DS.Typeface.headlineSmall)
                .foregroundStyle(DS.Palette.label)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ThemeCatalog.presets) { preset in
                    let active = state.currentThemeName == preset.fileName || state.currentThemeName == preset.id
                    Button {
                        state.applyTheme(name: preset.fileName, data: preset.jsonData)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 2) {
                                ForEach(Array(preset.swatches.prefix(6).enumerated()), id: \.offset) { _, hex in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: hex) ?? .accentColor)
                                        .frame(height: 16)
                                }
                            }
                            Text(preset.localizedTitle)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                                .foregroundStyle(DS.Palette.label)
                                .lineLimit(1)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.canvas))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(active ? DS.Palette.accent : DS.Palette.separator, lineWidth: active ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    importCustomTheme()
                } label: {
                    Label(bi("Nhập chủ đề (.json)…", "Import theme (.json)…"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    exportCurrentTheme()
                } label: {
                    Label(bi("Xuất chủ đề…", "Export theme…"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.danger)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func importCustomTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = bi("Chọn tệp chủ đề Power BI (.json)", "Select Power BI Theme (.json)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            if let reason = ThemeCatalog.validateThemeJSON(data) {
                errorMessage = reason
                return
            }
            let fileName = url.lastPathComponent
            state.applyTheme(name: fileName, data: data)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCurrentTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = state.currentThemeName ?? "BIProTheme.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let theme = state.workspace.theme
        let obj: [String: Any] = [
            "name": state.currentThemeName ?? "BIProTheme",
            "dataColors": theme.dataColors,
            "background": theme.background ?? "#FFFFFF",
            "foreground": theme.foreground ?? "#252423",
            "tableAccent": theme.dataColors.first ?? "#118DFF",
            "good": theme.good ?? "#1AAB40",
            "neutral": theme.neutral ?? "#D9B300",
            "bad": theme.bad ?? "#D64554",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}
