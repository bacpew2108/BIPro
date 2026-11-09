import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Đường lưu T1: `specs/002-d1-canvas-luu-t1/contracts/save-pipeline.md`.
@Suite @MainActor struct DocumentSaverTests {
    @MainActor private struct Env {
        let dir: URL
        let source: URL
        let backups: URL
        let editor: LayoutEditor
        let stamp: FileStamp

        init() throws {
            dir = SyntheticReport.temporaryDirectory("saver")
            source = try SyntheticReport.make(in: dir)
            backups = dir.appendingPathComponent("Backups", isDirectory: true)
            let report = try PBIXFile(url: source).loadReport()
            editor = LayoutEditor(report: report)
            editor.showPage("p1")
            stamp = try FileStamp.of(source)
        }

        func save(to destination: URL? = nil, stamp: FileStamp? = nil, readOnlyRoots: [URL] = []) throws -> SaveOutcome {
            try DocumentSaver.save(editor: editor, source: source, to: destination ?? source, expectedStamp: stamp ?? self.stamp,
                                   readOnlyRoots: readOnlyRoots, backupDirectory: backups)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    private func frames(_ url: URL, page: String = "p1") throws -> [String: Frame] {
        let report = try PBIXFile(url: url).loadReport()
        let page = try #require(report.pages.first { $0.id == page })
        return Dictionary(uniqueKeysWithValues: page.visuals.map { ($0.id, Frame($0)) })
    }

    @Test func savingAMoveWritesItAndReadsBack() throws {
        let env = try Env(); defer { env.cleanUp() }
        let originalBytes = try Data(contentsOf: env.source)
        env.editor.select(SyntheticReport.a1)
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 16, snap: true)
        #expect(env.editor.isDirty)

        let outcome = try env.save()
        #expect(outcome.didWrite)
        #expect(!env.editor.isDirty, "sau lưu thì sạch")
        let saved = try frames(env.source)
        #expect(saved[SyntheticReport.a1] == Frame(x: 120, y: 56, width: 100, height: 50))
        #expect(saved[SyntheticReport.a2] == Frame(x: 200, y: 40, width: 150, height: 80))
        // DataModel còn nguyên, trang p2 còn nguyên từng byte.
        let before = try ZipArchive(data: originalBytes), after = try ZipArchive(url: env.source)
        #expect(try after.read("DataModel") == before.read("DataModel"))
        let p2 = SyntheticReport.visualPath("p2", SyntheticReport.b1)
        #expect(try after.read(p2) == before.read(p2))
        #expect(outcome.newStamp == (try FileStamp.of(env.source)))
    }

    @Test func secondSaveAfterMoreEditsWorks() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        var outcome = try env.save()
        env.editor.move([SyntheticReport.a1], dx: 8, dy: 8, snap: true)
        outcome = try env.save(stamp: outcome.newStamp)
        #expect(outcome.didWrite)
        #expect(try frames(env.source)[SyntheticReport.a1] == Frame(x: 128, y: 48, width: 100, height: 50))
    }

    @Test func originalsUnderAReadOnlyRootAreRefused() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        let before = try Data(contentsOf: env.source)
        do {
            _ = try env.save(readOnlyRoots: [env.dir])
            Issue.record("expected readOnlyOriginal")
        } catch let error as SaveError {
            guard case .readOnlyOriginal = error else { Issue.record("got \(error)"); return }
        }
        #expect(try Data(contentsOf: env.source) == before)
        #expect(env.editor.isDirty, "chưa lưu được thì vẫn chưa sạch")
        // Dù đường dẫn có `..` hay liên kết, vẫn nhận ra.
        let sneaky = env.dir.appendingPathComponent("sub/../report.pbix")
        #expect(throws: SaveError.self) {
            _ = try DocumentSaver.save(editor: env.editor, source: env.source, to: sneaky, expectedStamp: env.stamp,
                                       readOnlyRoots: [env.dir], backupDirectory: env.backups)
        }
        // Thư mục tên giống nhưng khác (tiền tố chuỗi) thì không bị chặn.
        let sibling = env.dir.deletingLastPathComponent().appendingPathComponent(env.dir.lastPathComponent + "-other")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        let outcome = try env.save(to: sibling.appendingPathComponent("copy.pbix"), readOnlyRoots: [env.dir])
        #expect(outcome.didWrite)
    }

    @Test func aFileChangedByAnotherProgramIsNotOverwritten() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        // Chương trình khác ghi vào file (đổi kích thước).
        var bytes = try Data(contentsOf: env.source)
        bytes.append(contentsOf: [0])
        try bytes.write(to: env.source)
        let before = try Data(contentsOf: env.source)
        #expect(throws: SaveError.self) { _ = try env.save() }
        #expect(try Data(contentsOf: env.source) == before)
    }

    @Test func previousFileIsBackedUpAndOnlyOneCopyIsKept() throws {
        let env = try Env(); defer { env.cleanUp() }
        let v0 = try Data(contentsOf: env.source)
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        var outcome = try env.save()
        var files = try FileManager.default.contentsOfDirectory(at: env.backups, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(try Data(contentsOf: files[0]) == v0)
        let v1 = try Data(contentsOf: env.source)
        env.editor.move([SyntheticReport.a1], dx: 8, dy: 0, snap: true)
        outcome = try env.save(stamp: outcome.newStamp)
        files = try FileManager.default.contentsOfDirectory(at: env.backups, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(try Data(contentsOf: files[0]) == v1)
        // Không có .bak cạnh file.
        #expect(!FileManager.default.fileExists(atPath: env.source.appendingPathExtension("bak").path))
    }

    @Test func failedWriteLeavesTheDestinationAndNoTempFile() throws {
        let env = try Env(); defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: env.dir.appendingPathComponent("locked").path)
            env.cleanUp()
        }
        let locked = env.dir.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let target = locked.appendingPathComponent("out.pbix")
        try FileManager.default.copyItem(at: env.source, to: target)
        let before = try Data(contentsOf: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        #expect(throws: (any Error).self) { _ = try env.save(to: target) }
        #expect(try Data(contentsOf: target) == before)
        let left = try FileManager.default.contentsOfDirectory(atPath: locked.path)
        #expect(left == ["out.pbix"], "không còn file tạm: \(left)")
        #expect(env.editor.isDirty)
    }

    @Test func layoutVerificationCatchesAMismatch() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        let changes = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        let data = try PBIXWriter.build(source: env.source, changes: changes).data
        try DocumentSaver.verifyLayout(data, editor: env.editor)            // khớp
        env.editor.move([SyntheticReport.a2], dx: 8, dy: 8, snap: true)     // bộ sửa đi xa hơn dữ liệu đã dựng
        #expect(throws: SaveError.self) { try DocumentSaver.verifyLayout(data, editor: env.editor) }
    }

    @Test func saveAsCreatesTheNewFileAndLeavesTheSourceUntouched() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try Data(contentsOf: env.source)
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        let copy = env.dir.appendingPathComponent("copy.pbix")
        let outcome = try env.save(to: copy)
        #expect(outcome.didWrite && !env.editor.isDirty)
        #expect(try Data(contentsOf: env.source) == before)
        #expect(try frames(copy)[SyntheticReport.a1]?.x == 120)
        #expect(!FileManager.default.fileExists(atPath: env.backups.path), "đích chưa có thì không có gì để sao lưu")
    }

    @Test func nothingToSaveWritesNothing() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try Data(contentsOf: env.source)
        let modified = try FileStamp.of(env.source)
        let outcome = try env.save()
        #expect(!outcome.didWrite)
        #expect(try Data(contentsOf: env.source) == before)
        #expect(try FileStamp.of(env.source) == modified)
        #expect(!FileManager.default.fileExists(atPath: env.backups.path))
        // Sửa rồi hoàn tác về mốc sạch cũng không ghi.
        env.editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        env.editor.undo()
        #expect(!(try env.save().didWrite))
    }
}

/// `makeChanges`: chỉ phần của visual đã đổi, ghép byte (US2).
@Suite @MainActor struct LayoutChangesTests {
    @Test func onlyMovedVisualsProduceParts() throws {
        let dir = SyntheticReport.temporaryDirectory("changes"); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticReport.make(in: dir)
        let editor = LayoutEditor(report: try PBIXFile(url: source).loadReport())
        editor.showPage("p1")
        editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        editor.resize(SyntheticReport.a3, handle: .se, dx: 16, dy: 16, snap: true)
        let archive = try ZipArchive(url: source)
        let changes = try editor.makeChanges(archive: archive)

        #expect(Set(changes.reportParts.keys) == [SyntheticReport.visualPath("p1", SyntheticReport.a1),
                                                  SyntheticReport.visualPath("p1", SyntheticReport.a3)])
        #expect(changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        // Ghép byte: chỉ số trong position đổi.
        let a1 = String(decoding: try #require(changes.reportParts[SyntheticReport.visualPath("p1", SyntheticReport.a1)]), as: UTF8.self)
        let original = String(decoding: try archive.read(SyntheticReport.visualPath("p1", SyntheticReport.a1)), as: UTF8.self)
        #expect(a1 == original.replacingOccurrences(of: #""x":40"#, with: #""x":120"#))
    }

    @Test func untouchedEditorGivesNoChanges() throws {
        let dir = SyntheticReport.temporaryDirectory("changes0"); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticReport.make(in: dir)
        let editor = LayoutEditor(report: try PBIXFile(url: source).loadReport())
        let changes = try editor.makeChanges(archive: try ZipArchive(url: source))
        #expect(changes.reportParts.isEmpty && changes.addedParts.isEmpty && changes.removedParts.isEmpty)
    }

    @Test func movingBackToTheOriginalPlaceGivesNoPart() throws {
        let dir = SyntheticReport.temporaryDirectory("changes1"); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try SyntheticReport.make(in: dir)
        let editor = LayoutEditor(report: try PBIXFile(url: source).loadReport())
        editor.showPage("p1")
        editor.move([SyntheticReport.a1], dx: 80, dy: 0, snap: true)
        editor.move([SyntheticReport.a1], dx: -80, dy: 0, snap: true)
        let changes = try editor.makeChanges(archive: try ZipArchive(url: source))
        #expect(changes.reportParts.isEmpty)
    }

    @Test func decimalPositionsOfUntouchedVisualsAreNotRewritten() throws {
        let dir = SyntheticReport.temporaryDirectory("changes2"); defer { try? FileManager.default.removeItem(at: dir) }
        var members = SyntheticReport.members()
        let path = SyntheticReport.visualPath("p1", SyntheticReport.a3)
        members = members.map { $0.path == path ? (path, Data(String(decoding: $0.data, as: UTF8.self).replacingOccurrences(of: #""x":400"#, with: #""x":400.5"#).utf8), 8) : $0 }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("dec.pbix")
        try ZipWriter.write(members.map { (path: $0.path, source: ZipWriter.Source.bytes($0.data, method: $0.method)) }, modified: nil).write(to: url)
        let editor = LayoutEditor(report: try PBIXFile(url: url).loadReport())
        editor.showPage("p1")
        editor.move([SyntheticReport.a1], dx: 8, dy: 0, snap: true)   // chỉ a1; a3 (x = 400,5) không đụng tới
        let changes = try editor.makeChanges(archive: try ZipArchive(url: url))
        #expect(Set(changes.reportParts.keys) == [SyntheticReport.visualPath("p1", SyntheticReport.a1)])
    }
}
