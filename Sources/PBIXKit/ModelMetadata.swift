import Foundation
import SQLite3

/// Tabular model metadata read from the ABF's `metadata.sqlitedb`.
public struct ModelMetadata: Sendable {
    /// AMO `DataType` values as stored in `Column.ExplicitDataType`/`InferredDataType`.
    public enum DataType: Int, Sendable {
        case automatic = 1, string = 2, int64 = 6, double = 8, dateTime = 9, decimal = 10, boolean = 11, binary = 17, variant = 19
        case unknown = -1

        /// TMDL / TOM spelling.
        public var tmdlName: String {
            switch self {
            case .string: "string"
            case .int64: "int64"
            case .double: "double"
            case .dateTime: "dateTime"
            case .decimal: "decimal"
            case .boolean: "boolean"
            case .binary: "binary"
            case .variant: "variant"
            case .automatic, .unknown: "automatic"
            }
        }

        public var isNumeric: Bool { [.int64, .double, .decimal].contains(self) }
    }

    /// `Column.Type`: 1 = data, 2 = calculated, 3 = row number, 4 = calculated table column.
    public enum ColumnKind: Int, Sendable {
        case data = 1, calculated = 2, rowNumber = 3, calculatedTableColumn = 4
        case unknown = -1
    }

    public struct Table: Sendable, Hashable {
        public let id: Int
        public let name: String
        public let isHidden: Bool
        /// Non-zero for engine-generated tables (`H$`, `R$`, `U$`).
        public let systemFlags: Int
        public let description: String?
        public let lineageTag: String?
        /// `Table.DataCategory`, e.g. `Time` for a marked date table.
        public let dataCategory: String?
        public var isUserTable: Bool { systemFlags == 0 }
    }

    public struct Column: Sendable, Hashable {
        public let id: Int
        public let tableID: Int
        public let tableName: String
        public let name: String
        public let kind: ColumnKind
        public let dataType: DataType
        public let isHidden: Bool
        public let expression: String?
        public let formatString: String?
        public let sortByColumnID: Int?
        /// AMO AggregateFunction: 1 default, 2 none, 3 sum, 4 min, 5 max, 6 count, 7 average, 8 distinct count.
        public let summarizeBy: Int
        /// e.g. `City`, `StateOrProvince`, `WebUrl`.
        public let dataCategory: String?
        public let displayFolder: String?
        public let isKey: Bool
        public let sourceColumn: String?
        public let description: String?
        public let lineageTag: String?

        public var summarizeByName: String {
            switch summarizeBy {
            case 2: "none"
            case 3: "sum"
            case 4: "min"
            case 5: "max"
            case 6: "count"
            case 7: "average"
            case 8: "distinctCount"
            default: "default"
            }
        }

        /// Power BI marks numeric columns that aggregate by default with Σ.
        public var isSummarizable: Bool { dataType.isNumeric && summarizeBy > 2 }
    }

    public struct Measure: Sendable, Hashable {
        public let tableName: String
        public let name: String
        public let expression: String
        public let formatString: String?
        public let displayFolder: String?
        public let isHidden: Bool
        public let description: String?
        public let lineageTag: String?
        /// `Measure.DataType` (AMO values; a measure returning text is `.string`).
        public let dataType: DataType
        /// `Measure.State`: 1 = ready. Other values mean the measure has an error or is pending.
        public let state: Int
        /// Expression of the dynamic format string (`FormatStringDefinition`), if any.
        public let formatStringDefinition: String?
    }

    public struct Hierarchy: Sendable, Hashable {
        public struct Level: Sendable, Hashable {
            public let name: String
            public let columnName: String
            public let lineageTag: String?
        }

        public let tableName: String
        public let name: String
        public let isHidden: Bool
        public let displayFolder: String?
        public let lineageTag: String?
        public let levels: [Level]
    }

    public struct Relationship: Sendable, Hashable {
        public let name: String
        public let fromTable: String
        public let fromColumn: String
        public let toTable: String
        public let toColumn: String
        public let isActive: Bool
        /// e.g. `M:1`.
        public let cardinality: String
        /// 1 = single direction, 2 = both.
        public let crossFilteringBehavior: Int
    }

    /// Where a column's VertiPaq data lives inside the ABF.
    public struct ColumnStorage: Sendable, Hashable {
        public let tableName: String
        public let columnName: String
        public let dataType: DataType
        public let dictionaryFile: String?
        public let hashIndexFile: String?
        /// One IDF per partition, in storage order.
        public let idfFiles: [String]
        public let cardinality: Int
        /// Value-encoding parameters: value = (dataID + baseID) / magnitude.
        public let baseID: Int
        public let magnitude: Double
    }

    public let tables: [Table]
    public let columns: [Column]
    public let measures: [Measure]
    public let hierarchies: [Hierarchy]
    public let relationships: [Relationship]
    public let storage: [ColumnStorage]
    /// Power Query (M) partition sources per table.
    public let partitionQueries: [String: String]
    public let roles: [String]
    public let perspectives: [String]
    public let cultures: [String]
    /// `Model.Culture`, e.g. `en-US`. Nil when the metadata has no model row.
    public let culture: String?

    public var userTables: [Table] { tables.filter(\.isUserTable) }

    public init(sqlite bytes: Data) throws {
        let db = try SQLiteReader(bytes: bytes)
        // Older schemas lack some columns; select NULL for those instead of failing.
        func col(_ table: String, _ alias: String, _ name: String) -> String {
            db.hasColumn(table, name) ? "\(alias).\(name)" : "NULL"
        }

        tables = try db.rows("""
            SELECT t.ID, t.Name, t.IsHidden, t.SystemFlags, t.Description, \(col("Table", "t", "LineageTag")),
                   \(col("Table", "t", "DataCategory"))
            FROM [Table] t ORDER BY t.ID
            """).map {
            Table(id: $0.int(0), name: $0.string(1) ?? "", isHidden: $0.int(2) != 0, systemFlags: $0.int(3),
                  description: $0.string(4), lineageTag: $0.string(5), dataCategory: $0.nonEmpty(6))
        }

        columns = try db.rows("""
            SELECT c.ID, c.TableID, t.Name, COALESCE(c.ExplicitName, c.InferredName), c.Type,
                   CASE WHEN c.ExplicitDataType = 1 THEN c.InferredDataType ELSE c.ExplicitDataType END,
                   c.IsHidden, c.Expression, c.FormatString, c.SortByColumnID, c.SummarizeBy,
                   c.DataCategory, \(col("Column", "c", "DisplayFolder")), c.IsKey, c.SourceColumn,
                   c.Description, \(col("Column", "c", "LineageTag"))
            FROM [Column] c JOIN [Table] t ON t.ID = c.TableID
            ORDER BY c.TableID, c.ID
            """).map {
            Column(id: $0.int(0), tableID: $0.int(1), tableName: $0.string(2) ?? "", name: $0.string(3) ?? "",
                   kind: ColumnKind(rawValue: $0.int(4)) ?? .unknown,
                   dataType: DataType(rawValue: $0.int(5)) ?? .unknown,
                   isHidden: $0.int(6) != 0, expression: $0.string(7), formatString: $0.string(8),
                   sortByColumnID: $0.optionalInt(9).flatMap { $0 == 0 ? nil : $0 }, summarizeBy: $0.int(10),
                   dataCategory: $0.nonEmpty(11), displayFolder: $0.nonEmpty(12), isKey: $0.int(13) != 0,
                   sourceColumn: $0.string(14), description: $0.nonEmpty(15), lineageTag: $0.string(16))
        }

        // Older files have no FormatStringDefinitionID; the dynamic format string is then absent.
        let formatDefinition = db.hasColumn("Measure", "FormatStringDefinitionID")
            ? "(SELECT f.Expression FROM FormatStringDefinition f WHERE f.ID = m.FormatStringDefinitionID)"
            : "NULL"
        measures = try db.rows("""
            SELECT t.Name, m.Name, m.Expression, m.FormatString, \(col("Measure", "m", "DisplayFolder")), m.IsHidden,
                   m.Description, \(col("Measure", "m", "LineageTag")), m.DataType, \(col("Measure", "m", "State")),
                   \(formatDefinition)
            FROM Measure m JOIN [Table] t ON t.ID = m.TableID
            ORDER BY t.Name, m.ID
            """).map {
            Measure(tableName: $0.string(0) ?? "", name: $0.string(1) ?? "", expression: $0.string(2) ?? "",
                    formatString: $0.nonEmpty(3), displayFolder: $0.nonEmpty(4), isHidden: $0.int(5) != 0,
                    description: $0.nonEmpty(6), lineageTag: $0.string(7),
                    dataType: DataType(rawValue: $0.int(8)) ?? .unknown, state: $0.int(9),
                    formatStringDefinition: $0.nonEmpty(10))
        }

        var levels: [Int: [Hierarchy.Level]] = [:]
        for row in try db.rows("""
            SELECT l.HierarchyID, l.Name, COALESCE(c.ExplicitName, c.InferredName), \(col("Level", "l", "LineageTag"))
            FROM Level l JOIN [Column] c ON c.ID = l.ColumnID
            ORDER BY l.HierarchyID, l.Ordinal
            """) {
            levels[row.int(0), default: []].append(
                Hierarchy.Level(name: row.string(1) ?? "", columnName: row.string(2) ?? "", lineageTag: row.string(3)))
        }
        hierarchies = try db.rows("""
            SELECT h.ID, t.Name, h.Name, h.IsHidden, \(col("Hierarchy", "h", "DisplayFolder")), \(col("Hierarchy", "h", "LineageTag"))
            FROM Hierarchy h JOIN [Table] t ON t.ID = h.TableID
            WHERE t.SystemFlags = 0
            ORDER BY t.Name, h.ID
            """).map {
            Hierarchy(tableName: $0.string(1) ?? "", name: $0.string(2) ?? "", isHidden: $0.int(3) != 0,
                      displayFolder: $0.nonEmpty(4), lineageTag: $0.string(5), levels: levels[$0.int(0)] ?? [])
        }

        relationships = try db.rows("""
            SELECT r.Name, ft.Name, fc.ExplicitName, tt.Name, tc.ExplicitName, r.IsActive,
                   CASE WHEN r.FromCardinality = 2 THEN 'M' ELSE '1' END || ':' ||
                   CASE WHEN r.ToCardinality = 2 THEN 'M' ELSE '1' END,
                   r.CrossFilteringBehavior
            FROM Relationship r
            JOIN [Table] ft ON ft.ID = r.FromTableID JOIN [Column] fc ON fc.ID = r.FromColumnID
            JOIN [Table] tt ON tt.ID = r.ToTableID JOIN [Column] tc ON tc.ID = r.ToColumnID
            WHERE ft.SystemFlags = 0 AND tt.SystemFlags = 0
            """).map {
            Relationship(name: $0.string(0) ?? "", fromTable: $0.string(1) ?? "", fromColumn: $0.string(2) ?? "",
                         toTable: $0.string(3) ?? "", toColumn: $0.string(4) ?? "",
                         isActive: $0.int(5) != 0, cardinality: $0.string(6) ?? "", crossFilteringBehavior: $0.int(7))
        }

        // One row per (column, partition); collapsed below into one entry per column.
        let storageRows = try db.rows("""
            SELECT t.Name, COALESCE(c.ExplicitName, c.InferredName),
                   CASE WHEN c.ExplicitDataType = 1 THEN c.InferredDataType ELSE c.ExplicitDataType END,
                   sfd.FileName, sfh.FileName, sfi.FileName, cs.Statistics_DistinctStates,
                   ds.BaseId, ds.Magnitude
            FROM [Column] c
            JOIN [Table] t ON c.TableID = t.ID
            JOIN ColumnStorage cs ON c.ColumnStorageID = cs.ID
            JOIN AttributeHierarchy ah ON ah.ColumnID = c.ID
            JOIN AttributeHierarchyStorage ahs ON ah.AttributeHierarchyStorageID = ahs.ID
            LEFT JOIN StorageFile sfh ON sfh.ID = ahs.StorageFileID
            LEFT JOIN DictionaryStorage ds ON ds.ID = cs.DictionaryStorageID
            LEFT JOIN StorageFile sfd ON sfd.ID = ds.StorageFileID
            JOIN ColumnPartitionStorage cps ON cps.ColumnStorageID = cs.ID
            JOIN StorageFile sfi ON sfi.ID = cps.StorageFileID
            JOIN PartitionStorage ps ON ps.ID = cps.PartitionStorageID
            WHERE c.Type IN (1, 2, 4)
            ORDER BY t.Name, cs.StoragePosition, ps.StoragePosition
            """)
        var collapsed: [ColumnStorage] = []
        var index: [String: Int] = [:]
        for row in storageRows {
            let key = (row.string(0) ?? "") + "\u{0}" + (row.string(1) ?? "")
            if let i = index[key] {
                let old = collapsed[i]
                collapsed[i] = ColumnStorage(tableName: old.tableName, columnName: old.columnName, dataType: old.dataType,
                                             dictionaryFile: old.dictionaryFile, hashIndexFile: old.hashIndexFile,
                                             idfFiles: old.idfFiles + [row.string(5) ?? ""], cardinality: old.cardinality,
                                             baseID: old.baseID, magnitude: old.magnitude)
                continue
            }
            index[key] = collapsed.count
            collapsed.append(ColumnStorage(
                tableName: row.string(0) ?? "", columnName: row.string(1) ?? "",
                dataType: DataType(rawValue: row.int(2)) ?? .unknown,
                dictionaryFile: row.string(3), hashIndexFile: row.string(4), idfFiles: [row.string(5) ?? ""],
                cardinality: row.int(6), baseID: row.int(7), magnitude: row.optionalDouble(8) ?? 1))
        }
        storage = collapsed

        partitionQueries = Dictionary(
            try db.rows("SELECT t.Name, p.QueryDefinition FROM Partition p JOIN [Table] t ON t.ID = p.TableID WHERE p.Type = 4")
                .map { ($0.string(0) ?? "", $0.string(1) ?? "") },
            uniquingKeysWith: { first, _ in first })

        func names(_ table: String) -> [String] {
            ((try? db.rows("SELECT Name FROM [\(table)] ORDER BY ID")) ?? []).compactMap { $0.string(0) }
        }
        roles = names("Role")
        perspectives = names("Perspective")
        cultures = names("Culture")
        culture = (try? db.rows("SELECT Culture FROM Model ORDER BY ID LIMIT 1"))?.first?.nonEmpty(0)
    }

    public func storage(table: String) -> [ColumnStorage] {
        storage.filter { $0.tableName == table }
    }

    public func storage(table: String, column: String) -> ColumnStorage? {
        storage.first { $0.tableName == table && $0.columnName == column }
    }

    public func column(id: Int) -> Column? {
        columns.first { $0.id == id }
    }
}

// MARK: - SQLite

/// Opens a serialized SQLite database in memory (no temp file).
final class SQLiteReader {
    struct Row {
        fileprivate let values: [Value]
        enum Value { case null, int(Int64), double(Double), text(String), blob }

        func int(_ i: Int) -> Int {
            switch values[i] {
            case .int(let v): Int(v)
            case .double(let v): Int(v)
            case .text(let s): Int(s) ?? 0
            default: 0
            }
        }

        func optionalInt(_ i: Int) -> Int? {
            if case .null = values[i] { return nil }
            return int(i)
        }

        func optionalDouble(_ i: Int) -> Double? {
            switch values[i] {
            case .int(let v): Double(v)
            case .double(let v): v
            default: nil
            }
        }

        func string(_ i: Int) -> String? {
            switch values[i] {
            case .text(let s): s
            case .int(let v): String(v)
            case .double(let v): String(v)
            default: nil
            }
        }

        func nonEmpty(_ i: Int) -> String? {
            string(i).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    struct Error: Swift.Error, CustomStringConvertible {
        let description: String
    }

    private var db: OpaquePointer?
    private var columnCache: [String: Set<String>] = [:]

    init(bytes: Data) throws {
        guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw Error(description: "sqlite3_open failed")
        }
        // sqlite3_deserialize takes ownership of a sqlite3_malloc'd buffer.
        let size = bytes.count
        guard let buffer = sqlite3_malloc64(sqlite3_uint64(size)) else { throw Error(description: "sqlite3_malloc failed") }
        bytes.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: size)
        let flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_READONLY)
        let rc = sqlite3_deserialize(db, "main", buffer.assumingMemoryBound(to: UInt8.self),
                                     sqlite3_int64(size), sqlite3_int64(size), flags)
        guard rc == SQLITE_OK else { throw Error(description: "sqlite3_deserialize failed (\(rc))") }
    }

    deinit { sqlite3_close(db) }

    func hasColumn(_ table: String, _ column: String) -> Bool {
        if columnCache[table] == nil {
            columnCache[table] = Set(((try? rows("PRAGMA table_info([\(table)])")) ?? []).compactMap { $0.string(1) })
        }
        return columnCache[table]?.contains(column) ?? false
    }

    func rows(_ sql: String) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Error(description: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var result: [Row] = []
        let count = sqlite3_column_count(statement)
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw Error(description: String(cString: sqlite3_errmsg(db))) }
            var values: [Row.Value] = []
            values.reserveCapacity(Int(count))
            for i in 0..<count {
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: values.append(.int(sqlite3_column_int64(statement, i)))
                case SQLITE_FLOAT: values.append(.double(sqlite3_column_double(statement, i)))
                case SQLITE_TEXT: values.append(.text(String(cString: sqlite3_column_text(statement, i))))
                case SQLITE_NULL: values.append(.null)
                default: values.append(.blob)
                }
            }
            result.append(Row(values: values))
        }
        return result
    }
}
