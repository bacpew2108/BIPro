import Foundation
import PBIXKit

/// Thao tác thuần trên cấu hình trường của một visual (danh sách ô theo thứ tự). Mỗi thao tác trả cấu hình mới,
/// "không đổi", hoặc lý do từ chối bằng tiếng Việt. Hợp đồng: `contracts/field-editing.md`.
enum FieldEditor {
    enum Result {
        case changed([PBIRQueryPatch.Well])
        case unchanged
        case refused(String)

        var isUnchanged: Bool { if case .unchanged = self { true } else { false } }
    }

    typealias Well = PBIRQueryPatch.Well

    // MARK: Thêm

    /// Thêm `field` vào cuối ô `role`; ô một trường thì thay các trường cũ; ô chưa có trong file thì được tạo.
    /// `implicitMeasures`: cột vào ô chỉ nhận measure thành trường gộp với phép gộp mặc định của cột (VM-F10).
    static func add(_ field: FieldRef, to role: String, wells: [Well], visual: ReportVisual, implicitMeasures: Bool = false) -> Result {
        if let reason = WellRules.refusal(adding: field, to: role, in: visual, implicitMeasures: implicitMeasures) { return .refused(reason) }
        guard let rule = WellRules.rule(for: visual, role: role) else { return .refused("Visual này không có ô \"\(role)\".") }
        if field.kind == .column, !rule.accepts.contains(.column) {
            let function = AggregateFunction.defaultFunction(for: field)
            let native = function.nativeQueryRef(column: field.property, kind: AggregateFunction.ColumnKind(field.family))
            let element = PBIRQueryPatch.newAggregation(entity: field.entity, property: field.property, function: function.rawValue,
                                                        role: role, nativeQueryRef: native)
            var result = wells
            if let index = result.firstIndex(where: { $0.role == role }) {
                if rule.isSingle { result[index].elements = [element] } else { result[index].elements.append(element) }
            } else {
                result.append(Well(role: role, elements: [element]))
            }
            return .changed(result)
        }
        if field.kind == .hierarchy {
            // Phân cấp: một phần tử mỗi cấp, `active: true` cả (VM-D11 mục 1). Ô một trường thì thay các trường cũ.
            guard !field.levels.isEmpty else { return .refused("Phân cấp \"\(field.property)\" không có cấp nào.") }
            // Phân cấp ngày Auto date/time: chỉ cấp đầu `active` [SUY ĐOÁN, kiểm ở gate T037; file Desktop đã drill có đúng một cấp
            // `active`], để visual hiện theo Năm như Desktop vừa thả.
            let elements = field.levels.enumerated().map { offset, level in
                if let column = field.variationColumn {
                    return PBIRQueryPatch.newVariationLevel(entity: field.entity, column: column, variation: field.variationName ?? "Variation",
                                                            hierarchy: field.property, level: level, role: role, active: offset == 0)
                }
                return PBIRQueryPatch.newHierarchyLevel(entity: field.entity, hierarchy: field.property, level: level, role: role)
            }
            var result = wells
            if let index = result.firstIndex(where: { $0.role == role }) {
                if rule.isSingle { result[index].elements = elements } else { result[index].elements += elements }
            } else {
                result.append(Well(role: role, elements: elements))
            }
            return .changed(result)
        }
        let kind: ReportField.Kind = field.kind == .column ? .column : .measure
        // VM-V11A: tableEx, multiRowCard, kpi, advancedSlicerVisual, listSlicer, textSlicer không ghi cờ `"active"` cho cột.
        let omitsActive: Set<String> = ["tableEx", "multiRowCard", "kpi", "advancedSlicerVisual", "listSlicer", "textSlicer"]
        let hasColumn = wells.first { $0.role == role }?.elements.contains { $0.field.kind != .measure && $0.field.kind != .aggregation } ?? false
        let replacing = rule.isSingle
        let activeFlag: Bool? = (kind == .column && !omitsActive.contains(visual.type)) ? (replacing || !hasColumn) : nil
        let element = PBIRQueryPatch.newElement(kind: kind, entity: field.entity, property: field.property, displayName: nil, role: role,
                                                active: activeFlag)
        var result = wells
        if let index = result.firstIndex(where: { $0.role == role }) {
            if rule.isSingle { result[index].elements = [element] } else { result[index].elements.append(element) }
        } else {
            result.append(Well(role: role, elements: [element]))
        }
        return .changed(result)
    }

    // MARK: Bỏ

    /// Bỏ phần tử `index` của ô `role`. Bị chặn khi trường còn được nhắc ở sắp xếp, bộ lọc, định dạng (`references`)
    /// và không còn phần tử nào khác trong visual có cùng `queryRef`.
    static func remove(role: String, index: Int, wells: [Well], visual: ReportVisual,
                       references: (ReportField) -> [FieldReference]) -> Result {
        guard let w = wells.firstIndex(where: { $0.role == role }), wells[w].elements.indices.contains(index) else {
            return .refused("Không có trường để bỏ.")
        }
        let field = wells[w].elements[index].field
        let others = wells.enumerated().flatMap { (wi, well) in
            well.elements.enumerated().filter { !(wi == w && $0.offset == index) }.map(\.element.field.queryRef)
        }
        if !others.contains(field.queryRef) {
            let refs = references(field)
            if let first = refs.first {
                return .refused("Chưa bỏ được \"\(field.label)\": \(first.reason). Xử lý ở lát sau, chưa kiểm với Power BI Desktop.")
            }
        }
        var result = wells
        result[w].elements.remove(at: index)
        return .changed(result)
    }

    // MARK: Đổi thứ tự và chuyển ô

    /// Đưa phần tử `from` của ô `role` tới vị trí `to` (chỉ số trong ô sau khi đổi).
    static func reorder(role: String, from: Int, to: Int, wells: [Well]) -> Result {
        guard let w = wells.firstIndex(where: { $0.role == role }) else { return .refused("Không có ô \"\(role)\".") }
        let count = wells[w].elements.count
        guard (0..<count).contains(from), (0..<count).contains(to) else { return .refused("Vị trí ngoài ô.") }
        guard from != to else { return .unchanged }
        var result = wells
        let moved = result[w].elements.remove(at: from)
        result[w].elements.insert(moved, at: to)
        return .changed(result)
    }

    /// Chuyển phần tử `index` của ô `role` sang cuối ô `target` (giữ nguyên byte của phần tử).
    /// `column`: thông tin cột của phần tử (kiểu, `SummarizeBy`) khi cột dời sang ô chỉ nhận measure và thành trường gộp.
    static func move(role: String, index: Int, to target: String, wells: [Well], visual: ReportVisual,
                     implicitMeasures: Bool = false, column: FieldRef? = nil) -> Result {
        guard let w = wells.firstIndex(where: { $0.role == role }), wells[w].elements.indices.contains(index) else {
            return .refused("Không có trường để chuyển.")
        }
        guard role != target else { return .unchanged }
        var element = wells[w].elements[index]
        if let reason = WellRules.refusal(moving: element.field, to: target, in: visual, implicitMeasures: implicitMeasures) {
            return .refused(reason)
        }
        guard let rule = WellRules.rule(for: visual, role: target) else { return .refused("Visual này không có ô \"\(target)\".") }
        if element.field.kind == .column, !rule.accepts.contains(.column) {
            let info = column ?? FieldRef(kind: .column, entity: element.field.entity, property: element.field.property)
            var converted = PBIRQueryPatch.newAggregation(entity: element.field.entity, property: element.field.property,
                                                          function: AggregateFunction.defaultFunction(for: info).rawValue, role: target,
                                                          nativeQueryRef: element.field.nativeQueryRef ?? element.field.property)
            converted.field.displayName = element.field.displayName
            element = converted
        }
        element.field.role = target
        var result = wells
        result[w].elements.remove(at: index)
        if let t = result.firstIndex(where: { $0.role == target }) {
            if rule.isSingle { result[t].elements = [element] } else { result[t].elements.append(element) }
        } else {
            result.append(Well(role: target, elements: [element]))
        }
        return .changed(result)
    }

    // MARK: Đổi phép gộp

    /// Đổi phép gộp của trường gộp ở phần tử `index` của ô `role` (menu của trường, VM-F10). `kind` quyết định danh sách hợp lệ.
    static func setAggregation(role: String, index: Int, to function: AggregateFunction, kind: AggregateFunction.ColumnKind,
                               wells: [Well]) -> Result {
        guard let w = wells.firstIndex(where: { $0.role == role }), wells[w].elements.indices.contains(index) else {
            return .refused("Không có trường để đổi phép gộp.")
        }
        let element = wells[w].elements[index]
        guard element.field.kind == .aggregation else { return .refused("Trường này không có phép gộp.") }
        guard AggregateFunction.menu(for: kind).contains(function) else {
            return .refused("Cột kiểu này không gộp bằng \(function.label(column: element.field.property, kind: kind)).")
        }
        guard element.field.aggregationFunction != function.rawValue else { return .unchanged }
        var result = wells
        result[w].elements[index] = PBIRQueryPatch.changingAggregation(
            element, to: function.rawValue, nativeQueryRef: function.nativeQueryRef(column: element.field.property, kind: kind))
        return .changed(result)
    }

    // MARK: Đổi tên

    /// Đặt tên hiển thị riêng cho visual. Chuỗi rỗng hoặc bằng tên gốc: bỏ `displayName`.
    static func rename(role: String, index: Int, to name: String, wells: [Well]) -> Result {
        guard let w = wells.firstIndex(where: { $0.role == role }), wells[w].elements.indices.contains(index) else {
            return .refused("Không có trường để đổi tên.")
        }
        let field = wells[w].elements[index].field
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted: String? = (trimmed.isEmpty || trimmed == field.property) ? nil : trimmed
        guard wanted != field.displayName else { return .unchanged }
        var result = wells
        result[w].elements[index].field.displayName = wanted
        return .changed(result)
    }
}
