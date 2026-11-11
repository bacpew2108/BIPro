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

    private static let textKinds: Set<ComparisonKind> = [.contains, .doesNotContain, .startsWith, .doesNotStartWith]

    static func card(for filter: UserFilter, key: UserFilterKey) -> ExportResult<FilterCardSpec> {
        let column = filter.column
        let name = cardName(for: key, column: column)
        if filter.isMeasure { return .sessionOnly("Bộ lọc theo measure chưa lưu được vào file.") }
        guard let rule = filter.rule else {
            if filter.values.isEmpty {
                return .writable(FilterCardSpec(name: name, entity: column.table, property: column.column, type: "Categorical"))
            }
            let literals = filter.values.sorted(by: FilterTranslator.valuePrecedes).compactMap(literal)
            guard literals.count == filter.values.count else {
                return .sessionOnly("Bộ lọc có giá trị kiểu ngày hoặc tiền tệ chưa lưu được vào file.")
            }
            let json = PBIRFilterPatch.categoricalFilter(entity: column.table, property: column.column, values: literals, exclude: filter.exclude)
            return .writable(FilterCardSpec(name: name, entity: column.table, property: column.column, type: "Categorical", filter: json))
        }
        switch rule {
        case .topN(let top):
            guard top.top else { return .sessionOnly("Bottom N chưa lưu được vào file.") }
            let json = PBIRFilterPatch.topNFilter(entity: column.table, property: column.column,
                                                  measureEntity: top.measureTable, measureProperty: top.measureName, count: top.count)
            return .writable(FilterCardSpec(name: name, entity: column.table, property: column.column, type: "TopN", filter: json))
        case .advanced(let first, let second, let useOr, let numeric):
            if numeric { return .sessionOnly("Bộ lọc Advanced trên cột số chưa lưu được vào file.") }
            if useOr { return .sessionOnly("Bộ lọc Advanced nối bằng Hoặc chưa lưu được vào file.") }
            var conditions: [PBIRFilterPatch.TextCondition] = []
            for condition in [first] + (second.map { [$0] } ?? []) {
                guard textKinds.contains(condition.kind) else {
                    return .sessionOnly("Phép \"\(condition.kind.title)\" của bộ lọc Advanced chưa lưu được vào file.")
                }
                let text = condition.operand.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { // điều kiện còn dở: thẻ chưa lọc gì
                    return .writable(FilterCardSpec(name: name, entity: column.table, property: column.column, type: "Advanced"))
                }
                let isContains = condition.kind == .contains || condition.kind == .doesNotContain
                let negated = condition.kind == .doesNotContain || condition.kind == .doesNotStartWith
                conditions.append(.init(isContains ? .contains : .startsWith, negated: negated, text: condition.operand))
            }
            guard let json = PBIRFilterPatch.advancedTextFilter(entity: column.table, property: column.column, conditions: conditions) else {
                return .sessionOnly("Bộ lọc Advanced này chưa lưu được vào file.")
            }
            return .writable(FilterCardSpec(name: name, entity: column.table, property: column.column, type: "Advanced", filter: json))
        }
    }
}
