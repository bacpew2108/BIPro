import AppKit
import PBIXKit
import SwiftUI
import UniformTypeIdentifiers

/// Ô mẫu theme (chữ `Aa` + 6 cột màu hoặc gạch chéo mặc định) dùng chung cho dải 6 ô trên Ribbon Design và menu `Themes ▾`.
struct ThemeSwatchCard: View {
    let tile: RibbonMenus.ThemeTileSpec
    let active: Bool
    var width: CGFloat = 54
    var height: CGFloat = 42

    var body: some View {
        ZStack {
            if tile.isDefaultClear {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                Path { path in
                    path.move(to: CGPoint(x: 2, y: height - 2))
                    path.addLine(to: CGPoint(x: width - 2, y: 2))
                }
                .stroke(Color.gray.opacity(0.65), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: tile.backgroundHex) ?? .white)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aa")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: tile.foregroundHex) ?? .primary)
                    HStack(alignment: .bottom, spacing: 2) {
                        let heights: [CGFloat] = [14, 10, 12, 7, 11, 13]
                        ForEach(Array(tile.swatches.prefix(6).enumerated()), id: \.offset) { idx, hex in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(hex: hex) ?? .accentColor)
                                .frame(height: heights[idx % heights.count])
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(active ? DS.Palette.accentBrand : DS.Palette.separator, lineWidth: active ? 2 : 0.8)
        )
    }
}

/// Dải 6 ô mẫu theme + mũi tên mở rộng `Themes ▾` trên tab Design (T032, khớp `rb_design-2x.png`).
struct ThemesRibbonGallery: View {
    @Bindable var state: DocumentState
    @State private var showPopover = false

    private var visibleTiles: [RibbonMenus.ThemeTileSpec] {
        Array(RibbonMenus.themesPowerBITiles.prefix(6))
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(visibleTiles) { tile in
                    let active = isTileActive(tile)
                    Button {
                        applyTile(tile)
                    } label: {
                        ThemeSwatchCard(tile: tile, active: active, width: 54, height: 42)
                    }
                    .buttonStyle(.plain)
                    .help(tile.title.localized)
                    .accessibilityLabel(tile.title.localized)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)

            Divider()
                .frame(height: 46)

            Button {
                showPopover.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 20, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(bi("Mở danh sách chủ đề", "Open Themes menu"))
            .accessibilityLabel(bi("Mở danh sách chủ đề", "Open Themes menu"))
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                ThemePickerPopover(state: state, isPresented: $showPopover)
            }
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.Palette.separator, lineWidth: 0.75))
        .padding(.vertical, 6)
    }

    private func isTileActive(_ tile: RibbonMenus.ThemeTileSpec) -> Bool {
        guard let idx = tile.presetIndex, ThemeCatalog.presets.indices.contains(idx) else { return false }
        let preset = ThemeCatalog.presets[idx]
        return state.currentThemeName == preset.fileName || state.currentThemeName == preset.id
    }

    private func applyTile(_ tile: RibbonMenus.ThemeTileSpec) {
        let idx = tile.presetIndex ?? 0
        guard ThemeCatalog.presets.indices.contains(idx) else { return }
        let preset = ThemeCatalog.presets[idx]
        state.applyTheme(name: preset.fileName, data: preset.jsonData)
    }
}

/// Menu `Themes ▾` dạng Desktop (`dd_themes.png`): banner thông tin, "This report", "Power BI" (9 ô lưới 4 cột),
/// "Theme gallery" (vô hiệu), cùng Nhập/Xuất `.json` và hoàn tác ⌘Z như hiện có (T032).
struct ThemePickerPopover: View {
    @Bindable var state: DocumentState
    @Binding var isPresented: Bool
    @State private var errorMessage: String?

    private let gridColumns = Array(repeating: GridItem(.fixed(68), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Banner thông tin theo dd_themes.png
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(.top, 1)
                Text(RibbonMenus.themesBanner.localized)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(DS.Palette.chrome))

            // This report
            VStack(alignment: .leading, spacing: 6) {
                Text(bi("Báo cáo này", "This report"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.label)
                ThemeSwatchCard(tile: currentReportTile, active: true, width: 68, height: 42)
                    .accessibilityLabel(bi("Chủ đề báo cáo này", "This report theme"))
            }

            // Power BI (9 ô lưới 4 cột)
            VStack(alignment: .leading, spacing: 6) {
                Text(bi("Có sẵn", "Built-in"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.label)
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                    ForEach(RibbonMenus.themesPowerBITiles) { tile in
                        let active = isTileActive(tile)
                        Button {
                            applyTile(tile)
                            isPresented = false
                        } label: {
                            ThemeSwatchCard(tile: tile, active: active, width: 68, height: 42)
                        }
                        .buttonStyle(.plain)
                        .help(tile.title.localized)
                        .accessibilityLabel(tile.title.localized)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }

            Divider()

            // Theme gallery (vô hiệu) + Nhập / Xuất .json hiện có
            HStack(spacing: 8) {
                Button {} label: {
                    Label(bi("Thư viện chủ đề", "Theme gallery"), systemImage: "square.grid.2x2")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.45)
                .help(bi("BI Pro chưa hỗ trợ thư viện chủ đề trực tuyến", "Online theme gallery is not yet implemented in BI Pro"))

                Spacer()

                Button {
                    if let err = Self.importCustomTheme(state: state) {
                        errorMessage = err
                    } else {
                        isPresented = false
                    }
                } label: {
                    Label(bi("Nhập (.json)…", "Import…"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Self.exportCurrentTheme(state: state)
                } label: {
                    Label(bi("Xuất…", "Download…"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
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
        .frame(width: 326)
    }

    private var currentReportTile: RibbonMenus.ThemeTileSpec {
        let theme = state.workspace.theme
        return RibbonMenus.ThemeTileSpec(
            id: "thisReport",
            title: Bilingual(vi: "Báo cáo này", en: "This report"),
            isDefaultClear: false,
            backgroundHex: theme.background ?? "#FFFFFF",
            foregroundHex: theme.foreground ?? "#252423",
            swatches: theme.dataColors.isEmpty ? ThemeCatalog.presets[0].swatches : theme.dataColors,
            presetIndex: nil
        )
    }

    private func isTileActive(_ tile: RibbonMenus.ThemeTileSpec) -> Bool {
        guard let idx = tile.presetIndex, ThemeCatalog.presets.indices.contains(idx) else { return false }
        let preset = ThemeCatalog.presets[idx]
        return state.currentThemeName == preset.fileName || state.currentThemeName == preset.id
    }

    private func applyTile(_ tile: RibbonMenus.ThemeTileSpec) {
        let idx = tile.presetIndex ?? 0
        guard ThemeCatalog.presets.indices.contains(idx) else { return }
        let preset = ThemeCatalog.presets[idx]
        state.applyTheme(name: preset.fileName, data: preset.jsonData)
    }

    @MainActor
    @discardableResult
    static func importCustomTheme(state: DocumentState) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = bi("Chọn tệp chủ đề Power BI (.json)", "Select Power BI Theme (.json)")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            if let reason = ThemeCatalog.validateThemeJSON(data) {
                return reason
            }
            state.applyTheme(name: url.lastPathComponent, data: data)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @MainActor
    static func exportCurrentTheme(state: DocumentState) {
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
