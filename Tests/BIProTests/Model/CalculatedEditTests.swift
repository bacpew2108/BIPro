// Phase F, T116 (FR-060): sửa và xoá cột, bảng tính toán, trong phiên và trên file đã lưu. Đáp án tính tay trên bảng Sales 6 dòng:
// Qty 1, 2, 4, 5, 3, 2 (tổng 17), Price 2, 3, 1, 3, 2, 2, Region N, S, N, E, S, N. Qty × Price = 2, 6, 4, 15, 6, 4 (tổng 37, ba dòng ≥ 6);
// Qty × 10 = 10, 20, 40, 50, 30, 20 (tổng 170, cả sáu dòng ≥ 6).
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: sửa và xoá cột, bảng tính toán", .serialized) @MainActor struct CalculatedEditTests {
    private func sales() throws -> LoadedTable {
        LoadedTable(name: "Sales", data: try TableData(columns: [
            TableColumn(name: "Key", data: ColumnBuilder.integers([1, 2, 3, 4, 5, 6])),
            TableColumn(name: "Region", data: ColumnBuilder.strings(["N", "S", "N", "E", "S", "N"])),
            TableColumn(name: "Qty", data: ColumnBuilder.integers([1, 2, 4, 5, 3, 2])),
            TableColumn(name: "Price", data: ColumnBuilder.doubles([2, 3, 1, 3, 2, 2])),
        ]), status: .new)
    }

    private func document() async throws -> (DocumentState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("calc-edit-\(UUID().uuidString)", isDirectory: true)
        let url = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        state.editMode = true
        #expect(state.loadFromGetData([try sales()]) == nil)
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Doanh thu = Sales[Qty] * Sales[Price]") == nil)
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Lớn = IF(Sales[Doanh thu] >= 6, \"Có\", \"Không\")") == nil)
        return (state, root)
    }

    private func scalar(_ state: DocumentState, _ expression: String) async throws -> Value? {
        try await state.workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))").tables.first?.rows.first?.first
    }

    private func bigRows(_ state: DocumentState) async throws -> Value? {
        try await scalar(state, "COUNTROWS(FILTER(Sales, Sales[Lớn] = \"Có\"))")
    }

    @Test func suaCongThucTinhLaiCotPhuThuocVaHoanTac() async throws {
        let (state, root) = try await document(); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(state.workspace.metadata?.columns.first { $0.name == "Doanh thu" }?.id)
        let depth = state.layout.undoDepth
        #expect(await state.updateCalculatedColumn(table: "Sales", name: "Doanh thu", formula: "Doanh thu = Sales[Qty] * 10") == nil)
        #expect(state.layout.undoDepth == depth + 1)
        let column = try #require(state.workspace.metadata?.columns.first { $0.name == "Doanh thu" })
        #expect(column.id == id && column.dataType == .int64 && column.expression == "Sales[Qty] * 10")
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .integer(170))
        #expect(try await bigRows(state) == .integer(6))          // cột phụ thuộc tính lại

        state.layout.undo()
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .double(37))
        #expect(try await bigRows(state) == .integer(3))
        state.layout.redo()
        #expect(try await bigRows(state) == .integer(6))
    }

    @Test func doiTenQuaThanhCongThucVaChanTuThamChieuVaVong() async throws {
        let (state, root) = try await document(); defer { try? FileManager.default.removeItem(at: root) }
        let depth = state.layout.undoDepth
        #expect(await state.updateCalculatedColumn(table: "Sales", name: "Doanh thu", formula: "Doanh thu = [Doanh thu] + 1") != nil)
        // Vòng: Doanh thu dùng Lớn, mà Lớn dùng Doanh thu.
        let cycle = await state.updateCalculatedColumn(table: "Sales", name: "Doanh thu", formula: "Doanh thu = IF(Sales[Lớn] = \"Có\", 1, 0)")
        #expect(cycle?.contains("vòng") == true, Comment(rawValue: cycle ?? "nil"))
        // Đổi tên khi cột còn được dùng (cột Lớn dùng Doanh thu): chặn.
        #expect(await state.updateCalculatedColumn(table: "Sales", name: "Doanh thu", formula: "Thu = Sales[Qty]") != nil)
        #expect(state.layout.undoDepth == depth)
        // Cột không ai dùng: đổi tên và công thức cùng một bước.
        #expect(await state.updateCalculatedColumn(table: "Sales", name: "Lớn", formula: "Nhãn = Sales[Region] & \"!\"") == nil)
        #expect(state.layout.undoDepth == depth + 1)
        #expect(state.workspace.metadata?.columns.contains { $0.name == "Nhãn" && $0.expression == "Sales[Region] & \"!\"" } == true)
        #expect(try await scalar(state, "COUNTROWS(FILTER(Sales, Sales[Nhãn] = \"N!\"))") == .integer(3))
    }

    @Test func xoaCotTinhToanChanKhiConDungVaHoanTac() async throws {
        let (state, root) = try await document(); defer { try? FileManager.default.removeItem(at: root) }
        let blocked = state.deleteCalculatedColumn(table: "Sales", name: "Doanh thu")
        #expect(blocked?.contains("Lớn") == true, Comment(rawValue: blocked ?? "nil"))
        #expect(state.deleteCalculatedColumn(table: "Sales", name: "Qty") != nil)          // cột dữ liệu
        #expect(state.deleteCalculatedColumn(table: "Sales", name: "Lớn") == nil)
        #expect(state.deleteCalculatedColumn(table: "Sales", name: "Doanh thu") == nil)
        #expect(state.workspace.metadata?.columns.contains { $0.kind == .calculated } == false)
        state.layout.undo()
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .double(37))
        state.layout.undo()
        #expect(try await bigRows(state) == .integer(3))
    }

    @Test func suaVaXoaBangTinhToan() async throws {
        let (state, root) = try await document(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(await state.addCalculatedTable(formula: "Vùng = DISTINCT(Sales[Region])") == nil)
        #expect(await state.addCalculatedColumn(table: "Vùng", formula: "Trọng số = IF(Vùng[Region] = \"N\", 10, 1)") == nil)
        #expect(try await scalar(state, "SUM(Vùng[Trọng số])") == .integer(12))
        #expect(await state.updateCalculatedTable(name: "Vùng", formula: "Vùng = DISTINCT(Sales[Price])") != nil)  // cột Region mất mà còn dùng
        #expect(await state.updateCalculatedTable(name: "Vùng", formula: "Khác = DISTINCT(Sales[Region])") != nil)  // đổi tên chưa hỗ trợ
        let reason = await state.updateCalculatedTable(name: "Vùng", formula: "Vùng = FILTER(DISTINCT(Sales[Region]), Sales[Region] <> \"E\")")
        #expect(reason == nil, Comment(rawValue: reason ?? ""))
        #expect(try await scalar(state, "COUNTROWS(Vùng)") == .integer(2))
        #expect(try await scalar(state, "SUM(Vùng[Trọng số])") == .integer(11))   // cột trên bảng tính lại

        #expect(state.deleteCalculatedTable(name: "Sales") != nil)                 // bảng nạp
        #expect(state.deleteCalculatedTable(name: "Vùng") == nil)
        #expect(state.workspace.userTables.map(\.name) == ["Sales"])
        state.layout.undo()
        #expect(try await scalar(state, "COUNTROWS(Vùng)") == .integer(2))
    }

    @Test func thanhCongThucSuaCotDangChon() async throws {
        let (state, root) = try await document(); defer { try? FileManager.default.removeItem(at: root) }
        state.mode = .table
        state.select(table: "Sales", column: "Doanh thu")
        let draft = try #require(state.measureDraft)
        #expect(draft.mode == .editColumn(table: "Sales", name: "Doanh thu") && draft.text == "Doanh thu = Sales[Qty] * Sales[Price]")
        draft.text = "Doanh thu = Sales[Qty] * 10"
        await state.applyMeasureDraft()
        #expect(draft.message == nil && state.measureDraft === draft && !draft.isChanged)
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .integer(170))
        state.select(table: "Sales", column: "Qty")
        #expect(state.measureDraft == nil)                                           // cột dữ liệu: chỉ xem
    }

    @Test func luuSuaXoaTrenFileRoiMoLai() async throws {
        let (state, root) = try await document(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Bỏ = Sales[Qty] + 1") == nil)
        #expect(await state.addCalculatedTable(formula: "Vùng = DISTINCT(Sales[Region])") == nil)
        #expect(await state.addCalculatedTable(formula: "Tạm = DISTINCT(Sales[Key])") == nil)
        let source = try #require(state.fileURL)
        let file = root.appendingPathComponent("sua-xoa.pbix")
        let backups = root.appendingPathComponent("Backups")
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: source, to: file, readOnlyRoots: [], backupDirectory: backups).didWrite)

        // Mở lại: mọi mục giờ có sẵn trong file. Sửa công thức (cột phụ thuộc có sẵn tự tính lại và ghi lại), xoá cột, sửa và xoá bảng.
        let opened = DocumentState(workspace: try Workspace(data: Data(contentsOf: file)), fileName: file.lastPathComponent, fileURL: file)
        let ids = Dictionary(uniqueKeysWithValues: (opened.workspace.metadata?.columns ?? []).filter { $0.kind == .calculated }.map { ($0.name, $0.id) })
        #expect(await opened.updateCalculatedColumn(table: "Sales", name: "Doanh thu", formula: "Doanh thu = Sales[Qty] * 10") == nil)
        // Lưới Table view đọc giá trị mới của cột có sẵn trong file (đã sửa công thức).
        let grid = try #require(try opened.workspace.table("Sales").first { $0.name == "Doanh thu" })
        #expect((0..<grid.count).map { "\(grid[$0])" } == ["10", "20", "40", "50", "30", "20"])
        #expect(opened.deleteCalculatedColumn(table: "Sales", name: "Bỏ") == nil)
        #expect(await opened.updateCalculatedTable(name: "Vùng", formula: "Vùng = FILTER(DISTINCT(Sales[Region]), Sales[Region] <> \"E\")") == nil)
        #expect(opened.deleteCalculatedTable(name: "Tạm") == nil)
        #expect(try DocumentSaver.save(editor: opened.layout, source: file, to: file, expectedStamp: try FileStamp.of(file), readOnlyRoots: [],
                                       backupDirectory: backups).didWrite)

        let again = DocumentState(workspace: try Workspace(data: Data(contentsOf: file)), fileName: file.lastPathComponent, fileURL: file)
        let model = try #require(again.workspace.metadata)
        #expect(model.columns.first { $0.name == "Doanh thu" }?.id == ids["Doanh thu"])     // giữ ID cột như Desktop
        #expect(model.columns.first { $0.name == "Doanh thu" }?.expression == "Sales[Qty] * 10")
        #expect(model.columns.first { $0.name == "Lớn" }?.id == ids["Lớn"])
        #expect(model.columns.contains { $0.name == "Bỏ" } == false)
        #expect(model.userTables.map(\.name).sorted() == ["Sales", "Vùng"])
        #expect(model.calculatedTableExpressions["Vùng"] == "FILTER(DISTINCT(Sales[Region]), Sales[Region] <> \"E\")")
        // Cột kết quả giữ nguồn gốc cột mô hình: `SourceColumn` đủ bảng như Desktop (VM-F9b), không thì Desktop không đọc được bảng.
        #expect(model.columns.first { $0.tableName == "Vùng" && $0.kind == .calculatedTableColumn }?.sourceColumn == "Sales[Region]")
        #expect(again.workspace.runtime?.edits.isEmpty == true)
        #expect(try await scalar(again, "SUM(Sales[Doanh thu])") == .integer(170))           // đọc thẳng dữ liệu đã lưu
        #expect(try await bigRows(again) == .integer(6))
        #expect(try await scalar(again, "COUNTROWS(Vùng)") == .integer(2))
    }

    /// US4 (T050): cột tính toán làm khoá quan hệ, cấp phân cấp và cột sắp xếp: sửa công thức trên file đã lưu rồi lưu (bộ ghi dựng lại `R$`,
    /// `U$`), xoá thì hộp xác nhận liệt kê thứ bỏ kèm, một bước ⌘Z, lưu được, mở lại đúng.
    @Test func cotTinhToanTrongQuanHePhanCapSapXep() async throws {
        let (state, root) = try await document(); defer { try? FileManager.default.removeItem(at: root) }
        let dim = LoadedTable(name: "Nhom", data: try TableData(columns: [
            TableColumn(name: "K", data: ColumnBuilder.integers([0, 1, 2, 10, 11, 12])),
            TableColumn(name: "Ten", data: ColumnBuilder.strings(["Không", "Một", "Hai", "Mười", "Mười một", "Mười hai"])),
        ]), status: .new)
        #expect(state.loadFromGetData([dim]) == nil)
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Nhóm = MOD(Sales[Key], 3)") == nil)
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Nhãn = \"L\" & MOD(Sales[Key], 3)") == nil)
        #expect(state.modelEditor.apply([
            .addRelationship(NewRelationship(name: UUID().uuidString.lowercased(), fromTable: "Sales", fromColumn: "Nhóm", toTable: "Nhom", toColumn: "K")),
            .addHierarchy(NewHierarchy(table: "Sales", name: "Vùng nhóm", levels: [HierarchyLevel(name: "Vùng", column: "Region"),
                                                                                  HierarchyLevel(name: "Nhóm", column: "Nhóm")])),
            .updateColumn(table: "Sales", name: "Nhãn", patch: ColumnPatch(sortBy: .set("Nhóm"))),
        ]) == nil)
        let source = try #require(state.fileURL)
        let file = root.appendingPathComponent("us4.pbix")
        let backups = root.appendingPathComponent("Backups")
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: source, to: file, readOnlyRoots: [], backupDirectory: backups).didWrite)

        // Sửa công thức cột có sẵn trong file (giữ một–một với Nhãn): lưu được, quan hệ lọc theo dữ liệu mới.
        let opened = DocumentState(workspace: try Workspace(data: Data(contentsOf: file)), fileName: file.lastPathComponent, fileURL: file)
        #expect(await opened.updateCalculatedColumn(table: "Sales", name: "Nhóm", formula: "Nhóm = MOD(Sales[Key], 3) + 10") == nil)
        #expect(try DocumentSaver.save(editor: opened.layout, source: file, to: file, expectedStamp: try FileStamp.of(file), readOnlyRoots: [],
                                       backupDirectory: backups).didWrite)
        // Tệp gate VM-F13 (T052): sửa công thức xong, còn quan hệ, phân cấp, cột sắp xếp.
        let gate = try F2Fixtures.outputDirectory("f13")
        try? FileManager.default.removeItem(at: gate.appendingPathComponent("bipro-f13-sua.pbix"))
        try FileManager.default.copyItem(at: file, to: gate.appendingPathComponent("bipro-f13-sua.pbix"))
        let again = DocumentState(workspace: try Workspace(data: Data(contentsOf: file)), fileName: file.lastPathComponent, fileURL: file)
        #expect(again.workspace.metadata?.relationships.contains { $0.fromColumn == "Nhóm" && $0.toTable == "Nhom" } == true)
        // Key 1..6 → Nhóm 11, 12, 10, 11, 12, 10: "Mười" có Key 3 và 6 → Qty 4 + 2.
        #expect(try await scalar(again, "CALCULATE(SUM(Sales[Qty]), Nhom[Ten] = \"Mười\")") == .integer(6))

        // Xoá: hộp xác nhận nêu quan hệ, cấp phân cấp, cách sắp xếp; một bước ⌘Z.
        let cascade = again.deletionCascade(table: "Sales", name: "Nhóm")
        #expect(cascade.count == 3 && cascade.contains { $0.contains("quan hệ") } && cascade.contains { $0.contains("Vùng nhóm") }
                && cascade.contains { $0.contains("Nhãn") }, "\(cascade)")
        let depth = again.layout.undoDepth
        #expect(again.deleteCalculatedColumn(table: "Sales", name: "Nhóm") == nil)
        #expect(again.layout.undoDepth == depth + 1)
        var model = try #require(again.workspace.metadata)
        #expect(model.relationships.isEmpty && model.hierarchies.first { $0.name == "Vùng nhóm" }?.levels.map(\.columnName) == ["Region"])
        #expect(model.columns.first { $0.name == "Nhãn" }?.sortByColumnID == nil)
        again.layout.undo()
        model = try #require(again.workspace.metadata)
        #expect(model.relationships.count == 1 && model.hierarchies.first { $0.name == "Vùng nhóm" }?.levels.count == 2)
        again.layout.redo()
        #expect(try DocumentSaver.save(editor: again.layout, source: file, to: file, expectedStamp: try FileStamp.of(file), readOnlyRoots: [],
                                       backupDirectory: backups).didWrite)
        try? FileManager.default.removeItem(at: gate.appendingPathComponent("bipro-f13-xoa.pbix"))
        try FileManager.default.copyItem(at: file, to: gate.appendingPathComponent("bipro-f13-xoa.pbix"))
        let last = try #require(try Workspace(data: Data(contentsOf: file)).metadata)
        #expect(!last.columns.contains { $0.name == "Nhóm" } && last.relationships.isEmpty)
        #expect(last.hierarchies.first { $0.name == "Vùng nhóm" }?.levels.map(\.columnName) == ["Region"])
    }
}
