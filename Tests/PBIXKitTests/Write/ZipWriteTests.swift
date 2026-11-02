import Foundation
import Testing
@testable import PBIXKit

/// Fixtures are the author's own reports. Tests that need one are disabled when it is absent.
/// Test output goes to `$PBIX_WP2_OUT` when set, otherwise to the WP2 scratch folder.
enum WP2Fixture {
    static let nhom6 = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/Nhom6_Dashboard.pbix")

    static let outDir: URL = {
        if let path = ProcessInfo.processInfo.environment["PBIX_WP2_OUT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: "/private/tmp/claude-501/-Users-macprom114-Desktop-PowerBINative/39e5fdc8-d27c-46a2-b750-47ff2adaa733/scratchpad/w/out/wp2", isDirectory: true)
    }()

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func writeOutput(_ data: Data, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

@Suite struct ZipWriteTests {
    @Test func crc32MatchesStandardCheckValue() {
        #expect(ZipCRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZipCRC32.checksum(Data()) == 0)
    }

    @Test func dosTimestampUsesLocalTimeAndDosLayout() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 21, minute: 28, second: 39)))
        let stamp = ZipWriter.dosTimestamp(date)
        #expect(stamp.date == UInt16(((2026 - 1980) << 9) | (10 << 5) | 31))
        #expect(stamp.time == UInt16((21 << 11) | (28 << 5) | (39 / 2)))
        // Before 1980 clamps to the DOS epoch.
        let early = ZipWriter.dosTimestamp(Date(timeIntervalSince1970: 0))
        #expect(early.date == UInt16((1 << 5) | 1))
        #expect(early.time == 0)
    }

    @Test func deflateAndStoredMembersRoundTrip() throws {
        let text = Data(String(repeating: "Doanh thu theo tháng, giao dịch\n", count: 500).utf8)
        var blobBytes = [UInt8]()
        for i in 0..<4096 { blobBytes.append(UInt8(truncatingIfNeeded: i &* 31 ^ (i >> 3))) }
        let blob = Data(blobBytes)

        let data = try ZipWriter.write([
            (path: "a/deflate.txt", source: .bytes(text, method: 8)),
            (path: "b/stored.bin", source: .bytes(blob, method: 0)),
            (path: "c/empty.txt", source: .bytes(Data(), method: 8)),
            (path: "Report/tiếng Việt.json", source: .bytes(Data("{}".utf8), method: 8)),
        ], modified: Date(timeIntervalSince1970: 1_700_000_000))

        let archive = try ZipArchive(data: data)
        #expect(archive.entries.map(\.path) == ["a/deflate.txt", "b/stored.bin", "c/empty.txt", "Report/tiếng Việt.json"])

        let deflated = try #require(archive.entry("a/deflate.txt"))
        #expect(deflated.method == 8)
        #expect(deflated.uncompressedSize == text.count)
        #expect(deflated.compressedSize < text.count)
        #expect(deflated.crc32 == ZipCRC32.checksum(text))
        let deflatedBack = try archive.read(deflated)
        #expect(deflatedBack == text)

        let stored = try #require(archive.entry("b/stored.bin"))
        #expect(stored.method == 0)
        #expect(stored.compressedSize == blob.count)
        #expect(stored.crc32 == ZipCRC32.checksum(blob))
        let storedBack = try archive.read(stored)
        #expect(storedBack == blob)

        let empty = try #require(archive.entry("c/empty.txt"))
        let emptyBack = try archive.read(empty)
        #expect(emptyBack.isEmpty)
        #expect(empty.crc32 == 0)

        let unicodeName = try #require(archive.entry("Report/tiếng Việt.json"))
        let unicodeBack = try archive.read(unicodeName)
        #expect(unicodeBack == Data("{}".utf8))
    }

    @Test func unsupportedMethodThrowsInvalid() {
        expectInvalid {
            try ZipWriter.write([(path: "x.txt", source: .bytes(Data("x".utf8), method: 12))])
        }
    }

    @Test func emptyAndDuplicateNamesThrowInvalid() {
        expectInvalid {
            try ZipWriter.write([(path: "", source: .bytes(Data(), method: 0))])
        }
        expectInvalid {
            try ZipWriter.write([
                (path: "same.txt", source: .bytes(Data(), method: 0)),
                (path: "same.txt", source: .bytes(Data(), method: 0)),
            ])
        }
    }

    @Test func moreThan65535MembersThrowInvalid() {
        let members = (0...0xFFFF).map { (path: "m\($0)", source: ZipWriter.Source.bytes(Data(), method: 0)) }
        expectInvalid { try ZipWriter.write(members) }
    }

    private func expectInvalid(_ body: () throws -> Data) {
        do {
            _ = try body()
            Issue.record("expected WriteError.invalid, but the write succeeded")
        } catch let error as WriteError {
            if case .invalid = error { return }
            Issue.record("expected WriteError.invalid, got \(error)")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

@Suite(.enabled(if: WP2Fixture.exists(WP2Fixture.nhom6))) struct ZipNhom6CopyTests {
    @Test func rawCopyOfEveryMemberIsByteIdentical() throws {
        let source = try ZipArchive(url: WP2Fixture.nhom6)
        #expect(source.entries.count == 169)

        let members = source.entries.map { (path: $0.path, source: ZipWriter.Source.rawCopy(source, $0)) }
        let data = try ZipWriter.write(members)
        let copy = try ZipArchive(data: data)

        #expect(copy.entries.map(\.path) == source.entries.map(\.path))
        for (original, written) in zip(source.entries, copy.entries) {
            #expect(written.method == original.method, "\(original.path)")
            #expect(written.crc32 == original.crc32, "\(original.path)")
            #expect(written.compressedSize == original.compressedSize, "\(original.path)")
            #expect(written.uncompressedSize == original.uncompressedSize, "\(original.path)")

            let originalPayload = try source.rawPayload(of: original)
            let writtenPayload = try copy.rawPayload(of: written)
            #expect(writtenPayload == originalPayload, "\(original.path)")

            let originalText = try source.read(original)
            let writtenText = try copy.read(written)
            #expect(writtenText == originalText, "\(original.path)")
        }

        let dataModel = try #require(copy.entry("DataModel"))
        #expect(dataModel.method == 0)
        let entryOriginalmodel = try #require(source.entry("DataModel"))
        let originalModelOptional = try source.storedSlice(entryOriginalmodel)
        let originalModel = try #require(originalModelOptional)
        let writtenModelOptional = try copy.storedSlice(dataModel)
        let writtenModel = try #require(writtenModelOptional)
        #expect(writtenModel == originalModel)

        let url = try WP2Fixture.writeOutput(data, name: "nhom6.copy.pbix")
        print("WP2 wrote \(url.path) (\(data.count) bytes)")
    }
}
