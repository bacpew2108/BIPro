import Foundation
import Testing
@testable import PBIXKit

/// Sample reports are the author's own files, read only. Tests that need one are disabled when it is absent.
private enum CompressSamples {
    static let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    static let tuan62 = downloads.appendingPathComponent("tuan6.2.pbix")
    static let nhom6 = downloads.appendingPathComponent("Nhom6_Dashboard.pbix")

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    static var hasTuan62: Bool { exists(tuan62) }
    static var hasNhom6: Bool { exists(nhom6) }
}

/// The DataModel member as stored in the .pbix ZIP (still XPress9-compressed).
private func storedDataModel(of url: URL) throws -> Data {
    let archive = try ZipArchive(url: url)
    guard let entry = archive.entry("DataModel") else { throw ZipArchive.Error.missingEntry("DataModel") }
    return Data(try archive.storedSlice(entry) ?? archive.read(entry))
}

private func u32LE(_ data: Data, at offset: Int) -> Int {
    let i = data.startIndex + offset
    return Int(data[i]) | Int(data[i + 1]) << 8 | Int(data[i + 2]) << 16 | Int(data[i + 3]) << 24
}

/// (uncompressed, compressed) size of every chunk after the 102-byte signature.
private func chunkTable(_ stream: Data) -> [(uncompressed: Int, compressed: Int)] {
    var table: [(uncompressed: Int, compressed: Int)] = []
    var cursor = DataModelStream.signatureLength
    while cursor < stream.count {
        let uncompressed = u32LE(stream, at: cursor)
        let compressed = u32LE(stream, at: cursor + 4)
        table.append((uncompressed, compressed))
        cursor += 8 + compressed
    }
    return table
}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

private func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let clock = ContinuousClock()
    var result: T?
    let duration = try clock.measure { result = try body() }
    return (result!, seconds(duration))
}

@Suite struct CompressTests {
    @Test func signatureIsUTF16LEWithNUL() {
        let signature = DataModelStream.singleThreadSignatureBytes
        #expect(signature.count == 102)
        #expect(signature.suffix(2) == Data([0, 0]))
        #expect(signature.prefix(4) == Data([0x54, 0x00, 0x68, 0x00]))
    }

    @Test func roundTripsRandomBytesAcrossChunks() throws {
        var generator = SystemRandomNumberGenerator()
        let abf = Data((0..<250_000).map { _ in UInt8.random(in: 0...255, using: &generator) })

        let stream = try DataModelStream.compress(abf: abf, chunkSize: 100_000)
        let (decoded, kind) = try DataModelStream.decompress(stream)

        #expect(kind == .singleThreaded)
        #expect(decoded == abf)
        // Three chunks: 100 000, 100 000, then a 50 000 byte tail with nothing after it.
        let table = chunkTable(stream)
        #expect(table.map(\.uncompressed) == [100_000, 100_000, 50_000])
        #expect(102 + table.reduce(0) { $0 + 8 + $1.compressed } == stream.count)
    }

    @Test func roundTripsRepetitiveBytes() throws {
        let line = Data("Table(Marketing) Column(Ngày) Measure(Doanh thu)\n".utf8)
        var abf = Data()
        while abf.count < 40_000 { abf.append(line) }

        let stream = try DataModelStream.compress(abf: abf)
        let (decoded, _) = try DataModelStream.decompress(stream)

        #expect(decoded == abf)
        #expect(stream.count < abf.count / 10)
    }

    @Test(.enabled(if: CompressSamples.hasTuan62))
    func tuan62SignatureMatchesSampleByteForByte() throws {
        let sample = try storedDataModel(of: CompressSamples.tuan62)
        let (abf, _) = try PBIXFile(url: CompressSamples.tuan62).loadDataModel()
        let stream = try DataModelStream.compress(abf: abf.data)

        #expect(stream.prefix(102) == sample.prefix(102))
    }

    @Test(.enabled(if: CompressSamples.hasTuan62))
    func tuan62RoundTripsAndReportsSize() throws {
        let sample = try storedDataModel(of: CompressSamples.tuan62)
        let (abf, _) = try PBIXFile(url: CompressSamples.tuan62).loadDataModel()

        let (stream, seconds) = try timed { try DataModelStream.compress(abf: abf.data) }
        let (decoded, kind) = try DataModelStream.decompress(stream)

        #expect(kind == .singleThreaded)
        #expect(decoded == abf.data)
        let table = chunkTable(stream)
        #expect(table.map(\.uncompressed) == [958_464])

        let perChunk = try DataModelStream.compressChunks(abf: abf.data, chunkSize: DataModelStream.defaultChunkSize, encoderPerChunk: true)
        let (decodedPerChunk, _) = try DataModelStream.decompress(perChunk)
        #expect(decodedPerChunk == abf.data)

        print("KEY tuan6.2: ABF \(abf.data.count) B -> DataModel \(stream.count) B (original member \(sample.count) B, ratio \(String(format: "%.4f", Double(stream.count) / Double(sample.count)))); compress \(String(format: "%.3f", seconds)) s; per-chunk encoders \(perChunk.count) B")

        if let outDir = ProcessInfo.processInfo.environment["WP1_OUT_DIR"] {
            let target = URL(fileURLWithPath: outDir).appendingPathComponent("tuan6.2.compressed.bin")
            try stream.write(to: target)
        }
    }

    @Test(.enabled(if: CompressSamples.hasNhom6))
    func nhom6ChunkTableSignatureAndTiming() throws {
        let sample = try storedDataModel(of: CompressSamples.nhom6)
        let sampleTable = chunkTable(sample)
        #expect(sampleTable.count == 46)
        #expect(sampleTable.first?.uncompressed == 2_097_152)
        #expect(sampleTable.last?.uncompressed == 4096)

        let (abf, _) = try PBIXFile(url: CompressSamples.nhom6).loadDataModel()
        let (stream, seconds) = try timed { try DataModelStream.compress(abf: abf.data) }

        #expect(stream.prefix(102) == sample.prefix(102))
        let table = chunkTable(stream)
        #expect(table.count == 46)
        #expect(table.first?.uncompressed == 2_097_152)
        #expect(table.last?.uncompressed == 4096)
        #expect(table.map(\.uncompressed) == sampleTable.map(\.uncompressed))

        let (decoded, _) = try DataModelStream.decompress(stream)
        #expect(decoded == abf.data)

        print("KEY nhom6 shared encoder: ABF \(abf.data.count) B -> DataModel \(stream.count) B (original \(sample.count) B, ratio \(String(format: "%.4f", Double(stream.count) / Double(sample.count)))); compress \(String(format: "%.3f", seconds)) s; chunks \(table.count)")
    }

    /// Fresh encoder per chunk: each chunk restarts the XPress9 block index at 0, while the
    /// decoder (one session for the whole stream, as Power BI writes it) expects it to continue.
    /// So this layout is rejected on decode; the test pins that finding and records the size.
    @Test(.enabled(if: CompressSamples.hasNhom6))
    func nhom6FreshEncoderPerChunkIsRejectedByDecoder() throws {
        let sample = try storedDataModel(of: CompressSamples.nhom6)
        let (abf, _) = try PBIXFile(url: CompressSamples.nhom6).loadDataModel()
        let (stream, seconds) = try timed {
            try DataModelStream.compressChunks(abf: abf.data, chunkSize: DataModelStream.defaultChunkSize, encoderPerChunk: true)
        }

        #expect(throws: DataModelStream.Error.self) { _ = try DataModelStream.decompress(stream) }
        print("KEY nhom6 per-chunk encoders: DataModel \(stream.count) B (original \(sample.count) B, ratio \(String(format: "%.4f", Double(stream.count) / Double(sample.count)))); compress \(String(format: "%.3f", seconds)) s; decode rejected")
    }
}
