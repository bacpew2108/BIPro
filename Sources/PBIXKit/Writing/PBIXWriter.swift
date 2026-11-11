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
    static let securityBindingsPath = "SecurityBindings"
    static let contentTypesPath = "[Content_Types].xml"

    /// Builds the new `.pbix` bytes in memory and verifies them. With `rebuildModel`, the DataModel
    /// goes through the ABF rebuild and XPress9 recompression even when nothing in it changed
    /// (the test path used by gate W1).
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
        let needsModel = rebuildModel || !changes.measures.isEmpty
        let model = needsModel ? try rebuiltDataModel(archive: archive, measures: changes.measures) : nil

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
        let data = try ZipWriter.write(members, modified: nil)
        try verify(data, changes: changes, source: archive)
        return Result(data: data, tier: changes.tier)
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

    /// Reads the written bytes back and checks every change. With the source archive it also checks that
    /// every member that was not touched is unchanged.
    static func verify(_ data: Data, changes: PBIXChanges, source: ZipArchive? = nil) throws {
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
            let isModelRebuilt = !changes.measures.isEmpty
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
