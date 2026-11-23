import AppKit
import Connectors
import SwiftUI

/// Dữ liệu và bộ vẽ menu thả xuống cho thanh Ribbon (T027 — theo `docs/PHASE_H_UI_PARITY.md` mục 3.10 và ảnh `dd_*.png`).
enum RibbonMenus {
    struct Entry: Identifiable, Hashable, Sendable {
        let id: String
        let title: Bilingual
        let symbol: String
        let enabled: Bool
        let disabledReason: Bilingual?
        let observed: Bool
        let note: String?

        init(
            id: String,
            vi: String,
            en: String,
            symbol: String,
            enabled: Bool = true,
            disabledReason: Bilingual? = nil,
            observed: Bool = true,
            note: String? = nil
        ) {
            self.id = id
            self.title = Bilingual(vi: vi, en: en)
            self.symbol = symbol
            self.enabled = enabled
            self.disabledReason = disabledReason
            self.observed = observed
            self.note = note
        }
    }

    struct ShapeSection: Identifiable, Hashable, Sendable {
        let id: String
        let title: Bilingual?
        let items: [Entry]
    }

    struct ThemeTileSpec: Identifiable, Hashable, Sendable {
        let id: String
        let title: Bilingual
        let isDefaultClear: Bool
        let backgroundHex: String
        let foregroundHex: String
        let swatches: [String]
        let presetIndex: Int?
    }

    private static let pendingReason = Bilingual(
        vi: "BI Pro chưa hỗ trợ mục này",
        en: "Not yet implemented in BI Pro"
    )

    // MARK: - New page ▾ (dd_newpage.png)

    static let newPageEntries: [Entry] = [
        Entry(id: "newPage", vi: "Trang mới", en: "New page", symbol: "doc.badge.plus", enabled: true),
        Entry(id: "duplicatePage", vi: "Nhân bản trang", en: "Duplicate page", symbol: "doc.on.doc", enabled: true),
    ]

    // MARK: - Buttons ▾ (dd_buttons.png)

    static let buttonsEntries: [Entry] = [
        Entry(id: "rightArrow", vi: "Mũi tên phải", en: "Right arrow", symbol: "arrow.right", enabled: false, disabledReason: pendingReason),
        Entry(id: "reset", vi: "Đặt lại", en: "Reset", symbol: "arrow.uturn.left", enabled: false, disabledReason: pendingReason),
        Entry(id: "back", vi: "Quay lại", en: "Back", symbol: "arrow.left.circle", enabled: false, disabledReason: pendingReason),
        Entry(id: "information", vi: "Thông tin", en: "Information", symbol: "info.circle", enabled: false, disabledReason: pendingReason),
        Entry(id: "help", vi: "Trợ giúp", en: "Help", symbol: "questionmark.circle", enabled: false, disabledReason: pendingReason),
        Entry(id: "bookmark", vi: "Dấu trang", en: "Bookmark", symbol: "bookmark", enabled: false, disabledReason: pendingReason),
        Entry(id: "blank", vi: "Trống", en: "Blank", symbol: "rectangle", enabled: true),
        Entry(id: "applyAllSlicers", vi: "Áp dụng mọi slicer", en: "Apply all slicers", symbol: "line.3.horizontal.decrease.circle", enabled: false, disabledReason: pendingReason),
        Entry(id: "clearAllSlicers", vi: "Xoá mọi slicer", en: "Clear all slicers", symbol: "eraser", enabled: false, disabledReason: pendingReason),
        // [SUY ĐOÁN] Menu con Navigator chưa quan sát trên VM-UI2; gán hai loại navigator hiện có của BI Pro.
        Entry(
            id: "navigator",
            vi: "Điều hướng",
            en: "Navigator",
            symbol: "rectangle.split.3x1",
            enabled: true,
            observed: false,
            note: "[SUY ĐOÁN] Menu con Navigator chưa quan sát ảnh VM; gồm Page navigator và Bookmark navigator hiện có."
        ),
    ]

    static let navigatorSubmenuEntries: [Entry] = [
        Entry(id: "pageNavigator", vi: "Điều hướng trang", en: "Page navigator", symbol: "rectangle.split.3x1", enabled: true, observed: false, note: "[SUY ĐOÁN] Thuộc menu con Navigator."),
        Entry(id: "bookmarkNavigator", vi: "Điều hướng dấu trang", en: "Bookmark navigator", symbol: "bookmark.square", enabled: true, observed: false, note: "[SUY ĐOÁN] Thuộc menu con Navigator."),
    ]

    // MARK: - Shapes ▾ (dd_shapes.png)

    static let shapeSections: [ShapeSection] = [
        ShapeSection(
            id: "rectangles",
            title: nil,
            items: [
                Entry(id: "rectangle", vi: "Hình chữ nhật", en: "Rectangle", symbol: "rectangle", enabled: true),
                Entry(id: "roundedRectangle", vi: "Chữ nhật bo góc", en: "Rounded rectangle", symbol: "rectangle.roundedtop", enabled: false, disabledReason: pendingReason),
                Entry(id: "snipSingleCorner", vi: "Chữ nhật vát 1 góc", en: "Snip single corner rectangle", symbol: "doc", enabled: false, disabledReason: pendingReason),
                Entry(id: "snipTopCorners", vi: "Chữ nhật vát 2 góc trên", en: "Snip same side corner rectangle", symbol: "trapezoid.and.line.horizontal", enabled: false, disabledReason: pendingReason),
                Entry(id: "roundSingleCorner", vi: "Chữ nhật bo 1 góc", en: "Round single corner rectangle", symbol: "rectangle.inset.filled", enabled: false, disabledReason: pendingReason),
                Entry(id: "roundTopCorners", vi: "Chữ nhật bo 2 góc trên", en: "Round same side corner rectangle", symbol: "rectangle.roundedbottom", enabled: false, disabledReason: pendingReason),
            ]
        ),
        ShapeSection(
            id: "basicShapes",
            title: Bilingual(vi: "Hình cơ bản", en: "Basic Shapes"),
            items: [
                Entry(id: "oval", vi: "Hình tròn / Ôvan", en: "Oval", symbol: "circle", enabled: true),
                Entry(id: "pill", vi: "Viên thuốc", en: "Pill", symbol: "capsule", enabled: false, disabledReason: pendingReason),
                Entry(id: "triangle", vi: "Tam giác", en: "Isosceles triangle", symbol: "triangle", enabled: false, disabledReason: pendingReason),
                Entry(id: "rightTriangle", vi: "Tam giác vuông", en: "Right triangle", symbol: "triangleshape", enabled: false, disabledReason: pendingReason),
                Entry(id: "parallelogram", vi: "Hình bình hành", en: "Parallelogram", symbol: "rhombus", enabled: false, disabledReason: pendingReason),
                Entry(id: "trapezoid", vi: "Hình thang", en: "Trapezoid", symbol: "trapezoid.and.line.vertical", enabled: false, disabledReason: pendingReason),
                Entry(id: "pentagon", vi: "Ngũ giác", en: "Pentagon", symbol: "pentagon", enabled: false, disabledReason: pendingReason),
                Entry(id: "hexagon", vi: "Lục giác", en: "Hexagon", symbol: "hexagon", enabled: false, disabledReason: pendingReason),
                Entry(id: "octagon", vi: "Bát giác", en: "Octagon", symbol: "octagon", enabled: false, disabledReason: pendingReason),
                Entry(id: "heart", vi: "Trái tim", en: "Heart", symbol: "heart", enabled: false, disabledReason: pendingReason),
                Entry(id: "speechBubble", vi: "Bóng thoại", en: "Speech bubble", symbol: "bubble.left", enabled: false, disabledReason: pendingReason),
                Entry(id: "line", vi: "Đường thẳng", en: "Line", symbol: "line.diagonal", enabled: true),
            ]
        ),
        ShapeSection(
            id: "blockArrows",
            title: Bilingual(vi: "Mũi tên khối", en: "Block Arrows"),
            items: [
                Entry(id: "arrowRight", vi: "Mũi tên phải", en: "Right arrow", symbol: "arrow.right", enabled: false, disabledReason: pendingReason),
                Entry(id: "arrowLeft", vi: "Mũi tên trái", en: "Left arrow", symbol: "arrow.left", enabled: false, disabledReason: pendingReason),
                Entry(id: "arrowUp", vi: "Mũi tên lên", en: "Up arrow", symbol: "arrow.up", enabled: false, disabledReason: pendingReason),
                Entry(id: "arrowDown", vi: "Mũi tên xuống", en: "Down arrow", symbol: "arrow.down", enabled: false, disabledReason: pendingReason),
                Entry(id: "pentagonArrow", vi: "Mũi tên ngũ giác", en: "Pentagon arrow", symbol: "arrowtriangle.right", enabled: false, disabledReason: pendingReason),
                Entry(id: "chevronArrow", vi: "Mũi tên chữ V", en: "Chevron arrow", symbol: "chevron.right.2", enabled: false, disabledReason: pendingReason),
            ]
        ),
    ]

    // MARK: - Page view ▾ (dd_pageview.png)

    static let pageViewEntries: [Entry] = [
        Entry(id: "fitToPage", vi: "Vừa trang", en: "Fit to page", symbol: "arrow.up.left.and.arrow.down.right", enabled: true),
        Entry(id: "fitToWidth", vi: "Vừa chiều rộng", en: "Fit to width", symbol: "arrow.left.and.right", enabled: true),
        Entry(id: "actualSize", vi: "Kích thước thực", en: "Actual size", symbol: "1.magnifyingglass", enabled: true),
    ]

    // MARK: - Refresh ▾ (dd_refresh.png)

    static let refreshEntries: [Entry] = [
        Entry(id: "schemaAndData", vi: "Lược đồ và dữ liệu", en: "Schema and data", symbol: "arrow.clockwise", enabled: true),
        Entry(
            id: "schemaOnly",
            vi: "Lược đồ",
            en: "Schema",
            symbol: "tablecells",
            enabled: false,
            disabledReason: Bilingual(vi: "BI Pro hiện chỉ hỗ trợ làm mới đồng thời lược đồ và dữ liệu", en: "BI Pro currently refreshes schema and data together")
        ),
        Entry(
            id: "dataOnly",
            vi: "Dữ liệu",
            en: "Data",
            symbol: "cylinder",
            enabled: false,
            disabledReason: Bilingual(vi: "BI Pro hiện chỉ hỗ trợ làm mới đồng thời lược đồ và dữ liệu", en: "BI Pro currently refreshes schema and data together")
        ),
    ]

    // MARK: - Themes ▾ (dd_themes.png)

    static let themesBanner = Bilingual(
        vi: "Các chủ đề chỉ đổi màu trước đây nay là bảng màu. Mở khung định dạng chủ đề.",
        en: "Previous color-only themes are now color palettes. Open theme format pane."
    )

    /// 9 ô mẫu mục Power BI trong `dd_themes.png` (ô 0 là mặc định gạch chéo, các ô tiếp theo ánh xạ preset hiện có + biến thể).
    // [SUY ĐOÁN] Tên từng theme trong lưới 9 ô Power BI chưa hiển thị chữ trong ảnh `dd_themes.png`.
    static let themesPowerBITiles: [ThemeTileSpec] = [
        ThemeTileSpec(id: "defaultClear", title: Bilingual(vi: "Mặc định", en: "Default"), isDefaultClear: true, backgroundHex: "#FFFFFF", foregroundHex: "#252423", swatches: ["#118DFF", "#12239E", "#E66C37", "#6B007B", "#E044A7", "#744EC2"], presetIndex: 0),
        ThemeTileSpec(id: "executive", title: Bilingual(vi: "Điều hành", en: "Executive"), isDefaultClear: false, backgroundHex: "#5B4B9A", foregroundHex: "#FFFFFF", swatches: ["#3B5998", "#2B947E", "#D97724", "#7D4E9F", "#C24641", "#5E7E9C"], presetIndex: 1),
        ThemeTileSpec(id: "innovate", title: Bilingual(vi: "Sáng tạo tối", en: "Innovate"), isDefaultClear: false, backgroundHex: "#222428", foregroundHex: "#FFFFFF", swatches: ["#118DFF", "#30D158", "#FF9F0A", "#BF5AF2", "#FF453A", "#64D2FF"], presetIndex: 5),
        ThemeTileSpec(id: "bloom", title: Bilingual(vi: "Tươi sáng", en: "Bloom"), isDefaultClear: false, backgroundHex: "#FFFFFF", foregroundHex: "#252423", swatches: ["#D64550", "#E87A90", "#F4B6C2", "#34C759", "#1AAB40", "#5B4BDB"], presetIndex: 4),
        ThemeTileSpec(id: "cityPark", title: Bilingual(vi: "Công viên xanh", en: "City Park"), isDefaultClear: false, backgroundHex: "#FAF9F5", foregroundHex: "#1D2D24", swatches: ["#2F6F4E", "#6CA965", "#E2B144", "#3E7CB1", "#D96B43", "#7F9C8D"], presetIndex: 2),
        ThemeTileSpec(id: "classic", title: Bilingual(vi: "Cổ điển", en: "Classic"), isDefaultClear: false, backgroundHex: "#2B2D30", foregroundHex: "#FFFFFF", swatches: ["#01B8AA", "#374649", "#FD625E", "#F2C80F", "#8AD4EB", "#FE9666"], presetIndex: 3),
        ThemeTileSpec(id: "highContrast", title: Bilingual(vi: "Tương phản cao", en: "High Contrast"), isDefaultClear: false, backgroundHex: "#1E1E22", foregroundHex: "#FFFFFF", swatches: ["#005FCC", "#D62728", "#008744", "#E67E00", "#7B1FA2", "#00838F"], presetIndex: 4),
        ThemeTileSpec(id: "ocean", title: Bilingual(vi: "Đại dương", en: "Ocean"), isDefaultClear: false, backgroundHex: "#103A5C", foregroundHex: "#FFFFFF", swatches: ["#118DFF", "#30B0C7", "#34C759", "#FFD60A", "#5E5CE6", "#64D2FF"], presetIndex: 0),
        ThemeTileSpec(id: "sunset", title: Bilingual(vi: "Hoàng hôn", en: "Sunset"), isDefaultClear: false, backgroundHex: "#F7F3FA", foregroundHex: "#252423", swatches: ["#6B007B", "#E044A7", "#E66C37", "#D9B300", "#118DFF", "#12239E"], presetIndex: 1),
    ]

    // MARK: - Action helpers

    @MainActor
    static func performNewPage(_ entryID: String, state: DocumentState) {
        switch entryID {
        case "newPage":
            state.addPage()
        case "duplicatePage":
            if let current = state.pageID {
                state.duplicatePage(current)
            }
        default:
            break
        }
    }

    @MainActor
    static func performButton(_ entryID: String, state: DocumentState) {
        switch entryID {
        case "blank":
            state.insertVisual("actionButton")
        case "pageNavigator":
            state.insertVisual("pageNavigator")
        case "bookmarkNavigator":
            state.insertVisual("bookmarkNavigator")
        default:
            break
        }
    }

    @MainActor
    static func performShape(_ entryID: String, state: DocumentState) {
        switch entryID {
        case "rectangle", "oval", "line":
            state.insertShape(entryID)
        default:
            break
        }
    }

    @MainActor
    static func performPageView(_ entryID: String, state: DocumentState) {
        switch entryID {
        case "fitToPage":
            state.zoom = nil
        case "fitToWidth":
            // [SUY ĐOÁN] Khi chưa có cờ fit-width riêng, đặt mức thu phóng chuẩn 1.0 phù hợp chiều rộng khung.
            state.zoom = 1.0
        case "actualSize":
            state.zoom = 1.0
        default:
            break
        }
    }
}

/// Popover lưới 4 cột cho `Shapes ▾` khớp ảnh `dd_shapes.png`.
struct ShapesGalleryPopoverView: View {
    let state: DocumentState
    let dismiss: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(RibbonMenus.shapeSections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if let title = section.title {
                        Text(title.localized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.label)
                    }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(section.items) { entry in
                            Button {
                                RibbonMenus.performShape(entry.id, state: state)
                                dismiss()
                            } label: {
                                Image(systemName: entry.symbol)
                                    .font(.system(size: 15))
                                    .foregroundStyle(entry.enabled ? DS.Palette.label : DS.Palette.tertiaryLabel)
                                    .frame(width: 30, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.chrome.opacity(entry.enabled ? 0.8 : 0.3)))
                            }
                            .buttonStyle(.plain)
                            .disabled(!entry.enabled)
                            .opacity(entry.enabled ? 1 : 0.45)
                            .help(entry.enabled ? entry.title.localized : (entry.disabledReason?.localized ?? entry.title.localized))
                            .accessibilityLabel(entry.title.localized)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 176)
    }
}
