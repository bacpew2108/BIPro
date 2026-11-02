import CXPress9
import Foundation

extension DataModelStream {
    /// Uncompressed bytes per XPress9 chunk, as observed in the sample files.
    public static let defaultChunkSize = 2_097_152

    /// The 102-byte stream signature: UTF-16LE of `singleThreadSignature`, then a NUL code unit.
    static let singleThreadSignatureBytes: Data = {
        var bytes = singleThreadSignature.data(using: .utf16LittleEndian) ?? Data()
        bytes.append(contentsOf: [0, 0])
        return bytes
    }()

    /// Compresses an ABF backup into a single-threaded DataModel stream, the layout
    /// Power BI writes: the 102-byte signature, then `[u32 LE uncompressed][u32 LE compressed][payload]`
    /// per chunk. All chunks share one XPress9 history window. Only the last chunk may be smaller
    /// than `chunkSize`, and nothing follows it.
    public static func compress(abf: Data, chunkSize: Int = DataModelStream.defaultChunkSize) throws -> Data {
        try compressChunks(abf: abf, chunkSize: chunkSize, encoderPerChunk: false)
    }

    /// Same layout as `compress(abf:chunkSize:)`. With `encoderPerChunk`, each chunk gets a fresh
    /// encoder, so no chunk refers back to an earlier one. Used to compare sizes, not for writing.
    static func compressChunks(abf: Data, chunkSize: Int, encoderPerChunk: Bool) throws -> Data {
        guard !abf.isEmpty else { throw WriteError.invalid("ABF backup is empty") }
        guard chunkSize > 0, chunkSize <= Int(UInt32.max) else {
            throw WriteError.invalid("chunk size \(chunkSize) is out of range")
        }

        let total = abf.count
        var out = Data()
        out.reserveCapacity(singleThreadSignatureBytes.count + total)
        out.append(singleThreadSignatureBytes)

        // Output room for the worst case: incompressible input grows slightly, so allow 1/8 more plus a margin.
        let widest = min(chunkSize, total)
        var buffer = [UInt8](repeating: 0, count: widest + widest / 8 + 4096)
        var message = [CChar](repeating: 0, count: 256)

        var shared: OpaquePointer? = nil
        if !encoderPerChunk {
            guard let encoder = cxpress9_encoder_create() else {
                throw WriteError.invalid("could not create XPress9 encoder")
            }
            shared = encoder
        }
        defer { if let shared { cxpress9_encoder_destroy(shared) } }

        try abf.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let input = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            try buffer.withUnsafeMutableBufferPointer { (dest: inout UnsafeMutableBufferPointer<UInt8>) in
                var offset = 0
                var index = 0
                while offset < total {
                    let size = min(chunkSize, total - offset)

                    var owned: OpaquePointer? = nil
                    let encoder: OpaquePointer
                    if let shared {
                        encoder = shared
                    } else {
                        guard let fresh = cxpress9_encoder_create() else {
                            throw WriteError.invalid("could not create XPress9 encoder for chunk \(index)")
                        }
                        owned = fresh
                        encoder = fresh
                    }
                    defer { if let owned { cxpress9_encoder_destroy(owned) } }

                    let written = cxpress9_encode_chunk(
                        encoder,
                        input + offset, UInt32(size),
                        dest.baseAddress!, UInt32(dest.count),
                        &message, UInt32(message.count))
                    if written <= 0 {
                        let text = String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        throw WriteError.invalid("XPress9 encode of chunk \(index) failed: \(text)")
                    }

                    appendU32LE(UInt32(size), to: &out)
                    appendU32LE(UInt32(written), to: &out)
                    out.append(dest.baseAddress!, count: Int(written))

                    offset += size
                    index += 1
                }
            }
        }
        return out
    }
}

private func appendU32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
}
