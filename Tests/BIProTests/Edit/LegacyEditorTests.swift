import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Sửa bố cục báo cáo định dạng cũ `Report/Layout` (D7, US4). Bản nhỏ dựng tay; file thật (Nhóm 2, Nhóm 3 trong `~/Downloads`,
/// chỉ đọc) được chép sang thư mục tạm trước khi sửa, bỏ qua khi file không có.
@Suite @MainActor struct LegacyEditorTests {
    nonisolated static func containerText(_ name: String, x: Int, y: Int, w: Int, h: Int, z: Int, parent: String? = nil) -> String {
        let extra = parent.map { #","parentGroupName":"\#($0)""# } ?? ""
        let config = #"{"name":"\#(name)","layouts":[{"id":0,"position":{"x":\#(x),"y":\#(y),"z":\#(z),"width":\#(w),"height":\#(h),"tabOrder":\#(z)}}],"singleVisual":{"visualType":"card"}\#(extra)}"#
        let escaped = config.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"x":\#(x),"y":\#(y),"z":\#(z),"width":\#(w),"height":\#(h),"config":"\#(escaped)","filters":"[]","tabOrder":\#(z)}"#
    }

    static let a = "aaaaaaaaaaaaaaaaaaaa", b = "bbbbbbbbbbbbbbbbbbbb", c = "cccccccccccccccccccc", k = "kkkkkkkkkkkkkkkkkkkk"

    nonisolated static func members() -> [(path: String, data: Data, method: UInt16)] {
        let containers = [containerText(a, x: 40, y: 40, w: 100, h: 50, z: 1000), containerText(b, x: 200, y: 40, w: 150, h: 80, z: 2000),
                          containerText(c, x: 400, y: 400, w: 100, h: 50, z: 3000), containerText(k, x: 10, y: 10, w: 20, h: 20, z: 4000, parent: "grp")].joined(separator: ",")
        let layout = #"{"id":0,"sections":[{"id":0,"name":"s1","displayName":"A","visualContainers":[\#(containers)],"width":1280,"height":720,"config":"{}"}],"config":"{}"}"#
        return [
            ("Version", Data("1.28".utf8), 0),
            ("[Content_Types].xml", Data("\u{FEFF}<?xml version=\"1.0\" encoding=\"utf-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"json\" ContentType=\"\" /><Override PartName=\"/SecurityBindings\" ContentType=\"\" /></Types>".utf8), 8),
            ("DataModel", Data((0..<3000).map { UInt8(truncatingIfNeeded: $0 &* 13) }), 0),
            ("Report/Layout", layout.data(using: .utf16LittleEndian)!, 8),
            ("SecurityBindings", Data([1, 2, 3]), 0),
        ]
    }

    @MainActor struct Env {
        let dir: URL, source: URL, archive: ZipArchive, editor: LayoutEditor
        init(from realFile: URL? = nil) throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-legacy-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            source = dir.appendingPathComponent("legacy.pbix")
            if let realFile {
                try FileManager.default.copyItem(at: realFile, to: source)
            } else {
                try ZipWriter.write(LegacyEditorTests.members().map { ($0.path, ZipWriter.Source.bytes($0.data, method: $0.method)) }, modified: nil).write(to: source)
            }
            archive = try ZipArchive(url: source)
            let report = try PBIXFile(url: source).loadReport()
            editor = LayoutEditor.readingLegacy(archive: archive, report: report)
            editor.showPage(report.pages.first?.id)
        }
        func save() throws -> SaveOutcome {
            try DocumentSaver.save(editor: editor, source: source, to: source, expectedStamp: nil, readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    @Test func movingAndResizingWritesOnlyTheLayoutPart() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.select(Self.a)
        e.move([Self.a], dx: 24, dy: 8, snap: false)
        e.apply(frames: [Self.b: Frame(x: 200, y: 40, width: 160, height: 80)])
        _ = try env.save()
        let report = try PBIXFile(url: env.source).loadReport()
        let page = try #require(report.pages.first)
        #expect(page.visuals.first { $0.id == Self.a }.map { Frame($0) } == Frame(x: 64, y: 48, width: 100, height: 50))
        #expect(page.visuals.first { $0.id == Self.b }?.width == 160)
        let after = try ZipArchive(url: env.source)
        #expect(after.entry("SecurityBindings") == nil)                                  // như D1 (R13)
        for entry in env.archive.entries where !["Report/Layout", "SecurityBindings", "[Content_Types].xml"].contains(entry.path) {
            #expect(try after.read(entry.path) == (try env.archive.read(entry.path)), Comment(rawValue: entry.path))
        }
        // lưu lần hai không ghi gì; hoàn tác về như cũ
        #expect(try env.save().didWrite == false)
        e.undo(); e.undo()
        #expect(e.isDirty == false || e.undoDepth == 0)
    }

    @Test func deleteDuplicateAndPasteAreWritten() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.delete([Self.c])
        let copy = try #require(e.duplicate([Self.a]).first)
        e.select(Self.b); e.copy()
        let pasted = try #require(e.paste().first)
        _ = try env.save()
        let page = try #require(try PBIXFile(url: env.source).loadReport().pages.first)
        let ids = Set(page.visuals.map(\.id))
        #expect(!ids.contains(Self.c) && ids.contains(copy) && ids.contains(pasted) && ids.contains(Self.k))
        let moved = try #require(page.visuals.first { $0.id == pasted })
        #expect(moved.x == 210 && moved.y == 50 && moved.z == 4001 || moved.x == 210)   // +10 mỗi lần dán
        // phần tử bị khoá do nhóm cũ nguyên byte
        let layout = try LegacyLayoutPatch.containers(in: try ZipArchive(url: env.source).read("Report/Layout"))
        let original = try LegacyLayoutPatch.containers(in: try env.archive.read("Report/Layout"))
        #expect(layout["s1"]?.first { $0.name == Self.k }?.json == original["s1"]?.first { $0.name == Self.k }?.json)
        #expect(layout["s1"]?.first { $0.name == Self.a }?.json == original["s1"]?.first { $0.name == Self.a }?.json)
    }

    @Test func childOfALegacyGroupIsLocked() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        #expect(e.isLockedByGroup(Self.k))
        e.move([Self.k], dx: 50, dy: 0, snap: false)
        #expect(e.visual(Self.k)?.x == 10 && e.undoDepth == 0)
    }

    @Test func nonLayoutEditsAreRefusedWithTheLegacyReason() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        #expect(e.insertVisual(type: "card", visibleRect: nil) == nil && e.fieldRefusal == LayoutEditor.legacyMessage)
        #expect(e.fieldEditingBlocker(for: Self.a) == LayoutEditor.legacyMessage)
        #expect(e.formatEditingBlocker(for: Self.a) == LayoutEditor.legacyMessage)
        #expect(e.changeType(of: Self.a, to: "slicer") == LayoutEditor.legacyMessage)
        #expect(e.undoDepth == 0)
    }

    @Test func alignWorksOnLegacy() throws {
        let env = try Env(); defer { env.cleanUp() }
        let e = env.editor
        e.setSelection([Self.a, Self.b, Self.c], extend: false)
        #expect(e.align(.left))
        _ = try env.save()
        let page = try #require(try PBIXFile(url: env.source).loadReport().pages.first)
        #expect(page.visuals.filter { [Self.a, Self.b, Self.c].contains($0.id) }.map(\.x) == [40, 40, 40])
    }

    @Test func realFilesSaveEditsThatOpenAgain() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = [home.appendingPathComponent("Downloads/Nhóm 2/Dashboard/Nhóm 2 - Financial Service .pbix"),
                     home.appendingPathComponent("Downloads/Nhóm 3 - DW&BI/Dashboard/dashboard_DW&BI_nhom_3_20252.pbix")]
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            let env = try Env(from: file); defer { env.cleanUp() }
            let e = env.editor
            let page = try #require(e.pages.first)
            let free = page.visuals.filter { !e.isLockedByGroup($0.id) }
            guard free.count >= 3 else { continue }
            let ids = Array(free.prefix(3).map(\.id))
            e.setSelection(ids, extend: false)
            e.move([ids[0]], dx: 16, dy: 8, snap: false)
            #expect(e.align(.left))
            e.delete([ids[2]])
            let copy = try #require(e.duplicate([ids[1]]).first)
            let before = e.visuals(of: page.id).count
            _ = try env.save()
            let reloaded = try #require(try PBIXFile(url: env.source).loadReport().pages.first)
            #expect(reloaded.visuals.count == before && reloaded.visuals.contains { $0.id == copy } && !reloaded.visuals.contains { $0.id == ids[2] })
            // các trang khác và phần không phải Layout nguyên byte
            let after = try ZipArchive(url: env.source)
            for entry in env.archive.entries where !["Report/Layout", "SecurityBindings", "[Content_Types].xml"].contains(entry.path) {
                #expect(try after.read(entry.path) == (try env.archive.read(entry.path)), Comment(rawValue: entry.path))
            }
        }
    }
}
