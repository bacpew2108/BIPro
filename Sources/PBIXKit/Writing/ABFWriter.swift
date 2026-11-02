import Foundation

/// Rebuilds an ABF backup with payloads replaced or added. Layout is described in `ABFBackup`.
///
/// Output: a 4 KiB header page, then the payloads back to back from offset 4096 with no
/// padding between them (LOG stays last), zero padding up to the next 4 KiB boundary, the
/// virtual directory, and zero padding to a 4 KiB multiple. Unchanged payloads, the header
/// signature, and the header, directory and log text are reused, so a rebuild with no
/// changes returns `source.data` byte for byte.
///
/// Timestamps: a replaced file gets `LastWriteTime` = now in the directory and the log; its
/// `CreatedTimestamp` and `Access` are kept. A new file gets now for all three. The LOG gets
/// a new `LastWriteTime` when its text changes. Files that are not changed keep their times.
public enum ABFWriter {
    static let pageSize = 4096

    public static func rebuild(_ source: ABFBackup, replacing: [ABFPayload] = [], adding: [ABFPayload] = []) throws -> Data {
        guard let logEntry = source.virtualEntries.last else {
            throw WriteError.invalid("the backup's virtual directory cannot be rewritten")
        }

        var seen = Set<String>()
        for payload in replacing + adding {
            guard !payload.data.isEmpty else { throw WriteError.invalid("empty payload for \(payload.path)") }
            guard seen.insert(payload.path).inserted else {
                throw WriteError.invalid("\(payload.path) appears more than once")
            }
        }

        let files = Dictionary(source.files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var replacementByStorage: [String: Data] = [:]
        for payload in replacing {
            guard let file = files[payload.path] else {
                throw WriteError.invalid("no file named \(payload.path) in the backup")
            }
            // Identical bytes are not a change: the file keeps its size, time and place.
            guard payload.data != source.data[file.offset..<(file.offset + file.size)] else { continue }
            replacementByStorage[file.storagePath] = payload.data
        }
        for payload in adding {
            guard files[payload.path] == nil else {
                throw WriteError.invalid("\(payload.path) already exists in the backup; use replacing")
            }
            guard !payload.path.hasPrefix("\\") else { throw WriteError.invalid("path must be relative: \(payload.path)") }
        }

        let changed = !replacementByStorage.isEmpty || !adding.isEmpty
        if changed && source.header.errorCode {
            throw WriteError.invalid("a backup with an error-code trailer cannot be rewritten")
        }

        let stamp = fileTime(Date())
        var used = Set(source.virtualEntries.map(\.storagePath))
        var added: [(storage: String, path: String, data: Data)] = []
        for payload in adding {
            added.append((newStorageName(avoiding: &used), payload.path, payload.data))
        }

        // The log refers to sizes and times of the files, never to its own size or offset,
        // so one pass over the log text is enough.
        var log = source.logXML
        for (storage, data) in replacementByStorage.sorted(by: { $0.key < $1.key }) {
            log = try updateLogEntry(log, storagePath: storage, size: data.count, lastWrite: stamp)
        }
        for item in added {
            log = try appendLogEntry(log, databasePath: source.databasePersistPath, path: item.path,
                                     storagePath: item.storage, size: item.data.count, lastWrite: stamp)
        }

        // Payloads, in stored order, with new offsets. Offsets are assigned as we go.
        var position = pageSize
        func place(_ size: Int) -> Int {
            let offset = position
            position += size
            return offset
        }
        var payloads: [Data] = []
        var directory: [String] = []

        for entry in source.virtualEntries.dropLast() {
            var payload = source.data[entry.offset..<(entry.offset + entry.size)]
            var xml = entry.xml
            if let replacement = replacementByStorage[entry.storagePath] {
                payload = replacement
                xml = try setTag(xml, "LastWriteTime", stamp)
            }
            let offset = place(payload.count)
            directory.append(try relocate(xml, from: entry, size: payload.count, offset: offset))
            payloads.append(payload)
        }
        for item in added {
            let offset = place(item.data.count)
            directory.append("<BackupFile><Path>\(item.storage)</Path><Size>\(item.data.count)</Size>"
                + "<m_cbOffsetHeader>\(offset)</m_cbOffsetHeader><Delete>false</Delete>"
                + "<CreatedTimestamp>\(stamp)</CreatedTimestamp><Access>\(stamp)</Access>"
                + "<LastWriteTime>\(stamp)</LastWriteTime></BackupFile>")
            payloads.append(item.data)
        }

        // The LOG is always last, after any added payloads.
        let logPayload = changed ? utf16LEWithBOM(log) : source.data[logEntry.offset..<(logEntry.offset + logEntry.size)]
        var logXML = logEntry.xml
        if changed { logXML = try setTag(logXML, "LastWriteTime", stamp) }
        directory.append(try relocate(logXML, from: logEntry, size: logPayload.count, offset: place(logPayload.count)))
        payloads.append(logPayload)

        let vdOffset = align(position)
        let vd = Data((source.virtualDirectoryOpen + directory.joined() + source.virtualDirectoryClose).utf8)

        var header = source.headerXML
        header = try setTag(header, "m_cbOffsetHeader", String(vdOffset))
        header = try setTag(header, "DataSize", String(vd.count))
        header = try setTag(header, "Files", String(directory.count))

        var page = Data(source.data.prefix(72))
        for unit in header.utf16 {
            page.append(UInt8(truncatingIfNeeded: unit))
            page.append(UInt8(truncatingIfNeeded: unit >> 8))
        }
        guard page.count <= pageSize else { throw WriteError.invalid("header XML does not fit in one page") }
        page.append(contentsOf: repeatElement(UInt8(0), count: pageSize - page.count))

        var out = Data()
        out.reserveCapacity(vdOffset + vd.count + pageSize)
        out.append(page)
        for payload in payloads { out.append(payload) }
        out.append(contentsOf: repeatElement(UInt8(0), count: vdOffset - position))
        out.append(vd)
        out.append(contentsOf: repeatElement(UInt8(0), count: align(out.count) - out.count))
        return out
    }

    // MARK: - Virtual directory

    /// Updates `Size` and `m_cbOffsetHeader` of one entry when they differ from the source.
    static func relocate(_ xml: String, from entry: ABFBackup.VirtualEntry, size: Int, offset: Int) throws -> String {
        var out = xml
        if entry.size != size { out = try setTag(out, "Size", String(size)) }
        if entry.offset != offset { out = try setTag(out, "m_cbOffsetHeader", String(offset)) }
        return out
    }

    /// Replaces the text of the first `<tag>` element in `xml`.
    static func setTag(_ xml: String, _ tag: String, _ value: String) throws -> String {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else {
            throw WriteError.invalid("ABF XML has no <\(tag)> element")
        }
        var out = xml
        out.replaceSubrange(open.upperBound..<close.lowerBound, with: value)
        return out
    }

    // MARK: - Backup log

    /// Sets `Size` and `LastWriteTime` of the log entry whose `StoragePath` is `storagePath`.
    static func updateLogEntry(_ log: String, storagePath: String, size: Int, lastWrite: String) throws -> String {
        let marker = "<StoragePath>\(storagePath)</StoragePath>"
        guard let found = log.range(of: marker) else {
            throw WriteError.invalid("the backup log has no entry for \(storagePath)")
        }
        guard log.range(of: marker, range: found.upperBound..<log.endIndex) == nil else {
            throw WriteError.invalid("the backup log lists \(storagePath) twice")
        }
        guard let start = log.range(of: "<BackupFile>", options: .backwards, range: log.startIndex..<found.lowerBound),
              let end = log.range(of: "</BackupFile>", range: found.upperBound..<log.endIndex) else {
            throw WriteError.invalid("malformed backup log entry for \(storagePath)")
        }
        let element = String(log[start.lowerBound..<end.upperBound])
        let edited = try setTag(try setTag(element, "Size", String(size)), "LastWriteTime", lastWrite)
        var out = log
        out.replaceSubrange(start.lowerBound..<end.upperBound, with: edited)
        return out
    }

    /// Appends a log entry for a new database file at the end of the database file group
    /// (the second `FileGroup`, as `ABFBackup` reads it).
    static func appendLogEntry(_ log: String, databasePath: String, path: String, storagePath: String,
                               size: Int, lastWrite: String) throws -> String {
        guard let firstGroup = log.range(of: "<FileGroup>"),
              let databaseGroup = log.range(of: "<FileGroup>", range: firstGroup.upperBound..<log.endIndex),
              let listEnd = log.range(of: "</FileList>", range: databaseGroup.upperBound..<log.endIndex) else {
            throw WriteError.invalid("the backup log has no database file group")
        }
        let fullPath = xmlEscape(databasePath + "\\" + path)
        let entry = "<BackupFile><Path>\(fullPath)</Path><StoragePath>\(storagePath)</StoragePath>"
            + "<LastWriteTime>\(lastWrite)</LastWriteTime><Size>\(size)</Size></BackupFile>"
        var out = log
        out.insert(contentsOf: entry, at: listEnd.lowerBound)
        return out
    }

    // MARK: - Helpers

    /// A new storage name: 20 upper-case hex digits, not used by any entry or log item.
    static func newStorageName(avoiding used: inout Set<String>) -> String {
        let digits = Array("0123456789ABCDEF")
        while true {
            let name = String((0..<20).map { _ in digits[Int.random(in: 0..<16)] })
            if used.insert(name).inserted { return name }
        }
    }

    /// FILETIME: 100 ns ticks since 1601-01-01 UTC, as decimal text.
    static func fileTime(_ date: Date) -> String {
        let ticks = ((date.timeIntervalSince1970 + 11_644_473_600) * 10_000_000).rounded(.down)
        return String(Int64(ticks))
    }

    static func align(_ n: Int) -> Int {
        (n + pageSize - 1) / pageSize * pageSize
    }

    static func utf16LEWithBOM(_ text: String) -> Data {
        var data = Data([0xFF, 0xFE])
        data.reserveCapacity(2 + text.utf16.count * 2)
        for unit in text.utf16 {
            data.append(UInt8(truncatingIfNeeded: unit))
            data.append(UInt8(truncatingIfNeeded: unit >> 8))
        }
        return data
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
