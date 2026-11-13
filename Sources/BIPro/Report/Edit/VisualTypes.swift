import PBIXKit

/// Thông tin một loại visual thêm được hoặc đổi tới được ở lát D3 (`specs/004-d3-them-visual-doi-loai/data-model.md`).
struct VisualTypeInfo: Equatable {
    enum Family: Equatable { case xy, circular, matrix, value, slicer, text, map }

    let type: String
    let family: Family
    let defaultSize: (width: Int, height: Int)

    var isSupported: Bool { true }

    static func == (lhs: VisualTypeInfo, rhs: VisualTypeInfo) -> Bool {
        lhs.type == rhs.type && lhs.family == rhs.family && lhs.defaultSize == rhs.defaultSize
    }
}

enum VisualTypes {
    private static let families: [(type: String, family: VisualTypeInfo.Family)] = [
        ("card", .value), ("cardVisual", .value), ("slicer", .slicer),
        ("clusteredBarChart", .xy), ("clusteredColumnChart", .xy), ("columnChart", .xy), ("hundredPercentStackedColumnChart", .xy), ("lineChart", .xy),
        ("lineClusteredColumnComboChart", .xy), ("lineStackedColumnComboChart", .xy),
        ("donutChart", .circular), ("treemap", .circular),
        ("pivotTable", .matrix), ("shapeMap", .map), ("textbox", .text),
    ]

    /// Loại thêm được và đổi tới được ở bản đầu: loại có ô đã quan sát trong Nhom6 (`WellRules`) và hộp văn bản (R2).
    static let supported: [String] = families.map(\.type)

    static func isSupported(_ type: String) -> Bool { supported.contains(type) }

    static func info(for type: String) -> VisualTypeInfo? {
        guard let entry = families.first(where: { $0.type == type }), let size = PBIRNewVisual.defaultSize(for: type) else { return nil }
        return VisualTypeInfo(type: type, family: entry.family, defaultSize: size)
    }

    /// Lý do (tiếng Việt) một loại chưa thêm được hoặc chưa đổi tới được.
    static func refusal(for type: String) -> String {
        let needsObservation: Set<String> = ["stackedColumnChart", "stackedBarChart", "hundredPercentStackedBarChart",
                                             "areaChart", "stackedAreaChart", "ribbonChart", "waterfallChart", "funnel", "pieChart"]
        let needsResources: Set<String> = ["image", "actionButton", "pageNavigator", "shape", "basicShape", "bookmarkNavigator"]
        if needsObservation.contains(type) {
            return "Loại này chưa có luật ô quan sát từ Power BI Desktop (chờ buổi VM-D3), nên chưa thêm hoặc đổi tới được."
        }
        if needsResources.contains(type) {
            return "Loại này cần tài nguyên hoặc cấu hình riêng, chưa hỗ trợ ở lát này."
        }
        if VisualCatalog.gallery.contains(where: { $0.type == type }) {
            return "BI Pro chưa vẽ được loại này, nên chưa thêm hoặc đổi tới được."
        }
        return "Loại visual này chưa được hỗ trợ."
    }
}
