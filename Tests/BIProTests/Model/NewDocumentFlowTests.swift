// Phase F, T077 (US5, FR-053): "File → Mới" tạo tài liệu trống trong thư mục tạm riêng, mở như file thường; lần lưu đầu ghi ra
// nơi người dùng chọn kể cả khi chưa sửa gì, rồi mở lại được. Seam: `UntitledDocuments`, `DocumentState`, `DocumentSaver.saveUntitled`.
import ColumnStore
import Connectors
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: tài liệu mới", .serialized) @MainActor struct NewDocumentFlowTests {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("newdoc-flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func state(_ url: URL) throws -> DocumentState {
        DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
    }

    @Test func taiLieuMoiTrongCoMotTrangVaNapDuocDuLieu() throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try UntitledDocuments.create(root: root)
        #expect(url.lastPathComponent == "Không tên.pbix")
        #expect(url.path.hasPrefix(root.path))
        let state = try state(url)
        #expect(state.workspace.userTables.isEmpty)
        #expect(state.workspace.visiblePages.map(\.displayName) == ["Page 1"])
        #expect(state.getDataBlocker == nil)
        #expect(!state.layout.isDirty)
    }

    @Test func taiLieuMoiLuonHoiNoiLuuLanDau() throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try UntitledDocuments.create(root: root), b = try UntitledDocuments.create(root: root)
        #expect(a != b)
        #expect(UntitledDocuments.isUntitled(a, root: root) && UntitledDocuments.isUntitled(b, root: root))
        let other = try scratch(); defer { try? FileManager.default.removeItem(at: other) }
        let saved = other.appendingPathComponent("da-luu.pbix")
        try FileManager.default.copyItem(at: a, to: saved)
        #expect(!UntitledDocuments.isUntitled(saved, root: root))
        UntitledDocuments.discard(a, root: root)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
        #expect(!UntitledDocuments.isUntitled(nil, root: root))
    }

    @Test func taiLieuTrongChuaSuaVanLuuDuocVaMoLaiDuoc() throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try UntitledDocuments.create(root: root)
        let state = try state(url)
        let destination = root.appendingPathComponent("bao-cao-moi.pbix")
        let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: url, to: destination, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
        #expect(outcome.didWrite)
        let reopened = try self.state(destination)
        #expect(reopened.workspace.userTables.isEmpty)
        #expect(reopened.workspace.visiblePages.count == 1)
    }

    @Test(.enabled(if: FFixtures.sample("sales_100.csv") != nil)) func napBangRoiLuuLanDauDocLaiDungSoDong() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try UntitledDocuments.create(root: root)
        let state = try state(url)
        let csv = try #require(FFixtures.sample("sales_100.csv"))
        state.showGetData(kind: .csv, pickFile: { _ in csv.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        #expect(state.loadFromGetData(loaded) == nil)
        state.closeGetData()
        #expect(state.layout.isDirty)

        let destination = root.appendingPathComponent("mot-bang.pbix")
        let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: url, to: destination, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
        #expect(outcome.didWrite)
        let reopened = try self.state(destination)
        #expect(reopened.workspace.userTables.map(\.name) == ["sales_100"])
        #expect(reopened.workspace.rowCount("sales_100") == 100)
        #expect(reopened.workspace.metadata?.modelAnnotations["PBI_QueryOrder"] == #"["sales_100"]"#)
        // Bản tạm không bị ghi đè: vẫn là tài liệu trống.
        #expect(try Workspace(data: Data(contentsOf: url)).userTables.isEmpty)
    }
}
