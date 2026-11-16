// Phase F, T082 (US6): cột và bảng tính toán trong phiên, trên tài liệu mới có một bảng nạp tay. Đáp án là ví dụ tính tay:
// Sales = 6 dòng, Qty × Price = 2, 6, 4, 15, 6, 4 (tổng 37), Region N, S, N, E, S, N (3 vùng).
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: cột và bảng tính toán trong phiên", .serialized) @MainActor struct CalculatedTests {
    private func sales(qty: [Int64] = [1, 2, 4, 5, 3, 2], regions: [String] = ["N", "S", "N", "E", "S", "N"],
                       price: [Double]? = [2, 3, 1, 3, 2, 2], status: LoadedTable.Status = .new) throws -> LoadedTable {
        var columns = [TableColumn(name: "Key", data: ColumnBuilder.integers((1...Int64(qty.count)).map { $0 })),
                       TableColumn(name: "Region", data: ColumnBuilder.strings(regions)),
                       TableColumn(name: "Qty", data: ColumnBuilder.integers(qty))]
        if let price { columns.append(TableColumn(name: "Price", data: ColumnBuilder.doubles(price))) }
        return LoadedTable(name: "Sales", data: try TableData(columns: columns), status: status)
    }

    private func document() throws -> (DocumentState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("calc-\(UUID().uuidString)", isDirectory: true)
        let url = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        #expect(state.loadFromGetData([try sales()]) == nil)
        return (state, root)
    }

    private func scalar(_ state: DocumentState, _ expression: String) async throws -> Value? {
        try await state.workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))").tables.first?.rows.first?.first
    }

    @Test func cotTinhToanTinhDungHoanTacVaLamLai() async throws {
        let (state, root) = try document(); defer { try? FileManager.default.removeItem(at: root) }
        let before = state.layout.undoDepth
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Doanh thu = Sales[Qty] * Sales[Price]") == nil)
        #expect(state.layout.undoDepth == before + 1)
        let column = try #require(state.workspace.metadata?.columns.first { $0.tableName == "Sales" && $0.name == "Doanh thu" })
        #expect(column.kind == .calculated && column.dataType == .double)
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .double(37))
        #expect(state.workspace.runtime?.calculationErrors.isEmpty == true)

        state.layout.undo()
        #expect(state.workspace.metadata?.columns.contains { $0.name == "Doanh thu" } == false)
        state.layout.redo()
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .double(37))
    }

    @Test func cotPhuThuocCotTinhToanVaKieuSuyRa() async throws {
        let (state, root) = try document(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Doanh thu = Sales[Qty] * Sales[Price]") == nil)
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Lớn = IF(Sales[Doanh thu] >= 6, \"Có\", \"Không\")") == nil)
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "[Gấp đôi] = Sales[Qty] * 2") == nil)
        let columns = state.workspace.metadata?.columns.filter { $0.tableName == "Sales" && $0.kind == .calculated } ?? []
        #expect(columns.map(\.name) == ["Doanh thu", "Lớn", "Gấp đôi"])
        #expect(columns.map(\.dataType) == [.double, .string, .int64])
        #expect(try await scalar(state, "COUNTROWS(FILTER(Sales, Sales[Lớn] = \"Có\"))") == .integer(3))
        #expect(try await scalar(state, "SUM(Sales[Gấp đôi])") == .integer(34))
    }

    @Test func bieuThucSaiTenTrungKieuLanBiTuChoiKhongDoiGi() async throws {
        let (state, root) = try document(); defer { try? FileManager.default.removeItem(at: root) }
        let depth = state.layout.undoDepth
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "X = Sales[Không có]") != nil)
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Qty = 1") != nil)                       // trùng cột
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Y = IF(Sales[Qty] > 2, 1, \"a\")") != nil) // nhiều kiểu
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "chỉ có biểu thức") != nil)
        #expect(state.layout.undoDepth == depth)
        #expect(state.workspace.metadata?.columns.contains { $0.kind == .calculated } == false)
    }

    @Test func bangTinhToanVaCotTrenBangDo() async throws {
        let (state, root) = try document(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(await state.addCalculatedTable(formula: "Vùng = DISTINCT(Sales[Region])") == nil)
        #expect(state.workspace.userTables.map(\.name) == ["Sales", "Vùng"])
        let columns = state.workspace.columns(of: "Vùng")
        #expect(columns.map(\.name) == ["Region"] && columns.first?.kind == .calculatedTableColumn)
        #expect(try await scalar(state, "COUNTROWS(Vùng)") == .integer(3))
        let reason = await state.addCalculatedColumn(table: "Vùng", formula: "Trọng số = IF(Vùng[Region] = \"N\", 10, 1)")
        #expect(reason == nil, Comment(rawValue: reason ?? ""))
        let total = try await scalar(state, "SUM(Vùng[Trọng số])")
        #expect(total == .integer(12), Comment(rawValue: "\(String(describing: total)) lỗi: \(state.workspace.runtime?.calculationErrors ?? [:])"))
    }

    @Test func nguonDoiThiTinhLaiCotMatThiChanVaBaoDanhSach() async throws {
        let (state, root) = try document(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Doanh thu = Sales[Qty] * Sales[Price]") == nil)
        // Nạp lại còn đủ cột, ít dòng hơn: cột tính toán tính lại theo dữ liệu mới.
        #expect(state.loadFromGetData([try sales(qty: [10, 1], regions: ["N", "S"], price: [2, 5], status: .replaced)]) == nil)
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .double(25))
        // Nạp lại mất cột Price mà cột tính toán dùng: bị chặn, báo tên cột tính toán.
        let reason = state.loadFromGetData([try sales(qty: [1], regions: ["N"], price: nil, status: .replaced)])
        #expect(reason?.contains("Price") == true && reason?.contains("Doanh thu") == true)
        #expect(try await scalar(state, "SUM(Sales[Doanh thu])") == .double(25))
    }

    @Test func thanhCongThucCotMoiBangMoiVaTableView() async throws {
        let (state, root) = try document(); defer { try? FileManager.default.removeItem(at: root) }
        state.mode = .report
        state.editMode = false
        #expect(state.newColumnBlocker != nil)                 // chế độ Báo cáo chưa bật Sửa
        state.editMode = true
        state.beginNewColumn(table: "Sales")
        #expect(state.mode == .table)
        let draft = try #require(state.measureDraft)
        #expect(draft.text == "Cột = ")
        draft.text = "Doanh thu = Sales[Qty] * Sales[Price]"
        await state.applyMeasureDraft()
        #expect(state.measureDraft == nil && state.column == "Doanh thu")
        let decoded = try #require(try state.workspace.table("Sales").first { $0.name == "Doanh thu" })
        let total = (0..<decoded.count).reduce(0.0) { sum, row in
            if case .double(let d) = decoded[row] { return sum + d }
            return sum
        }
        #expect(decoded.count == 6 && total == 37)

        state.beginNewTable()
        let tableDraft = try #require(state.measureDraft)
        #expect(tableDraft.text == "Bảng = ")
        tableDraft.text = "Vùng = DISTINCT(Sales[Region])"
        await state.applyMeasureDraft()
        #expect(state.measureDraft == nil && state.table == "Vùng")
        #expect(state.workspace.rowCount("Vùng") == 3)
        #expect(Set(try state.workspace.table("Vùng").first.map { c in (0..<c.count).map { "\(c[$0])" } } ?? []).count == 3)

        // Lỗi thì bản nháp ở lại và báo lý do.
        state.beginNewColumn(table: "Sales")
        state.measureDraft?.text = "Hỏng = Sales[Không có]"
        await state.applyMeasureDraft()
        #expect(state.measureDraft?.message != nil)
    }

    @Test func luuRoiMoLaiDocGiaTriDaLuuVaThemTiepTrenBangCuaFile() async throws {
        let (state, root) = try document(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(await state.addCalculatedColumn(table: "Sales", formula: "Doanh thu = Sales[Qty] * Sales[Price]") == nil)
        #expect(await state.addCalculatedTable(formula: "Vùng = DISTINCT(Sales[Region])") == nil)
        #expect(await state.addCalculatedColumn(table: "Vùng", formula: "Trọng số = IF(Vùng[Region] = \"N\", 10, 1)") == nil)
        let source = try #require(state.fileURL)
        let first = root.appendingPathComponent("tinh-toan.pbix")
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: source, to: first, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)

        // Mở lại: không có thao tác nào, giá trị đọc thẳng từ dữ liệu đã lưu.
        let reopened = DocumentState(workspace: try Workspace(data: Data(contentsOf: first)), fileName: first.lastPathComponent, fileURL: first)
        let model = try #require(reopened.workspace.metadata)
        #expect(model.columns.first { $0.tableName == "Sales" && $0.name == "Doanh thu" }?.kind == .calculated)
        #expect(model.tables.first { $0.name == "Vùng" }?.isCalculatedUserTable == true)
        #expect(model.calculatedTableExpressions["Vùng"] == "DISTINCT(Sales[Region])")
        #expect(try await scalar(reopened, "SUM(Sales[Doanh thu])") == .double(37))
        #expect(try await scalar(reopened, "COUNTROWS(Vùng)") == .integer(3))
        #expect(try await scalar(reopened, "SUM(Vùng[Trọng số])") == .integer(12))

        // Thêm cột tính toán lên bảng giờ đã nằm trong file, lưu đè, mở lại.
        #expect(await reopened.addCalculatedColumn(table: "Sales", formula: "Gấp đôi = Sales[Qty] * 2") == nil)
        let stamp = try FileStamp.of(first)
        #expect(try DocumentSaver.save(editor: reopened.layout, source: first, to: first, expectedStamp: stamp, readOnlyRoots: [],
                                       backupDirectory: root.appendingPathComponent("Backups")).didWrite)
        let third = DocumentState(workspace: try Workspace(data: Data(contentsOf: first)), fileName: first.lastPathComponent, fileURL: first)
        #expect(try await scalar(third, "SUM(Sales[Gấp đôi])") == .integer(34))
        #expect(try await scalar(third, "SUM(Sales[Doanh thu])") == .double(37))
    }
}
