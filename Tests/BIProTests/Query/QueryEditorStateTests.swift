// Phase F, T057, T061: trạng thái Query Editor (bước, lệnh Ribbon, hỏi khi chèn giữa, hoàn tác, xem trước, profile, lỗi bước) và M mà
// Get Data ghi (so với `Partition.QueryDefinition` Desktop 2.159, docs/phase-f-evidence/vm-f1/QUAN-SAT.md mục 3 và golden vm-f3).
import ColumnStore
import Connectors
import Foundation
import MEngine
import Testing
@testable import BIPro

@MainActor
@Suite struct QueryEditorStateTests {
    private func sales() throws -> TableData {
        try TableData(columns: [
            TableColumn(name: "OrderID", data: ColumnBuilder.integers([1, 2, 3, 4, 5])),
            TableColumn(name: "Region", data: ColumnBuilder.strings(["North", "South", "North", nil, "East"])),
            TableColumn(name: "Qty", data: ColumnBuilder.integers([10, 20, 30, 40, 50])),
        ])
    }

    /// Truy vấn ba bước khoá (Source, Promoted Headers, Changed Type) trên bảng `sales`.
    private func makeState() throws -> QueryEditorState {
        let loaded = LoadedTable(name: "Sales", data: try sales(),
                                 origin: LoadedOrigin(kind: .csv, location: "/khong/co/sales.csv", itemName: "Sales", itemKind: .file))
        let state = QueryEditorState()
        state.addQuery(from: loaded)
        return state
    }

    private func names(_ state: QueryEditorState) -> [String] { state.selectedQuery?.steps.map(\.name) ?? [] }
    private func expressions(_ state: QueryEditorState) -> [String] { state.selectedQuery?.steps.map(\.expression) ?? [] }

    // MARK: M ghi theo Desktop

    @Test func csvSinhDungMDesktop() throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let origin = LoadedOrigin(kind: .csv, location: url.path, itemName: "sales_2026", itemKind: .file)
        let data = try awaitLoad(url, kind: .csv)
        let text = try #require(LoadedTable(name: "sales_2026", data: data, origin: origin).queryDefinition)
        let expected = """
        let
            Source = Csv.Document(File.Contents("\(url.path)"),[Delimiter=",", Columns=8, Encoding=65001, QuoteStyle=QuoteStyle.None]),
            #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
            #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"OrderID", Int64.Type}, {"OrderDate", type date}, {"Region", type text}, {"CustomerID", Int64.Type}, {"Product", type text}, {"Qty", Int64.Type}, {"Price", type number}, {"Amount", type number}})
        in
            #"Changed Type"
        """
        #expect(text == expected)
        _ = try MParser.parse(text)
    }

    @Test func dauPhanCachVaMaHoaCSV() throws {
        guard let semicolon = FFixtures.sample("sales_semicolon.csv"), let utf16 = FFixtures.sample("sales_utf16.csv") else { return }
        #expect(SourceQuery.csvFormat(semicolon.path).delimiter == ";")
        #expect(SourceQuery.csvFormat(semicolon.path).encoding == 65001)
        #expect(SourceQuery.csvFormat(utf16.path).encoding == 1200)
        #expect(SourceQuery.csvFormat("/khong/co").delimiter == ",")
    }

    @Test func excelCoBuocNavigationVaKhopGolden() throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let data = try awaitLoad(url, kind: .excel, item: "Sales")
        let steps = SourceQuery.steps(for: LoadedOrigin(kind: .excel, location: url.path, itemName: "Sales", itemKind: .sheet), data: data)
        let goldenURL = FFixtures.root.appendingPathComponent("docs/phase-f-evidence/vm-f3/golden/chuoi-2.m")
        let golden = try MQuery.parse(String(contentsOf: goldenURL, encoding: .utf8)).steps
        #expect(steps.map(\.name) == golden.prefix(4).map { $0.name })
        // Bước 1 đến 3 trùng nguyên văn Desktop (chỉ bước Source có đường dẫn riêng).
        #expect(Array(steps.dropFirst()).map { $0.expression } == golden[1..<4].map { $0.expression })
        #expect(steps[0].expression == "Excel.Workbook(File.Contents(\(StepFactory.quote(url.path))), null, true)")
        #expect(steps.map(\.kind) == ["source", "navigation", "promote", "type"])
    }

    @Test func bangDatTenKhongThangCapTieuDe() throws {
        let data = try sales()
        let steps = SourceQuery.steps(for: LoadedOrigin(kind: .excel, location: "/a.xlsx", itemName: "SalesTable", itemKind: .namedTable), data: data)
        #expect(steps.map(\.name) == ["Source", "SalesTable_Table", "Changed Type"])
        #expect(steps[1].expression == #"Source{[Item="SalesTable",Kind="Table"]}[Data]"#)
    }

    @Test func kieuNgayChiLaDateKhiMoiGiaTriNguyenNgay() throws {
        let whole = try TableData(columns: [TableColumn(name: "D", data: ColumnBuilder.dateTimes([46083, 46090, nil]))])
        let withTime = try TableData(columns: [TableColumn(name: "D", data: ColumnBuilder.dateTimes([46083.5]))])
        #expect(SourceQuery.typeChanges(whole) == [ColumnTypeChange(column: "D", type: .date)])
        #expect(SourceQuery.typeChanges(withTime) == [ColumnTypeChange(column: "D", type: .dateTime)])
    }

    // MARK: Bước và lệnh Ribbon

    @Test func moTruyVanChonBuocCuoiVaXemTruocDungBang() async throws {
        let state = try makeState()
        #expect(names(state) == ["Source", "Promoted Headers", "Changed Type"])
        #expect(state.selectedStepIndex == 2)
        await state.refresh()
        #expect(state.preview?.rowCount == 5)
        #expect(state.errorMessage == nil)
        #expect(!state.hasPendingChanges)
        #expect(state.selectedQuery?.isModified == true)   // chưa Close & Apply
    }

    @Test func lenhThemBuocSauBuocDangChonVaXemTruoc() async throws {
        let state = try makeState()
        #expect(state.perform(.keepTopRows(2)) == .applied)
        #expect(names(state).last == "Kept First Rows")
        #expect(expressions(state).last == #"Table.FirstN(#"Changed Type",2)"#)
        #expect(state.selectedStepIndex == 3)
        #expect(state.hasPendingChanges)
        await state.refresh()
        #expect(state.preview?.rowCount == 2)
        // Lệnh thứ hai nối tiếp bước vừa thêm.
        #expect(state.perform(.removeColumns(["Qty"])) == .applied)
        #expect(expressions(state).last == #"Table.RemoveColumns(#"Kept First Rows",{"Qty"})"#)
        await state.refresh()
        #expect(state.preview?.columns.map(\.name) == ["OrderID", "Region"])
    }

    @Test func locBangDanhSachGiaTriVaSapXep() async throws {
        let state = try makeState()
        #expect(state.perform(.filterEquals(column: "Region", values: [.text("North")])) == .applied)
        await state.refresh()
        #expect(state.preview?.rowCount == 2)
        #expect(state.perform(.sortRows([SortKey(column: "Qty", descending: true)])) == .applied)
        await state.refresh()
        let first = try #require(state.preview).value(row: 0, column: 2)
        #expect(first == .integer(30))
    }

    @Test func chenGiuaHoiXacNhanRoiNoiLaiBuocSau() async throws {
        let state = try makeState()
        state.perform(.keepTopRows(2))
        state.selectStep(2)
        #expect(state.perform(.reverseRows) == .needsInsertConfirmation)
        #expect(names(state).count == 4)   // chưa chèn gì
        #expect(state.perform(.reverseRows, confirmInsert: true) == .applied)
        #expect(names(state) == ["Source", "Promoted Headers", "Changed Type", "Reversed Rows", "Kept First Rows"])
        #expect(expressions(state)[4] == #"Table.FirstN(#"Reversed Rows",2)"#)   // bước sau nối vào bước mới
        #expect(state.selectedStepIndex == 3)
        await state.refresh()
        #expect(state.selectedQuery?.steps.count == 5)
        state.selectStep(4)
        await state.refresh()
        #expect(try #require(state.preview).value(row: 0, column: 0) == .integer(5))   // đảo rồi lấy 2 dòng đầu
    }

    @Test func buocNguonBiKhoa() throws {
        let state = try makeState()
        state.selectStep(0)
        if case .rejected(let why) = state.perform(.reverseRows) { #expect(why.contains("bước đầu")) } else { Issue.record("phải từ chối") }
        #expect(state.deleteStep(at: 1) != nil)
        #expect(state.renameStep(at: 2, to: "X") != nil)
        #expect(state.setExpression(at: 0, "1") != nil)
        #expect(state.moveStep(at: 1, by: 1) != nil)
        #expect(!state.hasPendingChanges)
        #expect(state.canUndo == false)
    }

    @Test func xoaDoiTenVaSuaBieuThuc() async throws {
        let state = try makeState()
        state.perform(.keepTopRows(3))
        state.perform(.reverseRows)
        // Xoá bước giữa: bước sau trỏ về bước trước.
        #expect(state.deleteStep(at: 3) == nil)
        #expect(names(state) == ["Source", "Promoted Headers", "Changed Type", "Reversed Rows"])
        #expect(expressions(state)[3] == #"Table.ReverseRows(#"Changed Type")"#)
        #expect(state.renameStep(at: 3, to: "Dao nguoc") == nil)
        #expect(names(state).last == "Dao nguoc")
        #expect(state.renameStep(at: 3, to: "") != nil)
        #expect(state.renameStep(at: 3, to: "Changed Type") != nil)   // trùng
        #expect(state.setExpression(at: 3, "Table.ReverseRows(")?.contains("Dòng") == true)
        #expect(state.setExpression(at: 3, "Table.FirstN(#\"Changed Type\", 1)") == nil)
        await state.refresh()
        #expect(state.preview?.rowCount == 1)
    }

    @Test func buocLoiHienLoiTrongKhongLamHongBuocTruoc() async throws {
        let state = try makeState()
        state.perform(.keepTopRows(2))
        #expect(state.setExpression(at: 3, #"Table.SelectRows(#"Changed Type", each [KhongCo] > 1)"#) == nil)
        await state.refresh()
        #expect(state.preview == nil)
        #expect(state.errorMessage?.isEmpty == false)
        #expect(state.stepErrors["Kept First Rows"] != nil)
        state.selectStep(2)
        await state.refresh()
        #expect(state.preview?.rowCount == 5)
        #expect(state.errorMessage == nil)
    }

    @Test func hoanTacVaLamLaiTungThaoTac() throws {
        let state = try makeState()
        state.perform(.keepTopRows(2))
        state.perform(.reverseRows)
        #expect(names(state).count == 5)
        state.undo()
        #expect(names(state).count == 4)
        state.undo()
        #expect(names(state).count == 3)
        #expect(!state.hasPendingChanges)
        #expect(!state.canUndo && state.canRedo)
        state.redo()
        #expect(names(state).count == 4 && state.hasPendingChanges)
        state.perform(.removeColumns(["Qty"]))   // thao tác mới xoá lịch sử làm lại
        #expect(!state.canRedo)
    }

    @Test func advancedEditorGiuBuocKhoaVaThemBuoc() async throws {
        let state = try makeState()
        let source = state.advancedSource
        #expect(source.hasPrefix("let\n    Source = "))
        let extended = source.replacingOccurrences(of: "\nin\n    #\"Changed Type\"",
                                                   with: ",\n    #\"Kept First Rows\" = Table.FirstN(#\"Changed Type\",1)\nin\n    #\"Kept First Rows\"")
        #expect(state.applyAdvancedSource(extended) == nil)
        #expect(names(state).last == "Kept First Rows")
        await state.refresh()
        #expect(state.preview?.rowCount == 1)
        // Sửa bước khoá bị từ chối; lỗi cú pháp có dòng cột.
        #expect(state.applyAdvancedSource(extended.replacingOccurrences(of: "Promoted Headers", with: "Dau De")) != nil)
        #expect(state.applyAdvancedSource("let A = 1,")?.contains("Dòng") == true)
        #expect(names(state).count == 4)
    }

    @Test func profileMotCotTrenBangXemTruoc() async throws {
        let state = try makeState()
        await state.refresh()
        let region = try #require(state.profiles.first { $0.columnName == "Region" })
        #expect((region.valid, region.empty, region.error) == (4, 1, 0))
        #expect(region.distinct == 4)   // North, South, East và rỗng
        let qty = try #require(state.profiles.first { $0.columnName == "Qty" })
        #expect(qty.min == "10" && qty.max == "50" && qty.average == "30")
        #expect(region.distribution.first == ProfileBucket(label: "North", count: 2))
    }

    @Test func doiTenTruyVanVaEnableLoad() throws {
        let state = try makeState()
        let id = try #require(state.selectedQueryID)
        #expect(state.renameQuery(id, to: "") != nil)
        #expect(state.renameQuery(id, to: "Doanh thu", existingTableNames: ["Fact"]) == nil)
        #expect(state.selectedQuery?.name == "Doanh thu")
        #expect(state.renameQuery(id, to: "fact", existingTableNames: ["Fact"]) != nil)   // trùng bảng, không phân biệt hoa thường
        state.setEnableLoad(id, false)
        #expect(state.selectedQuery?.enableLoad == false)
        state.undo()
        #expect(state.selectedQuery?.enableLoad == true)
    }

    @Test func truyVanKhongCoNguonBaoThieuDuLieu() async throws {
        let state = QueryEditorState()
        let query = QueryEditorState.model(name: "Cu", source: "let\n    Source = Excel.Workbook(File.Contents(\"C:\\\\a.xlsx\"), null, true)\nin\n    Source",
                                          tableName: "Cu", locked: true)
        state.addQuery(query, base: nil)
        await state.refresh()
        #expect(state.preview == nil)
        #expect(state.errorMessage == "Chưa có dữ liệu nguồn của truy vấn này.")
        #expect(state.selectedQuery?.isModified == false)
    }

    @Test func vanBanKhongPhanTichDuocThanhMotBuocTuyY() throws {
        let model = QueryEditorState.model(name: "Hong", source: "let A = in", tableName: nil, locked: false)
        #expect(model.steps.count == 1 && model.steps[0].kind == "custom")
        #expect(model.steps[0].expression == "let A = in")
    }

    // MARK: Trợ giúp

    private func awaitLoad(_ url: URL, kind: SourceKind, item: String? = nil) throws -> TableData {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<TableData, Error>?
        Task.detached {
            do {
                let source = try SourceFactory.make(kind: kind, location: url.path)
                let items = try await source.items()
                let chosen = try #require(items.first { item == nil || $0.name == item })
                result = .success(try await chosen.load(progress: nil))
            } catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try result!.get()
    }
}
