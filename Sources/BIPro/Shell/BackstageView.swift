import AppKit
import SwiftUI

/// Danh mục mục menu trái của File Backstage theo đúng thứ tự Power BI Desktop (`f_file.png`), ẩn Sign out.
struct BackstageItem: Identifiable, Equatable {
    enum Group { case top, middle, bottom }

    let id: String
    let group: Group
    let title: Bilingual
    let symbol: String?
    let isSupported: Bool
    let disabledReason: Bilingual?

    static let all: [BackstageItem] = [
        // Nhóm 1
        BackstageItem(id: "home", group: .top, title: Bilingual(vi: "Trang chủ", en: "Home"), symbol: "house", isSupported: true, disabledReason: nil),
        BackstageItem(id: "open", group: .top, title: Bilingual(vi: "Mở", en: "Open"), symbol: "folder", isSupported: true, disabledReason: nil),
        // Nhóm 2
        BackstageItem(id: "save", group: .middle, title: Bilingual(vi: "Lưu", en: "Save"), symbol: nil, isSupported: true, disabledReason: nil),
        BackstageItem(id: "saveAs", group: .middle, title: Bilingual(vi: "Lưu thành", en: "Save as"), symbol: nil, isSupported: true, disabledReason: nil),
        BackstageItem(
            id: "share",
            group: .middle,
            title: Bilingual(vi: "Chia sẻ", en: "Share"),
            symbol: nil,
            isSupported: false,
            disabledReason: Bilingual(vi: "Chia sẻ cần Power BI Service, chưa hỗ trợ trên BI Pro.", en: "Share requires Power BI Service and is not supported in BI Pro yet.")
        ),
        BackstageItem(id: "getData", group: .middle, title: Bilingual(vi: "Lấy dữ liệu", en: "Get data"), symbol: nil, isSupported: true, disabledReason: nil),
        BackstageItem(
            id: "importFile",
            group: .middle,
            title: Bilingual(vi: "Nhập", en: "Import"),
            symbol: nil,
            isSupported: false,
            disabledReason: Bilingual(vi: "Nhập mẫu Power Query / Power BI Template chưa hỗ trợ trên BI Pro.", en: "Import template is not supported in BI Pro yet.")
        ),
        BackstageItem(id: "export", group: .middle, title: Bilingual(vi: "Xuất", en: "Export"), symbol: nil, isSupported: true, disabledReason: nil),
        BackstageItem(
            id: "publish",
            group: .middle,
            title: Bilingual(vi: "Xuất bản", en: "Publish"),
            symbol: nil,
            isSupported: false,
            disabledReason: Bilingual(vi: "Xuất bản lên Power BI Service chưa hỗ trợ trên BI Pro.", en: "Publish to Power BI Service is not supported in BI Pro yet.")
        ),
        // Nhóm 3 (Sign out ẩn)
        BackstageItem(id: "optionsAndSettings", group: .bottom, title: Bilingual(vi: "Tuỳ chọn và cài đặt", en: "Options and settings"), symbol: nil, isSupported: true, disabledReason: nil),
        BackstageItem(id: "about", group: .bottom, title: Bilingual(vi: "Giới thiệu", en: "About"), symbol: nil, isSupported: true, disabledReason: nil),
    ]
}

/// Màn hình File Backstage khi bấm tab `File` (`state.showBackstage == true`), bám sát `f_file.png`.
struct BackstageView: View {
    @Bindable var state: DocumentState
    var initialSection: String = "home"
    var recentEntries: [RecentFileEntry]? = nil
    @Environment(\.openSettings) private var openSettings
    @State private var selectedID: String = "home"
    @State private var didInit = false
    @State private var exportNotice: String?

    private var activeID: String { didInit ? selectedID : initialSection }

    var body: some View {
        HStack(spacing: 0) {
            leftMenu
            rightDetail
        }
        .background(DS.Palette.canvas)
        .onAppear {
            if !didInit { selectedID = initialSection; didInit = true }
        }
    }

    private var leftMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { state.showBackstage = false } label: {
                Image(systemName: "arrow.left.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(DS.Palette.accentBrand)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .help(bi("Quay lại báo cáo (Esc)", "Back to report (Esc)"))
            .accessibilityLabel(bi("Quay lại báo cáo", "Back to report"))

            ForEach(BackstageItem.all.filter { $0.group == .top }) { item in
                menuRow(item)
            }
            Divider().padding(.horizontal, 12).padding(.vertical, 6)
            ForEach(BackstageItem.all.filter { $0.group == .middle }) { item in
                menuRow(item)
            }
            Spacer()
            Divider().padding(.horizontal, 12).padding(.vertical, 6)
            ForEach(BackstageItem.all.filter { $0.group == .bottom }) { item in
                menuRow(item)
            }
        }
        .padding(.bottom, 14)
        .frame(width: 216)
        .frame(maxHeight: .infinity)
        .background(DS.Palette.chrome)
        .hairline(.trailing)
    }

    private func menuRow(_ item: BackstageItem) -> some View {
        let selected = activeID == item.id
        return Button { handleSelect(item) } label: {
            HStack(spacing: 10) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? DS.Palette.accentBrand : DS.Palette.secondaryLabel)
                        .frame(width: 18)
                }
                Text(item.title.localized)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(item.isSupported ? (selected ? DS.Palette.accentBrand : DS.Palette.label) : DS.Palette.tertiaryLabel)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, item.symbol == nil ? 28 : 14)
            .padding(.trailing, 12)
            .frame(height: 34)
            .background(selected ? DS.Palette.selectionSoft : .clear)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle().fill(DS.Palette.accentBrand).frame(width: 3, height: 22)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isSupported)
        .opacity(item.isSupported ? 1 : 0.48)
        .help(item.disabledReason?.localized ?? item.title.localized)
        .accessibilityLabel(item.title.localized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func handleSelect(_ item: BackstageItem) {
        guard item.isSupported else { return }
        switch item.id {
        case "open":
            state.showBackstage = false
            NSDocumentController.shared.openDocument(nil)
        case "save":
            _ = state.save()
            state.showBackstage = false
        case "getData":
            state.showBackstage = false
            state.showGetData()
        default:
            selectedID = item.id
            didInit = true
        }
    }

    @ViewBuilder private var rightDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch activeID {
            case "saveAs":
                saveAsDetail
            case "export":
                exportDetail
            case "optionsAndSettings":
                optionsAndSettingsDetail
            case "about":
                aboutDetail
            default:
                homeDetail
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var homeDetail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(bi("Mới", "New"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.label)
                Button {
                    state.showBackstage = false
                    UntitledDocuments.openNew()
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: "#E6A817")!)
                        Text(bi("Báo cáo trống", "Blank report"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.label)
                    }
                    .frame(width: 120, height: 112)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.canvas))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
            }

            RecentFilesList(entries: recentEntries ?? RecentFileEntry.load()) { url in
                state.showBackstage = false
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
    }

    private var saveAsDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(bi("Lưu bản sao", "Save a copy"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Palette.label)
            Text(bi("Lưu báo cáo hiện tại thành một tệp .pbix mới trên máy Mac.",
                    "Save the current report as a new .pbix file on this Mac."))
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.secondaryLabel)
            Button(bi("Duyệt máy này…", "Browse this device…")) {
                state.showBackstage = false
                _ = state.saveAs()
            }
            .buttonStyle(PrimaryButtonStyle(compact: false))
        }
    }

    private var exportDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(bi("Xuất", "Export"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Palette.label)

            exportActionCard(
                symbol: "doc.richtext",
                title: tr(.exportPDFItem),
                detail: bi("Xuất trang hiện tại hoặc toàn bộ báo cáo sang tệp PDF.", "Export the current page or entire report to PDF."),
                disabled: state.pages.isEmpty
            ) {
                state.showBackstage = false
                state.openExportSheet(.pdf)
            }

            exportActionCard(
                symbol: "photo",
                title: tr(.exportPNGItem),
                detail: bi("Xuất trang báo cáo hiện tại sang ảnh PNG độ phân giải cao.", "Export the current report page as a high-resolution PNG."),
                disabled: state.page == nil
            ) {
                state.showBackstage = false
                state.openExportSheet(.png)
            }

            exportActionCard(
                symbol: "tablecells",
                title: tr(.exportCSVItem),
                detail: state.exportCSVDisabledReason ?? bi("Xuất bảng dữ liệu của visual đang chọn sang CSV.", "Export data of the selected visual to CSV."),
                disabled: state.exportCSVDisabledReason != nil
            ) {
                state.showBackstage = false
                state.exportSelectedVisualToCSV()
            }

            exportActionCard(
                symbol: "chevron.left.forwardslash.chevron.right",
                title: tr(.ribbonExportTMDL),
                detail: bi("Xuất toàn bộ kịch bản mô hình TMDL ra một thư mục cục bộ.", "Export all semantic model TMDL scripts to a local folder."),
                disabled: state.workspace.tmdlDocuments.isEmpty
            ) {
                exportTMDLFolder()
            }

            if let exportNotice {
                Text(exportNotice)
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.accentBrand)
            }
        }
    }

    private func exportActionCard(symbol: String, title: String, detail: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(disabled ? DS.Palette.tertiaryLabel : DS.Palette.accentBrand)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(disabled ? DS.Palette.tertiaryLabel : DS.Palette.label)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(14)
            .frame(maxWidth: 540)
            .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.canvas))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func exportTMDLFolder() {
        let docs = state.workspace.tmdlDocuments
        guard !docs.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = bi("Xuất TMDL", "Export TMDL")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            for doc in docs {
                let target = folder.appendingPathComponent(doc.path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try doc.text.write(to: target, atomically: true, encoding: .utf8)
            }
            exportNotice = bi("Đã xuất \(docs.count) tệp TMDL vào \(folder.lastPathComponent).",
                              "Exported \(docs.count) TMDL files to \(folder.lastPathComponent).")
        } catch {
            exportNotice = bi("Lỗi xuất TMDL: \(error.localizedDescription)", "TMDL export failed: \(error.localizedDescription)")
        }
    }

    private var optionsAndSettingsDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(bi("Tuỳ chọn và cài đặt", "Options and settings"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Palette.label)
            exportActionCard(
                symbol: "slider.horizontal.3",
                title: bi("Tuỳ chọn", "Options"),
                detail: bi("Cấu hình nạp dữ liệu, ngôn ngữ, giao diện và tuỳ chọn tệp hiện tại.", "Configure data load, regional settings, appearance, and current file options."),
                disabled: false
            ) {
                state.showBackstage = false
                state.showFileOptions = true
            }
            exportActionCard(
                symbol: "cylinder",
                title: bi("Cài đặt nguồn dữ liệu", "Data source settings"),
                detail: bi("Mở cài đặt kết nối và trình điều khiển nguồn dữ liệu của ứng dụng.", "Open application data source and driver settings."),
                disabled: false
            ) {
                state.showBackstage = false
                openSettings()
            }
        }
    }

    private var aboutDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(bi("Giới thiệu BI Pro", "About BI Pro"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Palette.label)
            Text(bi("Phiên bản 1.3.0 (macOS Native · SwiftUI + VertiPaq + DAX/M Engine)",
                    "Version 1.3.0 (macOS Native · SwiftUI + VertiPaq + DAX/M Engine)"))
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.secondaryLabel)
            Text(bi("Tệp đang mở: \(state.fileName)", "Current document: \(state.fileName)"))
                .font(DS.Typeface.bodySmall)
                .foregroundStyle(DS.Palette.tertiaryLabel)
        }
    }
}
