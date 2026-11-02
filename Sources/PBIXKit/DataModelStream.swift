import CXPress9
import Foundation

/// Decompresses the `DataModel` member of a `.pbix` into a raw ABF backup.
///
/// Layout (UTF-16LE signature, 102 bytes, then chunks):
/// - single-threaded: `[u32 uncompressed][u32 compressed][payload]...`, one XPress9
///   history window across all chunks.
/// - multi-threaded: five u64 fields (main chunks/thread, prefix chunks/thread,
///   prefix thread count, main thread count, chunk size), then prefix groups and
///   main groups; every group is an independent XPress9 stream.
/// - uncompressed: the ABF itself, starting with the stream storage signature.
public enum DataModelStream {
    public enum Compression: String, Sendable {
        case uncompressed
        case singleThreaded = "xpress9"
        case multiThreaded = "xpress9-multithreaded"
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case unknownSignature
        case truncated(Int)
        case decoderUnavailable
        case decode(chunk: Int, String)
        case sizeMismatch(chunk: Int, expected: Int, actual: Int)

        public var description: String {
            switch self {
            case .unknownSignature: "unknown DataModel signature"
            case .truncated(let at): "DataModel stream truncated at byte \(at)"
            case .decoderUnavailable: "could not create XPress9 decoder"
            case .decode(let c, let m): "XPress9 chunk \(c): \(m)"
            case .sizeMismatch(let c, let e, let a): "XPress9 chunk \(c): expected \(e) bytes, got \(a)"
            }
        }
    }

    static let signatureLength = 102
    static let singleThreadSignature = "This backup was created using XPress9 compression."
    static let multiThreadSignature = "This backup was created using multithreaded XPrs9."
    static let streamStorageSignature = "STREAM_STORAGE_SIGNATURE_)!@#$%^&*("

    public static func detect(_ stream: Data) -> Compression? {
        let head = stream.prefix(signatureLength)
        if head.prefix(72).utf16LEString().contains(streamStorageSignature) { return .uncompressed }
        let text = head.utf16LEString()
        if text.contains(singleThreadSignature) { return .singleThreaded }
        if text.contains(multiThreadSignature) { return .multiThreaded }
        return nil
    }

    struct Chunk {
        let uncompressedSize: Int
        let payload: Range<Int>
    }

    public static func decompress(_ stream: Data) throws -> (Data, Compression) {
        guard let kind = detect(stream) else { throw Error.unknownSignature }
        switch kind {
        case .uncompressed:
            return (Data(stream), kind)
        case .singleThreaded:
            var cursor = signatureLength
            let chunks = try readChunks(stream, cursor: &cursor, count: nil)
            return (try decode(groups: [chunks], from: stream), kind)
        case .multiThreaded:
            var cursor = signatureLength
            func next() throws -> Int {
                guard cursor + 8 <= stream.count else { throw Error.truncated(cursor) }
                defer { cursor += 8 }
                return Int(stream.u64(at: cursor))
            }
            let mainPerThread = try next()
            let prefixPerThread = try next()
            let prefixThreads = try next()
            let mainThreads = try next()
            _ = try next() // nominal chunk size
            var groups: [[Chunk]] = []
            for _ in 0..<prefixThreads where prefixPerThread > 0 {
                groups.append(try readChunks(stream, cursor: &cursor, count: prefixPerThread))
            }
            for _ in 0..<mainThreads where mainPerThread > 0 {
                groups.append(try readChunks(stream, cursor: &cursor, count: mainPerThread))
            }
            return (try decode(groups: groups, from: stream), kind)
        }
    }

    private static func readChunks(_ stream: Data, cursor: inout Int, count: Int?) throws -> [Chunk] {
        var chunks: [Chunk] = []
        while count.map({ chunks.count < $0 }) ?? (cursor < stream.count) {
            guard cursor + 8 <= stream.count else { throw Error.truncated(cursor) }
            let uncompressed = Int(stream.u32(at: cursor))
            let compressed = Int(stream.u32(at: cursor + 4))
            let start = cursor + 8
            guard start + compressed <= stream.count else { throw Error.truncated(start) }
            chunks.append(Chunk(uncompressedSize: uncompressed, payload: start..<(start + compressed)))
            cursor = start + compressed
        }
        return chunks
    }

    /// Decodes every group into one contiguous buffer. Groups are independent
    /// streams and run concurrently; chunks within a group run in order.
    private static func decode(groups: [[Chunk]], from stream: Data) throws -> Data {
        let sizes = groups.map { $0.reduce(0) { $0 + $1.uncompressedSize } }
        let groupOffsets = sizes.reduce(into: [0]) { $0.append($0.last! + $1) }
        let total = groupOffsets.last!

        var output = Data(count: total)
        let failure = FailureBox()
        output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            stream.withUnsafeBytes { (inp: UnsafeRawBufferPointer) in
                // Each group writes a disjoint slice of the output buffer.
                let buffers = SharedBuffers(input: inp.bindMemory(to: UInt8.self).baseAddress!,
                                            output: out.bindMemory(to: UInt8.self).baseAddress!)
                DispatchQueue.concurrentPerform(iterations: groups.count) { g in
                    guard let decoder = cxpress9_decoder_create() else {
                        failure.set(Error.decoderUnavailable); return
                    }
                    defer { cxpress9_decoder_destroy(decoder) }
                    var offset = groupOffsets[g]
                    var message = [CChar](repeating: 0, count: 256)
                    for (index, chunk) in groups[g].enumerated() {
                        if failure.isSet { return }
                        let written = cxpress9_decode_chunk(
                            decoder,
                            buffers.input + chunk.payload.lowerBound, UInt32(chunk.payload.count),
                            buffers.output + offset, UInt32(chunk.uncompressedSize),
                            &message, UInt32(message.count))
                        if written < 0 {
                            let text = String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                            failure.set(Error.decode(chunk: index, text)); return
                        }
                        if Int(written) != chunk.uncompressedSize {
                            failure.set(Error.sizeMismatch(chunk: index, expected: chunk.uncompressedSize, actual: Int(written)))
                            return
                        }
                        offset += chunk.uncompressedSize
                    }
                }
            }
        }
        if let error = failure.error { throw error }
        return output
    }
}

private struct SharedBuffers: @unchecked Sendable {
    let input: UnsafePointer<UInt8>
    let output: UnsafeMutablePointer<UInt8>
}

private final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Swift.Error?

    var isSet: Bool { lock.withLock { stored != nil } }
    var error: Swift.Error? { lock.withLock { stored } }

    func set(_ error: Swift.Error) {
        lock.withLock { if stored == nil { stored = error } }
    }
}
