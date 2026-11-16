import Foundation
import MEngine

/// Logic thuần của hộp thoại/popover mở rộng cột bảng lồng sau Merge.
public struct ExpandColumnModel: Sendable, Equatable {
    public var sourceColumn: String
    public var allColumns: [String]
    public var selectedColumns: Set<String>
    public var usePrefix: Bool

    public init(
        sourceColumn: String,
        allColumns: [String],
        selectedColumns: Set<String>? = nil,
        usePrefix: Bool = true
    ) {
        self.sourceColumn = sourceColumn
        self.allColumns = allColumns
        self.selectedColumns = selectedColumns ?? Set(allColumns)
        self.usePrefix = usePrefix
    }

    public var isAllSelected: Bool {
        !allColumns.isEmpty && selectedColumns.count == allColumns.count
    }

    public mutating func selectAll() {
        selectedColumns = Set(allColumns)
    }

    public mutating func deselectAll() {
        selectedColumns.removeAll()
    }

    public mutating func toggle(_ column: String) {
        if selectedColumns.contains(column) {
            selectedColumns.remove(column)
        } else {
            selectedColumns.insert(column)
        }
    }

    /// Các cột đã tích theo đúng thứ tự gốc.
    public var orderedSelectedColumns: [String] {
        allColumns.filter { selectedColumns.contains($0) }
    }

    public var isValid: Bool {
        !orderedSelectedColumns.isEmpty
    }

    public func command() -> StepCommand? {
        guard isValid else { return nil }
        return .expandColumn(
            column: sourceColumn,
            names: orderedSelectedColumns,
            prefixed: usePrefix
        )
    }
}
