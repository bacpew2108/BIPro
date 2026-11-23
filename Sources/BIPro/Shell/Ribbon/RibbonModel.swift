import SwiftUI

/// Nhãn song ngữ Việt / Anh cho Ribbon và các thành phần giao diện Phase H.
/// `en` dùng đúng chữ của Power BI Desktop 2.159.
struct Bilingual: Hashable, Sendable {
    let vi: String
    let en: String

    @MainActor
    var localized: String {
        bi(vi, en)
    }

    func text(for language: ResolvedLanguage) -> String {
        language == .en ? en : vi
    }

    var isNonEmpty: Bool {
        !vi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Mã định danh các tab trên thanh Ribbon theo hợp đồng `contracts/ribbon-catalog.md`.
enum RibbonTabID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case file
    case home
    case insert
    case modeling
    case design
    case view
    case optimize
    case help
    case format
    case dataDrill
    case tableTools
    case columnTools

    var id: String { rawValue }

    var isContextual: Bool {
        switch self {
        case .format, .dataDrill, .tableTools, .columnTools:
            return true
        default:
            return false
        }
    }

    var title: Bilingual {
        switch self {
        case .file: Bilingual(vi: "Tệp", en: "File")
        case .home: Bilingual(vi: "Trang chủ", en: "Home")
        case .insert: Bilingual(vi: "Chèn", en: "Insert")
        case .modeling: Bilingual(vi: "Mô hình hóa", en: "Modeling")
        case .design: Bilingual(vi: "Thiết kế", en: "Design")
        case .view: Bilingual(vi: "Xem", en: "View")
        case .optimize: Bilingual(vi: "Tối ưu", en: "Optimize")
        case .help: Bilingual(vi: "Trợ giúp", en: "Help")
        case .format: Bilingual(vi: "Định dạng", en: "Format")
        case .dataDrill: Bilingual(vi: "Dữ liệu / Truy sâu", en: "Data / Drill")
        case .tableTools: Bilingual(vi: "Công cụ bảng", en: "Table tools")
        case .columnTools: Bilingual(vi: "Công cụ cột", en: "Column tools")
        }
    }
}

/// Bảng màu hai tông cho biểu tượng SF Symbols (`.symbolRenderingMode(.palette)`).
enum RibbonTint: Hashable, Sendable {
    case neutral
    case brand
    case excel
    case sql
    case data
    case calculation
    case security
    case copilot
    case info
    case warning
    case indigo
    case danger

    var primary: Color {
        switch self {
        case .neutral: DS.Palette.label
        case .brand: DS.Palette.accentBrand
        case .excel: Color.dynamic(light: 0x107C41, dark: 0x33A864)
        case .sql: Color.dynamic(light: 0xC86400, dark: 0xF5A623)
        case .data: Color.dynamic(light: 0x5B4BDB, dark: 0x9A8EFF)
        case .calculation: DS.Palette.measure
        case .security: DS.Palette.accentBrand
        case .copilot: DS.Palette.indigo
        case .info: Color.dynamic(light: 0x5B4BDB, dark: 0x9A8EFF)
        case .warning: DS.Palette.warning
        case .indigo: DS.Palette.indigo
        case .danger: DS.Palette.danger
        }
    }

    var secondary: Color {
        switch self {
        case .neutral: DS.Palette.secondaryLabel
        case .brand: DS.Palette.secondaryLabel
        case .excel: DS.Palette.secondaryLabel
        case .sql: DS.Palette.secondaryLabel
        case .data: Color.dynamic(light: 0x6B7A99, dark: 0xA3AEC8)
        case .calculation: DS.Palette.secondaryLabel
        case .security: Color.dynamic(light: 0x6B7A99, dark: 0xA3AEC8)
        case .copilot: DS.Palette.accentBrand
        case .info: DS.Palette.secondaryLabel
        case .warning: DS.Palette.secondaryLabel
        case .indigo: DS.Palette.secondaryLabel
        case .danger: DS.Palette.secondaryLabel
        }
    }
}

/// Loại điều khiển dạng ô nhập / danh sách gắn nhãn trên Ribbon.
enum FieldControl: Hashable, Sendable {
    case tableName
    case columnName
    case dataType
    case format
    case formattingShortcuts
    case decimalPlaces
    case summarization
    case dataCategory
    case applyDrillFiltersTo
}

/// Loại thư viện ô mẫu trên Ribbon.
enum GalleryKind: Hashable, Sendable {
    case themes6
}

/// Quy tắc bật/tắt thuần hàm theo `RibbonContext`.
enum Availability {
    case always
    case when((RibbonContext) -> Bool, disabledReason: Bilingual)
    case unsupported(Bilingual)

    /// Nút chưa cài đặt tính năng (`P` trong `contracts/ribbon-catalog.md`): luôn vô hiệu kèm tooltip, khác với `unsupported` (Windows/cloud).
    static func pending(_ reason: Bilingual) -> Availability {
        .when({ _ in false }, disabledReason: reason)
    }

    func isEnabled(in context: RibbonContext) -> Bool {
        switch self {
        case .always:
            return true
        case .when(let predicate, _):
            return predicate(context)
        case .unsupported:
            return false
        }
    }

    func disabledReason(in context: RibbonContext) -> Bilingual? {
        switch self {
        case .always:
            return nil
        case .when(let predicate, let reason):
            return predicate(context) ? nil : reason
        case .unsupported(let reason):
            return reason
        }
    }

    var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    var unsupportedReason: Bilingual? {
        if case .unsupported(let reason) = self { return reason }
        return nil
    }
}

/// Hình thức hiển thị một mục trên Ribbon.
indirect enum RibbonItemKind {
    case large
    case smallStack([RibbonItemSpec])
    case checkbox
    case field(FieldControl)
    case gallery(GalleryKind)
    case toggle
}

/// Đặc tả một mục/nút trên Ribbon.
struct RibbonItemSpec: Identifiable {
    let id: RibbonCommandID
    let title: Bilingual
    let symbol: String
    let tint: RibbonTint
    let kind: RibbonItemKind
    let hasMenu: Bool
    let availability: Availability
    let observed: Bool
    let note: String?

    init(
        id: RibbonCommandID,
        title: Bilingual,
        symbol: String,
        tint: RibbonTint = .neutral,
        kind: RibbonItemKind = .large,
        hasMenu: Bool = false,
        availability: Availability = .always,
        observed: Bool = true,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.kind = kind
        self.hasMenu = hasMenu
        self.availability = availability
        self.observed = observed
        self.note = note
    }

    /// Trả về mọi lệnh lá (mở bung `smallStack`).
    var leafItems: [RibbonItemSpec] {
        if case .smallStack(let children) = kind {
            return children
        }
        return [self]
    }

    /// Kiểm tra các ràng buộc hợp đồng (T004 / FR-027 / FR-028).
    var validationIssues: [String] {
        var issues: [String] = []
        if !title.isNonEmpty {
            issues.append("\(id.rawValue): title.vi hoặc title.en rỗng")
        }
        if case .unsupported(let reason) = availability, !reason.isNonEmpty {
            issues.append("\(id.rawValue): Availability.unsupported thiếu tooltip song ngữ")
        }
        if case .when(_, let reason) = availability, !reason.isNonEmpty {
            issues.append("\(id.rawValue): Availability.when thiếu disabledReason song ngữ")
        }
        if !observed {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                issues.append("\(id.rawValue): observed == false nhưng note rỗng")
            }
        }
        if case .smallStack(let children) = kind {
            for child in children {
                issues.append(contentsOf: child.validationIssues)
            }
        }
        return issues
    }
}

/// Một nhóm nút nằm giữa hai vạch dọc trên Ribbon.
struct RibbonGroupSpec: Identifiable {
    let id: String
    let title: Bilingual
    let items: [RibbonItemSpec]
}

/// Toàn bộ nội dung một tab Ribbon.
struct RibbonTabSpec: Identifiable {
    let id: RibbonTabID
    let title: Bilingual
    let contextual: Bool
    let groups: [RibbonGroupSpec]
}
