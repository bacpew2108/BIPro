import Foundation

/// A `.pbix` container: OPC parts, report definition and the embedded data model.
public struct PBIXFile: Sendable {
    public enum ReportFormat: String, Sendable {
        /// Enhanced report format: `Report/definition/**` JSON files.
        case pbir
        /// Legacy single-file `Report/Layout` (UTF-16LE JSON).
        case legacyLayout
        case none
    }

    public let archive: ZipArchive

    public init(url: URL) throws {
        archive = try ZipArchive(url: url)
    }

    public init(data: Data) throws {
        archive = try ZipArchive(data: data)
    }

    /// The `Version` part, e.g. `1.32`.
    public var version: String? {
        (try? archive.read("Version"))?.utf16LEString()
    }

    public var reportFormat: ReportFormat {
        if archive.entry("Report/definition/report.json") != nil { return .pbir }
        if archive.entry("Report/Layout") != nil { return .legacyLayout }
        return .none
    }

    /// JSON parts stored as UTF-16LE (`Settings`, `Metadata`, `Report/Layout`).
    public func utf16Part(_ path: String) throws -> String {
        try archive.read(path).utf16LEString()
    }

    public var hasDataModel: Bool { archive.entry("DataModel") != nil }

    /// Decompresses the embedded model into an ABF backup.
    public func loadDataModel() throws -> (ABFBackup, DataModelStream.Compression) {
        guard let entry = archive.entry("DataModel") else { throw ZipArchive.Error.missingEntry("DataModel") }
        let stream = try archive.storedSlice(entry) ?? archive.read(entry)
        let (abf, compression) = try DataModelStream.decompress(stream)
        return (try ABFBackup(data: abf), compression)
    }
}
