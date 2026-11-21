import AppKit
import DAXEngine
import Foundation
import PBIXKit

/// Tóm tắt trợ năng VoiceOver cho một visual trên Report Canvas (US5, FR-041).
struct VisualAccessibilitySummary: Equatable, Sendable {
    let label: String
    let value: String
    let hint: String

    static func visualTypeName(_ type: String, language: ResolvedLanguage) -> String {
        let key: L10n.Key = switch type {
        case "card", "cardVisual": .a11yVisualTypeCard
        case "multiRowCard": .a11yVisualTypeMultiRowCard
        case "kpi": .a11yVisualTypeKPI
        case "gauge": .a11yVisualTypeGauge
        case "scatterChart": .a11yVisualTypeScatterChart
        case "clusteredBarChart", "barChart", "stackedBarChart", "hundredPercentStackedBarChart": .a11yVisualTypeBarChart
        case "clusteredColumnChart", "columnChart", "stackedColumnChart", "hundredPercentStackedColumnChart": .a11yVisualTypeColumnChart
        case "lineChart": .a11yVisualTypeLineChart
        case "lineClusteredColumnComboChart", "lineStackedColumnComboChart": .a11yVisualTypeComboChart
        case "areaChart", "stackedAreaChart", "hundredPercentStackedAreaChart": .a11yVisualTypeAreaChart
        case "donutChart": .a11yVisualTypeDonutChart
        case "pieChart": .a11yVisualTypePieChart
        case "treemap": .a11yVisualTypeTreemap
        case "shapeMap": .a11yVisualTypeShapeMap
        case "map", "filledMap": .a11yVisualTypeMap
        case "ribbonChart": .a11yVisualTypeRibbonChart
        case "waterfallChart": .a11yVisualTypeWaterfallChart
        case "funnel": .a11yVisualTypeFunnel
        case "pivotTable", "matrix": .a11yVisualTypeMatrix
        case "tableEx", "table": .a11yVisualTypeTable
        case "slicer", "advancedSlicerVisual", "listSlicer", "textSlicer": .a11yVisualTypeSlicer
        case "textbox": .a11yVisualTypeTextbox
        case "image": .a11yVisualTypeImage
        case "shape", "basicShape": .a11yVisualTypeShape
        case "actionButton", "pageNavigator", "bookmarkNavigator": .a11yVisualTypeButton
        default: .a11yVisualTypeGeneric
        }
        return L10n.string(key, language: language)
    }

    static func describe(
        visual: ReportVisual,
        data: DataView?,
        slicerSelectedCount: Int = 0,
        language: ResolvedLanguage
    ) -> VisualAccessibilitySummary {
        let typeName = visualTypeName(visual.type, language: language)
        let rawTitle = visual.containerObjects.string("title", "text")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = visual.fields.first?.label ?? ""
        let titlePart = (rawTitle?.isEmpty == false ? rawTitle! : fallbackTitle)
        let label = titlePart.isEmpty ? typeName : "\(typeName): \(titlePart)"

        let value: String
        switch data {
        case .none, .some(.empty):
            value = L10n.string(.a11yVisualDataEmpty, language: language)
        case .some(.single(let single)):
            let formatted = NumberDisplay.plain(single.cell)
            value = formatted.isEmpty ? L10n.string(.a11yVisualDataEmpty, language: language) : formatted
        case .some(.categorical(let cat)):
            let seriesCount = max(1, cat.series.isEmpty ? cat.measures.count : cat.series.count)
            value = L10n.format(.a11yVisualCategoriesFormat, language: language, cat.categories.count, seriesCount)
        case .some(.matrix(let mat)):
            let colCount = max(1, mat.columns.isEmpty ? mat.measures.count : mat.columns.count)
            value = L10n.format(.a11yVisualMatrixFormat, language: language, mat.rows.count, colCount)
        case .some(.slicer):
            if slicerSelectedCount == 0 {
                value = L10n.string(.a11yVisualSlicerAll, language: language)
            } else {
                value = L10n.format(.a11yVisualSlicerSelectedFormat, language: language, slicerSelectedCount)
            }
        case .some(.table(let table)):
            value = L10n.format(.a11yVisualMatrixFormat, language: language, table.rows.count, max(1, table.columns.count))
        case .some(.scatter(let scatter)):
            let seriesCount = max(1, scatter.series.count)
            value = L10n.format(.a11yVisualCategoriesFormat, language: language, scatter.points.count, seriesCount)
        case .some(.gauge(let gauge)):
            let formatted = NumberDisplay.plain(gauge.value)
            value = formatted.isEmpty ? L10n.string(.a11yVisualDataEmpty, language: language) : formatted
        case .some(.kpi(let kpi)):
            let formatted = NumberDisplay.plain(kpi.latestValue)
            value = formatted.isEmpty ? L10n.string(.a11yVisualDataEmpty, language: language) : formatted
        case .some(.multiRowCard(let card)):
            value = L10n.format(.a11yVisualMatrixFormat, language: language, card.rows.count, max(1, card.fields.count))
        }

        let hint = L10n.string(.a11yVisualHint, language: language)
        return VisualAccessibilitySummary(label: label, value: value, hint: hint)
    }
}

/// Nhãn trợ năng VoiceOver cho từng dòng cây trong ngăn Dữ liệu (DataPane — FR-041).
enum DataTreeAccessibility {
    enum Kind: Sendable, Equatable {
        case table, folder, column, measure, hierarchy, hierarchyLevel
    }

    static func label(kind: Kind, name: String, language: ResolvedLanguage) -> String {
        let prefix: String = switch kind {
        case .table: L10n.string(.a11yTable, language: language)
        case .folder: language == .en ? "Folder" : "Thư mục"
        case .column: L10n.string(.a11yColumn, language: language)
        case .measure: L10n.string(.a11yMeasure, language: language)
        case .hierarchy: L10n.string(.a11yHierarchy, language: language)
        case .hierarchyLevel: language == .en ? "Level" : "Cấp"
        }
        return "\(prefix): \(name)"
    }

    static func value(isHidden: Bool, isSelected: Bool, isChecked: Bool?, language: ResolvedLanguage) -> String {
        var parts: [String] = []
        if isChecked == true {
            parts.append(language == .en ? "In visual" : "Đang dùng")
        }
        if isSelected {
            parts.append(L10n.string(.a11ySelected, language: language))
        }
        if isHidden {
            parts.append(L10n.string(.a11yHidden, language: language))
        }
        return parts.joined(separator: ", ")
    }
}

/// Phát thông báo VoiceOver khi có sự kiện quan trọng (đổi trang, bật/tắt Sửa, lưu xong, xuất xong — FR-042).
@MainActor
enum AccessibilityAnnouncer {
    /// Bộ ghi tuỳ chọn phục vụ unit test kiểm tra sự kiện phát thông báo.
    static var testHook: ((String) -> Void)?

    static func announce(_ message: String) {
        guard !message.isEmpty else { return }
        testHook?(message)
        guard let app = NSApp else { return }
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: userInfo)
    }
}
