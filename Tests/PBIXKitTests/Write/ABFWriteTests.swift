import Foundation
import Testing
@testable import PBIXKit

/// Fixtures are the author's own reports. Tests that need one are disabled when it is absent.
/// Output goes to `$PBIX_WP3_OUT` when set, otherwise to the WP3 scratch folder.
enum ABFFixture {
    static let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    static let tuan6 = downloads.appendingPathComponent("tuan6.2.pbix")
    static let nhom6 = downloads.appendingPathComponent("Nhom6_Dashboard.pbix")

    /// The Financial Service report sits in a folder with a non-ASCII name; find it by content of its name.
    static let nhom2: URL? = {
        let folder = downloads.appendingPathComponent("Nhóm 2/Dashboard", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return names.first { $0.lastPathComponent.contains("Financial Service") && $0.pathExtension == "pbix" }
    }()

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static var nhom2Exists: Bool { nhom2.map(exists) ?? false }

    static func loadABF(_ url: URL) throws -> ABFBackup {
        try PBIXFile(url: url).loadDataModel().0
    }

    static let outDir: URL = {
        if let path = ProcessInfo.processInfo.environment["PBIX_WP3_OUT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: "/private/tmp/claude-501/-Users-macprom114-Desktop-PowerBINative/39e5fdc8-d27c-46a2-b750-47ff2adaa733/scratchpad/w/out/wp3", isDirectory: true)
    }()

    static func writeOutput(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try data.write(to: outDir.appendingPathComponent(name))
    }

    /// Describes the first differing byte, for a failure message only (never built on success).
    static func firstDifference(_ a: Data, _ b: Data) -> String {
        if a.count != b.count { return "size \(a.count) vs \(b.count)" }
        for i in 0..<a.count where a[a.startIndex + i] != b[b.startIndex + i] {
            return "first difference at byte \(i)"
        }
        return "no difference"
    }
}

/// Checks the stored layout that every rewrite must produce: header page, payloads back to back
/// from offset 4096 with LOG last, virtual directory on the next page boundary, total a 4 KiB multiple.
private func expectStoredLayout(_ abf: ABFBackup, total: Int) {
    var position = 4096
    for entry in abf.virtualEntries {
        #expect(entry.offset == position, "payload \(entry.storagePath) is not contiguous")
        position += entry.size
    }
    #expect(abf.virtualEntries.last?.storagePath == "LOG")
    #expect(abf.header.virtualDirectoryOffset == (position + 4095) / 4096 * 4096)
    #expect(abf.header.fileCount == abf.virtualEntries.count)
    #expect(total % 4096 == 0)
}

@Suite struct ABFWriteTests {
    @Test(.enabled(if: ABFFixture.exists(ABFFixture.tuan6)))
    func identityTuan6() throws {
        let abf = try ABFFixture.loadABF(ABFFixture.tuan6)
        let rebuilt = try ABFWriter.rebuild(abf)
        let same = rebuilt == abf.data
        #expect(same)
        if !same { Issue.record("tuan6.2: \(ABFFixture.firstDifference(rebuilt, abf.data))") }
        try ABFFixture.writeOutput(rebuilt, name: "tuan6.2.rebuilt.abf")
    }

    @Test(.enabled(if: ABFFixture.nhom2Exists))
    func identityNhom2() throws {
        let abf = try ABFFixture.loadABF(try #require(ABFFixture.nhom2))
        let rebuilt = try ABFWriter.rebuild(abf)
        let same = rebuilt == abf.data
        #expect(same)
        if !same { Issue.record("nhom2: \(ABFFixture.firstDifference(rebuilt, abf.data))") }
    }

    @Test(.enabled(if: ABFFixture.exists(ABFFixture.nhom6)))
    func identityNhom6() throws {
        let abf = try ABFFixture.loadABF(ABFFixture.nhom6)
        let start = Date()
        let rebuilt = try ABFWriter.rebuild(abf)
        let seconds = Date().timeIntervalSince(start)
        let same = rebuilt == abf.data
        #expect(same)
        if !same { Issue.record("Nhom6: \(ABFFixture.firstDifference(rebuilt, abf.data))") }
        print("WP3 KEY Nhom6 rebuild identity: \(String(format: "%.2f", seconds)) s, \(abf.data.count) bytes, debug build")
    }

    @Test(.enabled(if: ABFFixture.exists(ABFFixture.tuan6)))
    func sameLengthReplaceWithSameBytesIsIdentity() throws {
        let abf = try ABFFixture.loadABF(ABFFixture.tuan6)
        let file = try #require(abf.files.first { $0.path == "metadata.sqlitedb" })
        let payload = ABFPayload(path: "metadata.sqlitedb", data: abf.contents(of: file))
        let rebuilt = try ABFWriter.rebuild(abf, replacing: [payload])
        let same = rebuilt == abf.data
        #expect(same)
        if !same { Issue.record("same-length replace: \(ABFFixture.firstDifference(rebuilt, abf.data))") }
    }

    @Test(.enabled(if: ABFFixture.exists(ABFFixture.tuan6)))
    func sameLengthReplaceWithDifferentBytesChangesOnlyThatFile() throws {
        let abf = try ABFFixture.loadABF(ABFFixture.tuan6)
        let file = try #require(abf.files.first { $0.path == "metadata.sqlitedb" })
        var changed = Data(abf.contents(of: file))
        changed[changed.count / 2] ^= 0xFF
        let rebuilt = try ABFWriter.rebuild(abf, replacing: [ABFPayload(path: "metadata.sqlitedb", data: changed)])
        #expect(rebuilt.count == abf.data.count)

        let reparsed = try ABFBackup(data: rebuilt)
        #expect(reparsed.files.count == abf.files.count)
        let newFile = try #require(reparsed.files.first { $0.path == "metadata.sqlitedb" })
        #expect(newFile.size == changed.count)
        #expect(newFile.sizeFromLog == changed.count)
        #expect(reparsed.contents(of: newFile) == changed)
        expectStoredLayout(reparsed, total: rebuilt.count)
    }

    @Test(.enabled(if: ABFFixture.exists(ABFFixture.tuan6)))
    func replaceWithLargerOrSmallerPayloadKeepsOtherFiles() throws {
        let abf = try ABFFixture.loadABF(ABFFixture.tuan6)
        let file = try #require(abf.files.first { $0.path == "metadata.sqlitedb" })
        let original = Data(abf.contents(of: file))
        var grown = original
        grown.append(contentsOf: repeatElement(UInt8(0), count: 1024))
        let shrunk = Data(original.dropLast(1024))

        for (label, replacement) in [("grown", grown), ("shrunk", shrunk)] {
            let rebuilt = try ABFWriter.rebuild(abf, replacing: [ABFPayload(path: "metadata.sqlitedb", data: replacement)])
            let reparsed = try ABFBackup(data: rebuilt)
            #expect(reparsed.files.count == abf.files.count, "\(label): file count")

            let newFile = try #require(reparsed.files.first { $0.path == "metadata.sqlitedb" })
            #expect(newFile.size == replacement.count, "\(label): VD size")
            #expect(newFile.sizeFromLog == replacement.count, "\(label): log size")
            #expect(reparsed.contents(of: newFile) == replacement, "\(label): contents")

            let before = Dictionary(abf.files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            for other in reparsed.files where other.path != "metadata.sqlitedb" {
                guard let source = before[other.path] else {
                    Issue.record("\(label): unexpected file \(other.path)")
                    continue
                }
                #expect(reparsed.contents(of: other) == abf.contents(of: source), "\(label): \(other.path) changed")
            }
            expectStoredLayout(reparsed, total: rebuilt.count)

            if label == "grown" {
                try ABFFixture.writeOutput(rebuilt, name: "tuan6.2.replaced.abf")
            }
        }
    }

    @Test(.enabled(if: ABFFixture.exists(ABFFixture.tuan6)))
    func addedFileIsVisibleAfterReparse() throws {
        let abf = try ABFFixture.loadABF(ABFFixture.tuan6)
        let name = "Test.tbl\\0.test.bin"
        let blob = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 7 ^ ($0 >> 4)) })
        let rebuilt = try ABFWriter.rebuild(abf, adding: [ABFPayload(path: name, data: blob)])

        let reparsed = try ABFBackup(data: rebuilt)
        let added = try #require(reparsed.files.first { $0.path == name })
        #expect(added.size == 5000)
        #expect(added.sizeFromLog == 5000)
        #expect(reparsed.contents(of: added) == blob)

        let storage = added.storagePath
        #expect(storage.count == 20)
        #expect(storage.allSatisfy { "0123456789ABCDEF".contains($0) })
        #expect(!abf.virtualEntries.contains { $0.storagePath == storage })

        #expect(reparsed.files.count == abf.files.count + 1)
        #expect(reparsed.virtualEntries.count == abf.virtualEntries.count + 1)
        expectStoredLayout(reparsed, total: rebuilt.count)

        // The added payload sits before LOG; every other payload keeps its content.
        let before = Dictionary(abf.files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        for other in reparsed.files where other.path != name && other.path != "metadata.sqlitedb" {
            if let source = before[other.path] {
                #expect(reparsed.contents(of: other) == abf.contents(of: source), "\(other.path) changed")
            }
        }
    }

    @Test(.enabled(if: ABFFixture.exists(ABFFixture.tuan6)))
    func invalidInputsThrow() throws {
        let abf = try ABFFixture.loadABF(ABFFixture.tuan6)
        #expect(throws: WriteError.self) {
            try ABFWriter.rebuild(abf, replacing: [ABFPayload(path: "no-such-file.bin", data: Data([1]))])
        }
        #expect(throws: WriteError.self) {
            try ABFWriter.rebuild(abf, replacing: [ABFPayload(path: "metadata.sqlitedb", data: Data())])
        }
        #expect(throws: WriteError.self) {
            try ABFWriter.rebuild(abf, adding: [ABFPayload(path: "metadata.sqlitedb", data: Data([1]))])
        }
        #expect(throws: WriteError.self) {
            try ABFWriter.rebuild(abf, adding: [ABFPayload(path: "x.bin", data: Data())])
        }
    }
}
