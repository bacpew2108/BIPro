import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Lưu định dạng (D4): `specs/006-d4-format-pane/contracts/format-save.md`.
@Suite @MainActor struct FormatSavingTests {
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
            dir = S.temporaryDirectory("formatsave")
            source = try S.make(in: dir, withChart: true, extra: S.formatExtras)
            archive = try ZipArchive(url: source)
            backups = dir.appendingPathComponent("Backups", isDirectory: true)
            let archive = self.archive
            editor = LayoutEditor(report: try PBIXFile(url: source).loadReport(),
                                  sourceJSON: { page, id in try? archive.read(LayoutEditor.visualPath(page: page, id: id)) },
                                  pageSource: { page in try? archive.read(LayoutEditor.pagePath(page)) })
            editor.showPage("p1")
            stamp = try FileStamp.of(source)
        }

        func save(stamp: FileStamp? = nil) throws -> SaveOutcome {
            try DocumentSaver.save(editor: editor, source: source, to: source, expectedStamp: stamp ?? self.stamp,
                                   readOnlyRoots: [], backupDirectory: backups)
        }
        func reloaded(_ id: String) throws -> ReportVisual {
            let report = try PBIXFile(url: source).loadReport()
            return try #require(report.pages.flatMap(\.visuals).first { $0.id == id })
        }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    static func path(_ id: String, page: String = "p1") -> String { LayoutEditor.visualPath(page: page, id: id) }

    // MARK: (a) chỉ visual đã sửa có part

    @Test func onlyTheFormattedVisualProducesAPart() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.reportParts.keys) == [Self.path(S.f1)])
        #expect(changes.addedParts.isEmpty && changes.removedParts.isEmpty)
        // Sửa rồi trả về giá trị cũ: không còn gì để ghi.
        env.editor.setFormat(.number(20, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        #expect(try env.editor.makeChanges(archive: env.archive).reportParts.isEmpty)
    }

    // MARK: (b) nội dung ghi ra

    @Test func savedFormatReadsBackAndTheRestOfTheVisualIsUntouched() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try env.archive.read(Self.path(S.f1))
        env.editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        env.editor.setFormat(.bool(true), scope: .objects, object: "labels", property: "bold", visual: S.f1)
        env.editor.setFormat(.bool(false), scope: .objects, object: "categoryLabels", property: "show", visual: S.f1)
        env.editor.setFormat(.color(.hex("#e4572e")), scope: .container, object: "background", property: "color", visual: S.f1)
        env.editor.setFormat(.text("It's a test"), scope: .container, object: "title", property: "text", visual: S.f1)
        env.editor.resetFormat(scope: .objects, object: "labels", property: "labelPrecision", visual: S.f1)
        let expected = try #require(env.editor.visual(S.f1))
        _ = try env.save()
        let actual = try env.reloaded(S.f1)
        #expect(actual.objects.json == expected.objects.json && actual.containerObjects.json == expected.containerObjects.json)
        #expect(actual.objects.number("labels", "fontSize") == 28 && actual.objects.bool("labels", "bold") == true)
        #expect(actual.objects.bool("categoryLabels", "show") == false && actual.objects.number("labels", "labelPrecision") == nil)
        #expect(actual.containerObjects.string("title", "text") == "It's a test")
        // Ngoài hai khoá định dạng, visual.json giữ nguyên.
        let after = try ZipArchive(url: env.source).read(Self.path(S.f1))
        func stripped(_ data: Data) throws -> NSDictionary {
            var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var visual = root["visual"] as! [String: Any]
            visual["objects"] = nil; visual["visualContainerObjects"] = nil
            root["visual"] = visual
            return root as NSDictionary
        }
        #expect(try stripped(before) == stripped(after))
        #expect(try ZipArchive(url: env.source).entry("SecurityBindings") == nil)
        // visual khác khớp từng byte
        for other in [S.f2, S.f3, S.f4, S.f5, S.f6, S.c1, S.a1] {
            #expect(try ZipArchive(url: env.source).read(Self.path(other)) == env.archive.read(Self.path(other)), Comment(rawValue: other))
        }
    }

    @Test func aVisualWithoutFormatGetsBothScopesInTheFile() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: S.f4)
        env.editor.setFormat(.bool(true), scope: .objects, object: "cardImage", property: "show", visual: S.f4)
        _ = try env.save()
        let text = String(decoding: try ZipArchive(url: env.source).read(Self.path(S.f4)), as: UTF8.self)
        #expect(text.contains(#""objects":{"cardImage":[{"properties":{"show":\#(S.lit("true"))},"selector":{"id":"default"}}]},"visualContainerObjects":{"title":[{"properties":{"show":\#(S.lit("false"))}}]},"drillFilterOtherVisuals""#))
    }

    // MARK: (c) visual mới

    @Test func aNewVisualCarriesItsFormatIntoTheFile() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600)))
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Net"), to: "Values", visual: id)
        env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: id)
        env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: id)
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.addedParts.keys) == [Self.path(id)])
        _ = try env.save()
        let saved = try env.reloaded(id)
        #expect(saved.objects.number("labels", "fontSize") == 30 && saved.containerObjects.bool("title", "show") == false)
        #expect(saved.fields.map(\.property) == ["Net"])
    }

    // MARK: (d) cùng lúc với các sửa khác

    @Test func formatCombinedWithFieldsMoveAndTypeChangeWritesAll() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1)
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        env.editor.setFormat(.number(9, tail: .d), scope: .objects, object: "legend", property: "fontSize", visual: S.c1)
        env.editor.move([S.c1], dx: 40, dy: 24, snap: true)
        _ = try env.save()
        let actual = try env.reloaded(S.c1)
        #expect(actual.objects.bool("legend", "show") == true && actual.objects.number("legend", "fontSize") == 9)
        #expect(actual.fields.filter { $0.role == "Y" }.map(\.property) == ["Credit", "Debit", "Balance"])
        #expect(actual.x == 640 && actual.y == 128)
        // Đổi loại sau đó: khoá định dạng không dùng được bị bỏ, khoá còn dùng giữ.
        env.editor.setFormat(.bool(true), scope: .objects, object: "zoom", property: "show", visual: S.c1)
        let reason = env.editor.changeType(of: S.c1, to: "donutChart")
        try #require(reason == nil, "\(reason ?? "")")
        let second = try env.save(stamp: try FileStamp.of(env.source))
        #expect(second.didWrite)
        let donut = try env.reloaded(S.c1)
        #expect(donut.type == "donutChart" && donut.objects.has("legend") && !donut.objects.has("zoom"))
    }

    // MARK: (e) kiểm lúc lưu

    @Test func verifyLayoutAcceptsTheRealBuildAndCatchesDifferentFormat() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        let plain = try PBIXWriter.build(source: env.source, changes: PBIXChanges()).data
        do {
            try DocumentSaver.verifyLayout(plain, editor: env.editor)
            Issue.record("expected verificationFailed")
        } catch let error as SaveError {
            guard case .verificationFailed(let why) = error else { Issue.record("got \(error)"); return }
            #expect(why.contains(S.f1))
        }
        let good = try PBIXWriter.build(source: env.source, changes: try env.editor.makeChanges(archive: env.archive)).data
        try DocumentSaver.verifyLayout(good, editor: env.editor)
        // Cả khoá Chung cũng được so.
        env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: S.f2)
        #expect(throws: SaveError.self) { try DocumentSaver.verifyLayout(good, editor: env.editor) }
    }

    // MARK: (f), (g) lưu lần hai, hoàn tác về đã lưu

    @Test func aSecondSaveWithNothingNewWritesNothingAndUndoToSavedIsClean() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        let first = try env.save()
        #expect(first.didWrite && !env.editor.isDirty)
        let second = try env.save(stamp: first.newStamp)
        #expect(!second.didWrite)
        env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        #expect(env.editor.isDirty)
        env.editor.undo()
        #expect(!env.editor.isDirty)
        let third = try env.save(stamp: first.newStamp)
        #expect(!third.didWrite)
        #expect(try env.reloaded(S.f1).objects.number("labels", "fontSize") == 28)
    }

    // MARK: (h) bản sao

    @Test func copiesOfAFormattedVisualAndPageCarryTheFormatIntoTheFile() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: S.f1)
        env.editor.select(S.f1)
        let copy = try #require(env.editor.duplicate([S.f1]).first)
        let page = try #require(env.editor.duplicatePage("p1"))
        _ = try env.save()
        let savedCopy = try env.reloaded(copy)
        #expect(savedCopy.objects.number("labels", "fontSize") == 28 && savedCopy.containerObjects.bool("title", "show") == false)
        let report = try PBIXFile(url: env.source).loadReport()
        let pageCopies = try #require(report.pages.first { $0.id == page }).visuals.filter { $0.objects.number("labels", "fontSize") == 28 }
        #expect(!pageCopies.isEmpty)
    }
}
