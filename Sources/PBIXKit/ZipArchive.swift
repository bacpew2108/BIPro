import Compression
import Foundation

/// Minimal read-only ZIP reader for `.pbix` containers.
///
/// Supports STORED and DEFLATE members, which is everything Power BI writes.
/// The archive is memory-mapped so the large STORED `DataModel` member can be
/// read in place without copying.
public struct ZipArchive: Sendable {
    public struct Entry: Sendable, Hashable {
        public let path: String
        public let method: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let crc32: UInt32
        let localHeaderOffset: Int
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case notZip
        case malformed(String)
        case unsupportedMethod(UInt16, String)
        case missingEntry(String)
        case inflateFailed(String)

        public var description: String {
            switch self {
            case .notZip: "not a ZIP archive (no end-of-central-directory record)"
            case .malformed(let why): "malformed ZIP: \(why)"
            case .unsupportedMethod(let m, let p): "unsupported compression method \(m) for \(p)"
            case .missingEntry(let p): "no such entry: \(p)"
            case .inflateFailed(let p): "inflate failed for \(p)"
            }
        }
    }

    public let entries: [Entry]
    private let data: Data

    public init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    public func entry(_ path: String) -> Entry? {
        entries.first { $0.path == path }
    }

    /// Byte range of a member's payload inside the archive (compressed bytes).
    public func payloadRange(of entry: Entry) throws -> Range<Int> {
        let h = entry.localHeaderOffset
        guard data.u32(at: h) == 0x0403_4b50 else { throw Error.malformed("bad local header for \(entry.path)") }
        let nameLength = Int(data.u16(at: h + 26))
        let extraLength = Int(data.u16(at: h + 28))
        let start = h + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw Error.malformed("payload out of bounds for \(entry.path)") }
        return start..<(start + entry.compressedSize)
    }

    /// Zero-copy view of a STORED member, or nil if the member is compressed.
    public func storedSlice(_ entry: Entry) throws -> Data? {
        guard entry.method == 0 else { return nil }
        return data[try payloadRange(of: entry)]
    }

    /// The member's compressed payload exactly as stored in the archive (not inflated).
    public func rawPayload(of entry: Entry) throws -> Data {
        Data(data[try payloadRange(of: entry)])
    }

    public func read(_ path: String) throws -> Data {
        guard let entry = entry(path) else { throw Error.missingEntry(path) }
        return try read(entry)
    }

    public func read(_ entry: Entry) throws -> Data {
        let payload = data[try payloadRange(of: entry)]
        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            return try Self.inflate(payload, expectedSize: entry.uncompressedSize, path: entry.path)
        default:
            throw Error.unsupportedMethod(entry.method, entry.path)
        }
    }

    // MARK: - Parsing

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        // The EOCD record is at least 22 bytes and may be followed by a comment of up to 64 KiB.
        guard data.count >= 22 else { throw Error.notZip }
        let lowerBound = max(0, data.count - 22 - 0xFFFF)
        var eocd: Int?
        var i = data.count - 22
        while i >= lowerBound {
            if data.u32(at: i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard let eocd else { throw Error.notZip }

        var count = Int(data.u16(at: eocd + 10))
        var directoryOffset = Int(data.u32(at: eocd + 16))

        // ZIP64: the EOCD locator sits immediately before the EOCD record.
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF, eocd >= 20, data.u32(at: eocd - 20) == 0x0706_4b50 {
            let zip64 = Int(data.u64(at: eocd - 20 + 8))
            guard data.u32(at: zip64) == 0x0606_4b50 else { throw Error.malformed("bad ZIP64 EOCD") }
            count = Int(data.u64(at: zip64 + 32))
            directoryOffset = Int(data.u64(at: zip64 + 48))
        }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var p = directoryOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(at: p) == 0x0201_4b50 else {
                throw Error.malformed("bad central directory header at \(p)")
            }
            let flags = data.u16(at: p + 8)
            let method = data.u16(at: p + 10)
            let crc = data.u32(at: p + 16)
            var compressed = Int(data.u32(at: p + 20))
            var uncompressed = Int(data.u32(at: p + 24))
            let nameLength = Int(data.u16(at: p + 28))
            let extraLength = Int(data.u16(at: p + 30))
            let commentLength = Int(data.u16(at: p + 32))
            var localOffset = Int(data.u32(at: p + 42))
            let nameBytes = data[(p + 46)..<(p + 46 + nameLength)]
            // Bit 11 = UTF-8 names; Power BI always writes ASCII/UTF-8.
            let name = String(decoding: nameBytes, as: UTF8.self)
            _ = flags

            // ZIP64 extended information extra field.
            var e = p + 46 + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = data.u16(at: e)
                let size = Int(data.u16(at: e + 2))
                if id == 0x0001 {
                    var q = e + 4
                    if uncompressed == 0xFFFF_FFFF { uncompressed = Int(data.u64(at: q)); q += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = Int(data.u64(at: q)); q += 8 }
                    if localOffset == 0xFFFF_FFFF { localOffset = Int(data.u64(at: q)) }
                }
                e += 4 + size
            }

            entries.append(Entry(path: name, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, crc32: crc, localHeaderOffset: localOffset))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func inflate(_ input: Data, expectedSize: Int, path: String) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (inp: UnsafeRawBufferPointer) -> Int in
                // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what ZIP stores.
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          inp.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw Error.inflateFailed(path) }
        return output
    }
}

extension Data {
    @inline(__always) func u16(at offset: Int) -> UInt16 {
        let b = startIndex + offset
        return UInt16(self[b]) | UInt16(self[b + 1]) << 8
    }

    @inline(__always) func u32(at offset: Int) -> UInt32 {
        let b = startIndex + offset
        return UInt32(self[b]) | UInt32(self[b + 1]) << 8 | UInt32(self[b + 2]) << 16 | UInt32(self[b + 3]) << 24
    }

    @inline(__always) func u64(at offset: Int) -> UInt64 {
        UInt64(u32(at: offset)) | UInt64(u32(at: offset + 4)) << 32
    }

    /// Decodes UTF-16LE text, skipping a leading BOM if present.
    func utf16LEString() -> String {
        var body = self
        if body.count >= 2, body[body.startIndex] == 0xFF, body[body.startIndex + 1] == 0xFE {
            body = body.dropFirst(2)
        }
        return String(data: body, encoding: .utf16LittleEndian) ?? ""
    }
}
