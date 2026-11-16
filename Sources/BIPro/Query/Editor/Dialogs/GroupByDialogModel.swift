import Foundation
import ColumnStore
import MEngine

extension GroupOperation {
    public var needsColumn: Bool {
        switch self {
        case .sum, .average, .median, .min, .max:
            return true
        case .countRows, .countDistinctRows:
            return false
        }
    }

    public var title: String {
        switch self {
        case .countRows: return "Đếm số dòng"
        case .countDistinctRows: return "Đếm số dòng khác nhau"
        case .sum: return "Tổng"
        case .average: return "Trung bình"
        case .median: return "Trung vị"
        case .min: return "Nhỏ nhất"
        case .max: return "Lớn nhất"
        }
    }
}

/// Logic thuần của hộp thoại Group By (Nhóm theo).
public struct GroupByDialogModel: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case basic
        case advanced
    }

    public struct AggregateRow: Identifiable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var operation: GroupOperation
        public var column: String?

        public init(
            id: UUID = UUID(),
            name: String,
            operation: GroupOperation,
            column: String? = nil
        ) {
            self.id = id
            self.name = name
            self.operation = operation
            self.column = column
        }
    }

    public var allColumns: [QueryColumnInfo]
    public var mode: Mode {
        didSet {
            if mode == .advanced {
                keys = [basicKey]
                aggregates = [
                    AggregateRow(name: basicNewColumnName, operation: basicOperation, column: basicColumn)
                ]
            } else {
                if let firstKey = keys.first {
                    basicKey = firstKey
                }
                if let firstAgg = aggregates.first {
                    basicNewColumnName = firstAgg.name
                    basicOperation = firstAgg.operation
                    basicColumn = firstAgg.column
                }
            }
        }
    }

    // Basic fields
    public var basicKey: String
    public var basicNewColumnName: String
    public var basicOperation: GroupOperation
    public var basicColumn: String?

    // Advanced fields
    public var keys: [String]
    public var aggregates: [AggregateRow]

    public init(
        allColumns: [QueryColumnInfo],
        initialSelectedColumns: [String] = [],
        mode: Mode = .basic
    ) {
        self.allColumns = allColumns
        self.mode = mode

        let defaultKey = initialSelectedColumns.count == 1
            ? initialSelectedColumns[0]
            : (allColumns.first?.name ?? "")

        self.basicKey = defaultKey
        self.basicNewColumnName = "Count"
        self.basicOperation = .countRows
        self.basicColumn = nil

        let initialKeys = !initialSelectedColumns.isEmpty ? initialSelectedColumns : [defaultKey]
        self.keys = allColumns.isEmpty ? [] : initialKeys
        self.aggregates = [
            AggregateRow(name: "Count", operation: .countRows, column: nil)
        ]
    }

    public mutating func addKey(_ column: String) {
        keys.append(column)
    }

    public mutating func removeKey(at index: Int) {
        guard keys.indices.contains(index) else { return }
        keys.remove(at: index)
    }

    public mutating func addAggregate(name: String, operation: GroupOperation, column: String?) {
        aggregates.append(AggregateRow(name: name, operation: operation, column: column))
    }

    public mutating func removeAggregate(at index: Int) {
        guard aggregates.indices.contains(index) else { return }
        aggregates.remove(at: index)
    }

    /// Lọc các cột hợp lệ cho một phép tính: cột số cho Tổng/TB/Trung vị, mọi cột cho Min/Max, rỗng cho Đếm dòng.
    public func validColumns(for operation: GroupOperation) -> [QueryColumnInfo] {
        switch operation {
        case .sum, .average, .median:
            return allColumns.filter { isNumeric($0.type) }
        case .min, .max:
            return allColumns
        case .countRows, .countDistinctRows:
            return []
        }
    }

    public var isValid: Bool {
        switch mode {
        case .basic:
            guard !basicKey.isEmpty else { return false }
            let trimmedName = basicNewColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return false }
            guard trimmedName != basicKey else { return false }
            if basicOperation.needsColumn {
                guard let col = basicColumn, !col.isEmpty else { return false }
                guard let colInfo = allColumns.first(where: { $0.name == col }) else { return false }
                if isNumericRequired(basicOperation) && !isNumeric(colInfo.type) { return false }
            }
            return true

        case .advanced:
            guard !keys.isEmpty else { return false }
            guard keys.allSatisfy({ !$0.isEmpty }) else { return false }
            guard Set(keys).count == keys.count else { return false }

            guard !aggregates.isEmpty else { return false }
            var seenNames = Set<String>()
            for agg in aggregates {
                let trimmed = agg.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                guard seenNames.insert(trimmed).inserted else { return false }
                guard !keys.contains(trimmed) else { return false }

                if agg.operation.needsColumn {
                    guard let col = agg.column, !col.isEmpty else { return false }
                    guard let colInfo = allColumns.first(where: { $0.name == col }) else { return false }
                    if isNumericRequired(agg.operation) && !isNumeric(colInfo.type) { return false }
                }
            }
            return true
        }
    }

    public func command() -> StepCommand? {
        guard isValid else { return nil }
        switch mode {
        case .basic:
            let trimmed = basicNewColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
            let col = basicOperation.needsColumn ? basicColumn : nil
            let agg = GroupAggregate(name: trimmed, operation: basicOperation, column: col)
            return .groupBy(keys: [basicKey], aggregates: [agg])

        case .advanced:
            let aggs = aggregates.map {
                let trimmed = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let col = $0.operation.needsColumn ? $0.column : nil
                return GroupAggregate(name: trimmed, operation: $0.operation, column: col)
            }
            return .groupBy(keys: keys, aggregates: aggs)
        }
    }

    private func isNumericRequired(_ op: GroupOperation) -> Bool {
        switch op {
        case .sum, .average, .median: return true
        default: return false
        }
    }

    private func isNumeric(_ type: DAXType) -> Bool {
        switch type {
        case .integer, .double, .currency: return true
        default: return false
        }
    }
}
