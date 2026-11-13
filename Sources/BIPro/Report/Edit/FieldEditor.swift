import Foundation
import PBIXKit

/// Thao tác thuần trên cấu hình trường của một visual (danh sách ô theo thứ tự). Mỗi thao tác trả cấu hình mới,
/// "không đổi", hoặc lý do từ chối bằng tiếng Việt. Hợp đồng: `contracts/field-editing.md`.
enum FieldEditor {
    enum Result {
        case changed([PBIRQueryPatch.Well])
        case unchanged
        case refused(String)
    }

    typealias Well = PBIRQueryPatch.Well

    // MARK: Thêm

    /// Thêm `field` vào cuối ô `role`; ô một trường thì thay các trường cũ; ô chưa có trong file thì được tạo.
    static func add(_ field: FieldRef, to role: String, wells: [Well], visual: ReportVisual) -> Result {
        if let reason = WellRules.refusal(adding: field, to: role, in: visual) { return .refused(reason) }
        guard let rule = WellRules.rule(for: visual, role: role) else { return .refused("Visual này không có ô \"\(role)\".") }
        let kind: ReportField.Kind = field.kind == .column ? .column : .measure
        // Cột đầu của ô `active: true`, các cột sau `false` (Nhom6, VM-D3 mục B); measure không có cờ.
        let hasColumn = wells.first { $0.role == role }?.elements.contains { $0.field.kind != .measure && $0.field.kind != .aggregation } ?? false
        let replacing = rule.isSingle
        let element = PBIRQueryPatch.newElement(kind: kind, entity: field.entity, property: field.property, displayName: nil, role: role,
                                                active: kind == .column ? (replacing || !hasColumn) : nil)
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
    static func move(role: String, index: Int, to target: String, wells: [Well], visual: ReportVisual) -> Result {
        guard let w = wells.firstIndex(where: { $0.role == role }), wells[w].elements.indices.contains(index) else {
            return .refused("Không có trường để chuyển.")
        }
        guard role != target else { return .unchanged }
        var element = wells[w].elements[index]
        if let reason = WellRules.refusal(moving: element.field, to: target, in: visual) { return .refused(reason) }
        guard let rule = WellRules.rule(for: visual, role: target) else { return .refused("Visual này không có ô \"\(target)\".") }
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
