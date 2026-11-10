import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Lưu thay đổi trường (D2): `contracts/query-state-patch.md` mục "Kiểm tra khi lưu".
@Suite @MainActor struct FieldSavingTests {
    typealias S = SyntheticReport
    static let measure = FieldEditingTests.measure

    @MainActor struct Env {
        let dir: URL
        let source: URL
        let archive: ZipArchive
        let backups: URL
        let editor: LayoutEditor
        let stamp: FileStamp

        init() throws {
            dir = SyntheticReport.temporaryDirectory("fieldsave")
            source = try SyntheticReport.make(in: dir, withChart: true)
            archive = try ZipArchive(url: source)
            backups = dir.appendingPathComponent("Backups", isDirectory: true)
            let archive = self.archive
            editor = LayoutEditor(report: try PBIXFile(url: source).loadReport(), sourceJSON: { page, id in
                try? archive.read(LayoutEditor.visualPath(page: page, id: id))
            })
            editor.showPage("p1")
            stamp = try FileStamp.of(source)
        }

        func save(stamp: FileStamp? = nil) throws -> SaveOutcome {
            try DocumentSaver.save(editor: editor, source: source, to: source, expectedStamp: stamp ?? self.stamp,
                                   readOnlyRoots: [], backupDirectory: backups)
        }
        func reloaded(_ id: String = S.c1) throws -> ReportVisual {
            let report = try PBIXFile(url: source).loadReport()
            return try #require(report.pages.first { $0.id == "p1" }?.visuals.first { $0.id == id })
        }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    static let chartPath = LayoutEditor.visualPath(page: "p1", id: S.c1)

    @Test func onlyTheEditedVisualProducesAPart() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.reportParts.keys) == [Self.chartPath])
        #expect(changes.addedParts.isEmpty && changes.removedParts.isEmpty)
    }

    @Test func savedFieldsReadBackAndEverythingElseOfTheVisualIsUntouched() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try env.archive.read(Self.chartPath)
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        env.editor.renameField(role: "Y2", index: 0, to: "Dòng tiền", visual: S.c1)
        env.editor.moveField(role: "Y", index: 1, to: "Y2", visual: S.c1)
        let expected = try #require(env.editor.visual(S.c1))
        _ = try env.save()
        let actual = try env.reloaded()
        #expect(actual.fields == expected.fields)
        #expect(actual.fields.filter { $0.role == "Y" }.map(\.property) == ["Credit", "Balance"])
        #expect(actual.fields.filter { $0.role == "Y2" }.map(\.property) == ["Net", "Debit"])
        // Ngoài queryState, visual.json giữ nguyên.
        let after = try ZipArchive(url: env.source).read(Self.chartPath)
        func stripped(_ data: Data) throws -> NSDictionary {
            var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var visual = root["visual"] as! [String: Any]
            var query = visual["query"] as! [String: Any]
            query["queryState"] = nil
            visual["query"] = query
            root["visual"] = visual
            return root as NSDictionary
        }
        #expect(try stripped(before) == stripped(after))
        // SecurityBindings bị bỏ như D1.
        #expect(try ZipArchive(url: env.source).entry("SecurityBindings") == nil)
    }

    @Test func fieldEditCombinedWithAMoveWritesBoth() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        env.editor.move([S.c1], dx: 40, dy: 24, snap: true)
        _ = try env.save()
        let actual = try env.reloaded()
        #expect(actual.fields.filter { $0.role == "Y" }.map(\.property) == ["Credit", "Debit", "Balance"])
        #expect(actual.x == 640 && actual.y == 128)
    }

    @Test func aSecondSaveAfterMoreFieldEditsIsCorrect() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        var outcome = try env.save()
        env.editor.removeField(role: "Y", index: 0, visual: S.c1)
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Fees"), to: "Tooltips", visual: S.c1)
        outcome = try env.save(stamp: outcome.newStamp)
        #expect(outcome.didWrite)
        let actual = try env.reloaded()
        #expect(actual.fields == env.editor.visual(S.c1)?.fields)
        #expect(actual.fields.filter { $0.role == "Y" }.map(\.property) == ["Debit", "Balance"])
        #expect(actual.fields.filter { $0.role == "Tooltips" }.map(\.property) == ["Avg", "Fees"])
    }

    @Test func aCopyMadeAfterEditingCarriesItsFieldsIntoTheFile() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        env.editor.select(S.c1)
        let copy = try #require(env.editor.duplicate([S.c1]).first)
        env.editor.renameField(role: "Y", index: 0, to: "Copy", visual: copy)
        _ = try env.save()
        let saved = try env.reloaded(copy)
        #expect(saved.fields.filter { $0.role == "Y" }.map(\.label) == ["Copy", "Debit", "Balance"])
        // Visual gốc không bị ảnh hưởng bởi đổi tên của bản sao.
        #expect(try env.reloaded().fields.filter { $0.role == "Y" }.map(\.label) == ["Tiền vào", "Debit", "Balance"])
    }

    @Test func verifyLayoutCatchesFieldsThatDifferFromTheEditor() throws {
        let env = try Env(); defer { env.cleanUp() }
        // Bytes dựng KHÔNG có sửa trường, nhưng editor có: phải bị bắt.
        let plain = try PBIXWriter.build(source: env.source, changes: PBIXChanges()).data
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        do {
            try DocumentSaver.verifyLayout(plain, editor: env.editor)
            Issue.record("expected verificationFailed")
        } catch let error as SaveError {
            guard case .verificationFailed(let why) = error else { Issue.record("got \(error)"); return }
            #expect(why.contains(S.c1))
        }
        // Bytes đúng thì qua.
        let good = try PBIXWriter.build(source: env.source, changes: try env.editor.makeChanges(archive: env.archive)).data
        try DocumentSaver.verifyLayout(good, editor: env.editor)
    }
}
