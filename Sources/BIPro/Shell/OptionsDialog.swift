import SwiftUI

/// Danh mục mục cài đặt hộp Options theo `docs/PHASE_H_UI_PARITY.md` mục 3.10 và `dd_options_dialog.png`.
struct OptionsSection: Identifiable, Equatable {
    enum Scope: Equatable { case global, currentFile }

    let id: String
    let scope: Scope
    let title: Bilingual
    let available: Bool

    static let global: [OptionsSection] = [
        OptionsSection(id: "global.dataLoad", scope: .global, title: Bilingual(vi: "Nạp dữ liệu", en: "Data Load"), available: true),
        OptionsSection(id: "global.pqEditor", scope: .global, title: Bilingual(vi: "Trình sửa Power Query", en: "Power Query Editor"), available: false),
        OptionsSection(id: "global.directQuery", scope: .global, title: Bilingual(vi: "DirectQuery", en: "DirectQuery"), available: false),
        OptionsSection(id: "global.rScripting", scope: .global, title: Bilingual(vi: "Kịch bản R", en: "R scripting"), available: false),
        OptionsSection(id: "global.pythonScripting", scope: .global, title: Bilingual(vi: "Kịch bản Python", en: "Python scripting"), available: false),
        OptionsSection(id: "global.security", scope: .global, title: Bilingual(vi: "Bảo mật", en: "Security"), available: false),
        OptionsSection(id: "global.privacy", scope: .global, title: Bilingual(vi: "Quyền riêng tư", en: "Privacy"), available: false),
        OptionsSection(id: "global.regional", scope: .global, title: Bilingual(vi: "Cài đặt vùng", en: "Regional Settings"), available: true),
        OptionsSection(id: "global.updates", scope: .global, title: Bilingual(vi: "Cập nhật", en: "Updates"), available: false),
        OptionsSection(id: "global.usageData", scope: .global, title: Bilingual(vi: "Dữ liệu sử dụng", en: "Usage Data"), available: false),
        OptionsSection(id: "global.diagnostics", scope: .global, title: Bilingual(vi: "Chẩn đoán", en: "Diagnostics"), available: false),
        OptionsSection(id: "global.previewFeatures", scope: .global, title: Bilingual(vi: "Tính năng xem trước", en: "Preview features"), available: false),
        OptionsSection(id: "global.saveRecover", scope: .global, title: Bilingual(vi: "Lưu và khôi phục", en: "Save and Recover"), available: false),
        OptionsSection(id: "global.reportSettings", scope: .global, title: Bilingual(vi: "Cài đặt báo cáo", en: "Report settings"), available: true),
        OptionsSection(id: "global.copilot", scope: .global, title: Bilingual(vi: "Copilot (xem trước)", en: "Copilot (preview)"), available: false),
    ]

    static let currentFile: [OptionsSection] = [
        OptionsSection(id: "file.dataLoad", scope: .currentFile, title: Bilingual(vi: "Nạp dữ liệu", en: "Data Load"), available: true),
        OptionsSection(id: "file.regional", scope: .currentFile, title: Bilingual(vi: "Cài đặt vùng", en: "Regional Settings"), available: false),
        OptionsSection(id: "file.privacy", scope: .currentFile, title: Bilingual(vi: "Quyền riêng tư", en: "Privacy"), available: false),
        OptionsSection(id: "file.autoRecovery", scope: .currentFile, title: Bilingual(vi: "Tự khôi phục", en: "Auto recovery"), available: false),
        OptionsSection(id: "file.publishedModel", scope: .currentFile, title: Bilingual(vi: "Mô hình đã xuất bản", en: "Published semantic model settings"), available: false),
        OptionsSection(id: "file.queryReduction", scope: .currentFile, title: Bilingual(vi: "Giảm truy vấn", en: "Query reduction"), available: false),
        OptionsSection(id: "file.reportSettings", scope: .currentFile, title: Bilingual(vi: "Cài đặt báo cáo", en: "Report settings"), available: false),
    ]
}

/// Hộp thoại Options (≈ 770×600) khớp Power BI Desktop (`dd_options_dialog.png`), nối với `FileOptions` và `AppPreferences`.
struct OptionsDialog: View {
    @State var options: FileOptions
    var autoDateTimeBlocker: String?
    var onCommit: (FileOptions) -> String?
    var onCancel: () -> Void

    @Environment(\.isSnapshotRender) private var isSnapshotRender
    @State private var selectedSectionID: String = "file.dataLoad"
    @State private var message: String?
    private let preferences = AppPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(bi("Tuỳ chọn", "Options"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr(.cancel))
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .hairline(.bottom)

            // Body: Left sidebar + Right content
            HStack(spacing: 0) {
                sidebar
                detailPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer: OK (accentBrand) + Cancel
            HStack(spacing: 10) {
                if let message {
                    Text(message)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.danger)
                        .lineLimit(2)
                }
                Spacer()
                Button(tr(.ok)) {
                    if let refusal = onCommit(options) {
                        message = refusal
                    } else {
                        onCancel()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)

                Button(tr(.cancel), role: .cancel, action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .hairline(.top)
        }
        .frame(width: 770, height: 600)
        .background(DS.Palette.canvas)
    }

    private var sidebar: some View {
        Group {
            if isSnapshotRender {
                sidebarList
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    sidebarList
                }
            }
        }
        .frame(width: 252)
        .background(DS.Palette.chrome)
        .hairline(.trailing)
    }

    private var sidebarList: some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionHeader(bi("TOÀN CỤC", "GLOBAL"))
            ForEach(OptionsSection.global) { section in
                sidebarRow(section)
            }
            sectionHeader(bi("TỆP HIỆN TẠI", "CURRENT FILE"))
                .padding(.top, 6)
            ForEach(OptionsSection.currentFile) { section in
                sidebarRow(section)
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DS.Palette.secondaryLabel)
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
    }

    private func sidebarRow(_ section: OptionsSection) -> some View {
        let selected = selectedSectionID == section.id
        return Button {
            if section.available { selectedSectionID = section.id }
        } label: {
            Text(section.title.localized)
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(section.available ? DS.Palette.label : DS.Palette.tertiaryLabel)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 20)
                .background(selected ? DS.Palette.selectionSoft : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!section.available)
        .opacity(section.available ? 1 : 0.55)
        .help(section.available ? section.title.localized : bi("Mục này chưa hỗ trợ trên BI Pro.", "Not supported in BI Pro yet."))
        .accessibilityLabel(section.title.localized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var detailPane: some View {
        Group {
            if isSnapshotRender {
                detailContent
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    detailContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var detailContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch selectedSectionID {
            case "global.regional":
                regionalSettingsContent
            case "global.reportSettings":
                reportSettingsContent
            default:
                dataLoadContent
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dataLoadContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            optionGroup(bi("Phát hiện kiểu dữ liệu", "Type Detection")) {
                radioRow(bi("Phát hiện kiểu cột và tiêu đề theo cài đặt từng tệp",
                            "Detect column types and headers for unstructured sources according to each file's setting"), selected: true)
            }

            optionGroup(bi("Dữ liệu nền", "Background Data")) {
                radioRow(bi("Cho phép tải bản xem trước dữ liệu trong nền theo từng tệp",
                            "Allow data previews to download in the background according to each file's setting"), selected: true)
            }

            optionGroup(bi("Trí tuệ thời gian", "Time intelligence")) {
                checkboxRow(title: tr(.autoDateTimeLabel), isOn: $options.autoDateTime, disabled: autoDateTimeBlocker != nil)
                if let autoDateTimeBlocker {
                    Text(autoDateTimeBlocker)
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }

            optionGroup(bi("Quan hệ", "Relationships")) {
                checkboxRow(title: tr(.autoDetectRelLabel), isOn: $options.autodetectRelationships, disabled: false)
            }

            optionGroup(bi("Hành vi DAX", "DAX Behavior")) {
                checkboxRow(title: bi("Đặt ValueFilterBehavior thành Independent cho tệp mới",
                                      "Set ValueFilterBehavior to Independent for new files"),
                            isOn: .constant(true), disabled: true)
            }
        }
    }

    private var regionalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            optionGroup(bi("Ngôn ngữ giao diện", "Application language")) {
                ForEach(AppLanguage.allCases) { lang in
                    let label = switch lang {
                    case .system: bi("Theo hệ thống", "System default")
                    case .vi: "Tiếng Việt"
                    case .en: "English"
                    }
                    Button { preferences.language = lang } label: {
                        radioRow(label, selected: preferences.language == lang)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var reportSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            optionGroup(bi("Chế độ hiển thị", "Appearance")) {
                ForEach(AppAppearance.allCases) { item in
                    let label = switch item {
                    case .system: bi("Theo hệ thống", "System")
                    case .light: bi("Sáng", "Light")
                    case .dark: bi("Tối", "Dark")
                    }
                    Button { preferences.appearance = item } label: {
                        radioRow(label, selected: preferences.appearance == item)
                    }
                    .buttonStyle(.plain)
                }
            }

            optionGroup(bi("Bố cục báo cáo", "Report canvas")) {
                checkboxRow(title: bi("Bám lưới khi kéo visual", "Snap visuals to grid"),
                            isOn: Binding(get: { preferences.snapToGrid }, set: { preferences.snapToGrid = $0 }),
                            disabled: false)
                checkboxRow(title: bi("Mở báo cáo ở chế độ chỉ xem theo mặc định", "Open reports in View-only mode by default"),
                            isOn: Binding(get: { preferences.viewOnlyDefault }, set: { preferences.viewOnlyDefault = $0 }),
                            disabled: false)
            }
        }
    }

    private func optionGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS.Palette.label)
            content()
        }
    }

    private func radioRow(_ title: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(selected ? DS.Palette.accentBrand : DS.Palette.checkboxBorder, lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .overlay {
                    if selected {
                        Circle().fill(DS.Palette.accentBrand).frame(width: 7, height: 7)
                    }
                }
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.label)
        }
    }

    private func checkboxRow(title: String, isOn: Binding<Bool>, disabled: Bool) -> some View {
        Button {
            if !disabled { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 8) {
                CheckboxMark(isOn: isOn.wrappedValue)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(disabled ? DS.Palette.tertiaryLabel : DS.Palette.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }
}
