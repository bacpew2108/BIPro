import Foundation
import Testing
@testable import PBIXKit

/// Một `.pbix` nhỏ dựng bằng tay (định dạng PBIR) để test đường ghi T1 không cần file thật của người dùng.
enum SyntheticPBIX {
    static let pageA = "page_a"
    static let pageB = "page_b"
    static let visualsA = ["aaaaaaaaaaaaaaaaaaa1", "aaaaaaaaaaaaaaaaaaa2", "aaaaaaaaaaaaaaaaaaa3"]
    static let visualsB = ["bbbbbbbbbbbbbbbbbbb1", "bbbbbbbbbbbbbbbbbbb2"]

    static func visualPath(_ page: String, _ id: String) -> String {
        "Report/definition/pages/\(page)/visuals/\(id)/visual.json"
    }

    static func visualJSON(name: String, x: Int, y: Int, z: Int, w: Int, h: Int, type: String = "card") -> String {
        #"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.13.0/schema.json","name":"\#(name)","position":{"x":\#(x),"y":\#(y),"z":\#(z),"height":\#(h),"width":\#(w),"tabOrder":\#(z)},"visual":{"visualType":"\#(type)","query":{"queryState":{"Values":{"projections":[{"field":{"Measure":{"Expression":{"SourceRef":{"Entity":"T"}},"Property":"M"}},"queryRef":"T.M","nativeQueryRef":"M"}]}}}}}"#
    }

    /// Nội dung các phần theo thứ tự thành viên ZIP.
    static func members() -> [(path: String, data: Data, method: UInt16)] {
        func text(_ s: String) -> Data { Data(s.utf8) }
        var out: [(String, Data, UInt16)] = [
            ("Version", text("1.32"), 0),
            ("[Content_Types].xml", Data("\u{FEFF}<?xml version=\"1.0\" encoding=\"utf-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"json\" ContentType=\"\" /><Override PartName=\"/Version\" ContentType=\"\" /><Override PartName=\"/SecurityBindings\" ContentType=\"\" /><Override PartName=\"/DataModel\" ContentType=\"\" /></Types>".utf8), 8),
            ("DataModel", Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 31 ^ ($0 >> 3)) }), 0),
            ("SecurityBindings", Data([1, 2, 3, 4, 5]), 0),
            ("Report/definition/version.json", text(#"{"version":"2.0.0"}"#), 8),
            ("Report/definition/report.json", text(#"{"themeCollection":{"baseTheme":{"name":"CY"}}}"#), 8),
            ("Report/definition/pages/pages.json", text(#"{"pageOrder":["page_a","page_b"],"activePageName":"page_a"}"#), 8),
            ("Report/definition/bookmarks/bookmarks.json", text(#"{"items":[{"name":"bm1"}]}"#), 8),
            ("Report/definition/bookmarks/bm1.bookmark.json",
             text(#"{"name":"bm1","displayName":"BM","options":{"applyOnlyToTargetVisuals":true,"targetVisualNames":["aaaaaaaaaaaaaaaaaaa1","aaaaaaaaaaaaaaaaaaa2"]},"explorationState":{"version":"1.0","activeSection":"page_a","sections":{"page_a":{"visualContainers":{"aaaaaaaaaaaaaaaaaaa1":{"singleVisual":{"visualType":"card"}},"aaaaaaaaaaaaaaaaaaa2":{"singleVisual":{"visualType":"card"}}}}}}}"#), 8),
        ]
        for (page, ids) in [(pageA, visualsA), (pageB, visualsB)] {
            out.append(("Report/definition/pages/\(page)/page.json",
                        text(#"{"name":"\#(page)","displayName":"\#(page)","width":1280,"height":720}"#), 8))
            for (i, id) in ids.enumerated() {
                out.append((visualPath(page, id),
                            text(visualJSON(name: id, x: 40 + i * 100, y: 80, z: 1000 * (i + 1), w: 90, h: 60)), 8))
            }
        }
        return out
    }

    @discardableResult
    static func make(in directory: URL, name: String = "syn.pbix") throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let list = members().map { (path: $0.path, source: ZipWriter.Source.bytes($0.data, method: $0.method)) }
        let url = directory.appendingPathComponent(name)
        try ZipWriter.write(list, modified: nil).write(to: url)
        return url
    }

    static func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bipro-\(label)-\(UUID().uuidString)", isDirectory: true)
    }
}

@Suite struct PBIXWriterEditTests {
    private func expectInvalid(_ body: () throws -> Void, _ message: String = "") {
        do {
            try body()
            Issue.record("expected WriteError.invalid but the call succeeded \(message)")
        } catch let error as WriteError {
            if case .invalid = error { return }
            Issue.record("expected WriteError.invalid, got \(error)")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func addedPartIsInsertedAfterLastVisualOfThePage() throws {
        let dir = SyntheticPBIX.temporaryDirectory("add")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir)
        let newID = "aaaaaaaaaaaaaaaaaaa4"
        let path = SyntheticPBIX.visualPath(SyntheticPBIX.pageA, newID)
        var changes = PBIXChanges()
        changes.addedParts[path] = Data(SyntheticPBIX.visualJSON(name: newID, x: 0, y: 0, z: 4000, w: 10, h: 10).utf8)

        let result = try PBIXWriter.build(source: source, changes: changes)
        let archive = try ZipArchive(data: result.data)
        let paths = archive.entries.map(\.path)
        let last = try #require(paths.firstIndex(of: SyntheticPBIX.visualPath(SyntheticPBIX.pageA, "aaaaaaaaaaaaaaaaaaa3")))
        #expect(paths[last + 1] == path)
        #expect(try archive.read(path) == changes.addedParts[path])
        #expect(paths.count == SyntheticPBIX.members().count + 1 - 1)  // phần mới, và SecurityBindings bị bỏ
        #expect(result.tier == .report)
    }

    @Test func removedPartIsDroppedAndNothingElse() throws {
        let dir = SyntheticPBIX.temporaryDirectory("remove")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir)
        let path = SyntheticPBIX.visualPath(SyntheticPBIX.pageA, "aaaaaaaaaaaaaaaaaaa2")
        var changes = PBIXChanges()
        changes.removedParts.insert(path)

        let result = try PBIXWriter.build(source: source, changes: changes)
        let archive = try ZipArchive(data: result.data)
        #expect(archive.entry(path) == nil)
        #expect(archive.entries.count == SyntheticPBIX.members().count - 1 - 1)  // phần bị xoá, và SecurityBindings
        #expect(result.tier == .report)
    }

    @Test func untouchedMembersKeepTheirBytes() throws {
        let dir = SyntheticPBIX.temporaryDirectory("same")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir)
        let original = try ZipArchive(url: source)
        let changedPath = SyntheticPBIX.visualPath(SyntheticPBIX.pageA, "aaaaaaaaaaaaaaaaaaa1")
        var changes = PBIXChanges()
        changes.reportParts[changedPath] = Data(SyntheticPBIX.visualJSON(name: "aaaaaaaaaaaaaaaaaaa1", x: 8, y: 8, z: 1000, w: 90, h: 60).utf8)
        changes.removedParts.insert(SyntheticPBIX.visualPath(SyntheticPBIX.pageB, "bbbbbbbbbbbbbbbbbbb2"))

        let result = try PBIXWriter.build(source: source, changes: changes)
        let written = try ZipArchive(data: result.data)
        let dropped: Set = ["SecurityBindings", "[Content_Types].xml"]  // xem reportChangesDropSecurityBinding...
        for entry in original.entries where entry.path != changedPath && !changes.removedParts.contains(entry.path) && !dropped.contains(entry.path) {
            let now = try #require(written.entry(entry.path), "\(entry.path) missing")
            #expect(now.crc32 == entry.crc32, "\(entry.path)")
            #expect(try written.read(now) == original.read(entry), "\(entry.path)")
        }
        #expect(try written.read(changedPath) == changes.reportParts[changedPath])
        // DataModel còn nguyên.
        #expect(try written.read("DataModel") == original.read("DataModel"))
    }

    /// Đo trên VM (2026-11-10, Power BI Desktop 2.159): đổi dù một byte của một phần `Report/definition/**` mà
    /// giữ `SecurityBindings` thì Desktop báo "file is corrupted"; bỏ `SecurityBindings` (cùng dòng Override của
    /// nó trong `[Content_Types].xml`) thì mở được. Xem `specs/002-d1-canvas-luu-t1/research.md` R13.
    @Test func reportChangesDropSecurityBindingAndItsContentTypeOverride() throws {
        let dir = SyntheticPBIX.temporaryDirectory("sb")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir)
        let original = try ZipArchive(url: source)
        let path = SyntheticPBIX.visualPath(SyntheticPBIX.pageA, "aaaaaaaaaaaaaaaaaaa1")
        var changes = PBIXChanges()
        changes.reportParts[path] = Data(SyntheticPBIX.visualJSON(name: "aaaaaaaaaaaaaaaaaaa1", x: 8, y: 8, z: 1000, w: 90, h: 60).utf8)

        let written = try ZipArchive(data: try PBIXWriter.build(source: source, changes: changes).data)
        #expect(written.entry("SecurityBindings") == nil)
        #expect(written.entries.count == original.entries.count - 1)
        // Chỉ dòng Override của SecurityBindings mất; mọi thứ khác (cả dấu BOM đầu file) giữ nguyên.
        let before = String(decoding: try original.read("[Content_Types].xml"), as: UTF8.self)
        let after = String(decoding: try written.read("[Content_Types].xml"), as: UTF8.self)
        #expect(after == before.replacingOccurrences(of: #"<Override PartName="/SecurityBindings" ContentType="" />"#, with: ""))
        #expect(!after.contains("SecurityBindings"))
        #expect(after.hasPrefix("\u{FEFF}"))
        // DataModel và các phần khác còn nguyên.
        #expect(try written.read("DataModel") == original.read("DataModel"))
        #expect(try written.read("Version") == original.read("Version"))
    }

    @Test func addAndRemoveAlsoDropSecurityBinding() throws {
        let dir = SyntheticPBIX.temporaryDirectory("sb2")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir)
        var removed = PBIXChanges()
        removed.removedParts.insert(SyntheticPBIX.visualPath(SyntheticPBIX.pageB, "bbbbbbbbbbbbbbbbbbb2"))
        #expect(try ZipArchive(data: try PBIXWriter.build(source: source, changes: removed).data).entry("SecurityBindings") == nil)

        var added = PBIXChanges()
        let newID = "aaaaaaaaaaaaaaaaaaa4"
        added.addedParts[SyntheticPBIX.visualPath(SyntheticPBIX.pageA, newID)] = Data(SyntheticPBIX.visualJSON(name: newID, x: 0, y: 0, z: 4000, w: 10, h: 10).utf8)
        #expect(try ZipArchive(data: try PBIXWriter.build(source: source, changes: added).data).entry("SecurityBindings") == nil)
    }

    @Test func noChangeToTheReportKeepsSecurityBinding() throws {
        let dir = SyntheticPBIX.temporaryDirectory("sb3")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir)
        let original = try ZipArchive(url: source)
        let written = try ZipArchive(data: try PBIXWriter.build(source: source, changes: PBIXChanges()).data)
        #expect(try written.read("SecurityBindings") == original.read("SecurityBindings"))
        #expect(try written.read("[Content_Types].xml") == original.read("[Content_Types].xml"))
    }

    @Test func invalidChangesAreRejected() throws {
        let dir = SyntheticPBIX.temporaryDirectory("invalid")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir)

        var addExisting = PBIXChanges()
        addExisting.addedParts[SyntheticPBIX.visualPath(SyntheticPBIX.pageA, "aaaaaaaaaaaaaaaaaaa1")] = Data("{}".utf8)
        expectInvalid({ _ = try PBIXWriter.build(source: source, changes: addExisting) }, "(thêm phần đã có)")

        var removeMissing = PBIXChanges()
        removeMissing.removedParts.insert(SyntheticPBIX.visualPath(SyntheticPBIX.pageA, "zzzzzzzzzzzzzzzzzzzz"))
        expectInvalid({ _ = try PBIXWriter.build(source: source, changes: removeMissing) }, "(bỏ phần không có)")

        var replaceAndRemove = PBIXChanges()
        let path = SyntheticPBIX.visualPath(SyntheticPBIX.pageA, "aaaaaaaaaaaaaaaaaaa1")
        replaceAndRemove.reportParts[path] = Data("{}".utf8)
        replaceAndRemove.removedParts.insert(path)
        expectInvalid({ _ = try PBIXWriter.build(source: source, changes: replaceAndRemove) }, "(vừa thay vừa bỏ)")
    }

    @Test func tierStaysReportForPartChanges() {
        var changes = PBIXChanges()
        changes.addedParts["x"] = Data()
        changes.removedParts.insert("y")
        changes.reportParts["z"] = Data()
        #expect(changes.tier == .report)
    }

    @Test func directoryBackupKeepsPreviousFileOutsideTheFolder() throws {
        let dir = SyntheticPBIX.temporaryDirectory("backup")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir, name: "src.pbix")
        let destination = dir.appendingPathComponent("dest.pbix")
        try FileManager.default.copyItem(at: source, to: destination)
        let before = try Data(contentsOf: destination)
        let backupDir = dir.appendingPathComponent("Backups", isDirectory: true)

        var changes = PBIXChanges()
        changes.removedParts.insert(SyntheticPBIX.visualPath(SyntheticPBIX.pageB, "bbbbbbbbbbbbbbbbbbb1"))
        try PBIXWriter.save(source: source, to: destination, changes: changes, backup: .directory(backupDir))

        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathExtension("bak").path))
        let backups = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: try #require(backups.first)) == before)
        let after = try ZipArchive(url: destination)
        #expect(after.entry(SyntheticPBIX.visualPath(SyntheticPBIX.pageB, "bbbbbbbbbbbbbbbbbbb1")) == nil)

        // Lần lưu thứ hai ghi đè bản sao lưu cũ, vẫn chỉ một bản.
        let second = try Data(contentsOf: destination)
        var again = PBIXChanges()
        again.removedParts.insert(SyntheticPBIX.visualPath(SyntheticPBIX.pageB, "bbbbbbbbbbbbbbbbbbb2"))
        try PBIXWriter.save(source: destination, to: destination, changes: again, backup: .directory(backupDir))
        let backups2 = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
        #expect(backups2.count == 1)
        #expect(try Data(contentsOf: try #require(backups2.first)) == second)
    }

    @Test func sideBakPolicyKeepsLegacyBehaviour() throws {
        let dir = SyntheticPBIX.temporaryDirectory("sidebak")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticPBIX.make(in: dir, name: "src.pbix")
        let destination = dir.appendingPathComponent("dest.pbix")
        try FileManager.default.copyItem(at: source, to: destination)
        var changes = PBIXChanges()
        changes.removedParts.insert(SyntheticPBIX.visualPath(SyntheticPBIX.pageB, "bbbbbbbbbbbbbbbbbbb1"))
        try PBIXWriter.save(source: source, to: destination, changes: changes)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathExtension("bak").path))
    }
}
