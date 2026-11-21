import Foundation
import PBIXKit

/// Kết quả lập kế hoạch đổi loại visual (`specs/004-d3-them-visual-doi-loai/research.md` R7, R8).
struct TypeChangePlan {
    /// Cấu hình ô của loại mới (phần tử giữ nguyên byte, đã mang ô mới).
    var wells: [PBIRQueryPatch.Well]
    /// Trường không có ô nhận trong loại mới.
    var droppedFields: [ReportField] = []
    /// Khoá `visual.objects` (định dạng) sẽ bị bỏ vì không dùng được cho loại đích (xem `TypeChange.keepsObjectKey`).
    var droppedObjectKeys: [String] = []
    /// Lý do chặn cả thao tác (nil: đổi được).
    var blocked: String?
    var isNoOp = false

    /// Thông báo cho người dùng ngay sau khi đổi loại; nil khi không bỏ gì.
    var notice: String? {
        var parts: [String] = []
        if !droppedFields.isEmpty {
            parts.append("Đã bỏ \(droppedFields.count) trường không có ô trong loại mới: " + droppedFields.map { "\($0.role) \($0.label)" }.joined(separator: ", "))
        }
        if !droppedObjectKeys.isEmpty {
            parts.append("Đã bỏ định dạng riêng không dùng được cho loại mới: " + droppedObjectKeys.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ") + "."
    }
}

enum TypeChange {
    /// Ô thay thế khi loại mới không có ô cùng tên (R7). Chỉ các cặp cùng nghĩa.
    private static let fallbacks: [String: [String]] = [
        "Y2": ["Y"], "Group": ["Category"], "Category": ["Group"], "Values": ["Y"], "Y": ["Values"],
    ]

    /// Ô thay thế riêng theo loại đích (VM-D12, đổi đường có cột ngày ở `Category` sang loại đó trên Desktop): slicer nhận cột
    /// vào `Values`; ma trận nhận cột vào `Rows` và measure ở `Tooltips` vào `Values` (cùng ô với measure của `Y`).
    private static let targetFallbacks: [String: [String: [String]]] = [
        "slicer": ["Category": ["Values"]],
        "advancedSlicerVisual": ["Category": ["Values"]],
        "listSlicer": ["Category": ["Values"]],
        "textSlicer": ["Category": ["Values"]],
        "tableEx": ["Category": ["Values"], "Rows": ["Values"], "Y": ["Values"], "Tooltips": ["Values"]],
        "multiRowCard": ["Category": ["Values"], "Y": ["Values"]],
        "pivotTable": ["Category": ["Rows"], "Tooltips": ["Values"]],
        "kpi": ["Y": ["Indicator"], "Category": ["TrendLine"]],
        "scatterChart": ["Y": ["X", "Y"]],
    ]

    /// Ô ưu tiên trước ô cùng tên ở loại đích (VM-D12): bản đồ hình nhận cột ở `Series` (ô "Chú giải"), không phải `Category`
    /// (vị trí), và `Y` vào `Value` (độ bão hoà màu); đã thử với cột ngày và cột chữ.
    private static let targetFirst: [String: [String: [String]]] = [
        "shapeMap": ["Category": ["Series"], "Y": ["Value"]],
    ]

    /// - Parameters:
    ///   - visual: visual hiện tại (loại, trường).
    ///   - wells: cấu hình ô hiện tại.
    ///   - type: loại đích.
    ///   - objectKeys: khoá `visual.objects` hiện có của visual.
    ///   - seenObjectKeys: khoá `objects` thấy trên các visual cùng loại đích trong báo cáo.
    ///   - references: nơi khác trong `visual.json` còn nhắc tới một trường (sắp xếp, bộ lọc, định dạng).
    static func plan(visual: ReportVisual, wells: [PBIRQueryPatch.Well], to type: String, objectKeys: [String],
                     seenObjectKeys: Set<String>, references: (ReportField) -> [FieldReference]) -> TypeChangePlan {
        var plan = TypeChangePlan(wells: wells)
        if type == visual.type { plan.isNoOp = true; return plan }
        if type == "textbox" || visual.type == "textbox" {
            plan.blocked = "Hộp văn bản không đổi loại được và các loại khác không đổi thành hộp văn bản; hãy thêm hộp văn bản mới."
            return plan
        }
        guard VisualTypes.isSupported(type) else { plan.blocked = VisualTypes.refusal(for: type); return plan }

        let target = ReportVisual(id: visual.id, type: type)
        let rules = WellRules.rules(for: target).filter { $0.status == .observed }
        var placed: [(role: String, elements: [PBIRQueryPatch.Element])] = []
        var dropped: [ReportField] = []

        func index(of role: String) -> Int {
            if let i = placed.firstIndex(where: { $0.role == role }) { return i }
            placed.append((role, []))
            return placed.count - 1
        }

        for well in wells {
            for element in well.elements {
                guard let kind = WellKind(element.field.kind) else { dropped.append(element.field); continue }
                let candidates = (targetFirst[type]?[well.role] ?? []) + [well.role] + (fallbacks[well.role] ?? []) + (targetFallbacks[type]?[well.role] ?? [])
                guard let rule = candidates.lazy.compactMap({ role in rules.first { $0.role == role && $0.accepts.contains(kind) } }).first else {
                    dropped.append(element.field); continue
                }
                let i = index(of: rule.role)
                if rule.isSingle && !placed[i].elements.isEmpty { dropped.append(element.field); continue }
                if placed[i].elements.contains(where: { $0.field.queryRef == element.field.queryRef }) { dropped.append(element.field); continue }
                var moved = element
                moved.field.role = rule.role
                if type == "shapeMap", rule.role == "Series" { moved = moved.withoutActive() }   // VM-D12: không có `active`
                placed[i].elements.append(moved)
            }
        }
        plan.wells = placed.map { PBIRQueryPatch.Well(role: $0.role, elements: $0.elements) }
        plan.droppedFields = dropped

        // Trường bị bỏ mà không còn phần tử nào khác giữ cùng queryRef và còn được nhắc ở nơi khác: chặn (như D2).
        let keptRefs = Set(plan.wells.flatMap { $0.elements.map(\.field.queryRef) })
        for field in dropped where !keptRefs.contains(field.queryRef) {
            if let first = references(field).first {
                plan.blocked = "Chưa đổi loại được: \"\(field.label)\" sẽ bị bỏ nhưng \(first.reason). Xử lý ở lát sau, chưa kiểm với Power BI Desktop."
                return plan
            }
        }
        plan.droppedObjectKeys = objectKeys.filter { !keepsObjectKey($0, to: type, seen: seenObjectKeys) }
        return plan
    }

    // MARK: Định dạng (objects)

    private static let axisKeys: Set<String> = ["valueAxis", "categoryAxis", "trend", "forecast", "y1AxisReferenceLine", "zoom"]

    /// Loại có trục (cột, thanh, đường, vùng, combo…).
    static func hasAxes(_ type: String) -> Bool {
        type.hasSuffix("BarChart") || type == "barChart" || type.hasSuffix("ColumnChart") || type == "columnChart" || type.contains("Combo")
            || ["lineChart", "areaChart", "stackedAreaChart", "hundredPercentStackedAreaChart", "ribbonChart", "waterfallChart", "scatterChart"].contains(type)
    }

    /// Khoá `objects` có giữ khi đổi sang `type` không. Quan sát VM-D3: Desktop chỉ bỏ khoá không còn hợp lệ
    /// (`forecast` khi đường → cột/thanh, `value` khi donut → treemap, `valueAxis` khi combo → donut) và giữ phần còn lại
    /// (`trend`, `valueAxis`, `labels`, `categoryAxis`, `dataPoint`, `legend`…). Khoá đã thấy trên visual cùng loại đích
    /// trong báo cáo thì chắc chắn dùng được.
    static func keepsObjectKey(_ key: String, to type: String, seen: Set<String>) -> Bool {
        if seen.contains(key) { return true }
        if key == "forecast" { return type == "lineChart" }
        if key == "value" { return type == "donutChart" || type == "pieChart" }
        if key == "labels" { return type != "shapeMap" }   // VM-D12: Desktop bỏ `labels` khi thành bản đồ hình
        // VM-D12 (`retype-waterfall`, `retype-funnel`, `retype-lineStackedColumn`): đường sang các loại này bỏ `trend`; phễu giữ
        // `categoryAxis` (bỏ `valueAxis`).
        if key == "trend", ["waterfallChart", "funnel", "lineStackedColumnComboChart"].contains(type) { return false }
        if key == "categoryAxis", type == "funnel" { return true }
        if axisKeys.contains(key) { return hasAxes(type) }
        return true
    }
}
