import Foundation
import SQLite3

/// Adds measures to a model's `metadata.sqlitedb` (T2).
///
/// Works on an in-memory copy of the database. The bytes passed to `init` are never changed;
/// `serialize()` returns the edited database. Every `addMeasure` call is one transaction: it either
/// commits completely or leaves the in-memory copy as it was.
public struct MetadataWriter {
    /// `Measure.DataType` for new measures. Nhom6 samples: 2 = string (labels, colors), 6 = int64
    /// (counts with `#,0`), 8 = double (ratios, amounts). The default 8 is a guess for measures whose
    /// result type is not known; it is not verified in Power BI Desktop.
    public var measureDataType: Int = 8

    /// When true, `addMeasure` also sets the timestamps that Power BI is suspected to bump on save:
    /// `Table.ModifiedTime` / `StructureModifiedTime` of the target table, `Model.ModifiedTime` /
    /// `StructureModifiedTime`, and `DBPROPERTIES` LASTCOMMITTED, LASTCUBESCHEMACHANGE and
    /// LASTMETADATACHANGEFORSYNCCOMMITTED. Off by default until a reference file made in Power BI
    /// Desktop confirms the behaviour. `LASTCUBEDATACHANGE` is never changed by a measure.
    public var updateTimestamps: Bool = false

    private let database: MetadataDatabase

    /// Opens the database and checks that it is readable and has the tables this writer needs.
    /// Throws `WriteError.invalid` for empty, non-SQLite or incomplete input.
    public init(sqlite: Data) throws {
        database = try MetadataDatabase(bytes: sqlite)
        try database.requireIntegrity()
        for table in ["DBPROPERTIES", "Model", "Table", "Column", "Measure"] where !database.tableExists(table) {
            throw WriteError.invalid("metadata.sqlitedb has no \(table) table")
        }
    }

    /// Adds a measure and returns its new object ID (`MAXID + 1`, which also becomes the new `MAXID`).
    ///
    /// Throws `WriteError.invalid` for an unknown table, a duplicate name in the table, or empty
    /// required fields. Throws `WriteError.verificationFailed` when `DBPROPERTIES.MAXID` does not match
    /// the largest ID in the database. A failed call leaves the database unchanged.
    @discardableResult
    public mutating func addMeasure(_ measure: NewMeasure) throws -> Int {
        let name = measure.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let expression = measure.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let tableName = measure.table.trimmingCharacters(in: .whitespacesAndNewlines)
        for (label, value) in [("table", tableName), ("name", name), ("expression", expression)] {
            guard !value.isEmpty else { throw WriteError.invalid("measure \(label) is empty") }
            guard !value.contains("\0") else { throw WriteError.invalid("measure \(label) contains a NUL character") }
        }
        guard let dataType = ModelMetadata.DataType(rawValue: measureDataType),
              dataType != .automatic, dataType != .unknown else {
            throw WriteError.invalid("measure data type \(measureDataType) is not a known DataType")
        }

        let db = database
        let timestamps = updateTimestamps
        let now = Self.fileTimeNow()

        try db.exec("BEGIN IMMEDIATE")
        do {
            let tableID = try db.userTableID(named: tableName)
            if try db.measureNameExists(name, tableID: tableID) {
                throw WriteError.invalid("table '\(tableName)' already has a measure named '\(name)'")
            }
            if try db.columnNameExists(name, tableID: tableID) {
                throw WriteError.invalid("table '\(tableName)' already has a column named '\(name)'")
            }

            // Shared counter: MAXID must equal the largest ID in any table that has an ID column.
            let storedMaxID = try db.storedMaxID()
            let actualMaxID = try db.actualMaxID()
            guard storedMaxID == actualMaxID else {
                throw WriteError.verificationFailed("DBPROPERTIES.MAXID is \(storedMaxID) but the largest ID is \(actualMaxID)")
            }
            let newID = actualMaxID + 1
            // newID is above every existing ID, so this cannot collide; checked anyway.
            guard try !db.objectIDExists(newID, inTable: "Measure") else {
                throw WriteError.verificationFailed("measure ID \(newID) already exists")
            }

            try db.run("""
                INSERT INTO [Measure] (ID, TableID, Name, Description, DataType, Expression, FormatString, IsHidden,
                    State, ModifiedTime, StructureModifiedTime, KPIID, IsSimpleMeasure, ErrorMessage, DisplayFolder,
                    DetailRowsDefinitionID, DataCategory, FormatStringDefinitionID, LineageTag, SourceLineageTag)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 0, 0, NULL, ?, 0, NULL, 0, ?, NULL)
                """, [
                    .int(Int64(newID)),
                    .int(Int64(tableID)),
                    .text(name),
                    Self.optionalText(measure.description),
                    .int(Int64(dataType.rawValue)),
                    .text(expression),
                    Self.optionalText(measure.formatString),
                    .int(measure.isHidden ? 1 : 0),
                    .int(now),
                    .int(now),
                    Self.optionalText(measure.displayFolder),
                    .text(UUID().uuidString.lowercased()),
                ])

            if timestamps {
                try db.run("UPDATE [Table] SET ModifiedTime = ?, StructureModifiedTime = ? WHERE ID = ?",
                           [.int(now), .int(now), .int(Int64(tableID))])
                try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
                for property in ["LASTCOMMITTED", "LASTCUBESCHEMACHANGE", "LASTMETADATACHANGEFORSYNCCOMMITTED"] {
                    try db.run("UPDATE DBPROPERTIES SET VALUE = ? WHERE NAME = ?", [.int(now), .text(property)])
                }
            }

            try db.run("UPDATE DBPROPERTIES SET VALUE = ? WHERE NAME = 'MAXID'", [.int(Int64(newID))])
            try db.exec("COMMIT")
            return newID
        } catch {
            db.rollbackIfOpen()
            throw error
        }
    }

    /// The edited database as a `metadata.sqlitedb` file.
    public func serialize() throws -> Data {
        try database.serialize()
    }

    /// Windows FILETIME: 100 ns ticks since 1601-01-01 UTC.
    static func fileTimeNow() -> Int64 {
        Int64((Date().timeIntervalSince1970 + 11_644_473_600) * 10_000_000)
    }

    private static func optionalText(_ value: String?) -> MetadataDatabase.Value {
        guard let value, !value.isEmpty else { return .null }
        return .text(value)
    }
}

// MARK: - SQLite access

/// One in-memory SQLite connection holding a serialized `metadata.sqlitedb`.
private final class MetadataDatabase {
    enum Value {
        case int(Int64)
        case text(String)
        case null
    }

    private var handle: OpaquePointer?

    /// `sqlite3_deserialize` takes ownership of the buffer (FREEONCLOSE) and allows growth (RESIZEABLE),
    /// so the database can be written in memory.
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

    /// Runs a statement that returns no rows.
    func run(_ sql: String, _ values: [Value] = []) throws {
        try query(sql, values) { _ in }
    }

    func exec(_ sql: String) throws {
        try run(sql)
    }

    /// Returns the first column of every row, as text.
    func strings(_ sql: String, _ values: [Value] = []) throws -> [String] {
        var result: [String] = []
        try query(sql, values) { statement in
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
        }
        return result
    }

    /// Returns the first column of the first row as an integer, or nil when there is no row or the value is NULL.
    func int(_ sql: String, _ values: [Value] = []) throws -> Int64? {
        var result: Int64?
        try query(sql, values) { statement in
            if result == nil, sqlite3_column_type(statement, 0) != SQLITE_NULL {
                result = sqlite3_column_int64(statement, 0)
            }
        }
        return result
    }

    /// Prepares, binds and steps one statement, calling `row` for each result row.
    private func query(_ sql: String, _ values: [Value], _ row: (OpaquePointer?) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let rc: Int32
            switch value {
            case .int(let number): rc = sqlite3_bind_int64(statement, position, number)
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

    /// The user table (SystemFlags = 0) with this name. Table names are matched case-insensitively, as in DAX.
    func userTableID(named name: String) throws -> Int {
        let ids = try strings("SELECT ID FROM [Table] WHERE Name = ? COLLATE NOCASE AND SystemFlags = 0", [.text(name)])
        guard ids.count == 1, let id = Int(ids[0]) else {
            throw WriteError.invalid("no user table named '\(name)' (found \(ids.count))")
        }
        return id
    }

    func measureNameExists(_ name: String, tableID: Int) throws -> Bool {
        try (int("SELECT COUNT(*) FROM Measure WHERE TableID = ? AND Name = ? COLLATE NOCASE",
                 [.int(Int64(tableID)), .text(name)]) ?? 0) > 0
    }

    func columnNameExists(_ name: String, tableID: Int) throws -> Bool {
        try (int("SELECT COUNT(*) FROM [Column] WHERE TableID = ? AND COALESCE(ExplicitName, InferredName) = ? COLLATE NOCASE",
                 [.int(Int64(tableID)), .text(name)]) ?? 0) > 0
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

    /// The largest ID in every table that has an `ID` column (the shared counter's ground truth).
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
