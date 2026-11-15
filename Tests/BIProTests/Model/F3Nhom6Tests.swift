// Phase F, T024/T025: lưu bảng nạp từ Get Data vào bản sao Nhom6 (tầng T3), mở lại bằng Workspace mới và đối chiếu từng ô, tổng, số dòng.
// Mỗi ca để lại một file trong `build/f-out/F3/` (ngoài git) cho gate trên Desktop (T026, `docs/phase-f-evidence/vm-f1/CHECKLIST.md`).
// Chạy nặng (BIPRO_HEAVY=1) vì mở cả mô hình Nhom6. Số mong đợi tính độc lập bằng Python trên file mẫu: sales_2026.csv = 10 000 dòng,
// Σ Qty 99742, Σ Amount 3 654 202,84, 5 vùng; xlsx: Sales 500, Customers 50.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: lưu T3 vào Nhom6", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil && FFixtures.sample("sales_2026.csv") != nil), .serialized)
@MainActor
struct F3Nhom6Tests {
    private func output(_ name: String) throws -> URL {
        let dir = try EFixtures.outputDirectory("F3")
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: url)
        return url
    }

    private func state(_ url: URL) throws -> DocumentState {
        DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
    }

    private func number(_ value: Value?) -> Double? {
        switch value {
        case .integer(let i)?: Double(i)
        case .double(let d)?: d
        default: nil
        }
    }

    private func scalar(_ state: DocumentState, _ expression: String) async throws -> Double {
        let result = try await state.workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))")
        return try #require(number(result.tables.first?.rows.first?.first), Comment(rawValue: expression))
    }

    private func load(_ state: DocumentState, _ kind: SourceKind, _ file: String, pick: [String]) async throws {
        let url = try #require(FFixtures.sample(file))
        state.showGetData(kind: kind, pickFile: { _ in url.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items where pick.contains(item.name) { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        #expect(state.loadFromGetData(loaded) == nil)
        state.closeGetData()
    }

    private func save(_ state: DocumentState, to url: URL) throws {
        let backups = url.deletingLastPathComponent().appendingPathComponent("Backups")
        defer { try? FileManager.default.removeItem(at: backups) }
        let outcome = try DocumentSaver.save(editor: state.layout, source: url, to: url, expectedStamp: nil, readOnlyRoots: [], backupDirectory: backups)
        #expect(outcome.didWrite)
    }

    private func reopen(_ url: URL) throws -> DocumentState { try state(url) }

    @Test func f1MotBangTuCSV() async throws {
        let url = try output("Nhom6_f1_a_mot_bang_csv.pbix")
        let state = try state(url)
        try await load(state, .csv, "sales_2026.csv", pick: ["sales_2026"])
        try save(state, to: url)
        let reopened = try reopen(url)
        #expect(reopened.workspace.rowCount("sales_2026") == 10_000)
        #expect(try await scalar(reopened, "SUM(sales_2026[Qty])") == 99_742)
        #expect(abs(try await scalar(reopened, "SUM(sales_2026[Amount])") - 3_654_202.84) < 0.005)
        #expect(try await scalar(reopened, "DISTINCTCOUNT(sales_2026[Region])") == 5)
        // Nhom6 gốc nguyên vẹn: một bảng và số dòng của bảng cũ.
        #expect(reopened.workspace.rowCount("Fact_Loan") == 682)
        #expect(try await scalar(reopened, "COUNTROWS(Dim_Account)") == 4_501)
    }

    /// T061: truy vấn M thật (Source, Promoted Headers, Changed Type) ghi vào `Partition.QueryDefinition` và đọc lại đúng văn bản.
    @Test func f5TruyVanMGhiVaDocLai() async throws {
        let url = try output("Nhom6_f5_truy_van_m.pbix")
        let state = try state(url)
        try await load(state, .csv, "sales_2026.csv", pick: ["sales_2026"])
        try await load(state, .excel, "sales_2026.xlsx", pick: ["Sales"])
        try save(state, to: url)
        let reopened = try reopen(url)
        let queries = try #require(reopened.workspace.metadata?.partitionQueries)
        let csv = try #require(queries["sales_2026"])
        #expect(csv.contains("Csv.Document(File.Contents(\"\(try #require(FFixtures.sample("sales_2026.csv")).path)\"),[Delimiter=\",\", Columns=8, Encoding=65001, QuoteStyle=QuoteStyle.None])"))
        #expect(try MQuery.parse(csv).steps.map(\.name) == ["Source", "Promoted Headers", "Changed Type"])
        let excel = try #require(queries["Sales"])
        #expect(try MQuery.parse(excel).steps.map(\.name) == ["Source", "Sales_Sheet", "Promoted Headers", "Changed Type"])
        #expect(excel.contains(#"Source{[Item="Sales",Kind="Sheet"]}[Data]"#))
        // Bảng cũ của Nhom6 giữ nguyên truy vấn của nó.
        #expect(queries["Fact_Loan"] == state.workspace.metadata?.partitionQueries["Fact_Loan"])
        #expect(reopened.workspace.rowCount("Sales") == 500)
    }

    @Test func f2BaBangCungLuc() async throws {
        let url = try output("Nhom6_f1_b_ba_bang.pbix")
        let state = try state(url)
        try await load(state, .csv, "sales_2026.csv", pick: ["sales_2026"])
        try await load(state, .excel, "sales_2026.xlsx", pick: ["Sales", "Customers"])
        try save(state, to: url)
        let reopened = try reopen(url)
        #expect(reopened.workspace.rowCount("sales_2026") == 10_000)
        #expect(reopened.workspace.rowCount("Sales") == 500)
        #expect(reopened.workspace.rowCount("Customers") == 50)
        #expect(try await scalar(reopened, "COUNTROWS(Customers)") == 50)
    }

    @Test func f3QuanHeVaMeasure() async throws {
        let url = try output("Nhom6_f1_c_quan_he_measure.pbix")
        let state = try state(url)
        try await load(state, .csv, "sales_2026.csv", pick: ["sales_2026"])
        try await load(state, .excel, "sales_2026.xlsx", pick: ["Customers"])
        let relationship = NewRelationship(fromTable: "sales_2026", fromColumn: "CustomerID", toTable: "Customers", toColumn: "CustomerID")
        #expect(state.modelEditor.apply(.addRelationship(relationship)) == nil)
        state.beginNewMeasure(table: "sales_2026")
        state.measureDraft?.text = "Tong Amount = SUM(sales_2026[Amount])"
        await state.applyMeasureDraft()
        #expect(state.measureDraft?.message == nil)
        try save(state, to: url)
        let reopened = try reopen(url)
        #expect(abs(try await scalar(reopened, "[Tong Amount]") - 3_654_202.84) < 0.005)
        // Quan hệ hoạt động: lọc bảng khách một dòng thì tổng bảng bán thu hẹp, và số dòng khớp tính tay bằng cách nối.
        let filtered = try await scalar(reopened, "CALCULATE(COUNTROWS(sales_2026), Customers[CustomerID] = 1)")
        let direct = try await scalar(reopened, "COUNTROWS(FILTER(sales_2026, sales_2026[CustomerID] = 1))")
        #expect(filtered == direct && filtered > 0)
    }

    @Test func f4MotTramNganDong() async throws {
        let url = try output("Nhom6_f1_d_100000_dong.pbix")
        let state = try state(url)
        let rows = 100_000
        var ids: [Int64?] = [], amount: [Double?] = [], days: [Double?] = [], city: [String?] = [], note: [String?] = []
        ids.reserveCapacity(rows); amount.reserveCapacity(rows); days.reserveCapacity(rows); city.reserveCapacity(rows); note.reserveCapacity(rows)
        let cities = ["Hà Nội", "Đà Nẵng", "Hồ Chí Minh", "Cần Thơ", "Huế", "Hải Phòng", "Nha Trang"]
        for i in 0..<rows {
            ids.append(Int64(i))
            amount.append(i % 29 == 0 ? nil : Double(i % 1000) / 4)
            days.append(i % 31 == 0 ? nil : 45_000 + Double(i % 700))
            city.append(cities[i % cities.count])
            note.append(i % 5 == 0 ? nil : "ghi chú \(i % 977)")
        }
        let data = try TableData(columns: [
            TableColumn(name: "Id", data: ColumnBuilder.integers(ids)), TableColumn(name: "Tien", data: ColumnBuilder.doubles(amount)),
            TableColumn(name: "Ngay", data: ColumnBuilder.dateTimes(days)), TableColumn(name: "ThanhPho", data: ColumnBuilder.strings(city)),
            TableColumn(name: "GhiChu", data: ColumnBuilder.strings(note)),
        ])
        #expect(state.loadFromGetData([LoadedTable(name: "Lon", data: data)]) == nil)
        let start = Date()
        try save(state, to: url)
        print("F3 100000 dòng: lưu \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
        let reopened = try reopen(url)
        #expect(reopened.workspace.rowCount("Lon") == rows)
        let expectedSum = amount.compactMap { $0 }.reduce(0, +)
        #expect(abs(try await scalar(reopened, "SUM(Lon[Tien])") - expectedSum) < 0.01)
        #expect(try await scalar(reopened, "DISTINCTCOUNT(Lon[ThanhPho])") == 7)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Lon, ISBLANK(Lon[GhiChu])))") == 20_000)
    }

    @Test func f5NullOMoiKieuVaChuoiTiengViet() async throws {
        let url = try output("Nhom6_f1_e_null_moi_kieu.pbix")
        let state = try state(url)
        let data = try TableData(columns: [
            TableColumn(name: "So", data: ColumnBuilder.integers([1, nil, 3, nil, 5])),
            TableColumn(name: "Thuc", data: ColumnBuilder.doubles([1.5, 2.25, nil, nil, 0])),
            TableColumn(name: "Ngay", data: ColumnBuilder.dateTimes([46_000, nil, 46_002, 46_000, nil])),
            TableColumn(name: "Chu", data: ColumnBuilder.strings(["Đà Nẵng", nil, "Huế", "", "Đà Nẵng"])),
            TableColumn(name: "Dung", data: ColumnBuilder.booleans([true, nil, false, true, true])),
            TableColumn(name: "Luon", data: ColumnBuilder.booleans([true, true, true, true, true])),
            TableColumn(name: "Hang", data: ColumnBuilder.strings(["a", "a", "a", "a", "a"])),
            TableColumn(name: "Hai", data: ColumnBuilder.strings(["x", "y", "x", "y", "x"])),
            TableColumn(name: "NgayHang", data: ColumnBuilder.dateTimes([46_023, 46_023, 46_023, 46_023, 46_023])),
        ])
        #expect(state.loadFromGetData([LoadedTable(name: "Null", data: data)]) == nil)
        try save(state, to: url)
        let reopened = try reopen(url)
        #expect(reopened.workspace.rowCount("Null") == 5)
        #expect(try await scalar(reopened, "SUM(Null[So])") == 9)
        #expect(try await scalar(reopened, "SUM(Null[Thuc])") == 3.75)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, Null[Dung] = TRUE()))") == 3)
        // DAX coi BLANK() = FALSE() là đúng, nên so với FALSE() khớp cả ô trống; ISBLANK tách ra.
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, Null[Dung] = FALSE()))") == 2)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, NOT ISBLANK(Null[Dung]) && Null[Dung] = FALSE()))") == 1)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, Null[Luon] = TRUE()))") == 5)
        #expect(try await scalar(reopened, "DISTINCTCOUNT(Null[Hang])") == 1)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, Null[Hai] = \"x\"))") == 3)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, Null[NgayHang] = DATE(2026,1,1)))") == 5)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, ISBLANK(Null[Chu])))") == 1)
        // Chuỗi rỗng khác ô trống (NULL): DAX coi BLANK() = "" là đúng nên so sánh thường khớp cả hai, ISBLANK tách ra.
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, Null[Chu] = \"\"))") == 2)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(Null, NOT ISBLANK(Null[Chu]) && Null[Chu] = \"\"))") == 1)
    }
}
