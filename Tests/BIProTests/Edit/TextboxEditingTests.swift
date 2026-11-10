import CoreGraphics
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Hộp văn bản (D3): thêm, sửa nội dung, hoàn tác, lưu.
@Suite @MainActor struct TextboxEditingTests {
    typealias S = SyntheticReport
    typealias Env = FieldSavingTests.Env
    static let view = CGRect(x: 0, y: 0, width: 1000, height: 600)

    /// Hộp văn bản có sẵn trong file (id của `chartJSON` mẫu), hai đoạn có kiểu chữ.
    static let styled = Data(##"{"name":"\##(S.c1)","position":{"x":0,"y":0,"z":4000,"height":88,"width":1920,"tabOrder":4000},"visual":{"visualType":"textbox","objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":"Tiêu đề","textStyle":{"fontWeight":"bold","color":"#FFFFFF"}}],"horizontalTextAlignment":"center"},{"textRuns":[{"value":"Phụ đề","textStyle":{"fontSize":"10pt"}}]}]}}]}}}"##.utf8)

    func lines(_ editor: LayoutEditor, _ id: String) -> [String] {
        editor.visual(id).map { LayoutEditor.paragraphTexts(of: $0.raw) } ?? []
    }

    @Test func aNewTextboxHasOneDefaultParagraphReadFromObjects() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "textbox", visibleRect: Self.view))
        #expect(lines(env.editor, id) == ["Hộp văn bản"])
        // Hộp văn bản vẽ từ `objects`, không từ `raw`.
        let paragraphs = env.editor.visual(id)?.objects.raw("general", "paragraphs")?.array ?? []
        #expect(paragraphs.count == 1 && paragraphs[0]["textRuns"]?[0]?["value"]?.string == "Hộp văn bản")
        let visual = try #require(env.editor.visual(id))
        #expect(visual.width == 400 && visual.height == 100)
    }

    @Test func setTextUpdatesObjectsAndRawAsOneUndoStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "textbox", visibleRect: Self.view))
        let depth = env.editor.undoDepth
        #expect(env.editor.setText("Tiêu đề\nDòng hai", visual: id) == nil)
        #expect(lines(env.editor, id) == ["Tiêu đề", "Dòng hai"])
        let paragraphs = env.editor.visual(id)?.objects.raw("general", "paragraphs")?.array ?? []
        #expect(paragraphs.map { $0["textRuns"]?[0]?["value"]?.string } == ["Tiêu đề", "Dòng hai"])
        #expect(env.editor.undoDepth == depth + 1)
        env.editor.undo()
        #expect(lines(env.editor, id) == ["Hộp văn bản"])
        env.editor.redo()
        #expect(lines(env.editor, id) == ["Tiêu đề", "Dòng hai"])
        // cùng nội dung: không tạo bước
        let after = env.editor.undoDepth
        #expect(env.editor.setText("Tiêu đề\nDòng hai", visual: id) == nil)
        #expect(env.editor.undoDepth == after)
    }

    @Test func existingTextboxKeepsStylesAndSavesBackToTheFile() throws {
        let dir = S.temporaryDirectory("textbox"); defer { try? FileManager.default.removeItem(at: dir) }
        let env = try FieldEditingTests.Env(chart: Self.styled)
        defer { env.cleanUp() }
        #expect(env.editor.setText("Tiêu đề mới\nPhụ đề", visual: S.c1) == nil)
        #expect(lines(env.editor, S.c1) == ["Tiêu đề mới", "Phụ đề"])
        let changes = try env.editor.makeChanges(archive: env.archive)
        let path = LayoutEditor.visualPath(page: "p1", id: S.c1)
        let written = String(decoding: try #require(changes.reportParts[path]), as: UTF8.self)
        #expect(written.contains(##"{"value":"Tiêu đề mới","textStyle":{"fontWeight":"bold","color":"#FFFFFF"}}"##))
        #expect(written.contains(##""horizontalTextAlignment":"center""##) && written.contains("Phụ đề"))
        #expect(Set(changes.reportParts.keys) == [path])
    }

    @Test func savedTextReadsBackForNewAndExistingTextboxes() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "textbox", visibleRect: Self.view))
        env.editor.setText("Một\nHai\nBa", visual: id)
        _ = try env.save()
        #expect(LayoutEditor.paragraphTexts(of: try env.reloaded(id).raw) == ["Một", "Hai", "Ba"])
        // sửa tiếp visual mới đã lưu, lưu lần hai
        env.editor.setText("Chỉ một", visual: id)
        _ = try env.save(stamp: try FileStamp.of(env.source))
        #expect(LayoutEditor.paragraphTexts(of: try env.reloaded(id).raw) == ["Chỉ một"])
    }

    @Test func nonTextboxesAndMissingVisualsAreRefused() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.setText("x", visual: S.c1) != nil)
        #expect(env.editor.setText("x", visual: "zzzzzzzzzzzzzzzzzzzz") != nil)
        #expect(env.editor.undoDepth == depth)
    }

    @Test func verifyLayoutChecksTheText() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "textbox", visibleRect: Self.view))
        let good = try PBIXWriter.build(source: env.source, changes: try env.editor.makeChanges(archive: env.archive)).data
        env.editor.setText("Khác", visual: id)
        #expect(throws: SaveError.self) { try DocumentSaver.verifyLayout(good, editor: env.editor) }
        let better = try PBIXWriter.build(source: env.source, changes: try env.editor.makeChanges(archive: env.archive)).data
        try DocumentSaver.verifyLayout(better, editor: env.editor)
    }
}
