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

    /// Cho `addRelationship` biết các giá trị `INDEX` và số dòng bảng phía một (đọc từ dữ liệu cột trong ABF). Bắt buộc khi thêm
    /// quan hệ: Desktop không mở được file có quan hệ thiếu chỉ mục (VM-E3).
    public var relationshipIndexProvider: ((NewRelationship) throws -> (values: [Int], toRowCount: Int))?
    /// Tệp ABF mới do các thao tác đã áp (chỉ mục quan hệ): để `PBIXWriter` thêm vào ABF.
    public private(set) var addedFiles: [ABFPayload] = []
    /// Đường dẫn tệp ABF mà các thao tác đã áp muốn xoá (chỉ mục của quan hệ bị xoá).
    public private(set) var removedFiles: [String] = []

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
        guard let dataType = ModelMetadata.DataType(rawValue: measure.dataType ?? measureDataType),
              dataType != .automatic, dataType != .unknown else {
            throw WriteError.invalid("measure data type \(measure.dataType ?? measureDataType) is not a known DataType")
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
            // MAXID là bộ đếm: sau khi xoá đối tượng nó có thể lớn hơn ID lớn nhất còn lại (Desktop cũng vậy); nhỏ hơn thì sai.
            guard storedMaxID >= actualMaxID else {
                throw WriteError.verificationFailed("DBPROPERTIES.MAXID is \(storedMaxID) but the largest ID is \(actualMaxID)")
            }
            let newID = storedMaxID + 1
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

// MARK: - Phase E: áp `ModelEdit` (specs/009-e-mo-hinh-hoa-luu-t2, QUAN-SAT VM-E1)

extension MetadataWriter {
    /// Áp lần lượt từng thao tác; mỗi thao tác là một giao dịch (lỗi thì cơ sở dữ liệu giữ như trước thao tác đó).
    public mutating func apply(_ edits: ModelEdits) throws {
        for edit in edits.items { try apply(edit) }
    }

    public mutating func apply(_ edit: ModelEdit) throws {
        switch edit {
        case .addMeasure(let measure):
            try addMeasure(measure)
            try transaction { db, now in
                // Desktop cập nhật `Table.ModifiedTime` của bảng chứa khi thêm hoặc xoá measure (VM-E1, VM-E2).
                try db.run("UPDATE [Table] SET ModifiedTime = ? WHERE ID = ?", [.int(now), .int(Int64(try db.userTableID(named: measure.table)))])
                try Self.bumpProperties(db, now)
            }
        case .updateMeasure(let table, let name, let patch):
            try transaction { db, now in try Self.updateMeasure(db, table: table, name: name, patch: patch, now: now) }
        case .deleteMeasure(let table, let name):
            try transaction { db, now in try Self.deleteMeasure(db, table: table, name: name, now: now) }
        case .updateRelationship(let name, let patch):
            try transaction { db, now in try Self.updateRelationship(db, name: name, patch: patch, now: now) }
        case .updateColumn(let table, let name, let patch):
            try transaction { db, now in try Self.updateColumn(db, table: table, name: name, patch: patch, now: now) }
        case .updateTable(let name, let patch):
            try transaction { db, now in
                let id = try db.userTableID(named: name)
                guard let hidden = patch.isHidden else { return }
                try db.run("UPDATE [Table] SET IsHidden = ?, ModifiedTime = ? WHERE ID = ?", [.int(hidden ? 1 : 0), .int(now), .int(Int64(id))])
                try Self.bumpProperties(db, now)
            }
        case .addRelationship(let relationship):
            guard let provider = relationshipIndexProvider else { throw WriteError.invalid("thiếu nguồn chỉ mục cho quan hệ mới") }
            let index = try provider(relationship)
            let files = try RelationshipIndex.encode(values: index.values, toRowCount: index.toRowCount)
            var payloads: [ABFPayload] = []
            try transaction { db, now in
                payloads = try Self.addRelationship(db, relationship, records: index.values.count, files: files, now: now)
            }
            addedFiles += payloads
        case .deleteRelationship(let name):
            var removed: [String] = []
            try transaction { db, now in removed = try Self.deleteRelationship(db, name: name, now: now) }
            // Tệp vừa thêm trong cùng đợt thì bỏ khỏi danh sách thêm, không cần xoá khỏi ABF.
            let alreadyAdded = Set(addedFiles.map(\.path))
            addedFiles.removeAll { removed.contains($0.path) }
            removedFiles += removed.filter { !alreadyAdded.contains($0) }
        }
    }

    private func transaction(_ body: (MetadataDatabase, Int64) throws -> Void) throws {
        let db = database
        try db.exec("BEGIN IMMEDIATE")
        do {
            try body(db, Self.fileTimeNow())
            try db.exec("COMMIT")
        } catch {
            db.rollbackIfOpen()
            throw error
        }
    }

    /// Desktop cập nhật bốn thuộc tính này ở mọi lần lưu có đổi (QUAN-SAT mục 1 đến 3).
    private static func bumpProperties(_ db: MetadataDatabase, _ now: Int64) throws {
        for property in ["LASTCUBEDATACHANGE", "LASTCUBESCHEMACHANGE", "LASTCOMMITTED", "LASTMETADATACHANGEFORSYNCCOMMITTED"]
        where try db.int("SELECT COUNT(*) FROM DBPROPERTIES WHERE NAME = ?", [.text(property)]) == 1 {
            try db.run("UPDATE DBPROPERTIES SET VALUE = ? WHERE NAME = ?", [.int(now), .text(property)])
        }
    }

    private static func text(_ value: String?) -> MetadataDatabase.Value { optionalText(value) }

    private static func assignment(_ value: Assignment<String>?) -> (set: Bool, value: MetadataDatabase.Value) {
        switch value {
        case .none: (false, .null)
        case .some(.clear): (true, .null)
        case .some(.set(let text)): (true, optionalText(text))
        }
    }

    private static func measureID(_ db: MetadataDatabase, table: String, name: String) throws -> Int {
        let ids = try db.strings("""
            SELECT m.ID FROM Measure m JOIN [Table] t ON t.ID = m.TableID
            WHERE t.Name = ? COLLATE NOCASE AND t.SystemFlags = 0 AND m.Name = ?
            """, [.text(table), .text(name)])
        guard ids.count == 1, let id = Int(ids[0]) else { throw WriteError.invalid("không có measure \(table)[\(name)]") }
        return id
    }

    private static func updateMeasure(_ db: MetadataDatabase, table: String, name: String, patch: MeasurePatch, now: Int64) throws {
        let id = try measureID(db, table: table, name: name)
        let tableID = try db.userTableID(named: table)
        var sets: [String] = []
        var values: [MetadataDatabase.Value] = []
        if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != name {
            guard !renamed.isEmpty, !renamed.contains("\0") else { throw WriteError.invalid("tên measure không hợp lệ") }
            let clash = try db.int("SELECT COUNT(*) FROM Measure WHERE TableID = ? AND Name = ? COLLATE NOCASE AND ID <> ?",
                                   [.int(Int64(tableID)), .text(renamed), .int(Int64(id))]) ?? 0
            guard clash == 0, try !db.columnNameExists(renamed, tableID: tableID) else {
                throw WriteError.invalid("bảng '\(table)' đã có mục tên '\(renamed)'")
            }
            sets.append("Name = ?"); values.append(.text(renamed))
        }
        if let expression = patch.expression?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !expression.isEmpty, !expression.contains("\0") else { throw WriteError.invalid("biểu thức không hợp lệ") }
            sets.append("Expression = ?"); values.append(.text(expression))
        }
        for (column, value) in [("FormatString", assignment(patch.formatString)), ("DisplayFolder", assignment(patch.displayFolder)),
                                ("Description", assignment(patch.description))] where value.set {
            sets.append("\(column) = ?"); values.append(value.value)
        }
        if let hidden = patch.isHidden { sets.append("IsHidden = ?"); values.append(.int(hidden ? 1 : 0)) }
        if let type = patch.dataType {
            guard type != .automatic, type != .unknown else { throw WriteError.invalid("kiểu dữ liệu measure không hợp lệ") }
            sets.append("DataType = ?"); values.append(.int(Int64(type.rawValue)))
        }
        guard !sets.isEmpty else { return }
        sets.append("ModifiedTime = ?"); values.append(.int(now))
        values.append(.int(Int64(id)))
        try db.run("UPDATE Measure SET \(sets.joined(separator: ", ")) WHERE ID = ?", values)
        try bumpProperties(db, now)
    }

    /// Xoá measure cùng các dòng phụ thuộc (ID dùng chung toàn cơ sở dữ liệu nên `ObjectID` không nhầm loại).
    private static func deleteMeasure(_ db: MetadataDatabase, table: String, name: String, now: Int64) throws {
        let id = try measureID(db, table: table, name: name)
        if (try db.int("SELECT KPIID FROM Measure WHERE ID = ?", [.int(Int64(id))]) ?? 0) != 0 {
            throw WriteError.invalid("measure '\(name)' có KPI, chưa hỗ trợ xoá")
        }
        if db.tableExists("Model"), (try db.int("SELECT COUNT(*) FROM Model WHERE DefaultMeasureID = ?", [.int(Int64(id))]) ?? 0) > 0 {
            throw WriteError.invalid("measure '\(name)' là measure mặc định của mô hình")
        }
        for dependent in ["Annotation", "ExtendedProperty", "FormatStringDefinition", "DetailRowsDefinition", "ChangedProperty",
                          "ObjectTranslation", "PackageObjectReference", "ExcludedArtifact"] where db.tableExists(dependent) {
            try db.run("DELETE FROM [\(dependent)] WHERE ObjectID = ?", [.int(Int64(id))])
        }
        if db.tableExists("PerspectiveMeasure") { try db.run("DELETE FROM PerspectiveMeasure WHERE MeasureID = ?", [.int(Int64(id))]) }
        let tableID = try db.int("SELECT TableID FROM Measure WHERE ID = ?", [.int(Int64(id))]) ?? 0
        try db.run("DELETE FROM Measure WHERE ID = ?", [.int(Int64(id))])
        try db.run("UPDATE [Table] SET ModifiedTime = ? WHERE ID = ?", [.int(now), .int(tableID)])
        try bumpProperties(db, now)
    }

    private static func updateRelationship(_ db: MetadataDatabase, name: String, patch: RelationshipPatch, now: Int64) throws {
        guard (try db.int("SELECT COUNT(*) FROM Relationship WHERE Name = ?", [.text(name)]) ?? 0) == 1 else {
            throw WriteError.invalid("không có quan hệ \(name)")
        }
        var sets: [String] = []
        var values: [MetadataDatabase.Value] = []
        if let active = patch.isActive { sets.append("IsActive = ?"); values.append(.int(active ? 1 : 0)) }
        if let behavior = patch.crossFilteringBehavior {
            guard behavior == 1 || behavior == 2 else { throw WriteError.invalid("hướng lọc chéo phải là 1 hoặc 2") }
            sets.append("CrossFilteringBehavior = ?"); values.append(.int(Int64(behavior)))
        }
        guard !sets.isEmpty else { return }
        sets.append("ModifiedTime = ?"); values.append(.int(now))
        values.append(.text(name))
        try db.run("UPDATE Relationship SET \(sets.joined(separator: ", ")) WHERE Name = ?", values)
        try bumpProperties(db, now)
    }

    /// Thêm quan hệ nhiều-một đúng như Desktop ghi (QUAN-SAT VM-E3): dòng `Relationship`, `RelationshipStorage`,
    /// `RelationshipIndexStorage`, bảng hệ thống ẩn `R$…` cùng mọi dòng lưu trữ của nó, và hai tệp ABF `.idf`/`.idfmeta`.
    /// Trả hai tệp ABF mới. `records` là số mục của cột `INDEX` (ba mã dành riêng cộng số mục từ điển cột phía nhiều).
    private static func addRelationship(_ db: MetadataDatabase, _ new: NewRelationship, records: Int,
                                        files: (idf: Data, meta: Data), now: Int64) throws -> [ABFPayload] {
        guard new.fromMany, !new.toMany else { throw WriteError.invalid("chỉ ghi được quan hệ nhiều-một") }
        let fromTable = try db.userTableID(named: new.fromTable), toTable = try db.userTableID(named: new.toTable)
        let fromColumn = try columnID(db, table: new.fromTable, name: new.fromColumn)
        let toColumn = try columnID(db, table: new.toTable, name: new.toColumn)
        guard (try db.int("SELECT COUNT(*) FROM Relationship WHERE Name = ?", [.text(new.name)]) ?? 0) == 0 else {
            throw WriteError.invalid("đã có quan hệ \(new.name)")
        }
        let stored = try db.storedMaxID(), actual = try db.actualMaxID()
        guard stored >= actual else { throw WriteError.verificationFailed("DBPROPERTIES.MAXID là \(stored) nhưng ID lớn nhất là \(actual)") }
        guard let tableStorageName = try db.strings("SELECT Name FROM TableStorage WHERE TableID = ?", [.int(Int64(fromTable))]).first else {
            throw WriteError.invalid("bảng \(new.fromTable) không có TableStorage")
        }
        guard let modelID = try db.int("SELECT MIN(ID) FROM Model") else { throw WriteError.invalid("không có dòng Model") }

        // Thứ tự cấp ID: quan hệ, lưu trữ quan hệ, bảng R$ rồi các dòng lưu trữ của nó (mỗi ID một giá trị mới).
        var next = stored + 1
        func take() -> Int64 { defer { next += 1 }; return Int64(next) }
        let relID = take(), relStorageID = take(), indexStorageID = take()
        let tableID = take(), tableStorageID = take(), tableFolderID = take(), partitionID = take(), partitionStorageID = take()
        let partitionFolderID = take(), segmentMapID = take(), columnID = take(), columnStorageID = take(), dictionaryID = take()
        let columnPartitionID = take(), segmentID = take(), idfFileID = take(), metaFileID = take()

        let guidSpaces = new.name.replacingOccurrences(of: "-", with: " ")
        let tableName = "R$\(tableStorageName)$\(guidSpaces) (\(relID))"
        let tableFolder = "\(tableName)$(\(tableID)).tbl"
        let partitionFolder = "\(tableFolder)\\\(partitionID).prt"
        let fileBase = "0.\(tableName).INDEX.0"
        let refreshedNever: Int64 = 31_240_512_000_000_000

        try db.run("""
            INSERT INTO Relationship (ID, ModelID, Name, IsActive, Type, CrossFilteringBehavior, JoinOnDateBehavior,
                RelyOnReferentialIntegrity, FromTableID, FromColumnID, FromCardinality, ToTableID, ToColumnID, ToCardinality,
                State, RelationshipStorageID, RelationshipStorage2ID, ModifiedTime, RefreshedTime, SecurityFilteringBehavior)
            VALUES (?, ?, ?, ?, 1, ?, 1, 0, ?, ?, 2, ?, ?, 1, 1, ?, 0, ?, ?, 1)
            """, [.int(relID), .int(Int64(modelID)), .text(new.name), .int(new.isActive ? 1 : 0), .int(Int64(new.crossFilteringBehavior)),
                  .int(Int64(fromTable)), .int(Int64(fromColumn)), .int(Int64(toTable)), .int(Int64(toColumn)), .int(relStorageID),
                  .int(now), .int(now)])
        try db.run("INSERT INTO RelationshipStorage (ID, RelationshipID, Name, DefinitionType, Cardinality, Flags, RelationshipIndexStorageID) VALUES (?, ?, ?, 0, 0, 0, ?)",
                   [.int(relStorageID), .int(relID), .text("\(guidSpaces) (\(relID))"), .int(indexStorageID)])
        try db.run("INSERT INTO RelationshipIndexStorage (ID, RelationshipStorageID, IndexType, Flags, RecordCount, SecondaryRecordCount, StorageFolderID, StorageFileID, SystemTableID, SecondarySystemTableID) VALUES (?, ?, 1, 0, ?, 0, 0, 0, ?, 0)",
                   [.int(indexStorageID), .int(relStorageID), .int(Int64(records)), .int(tableID)])

        // Bảng hệ thống ẩn R$ (SystemFlags 1, IsHidden 1, ModelID 0) và cột INDEX.
        try db.run("""
            INSERT INTO StorageFolder (ID, OwnerID, OwnerType, Path) VALUES (?, ?, 18, ?)
            """, [.int(tableFolderID), .int(tableStorageID), .text(tableFolder)])
        try db.run("INSERT INTO TableStorage (ID, TableID, Name, Version, Settings, RIViolationCount, StorageFolderID) VALUES (?, ?, ?, 0, 2, 0, ?)",
                   [.int(tableStorageID), .int(tableID), .text(tableName), .int(tableFolderID)])
        try db.run("""
            INSERT INTO [Table] (ID, ModelID, Name, DataCategory, Description, IsHidden, TableStorageID, ModifiedTime,
                StructureModifiedTime, SystemFlags, ShowAsVariationsOnly, IsPrivate, DefaultDetailRowsDefinitionID,
                AlternateSourcePrecedence, RefreshPolicyID, CalculationGroupID, ExcludeFromModelRefresh, LineageTag,
                SourceLineageTag, SystemManaged, ExcludeFromAutomaticAggregations, DirectLakeIndexingBehavior)
            VALUES (?, 0, ?, NULL, NULL, 1, ?, ?, ?, 1, 0, 0, 0, 0, 0, 0, 0, NULL, NULL, 0, 0, 3)
            """, [.int(tableID), .text(tableName), .int(tableStorageID), .int(now), .int(now)])
        try db.run("""
            INSERT INTO StorageFolder (ID, OwnerID, OwnerType, Path) VALUES (?, ?, 20, ?)
            """, [.int(partitionFolderID), .int(partitionStorageID), .text(partitionFolder)])
        try db.run("INSERT INTO PartitionStorage (ID, PartitionID, Name, StoragePosition, SegmentMapStorageID, DataObjectId, StorageFolderID, DeltaTableMetadataStorageID) VALUES (?, ?, ?, 0, ?, 0, ?, 0)",
                   [.int(partitionStorageID), .int(partitionID), .text(tableName), .int(segmentMapID), .int(partitionFolderID)])
        try db.run("INSERT INTO SegmentMapStorage (ID, PartitionStorageID, Type, RecordCount, SegmentCount, RecordsPerSegment) VALUES (?, ?, 3, ?, 1, ?)",
                   [.int(segmentMapID), .int(partitionStorageID), .int(Int64(records)), .int(Int64(records))])
        try db.run("""
            INSERT INTO Partition (ID, TableID, Name, Description, DataSourceID, QueryDefinition, State, Type, PartitionStorageID,
                Mode, DataView, ModifiedTime, RefreshedTime, SystemFlags, ErrorMessage, RetainDataTillForceCalculate, RangeStart,
                RangeEnd, RangeGranularity, RefreshBookmark, QueryGroupID, ExpressionSourceID, MAttributes,
                DataCoverageDefinitionID, SchemaName)
            VALUES (?, ?, ?, NULL, 0, NULL, 1, 3, ?, 2, 3, ?, ?, 1, NULL, 0, 0.0, 0.0, -1, NULL, 0, 0, NULL, 0, NULL)
            """, [.int(partitionID), .int(tableID), .text(tableName), .int(partitionStorageID), .int(now), .int(refreshedNever)])
        try db.run("""
            INSERT INTO [Column] (ID, TableID, ExplicitName, InferredName, ExplicitDataType, InferredDataType, DataCategory, Description,
                IsHidden, State, IsUnique, IsKey, IsNullable, Alignment, TableDetailPosition, IsDefaultLabel, IsDefaultImage, SummarizeBy,
                ColumnStorageID, Type, SourceColumn, ColumnOriginID, Expression, FormatString, IsAvailableInMDX, SortByColumnID,
                AttributeHierarchyID, ModifiedTime, StructureModifiedTime, RefreshedTime, SystemFlags, KeepUniqueRows, DisplayOrdinal,
                ErrorMessage, SourceProviderType, DisplayFolder, EncodingHint, RelatedColumnDetailsID, AlternateOfID, LineageTag,
                SourceLineageTag, ExpressionContext, StringIndexingBehavior, FullTextIndexingBehavior, StringIndexID, FullTextIndexID)
            VALUES (?, ?, 'INDEX', NULL, 6, 19, NULL, NULL, 0, 1, 0, 0, 1, 1, -1, 0, 0, 1, ?, 1, NULL, 0, NULL, NULL, 1, 0, 0, ?, ?, ?,
                    1, 0, 0, NULL, NULL, NULL, 0, 0, 0, NULL, NULL, 1, 1, 0, 0, 0)
            """, [.int(columnID), .int(tableID), .int(columnStorageID), .int(now), .int(now), .int(refreshedNever)])
        try db.run("""
            INSERT INTO ColumnStorage (ID, ColumnID, Name, StoragePosition, DictionaryStorageID, Settings, ColumnFlags, Collation, OrderByColumn,
                Locale, BinaryCharacters, Statistics_DistinctStates, Statistics_MinDataID, Statistics_MaxDataID,
                Statistics_OriginalMinSegmentDataID, Statistics_RLESortOrder, Statistics_RowCount, Statistics_HasNulls, Statistics_RLERuns,
                Statistics_OthersRLERuns, Statistics_Usage, Statistics_DBType, Statistics_XMType, Statistics_CompressionType,
                Statistics_CompressionParam, Statistics_EncodingHint, IsDeltaPartitionColumn, DeltaColumnMappingPhysicalName,
                DeltaColumnMappingId, FramedSourceColumn, DeltaColumnPrimitiveType, DeltaTableColumnStorageID, StringIndexStorageID,
                ColumnIndexStorageID, FullTextIndexStorageID)
            VALUES (?, ?, 'INDEX', 0, ?, 3, 0, NULL, NULL, 0, 0, 1, 2, 2, 2, -1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, NULL, -1, NULL, 0, 0, 0, 0, NULL)
            """, [.int(columnStorageID), .int(columnID), .int(dictionaryID)])
        try db.run("INSERT INTO DictionaryStorage (ID, ColumnStorageID, Type, DataType, DataVersion, BaseId, Magnitude, LastId, IsNullable, IsUnique, IsOperatingOn32, DictionaryFlags, StorageFileID, Size) VALUES (?, ?, 0, 19, 0, 0, 0.0, 0, 0, 0, 0, 0, 0, 0)",
                   [.int(dictionaryID), .int(columnStorageID)])
        try db.run("INSERT INTO ColumnPartitionStorage (ID, ColumnStorageID, PartitionStorageID, DataVersion, State, SegmentStorageID, StorageFileID) VALUES (?, ?, ?, 0, 3, ?, ?)",
                   [.int(columnPartitionID), .int(columnStorageID), .int(partitionStorageID), .int(segmentID), .int(idfFileID)])
        try db.run("INSERT INTO SegmentStorage (ID, ColumnPartitionStorageID, SegmentCount, StorageFileID) VALUES (?, ?, 1, ?)",
                   [.int(segmentID), .int(columnPartitionID), .int(metaFileID)])
        try db.run("INSERT INTO StorageFile (ID, OwnerID, OwnerType, StorageFolderID, FileName) VALUES (?, ?, 23, ?, ?)",
                   [.int(idfFileID), .int(columnPartitionID), .int(partitionFolderID), .text("\(fileBase).idf")])
        try db.run("INSERT INTO StorageFile (ID, OwnerID, OwnerType, StorageFolderID, FileName) VALUES (?, ?, 24, ?, ?)",
                   [.int(metaFileID), .int(segmentID), .int(partitionFolderID), .text("\(fileBase).idfmeta")])

        // Bảng nguồn tăng phiên bản lưu trữ (Desktop: Version 9 → 10), mô hình và bốn DBPROPERTIES đổi thời gian.
        try db.run("UPDATE TableStorage SET Version = Version + 1 WHERE TableID = ?", [.int(Int64(fromTable))])
        try db.run("UPDATE Model SET ModifiedTime = ?", [.int(now)])
        try db.run("UPDATE DBPROPERTIES SET VALUE = ? WHERE NAME = 'MAXID'", [.int(Int64(next - 1))])
        try bumpProperties(db, now)
        return [ABFPayload(path: "\(partitionFolder)\\\(fileBase).idf", data: files.idf),
                ABFPayload(path: "\(partitionFolder)\\\(fileBase).idfmeta", data: files.meta)]
    }

    /// Xoá quan hệ cùng bảng `R$` của nó (mọi dòng lưu trữ). Trả đường dẫn các tệp ABF cần xoá.
    private static func deleteRelationship(_ db: MetadataDatabase, name: String, now: Int64) throws -> [String] {
        let ids = try db.strings("SELECT ID FROM Relationship WHERE Name = ?", [.text(name)])
        guard ids.count == 1, let id = Int64(ids[0]) else { throw WriteError.invalid("không có quan hệ \(name)") }
        var files: [String] = []
        for storage in try db.strings("SELECT ID FROM RelationshipStorage WHERE RelationshipID = ?", [.int(id)]) {
            guard let storageID = Int64(storage) else { continue }
            for index in try db.strings("SELECT SystemTableID FROM RelationshipIndexStorage WHERE RelationshipStorageID = ?", [.int(storageID)]) {
                if let tableID = Int64(index), tableID != 0 { files += try removeSystemTable(db, tableID: tableID) }
            }
            try db.run("DELETE FROM RelationshipIndexStorage WHERE RelationshipStorageID = ?", [.int(storageID)])
            try db.run("DELETE FROM RelationshipStorage WHERE ID = ?", [.int(storageID)])
        }
        for dependent in ["Annotation", "ExtendedProperty"] where db.tableExists(dependent) {
            try db.run("DELETE FROM [\(dependent)] WHERE ObjectID = ?", [.int(id)])
        }
        try db.run("DELETE FROM Relationship WHERE ID = ?", [.int(id)])
        try bumpProperties(db, now)
        return files
    }

    /// Xoá bảng hệ thống `R$` cùng mọi dòng lưu trữ; trả đường dẫn ABF các tệp dữ liệu của nó.
    private static func removeSystemTable(_ db: MetadataDatabase, tableID: Int64) throws -> [String] {
        var files: [String] = []
        let partitionIDs = try db.strings("SELECT ID FROM Partition WHERE TableID = ?", [.int(tableID)]).compactMap(Int64.init)
        let columnIDs = try db.strings("SELECT ID FROM [Column] WHERE TableID = ?", [.int(tableID)]).compactMap(Int64.init)
        for columnID in columnIDs {
            for cs in try db.strings("SELECT ID FROM ColumnStorage WHERE ColumnID = ?", [.int(columnID)]).compactMap(Int64.init) {
                for cp in try db.strings("SELECT ID FROM ColumnPartitionStorage WHERE ColumnStorageID = ?", [.int(cs)]).compactMap(Int64.init) {
                    for segment in try db.strings("SELECT ID FROM SegmentStorage WHERE ColumnPartitionStorageID = ?", [.int(cp)]).compactMap(Int64.init) {
                        files += try storageFilePaths(db, owner: segment, type: 24)
                        try db.run("DELETE FROM StorageFile WHERE OwnerID = ? AND OwnerType = 24", [.int(segment)])
                        try db.run("DELETE FROM SegmentStorage WHERE ID = ?", [.int(segment)])
                    }
                    files += try storageFilePaths(db, owner: cp, type: 23)
                    try db.run("DELETE FROM StorageFile WHERE OwnerID = ? AND OwnerType = 23", [.int(cp)])
                    try db.run("DELETE FROM ColumnPartitionStorage WHERE ID = ?", [.int(cp)])
                }
                try db.run("DELETE FROM DictionaryStorage WHERE ColumnStorageID = ?", [.int(cs)])
                try db.run("DELETE FROM ColumnStorage WHERE ID = ?", [.int(cs)])
            }
            try db.run("DELETE FROM [Column] WHERE ID = ?", [.int(columnID)])
        }
        for partition in partitionIDs {
            for ps in try db.strings("SELECT ID FROM PartitionStorage WHERE PartitionID = ?", [.int(partition)]).compactMap(Int64.init) {
                try db.run("DELETE FROM SegmentMapStorage WHERE PartitionStorageID = ?", [.int(ps)])
                try db.run("DELETE FROM StorageFolder WHERE OwnerID = ? AND OwnerType = 20", [.int(ps)])
                try db.run("DELETE FROM PartitionStorage WHERE ID = ?", [.int(ps)])
            }
            try db.run("DELETE FROM Partition WHERE ID = ?", [.int(partition)])
        }
        for ts in try db.strings("SELECT TableStorageID FROM [Table] WHERE ID = ?", [.int(tableID)]).compactMap(Int64.init) {
            try db.run("DELETE FROM StorageFolder WHERE OwnerID = ? AND OwnerType = 18", [.int(ts)])
            try db.run("DELETE FROM TableStorage WHERE ID = ?", [.int(ts)])
        }
        try db.run("DELETE FROM [Table] WHERE ID = ?", [.int(tableID)])
        return files
    }

    /// Đường dẫn ABF (`thư mục\\tên`) của các `StorageFile` thuộc `owner` loại `type`.
    private static func storageFilePaths(_ db: MetadataDatabase, owner: Int64, type: Int64) throws -> [String] {
        try db.strings("""
            SELECT f.Path || '\\' || s.FileName FROM StorageFile s JOIN StorageFolder f ON f.ID = s.StorageFolderID
            WHERE s.OwnerID = ? AND s.OwnerType = ?
            """, [.int(owner), .int(type)])
    }

    private static func columnID(_ db: MetadataDatabase, table: String, name: String) throws -> Int {
        let ids = try db.strings("""
            SELECT c.ID FROM [Column] c JOIN [Table] t ON t.ID = c.TableID
            WHERE t.Name = ? COLLATE NOCASE AND t.SystemFlags = 0 AND COALESCE(c.ExplicitName, c.InferredName) = ?
            """, [.text(table), .text(name)])
        guard ids.count == 1, let id = Int(ids[0]) else { throw WriteError.invalid("không có cột \(table)[\(name)]") }
        return id
    }

    /// [SUY ĐOÁN] Desktop còn ghi `Annotation` (ví dụ `SummarizationSetBy`) khi đổi tổng hợp mặc định; chưa quan sát nên
    /// không ghi (VM-E4a).
    private static func updateColumn(_ db: MetadataDatabase, table: String, name: String, patch: ColumnPatch, now: Int64) throws {
        let id = try columnID(db, table: table, name: name)
        let tableID = try db.userTableID(named: table)
        var sets: [String] = []
        var values: [MetadataDatabase.Value] = []
        if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != name {
            guard !renamed.isEmpty, !renamed.contains("\0") else { throw WriteError.invalid("tên cột không hợp lệ") }
            let clash = try db.int("""
                SELECT COUNT(*) FROM [Column] WHERE TableID = ? AND COALESCE(ExplicitName, InferredName) = ? COLLATE NOCASE AND ID <> ?
                """, [.int(Int64(tableID)), .text(renamed), .int(Int64(id))]) ?? 0
            guard clash == 0, try !db.measureNameExists(renamed, tableID: tableID) else {
                throw WriteError.invalid("bảng '\(table)' đã có mục tên '\(renamed)'")
            }
            sets.append("ExplicitName = ?"); values.append(.text(renamed))
        }
        if let hidden = patch.isHidden { sets.append("IsHidden = ?"); values.append(.int(hidden ? 1 : 0)) }
        if let summarize = patch.summarizeBy {
            guard (1...8).contains(summarize) else { throw WriteError.invalid("kiểu tổng hợp không hợp lệ") }
            sets.append("SummarizeBy = ?"); values.append(.int(Int64(summarize)))
        }
        for (column, value) in [("FormatString", assignment(patch.formatString)), ("DataCategory", assignment(patch.dataCategory)),
                                ("DisplayFolder", assignment(patch.displayFolder)), ("Description", assignment(patch.description))]
        where value.set {
            sets.append("\(column) = ?"); values.append(value.value)
        }
        switch patch.sortBy {
        case .none: break
        case .some(.clear): sets.append("SortByColumnID = 0")
        case .some(.set(let target)):
            let sortID = try columnID(db, table: table, name: target)
            guard sortID != id else { throw WriteError.invalid("cột không thể sắp xếp theo chính nó") }
            sets.append("SortByColumnID = ?"); values.append(.int(Int64(sortID)))
        }
        guard !sets.isEmpty else { return }
        sets.append("ModifiedTime = ?"); values.append(.int(now))
        values.append(.int(Int64(id)))
        try db.run("UPDATE [Column] SET \(sets.joined(separator: ", ")) WHERE ID = ?", values)
        try bumpProperties(db, now)
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
