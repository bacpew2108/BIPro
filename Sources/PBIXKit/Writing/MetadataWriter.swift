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
    /// Tệp ABF đã có mà thao tác thay bảng ghi lại cùng đường dẫn (nội dung mới): `PBIXWriter` đưa vào `replacing`.
    public private(set) var replacedFiles: [ABFPayload] = []

    private var database: MetadataDatabase

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

    /// Adds a loaded table (T3): VertiPaq files for every column, `H$` system tables and the metadata rows. Every column needs
    /// `values`. A table with "Enable load" off adds nothing. Files go to `addedFiles`.
    /// Tên bảng nối vào cuối `PBI_QueryOrder` như Desktop (VM-F8 mục 3), khi file có chú thích này.
    public mutating func addTable(_ table: NewTable) throws {
        try addTable(table, reusing: nil)
        guard table.enableLoad else { return }
        try transaction { db, now in
            try Self.editQueryOrder(db, now: now) { order in if !order.contains(table.name) { order.append(table.name) } }
        }
    }

    /// ID của bảng cũ dùng lại khi thay bảng: giữ ID bảng, phân vùng, cột RowNumber và cột cùng tên (quan hệ, measure, annotation
    /// trỏ vào ID nên không đứt).
    struct ReusedIDs {
        var tableID: Int
        var partitionID: Int
        var rowNumberID: Int?
        var columnIDs: [String: Int]
    }

    private mutating func addTable(_ table: NewTable, reusing old: ReusedIDs?) throws {
        guard table.enableLoad else { return }
        var columns: [(name: String, values: VertiPaqWriter.Values)] = []
        for column in table.columns {
            guard let values = column.values else {
                throw WriteError.invalid("cột «\(column.name)» của bảng «\(table.name)» chưa có dữ liệu mã hoá để ghi")
            }
            columns.append((column.name, values))
        }
        var writer = try TableMetadataWriter(sqlite: try database.serialize())
        let base = writer.maxID
        var fresh = base + 4
        let ids = columns.map { column -> Int in
            if let id = old?.columnIDs[column.name] { return id }
            defer { fresh += 1 }
            return fresh
        }
        let encoded = try VertiPaqWriter.encodeTable(name: table.name, tableID: old?.tableID ?? base + 1, partitionID: old?.partitionID ?? base + 2,
                                                     rowNumberID: old?.rowNumberID ?? base + 3,
                                                     columns: columns.enumerated().map { .init(id: ids[$0.offset], name: $0.element.name, values: $0.element.values) })
        try writer.addTable(encoded, queryExpression: table.queryExpression, lineageTag: table.lineageTag, reusingIDs: old != nil)
        database = try MetadataDatabase(bytes: try writer.serialize())
        addedFiles += (encoded.files + writer.systemFiles).map { ABFPayload(path: $0.path, data: $0.data) }
        try transaction { db, now in
            try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
            try Self.bumpProperties(db, now)
        }
    }

    // MARK: Cột và bảng tính toán (Phase F, T084)

    /// Giá trị đã tính của cột tính toán và cột của bảng tính toán, khoá `Bảng[Cột]` (ứng dụng tính bằng engine rồi đưa qua
    /// `PBIXChanges.calculatedData`). Desktop lưu sẵn dữ liệu VertiPaq của chúng nên file mở không cần làm mới (VM-F6).
    public var calculatedValues: [String: VertiPaqWriter.Values] = [:]

    private func calculated(_ table: String, _ column: String) throws -> VertiPaqWriter.Values {
        guard let values = calculatedValues["\(table)[\(column)]"] else {
            throw WriteError.invalid("chưa có giá trị đã tính của cột «\(table)[\(column)]» để ghi")
        }
        return values
    }

    mutating func addCalculatedColumn(table: String, name: String, expression: String) throws {
        let values = try calculated(table, name)
        var writer = try TableMetadataWriter(sqlite: try database.serialize())
        let files = try writer.addCalculatedColumn(table: table, columnID: writer.maxID + 1, columnName: name, expression: expression, values: values)
        database = try MetadataDatabase(bytes: try writer.serialize())
        addedFiles += files.map { ABFPayload(path: $0.path, data: $0.data) }
        try transaction { db, now in
            try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
            try Self.bumpProperties(db, now)
        }
    }

    mutating func addCalculatedTable(name: String, expression: String, columns: [ColumnSignature]) throws {
        var data: [NewTableColumn] = []
        for column in columns { data.append(NewTableColumn(name: column.name, values: try calculated(name, column.name))) }
        // Như bảng nạp (không vào `PBI_QueryOrder`: bảng tính toán không phải truy vấn), rồi đổi các dòng thành dạng bảng tính toán.
        try addTable(NewTable(name: name, columns: data, queryExpression: expression), reusing: nil)
        var writer = try TableMetadataWriter(sqlite: try database.serialize())
        try writer.markCalculatedTable(name, expression: expression, sources: Self.sources(columns))
        database = try MetadataDatabase(bytes: try writer.serialize())
    }

    // MARK: Sửa và xoá cột, bảng tính toán có trong file (Phase F, T116, VM-F9)

    /// Sửa công thức cột tính toán như Desktop: giữ dòng `Column` (ID, thuộc tính, `LineageTag`), bỏ dữ liệu lưu trữ cũ cùng bảng `H$`,
    /// ghi dữ liệu mới (giá trị đã tính trong `calculatedValues`) ở cùng vị trí lưu. Cột nằm trong quan hệ, là cấp của phân cấp hay là
    /// cột sắp xếp của cột khác thì từ chối (chỉ mục `R$`/`U$` chưa dựng lại được). Lỗi thì cơ sở dữ liệu và danh sách tệp như trước.
    mutating func updateCalculatedColumn(table: String, name: String, expression: String) throws {
        let values = try calculated(table, name)
        let snapshot = try database.serialize()
        let before = (addedFiles, removedFiles, replacedFiles)
        do {
            var removed: [String] = [], columnID = 0, position = 0
            try transaction { db, _ in
                columnID = try Self.calculatedColumnID(db, table: table, name: name)
                try Self.requireNoIndexes(db, columnID: columnID, table: table, name: name, action: "sửa công thức")
                guard let stored = try db.int("""
                    SELECT cs.StoragePosition FROM ColumnStorage cs JOIN [Column] c ON c.ColumnStorageID = cs.ID WHERE c.ID = ?
                    """, [.int(Int64(columnID))]) else {
                    throw WriteError.invalid("cột tính toán «\(table)[\(name)]» không có dữ liệu lưu trữ")
                }
                position = Int(stored)
                removed = try Self.removeColumnStorage(db, columnID: Int64(columnID))
            }
            var writer = try TableMetadataWriter(sqlite: try database.serialize())
            let files = try writer.rewriteCalculatedColumn(table: table, columnID: columnID, storagePosition: position,
                                                           expression: expression, values: values)
            database = try MetadataDatabase(bytes: try writer.serialize())
            try transaction { db, now in
                try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
                try Self.bumpProperties(db, now)
            }
            record(removed: removed, added: files.map { ABFPayload(path: $0.path, data: $0.data) })
        } catch {
            database = try MetadataDatabase(bytes: snapshot)
            (addedFiles, removedFiles, replacedFiles) = before
            throw error
        }
    }

    /// Xoá cột tính toán như Desktop: dòng `Column`, dữ liệu lưu trữ, bảng `H$`, chú thích và tệp ABF của cột.
    mutating func deleteCalculatedColumn(table: String, name: String) throws {
        var removed: [String] = []
        try transaction { db, now in
            let columnID = try Self.calculatedColumnID(db, table: table, name: name)
            try Self.requireNoIndexes(db, columnID: columnID, table: table, name: name, action: "xoá")
            removed = try Self.removeColumnStorage(db, columnID: Int64(columnID))
            try Self.deleteDependents(db, objectID: columnID)
            try db.run("DELETE FROM [Column] WHERE ID = ?", [.int(Int64(columnID))])
            try db.run("UPDATE [Table] SET ModifiedTime = ?, StructureModifiedTime = ? WHERE ID = ?",
                       [.int(now), .int(now), .int(Int64(try db.userTableID(named: table)))])
            try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
            try Self.bumpProperties(db, now)
        }
        record(removed: removed, added: [])
    }

    /// Sửa công thức bảng tính toán: thay dữ liệu như `replaceTable` (giữ ID bảng, phân vùng, cột cùng tên và thuộc tính của chúng,
    /// measure của bảng), rồi đưa các dòng về dạng bảng tính toán. [SUY ĐOÁN] chưa quan sát Desktop (VM-F9 mục 5).
    mutating func updateCalculatedTable(name: String, expression: String, columns: [ColumnSignature]) throws {
        var data: [NewTableColumn] = []
        for column in columns { data.append(NewTableColumn(name: column.name, values: try calculated(name, column.name))) }
        let snapshot = try database.serialize()
        let before = (addedFiles, removedFiles, replacedFiles)
        do {
            try replaceTable(name, with: NewTable(name: name, columns: data, queryExpression: expression), calculated: true)
            var writer = try TableMetadataWriter(sqlite: try database.serialize())
            try writer.markCalculatedTable(name, expression: expression, sources: Self.sources(columns))
            database = try MetadataDatabase(bytes: try writer.serialize())
        } catch {
            database = try MetadataDatabase(bytes: snapshot)
            (addedFiles, removedFiles, replacedFiles) = before
            throw error
        }
    }

    /// Ghi nhận tệp bỏ và tệp mới của một thao tác: tệp vừa thêm trong cùng đợt thì chỉ bỏ khỏi danh sách thêm; đường dẫn cũ trùng đường
    /// dẫn mới thì ghi đè (`replacedFiles`).
    private mutating func record(removed: [String], added files: [ABFPayload]) {
        let newByPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var fresh = Set(newByPath.keys)
        for path in removed {
            if let index = addedFiles.firstIndex(where: { $0.path == path }) { addedFiles.remove(at: index); continue }
            replacedFiles.removeAll { $0.path == path }
            if let file = newByPath[path] {
                replacedFiles.append(file)
                fresh.remove(path)
            } else {
                removedFiles.append(path)
            }
        }
        addedFiles += files.filter { fresh.contains($0.path) }
    }

    /// `SourceColumn` của từng cột kết quả bảng tính toán (VM-F9b).
    private static func sources(_ columns: [ColumnSignature]) -> [String: String] {
        Dictionary(columns.compactMap { c in c.sourceColumn.map { (c.name, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    private static func calculatedColumnID(_ db: MetadataDatabase, table: String, name: String) throws -> Int {
        let id = try columnID(db, table: table, name: name)
        guard try db.int("SELECT Type FROM [Column] WHERE ID = ?", [.int(Int64(id))]) == 2 else {
            throw WriteError.invalid("cột «\(table)[\(name)]» không phải cột tính toán")
        }
        return id
    }

    /// Chỉ mục phải dựng lại khi dữ liệu cột đổi hay cột mất: quan hệ (`R$`), cấp phân cấp (`U$`), cột khác sắp xếp theo cột này.
    private static func requireNoIndexes(_ db: MetadataDatabase, columnID: Int, table: String, name: String, action: String) throws {
        let id = MetadataDatabase.Value.int(Int64(columnID))
        if (try db.int("SELECT COUNT(*) FROM Relationship WHERE FromColumnID = ? OR ToColumnID = ?", [id, id]) ?? 0) > 0 {
            throw WriteError.invalid("Chưa lưu được việc \(action) cột «\(table)[\(name)]»: cột nằm trong quan hệ (chỉ mục quan hệ chưa dựng lại được)")
        }
        if db.tableExists("Level"), (try db.int("SELECT COUNT(*) FROM Level WHERE ColumnID = ?", [id]) ?? 0) > 0 {
            throw WriteError.invalid("Chưa lưu được việc \(action) cột «\(table)[\(name)]»: cột là cấp của một phân cấp")
        }
        if (try db.int("SELECT COUNT(*) FROM [Column] WHERE SortByColumnID = ? AND ID <> ?", [id, id]) ?? 0) > 0 {
            throw WriteError.invalid("Chưa lưu được việc \(action) cột «\(table)[\(name)]»: cột khác sắp xếp theo cột này")
        }
    }

    // MARK: Thay và xoá bảng đã có trong file (Phase F, T063b)

    /// Xoá bảng người dùng khỏi file: dòng siêu dữ liệu, bảng hệ thống `H$` của cột và tệp ABF. Chỉ làm được khi bảng không dính quan hệ
    /// (chỉ mục quan hệ `R$` phải dựng lại theo dữ liệu mới, chưa cài), không có phân cấp, cột tính toán hay measure (xoá).
    public mutating func dropTable(_ name: String) throws {
        let snapshot = try database.serialize()
        let (addedBefore, removedBefore) = (addedFiles, removedFiles)
        do {
            var removed: [String] = []
            try transaction { db, now in
                let id = try db.userTableID(named: name)
                try Self.requireReplaceable(db, tableID: id, name: name, action: "xoá", allowedTypes: nil)
                if (try db.int("SELECT COUNT(*) FROM Measure WHERE TableID = ?", [.int(Int64(id))]) ?? 0) > 0 {
                    throw WriteError.invalid("Không thể xoá bảng «\(name)»: còn chứa measure")
                }
                try Self.deleteAnnotations(db, tableID: id, keeping: [])
                removed = try Self.removeUserTable(db, tableID: Int64(id))
                try Self.editQueryOrder(db, now: now) { order in order.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame } }
                try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
                try Self.bumpProperties(db, now)
            }
            removedFiles += removed
        } catch {
            database = try MetadataDatabase(bytes: snapshot)
            (addedFiles, removedFiles) = (addedBefore, removedBefore)
            throw error
        }
    }

    /// Thay dữ liệu và truy vấn của bảng đã có, giữ ID bảng, phân vùng, cột cùng tên và thuộc tính của chúng (ẩn, định dạng, thư mục
    /// hiển thị…), measure của bảng. Cùng điều kiện với `dropTable` (trừ measure). Lỗi thì cơ sở dữ liệu và danh sách tệp như trước.
    public mutating func replaceTable(_ name: String, with table: NewTable) throws {
        try replaceTable(name, with: table, calculated: false)
    }

    /// `calculated`: bảng tính toán (T116), cột kết quả `Type = 4` được giữ ID như cột dữ liệu.
    private mutating func replaceTable(_ name: String, with table: NewTable, calculated: Bool) throws {
        guard table.enableLoad else { return try dropTable(name) }
        let snapshot = try database.serialize()
        let (addedBefore, removedBefore, replacedBefore) = (addedFiles, removedFiles, replacedFiles)
        do {
            var reused = ReusedIDs(tableID: 0, partitionID: 0, rowNumberID: nil, columnIDs: [:])
            var removed: [String] = []
            var oldColumns: [OldColumn] = []
            var tableProperties: (hidden: Int64, description: String?, category: String?, lineage: String?) = (0, nil, nil, nil)
            try transaction { db, now in
                let id = try db.userTableID(named: name)
                try Self.requireReplaceable(db, tableID: id, name: name, action: calculated ? "sửa công thức" : "thay dữ liệu",
                                            allowedTypes: calculated ? [1, 3, 4] : [1, 3])
                let partitions = try db.strings("SELECT ID FROM Partition WHERE TableID = ?", [.int(Int64(id))])
                guard partitions.count == 1, let partitionID = Int(partitions[0]) else {
                    throw WriteError.invalid("Chưa lưu được việc thay dữ liệu của bảng «\(name)»: bảng có nhiều phân vùng")
                }
                reused = ReusedIDs(tableID: id, partitionID: partitionID,
                                   rowNumberID: try db.strings("SELECT ID FROM [Column] WHERE TableID = ? AND Type = 3", [.int(Int64(id))]).first.flatMap(Int.init),
                                   columnIDs: [:])
                for column in table.columns where reused.columnIDs[column.name] == nil {
                    let ids = try db.strings("""
                        SELECT ID FROM [Column] WHERE TableID = ? AND Type IN (1, 4) AND COALESCE(ExplicitName, InferredName) = ?
                        """, [.int(Int64(id)), .text(column.name)])
                    if ids.count == 1, let columnID = Int(ids[0]) { reused.columnIDs[column.name] = columnID }
                }
                tableProperties = (try db.int("SELECT IsHidden FROM [Table] WHERE ID = ?", [.int(Int64(id))]) ?? 0,
                                   try db.strings("SELECT Description FROM [Table] WHERE ID = ?", [.int(Int64(id))]).first,
                                   try db.strings("SELECT DataCategory FROM [Table] WHERE ID = ?", [.int(Int64(id))]).first,
                                   try db.strings("SELECT LineageTag FROM [Table] WHERE ID = ?", [.int(Int64(id))]).first)
                oldColumns = try Self.captureColumns(db, tableID: id)
                try Self.deleteAnnotations(db, tableID: id, keeping: Set(reused.columnIDs.values))
                removed = try Self.removeUserTable(db, tableID: Int64(id))
            }
            let added = addedFiles.count
            try addTable(table, reusing: reused)
            try transaction { db, now in
                try Self.restoreProperties(db, tableID: reused.tableID, old: oldColumns, table: tableProperties, now: now)
                if table.name != name {
                    try Self.editQueryOrder(db, now: now) { order in
                        if let i = order.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { order[i] = table.name }
                    }
                }
            }
            // Đường dẫn cũ trùng đường dẫn mới (cùng ID bảng, cột): ABF ghi đè tệp thay vì xoá rồi thêm.
            let newPaths = Dictionary(addedFiles[added...].enumerated().map { ($1.path, added + $0) }, uniquingKeysWith: { a, _ in a })
            var overwritten = Set<Int>()
            for path in removed {
                if let index = newPaths[path] {
                    replacedFiles.append(addedFiles[index])
                    overwritten.insert(index)
                } else {
                    removedFiles.append(path)
                }
            }
            addedFiles = addedFiles.enumerated().filter { !overwritten.contains($0.offset) }.map(\.element)
        } catch {
            database = try MetadataDatabase(bytes: snapshot)
            (addedFiles, removedFiles, replacedFiles) = (addedBefore, removedBefore, replacedBefore)
            throw error
        }
    }

    // MARK: Truy vấn không nạp (Enable load tắt, VM-F8)

    /// Ghi hoặc cập nhật truy vấn không nạp thành dòng `Expression` (M nguyên văn, `Kind` 0) như Desktop 2.159: chú thích `PBI_NavigationStepName`
    /// và `PBI_ResultType` (ObjectType 41) và tên truy vấn ở cuối `PBI_QueryOrder`. Tên không được trùng bảng đang nạp.
    public mutating func setQuery(name: String, expression: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WriteError.invalid("tên truy vấn trống") }
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !expression.contains("\0") else {
            throw WriteError.invalid("biểu thức M của truy vấn «\(name)» trống hoặc chứa NUL")
        }
        try transaction { db, now in
            guard db.tableExists("Expression"), db.tableExists("Annotation") else {
                throw WriteError.invalid("file không có bảng Expression, chưa lưu được truy vấn tắt Enable load")
            }
            if (try db.int("SELECT COUNT(*) FROM [Table] WHERE Name = ? COLLATE NOCASE", [.text(name)]) ?? 0) > 0 {
                throw WriteError.invalid("không thể lưu truy vấn «\(name)» không nạp: trùng tên một bảng trong mô hình")
            }
            if let existing = try db.int("SELECT ID FROM Expression WHERE Name = ? COLLATE NOCASE", [.text(name)]) {
                try db.run("UPDATE Expression SET Expression = ?, ModifiedTime = ? WHERE ID = ?", [.text(expression), .int(now), .int(existing)])
            } else {
                let stored = try db.storedMaxID(), actual = try db.actualMaxID()
                guard stored >= actual else { throw WriteError.verificationFailed("DBPROPERTIES.MAXID is \(stored) but the largest ID is \(actual)") }
                let id = Int64(stored + 1)
                try db.run("""
                    INSERT INTO Expression (ID, ModelID, Name, Description, Kind, Expression, ModifiedTime, QueryGroupID, ParameterValuesColumnID,
                        MAttributes, LineageTag, SourceLineageTag, RemoteParameterName, ExpressionSourceID)
                    VALUES (?, 1, ?, NULL, 0, ?, ?, 0, 0, NULL, ?, NULL, NULL, 0)
                    """, [.int(id), .text(name), .text(expression), .int(now), .text(UUID().uuidString.lowercased())])
                var next = id + 1
                for (key, value) in [("PBI_NavigationStepName", "Navigation"), ("PBI_ResultType", "Table")] {
                    try db.run("INSERT INTO Annotation (ID, ObjectID, ObjectType, Name, Value, ModifiedTime) VALUES (?, ?, 41, ?, ?, ?)",
                               [.int(next), .int(id), .text(key), .text(value), .int(now)])
                    next += 1
                }
                try db.run("UPDATE DBPROPERTIES SET VALUE = ? WHERE NAME = 'MAXID'", [.int(next - 1)])
            }
            try Self.editQueryOrder(db, now: now) { order in if !order.contains(name) { order.append(name) } }
            try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
            try Self.bumpProperties(db, now)
        }
    }

    /// Bỏ truy vấn không nạp (bật lại Enable load hoặc xoá truy vấn): xoá dòng `Expression`, chú thích và tên trong `PBI_QueryOrder`
    /// (truy vấn sắp nạp lại thành bảng sẽ được `addTable` thêm tên lại). Không có thì không làm gì.
    public mutating func dropQuery(name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try transaction { db, now in
            guard db.tableExists("Expression"),
                  let id = try db.int("SELECT ID FROM Expression WHERE Name = ? COLLATE NOCASE", [.text(name)]) else { return }
            try Self.deleteDependents(db, objectID: Int(id))
            try db.run("DELETE FROM Expression WHERE ID = ?", [.int(id)])
            try Self.editQueryOrder(db, now: now) { order in order.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame } }
            try db.run("UPDATE Model SET ModifiedTime = ?, StructureModifiedTime = ?", [.int(now), .int(now)])
            try Self.bumpProperties(db, now)
        }
    }

    /// Đặt chú thích của mô hình (`Annotation`, ObjectType 1, ObjectID 1): sửa giá trị nếu đã có, không thì thêm dòng mới với ID `MAXID + 1`.
    /// Dùng cho tài liệu mới (`NewDocument`): tắt Auto date/time, thêm `PBI_QueryOrder` rỗng.
    public mutating func setModelAnnotation(name: String, value: String) throws {
        try transaction { db, now in
            if (try db.int("SELECT COUNT(*) FROM Annotation WHERE ObjectType = 1 AND ObjectID = 1 AND Name = ?", [.text(name)]) ?? 0) > 0 {
                try db.run("UPDATE Annotation SET Value = ?, ModifiedTime = ? WHERE ObjectType = 1 AND ObjectID = 1 AND Name = ?",
                           [.text(value), .int(now), .text(name)])
            } else {
                let stored = try db.storedMaxID(), actual = try db.actualMaxID()
                guard stored >= actual else { throw WriteError.verificationFailed("DBPROPERTIES.MAXID is \(stored) but the largest ID is \(actual)") }
                let id = Int64(stored + 1)
                try db.run("INSERT INTO Annotation (ID, ObjectID, ObjectType, Name, Value, ModifiedTime) VALUES (?, 1, 1, ?, ?, ?)",
                           [.int(id), .text(name), .text(value), .int(now)])
                try db.run("UPDATE DBPROPERTIES SET VALUE = ? WHERE NAME = 'MAXID'", [.int(id)])
            }
            try Self.bumpProperties(db, now)
        }
    }

    /// Sửa mảng JSON `PBI_QueryOrder` (chú thích của mô hình). Không có chú thích thì không tạo.
    private static func editQueryOrder(_ db: MetadataDatabase, now: Int64, _ change: (inout [String]) -> Void) throws {
        guard let current = try db.strings("SELECT Value FROM Annotation WHERE ObjectType = 1 AND ObjectID = 1 AND Name = 'PBI_QueryOrder'").first,
              let data = current.data(using: .utf8), var order = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return }
        change(&order)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: order, options: [.withoutEscapingSlashes]), as: UTF8.self)
        try db.run("UPDATE Annotation SET Value = ?, ModifiedTime = ? WHERE ObjectType = 1 AND ObjectID = 1 AND Name = 'PBI_QueryOrder'", [.text(text), .int(now)])
    }

    /// Các quan hệ đang nối với bảng `name` (phía nào cũng được) để xoá rồi thêm lại quanh `replaceTable`: chỉ mục quan hệ `R$` phụ thuộc dữ liệu
    /// hai cột nên phải dựng lại theo bảng mới. Chỉ dựng lại được quan hệ nhiều-một mặc định (đúng loại `addRelationship` ghi); quan hệ có thuộc tính
    /// khác (tuỳ chỉnh ngày, tin cậy toàn vẹn tham chiếu, bảo mật dòng…) thì ném lỗi, không đoán.
    public func relationshipsToRebuild(touching name: String) throws -> [NewRelationship] {
        let db = database
        guard let tableID = try? db.userTableID(named: name) else { return [] }
        let ids = try db.strings("SELECT ID FROM Relationship WHERE FromTableID = ? OR ToTableID = ? ORDER BY ID", [.int(Int64(tableID)), .int(Int64(tableID))])
        return try ids.compactMap(Int64.init).map { id in
            func text(_ sql: String) throws -> String { try db.strings(sql, [.int(id)]).first ?? "" }
            func number(_ field: String) throws -> Int64 { try db.int("SELECT \(field) FROM Relationship WHERE ID = ?", [.int(id)]) ?? 0 }
            let relName = try text("SELECT Name FROM Relationship WHERE ID = ?")
            guard try number("Type") == 1, try number("FromCardinality") == 2, try number("ToCardinality") == 1, try number("JoinOnDateBehavior") == 1,
                  try number("RelyOnReferentialIntegrity") == 0, try number("SecurityFilteringBehavior") == 1, try number("State") == 1 else {
                throw WriteError.invalid("Chưa lưu được việc thay dữ liệu của bảng «\(name)»: quan hệ \(relName) có thuộc tính khác mặc định, chỉ mục quan hệ chưa dựng lại được")
            }
            func column(_ side: String) throws -> (table: String, column: String) {
                (try text("SELECT t.Name FROM Relationship r JOIN [Table] t ON t.ID = r.\(side)TableID WHERE r.ID = ?"),
                 try text("SELECT COALESCE(c.ExplicitName, c.InferredName) FROM Relationship r JOIN [Column] c ON c.ID = r.\(side)ColumnID WHERE r.ID = ?"))
            }
            let (fromTable, fromColumn) = try column("From"), (toTable, toColumn) = try column("To")
            return NewRelationship(name: relName, fromTable: fromTable, fromColumn: fromColumn, toTable: toTable, toColumn: toColumn,
                                   isActive: try number("IsActive") == 1, crossFilteringBehavior: Int(try number("CrossFilteringBehavior")))
        }
    }

    /// `allowedTypes`: loại cột (`Column.Type`) bảng được có; nil là bỏ qua (xoá bảng bỏ luôn cột tính toán của nó, như Desktop).
    private static func requireReplaceable(_ db: MetadataDatabase, tableID: Int, name: String, action: String,
                                           allowedTypes: [Int]? = [1, 3]) throws {
        let columns = "SELECT ID FROM [Column] WHERE TableID = \(tableID)"
        if (try db.int("SELECT COUNT(*) FROM Relationship WHERE FromColumnID IN (\(columns)) OR ToColumnID IN (\(columns))") ?? 0) > 0 {
            throw WriteError.invalid("Chưa lưu được việc \(action) của bảng «\(name)» đã có trong file: bảng đang tham gia quan hệ (chỉ mục quan hệ chưa dựng lại được)")
        }
        if db.tableExists("Hierarchy"), (try db.int("SELECT COUNT(*) FROM Hierarchy WHERE TableID = ?", [.int(Int64(tableID))]) ?? 0) > 0 {
            throw WriteError.invalid("Chưa lưu được việc \(action) của bảng «\(name)» đã có trong file: bảng có phân cấp")
        }
        if let allowedTypes, (try db.int("SELECT COUNT(*) FROM [Column] WHERE TableID = ? AND Type NOT IN (\(allowedTypes.map(String.init).joined(separator: ", ")))",
                                         [.int(Int64(tableID))]) ?? 0) > 0 {
            throw WriteError.invalid("Chưa lưu được việc \(action) của bảng «\(name)» đã có trong file: bảng có cột tính toán")
        }
        if (try db.int("SELECT COUNT(*) FROM [Column] WHERE TableID <> ? AND SortByColumnID IN (\(columns))", [.int(Int64(tableID))]) ?? 0) > 0 {
            throw WriteError.invalid("Chưa lưu được việc \(action) của bảng «\(name)» đã có trong file: cột của bảng khác sắp xếp theo cột của bảng này")
        }
    }

    /// Xoá `Annotation` và `ExtendedProperty` của bảng và của các cột không nằm trong `keeping`.
    private static func deleteAnnotations(_ db: MetadataDatabase, tableID: Int, keeping: Set<Int>) throws {
        let ids = try db.strings("SELECT ID FROM [Column] WHERE TableID = ?", [.int(Int64(tableID))]).compactMap(Int.init)
        for id in ids where !keeping.contains(id) { try deleteDependents(db, objectID: id) }
        try deleteDependents(db, objectID: tableID)
    }

    private static func deleteDependents(_ db: MetadataDatabase, objectID: Int) throws {
        for dependent in ["Annotation", "ExtendedProperty"] where db.tableExists(dependent) {
            try db.run("DELETE FROM [\(dependent)] WHERE ObjectID = ?", [.int(Int64(objectID))])
        }
    }

    /// Xoá bảng người dùng cùng bảng `H$` của cột (`removeSystemTable` lo từ điển, phân cấp thuộc tính và tệp); trả đường dẫn ABF.
    private static func removeUserTable(_ db: MetadataDatabase, tableID: Int64) throws -> [String] {
        try removeSystemTable(db, tableID: tableID)
    }

    private struct OldColumn {
        var id: Int64, name: String, dataType: Int64, isHidden: Int64, isKey: Int64, summarizeBy: Int64, sortBy: Int64
        var description: String?, displayFolder: String?, dataCategory: String?, lineageTag: String?, formatString: String?
    }

    private static func captureColumns(_ db: MetadataDatabase, tableID: Int) throws -> [OldColumn] {
        try db.strings("SELECT ID FROM [Column] WHERE TableID = ? AND Type IN (1, 4)", [.int(Int64(tableID))]).compactMap(Int64.init).map { id in
            func text(_ field: String) throws -> String? { try db.strings("SELECT \(field) FROM [Column] WHERE ID = ?", [.int(id)]).first }
            func number(_ field: String) throws -> Int64 { try db.int("SELECT \(field) FROM [Column] WHERE ID = ?", [.int(id)]) ?? 0 }
            return OldColumn(id: id, name: try text("COALESCE(ExplicitName, InferredName)") ?? "",
                             dataType: try number("CASE WHEN Type = 4 THEN InferredDataType ELSE ExplicitDataType END"),
                             isHidden: try number("IsHidden"), isKey: try number("IsKey"), summarizeBy: try number("SummarizeBy"),
                             sortBy: try number("SortByColumnID"), description: try text("Description"),
                             displayFolder: try text("DisplayFolder"), dataCategory: try text("DataCategory"),
                             lineageTag: try text("LineageTag"), formatString: try text("FormatString"))
        }
    }

    /// Đưa thuộc tính của cột cùng tên (và của bảng) từ bản cũ sang bản mới: ẩn, mô tả, thư mục hiển thị, nhóm dữ liệu, khoá,
    /// cột sắp xếp (nếu còn), nhãn dòng gốc; định dạng và cách tổng hợp chỉ khi kiểu dữ liệu không đổi (như bản trong bộ nhớ).
    /// Cột cùng tên giữ nguyên ID nên `SortByColumnID` cũ còn đúng khi cột sắp xếp còn.
    private static func restoreProperties(_ db: MetadataDatabase, tableID: Int, old: [OldColumn],
                                          table: (hidden: Int64, description: String?, category: String?, lineage: String?),
                                          now: Int64) throws {
        let current = try db.strings("SELECT ID FROM [Column] WHERE TableID = ? AND Type = 1", [.int(Int64(tableID))]).compactMap(Int64.init)
        for column in old where current.contains(column.id) {
            let sameType = (try db.int("SELECT ExplicitDataType FROM [Column] WHERE ID = ?", [.int(column.id)])) == column.dataType
            var sets = ["IsHidden = ?", "IsKey = ?", "Description = ?", "DisplayFolder = ?", "DataCategory = ?", "LineageTag = COALESCE(?, LineageTag)", "ModifiedTime = ?"]
            var values: [MetadataDatabase.Value] = [.int(column.isHidden), .int(column.isKey), optionalText(column.description),
                                                    optionalText(column.displayFolder), optionalText(column.dataCategory),
                                                    optionalText(column.lineageTag), .int(now)]
            if sameType {
                sets += ["FormatString = ?", "SummarizeBy = ?"]
                values += [optionalText(column.formatString), .int(column.summarizeBy)]
            }
            if column.sortBy != 0, current.contains(column.sortBy) { sets.append("SortByColumnID = ?"); values.append(.int(column.sortBy)) }
            values.append(.int(column.id))
            try db.run("UPDATE [Column] SET \(sets.joined(separator: ", ")) WHERE ID = ?", values)
        }
        try db.run("UPDATE [Table] SET IsHidden = ?, Description = ?, DataCategory = ?, LineageTag = COALESCE(?, LineageTag) WHERE ID = ?",
                   [.int(table.hidden), optionalText(table.description), optionalText(table.category), optionalText(table.lineage), .int(Int64(tableID))])
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
        case .addTable(let table):
            try addTable(table)
        case .replaceTable(let name, let table):
            try replaceTable(name, with: table)
        case .dropTable(let name):
            try dropTable(name)
        case .setQuery(let name, let expression):
            try setQuery(name: name, expression: expression)
        case .dropQuery(let name):
            try dropQuery(name: name)
        case .addCalculatedColumn(let table, let name, let expression, _):
            try addCalculatedColumn(table: table, name: name, expression: expression)
        case .addCalculatedTable(let name, let expression, let columns):
            try addCalculatedTable(name: name, expression: expression, columns: columns)
        case .updateCalculatedColumn(let table, let name, let expression, _):
            try updateCalculatedColumn(table: table, name: name, expression: expression)
        case .deleteCalculatedColumn(let table, let name):
            try deleteCalculatedColumn(table: table, name: name)
        case .updateCalculatedTable(let name, let expression, let columns):
            try updateCalculatedTable(name: name, expression: expression, columns: columns)
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
            WHERE t.Name = ? COLLATE NOCASE AND t.SystemFlags IN (0, 2) AND m.Name = ?
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
            files += try removeColumnStorage(db, columnID: columnID)
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

    /// Xoá dữ liệu lưu trữ của một cột (giữ dòng `Column`): phân cấp thuộc tính cùng bảng `H$` của nó, `ColumnStorage`, từ điển, phân đoạn
    /// và `StorageFile`. Trả đường dẫn ABF các tệp bị bỏ.
    private static func removeColumnStorage(_ db: MetadataDatabase, columnID: Int64) throws -> [String] {
        var files: [String] = []
        // Phân cấp thuộc tính của cột dữ liệu: bảng `H$` đi kèm (đệ quy), rồi dòng AttributeHierarchy(Storage).
        if db.tableExists("AttributeHierarchy"), db.tableExists("AttributeHierarchyStorage") {
            for ah in try db.strings("SELECT ID FROM AttributeHierarchy WHERE ColumnID = ?", [.int(columnID)]).compactMap(Int64.init) {
                for ahs in try db.strings("SELECT ID FROM AttributeHierarchyStorage WHERE AttributeHierarchyID = ?", [.int(ah)]).compactMap(Int64.init) {
                    if let system = try db.int("SELECT SystemTableID FROM AttributeHierarchyStorage WHERE ID = ?", [.int(ahs)]), system != 0 {
                        files += try removeSystemTable(db, tableID: system)
                    }
                    try db.run("DELETE FROM AttributeHierarchyStorage WHERE ID = ?", [.int(ahs)])
                }
                try db.run("DELETE FROM AttributeHierarchy WHERE ID = ?", [.int(ah)])
            }
        }
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
            for ds in try db.strings("SELECT ID FROM DictionaryStorage WHERE ColumnStorageID = ?", [.int(cs)]).compactMap(Int64.init) {
                files += try storageFilePaths(db, owner: ds, type: 22)
                try db.run("DELETE FROM StorageFile WHERE OwnerID = ? AND OwnerType = 22", [.int(ds)])
            }
            try db.run("DELETE FROM DictionaryStorage WHERE ColumnStorageID = ?", [.int(cs)])
            try db.run("DELETE FROM ColumnStorage WHERE ID = ?", [.int(cs)])
        }
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
            WHERE t.Name = ? COLLATE NOCASE AND t.SystemFlags IN (0, 2) AND COALESCE(c.ExplicitName, c.InferredName) = ?
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

    /// The user table (SystemFlags 0, or 2 for a calculated table) with this name. Table names are matched case-insensitively, as in DAX.
    func userTableID(named name: String) throws -> Int {
        let ids = try strings("SELECT ID FROM [Table] WHERE Name = ? COLLATE NOCASE AND SystemFlags IN (0, 2)", [.text(name)])
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
