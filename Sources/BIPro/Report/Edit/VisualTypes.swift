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
        ("card", .value), ("cardVisual", .value), ("multiRowCard", .value), ("gauge", .value), ("kpi", .value),
        ("slicer", .slicer), ("advancedSlicerVisual", .slicer), ("listSlicer", .slicer), ("textSlicer", .slicer),
        // VM-V11A: Stacked bar ghi `barChart`, 100% bar ghi `hundredPercentStackedBarChart`, Pie ghi `pieChart`.
        ("barChart", .xy), ("stackedBarChart", .xy), ("clusteredBarChart", .xy), ("hundredPercentStackedBarChart", .xy),
        ("clusteredColumnChart", .xy), ("columnChart", .xy), ("hundredPercentStackedColumnChart", .xy), ("lineChart", .xy),
        ("lineClusteredColumnComboChart", .xy), ("lineStackedColumnComboChart", .xy),
        ("areaChart", .xy), ("stackedAreaChart", .xy), ("hundredPercentStackedAreaChart", .xy),
        ("ribbonChart", .xy), ("waterfallChart", .xy), ("funnel", .circular), ("scatterChart", .xy),
        ("pieChart", .circular), ("donutChart", .circular), ("treemap", .circular),
        ("tableEx", .matrix), ("pivotTable", .matrix),
        ("shapeMap", .map), ("map", .map), ("filledMap", .map),
        ("textbox", .text), ("shape", .text), ("actionButton", .text), ("pageNavigator", .text), ("bookmarkNavigator", .text), ("image", .text),
    ]

    /// Loại thêm được và đổi tới được (quan sát qua Nhom6, VM-D3/D15 và VM-V11A).
    static let supported: [String] = families.map(\.type)

    static func isSupported(_ type: String) -> Bool { supported.contains(type) }

    static func info(for type: String) -> VisualTypeInfo? {
        guard let entry = families.first(where: { $0.type == type }), let size = PBIRNewVisual.defaultSize(for: type) else { return nil }
        return VisualTypeInfo(type: type, family: entry.family, defaultSize: size)
    }

    /// Lý do (tiếng Việt) một loại chưa thêm được hoặc chưa đổi tới được.
    static func refusal(for type: String) -> String {
        if VisualCatalog.gallery.contains(where: { $0.type == type }) {
            return "BI Pro chưa vẽ được loại này, nên chưa thêm hoặc đổi tới được."
        }
        return "Loại visual này chưa được hỗ trợ."
    }
}
