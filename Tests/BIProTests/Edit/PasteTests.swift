import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Chép dán (D7, US2): vị trí và `z` theo Power BI Desktop (VM-D7 §6).
@Suite @MainActor struct PasteTests {
    typealias Env = PageSavingTests.Env
    typealias S = SyntheticReport

    @Test func pasteOnAnotherPageMovesTheSourceByTenPoints() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.select(S.a1)                         // 40,40, z 1000
        e.copy()
        e.showPage("p2")                       // b1 ở z 1000
        let first = try #require(e.paste().first)
        let a = try #require(e.visual(first))
        #expect(a.x == 50 && a.y == 50 && a.z == 1001 && a.parentGroup == nil)
        let second = try #require(e.paste().first)
        let b = try #require(e.visual(second))
        #expect(b.x == 60 && b.y == 60 && b.z == 1002)
        #expect(e.selection == [second] && e.undoDepth == 2)
        #expect(e.visuals(of: "p1").count == 3, "trang nguồn không đổi")
    }

    @Test func theCopyHasEveryPartOfTheSourceExceptNameAndPosition() throws {
        let env = try Env(extra: SyntheticReport.formatExtras); defer { env.cleanUp() }
        let e = env.editor
        e.select(S.f1)
        e.copy()
        e.showPage("p2")
        let id = try #require(e.paste().first)
        let changes = try e.makeChanges(archive: env.archive)
        let copy = try #require(changes.addedParts[LayoutEditor.visualPath(page: "p2", id: id)])
        let source = try env.archive.read(LayoutEditor.visualPath(page: "p1", id: S.f1))
        func parse(_ d: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: d) as! [String: Any] }
        var a = try parse(source), b = try parse(copy)
        #expect(b["visual"] as? NSDictionary == a["visual"] as? NSDictionary)
        a["name"] = nil; a["position"] = nil; b["name"] = nil; b["position"] = nil
        #expect((a as NSDictionary).isEqual(to: b))
        // trang nguồn nguyên byte sau khi lưu
        _ = try env.save()
        #expect(try ZipArchive(url: env.source).read(LayoutEditor.visualPath(page: "p1", id: S.f1)) == source)
    }

    @Test func pastingAGroupBringsItsChildren() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([S.a1, S.a2], extend: false)
        let group = try #require(e.group())
        e.copy()
        e.showPage("p2")
        let pasted = e.paste()
        #expect(pasted.count == 1 && pasted[0] != group)
        #expect(e.groups(of: "p2").count == 1 && e.children(ofGroup: pasted[0]).count == 2)
        _ = try env.save()
        let report = try env.report()
        let p2 = try #require(report.pages.first { $0.id == "p2" })
        #expect(p2.groups.count == 1 && p2.visuals.filter { $0.parentGroup == pasted[0] }.count == 2)
    }

    @Test func duplicateKeepsTheD1Rule() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        let id = try #require(e.duplicate([S.a1]).first)
        #expect(e.visual(id)?.x == 56 && e.visual(id)?.z == 4000)
    }
}
