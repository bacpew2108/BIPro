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
        /// Bảng tính toán do người dùng tạo (phân vùng DAX). Desktop ghi `SystemFlags = 2` cho cả bảng này lẫn bảng ngày tự động
        /// (`LocalDateTable_…`, `DateTableTemplate_…`), nên phải phân biệt riêng (w8.3, `docs/phase-f-evidence/vm-f6/QUAN-SAT.md`).
        public var isCalculatedUserTable: Bool = false
        public var isUserTable: Bool { systemFlags == 0 || isCalculatedUserTable }
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
        /// `JoinOnDateBehavior`: 1 = ngày giờ đầy đủ, 2 = chỉ phần ngày (quan hệ tới bảng ngày cục bộ của Auto date/time).
        public var joinOnDateBehavior: Int = 1
    }

    /// Dòng `Variation` (Auto date/time): cột ngày `table[column]` hiện phân cấp mặc định của bảng ngày cục bộ qua `relationship`.
    public struct Variation: Sendable, Hashable {
        public let table: String
        public let column: String
        public let name: String
        public let relationship: String
        public let hierarchy: HierarchyRef
        public let isDefault: Bool
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

    /// Một quy tắc lọc RLS của vai trò trên một bảng (`[TablePermission]`, Desktop 2.159).
    public struct TablePermission: Sendable, Hashable {
        public let tableName: String
        public let filterExpression: String

        public init(tableName: String, filterExpression: String) {
            self.tableName = tableName
            self.filterExpression = filterExpression
        }
    }

    /// Một vai trò bảo mật cấp dòng (`[Role]` + `[TablePermission]`, `ModelPermission.Read = 2`).
    public struct RoleDefinition: Sendable, Hashable {
        public let name: String
        public let description: String?
        public let modelPermission: Int
        public let tablePermissions: [TablePermission]

        public init(name: String, description: String? = nil, modelPermission: Int = 2, tablePermissions: [TablePermission] = []) {
            self.name = name
            self.description = description
            self.modelPermission = modelPermission
            self.tablePermissions = tablePermissions
        }
    }

    public let tables: [Table]
    public let columns: [Column]
    public let measures: [Measure]
    public let hierarchies: [Hierarchy]
    public let relationships: [Relationship]
    public let storage: [ColumnStorage]
    /// Power Query (M) partition sources per table.
    public let partitionQueries: [String: String]
    /// Biểu thức DAX của bảng tính toán (phân vùng kiểu 2) theo tên bảng, kể cả bảng ngày tự động của Desktop.
    public let calculatedTableExpressions: [String: String]
    public let roles: [String]
    /// Định nghĩa chi tiết các vai trò RLS (`[Role]` + `[TablePermission]`, v1.2).
    public let roleDefinitions: [RoleDefinition]
    public let perspectives: [String]
    public let cultures: [String]
    /// Shared Power Query expressions (`Expression`), e.g. parameters and shared queries.
    public let expressions: [String]
    /// Biểu thức M của các mục trong `expressions` (tên → văn bản): truy vấn không nạp (Enable load tắt) và tham số. Rỗng nếu bảng `Expression` không có.
    public let expressionBodies: [String: String]
    /// Tables that are calculation groups (`CalculationGroup` → `Table`).
    public let calculationGroups: [String]
    /// User-defined DAX functions (`Function`); empty when the file predates them.
    public let functions: [String]
    /// `Model.Culture`, e.g. `en-US`. Nil when the metadata has no model row.
    public let culture: String?
    /// Chú thích của mô hình (`Annotation`, ObjectType 1), ví dụ `__PBI_TimeIntelligenceEnabled`, `PBI_QueryOrder`.
    public let modelAnnotations: [String: String]
    /// `Model.DiscourageImplicitMeasures`: bật thì ô giá trị của visual chỉ nhận measure (Nhom6), tắt thì cột tự gộp (US1).
    public let discourageImplicitMeasures: Bool
    /// Quan hệ có một đầu là bảng ngày cục bộ hay bảng mẫu của Auto date/time. Tách khỏi `relationships` vì các bảng đó ẩn với người dùng.
    public let dateTableRelationships: [Relationship]
    public let variations: [Variation]

    public var userTables: [Table] { tables.filter(\.isUserTable) }

    /// Bảng ngày của Auto date/time (bảng mẫu và bảng cục bộ): bảng tính toán `SystemFlags = 2` không phải bảng người dùng.
    public var autoDateTables: Set<String> {
        Set(tables.filter { $0.systemFlags == 2 && !$0.isCalculatedUserTable && calculatedTableExpressions[$0.name] != nil }.map(\.name))
    }

    public init(sqlite bytes: Data) throws {
        let db = try SQLiteReader(bytes: bytes)
        // Older schemas lack some columns; select NULL for those instead of failing.
        func col(_ table: String, _ alias: String, _ name: String) -> String {
            db.hasColumn(table, name) ? "\(alias).\(name)" : "NULL"
        }

        // Bảng tính toán của người dùng: phân vùng kiểu 2 (Calculated), không riêng tư, không chỉ hiện như biến thể, không mang chú thích
        // bảng ngày tự động của Desktop.
        let calculatedUserTables = Set(((try? db.rows("""
            SELECT t.ID FROM [Table] t JOIN Partition p ON p.TableID = t.ID
            WHERE p.Type = 2 AND COALESCE(\(col("Table", "t", "IsPrivate")), 0) = 0
              AND COALESCE(\(col("Table", "t", "ShowAsVariationsOnly")), 0) = 0
              AND NOT EXISTS (SELECT 1 FROM Annotation a WHERE a.ObjectType = 3 AND a.ObjectID = t.ID
                              AND a.Name IN ('__PBI_LocalDateTable', '__PBI_TemplateDateTable'))
            """)) ?? []).map { $0.int(0) })
        tables = try db.rows("""
            SELECT t.ID, t.Name, t.IsHidden, t.SystemFlags, t.Description, \(col("Table", "t", "LineageTag")),
                   \(col("Table", "t", "DataCategory"))
            FROM [Table] t ORDER BY t.ID
            """).map {
            Table(id: $0.int(0), name: $0.string(1) ?? "", isHidden: $0.int(2) != 0, systemFlags: $0.int(3),
                  description: $0.string(4), lineageTag: $0.string(5), dataCategory: $0.nonEmpty(6),
                  isCalculatedUserTable: calculatedUserTables.contains($0.int(0)))
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

        // Bảng tính toán (`SystemFlags = 2`) cũng có quan hệ: bảng người dùng (CALENDAR…) và bảng ngày của Auto date/time.
        let autoDateTables = Set(((try? db.rows("""
            SELECT ObjectID FROM Annotation WHERE ObjectType = 3 AND Name IN ('__PBI_LocalDateTable', '__PBI_TemplateDateTable')
            """)) ?? []).map { $0.int(0) })
        let allRelationships = try db.rows("""
            SELECT r.Name, ft.Name, COALESCE(fc.ExplicitName, fc.InferredName), tt.Name, COALESCE(tc.ExplicitName, tc.InferredName), r.IsActive,
                   CASE WHEN r.FromCardinality = 2 THEN 'M' ELSE '1' END || ':' ||
                   CASE WHEN r.ToCardinality = 2 THEN 'M' ELSE '1' END,
                   r.CrossFilteringBehavior, \(col("Relationship", "r", "JoinOnDateBehavior")), ft.ID, tt.ID
            FROM Relationship r
            JOIN [Table] ft ON ft.ID = r.FromTableID JOIN [Column] fc ON fc.ID = r.FromColumnID
            JOIN [Table] tt ON tt.ID = r.ToTableID JOIN [Column] tc ON tc.ID = r.ToColumnID
            WHERE ft.SystemFlags IN (0, 2) AND tt.SystemFlags IN (0, 2)
            """).map {
            (Relationship(name: $0.string(0) ?? "", fromTable: $0.string(1) ?? "", fromColumn: $0.string(2) ?? "",
                          toTable: $0.string(3) ?? "", toColumn: $0.string(4) ?? "",
                          isActive: $0.int(5) != 0, cardinality: $0.string(6) ?? "", crossFilteringBehavior: $0.int(7),
                          joinOnDateBehavior: $0.int(8) == 0 ? 1 : $0.int(8)),
             autoDateTables.contains($0.int(9)) || autoDateTables.contains($0.int(10)))
        }
        relationships = allRelationships.filter { !$0.1 }.map(\.0)
        dateTableRelationships = allRelationships.filter(\.1).map(\.0)
        variations = db.hasColumn("Variation", "DefaultHierarchyID") ? ((try? db.rows("""
            SELECT t.Name, COALESCE(c.ExplicitName, c.InferredName), v.Name, r.Name, ht.Name, h.Name, v.IsDefault
            FROM Variation v JOIN [Column] c ON c.ID = v.ColumnID JOIN [Table] t ON t.ID = c.TableID
            JOIN Relationship r ON r.ID = v.RelationshipID
            JOIN Hierarchy h ON h.ID = v.DefaultHierarchyID JOIN [Table] ht ON ht.ID = h.TableID
            ORDER BY v.ID
            """)) ?? []).map {
            Variation(table: $0.string(0) ?? "", column: $0.string(1) ?? "", name: $0.string(2) ?? "", relationship: $0.string(3) ?? "",
                      hierarchy: HierarchyRef(table: $0.string(4) ?? "", name: $0.string(5) ?? ""), isDefault: $0.int(6) != 0)
        } : []

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
        calculatedTableExpressions = Dictionary(
            try db.rows("SELECT t.Name, p.QueryDefinition FROM Partition p JOIN [Table] t ON t.ID = p.TableID WHERE p.Type = 2")
                .map { ($0.string(0) ?? "", $0.string(1) ?? "") },
            uniquingKeysWith: { first, _ in first })

        func names(_ table: String) -> [String] {
            ((try? db.rows("SELECT Name FROM [\(table)] ORDER BY ID")) ?? []).compactMap { $0.string(0) }
        }
        let rawRoleRows = (try? db.rows("SELECT ID, Name, Description, ModelPermission FROM [Role] ORDER BY ID")) ?? []
        let rawPermRows = (try? db.rows("""
            SELECT tp.RoleID, t.Name, tp.FilterExpression
            FROM [TablePermission] tp JOIN [Table] t ON t.ID = tp.TableID
            ORDER BY tp.ID
            """)) ?? []
        var permsByRole: [Int: [TablePermission]] = [:]
        for row in rawPermRows {
            let roleID = row.int(0)
            guard let tableName = row.string(1), let expr = row.nonEmpty(2) else { continue }
            permsByRole[roleID, default: []].append(TablePermission(tableName: tableName, filterExpression: expr))
        }
        let parsedRoles: [RoleDefinition] = rawRoleRows.compactMap { row in
            let id = row.int(0)
            guard let name = row.nonEmpty(1) else { return nil }
            let mp = row.int(3)
            return RoleDefinition(
                name: name,
                description: row.nonEmpty(2),
                modelPermission: mp > 0 ? mp : 2,
                tablePermissions: permsByRole[id] ?? []
            )
        }
        roleDefinitions = parsedRoles
        roles = parsedRoles.map(\.name)
        perspectives = names("Perspective")
        cultures = names("Culture")
        expressions = names("Expression")
        expressionBodies = Dictionary(
            ((try? db.rows("SELECT Name, Expression FROM [Expression] ORDER BY ID")) ?? []).map { ($0.string(0) ?? "", $0.string(1) ?? "") },
            uniquingKeysWith: { first, _ in first })
        functions = names("Function")
        calculationGroups = ((try? db.rows(
            "SELECT t.Name FROM CalculationGroup c JOIN [Table] t ON t.ID = c.TableID ORDER BY c.ID")) ?? [])
            .compactMap { $0.string(0) }
        culture = (try? db.rows("SELECT Culture FROM Model ORDER BY ID LIMIT 1"))?.first?.nonEmpty(0)
        discourageImplicitMeasures = db.hasColumn("Model", "DiscourageImplicitMeasures")
            && ((try? db.rows("SELECT DiscourageImplicitMeasures FROM Model ORDER BY ID LIMIT 1"))?.first?.int(0) ?? 0) != 0
        modelAnnotations = Dictionary(
            ((try? db.rows("SELECT Name, Value FROM Annotation WHERE ObjectType = 1 ORDER BY ID")) ?? []).map { ($0.string(0) ?? "", $0.string(1) ?? "") },
            uniquingKeysWith: { first, _ in first })
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
