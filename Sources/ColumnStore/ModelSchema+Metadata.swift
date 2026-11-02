// Dựng ModelSchema từ metadata của PBIXKit (lead, đợt 0). Đợt 1a dùng cho LANG và CS.
import PBIXKit

extension ModelSchema {
    /// Ánh xạ metadata sang lược đồ engine.
    /// - Bỏ bảng hệ thống, cột số hàng (`rowNumber`) và cột có kiểu không dùng được trong DAX.
    /// - `ColumnID.index` là `Column.ID` của metadata.
    /// - Quan hệ: `ModelMetadata.Relationship` không có ID, nên `RelationshipID.raw` là vị trí trong danh sách.
    ///   Với cardinality `1:M`, phía "từ" là phía một, nên hai cột được đổi chỗ.
    ///   `crossFilteringBehavior` theo enum TOM của Microsoft: 1 = một chiều, 2 = hai chiều, 3 = tự động.
    public init(metadata: ModelMetadata) {
        func daxType(_ type: ModelMetadata.DataType) -> DAXType? {
            switch type {
            case .string: .string
            case .int64: .integer
            case .double: .double
            case .decimal: .currency
            case .dateTime: .dateTime
            case .boolean: .boolean
            case .automatic, .binary, .variant, .unknown: nil
            }
        }

        let userTableIDs = Set(metadata.tables.filter(\.isUserTable).map(\.id))

        var columnsByTable: [Int: [ModelSchema.Column]] = [:]
        var columnLookup: [String: ColumnID] = [:]
        for c in metadata.columns where c.kind != .rowNumber && c.kind != .unknown {
            guard userTableIDs.contains(c.tableID), let type = daxType(c.dataType) else { continue }
            let id = ColumnID(table: TableID(raw: c.tableID), index: c.id)
            let column = ModelSchema.Column(
                id: id,
                name: c.name,
                type: type,
                isCalculated: c.kind == .calculated || c.kind == .calculatedTableColumn,
                isHidden: c.isHidden,
                isKey: c.isKey,
                sortByColumn: c.sortByColumnID.map { ColumnID(table: id.table, index: $0) },
                formatString: c.formatString)
            columnsByTable[c.tableID, default: []].append(column)
            columnLookup[Self.lookupKey(c.tableName, c.name)] = id
        }

        let tables: [ModelSchema.Table] = metadata.tables.filter { userTableIDs.contains($0.id) }.map { t in
            ModelSchema.Table(
                id: TableID(raw: t.id),
                name: t.name,
                isHidden: t.isHidden,
                isUserTable: true,
                isDateTable: t.dataCategory == "Time",
                columns: columnsByTable[t.id] ?? [])
        }

        var relationships: [RelationshipSchema] = []
        for r in metadata.relationships {
            guard let from = columnLookup[Self.lookupKey(r.fromTable, r.fromColumn)],
                  let to = columnLookup[Self.lookupKey(r.toTable, r.toColumn)] else { continue }
            let fromIsOne = r.cardinality.hasPrefix("1:")
            let many = fromIsOne ? to : from
            let one = fromIsOne ? from : to
            let behavior: CrossFilterBehavior
            switch r.crossFilteringBehavior {
            case 1: behavior = .oneDirection
            case 2: behavior = .bothDirections
            default: behavior = .automatic
            }
            relationships.append(RelationshipSchema(
                id: RelationshipID(raw: relationships.count),
                name: r.name,
                manyColumn: many,
                oneColumn: one,
                isActive: r.isActive,
                crossFilter: behavior))
        }

        self.init(culture: metadata.culture ?? "en-US", tables: tables, relationships: relationships)
    }

    private static func lookupKey(_ table: String, _ column: String) -> String {
        table.lowercased() + "\u{0}" + column.lowercased()
    }
}
