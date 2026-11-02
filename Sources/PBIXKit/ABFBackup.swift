import Foundation

/// An Analysis Services backup (ABF), i.e. the decompressed `DataModel`.
///
/// Layout: a 72-byte stream storage signature, a one-page (4 KiB) UTF-16 XML
/// header, a virtual directory (XML) locating each stored file, and a backup
/// log (XML, the last virtual-directory file) mapping storage names to model
/// paths such as `metadata.sqlitedb` or `Fact_Loan (123).tbl\\...idf`.
public struct ABFBackup: Sendable {
    public struct File: Sendable, Hashable {
        /// Path relative to the database persist root, with `\` separators.
        public let path: String
        public let storagePath: String
        public let offset: Int
        public let size: Int
        public let sizeFromLog: Int

        public var fileName: String { path.split(separator: "\\").last.map(String.init) ?? path }
    }

    public struct Header: Sendable {
        public let backupRestoreSyncVersion: Int
        public let errorCode: Bool
        public let encrypted: Bool
        public let applyCompression: Bool
        public let virtualDirectoryOffset: Int
        public let virtualDirectorySize: Int
        public let fileCount: Int
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case malformed(String)
        case unsupported(String)
        case missingFile(String)

        public var description: String {
            switch self {
            case .malformed(let m): "malformed ABF: \(m)"
            case .unsupported(let m): "unsupported ABF: \(m)"
            case .missingFile(let f): "ABF has no file named \(f)"
            }
        }
    }

    /// One `<BackupFile>` entry of the virtual directory, kept verbatim so a rewrite can reuse it.
    public struct VirtualEntry: Sendable, Equatable {
        /// Storage name, e.g. `ADDITIONAL_LOG`, `PARTITIONS`, a 20-character hex name, or `LOG`.
        public let storagePath: String
        public let size: Int
        public let offset: Int
        /// The entry's `<BackupFile>...</BackupFile>` XML, byte for byte as stored.
        public let xml: String
    }

    public let data: Data
    public let header: Header
    public let files: [File]
    /// Header page XML (after the 72-byte signature) without NUL padding.
    public let headerXML: String
    /// Virtual directory entries in stored order. The last entry is the LOG.
    /// Empty when the directory layout is not one the writer can reproduce.
    public let virtualEntries: [VirtualEntry]
    /// Virtual directory XML before the first `<BackupFile>`, verbatim.
    public let virtualDirectoryOpen: String
    /// Virtual directory XML after the last `</BackupFile>`, verbatim.
    public let virtualDirectoryClose: String
    /// Decoded backup log (the LOG entry) without its byte-order mark.
    public let logXML: String
    /// `PersistLocationPath` of the database file group, without a trailing separator.
    public let databasePersistPath: String

    public init(data: Data) throws {
        self.data = data
        guard data.count > 0x1000 else { throw Error.malformed("shorter than one header page") }

        let headerXML = data[72..<0x1000].utf16LEString().trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        let h = try XMLElementView(string: headerXML)
        header = Header(
            backupRestoreSyncVersion: h.int("BackupRestoreSyncVersion") ?? 0,
            errorCode: h.bool("ErrorCode"),
            encrypted: h.bool("EncryptionFlag"),
            applyCompression: h.bool("ApplyCompression"),
            virtualDirectoryOffset: try h.require(int: "m_cbOffsetHeader"),
            virtualDirectorySize: try h.require(int: "DataSize"),
            fileCount: h.int("Files") ?? 0)
        if header.encrypted { throw Error.unsupported("encrypted backup") }
        // Per-file XPress8 compression only occurs in standalone .abf backups, not in .pbix.
        if header.applyCompression { throw Error.unsupported("per-file XPress8 compression") }

        let vdRange = header.virtualDirectoryOffset..<(header.virtualDirectoryOffset + header.virtualDirectorySize)
        guard vdRange.upperBound <= data.count else { throw Error.malformed("virtual directory out of bounds") }
        let virtualDirectory = try XMLDocument(data: Data(data[vdRange]))
        struct VirtualFile { let path: String; let size: Int; let offset: Int }
        let virtualFiles: [VirtualFile] = try virtualDirectory.nodes(forXPath: "//BackupFile").map { node in
            let e = XMLElementView(node)
            return VirtualFile(path: e.text("Path") ?? "", size: try e.require(int: "Size"), offset: try e.require(int: "m_cbOffsetHeader"))
        }
        guard let logFile = virtualFiles.last else { throw Error.malformed("empty virtual directory") }

        var logBytes = data[logFile.offset..<(logFile.offset + logFile.size)]
        if header.errorCode { logBytes = logBytes.dropLast(4) }
        let logText = String(data: logBytes, encoding: .utf16) ?? logBytes.utf16LEString()
        let log = try XMLElementView(string: logText)
        let groups = try log.node.nodes(forXPath: "FileGroups/FileGroup")
        guard groups.count > 1 else { throw Error.malformed("backup log has no database file group") }
        let persistPath = XMLElementView(groups[1]).text("PersistLocationPath") ?? ""
        let persistRoot = persistPath + "\\"

        // Verbatim directory entries for the writer. Only kept when the entries tile the text exactly.
        let vdText = Array(data[vdRange])
        var vdOpen = "", vdClose = "", entries: [VirtualEntry] = []
        if let split = Self.splitBackupFiles(vdText), split.elements.count == virtualFiles.count {
            vdOpen = split.open
            vdClose = split.close
            entries = zip(split.elements, virtualFiles).map {
                VirtualEntry(storagePath: $1.path, size: $1.size, offset: $1.offset, xml: $0)
            }
        }

        let byStoragePath = Dictionary(virtualFiles.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        var files: [File] = []
        for group in groups {
            for node in try group.nodes(forXPath: "FileList/BackupFile") {
                let e = XMLElementView(node)
                guard let storage = e.text("StoragePath"), let match = byStoragePath[storage] else { continue }
                var path = e.text("Path") ?? ""
                if path.hasPrefix(persistRoot) { path.removeFirst(persistRoot.count) }
                files.append(File(path: path, storagePath: storage, offset: match.offset,
                                  size: match.size, sizeFromLog: e.int("Size") ?? match.size))
            }
        }
        self.files = files
        self.headerXML = headerXML
        self.virtualEntries = entries
        self.virtualDirectoryOpen = vdOpen
        self.virtualDirectoryClose = vdClose
        self.logXML = logText
        self.databasePersistPath = persistPath
    }

    /// Splits the virtual directory bytes into the text before the first entry, each
    /// `<BackupFile>` element, and the text after the last one. Returns nil when any byte
    /// lies between elements in a way the split cannot reproduce.
    private static func splitBackupFiles(_ bytes: [UInt8]) -> (open: String, elements: [String], close: String)? {
        let openTag = Array("<BackupFile>".utf8)
        let closeTag = Array("</BackupFile>".utf8)
        guard let first = indexOf(openTag, in: bytes, from: 0) else { return nil }
        var elements: [String] = []
        var cursor = first
        while let start = indexOf(openTag, in: bytes, from: cursor) {
            guard start == cursor, let end = indexOf(closeTag, in: bytes, from: start) else { return nil }
            let stop = end + closeTag.count
            elements.append(String(decoding: bytes[start..<stop], as: UTF8.self))
            cursor = stop
        }
        return (String(decoding: bytes[0..<first], as: UTF8.self),
                elements,
                String(decoding: bytes[cursor...], as: UTF8.self))
    }

    private static func indexOf(_ pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard bytes.count >= pattern.count else { return nil }
        let last = bytes.count - pattern.count
        var i = start
        while i <= last {
            if bytes[i] == pattern[0], bytes[i..<(i + pattern.count)].elementsEqual(pattern) { return i }
            i += 1
        }
        return nil
    }

    public func file(named name: String) -> File? {
        files.first { $0.fileName == name }
    }

    public func contents(of file: File) -> Data {
        let length = header.errorCode ? file.size - 4 : file.size
        return data[file.offset..<(file.offset + length)]
    }

    public func contents(named name: String) throws -> Data {
        guard let file = file(named: name) else { throw Error.missingFile(name) }
        return contents(of: file)
    }
}

/// Small helper over Foundation's XMLNode for "child element text" lookups.
struct XMLElementView {
    let node: XMLNode

    init(_ node: XMLNode) { self.node = node }

    init(string: String) throws {
        let document = try XMLDocument(xmlString: string)
        guard let root = document.rootElement() else { throw ABFBackup.Error.malformed("empty XML") }
        node = root
    }

    func text(_ name: String) -> String? {
        (try? node.nodes(forXPath: name))?.first?.stringValue
    }

    func int(_ name: String) -> Int? { text(name).flatMap { Int($0) } }

    func bool(_ name: String) -> Bool { text(name) == "true" }

    func require(int name: String) throws -> Int {
        guard let value = int(name) else { throw ABFBackup.Error.malformed("missing <\(name)>") }
        return value
    }
}
