import CoreGraphics
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Lưu visual mới và visual đã đổi loại (D3): `contracts/visual-json-patches.md`.
@Suite @MainActor struct NewVisualSavingTests {
    typealias S = SyntheticReport
    typealias Env = FieldSavingTests.Env
    static let view = CGRect(x: 0, y: 0, width: 1000, height: 600)
    static let net = FieldRef(kind: .measure, entity: "Fact", property: "Net")

    func path(_ id: String) -> String { LayoutEditor.visualPath(page: "p1", id: id) }

    // MARK: visual mới

    @Test func newVisualsBecomeAddedPartsAfterTheLastVisualOfThePage() throws {
        let env = try Env(); defer { env.cleanUp() }
        let card = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        let chart = try #require(env.editor.insertVisual(type: "clusteredBarChart", visibleRect: Self.view))
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.addedParts.keys) == [path(card), path(chart)])
        #expect(changes.reportParts.isEmpty && changes.removedParts.isEmpty)
        _ = try env.save()
        let archive = try ZipArchive(url: env.source)
        let paths = archive.entries.map(\.path)
        let lastOld = try #require(paths.lastIndex { $0.hasPrefix("Report/definition/pages/p1/visuals/") && !$0.contains(card) && !$0.contains(chart) })
        #expect(paths[lastOld + 1].contains("/visuals/") && Set([card, chart]).contains(where: { paths[lastOld + 1].contains($0) }))
        #expect(archive.entry("SecurityBindings") == nil)
    }

    @Test func savedNewVisualsReadBackWithTypeFrameAndFields() throws {
        let env = try Env(); defer { env.cleanUp() }
        let card = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        #expect(env.editor.addField(Self.net, to: "Values", visual: card) == nil)
        let bar = try #require(env.editor.insertVisual(type: "clusteredBarChart", visibleRect: Self.view))
        env.editor.addField(FieldRef(kind: .column, entity: "Dim_Date", property: "month_name", family: .text), to: "Category", visual: bar)
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Credit"), to: "Y", visual: bar)
        let empty = try #require(env.editor.insertVisual(type: "slicer", visibleRect: Self.view))
        _ = try env.save()
        for id in [card, bar, empty] {
            let expected = try #require(env.editor.visual(id)), actual = try env.reloaded(id)
            #expect(actual.type == expected.type, Comment(rawValue: id))
            #expect(Frame(actual) == Frame(expected) && Int(actual.z) == Int(expected.z), Comment(rawValue: id))
            #expect(actual.fields == expected.fields, Comment(rawValue: id))
        }
        // visual mới chưa có trường vẫn được ghi, không có query
        let raw = try ZipArchive(url: env.source).read(path(empty))
        #expect(!String(decoding: raw, as: UTF8.self).contains("queryState"))
        #expect(try env.reloaded(empty).type == "slicer")
    }

    @Test func addedThenDeletedBeforeSavingLeavesNothing() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        env.editor.delete([id])
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(changes.addedParts.isEmpty && changes.reportParts.isEmpty && changes.removedParts.isEmpty)
    }

    // MARK: visual đã đổi loại

    @Test func retypedFileVisualWritesTypeQueryStateAndObjectsOnly() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = try env.archive.read(path(S.c1))
        #expect(env.editor.changeType(of: S.c1, to: "lineChart") == nil)
        let changes = try env.editor.makeChanges(archive: env.archive)
        #expect(Set(changes.reportParts.keys) == [path(S.c1)] && changes.addedParts.isEmpty)
        _ = try env.save()
        let actual = try env.reloaded()
        #expect(actual.type == "lineChart" && actual.fields == env.editor.visual(S.c1)?.fields)
        #expect(actual.fields.filter { $0.role == "Y" }.map(\.property) == ["Credit", "Debit", "Net"])
        // Ngoài visualType và queryState, visual.json giữ nguyên.
        let after = try ZipArchive(url: env.source).read(path(S.c1))
        func stripped(_ data: Data) throws -> NSDictionary {
            var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var visual = root["visual"] as! [String: Any]
            visual["visualType"] = nil
            var query = visual["query"] as! [String: Any]
            query["queryState"] = nil
            visual["query"] = query
            root["visual"] = visual
            return root as NSDictionary
        }
        #expect(try stripped(before) == stripped(after))
    }

    @Test func retypeThenMoveThenFieldEditThenSaveTwice() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.changeType(of: S.c1, to: "clusteredBarChart")
        env.editor.move([S.c1], dx: 40, dy: 24, snap: true)
        var outcome = try env.save()
        var actual = try env.reloaded()
        #expect(actual.type == "clusteredBarChart" && actual.x == 640 && actual.y == 128)
        // Lần hai: đổi loại tiếp, thêm trường, thêm visual mới.
        env.editor.changeType(of: S.c1, to: "lineChart")
        env.editor.addField(Self.net, to: "Tooltips", visual: S.c1)
        let card = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        env.editor.addField(Self.net, to: "Values", visual: card)
        outcome = try env.save(stamp: outcome.newStamp)
        #expect(outcome.didWrite)
        actual = try env.reloaded()
        #expect(actual.type == "lineChart" && actual.fields == env.editor.visual(S.c1)?.fields)
        #expect(try env.reloaded(card).fields == env.editor.visual(card)?.fields)
        // Lần ba: sửa thêm visual mới đã lưu.
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Credit"), to: "Values", visual: card)   // đã có Net: thay (ô một trường)
        _ = try env.save(stamp: outcome.newStamp)
        #expect(try env.reloaded(card).fields.map(\.property) == ["Credit"])
    }

    // MARK: kiểm lại khi lưu

    @Test func verifyLayoutCatchesATypeThatDiffersFromTheEditor() throws {
        let env = try Env(); defer { env.cleanUp() }
        let plain = try PBIXWriter.build(source: env.source, changes: PBIXChanges()).data
        env.editor.changeType(of: S.c1, to: "lineChart")
        do {
            try DocumentSaver.verifyLayout(plain, editor: env.editor)
            Issue.record("expected verificationFailed")
        } catch let error as SaveError {
            guard case .verificationFailed(let why) = error else { Issue.record("got \(error)"); return }
            #expect(why.contains(S.c1))
        }
        let good = try PBIXWriter.build(source: env.source, changes: try env.editor.makeChanges(archive: env.archive)).data
        try DocumentSaver.verifyLayout(good, editor: env.editor)
        // visual mới có trong editor mà thiếu trong bytes: bị bắt (đã có từ D1)
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: Self.view))
        #expect(throws: SaveError.self) { try DocumentSaver.verifyLayout(good, editor: env.editor) }
        _ = id
    }

    @Test func aNewVisualThatWasSavedThenRetypedIsRewrittenOnTheSecondSave() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "lineChart", visibleRect: Self.view))
        env.editor.addField(FieldRef(kind: .column, entity: "Dim_Date", property: "month_name", family: .text), to: "Category", visual: id)
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Credit"), to: "Y", visual: id)
        var outcome = try env.save()
        #expect(try env.reloaded(id).type == "lineChart")
        #expect(env.editor.changeType(of: id, to: "clusteredBarChart") == nil)
        env.editor.addField(Self.net, to: "Tooltips", visual: id)
        outcome = try env.save(stamp: outcome.newStamp)
        let actual = try env.reloaded(id)
        #expect(actual.type == "clusteredBarChart" && actual.fields == env.editor.visual(id)?.fields)
        // ba lần liên tiếp: không đổi gì thì không ghi lại gì
        let again = try env.editor.makeChanges(archive: try ZipArchive(url: env.source))
        #expect(again.reportParts.isEmpty && again.addedParts.isEmpty)
        _ = outcome
    }
}

