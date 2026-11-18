// T033: Tệp ▸ "Tuỳ chọn tệp" (Auto date/time, tự phát hiện quan hệ), mỗi tuỳ chọn một bước ⌘Z, lưu vào file.
import ColumnStore
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite struct FileOptionsTests {
    private func newDocument(_ root: URL) throws -> (DocumentState, URL) {
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        return (state, untitled)
    }

    private func dateTable(_ name: String) throws -> LoadedTable {
        // 45 658 = 1/1/2025.
        LoadedTable(name: name, data: try TableData(columns: [TableColumn(name: "Ngày", data: ColumnBuilder.dateTimes([45_658]))]))
    }

    @Test func taiLieuMoiBatCaHaiTuyChon() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fileopt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (state, _) = try newDocument(root)
        #expect(state.fileOptions == FileOptions(autoDateTime: true, autodetectRelationships: true))
        #expect(state.autoDateTimeBlocker == nil)
        // Nạp bảng có cột ngày: có bộ bảng ngày mà không cần bật gì.
        #expect(state.loadFromGetData([try dateTable("A")]) == nil)
        #expect(state.workspace.metadata?.variations.map(\.column) == ["Ngày"])
    }

    @Test func tatAutoDateRoiHoanTac() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fileopt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (state, _) = try newDocument(root)
        #expect(state.loadFromGetData([try dateTable("A")]) == nil)
        let depth = state.layout.undoDepth

        #expect(state.applyFileOptions(FileOptions(autoDateTime: false, autodetectRelationships: true)) == nil)
        #expect(state.layout.undoDepth == depth + 1)
        let off = try #require(state.workspace.metadata)
        #expect(off.variations.isEmpty && off.autoDateTables.isEmpty)
        #expect(state.fileOptions.autoDateTime == false)
        // Tắt rồi nạp bảng mới: không sinh bảng ngày.
        #expect(state.loadFromGetData([try dateTable("B")]) == nil)
        #expect(state.workspace.metadata?.variations.isEmpty == true)

        state.layout.undo()
        state.layout.undo()
        #expect(state.fileOptions.autoDateTime)
        #expect(state.workspace.metadata?.variations.map(\.column) == ["Ngày"])
        // OK không đổi gì thì không tạo bước.
        #expect(state.applyFileOptions(state.fileOptions) == nil)
        #expect(state.layout.undoDepth == depth)
    }

    @Test func tuPhatHienQuanHeLuuVaoSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fileopt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (state, untitled) = try newDocument(root)
        let backups = root.appendingPathComponent("Backups")

        #expect(state.applyFileOptions(FileOptions(autoDateTime: true, autodetectRelationships: false)) == nil)
        #expect(state.layout.isDirty)
        #expect(state.fileOptions.autodetectRelationships == false)
        state.layout.undo()
        #expect(state.fileOptions.autodetectRelationships)
        #expect(!state.layout.isDirty)
        state.layout.redo()

        let destination = root.appendingPathComponent("opt.pbix")
        let first = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [], backupDirectory: backups)
        #expect(first.didWrite)
        let saved = try ZipArchive(url: destination)
        #expect(!FileSettings.autodetectRelationships(in: try saved.read(FileSettings.path)))
        // Phần còn lại của Settings giữ nguyên.
        let before = FileSettings.decode(try ZipArchive(url: untitled).read(FileSettings.path))
        #expect(FileSettings.decode(try saved.read(FileSettings.path)) == before.replacingOccurrences(
            of: "\"ReportSettings\":{}", with: "\"ReportSettings\":{\"IsRelationshipAutodetectionEnabled\":false}"))

        let reopened = DocumentState(workspace: try Workspace(data: Data(contentsOf: destination)), fileName: "opt.pbix", fileURL: destination)
        #expect(reopened.fileOptions.autodetectRelationships == false)
        // Để lại cho gate VM-F11: Desktop mở file thấy ô Autodetect tắt.
        let gate = try F2Fixtures.outputDirectory("f11").appendingPathComponent("bipro-noauto.pbix")
        try? FileManager.default.removeItem(at: gate)
        try FileManager.default.copyItem(at: destination, to: gate)

        // Hoàn tác sau khi lưu rồi lưu lại: file về bật.
        state.layout.undo()
        #expect(state.layout.isDirty)
        let second = try DocumentSaver.save(editor: state.layout, source: destination, to: destination, expectedStamp: first.newStamp,
                                            readOnlyRoots: [], backupDirectory: backups)
        #expect(second.didWrite)
        #expect(FileSettings.autodetectRelationships(in: try ZipArchive(url: destination).read(FileSettings.path)))
    }
}
