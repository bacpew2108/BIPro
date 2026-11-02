import Compression
import Foundation

/// Minimal ZIP32 writer for `.pbix` containers.
///
/// Members are written in the order given. Unchanged members are copied with their
/// compressed payload (`.rawCopy`), so their bytes, CRC and method are identical to the source.
/// Only ZIP32 is produced: more than 65535 members, or any offset or size above 4 GiB, throws.
public enum ZipWriter {
    public enum Source {
        /// New bytes, compressed with `method` (0 = stored, 8 = deflate).
        case bytes(Data, method: UInt16)
        /// The member is copied as stored in another archive, with its compressed payload.
        case rawCopy(ZipArchive, ZipArchive.Entry)
    }

    /// Writes members in the given order, stamping every member with the current local time.
    public static func write(_ members: [(path: String, source: Source)]) throws -> Data {
        try write(members, modified: nil)
    }

    /// Writes members in the given order. `modified` (local time) sets the DOS timestamp of
    /// every member; nil uses the current time. DOS time has 2 s resolution and starts in 1980.
    public static func write(_ members: [(path: String, source: Source)], modified: Date?) throws -> Data {
        guard members.count <= 0xFFFF else {
            throw WriteError.invalid("ZIP32 allows at most 65535 members (got \(members.count))")
        }
        let stamp = dosTimestamp(modified ?? Date())

        var seen = Set<String>()
        var prepared: [PreparedMember] = []
        prepared.reserveCapacity(members.count)
        for member in members {
            guard !member.path.isEmpty else { throw WriteError.invalid("empty member path") }
            guard seen.insert(member.path).inserted else { throw WriteError.invalid("duplicate member \(member.path)") }
            prepared.append(try prepare(member.path, member.source))
        }

        var out = Data()
        var localOffsets: [UInt32] = []
        localOffsets.reserveCapacity(prepared.count)
        for member in prepared {
            let offset = out.count
            guard offset <= Int(UInt32.max) else { throw WriteError.invalid("archive exceeds 4 GiB (ZIP64 not supported)") }
            localOffsets.append(UInt32(offset))
            out.appendLE32(0x0403_4b50)
            out.appendLE16(member.versionNeeded)
            out.appendLE16(member.flags)
            out.appendLE16(member.method)
            out.appendLE16(stamp.time)
            out.appendLE16(stamp.date)
            out.appendLE32(member.crc32)
            out.appendLE32(UInt32(member.payload.count))
            out.appendLE32(UInt32(member.uncompressedSize))
            out.appendLE16(UInt16(member.name.count))
            out.appendLE16(0) // extra length
            out.append(contentsOf: member.name)
            out.append(member.payload)
        }

        let directoryOffset = out.count
        guard directoryOffset <= Int(UInt32.max) else { throw WriteError.invalid("archive exceeds 4 GiB (ZIP64 not supported)") }
        for (member, localOffset) in zip(prepared, localOffsets) {
            out.appendLE32(0x0201_4b50)
            out.appendLE16(0x002D) // version made by: 4.5, host 0 (MS-DOS), as Power BI writes
            out.appendLE16(member.versionNeeded)
            out.appendLE16(member.flags)
            out.appendLE16(member.method)
            out.appendLE16(stamp.time)
            out.appendLE16(stamp.date)
            out.appendLE32(member.crc32)
            out.appendLE32(UInt32(member.payload.count))
            out.appendLE32(UInt32(member.uncompressedSize))
            out.appendLE16(UInt16(member.name.count))
            out.appendLE16(0) // extra length
            out.appendLE16(0) // comment length
            out.appendLE16(0) // disk number start
            out.appendLE16(0) // internal attributes
            out.appendLE32(0) // external attributes
            out.appendLE32(localOffset)
            out.append(contentsOf: member.name)
        }
        let directorySize = out.count - directoryOffset
        guard directorySize <= Int(UInt32.max) else { throw WriteError.invalid("central directory too large") }

        // End of central directory record. No archive comment.
        out.appendLE32(0x0605_4b50)
        out.appendLE16(0)
        out.appendLE16(0)
        out.appendLE16(UInt16(prepared.count))
        out.appendLE16(UInt16(prepared.count))
        out.appendLE32(UInt32(directorySize))
        out.appendLE32(UInt32(directoryOffset))
        out.appendLE16(0)
        return out
    }

    // MARK: - Members

    private struct PreparedMember {
        let name: Data
        let method: UInt16
        let flags: UInt16
        let versionNeeded: UInt16
        let crc32: UInt32
        let uncompressedSize: Int
        let payload: Data
    }

    private static func prepare(_ path: String, _ source: Source) throws -> PreparedMember {
        let name = Data(path.utf8)
        guard name.count <= 0xFFFF else { throw WriteError.invalid("member name too long: \(path)") }
        // Bit 11 marks UTF-8 names. ASCII names keep flags 0, as Power BI writes them.
        let flags: UInt16 = path.utf8.allSatisfy { $0 < 0x80 } ? 0 : 0x0800
        func checkSize(_ value: Int) throws {
            guard value <= Int(UInt32.max) else { throw WriteError.invalid("member too large for ZIP32: \(path)") }
        }

        switch source {
        case .bytes(let data, let method):
            try checkSize(data.count)
            let payload: Data
            switch method {
            case 0: payload = data
            case 8: payload = try deflate(data, path: path)
            default: throw WriteError.invalid("unsupported method \(method) for \(path)")
            }
            return PreparedMember(name: name, method: method, flags: flags,
                                  versionNeeded: method == 8 ? 20 : 10,
                                  crc32: ZipCRC32.checksum(data), uncompressedSize: data.count,
                                  payload: payload)

        case .rawCopy(let archive, let entry):
            guard entry.method == 0 || entry.method == 8 else {
                throw WriteError.invalid("unsupported method \(entry.method) for \(path)")
            }
            let payload = try archive.rawPayload(of: entry)
            guard payload.count == entry.compressedSize else {
                throw WriteError.invalid("compressed payload size mismatch for \(path)")
            }
            try checkSize(payload.count)
            try checkSize(entry.uncompressedSize)
            return PreparedMember(name: name, method: entry.method, flags: flags,
                                  versionNeeded: entry.method == 8 ? 20 : 10,
                                  crc32: entry.crc32, uncompressedSize: entry.uncompressedSize,
                                  payload: payload)
        }
    }

    /// Raw DEFLATE (RFC 1951), the form ZIP stores. `COMPRESSION_ZLIB` in Apple's
    /// Compression framework is the same raw stream that `ZipArchive` inflates.
    private static func deflate(_ input: Data, path: String) throws -> Data {
        // Raw DEFLATE of zero bytes: one final fixed-Huffman block with no symbols.
        if input.isEmpty { return Data([0x03, 0x00]) }
        let capacity = input.count + input.count / 8 + 256
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw WriteError.invalid("deflate failed for \(path)") }
        output.removeSubrange(written...)
        return output
    }

    // MARK: - DOS time

    /// DOS date and time for `date` in the local time zone (Gregorian calendar).
    /// Values before 1980-01-01 or after 2107-12-31 are clamped.
    static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var year = parts.year ?? 1980
        var month = parts.month ?? 1
        var day = parts.day ?? 1
        var hour = parts.hour ?? 0
        var minute = parts.minute ?? 0
        var second = parts.second ?? 0
        if year < 1980 { (year, month, day, hour, minute, second) = (1980, 1, 1, 0, 0, 0) }
        if year > 2107 { (year, month, day, hour, minute, second) = (2107, 12, 31, 23, 59, 58) }
        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | (second / 2))
        return (dosTime, dosDate)
    }
}

/// CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320) as used by ZIP.
enum ZipCRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt32 in
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in raw {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
            return ~crc
        }
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE32(_ value: UInt32) {
        appendLE16(UInt16(value & 0xFFFF))
        appendLE16(UInt16(value >> 16))
    }
}
