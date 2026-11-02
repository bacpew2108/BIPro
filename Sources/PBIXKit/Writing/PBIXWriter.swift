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
    }

    static let metadataPath = "metadata.sqlitedb"

    /// Builds the new `.pbix` bytes in memory and verifies them. With `rebuildModel`, the DataModel
    /// goes through the ABF rebuild and XPress9 recompression even when nothing in it changed
    /// (the test path used by gate W1).
    public static func build(source: URL, changes: PBIXChanges, rebuildModel: Bool = false) throws -> Result {
        let archive = try ZipArchive(url: source)
        for path in changes.reportParts.keys.sorted() where archive.entry(path) == nil {
            throw WriteError.invalid("\(path) is not a member of \(source.lastPathComponent)")
        }
        let needsModel = rebuildModel || !changes.measures.isEmpty
        let model = needsModel ? try rebuiltDataModel(archive: archive, measures: changes.measures) : nil

        var members: [(path: String, source: ZipWriter.Source)] = []
        for entry in archive.entries {
            if entry.path == "DataModel", let model {
                // The DataModel member is stored (method 0) in every Power BI file; keep it so.
                members.append((path: entry.path, source: .bytes(model, method: 0)))
            } else if let part = changes.reportParts[entry.path] {
                members.append((path: entry.path, source: .bytes(part, method: 8)))
            } else {
                members.append((path: entry.path, source: .rawCopy(archive, entry)))
            }
        }
        let data = try ZipWriter.write(members, modified: nil)
        try verify(data, changes: changes)
        return Result(data: data, tier: changes.tier)
    }

    /// Builds, verifies and writes the file. The first save keeps a `<name>.pbix.bak` copy of the
    /// previous file. The write goes through a temporary file in the same folder and is swapped
    /// in only after it reopens cleanly.
    @discardableResult
    public static func save(source: URL, to destination: URL, changes: PBIXChanges, rebuildModel: Bool = false) throws -> SaveTier {
        let result = try build(source: source, changes: changes, rebuildModel: rebuildModel)
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try result.data.write(to: temp)
        do {
            _ = try PBIXFile(url: temp)
        } catch {
            try? fm.removeItem(at: temp)
            throw WriteError.verificationFailed("\(error)")
        }
        if fm.fileExists(atPath: destination.path) {
            let backup = destination.appendingPathExtension("bak")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: destination, to: backup) }
            _ = try fm.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
        return result.tier
    }

    /// T2: adds measures to metadata.sqlitedb, rebuilds the ABF and recompresses the DataModel.
    static func rebuiltDataModel(archive: ZipArchive, measures: [NewMeasure]) throws -> Data {
        guard let entry = archive.entry("DataModel") else { throw ZipArchive.Error.missingEntry("DataModel") }
        let stream = try archive.storedSlice(entry) ?? archive.read(entry)
        let (abfBytes, _) = try DataModelStream.decompress(stream)
        let abf = try ABFBackup(data: abfBytes)
        guard let metadataFile = abf.file(named: metadataPath) else {
            throw WriteError.invalid("the data model has no \(metadataPath)")
        }
        var metadata = try MetadataWriter(sqlite: try abf.contents(of: metadataFile))
        for measure in measures {
            try metadata.addMeasure(measure)
        }
        let newABF = try ABFWriter.rebuild(abf, replacing: [ABFPayload(path: metadataFile.path, data: try metadata.serialize())])
        return try DataModelStream.compress(abf: newABF)
    }

    /// Reads the written bytes back and checks every change.
    static func verify(_ data: Data, changes: PBIXChanges) throws {
        let pbix: PBIXFile
        do {
            pbix = try PBIXFile(data: data)
        } catch {
            throw WriteError.verificationFailed("cannot reopen the new file: \(error)")
        }
        for (path, expected) in changes.reportParts {
            let actual = try pbix.archive.read(path)
            guard actual == expected else { throw WriteError.verificationFailed("\(path) does not read back") }
        }
        guard !changes.measures.isEmpty else { return }
        let (abf, _) = try pbix.loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: metadataPath))
        for measure in changes.measures {
            let found = model.measures.contains {
                $0.tableName == measure.table && $0.name == measure.name && $0.expression == measure.expression
            }
            guard found else { throw WriteError.verificationFailed("measure \(measure.name) is missing after save") }
        }
    }
}
