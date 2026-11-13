// D6: bộ lọc người dùng sửa → thẻ ghi vào `filterConfig.filters`, hoặc "chỉ trong phiên" kèm lý do (research R7).
import CryptoKit
import DAXEngine
import Foundation
import PBIXKit

enum FilterExport {
    /// Tên thẻ trong file. Thẻ có sẵn dùng mã của nó; thẻ người dùng thêm (`added-…`) hoặc thẻ ngầm của field (`implicit-…`)
    /// nhận tên 20 hex suy ra từ (cấp, phạm vi, cột) để lưu nhiều lần ra cùng một thẻ (research R4).
    static func cardName(for key: UserFilterKey, column: QueryColumn) -> String {
        if !(key.filterID.hasPrefix("added-") || key.filterID.hasPrefix("implicit-")) { return key.filterID }
        let digest = SHA256.hash(data: Data("\(key.level.rawValue)|\(key.scope)|\(column.table).\(column.column)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(20).lowercased()
    }

    static func literal(_ value: Value) -> FilterLiteral? {
        switch value {
        case .string(let s): .string(s)
        case .integer(let n): .integer(n)
        case .double(let d): .decimal(d)
        case .boolean(let b): .boolean(b)
        default: nil
        }
    }

    /// Một điều kiện của Filters pane → điều kiện ghi được. nil khi điều kiện còn dở (thiếu toán hạng, cột số mà toán hạng không phải số):
    /// khi đó cả thẻ chưa lọc gì, như `FilterRule.predicate`.
    private static func condition(_ condition: FilterCondition, numeric: Bool, decimal: Bool) -> PBIRFilterPatch.AdvancedCondition? {
        if condition.kind == .isBlank { return .init(.blank) }
        if condition.kind == .isNotBlank { return .init(.blank, negated: true) }
        let text = condition.operand.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let literal: FilterLiteral
        if numeric {
            if !decimal, let n = Int64(text) { literal = .integer(n) }
            else if let d = Double(text), d.isFinite { literal = .decimal(d) }
            else { return nil }
        } else {
            literal = .string(condition.operand)
        }
        switch condition.kind {
        case .isEqual: return .init(.equal, literal: literal)
        case .isNot: return .init(.equal, negated: true, literal: literal)
        case .lessThan: return .init(.lessThan, literal: literal)
        case .lessOrEqual: return .init(.lessOrEqual, literal: literal)
        case .greaterThan: return .init(.greaterThan, literal: literal)
        case .greaterOrEqual: return .init(.greaterOrEqual, literal: literal)
        case .contains: return .init(.contains, literal: literal)
        case .doesNotContain: return .init(.contains, negated: true, literal: literal)
        case .startsWith: return .init(.startsWith, literal: literal)
        case .doesNotStartWith: return .init(.startsWith, negated: true, literal: literal)
        case .isBlank, .isNotBlank: return nil
        }
    }

    /// `decimal`: cột kiểu số thực, toán hạng số nguyên cũng ghi `…D`.
    static func card(for filter: UserFilter, key: UserFilterKey, decimal: Bool = false) -> ExportResult<FilterCardSpec> {
        let column = filter.column
        let name = cardName(for: key, column: column)
        // Thẻ measure (VM-D8): `field.Measure`, luôn `type:"Advanced"`; thẻ của field visual không có `howCreated`.
        let kind: FilterCardSpec.Kind = filter.isMeasure ? .measure : .column
        func spec(type: String, filter json: String? = nil) -> FilterCardSpec {
            FilterCardSpec(name: name, kind: kind, entity: column.table, property: column.column, type: type, filter: json,
                           howCreated: filter.isMeasure ? nil : "User")
        }
        guard let rule = filter.rule else {
            if filter.isMeasure { return .writable(spec(type: "Advanced")) }
            if filter.values.isEmpty { return .writable(spec(type: "Categorical")) }
            let literals = filter.values.sorted(by: FilterTranslator.valuePrecedes).compactMap(literal)
            guard literals.count == filter.values.count else {
                return .sessionOnly("Bộ lọc có giá trị kiểu ngày hoặc tiền tệ chưa lưu được vào file.")
            }
            let json = PBIRFilterPatch.categoricalFilter(entity: column.table, property: column.column, values: literals, exclude: filter.exclude)
            return .writable(spec(type: "Categorical", filter: json))
        }
        switch rule {
        case .topN(let top):
            if filter.isMeasure { return .sessionOnly("Top N trên measure chưa lưu được vào file.") }
            let json = PBIRFilterPatch.topNFilter(entity: column.table, property: column.column,
                                                  measureEntity: top.measureTable, measureProperty: top.measureName, count: top.count,
                                                  bottom: !top.top)
            return .writable(spec(type: "TopN", filter: json))
        case .advanced(let first, let second, let useOr, let numeric):
            var conditions: [PBIRFilterPatch.AdvancedCondition] = []
            for item in [first] + (second.map { [$0] } ?? []) {
                // Điều kiện còn dở: thẻ chưa lọc gì.
                guard let ready = condition(item, numeric: numeric, decimal: decimal) else { return .writable(spec(type: "Advanced")) }
                conditions.append(ready)
            }
            guard let json = PBIRFilterPatch.advancedFilter(kind: kind, entity: column.table, property: column.column,
                                                            conditions: conditions, useOr: useOr) else {
                return .sessionOnly("Bộ lọc Advanced này chưa lưu được vào file.")
            }
            return .writable(spec(type: "Advanced", filter: json))
        }
    }
}
