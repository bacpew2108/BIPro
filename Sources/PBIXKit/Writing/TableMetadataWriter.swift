import Foundation
import SQLite3

/// Adds the metadata rows of one VertiPaq table (T3, WP5) to `metadata.sqlitedb`.
///
/// `MetadataWriter` (WP4) only adds measures. This writer adds a whole table: `Table`, `Column`,
/// `Partition` and the storage rows (`TableStorage`, `StorageFolder`, `PartitionStorage`,
/// `SegmentMapStorage`, `ColumnStorage`, `DictionaryStorage`, `ColumnPartitionStorage`,
/// `SegmentStorage`, `StorageFile`, `AttributeHierarchy`, `AttributeHierarchyStorage`).
/// Storage object IDs come from the shared counter (`DBPROPERTIES.MAXID + 1`, then up); the table,
/// partition and column IDs are chosen by the caller and must be above `MAXID`.
///
/// Works on an in-memory copy. The bytes given to `init` are not changed. `addTable` is one
/// transaction: a failed call leaves the copy as it was.
public struct TableMetadataWriter {
    /// `DBPROPERTIES.MAXID` as stored. Equals the largest ID in the database (checked in `init`).
    public private(set) var maxID: Int

    private let database: TableMetadataDatabase

    /// Opens the database and checks it. Throws `WriteError.invalid` for empty, non-SQLite or
    /// incomplete input, and `WriteError.verificationFailed` when `MAXID` is not the largest ID.
    public init(sqlite: Data) throws {
        database = try TableMetadataDatabase(bytes: sqlite)
        try database.requireIntegrity()
        for table in ["DBPROPERTIES", "Model", "Table", "Column", "Partition", "PartitionStorage", "TableStorage",
                      "ColumnStorage", "DictionaryStorage", "ColumnPartitionStorage", "SegmentStorage",
                      "SegmentMapStorage", "StorageFile", "StorageFolder", "AttributeHierarchy",
                      "AttributeHierarchyStorage"] where !database.tableExists(table) {
            throw WriteError.invalid("metadata.sqlitedb has no \(table) table")
        }
        let stored = try database.storedMaxID()
        let actual = try database.actualMaxID()
        guard stored == actual else {
            throw WriteError.verificationFailed("DBPROPERTIES.MAXID is \(stored) but the largest ID is \(actual)")
        }
        maxID = stored
    }

    /// Adds the table described by `table`. Its `tableID`, `partitionID` and column IDs must be
    /// above `maxID` and unused. Storage IDs are allocated after the largest of them.
    ///
    /// Throws `WriteError.invalid` when the table name exists, an ID is already used, or a
    /// required value is missing. A failed call leaves the database unchanged.
    public mutating func addTable(_ table: VertiPaqWriter.EncodedTable) throws {
        let db = database
        let callerIDs = [table.tableID, table.partitionID] + table.columns.map(\.id)
        guard callerIDs.allSatisfy({ $0 > maxID }) else {
            throw WriteError.invalid("table, partition and column IDs must be above MAXID \(maxID)")
        }
        guard Set(callerIDs).count == callerIDs.count else { throw WriteError.invalid("object IDs repeat") }
        guard try db.int("SELECT COUNT(*) FROM [Table] WHERE Name = ? COLLATE NOCASE", [.text(table.name)]) == 0 else {
            throw WriteError.invalid("a table named '\(table.name)' already exists")
        }
        for id in callerIDs {
            for name in ["Table", "Partition", "Column"] {
                guard try !db.objectIDExists(id, inTable: name) else {
                    throw WriteError.invalid("ID \(id) is already used in \(name)")
                }
            }
        }
        guard let modelID = try db.int("SELECT MIN(ID) FROM Model") else {
            throw WriteError.invalid("metadata.sqlitedb has no Model row")
        }

        var next = max(maxID, callerIDs.max() ?? maxID) + 1
        func allocate() -> Int64 {
            defer { next += 1 }
            return Int64(next)
        }

        let now = Self.fileTimeNow()
        let refreshedNever: Int64 = 31_240_512_000_000_000 // sentinel used for "never refreshed"
        let tableStorageID = allocate()
        let tableFolderID = allocate()
        let partitionStorageID = allocate()
        let partitionFolderID = allocate()
        let segmentMapID = allocate()
        let tableID = Int64(table.tableID)
        let partitionID = Int64(table.partitionID)

        try db.exec("BEGIN IMMEDIATE")
        do {
            try db.run("""
                INSERT INTO StorageFolder (ID, OwnerID, OwnerType, Path) VALUES (?, ?, 18, ?)
                """, [.int(tableFolderID), .int(tableStorageID), .text(table.tableFolderPath)])
            try db.run("""
                INSERT INTO TableStorage (ID, TableID, Name, Version, Settings, RIViolationCount, StorageFolderID)
                VALUES (?, ?, ?, 0, 4353, 0, ?)
                """, [.int(tableStorageID), .int(tableID), .text("\(table.name) (\(table.tableID))"), .int(tableFolderID)])
            try db.run("""
                INSERT INTO [Table] (ID, ModelID, Name, DataCategory, Description, IsHidden, TableStorageID,
                    ModifiedTime, StructureModifiedTime, SystemFlags, ShowAsVariationsOnly, IsPrivate,
                    DefaultDetailRowsDefinitionID, AlternateSourcePrecedence, RefreshPolicyID, CalculationGroupID,
                    ExcludeFromModelRefresh, LineageTag, SourceLineageTag, SystemManaged,
                    ExcludeFromAutomaticAggregations, DirectLakeIndexingBehavior)
                VALUES (?, ?, ?, NULL, NULL, 0, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, ?, NULL, 0, 0, 3)
                """, [.int(tableID), .int(modelID), .text(table.name), .int(tableStorageID), .int(now), .int(now),
                      .text(UUID().uuidString.lowercased())])

            try db.run("""
                INSERT INTO StorageFolder (ID, OwnerID, OwnerType, Path) VALUES (?, ?, 20, ?)
                """, [.int(partitionFolderID), .int(partitionStorageID), .text(table.partitionFolderPath)])
            try db.run("""
                INSERT INTO PartitionStorage (ID, PartitionID, Name, StoragePosition, SegmentMapStorageID, DataObjectId,
                    StorageFolderID, DeltaTableMetadataStorageID) VALUES (?, ?, ?, 0, ?, 0, ?, 0)
                """, [.int(partitionStorageID), .int(partitionID), .text("\(table.name) (\(table.partitionID))"),
                      .int(segmentMapID), .int(partitionFolderID)])
            try db.run("""
                INSERT INTO SegmentMapStorage (ID, PartitionStorageID, Type, RecordCount, SegmentCount, RecordsPerSegment)
                VALUES (?, ?, 3, ?, 1, ?)
                """, [.int(segmentMapID), .int(partitionStorageID), .int(Int64(table.rowCount)), .int(Int64(table.rowCount))])
            // A table without a source query. Power BI treats it as a stored (Type 4) partition with an empty query.
            try db.run("""
                INSERT INTO Partition (ID, TableID, Name, Description, DataSourceID, QueryDefinition, State, Type,
                    PartitionStorageID, Mode, DataView, ModifiedTime, RefreshedTime, SystemFlags, ErrorMessage,
                    RetainDataTillForceCalculate, RangeStart, RangeEnd, RangeGranularity, RefreshBookmark,
                    QueryGroupID, ExpressionSourceID, MAttributes, DataCoverageDefinitionID, SchemaName)
                VALUES (?, ?, ?, NULL, 0, '', 1, 4, ?, 0, 0, ?, ?, 0, NULL, 0, 0.0, 0.0, -1, NULL, 0, 0, NULL, 0, NULL)
                """, [.int(partitionID), .int(tableID), .text(table.name), .int(partitionStorageID), .int(now), .int(now)])

            for column in table.columns {
                try insertColumn(column, table: table, tableID: tableID, now: now, refreshedNever: refreshedNever,
                                 tableFolderID: tableFolderID, partitionFolderID: partitionFolderID,
                                 partitionStorageID: partitionStorageID, allocate: allocate)
            }

            try db.run("UPDATE DBPROPERTIES SET VALUE = ? WHERE NAME = 'MAXID'", [.int(Int64(next - 1))])
            try db.exec("COMMIT")
        } catch {
            db.rollbackIfOpen()
            throw error
        }
        maxID = next - 1
    }

    /// The edited database as a `metadata.sqlitedb` file.
    public func serialize() throws -> Data {
        try database.serialize()
    }

    // MARK: - Column rows

    private func insertColumn(_ column: VertiPaqWriter.EncodedColumn, table: VertiPaqWriter.EncodedTable,
                              tableID: Int64, now: Int64, refreshedNever: Int64, tableFolderID: Int64,
                              partitionFolderID: Int64, partitionStorageID: Int64,
                              allocate: () -> Int64) throws {
        let db = database
        let columnStorageID = allocate()
        let dictionaryStorageID = allocate()
        let attributeID = allocate()
        let attributeStorageID = allocate()
        let columnPartitionID = allocate()
        let segmentStorageID = allocate()
        let idfFileID = allocate()
        let idfmetaFileID = allocate()
        let dictionaryFileID: Int64? = column.dictionary == nil ? nil : allocate()
        let isRowNumber = column.kind == .rowNumber
        let columnID = Int64(column.id)
        let dataType = Int64(column.dataType.rawValue)

        let dbType: Int64 = isRowNumber ? 20 : (column.dataType == .string ? 130 : (column.dataType == .double ? 5 : 20))
        try db.run("""
            INSERT INTO ColumnStorage (ID, ColumnID, Name, StoragePosition, DictionaryStorageID, Settings, ColumnFlags,
                Collation, OrderByColumn, Locale, BinaryCharacters, Statistics_DistinctStates, Statistics_MinDataID,
                Statistics_MaxDataID, Statistics_OriginalMinSegmentDataID, Statistics_RLESortOrder, Statistics_RowCount,
                Statistics_HasNulls, Statistics_RLERuns, Statistics_OthersRLERuns, Statistics_Usage, Statistics_DBType,
                Statistics_XMType, Statistics_CompressionType, Statistics_CompressionParam, Statistics_EncodingHint,
                IsDeltaPartitionColumn, DeltaColumnMappingPhysicalName, DeltaColumnMappingId, FramedSourceColumn,
                DeltaColumnPrimitiveType, DeltaTableColumnStorageID, StringIndexStorageID, ColumnIndexStorageID,
                FullTextIndexStorageID)
            VALUES (?, ?, ?, ?, ?, 1, ?, '', '', 1033, 0, ?, ?, ?, ?, -1, ?, ?, 0, 0, 3, ?, 0, 0, 0, 0,
                0, NULL, -1, NULL, 0, 0, 0, 0, 0)
            """, [
                .int(columnStorageID), .int(columnID), .text(column.storageName), .int(Int64(column.storagePosition)),
                .int(dictionaryStorageID), .int(isRowNumber ? 31 : 8),
                .int(Int64(column.distinctCount)), .int(Int64(column.minDataID)), .int(Int64(column.maxDataID)),
                .int(Int64(column.originalMinDataID)), .int(Int64(column.rowCount)),
                .int(column.hasNulls ? 1 : 0), .int(dbType),
            ])

        try db.run("""
            INSERT INTO DictionaryStorage (ID, ColumnStorageID, Type, DataType, DataVersion, BaseId, Magnitude, LastId,
                IsNullable, IsUnique, IsOperatingOn32, DictionaryFlags, StorageFileID, Size)
            VALUES (?, ?, ?, ?, 0, ?, ?, ?, 1, 0, 0, 0, ?, ?)
            """, [
                .int(dictionaryStorageID), .int(columnStorageID), .int(Int64(column.dictionaryType)), .int(dataType),
                .int(Int64(column.dictionaryBaseID)), .double(column.magnitude), .int(Int64(column.maxDataID)),
                .int(dictionaryFileID ?? 0), .int(Int64(column.dictionaryByteCount)),
            ])
        if let dictionary = column.dictionary, let dictionaryFileID {
            try insertStorageFile(id: dictionaryFileID, owner: dictionaryStorageID, ownerType: 22,
                                  folder: tableFolderID, fileName: dictionary.fileName)
        }

        try db.run("""
            INSERT INTO AttributeHierarchy (ID, ColumnID, State, AttributeHierarchyStorageID, ModifiedTime, RefreshedTime)
            VALUES (?, ?, 1, ?, ?, ?)
            """, [.int(attributeID), .int(columnID), .int(attributeStorageID), .int(now), .int(now)])
        let materialization: Int64 = isRowNumber ? 3 : 0
        let positionToData: Int64 = isRowNumber ? -1 : 0
        let dataToPosition: Int64 = isRowNumber ? -1 : 1
        let maxLength = Int64(column.stringValueMaxLength)
        try db.run("""
            INSERT INTO AttributeHierarchyStorage (ID, AttributeHierarchyID, SortOrder, OptimizationLevel,
                MaterializationType, ColumnPositionToData, ColumnDataToPosition, DistinctDataCount, DataVersion,
                StorageFileID, SystemTableID, HasStatistics, MinValue, MaxValue, StringValueMaxLength)
            VALUES (?, ?, 0, 0, ?, ?, ?, ?, 1, 0, 0, 1, ?, ?, ?)
            """, [
                .int(attributeStorageID), .int(attributeID), .int(materialization), .int(positionToData),
                .int(dataToPosition), .int(Int64(column.distinctCount)),
                Self.optionalText(column.minValueText), Self.optionalText(column.maxValueText), .int(maxLength),
            ])

        try db.run("""
            INSERT INTO ColumnPartitionStorage (ID, ColumnStorageID, PartitionStorageID, DataVersion, State,
                SegmentStorageID, StorageFileID) VALUES (?, ?, ?, 0, 1, ?, ?)
            """, [.int(columnPartitionID), .int(columnStorageID), .int(partitionStorageID),
                  .int(segmentStorageID), .int(idfFileID)])
        try db.run("""
            INSERT INTO SegmentStorage (ID, ColumnPartitionStorageID, SegmentCount, StorageFileID)
            VALUES (?, ?, 1, ?)
            """, [.int(segmentStorageID), .int(columnPartitionID), .int(idfmetaFileID)])
        try insertStorageFile(id: idfFileID, owner: columnPartitionID, ownerType: 23, folder: partitionFolderID,
                              fileName: column.idf.fileName)
        try insertStorageFile(id: idfmetaFileID, owner: segmentStorageID, ownerType: 24, folder: partitionFolderID,
                              fileName: column.idfmeta.fileName)

        // The Column row last, so it can refer to the storage IDs above.
        let isData = !isRowNumber
        try db.run("""
            INSERT INTO [Column] (ID, TableID, ExplicitName, InferredName, ExplicitDataType, InferredDataType,
                DataCategory, Description, IsHidden, State, IsUnique, IsKey, IsNullable, Alignment,
                TableDetailPosition, IsDefaultLabel, IsDefaultImage, SummarizeBy, ColumnStorageID, Type, SourceColumn,
                ColumnOriginID, Expression, FormatString, IsAvailableInMDX, SortByColumnID, AttributeHierarchyID,
                ModifiedTime, StructureModifiedTime, RefreshedTime, SystemFlags, KeepUniqueRows, DisplayOrdinal,
                ErrorMessage, SourceProviderType, DisplayFolder, EncodingHint, RelatedColumnDetailsID, AlternateOfID,
                LineageTag, SourceLineageTag, ExpressionContext, StringIndexingBehavior, FullTextIndexingBehavior)
            VALUES (?, ?, ?, NULL, ?, 19, NULL, NULL, ?, 1, ?, ?, ?, ?, -1, 0, 0, ?, ?, ?, ?, 0, NULL, NULL, 1, 0, ?,
                ?, ?, ?, 0, 0, 0, NULL, NULL, NULL, 0, 0, 0, ?, NULL, 1, 1, 0)
            """, [
                .int(columnID), .int(tableID), .text(column.explicitName), .int(dataType),
                .int(isRowNumber ? 1 : 0), .int(isRowNumber ? 1 : 0), .int(isRowNumber ? 1 : 0),
                .int(isRowNumber ? 0 : 1), .int(isRowNumber ? 1 : 0),
                .int(Self.summarizeBy(column.dataType, isRowNumber: isRowNumber)),
                .int(columnStorageID), .int(isRowNumber ? 3 : 1), Self.optionalText(isData ? column.explicitName : nil),
                .int(attributeID), .int(now), .int(now), .int(refreshedNever),
                .text(UUID().uuidString.lowercased()),
            ])
    }

    private func insertStorageFile(id: Int64, owner: Int64, ownerType: Int64, folder: Int64, fileName: String) throws {
        try database.run("""
            INSERT INTO StorageFile (ID, OwnerID, OwnerType, StorageFolderID, FileName) VALUES (?, ?, ?, ?, ?)
            """, [.int(id), .int(owner), .int(ownerType), .int(folder), .text(fileName)])
    }

    /// `Column.SummarizeBy` as observed in `tuan6.2.pbix`: strings 2, numbers 3, RowNumber 1.
    static func summarizeBy(_ type: ModelMetadata.DataType, isRowNumber: Bool) -> Int64 {
        if isRowNumber { return 1 }
        return type == .string ? 2 : 3
    }

    static func optionalText(_ value: String?) -> TableMetadataDatabase.Value {
        guard let value else { return .null }
        return .text(value)
    }

    /// Windows FILETIME: 100 ns ticks since 1601-01-01 UTC.
    static func fileTimeNow() -> Int64 {
        Int64((Date().timeIntervalSince1970 + 11_644_473_600) * 10_000_000)
    }
}

// MARK: - SQLite access

/// One in-memory SQLite connection holding a serialized `metadata.sqlitedb`.
final class TableMetadataDatabase {
    enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case null
    }

    private var handle: OpaquePointer?

    init(bytes: Data) throws {
        guard !bytes.isEmpty else { throw WriteError.invalid("metadata.sqlitedb is empty") }
        guard sqlite3_open_v2(":memory:", &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw WriteError.invalid("sqlite3_open failed")
        }
        let size = bytes.count
        guard let buffer = sqlite3_malloc64(sqlite3_uint64(size)) else {
            throw WriteError.invalid("sqlite3_malloc failed")
        }
        bytes.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: size)
        let flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE)
        let rc = sqlite3_deserialize(handle, "main", buffer.assumingMemoryBound(to: UInt8.self),
                                     sqlite3_int64(size), sqlite3_int64(size), flags)
        guard rc == SQLITE_OK else { throw WriteError.invalid("sqlite3_deserialize failed (\(rc))") }
    }

    deinit { sqlite3_close(handle) }

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func failure() -> WriteError {
        WriteError.invalid("sqlite: " + String(cString: sqlite3_errmsg(handle)))
    }

    func run(_ sql: String, _ values: [Value] = []) throws {
        try query(sql, values) { _ in }
    }

    func exec(_ sql: String) throws {
        try run(sql)
    }

    func strings(_ sql: String, _ values: [Value] = []) throws -> [String] {
        var result: [String] = []
        try query(sql, values) { statement in
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
        }
        return result
    }

    func int(_ sql: String, _ values: [Value] = []) throws -> Int64? {
        var result: Int64?
        try query(sql, values) { statement in
            if result == nil, sqlite3_column_type(statement, 0) != SQLITE_NULL {
                result = sqlite3_column_int64(statement, 0)
            }
        }
        return result
    }

    private func query(_ sql: String, _ values: [Value], _ row: (OpaquePointer?) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let rc: Int32
            switch value {
            case .int(let number): rc = sqlite3_bind_int64(statement, position, number)
            case .double(let number): rc = sqlite3_bind_double(statement, position, number)
            case .text(let text): rc = sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .null: rc = sqlite3_bind_null(statement, position)
            }
            guard rc == SQLITE_OK else { throw failure() }
        }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw failure() }
            row(statement)
        }
    }

    func requireIntegrity() throws {
        let results = try strings("PRAGMA integrity_check")
        guard results == ["ok"] else {
            throw WriteError.invalid("PRAGMA integrity_check: \(results.prefix(3).joined(separator: "; "))")
        }
    }

    func tableExists(_ name: String) -> Bool {
        ((try? int("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?", [.text(name)])) ?? 0) == 1
    }

    func objectIDExists(_ id: Int, inTable table: String) throws -> Bool {
        try (int("SELECT COUNT(*) FROM [\(table)] WHERE ID = ?", [.int(Int64(id))]) ?? 0) > 0
    }

    func storedMaxID() throws -> Int {
        guard let value = try int("SELECT VALUE FROM DBPROPERTIES WHERE NAME = 'MAXID'") else {
            throw WriteError.verificationFailed("DBPROPERTIES has no MAXID")
        }
        return Int(value)
    }

    /// The largest ID in every table that has an `ID` column.
    func actualMaxID() throws -> Int {
        let tables = try strings("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        var parts: [String] = []
        for table in tables {
            let columns = try strings("SELECT name FROM pragma_table_info(?)", [.text(table)])
            guard columns.contains("ID") else { continue }
            parts.append("SELECT MAX(\"ID\") AS m FROM \"\(table.replacingOccurrences(of: "\"", with: "\"\""))\"")
        }
        guard !parts.isEmpty else { throw WriteError.verificationFailed("no table with an ID column") }
        let maximum = try int("SELECT MAX(m) FROM (\(parts.joined(separator: " UNION ALL ")))")
        return Int(maximum ?? 0)
    }

    func rollbackIfOpen() {
        if sqlite3_get_autocommit(handle) == 0 {
            try? exec("ROLLBACK")
        }
    }

    func serialize() throws -> Data {
        var size: sqlite3_int64 = 0
        guard let pointer = sqlite3_serialize(handle, "main", &size, 0) else {
            throw WriteError.invalid("sqlite3_serialize failed")
        }
        defer { sqlite3_free(pointer) }
        return Data(bytes: pointer, count: Int(size))
    }
}
