// Lỗi T096 (`/code-review`): ở lần lưu thứ hai trở đi `modelDelta` đặt `dropTable` (thao tác bảng) trước phần so mô hình
// (`deleteMeasure`, `deleteRelationship`), mà bộ ghi từ chối xoá bảng còn measure/quan hệ, nên lưu hỏng sau chuỗi thêm → lưu → xoá → lưu.
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite(.enabled(if: FFixtures.sample("sales_100.csv") != nil), .serialized) @MainActor
struct SecondSaveDropTableTests {
    @Test func xoaMeasureRoiXoaBangLuuLanHaiDuoc() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ss-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        let csv = try #require(FFixtures.sample("sales_100.csv"))
        state.showGetData(kind: .csv, pickFile: { _ in csv.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items { navigator.toggle(item.id) }
        #expect(state.loadFromGetData(try #require(await navigator.load(existingNames: state.existingTableNames))) == nil)
        state.closeGetData()
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "sales_100", name: "Số dòng", expression: "COUNTROWS(sales_100)"))) == nil)

        let destination = root.appendingPathComponent("a.pbix")
        let first = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                   backupDirectory: root.appendingPathComponent("Backups"))
        #expect(first.didWrite)

        #expect(state.modelEditor.apply(.deleteMeasure(table: "sales_100", name: "Số dòng")) == nil)
        #expect(state.modelEditor.apply(.dropTable(name: "sales_100")) == nil)
        let second = try DocumentSaver.save(editor: state.layout, source: destination, to: destination, expectedStamp: first.newStamp,
                                            readOnlyRoots: [], backupDirectory: root.appendingPathComponent("Backups"))
        #expect(second.didWrite)
        #expect(try Workspace(data: Data(contentsOf: destination)).userTables.isEmpty)
    }
}
