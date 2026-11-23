import AppKit
import SwiftUI

/// Thẻ khởi tạo trên màn hình khởi động Power BI Desktop 2.159 (6 thẻ).
struct StartEntry: Identifiable, Equatable {
    let id: String
    let title: Bilingual
    let symbol: String
    let tintHex: String
    let isSupported: Bool
    let disabledReason: Bilingual?

    static let all: [StartEntry] = [
        StartEntry(
            id: "blankReport",
            title: Bilingual(vi: "Báo cáo trống", en: "Blank report"),
            symbol: "doc.richtext",
            tintHex: "#E6A817",
            isSupported: true,
            disabledReason: nil
        ),
        StartEntry(
            id: "oneLake",
            title: Bilingual(vi: "Danh mục OneLake", en: "OneLake catalog"),
            symbol: "externaldrive.connected.to.line.below",
            tintHex: "#5B4BDB",
            isSupported: false,
            disabledReason: Bilingual(
                vi: "OneLake catalog yêu cầu đăng nhập Microsoft Fabric, chưa hỗ trợ trên BI Pro.",
                en: "OneLake catalog requires Microsoft Fabric and is not supported in BI Pro yet."
            )
        ),
        StartEntry(
            id: "excel",
            title: Bilingual(vi: "Sổ tính Excel", en: "Excel workbook"),
            symbol: "tablecells",
            tintHex: "#1D6F42",
            isSupported: true,
            disabledReason: nil
        ),
        StartEntry(
            id: "sqlServer",
            title: Bilingual(vi: "SQL Server", en: "SQL Server"),
            symbol: "server.rack",
            tintHex: "#2563EB",
            isSupported: true,
            disabledReason: nil
        ),
        StartEntry(
            id: "sampleData",
            title: Bilingual(vi: "Học với dữ liệu mẫu", en: "Learn with sample data"),
            symbol: "book.closed",
            tintHex: "#6B7280",
            isSupported: false,
            disabledReason: Bilingual(
                vi: "BI Pro chưa đi kèm bộ dữ liệu mẫu trực tuyến.",
                en: "BI Pro does not bundle online sample datasets yet."
            )
        ),
        StartEntry(
            id: "otherSources",
            title: Bilingual(vi: "Lấy dữ liệu từ nguồn khác", en: "Get data from other sources"),
            symbol: "cylinder.split.1x2",
            tintHex: "#5B4BDB",
            isSupported: true,
            disabledReason: nil
        ),
    ]
}

/// Màn hình khởi động khi mở app không kèm `.pbix`, bám sát Power BI Desktop 2.159.
struct StartScreen: View {
    var recentEntries: [RecentFileEntry]? = nil
    var onStart: (StartEntry) -> Void = { UntitledDocuments.start(entryID: $0.id) }
    var onOpenFile: () -> Void = { NSDocumentController.shared.openDocument(nil) }
    var onOpenURL: (URL) -> Void = { url in
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
    var onDismiss: () -> Void = {}

    @Environment(\.openSettings) private var openSettings
    @State private var showOptions = false
    @State private var showAbout = false

    private var entries: [RecentFileEntry] {
        recentEntries ?? RecentFileEntry.load()
    }

    var body: some View {
        HStack(spacing: 0) {
            leftRail
            mainContent
        }
        .background(DS.Palette.canvas)
        .sheet(isPresented: $showOptions) {
            OptionsDialog(
                options: FileOptions(autoDateTime: true, autodetectRelationships: true),
                autoDateTimeBlocker: bi("Mở một báo cáo để sửa tuỳ chọn tệp hiện tại.", "Open a report to edit current file options."),
                onCommit: { _ in nil },
                onCancel: { showOptions = false }
            )
        }
        .alert(bi("Giới thiệu BI Pro", "About BI Pro"), isPresented: $showAbout) {
            Button(tr(.ok), role: .cancel) {}
        } message: {
            Text(bi("BI Pro 1.3.0 — Ứng dụng phân tích .pbix native macOS.",
                    "BI Pro 1.3.0 — Native macOS .pbix analytics workspace."))
        }
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 36)
            railRow(title: bi("Trang chủ", "Home"), symbol: "house", active: true) {}
            railRow(title: bi("Mở", "Open"), symbol: "folder", active: false) {
                onOpenFile()
            }
            Spacer()
            Divider().padding(.vertical, 6)
            railRow(title: bi("Tuỳ chọn và cài đặt", "Options and settings"), symbol: "gearshape", active: false) {
                showOptions = true
            }
            railRow(title: bi("Giới thiệu", "About"), symbol: "info.circle", active: false) {
                showAbout = true
            }
        }
        .padding(.vertical, 12)
        .frame(width: 204)
        .frame(maxHeight: .infinity)
        .background(DS.Palette.chrome)
        .hairline(.trailing)
    }

    private func railRow(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(active ? DS.Palette.accentBrand : DS.Palette.secondaryLabel)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? DS.Palette.accentBrand : DS.Palette.label)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(active ? DS.Palette.selectionSoft : .clear)
            .overlay(alignment: .leading) {
                if active {
                    Rectangle().fill(DS.Palette.accentBrand).frame(width: 3, height: 22)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text(bi("Chọn nguồn dữ liệu hoặc bắt đầu với báo cáo trống",
                        "Select a data source or start with a blank report"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.Palette.label)

                HStack(spacing: 12) {
                    ForEach(StartEntry.all) { entry in
                        startCard(entry)
                    }
                }
            }

            RecentFilesList(entries: entries) { url in
                onOpenURL(url)
                onDismiss()
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 36)
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func startCard(_ entry: StartEntry) -> some View {
        let tint = Color(hex: entry.tintHex) ?? DS.Palette.accentBrand
        return Button {
            guard entry.isSupported else { return }
            onStart(entry)
            onDismiss()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(entry.isSupported ? tint : DS.Palette.tertiaryLabel)
                Text(entry.title.localized)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(entry.isSupported ? DS.Palette.label : DS.Palette.tertiaryLabel)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: 210)
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(DS.Palette.canvas))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Palette.separator))
            .shadow(color: .black.opacity(entry.isSupported ? 0.06 : 0.02), radius: 3, y: 1)
            .opacity(entry.isSupported ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!entry.isSupported)
        .help(entry.disabledReason?.localized ?? entry.title.localized)
        .accessibilityLabel(entry.title.localized)
    }
}
