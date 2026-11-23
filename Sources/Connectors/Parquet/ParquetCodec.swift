// Phase F, T089 (US7): giải nén trang Parquet (UNCOMPRESSED, SNAPPY tự viết theo đặc tả định dạng Snappy, GZIP qua framework Compression
// của Apple) và giải mã RLE/bit-packed hybrid (mức định nghĩa, chỉ số từ điển, boolean RLE). Codec khác báo "chưa hỗ trợ" kèm tên.

import PBIXKit
import Compression
import Foundation

enum ParquetCodec {
    static func name(_ codec: Int) -> String {
        ["UNCOMPRESSED", "SNAPPY", "GZIP", "LZO", "BROTLI", "LZ4", "ZSTD", "LZ4_RAW"].indices.contains(codec)
            ? ["UNCOMPRESSED", "SNAPPY", "GZIP", "LZO", "BROTLI", "LZ4", "ZSTD", "LZ4_RAW"][codec] : "codec \(codec)"
    }

    static func decompress(_ input: ArraySlice<UInt8>, codec: Int, size: Int) throws -> [UInt8] {
        switch codec {
        case 0: return Array(input)
        case 1: return try snappy(input, size: size)
        case 2: return try gzip(input, size: size)
        default: throw SourceError.unsupported(lt("Parquet nén \(name(codec))", "Parquet compressed with \(name(codec))"))
        }
    }

    /// Snappy dạng khối: varint độ dài gốc, rồi các phần tử literal/copy.
    static func snappy(_ input: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        let bad = SourceError.unreadable(lt("Tệp Parquet hỏng: khối Snappy sai", "Corrupt Parquet file: bad Snappy block"))
        var i = input.startIndex
        var length = 0, shift = 0
        while true {
            guard i < input.endIndex, shift < 35 else { throw bad }
            let b = input[i]; i += 1
            length |= Int(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
        }
        guard length == size else { throw bad }
        var out = [UInt8](repeating: 0, count: length)
        var o = 0
        try out.withUnsafeMutableBufferPointer { dst in
            while i < input.endIndex {
                let tag = input[i]; i += 1
                switch tag & 3 {
                case 0:
                    var n = Int(tag >> 2)
                    if n >= 60 {
                        let extra = n - 59
                        guard i + extra <= input.endIndex else { throw bad }
                        n = 0
                        for k in 0..<extra { n |= Int(input[i + k]) << (8 * k) }
                        i += extra
                    }
                    n += 1
                    guard i + n <= input.endIndex, o + n <= length else { throw bad }
                    for k in 0..<n { dst[o + k] = input[i + k] }
                    i += n; o += n
                default:
                    let n: Int, offset: Int
                    switch tag & 3 {
                    case 1:
                        guard i < input.endIndex else { throw bad }
                        n = Int((tag >> 2) & 7) + 4
                        offset = Int(tag >> 5) << 8 | Int(input[i]); i += 1
                    case 2:
                        guard i + 2 <= input.endIndex else { throw bad }
                        n = Int(tag >> 2) + 1
                        offset = Int(input[i]) | Int(input[i + 1]) << 8; i += 2
                    default:
                        guard i + 4 <= input.endIndex else { throw bad }
                        n = Int(tag >> 2) + 1
                        offset = Int(input[i]) | Int(input[i + 1]) << 8 | Int(input[i + 2]) << 16 | Int(input[i + 3]) << 24; i += 4
                    }
                    guard offset > 0, offset <= o, o + n <= length else { throw bad }
                    for k in 0..<n { dst[o + k] = dst[o - offset + k] }   // chép từng byte: vùng nguồn có thể chồng vùng đích
                    o += n
                }
            }
        }
        guard o == length else { throw bad }
        return out
    }

    /// GZIP (RFC 1952): bỏ phần đầu (và các trường tuỳ chọn theo cờ), phần thân là DEFLATE thô (`COMPRESSION_ZLIB`).
    static func gzip(_ input: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        let bad = SourceError.unreadable(lt("Tệp Parquet hỏng: khối GZIP sai", "Corrupt Parquet file: bad GZIP block"))
        let b = Array(input)
        guard b.count >= 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { throw bad }
        let flags = b[3]
        var p = 10
        if flags & 4 != 0 { guard p + 2 <= b.count else { throw bad }; p += 2 + (Int(b[p]) | Int(b[p + 1]) << 8) }
        if flags & 8 != 0 { while p < b.count, b[p] != 0 { p += 1 }; p += 1 }
        if flags & 16 != 0 { while p < b.count, b[p] != 0 { p += 1 }; p += 1 }
        if flags & 2 != 0 { p += 2 }
        guard p < b.count - 8 else { throw bad }
        if size == 0 { return [] }
        var out = [UInt8](repeating: 0, count: size)
        let written = out.withUnsafeMutableBufferPointer { dst in
            b.withUnsafeBufferPointer { src in
                compression_decode_buffer(dst.baseAddress!, size, src.baseAddress! + p, b.count - 8 - p, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw bad }
        return out
    }
}

/// Đọc dần một vùng byte của trang đã giải nén.
struct ParquetBytes {
    let bytes: [UInt8]
    var index: Int
    let end: Int

    init(_ bytes: [UInt8], from start: Int = 0, to end: Int? = nil) {
        self.bytes = bytes
        index = start
        self.end = end ?? bytes.count
    }

    static let truncated = SourceError.unreadable(lt("Tệp Parquet hỏng: trang dữ liệu bị cắt", "Corrupt Parquet file: truncated data page"))

    mutating func uleb() throws -> Int {
        var result = 0, shift = 0
        while true {
            guard index < end, shift < 63 else { throw Self.truncated }
            let b = bytes[index]; index += 1
            result |= Int(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
        }
    }

    mutating func u32() throws -> Int {
        guard index + 4 <= end else { throw Self.truncated }
        defer { index += 4 }
        return Int(bytes[index]) | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2]) << 16 | Int(bytes[index + 3]) << 24
    }

    /// RLE/bit-packed hybrid: `count` số rộng `bitWidth` bit, đọc trong [index, end).
    mutating func hybrid(bitWidth: Int, count: Int) throws -> [Int32] {
        var out = [Int32]()
        out.reserveCapacity(count)
        if bitWidth == 0 { return [Int32](repeating: 0, count: count) }
        guard bitWidth <= 32 else { throw Self.truncated }
        let byteWidth = (bitWidth + 7) / 8
        while out.count < count {
            let header = try uleb()
            if header & 1 == 0 {
                let run = header >> 1
                guard index + byteWidth <= end else { throw Self.truncated }
                var v: UInt32 = 0
                for k in 0..<byteWidth { v |= UInt32(bytes[index + k]) << (8 * UInt32(k)) }
                index += byteWidth
                let n = min(run, count - out.count)
                out.append(contentsOf: repeatElement(Int32(bitPattern: v), count: n))
            } else {
                let values = (header >> 1) * 8
                let byteCount = (header >> 1) * bitWidth
                guard index + byteCount <= end else { throw Self.truncated }
                let mask: UInt64 = bitWidth == 32 ? 0xFFFF_FFFF : (1 << UInt64(bitWidth)) - 1
                var acc: UInt64 = 0, bits = 0, p = index
                for _ in 0..<values {
                    while bits < bitWidth { acc |= UInt64(bytes[p]) << UInt64(bits); p += 1; bits += 8 }
                    if out.count < count { out.append(Int32(bitPattern: UInt32(acc & mask))) }
                    acc >>= UInt64(bitWidth); bits -= bitWidth
                }
                index += byteCount
            }
        }
        return out
    }
}
