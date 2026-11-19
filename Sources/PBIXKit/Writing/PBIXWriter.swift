import Foundation

/// Saves a `.pbix` with the requested changes, at the lowest tier that covers them
/// (docs/BIPRO_BUILD_PLAN.md §2). Lead-owned: it only composes the work-package writers.
///
/// Every save is verified before it replaces anything: the new bytes are reopened with
/// `PBIXFile` and each change is read back. Unchanged ZIP members are copied as raw
/// compressed payloads, so their bytes stay identical.
public enum PBIXWriter {
    public struct Result: Sendable {
        public let data: Data
        public let tier: SaveTier
        /// The DataModel decompressed from `data` while verifying it (nil when the model was not rebuilt), so callers that check
        /// more of the model read the written bytes without decompressing them again.
        public let model: ABFBackup?

        public init(data: Data, tier: SaveTier, model: ABFBackup? = nil) {
            self.data = data
            self.tier = tier
            self.model = model
        }
    }

    static let metadataPath = "metadata.sqlitedb"
    static let securityBindingsPath = "SecurityBindings"
    static let contentTypesPath = "[Content_Types].xml"
    static let diagramLayoutPath = "DiagramLayout"

    /// Builds the new `.pbix` bytes in memory and verifies them. With `rebuildModel`, the DataModel
    /// goes through the ABF rebuild and XPress9 recompression even when nothing in it changed
    /// (the test path used by gate W1).
    /// `BIPRO_TIMING=1` prints the time of each step of `build` to stderr (Phase E measurements).
    private static let timing = ProcessInfo.processInfo.environment["BIPRO_TIMING"] == "1"

    private static func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        guard timing else { return try body() }
        let start = Date()
        defer { FileHandle.standardError.write(Data("[timing] \(label): \(String(format: "%.2f", Date().timeIntervalSince(start))) s\n".utf8)) }
        return try body()
    }

    public static func build(source: URL, changes: PBIXChanges, rebuildModel: Bool = false) throws -> Result {
        let archive = try ZipArchive(url: source)
        for path in changes.reportParts.keys.sorted() where archive.entry(path) == nil {
            throw WriteError.invalid("\(path) is not a member of \(source.lastPathComponent)")
        }
        for path in changes.removedParts.sorted() {
            guard archive.entry(path) != nil else {
                throw WriteError.invalid("cannot remove \(path): not a member of \(source.lastPathComponent)")
            }
            guard changes.reportParts[path] == nil else {
                throw WriteError.invalid("\(path) is both replaced and removed")
            }
        }
        for path in changes.addedParts.keys.sorted() where archive.entry(path) != nil {
            throw WriteError.invalid("cannot add \(path): already a member of \(source.lastPathComponent)")
        }
        if changes.diagramLayout != nil, archive.entry(Self.diagramLayoutPath) == nil {
            throw WriteError.invalid("cannot replace \(Self.diagramLayoutPath): not a member of \(source.lastPathComponent)")
        }
        let needsModel = rebuildModel || changes.changesModel
        let rebuilt = needsModel ? try timed("rebuiltDataModel") {
            try rebuiltDataModel(archive: archive, edits: changes.allModelEdits, calculated: changes.calculatedData)
        } : nil
        let model = rebuilt?.stream

        let dropsBinding = changes.changesReport && archive.entry(Self.securityBindingsPath) != nil
        var members: [(path: String, source: ZipWriter.Source)] = []
        for entry in archive.entries {
            if changes.removedParts.contains(entry.path) { continue }
            if dropsBinding && entry.path == Self.securityBindingsPath { continue }
            if dropsBinding && entry.path == Self.contentTypesPath {
                let types = withoutSecurityBindingsOverride(try archive.read(entry))
                members.append((path: entry.path, source: types == nil ? .rawCopy(archive, entry) : .bytes(types!, method: 8)))
            } else if entry.path == "DataModel", let model {
                // The DataModel member is stored (method 0) in every Power BI file; keep it so.
                members.append((path: entry.path, source: .bytes(model, method: 0)))
            } else if entry.path == Self.diagramLayoutPath, let layout = changes.diagramLayout {
                members.append((path: entry.path, source: .bytes(layout, method: 8)))
            } else if let part = changes.reportParts[entry.path] {
                members.append((path: entry.path, source: .bytes(part, method: 8)))
            } else {
                members.append((path: entry.path, source: .rawCopy(archive, entry)))
            }
        }
        for path in changes.addedParts.keys.sorted() {
            let index = insertionIndex(for: path, in: members.map(\.path))
            members.insert((path: path, source: .bytes(changes.addedParts[path]!, method: 8)), at: index)
        }
        let data = try timed("zip") { try ZipWriter.write(members, modified: nil) }
        let readBack = try timed("verify") { try verify(data, changes: changes, source: archive, sourceABF: rebuilt?.source) }
        return Result(data: data, tier: changes.tier, model: readBack)
    }

    /// `[Content_Types].xml` without the `<Override PartName="/SecurityBindings" .../>` element, byte for byte
    /// otherwise (the BOM and spacing stay). Nil when there is no such element.
    static func withoutSecurityBindingsOverride(_ xml: Data) -> Data? {
        let text = [UInt8](xml)
        let open = Array(#"<Override PartName="/SecurityBindings""#.utf8)
        guard let start = text.indices.first(where: { text[$0...].starts(with: open) }) else { return nil }
        var end = start + open.count
        while end < text.count, text[end] != UInt8(ascii: ">") { end += 1 }
        guard end < text.count else { return nil }
        var out = text
        out.removeSubrange(start...end)
        return Data(out)
    }

    /// Where a new part goes: after the last member of the same folder of visuals (or the same page), for a page that
    /// is new to the file after the last member under `pages/`, otherwise at the end.
    static func insertionIndex(for path: String, in existing: [String]) -> Int {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if let pages = parts.firstIndex(of: "pages"), parts.count > pages + 2 {
            let pagePrefix = parts[...(pages + 1)].joined(separator: "/") + "/"
            for prefix in [pagePrefix + "visuals/", pagePrefix] {
                if let last = existing.lastIndex(where: { $0.hasPrefix(prefix) }) { return last + 1 }
            }
            // A page that is new to the file: after the last member under `pages/`.
            let pagesPrefix = parts[...pages].joined(separator: "/") + "/"
            if let last = existing.lastIndex(where: { $0.hasPrefix(pagesPrefix) }) { return last + 1 }
        }
        // Bookmarks (D6): after the last bookmark part, else after the last page part, else at the end.
        if path.hasPrefix("Report/definition/bookmarks/") {
            for prefix in ["Report/definition/bookmarks/", "Report/definition/pages/"] {
                if let last = existing.lastIndex(where: { $0.hasPrefix(prefix) }) { return last + 1 }
            }
        }
        return existing.count
    }

    /// Builds, verifies and writes the file. The write goes through a temporary file in the same folder
    /// and is swapped in only after it reopens cleanly. `backup` says what is kept of the previous file.
    @discardableResult
    public static func save(source: URL, to destination: URL, changes: PBIXChanges, rebuildModel: Bool = false,
                            backup: BackupPolicy = .sideBak) throws -> SaveTier {
        let result = try build(source: source, changes: changes, rebuildModel: rebuildModel)
        try write(result.data, to: destination, backup: backup)
        return result.tier
    }

    /// Writes already verified bytes: through a temporary file next to the destination, reopened before it
    /// replaces anything. On any failure the destination is unchanged and the temporary file is removed.
    public static func write(_ data: Data, to destination: URL, backup: BackupPolicy = .sideBak) throws {
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp)
            do {
                _ = try PBIXFile(url: temp)
            } catch {
                throw WriteError.verificationFailed("\(error)")
            }
            if fm.fileExists(atPath: destination.path) {
                do { try keepBackup(of: destination, policy: backup) } catch { throw WriteError.backupFailed("\(error)") }
                _ = try fm.replaceItemAt(destination, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: destination)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    static func keepBackup(of destination: URL, policy: BackupPolicy) throws {
        let fm = FileManager.default
        switch policy {
        case .none:
            return
        case .sideBak:
            let backup = destination.appendingPathExtension("bak")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: destination, to: backup) }
        case .directory(let folder):
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let key = destination.standardizedFileURL.resolvingSymlinksInPath().path
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
            let name = String(hash, radix: 16).padding(toLength: 16, withPad: "0", startingAt: 0) + "-" + destination.lastPathComponent
            let backup = folder.appendingPathComponent(name)
            let staged = folder.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
            try fm.copyItem(at: destination, to: staged)
            if fm.fileExists(atPath: backup.path) {
                _ = try fm.replaceItemAt(backup, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: backup)
            }
        }
    }

    /// T2: adds measures to metadata.sqlitedb, rebuilds the ABF and recompresses the DataModel.
    static func rebuiltDataModel(archive: ZipArchive, measures: [NewMeasure]) throws -> Data {
        try rebuiltDataModel(archive: archive, edits: ModelEdits(measures.map { .addMeasure($0) })).stream
    }

    /// T2: applies model edits to metadata.sqlitedb, rebuilds the ABF and recompresses the DataModel. Also returns the source ABF it
    /// decompressed, which `verify` compares against.
    static func rebuiltDataModel(archive: ZipArchive, edits: ModelEdits,
                                 calculated: [String: VertiPaqWriter.Values] = [:]) throws -> (stream: Data, source: ABFBackup) {
        guard let entry = archive.entry("DataModel") else { throw ZipArchive.Error.missingEntry("DataModel") }
        let stream = try archive.storedSlice(entry) ?? archive.read(entry)
        let (abfBytes, _) = try timed("decompress") { try DataModelStream.decompress(stream) }
        let abf = try ABFBackup(data: abfBytes)
        guard let metadataFile = abf.file(named: metadataPath) else {
            throw WriteError.invalid("the data model has no \(metadataPath)")
        }
        var metadata = try MetadataWriter(sqlite: try abf.contents(of: metadataFile))
        metadata.calculatedValues = calculated
        // Chỉ mục quan hệ mới đọc từ dữ liệu cột của ABF gốc (lược đồ lưu trữ cột không đổi giữa các thao tác).
        let sourceModel = try ModelMetadata(sqlite: try abf.contents(of: metadataFile))
        // Bảng thêm trong cùng đợt chưa nằm trong ABF: cột của chúng lấy từ dữ liệu mã hoá trong thao tác.
        let collapsed = edits.collapsingTableEdits()
        var inMemory: [String: NewTable] = [:]
        for item in collapsed.items {
            switch item {
            case .addTable(let table) where table.enableLoad: inMemory[table.name.lowercased()] = table
            case .replaceTable(_, let table) where table.enableLoad: inMemory[table.name.lowercased()] = table
            default: break
            }
        }
        // Bảng và cột tính toán thêm trong đợt: giá trị đã tính theo khoá `Bảng[Cột]` (bảng ngày cục bộ của Auto date/time, T031).
        let calculatedByKey = Dictionary(calculated.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        func cells(_ table: String, _ column: String) -> [CellValue]? {
            guard let values = inMemory[table.lowercased()]?.columns.first(where: { $0.name == column })?.values
                    ?? calculatedByKey["\(table)[\(column)]".lowercased()] else { return nil }
            switch values {
            case .int64(let v): return v.map { $0.map { .int($0) } ?? .null }
            case .currency(let v): return v.map { $0.map { .decimal(Double($0) / 10_000) } ?? .null }
            case .boolean(let v): return v.map { $0.map { .bool($0) } ?? .null }
            case .double(let v): return v.map { $0.map { .double($0 == 0 ? 0 : $0) } ?? .null }
            case .dateTime(let v): return v.map { $0.map { .dateTime($0) } ?? .null }
            case .string(let v): return v.map { $0.map { .string($0) } ?? .null }
            }
        }
        metadata.relationshipIndexProvider = { new in
            // Quan hệ chỉ so phần ngày (`JoinOnDateBehavior` 2): hai phía so theo ngày, bỏ phần giờ.
            func datePart(_ list: [CellValue]) -> [CellValue] {
                guard new.joinOnDateBehavior == 2 else { return list }
                return list.map { if case .dateTime(let d) = $0 { .dateTime(d.rounded(.down)) } else { $0 } }
            }
            let fromCells = cells(new.fromTable, new.fromColumn), toCells = cells(new.toTable, new.toColumn)
            if fromCells != nil || toCells != nil || new.joinOnDateBehavior == 2 {
                // Phía nào nằm trong bộ nhớ thì dùng ô của nó, phía kia đọc từ ABF (phía nhiều theo từ điển của ABF).
                func abfColumn(_ table: String, _ column: String) throws -> DecodedColumn {
                    guard let storage = sourceModel.storage(table: table, column: column) else {
                        throw WriteError.invalid("cột \(table)[\(column)] không có dữ liệu lưu trữ")
                    }
                    return try VertiPaq.decodeColumn(storage, abf: abf)
                }
                let one: [CellValue]
                if let toCells { one = toCells } else { let c = try abfColumn(new.toTable, new.toColumn); one = (0..<c.count).map { c[$0] } }
                let oneName = "\(new.toTable)[\(new.toColumn)]"
                if let fromCells {
                    return (try RelationshipIndex.values(manyDictionary: datePart(RelationshipIndex.dictionary(ofCells: fromCells)), oneCells: datePart(one), oneName: oneName), one.count)
                }
                guard let storage = sourceModel.storage(table: new.fromTable, column: new.fromColumn) else {
                    throw WriteError.invalid("cột \(new.fromTable)[\(new.fromColumn)] không có dữ liệu lưu trữ")
                }
                if new.joinOnDateBehavior == 2 {
                    guard case .dictionary(_, let dictionary) = try abfColumn(new.fromTable, new.fromColumn).storage else {
                        throw WriteError.invalid("cột \(new.fromTable)[\(new.fromColumn)] không mã hoá bằng từ điển, chưa tạo được chỉ mục quan hệ")
                    }
                    return (try RelationshipIndex.values(manyDictionary: datePart(dictionary), oneCells: datePart(one), oneName: oneName), one.count)
                }
                return (try RelationshipIndex.values(from: storage, abf: abf, oneCells: one, oneName: oneName), one.count)
            }
            guard let from = sourceModel.storage(table: new.fromTable, column: new.fromColumn),
                  let to = sourceModel.storage(table: new.toTable, column: new.toColumn) else {
                throw WriteError.invalid("cột \(new.fromTable)[\(new.fromColumn)] hoặc \(new.toTable)[\(new.toColumn)] không có dữ liệu lưu trữ")
            }
            return (try RelationshipIndex.values(from: from, to: to, abf: abf), try VertiPaq.rowCount(to, abf: abf))
        }
        // Phân cấp mới (T030): cột của bảng thêm trong cùng đợt lấy từ dữ liệu mã hoá, cột đã có trong ABF đọc mã dữ liệu và `H$`.
        metadata.hierarchyLevelsProvider = { table, levels in
            if let memory = inMemory[table.lowercased()] {
                func values(_ column: String) throws -> VertiPaqWriter.Values {
                    guard let v = memory.columns.first(where: { $0.name == column })?.values
                            ?? calculatedByKey["\(table)[\(column)]".lowercased()] else {
                        throw WriteError.invalid("bảng \(table) không có cột \(column)")
                    }
                    return v
                }
                return try levels.map { try HierarchyIndex.level(try values($0.column), sortBy: try $0.sortBy.map(values)) }
            }
            func stored(_ column: String) throws -> (ModelMetadata.ColumnStorage, Int) {
                guard let storage = sourceModel.storage(table: table, column: column),
                      let id = sourceModel.columns.first(where: { $0.tableName == table && $0.name == column })?.id else {
                    throw WriteError.invalid("cột \(table)[\(column)] không có dữ liệu lưu trữ")
                }
                return (storage, id)
            }
            // Cột tính toán vừa tính lại (US4) lấy giá trị trong bộ nhớ, cột khác đọc từ ABF; hai nguồn ghép được vì mã dữ liệu của cột
            // mới theo đúng `VertiPaqWriter.encodeDictionary` mà bộ ghi dùng.
            func ranked(_ column: String) throws -> HierarchyIndex.Ranked {
                if let values = calculatedByKey["\(table)[\(column)]".lowercased()] { return try HierarchyIndex.ranked(values) }
                let (storage, id) = try stored(column)
                return try HierarchyIndex.ranked(storage, columnID: id, abf: abf)
            }
            return try levels.map { level in try HierarchyIndex.level(try ranked(level.column), sortBy: try level.sortBy.map(ranked)) }
        }
        /// Cột sắp theo `sortColumn` phải còn một–một với giá trị mới của nó: Desktop báo không sắp được khi một giá trị của cột được sắp ứng
        /// với nhiều giá trị của cột sắp xếp.
        func checkSortedColumns(table: String, sortColumn: String) throws {
            let sorted = try metadata.columnsSorted(by: table, column: sortColumn)
            guard !sorted.isEmpty, let keys = cells(table, sortColumn) else { return }
            for column in sorted {
                let own: [CellValue]
                if let memory = cells(table, column) { own = memory } else {
                    guard let storage = sourceModel.storage(table: table, column: column) else { continue }
                    let decoded = try VertiPaq.decodeColumn(storage, abf: abf)
                    own = (0..<decoded.count).map { decoded[$0] }
                }
                guard own.count == keys.count else { continue }
                var seen: [CellValue: CellValue] = [:]
                for (value, key) in zip(own, keys) {
                    if let previous = seen.updateValue(key, forKey: value), previous != key {
                        throw WriteError.invalid("Không sắp «\(table)[\(column)]» theo «\(sortColumn)» được nữa: một giá trị của «\(column)» (\(value)) "
                                                 + "ứng với nhiều giá trị của «\(sortColumn)». Hãy chọn cột sắp xếp khác hoặc sửa công thức «\(sortColumn)».")
                    }
                }
            }
        }
        // Thay dữ liệu bảng đang dính quan hệ: xoá quan hệ (kèm bảng `R$` và tệp chỉ mục), thay bảng, thêm lại quan hệ cùng tên với chỉ mục dựng từ
        // dữ liệu mới. Bảng xoá khỏi file mà còn quan hệ thì `dropTable` từ chối như trước.
        for edit in collapsed.items {
            // Cột tính toán còn được dùng (US4, T049): dựng lại `R$` của quan hệ và `U$` của phân cấp theo dữ liệu mới; xoá thì bỏ kèm.
            switch edit {
            case .updateCalculatedColumn(let table, let name, _, _):
                try checkSortedColumns(table: table, sortColumn: name)
                let relationships = try metadata.relationships(using: table, column: name)
                let hierarchies = try metadata.hierarchies(using: table, column: name)
                for relationship in relationships { try metadata.apply(.deleteRelationship(name: relationship.name)) }
                for hierarchy in hierarchies { try metadata.apply(.dropHierarchy(table: hierarchy.table, name: hierarchy.name)) }
                try metadata.apply(edit)
                for hierarchy in hierarchies { try metadata.apply(.addHierarchy(hierarchy)) }
                for relationship in relationships { try metadata.apply(.addRelationship(relationship)) }
                continue
            case .deleteCalculatedColumn(let table, let name):
                // `[SUY ĐOÁN]` như Desktop xoá cột (VM-F13 chưa quan sát): bỏ quan hệ dùng cột, bỏ cấp khỏi phân cấp (hết cấp thì bỏ phân cấp),
                // cột sắp theo cột này về sắp mặc định.
                for relationship in try metadata.relationships(using: table, column: name) { try metadata.apply(.deleteRelationship(name: relationship.name)) }
                for hierarchy in try metadata.hierarchies(using: table, column: name) {
                    try metadata.apply(.dropHierarchy(table: hierarchy.table, name: hierarchy.name))
                    var rest = hierarchy
                    rest.levels.removeAll { $0.column.caseInsensitiveCompare(name) == .orderedSame }
                    if !rest.levels.isEmpty { try metadata.apply(.addHierarchy(rest)) }
                }
                for column in try metadata.columnsSorted(by: table, column: name) {
                    try metadata.apply(.updateColumn(table: table, name: column, patch: ColumnPatch(sortBy: .clear)))
                }
                try metadata.apply(edit)
                continue
            default:
                break
            }
            guard case .replaceTable(let old, let new) = edit, new.enableLoad else { try metadata.apply(edit); continue }
            let relationships = try metadata.relationshipsToRebuild(touching: old)
            for relationship in relationships { try metadata.apply(.deleteRelationship(name: relationship.name)) }
            try metadata.apply(edit)
            for var relationship in relationships {
                if relationship.fromTable == old { relationship.fromTable = new.name }
                if relationship.toTable == old { relationship.toTable = new.name }
                try metadata.apply(.addRelationship(relationship))
            }
        }
        let newABF = try timed("abfRebuild") { try ABFWriter.rebuild(abf, replacing: [ABFPayload(path: metadataFile.path, data: try metadata.serialize())] + metadata.replacedFiles, adding: metadata.addedFiles, removing: metadata.removedFiles) }
        return (try timed("compress") { try DataModelStream.compress(abf: newABF) }, abf)
    }

    /// Reads the written bytes back and checks every change. With the source archive it also checks that
    /// every member that was not touched is unchanged. `sourceABF` is the source DataModel already decompressed by the build
    /// (read from `source` otherwise). Returns the DataModel read back from `data` when the model changed.
    @discardableResult
    static func verify(_ data: Data, changes: PBIXChanges, source: ZipArchive? = nil, sourceABF: ABFBackup? = nil) throws -> ABFBackup? {
        let pbix: PBIXFile
        do {
            pbix = try PBIXFile(data: data)
        } catch {
            throw WriteError.verificationFailed("cannot reopen the new file: \(error)")
        }
        for (path, expected) in changes.reportParts.merging(changes.addedParts, uniquingKeysWith: { a, _ in a }) {
            let actual = try pbix.archive.read(path)
            guard actual == expected else { throw WriteError.verificationFailed("\(path) does not read back") }
        }
        for path in changes.removedParts where pbix.archive.entry(path) != nil {
            throw WriteError.verificationFailed("\(path) is still in the file")
        }
        if let source {
            let dropsBinding = changes.changesReport && source.entry(Self.securityBindingsPath) != nil
            var touched = Set(changes.reportParts.keys).union(changes.removedParts)
            if dropsBinding {
                touched.formUnion([Self.securityBindingsPath, Self.contentTypesPath])
                if pbix.archive.entry(Self.securityBindingsPath) != nil {
                    throw WriteError.verificationFailed("SecurityBindings is still in the file")
                }
                if let types = pbix.archive.entry(Self.contentTypesPath),
                   String(decoding: try pbix.archive.read(types), as: UTF8.self).contains("SecurityBindings") {
                    throw WriteError.verificationFailed("[Content_Types].xml still mentions SecurityBindings")
                }
            }
            let isModelRebuilt = changes.changesModel
            if let layout = changes.diagramLayout {
                touched.insert(Self.diagramLayoutPath)
                guard let entry = pbix.archive.entry(Self.diagramLayoutPath), try pbix.archive.read(entry) == layout else {
                    throw WriteError.verificationFailed("DiagramLayout does not read back")
                }
            }
            for entry in source.entries where !touched.contains(entry.path) {
                if isModelRebuilt && entry.path == "DataModel" { continue }
                guard let now = pbix.archive.entry(entry.path), now.crc32 == entry.crc32,
                      now.uncompressedSize == entry.uncompressedSize else {
                    throw WriteError.verificationFailed("\(entry.path) changed although it was not meant to")
                }
            }
            let expectedCount = source.entries.count + changes.addedParts.count - changes.removedParts.count - (dropsBinding ? 1 : 0)
            guard pbix.archive.entries.count == expectedCount else {
                throw WriteError.verificationFailed("unexpected number of members")
            }
        }
        guard changes.changesModel else { return nil }
        let (abf, _) = try timed("verify.decompressNew") { try pbix.loadDataModel() }
        let model = try ModelMetadata(sqlite: try abf.contents(named: metadataPath))
        if let source {
            // Mô hình đọc lại phải bằng mô hình nguồn sau khi áp đúng danh sách thao tác (bỏ `lineageTag` của measure mới).
            let oldABF = try sourceABF ?? timed("verify.decompressOld") { try PBIXFile(archive: source).loadDataModel().0 }
            let oldModel = try ModelMetadata(sqlite: try oldABF.contents(named: metadataPath))
            let expected: ModelMetadata
            do { expected = try oldModel.applying(changes.allModelEdits) } catch {
                throw WriteError.verificationFailed("model edits do not apply to the source model: \(error)")
            }
            func plain(_ m: ModelMetadata.Measure) -> ModelMetadata.Measure {
                ModelMetadata.Measure(tableName: m.tableName, name: m.name, expression: m.expression, formatString: m.formatString,
                                      displayFolder: m.displayFolder, isHidden: m.isHidden, description: m.description, lineageTag: nil,
                                      dataType: m.dataType, state: m.state, formatStringDefinition: nil)
            }
            func sorted(_ list: [ModelMetadata.Measure]) -> [ModelMetadata.Measure] {
                list.map(plain).sorted { ($0.tableName, $0.name) < ($1.tableName, $1.name) }
            }
            guard sorted(model.measures).map({ "\($0)" }) == sorted(expected.measures).map({ "\($0)" }) else {
                throw WriteError.verificationFailed("measures read back differ from the edited model")
            }
            guard model.tables.filter(\.isUserTable).map({ "\($0.name)|\($0.isHidden)" }) == expected.tables.filter(\.isUserTable).map({ "\($0.name)|\($0.isHidden)" }) else {
                throw WriteError.verificationFailed("tables read back differ from the edited model")
            }
            // Quan hệ dựng lại quanh thay bảng có ID mới nên đứng cuối danh sách: so theo tên, không theo thứ tự.
            guard model.relationships.sorted(by: { $0.name < $1.name }) == expected.relationships.sorted(by: { $0.name < $1.name }) else {
                throw WriteError.verificationFailed("relationships read back differ from the edited model")
            }
            // Auto date/time (T031): quan hệ tới bảng ngày, variation và chú thích mô hình vừa đặt.
            guard model.dateTableRelationships.sorted(by: { $0.name < $1.name }) == expected.dateTableRelationships.sorted(by: { $0.name < $1.name }),
                  Set(model.variations) == Set(expected.variations) else {
                throw WriteError.verificationFailed("date tables or variations read back differ from the edited model")
            }
            for case .setModelAnnotation(let name, _) in changes.allModelEdits.items where model.modelAnnotations[name] != expected.modelAnnotations[name] {
                throw WriteError.verificationFailed("model annotation \(name) does not read back")
            }
            // Cột `INDEX` của bảng hệ thống `R$` (chỉ mục quan hệ) không thuộc mô hình hiệu lực.
            // Bảng mới (T3): ID do bộ ghi cấp và có thêm cột RowNumber, bảng `H$`; so theo tên, kiểu, ẩn và cách tổng hợp.
            let sourceTables = Set(oldModel.tables.map(\.name))
            // Bảng thay dữ liệu (T063b) coi như bảng mới: ID cột và tệp do bộ ghi cấp lại; bảng bị thay hoặc xoá thì tệp cũ của nó đổi hoặc mất.
            var replacedNames = Set<String>(), goneNames = Set<String>()
            for case .replaceTable(let old, let new) in changes.allModelEdits.items { replacedNames.insert(new.name); goneNames.insert(old) }
            for case .dropTable(let dropped) in changes.allModelEdits.items { goneNames.insert(dropped) }
            // Bảng tính toán sửa công thức (T116): ghi lại như thay dữ liệu.
            for case .updateCalculatedTable(let name, _, _) in changes.allModelEdits.items { replacedNames.insert(name); goneNames.insert(name) }
            let newTableNames = Set(expected.tables.map(\.name)).subtracting(sourceTables).union(replacedNames)
            // Cột tính toán thêm vào bảng đã có (T084): ID do bộ ghi cấp; so theo tên, kiểu, ẩn, cách tổng hợp và biểu thức.
            var calculatedKeys = Set<String>()
            for case .addCalculatedColumn(let table, let name, _, _) in changes.allModelEdits.items { calculatedKeys.insert("\(table)|\(name)") }
            func userColumns(_ m: ModelMetadata) -> [ModelMetadata.Column] {
                m.columns.filter { !$0.tableName.hasPrefix("R$") && !$0.tableName.hasPrefix("H$") && !$0.tableName.hasPrefix("U$") && !newTableNames.contains($0.tableName)
                    && !calculatedKeys.contains("\($0.tableName)|\($0.name)") }
            }
            func calculatedColumns(_ m: ModelMetadata) -> [String] {
                m.columns.filter { calculatedKeys.contains("\($0.tableName)|\($0.name)") }
                    .map { "\($0.tableName)|\($0.name)|\($0.dataType.rawValue)|\($0.isHidden)|\($0.summarizeBy)|\($0.kind)|\($0.expression ?? "")" }.sorted()
            }
            guard calculatedColumns(model) == calculatedColumns(expected) else {
                throw WriteError.verificationFailed("calculated columns read back differ from the edited model")
            }
            func newColumns(_ m: ModelMetadata) -> [String] {
                m.columns.filter { newTableNames.contains($0.tableName) && $0.kind != .rowNumber }
                    .map { "\($0.tableName)|\($0.name)|\($0.dataType.rawValue)|\($0.isHidden)|\($0.summarizeBy)" }.sorted()
            }
            guard userColumns(model) == userColumns(expected), newColumns(model) == newColumns(expected) else {
                let read = Set(userColumns(model)), wanted = Set(userColumns(expected))
                let odd = read.symmetricDifference(wanted).map { "\($0.tableName)[\($0.name)]" } + Set(newColumns(model)).symmetricDifference(newColumns(expected))
                throw WriteError.verificationFailed("columns read back differ from the edited model (\(Set(odd).sorted().prefix(4).joined(separator: ", ")))")
            }
            // Mọi tệp ABF khác metadata.sqlitedb giữ nguyên byte; chỉ có thêm hoặc bớt tệp chỉ mục quan hệ (2 tệp mỗi quan hệ).
            let compareStart = Date()
            defer { if timing { FileHandle.standardError.write(Data("[timing] verify.compareFiles: \(String(format: "%.2f", Date().timeIntervalSince(compareStart))) s\n".utf8)) } }
            let oldPaths = Set(oldABF.files.map { $0.path }), newPaths = Set(abf.files.map { $0.path })
            let isIndex: (String) -> Bool = { $0.hasSuffix("INDEX.0.idf") || $0.hasSuffix("INDEX.0.idfmeta") }
            let addedPaths = newPaths.subtracting(oldPaths), removedPaths = oldPaths.subtracting(newPaths)
            // Quan hệ nối với bảng thay dữ liệu được xoá rồi thêm lại (chỉ mục `R$` dựng theo dữ liệu mới): thêm vào số tệp chỉ mục được phép đổi.
            let replacedOldNames = Set(changes.allModelEdits.items.compactMap { edit -> String? in
                if case .replaceTable(let old, let new) = edit, new.enableLoad { old } else { nil }
            })
            // Một–một có hai chỉ mục (T066): tính là hai.
            let weight: (String) -> Int = { $0 == "1:1" ? 2 : 1 }
            // Cột tính toán sửa (US4): quan hệ và phân cấp dùng cột được xoá rồi thêm lại; xoá cột: quan hệ bỏ, phân cấp bỏ (còn cấp thì thêm lại).
            var updatedColumns = Set<String>(), deletedColumns = Set<String>()
            for edit in changes.allModelEdits.items {
                if case .updateCalculatedColumn(let t, let n, _, _) = edit { updatedColumns.insert("\(t)[\(n)]".lowercased()) }
                if case .deleteCalculatedColumn(let t, let n) = edit { deletedColumns.insert("\(t)[\(n)]".lowercased()) }
            }
            func usesColumn(_ r: ModelMetadata.Relationship, _ set: Set<String>) -> Bool {
                set.contains("\(r.fromTable)[\(r.fromColumn)]".lowercased()) || set.contains("\(r.toTable)[\(r.toColumn)]".lowercased())
            }
            func hierarchyUses(_ h: ModelMetadata.Hierarchy, _ set: Set<String>) -> Bool {
                h.levels.contains { set.contains("\(h.tableName)[\($0.columnName)]".lowercased()) }
            }
            let calcRebuilt = oldModel.relationships.filter { usesColumn($0, updatedColumns) }.reduce(0) { $0 + weight($1.cardinality) }
            let calcDropped = oldModel.relationships.filter { usesColumn($0, deletedColumns) }.reduce(0) { $0 + weight($1.cardinality) }
            let hierarchyRebuilt = oldModel.hierarchies.filter { hierarchyUses($0, updatedColumns) || hierarchyUses($0, deletedColumns) }.count
            let rebuilt = oldModel.relationships.filter { replacedOldNames.contains($0.fromTable) || replacedOldNames.contains($0.toTable) }
                .reduce(0) { $0 + weight($1.cardinality) } + calcRebuilt
            let adds = changes.allModelEdits.items.reduce(0) { total, edit in
                if case .addRelationship(let r) = edit { total + (!r.fromMany && !r.toMany ? 2 : 1) } else { total }
            } + rebuilt
            let deletes = changes.allModelEdits.items.reduce(0) { total, edit in
                if case .deleteRelationship(let name) = edit {
                    total + ((oldModel.relationships + oldModel.dateTableRelationships).first { $0.name == name }.map { weight($0.cardinality) } ?? 1)
                } else { total }
            } + rebuilt + calcDropped
            // Bảng mới: tệp của bảng (`<Tên> (<id>).tbl…`) và của bảng hệ thống `H$<Tên> (<id>)$…`.
            // Tên tệp của bảng do Desktop ghi thay ký tự không phải chữ số bằng khoảng trắng ("Dim_Loan_Profile" thành "Dim Loan Profile (31).tbl").
            // Khớp cả mã bảng: tiền tố chỉ theo tên ("Sales (") còn trúng tệp của bảng "Sales (2)" và bỏ qua so byte của nó (lỗi T096/T104).
            let flat = Self.flatFileName
            let newPrefixes = Self.tableFilePrefixes(model.tables.filter { newTableNames.contains($0.name) }.map { ($0.name, $0.id) })
            let gonePrefixes = Self.tableFilePrefixes(oldModel.tables.filter { goneNames.contains($0.name) }.map { ($0.name, $0.id) })
            // Cột tính toán thêm vào bảng đã có (T084): tệp mới của cột trong thư mục bảng, phân vùng và bảng `H$` của cột.
            // Cột tính toán sửa công thức hoặc xoá (T116): tệp cũ của cột bỏ, tệp mới (cùng hoặc khác tên) thêm.
            let calculatedFiles: [(table: [String], column: String)] = changes.allModelEdits.items.compactMap { edit in
                switch edit {
                case .addCalculatedColumn(let table, let name, _, _), .updateCalculatedColumn(let table, let name, _, _),
                     .deleteCalculatedColumn(let table, let name):
                    let ids = (model.tables + oldModel.tables).filter { $0.name == table }.map { ($0.name, $0.id) }
                    return (Self.tableFilePrefixes(ids), flat("\(name) ("))
                default:
                    return nil
                }
            }
            let isCalculatedFile: (String) -> Bool = { path in
                let f = flat(path)
                return calculatedFiles.contains { item in item.table.contains { f.hasPrefix($0) } && f.contains(item.column) }
            }
            let isNewTableFile: (String) -> Bool = { path in let f = flat(path); return newPrefixes.contains { f.hasPrefix($0) } || isCalculatedFile(path) }
            let isGoneTableFile: (String) -> Bool = { path in let f = flat(path); return gonePrefixes.contains { f.hasPrefix($0) } || isCalculatedFile(path) }
            let isTouchedTableFile: (String) -> Bool = { isNewTableFile($0) || isGoneTableFile($0) }
            // Phân cấp thêm hay xoá (T030): bốn cột của bảng `U$`, mỗi cột `.idf` và `.idfmeta`.
            let isHierarchyIndex: (String) -> Bool = { $0.hasPrefix("U$") }
            let hierarchyAdds = changes.allModelEdits.items.filter { if case .addHierarchy = $0 { true } else { false } }.count + hierarchyRebuilt
            let hierarchyDrops = changes.allModelEdits.items.filter { if case .dropHierarchy = $0 { true } else { false } }.count + hierarchyRebuilt
            guard addedPaths.allSatisfy({ isIndex($0) || isHierarchyIndex($0) || isNewTableFile($0) }),
                  removedPaths.allSatisfy({ isIndex($0) || isHierarchyIndex($0) || isGoneTableFile($0) }),
                  addedPaths.filter(isIndex).count <= 2 * adds, removedPaths.filter(isIndex).count <= 2 * deletes,
                  addedPaths.filter(isHierarchyIndex).count <= 8 * hierarchyAdds, removedPaths.filter(isHierarchyIndex).count <= 8 * hierarchyDrops else {
                let strayAdded: [String] = addedPaths.filter { !(isIndex($0) || isHierarchyIndex($0) || isNewTableFile($0)) }
                let strayRemoved: [String] = removedPaths.filter { !(isIndex($0) || isHierarchyIndex($0) || isGoneTableFile($0)) }
                let strays = strayAdded + strayRemoved
                throw WriteError.verificationFailed("the ABF file list changed unexpectedly (\(strays.prefix(3).joined(separator: "; ")); index +\(addedPaths.filter(isIndex).count)/-\(removedPaths.filter(isIndex).count), allowed \(2 * adds)/\(2 * deletes))")
            }
            let newFiles = Dictionary(uniqueKeysWithValues: abf.files.map { ($0.path, $0) })
            let metadataFilePath = abf.file(named: metadataPath)?.path
            for file in oldABF.files where file.path != metadataFilePath && !removedPaths.contains(file.path) && !isTouchedTableFile(file.path) {
                guard let other = newFiles[file.path],
                      try oldABF.contents(of: file) == abf.contents(of: other) else {
                    throw WriteError.verificationFailed("\(file.path) changed although it was not meant to")
                }
            }
        } else {
            for measure in changes.measures {
                let found = model.measures.contains {
                    $0.tableName == measure.table && $0.name == measure.name && $0.expression == measure.expression
                }
                guard found else { throw WriteError.verificationFailed("measure \(measure.name) is missing after save") }
            }
        }
        return abf
    }
}

extension PBIXFile {
    /// A `PBIXFile` over an archive that is already open.
    init(archive: ZipArchive) { self.archive = archive }
}

extension PBIXWriter {
    /// Tên tệp ABF do Desktop ghi thay ký tự không phải chữ, số, `(`, `$`, `.`, `\\` bằng khoảng trắng ("Dim_Loan_Profile" → "Dim Loan Profile (31).tbl").
    static func flatFileName(_ text: String) -> String {
        String(text.map { $0.isLetter || $0.isNumber || $0 == "(" || $0 == "$" || $0 == "." || $0 == "\\" ? $0 : " " })
    }

    /// Tiền tố tệp của bảng và bảng hệ thống `H$` của nó, kèm mã bảng: `<Tên> (<id>)` và `H$<Tên> (<id>)$`.
    static func tableFilePrefixes(_ tables: [(name: String, id: Int)]) -> [String] {
        tables.flatMap { [flatFileName("\($0.name) (\($0.id))"), flatFileName("H$\($0.name) (\($0.id))$")] }
    }
}
