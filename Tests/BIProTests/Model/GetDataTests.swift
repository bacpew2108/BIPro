// Phase F, T044: Get Data → mô hình, từ DocumentState (Ribbon "Lấy dữ liệu"/"Excel") đến engine DAX và visual. Chạy trên Nhom6 thật
// (BIPRO_HEAVY=1) và file mẫu `build/f-out/samples/`. Số mong đợi tính độc lập bằng Python trên file mẫu:
// sales_2026.csv = 10 000 dòng, Σ Qty 99742, Σ Amount 3 654 202,84, 5 vùng; sales_2026.xlsx: Sales 500 dòng, Customers 50 dòng.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: Get Data vào mô hình", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil && FFixtures.sample("sales_2026.csv") != nil),
       .serialized)
@MainActor
struct GetDataTests {
    private func makeState() throws -> DocumentState {
        DocumentState(workspace: try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6))), fileName: "Nhom6_f.pbix")
    }

    private func number(_ value: Value?) -> Double? {
        switch value {
        case .integer(let i)?: Double(i)
        case .double(let d)?: d
        case .currency(let c)?: Double(c) / 10_000
        default: nil
        }
    }

    private func scalar(_ state: DocumentState, _ expression: String) async throws -> Double {
        let result = try await state.workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))")
        return try #require(number(result.tables.first?.rows.first?.first), Comment(rawValue: expression))
    }

    /// Mở nguồn qua đường của Ribbon (`showGetData(kind:pickFile:)`) và chờ Navigator sẵn sàng.
    private func open(_ state: DocumentState, kind: SourceKind, file: String) async throws -> NavigatorState {
        let url = try #require(FFixtures.sample(file))
        state.showGetData(kind: kind, pickFile: { _ in url.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems {
            try await Task.sleep(for: .milliseconds(25))
        }
        return navigator
    }

    private func load(_ state: DocumentState, _ navigator: NavigatorState, pick names: [String]) async throws -> [LoadedTable] {
        for item in navigator.items where names.contains(item.name) { navigator.toggle(item.id) }
        return try #require(await navigator.load(existingNames: state.existingTableNames))
    }

    @Test func csvThanhBangSoKhopGoldenVaHoanTac() async throws {
        let state = try makeState()
        let navigator = try await open(state, kind: .csv, file: "sales_2026.csv")
        #expect(navigator.phase == .ready)
        let loaded = try await load(state, navigator, pick: ["sales_2026"])
        #expect(state.loadFromGetData(loaded) == nil)

        #expect(state.workspace.rowCount("sales_2026") == 10_000)
        #expect(try await scalar(state, "COUNTROWS(sales_2026)") == 10_000)
        #expect(try await scalar(state, "SUM(sales_2026[Qty])") == 99_742)
        #expect(abs(try await scalar(state, "SUM(sales_2026[Amount])") - 3_654_202.84) < 0.005)
        #expect(try await scalar(state, "DISTINCTCOUNT(sales_2026[Region])") == 5)
        #expect(state.workspace.userTables.contains { $0.name == "sales_2026" })

        // ⌘Z: bảng biến mất khỏi mô hình lẫn Table View; ⇧⌘Z: trở lại với cùng số liệu.
        state.layout.undo()
        #expect(!state.workspace.userTables.contains { $0.name == "sales_2026" })
        #expect(state.workspace.rowCount("sales_2026") == 0)
        state.layout.redo()
        #expect(state.workspace.rowCount("sales_2026") == 10_000)
        #expect(try await scalar(state, "SUM(sales_2026[Qty])") == 99_742)
    }

    @Test func excelNhieuMucThanhNhieuBangMotBuocHoanTac() async throws {
        let state = try makeState()
        let before = state.layout.undoDepth
        let navigator = try await open(state, kind: .excel, file: "sales_2026.xlsx")
        let loaded = try await load(state, navigator, pick: ["Sales", "Customers"])
        #expect(loaded.map(\.name) == ["Customers", "Sales"])   // thứ tự Navigator (chữ cái), như Desktop
        #expect(state.loadFromGetData(loaded) == nil)
        #expect(state.layout.undoDepth == before + 1)
        #expect(state.workspace.rowCount("Sales") == 500)
        #expect(state.workspace.rowCount("Customers") == 50)
        #expect(try await scalar(state, "COUNTROWS(Customers)") == 50)
        state.layout.undo()
        #expect(!state.workspace.userTables.contains { $0.name == "Sales" || $0.name == "Customers" })
    }

    @Test func napHaiLanTenTrungDuocKhuTrung() async throws {
        let state = try makeState()
        for _ in 0..<2 {
            let navigator = try await open(state, kind: .csv, file: "sales_2026.csv")
            let loaded = try await load(state, navigator, pick: ["sales_2026"])
            #expect(state.loadFromGetData(loaded) == nil)
            state.closeGetData()
        }
        let names = state.workspace.userTables.map(\.name).filter { $0.hasPrefix("sales_2026") }
        #expect(names == ["sales_2026", "sales_2026 (2)"])
        #expect(try await scalar(state, "SUM('sales_2026 (2)'[Qty])") == 99_742)
    }

    @Test func fileHongHoacRongBaoLoiTiengVietVaKhongDoiMoHinh() async throws {
        let dir = try EFixtures.outputDirectory("F-getdata")
        let empty = dir.appendingPathComponent("rong.csv"), broken = dir.appendingPathComponent("hong.xlsx")
        try Data().write(to: empty)
        try Data("không phải zip".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: empty); try? FileManager.default.removeItem(at: broken) }

        let state = try makeState()
        let tables = state.workspace.userTables.count
        for (kind, url) in [(SourceKind.csv, empty), (.excel, broken)] {
            let navigator = NavigatorState()
            await navigator.openSource(kind: kind, location: url.path)
            // Lỗi có thể lộ ngay lúc mở (file không đọc được) hoặc lúc nạp (nguồn rỗng; xem trước chỉ ghi `previewError`).
            if navigator.phase == .ready {
                for item in navigator.items { navigator.toggle(item.id) }
                #expect(await navigator.load(existingNames: state.existingTableNames) == nil)
            }
            guard case .failed(let message) = navigator.phase else { Issue.record("phải báo lỗi: \(navigator.phase)"); continue }
            #expect(!message.isEmpty)
            #expect(navigator.loaded.isEmpty)
        }
        #expect(state.workspace.userTables.count == tables)
        #expect(state.layout.modelEdits.isEmpty && !state.layout.isDirty)
    }

    @Test func tenBangTrungMoHinhBiTuChoiHopThoaiOLai() async throws {
        let state = try makeState()
        let existing = try #require(state.workspace.userTables.first?.name)
        let data = try TableData(columns: [TableColumn(name: "A", data: ColumnBuilder.integers([1]))])
        let reason = state.loadFromGetData([LoadedTable(name: existing.uppercased(), data: data)])
        #expect(reason?.contains("trùng") == true)
        #expect(state.layout.modelEdits.isEmpty)
    }

    @Test func measureTrenBangMoiChayQuaCardVisual() async throws {
        let state = try makeState()
        let navigator = try await open(state, kind: .csv, file: "sales_2026.csv")
        #expect(state.loadFromGetData(try await load(state, navigator, pick: ["sales_2026"])) == nil)
        state.beginNewMeasure(table: "sales_2026")
        state.measureDraft?.text = "Tong Qty = SUM(sales_2026[Qty])"
        await state.applyMeasureDraft()
        #expect(state.measureDraft?.message == nil, Comment(rawValue: state.measureDraft?.message ?? ""))

        let field = FieldInfo(queryRef: "sales_2026.Tong Qty", displayName: "Tong Qty", role: "Values", formatString: nil, isMeasure: true)
        var spec = VisualQuerySpec(visualID: "card1", visualType: "card")
        spec.shape = .card
        spec.measures = [QueryMeasure(field: field, table: "sales_2026", measure: "Tong Qty", resultName: "Tong_Qty", ignore: false, purpose: .value)]
        let loader = VisualDataLoader(engine: try state.workspace.daxEngine(), maxConcurrent: 1)
        let result = try await loader.load(spec)
        guard case .single(let single) = result.view else { Issue.record("không phải card: \(result.view)"); return }
        #expect(single.cell.value == .integer(99_742))
    }

    /// T022: lưu bảng nạp từ CSV vào `.pbix` rồi mở lại bằng `Workspace` mới: số dòng, tổng, ngày khớp golden. Hai lần lưu liên tiếp.
    @Test func luuBangMoiRoiMoLaiKhopGolden() async throws {
        let dir = try EFixtures.outputDirectory("F-getdata")
        let source = dir.appendingPathComponent("Nhom6_f_save.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: dir.appendingPathComponent("Backups")) }
        let backups = dir.appendingPathComponent("Backups")
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
        let navigator = try await open(state, kind: .csv, file: "sales_2026.csv")
        #expect(state.loadFromGetData(try await load(state, navigator, pick: ["sales_2026"])) == nil)
        let outcome = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                             readOnlyRoots: [], backupDirectory: backups)
        #expect(outcome.didWrite && !state.layout.isDirty)

        let reopened = DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
        #expect(reopened.workspace.rowCount("sales_2026") == 10_000)
        #expect(try await scalar(reopened, "SUM(sales_2026[Qty])") == 99_742)
        #expect(abs(try await scalar(reopened, "SUM(sales_2026[Amount])") - 3_654_202.84) < 0.005)
        #expect(try await scalar(reopened, "DISTINCTCOUNT(sales_2026[Region])") == 5)
        #expect(try await scalar(reopened, "COUNTROWS(FILTER(sales_2026, sales_2026[OrderDate] >= DATE(2026,1,1)))") == 10_000)
        // Bảng cũ của Nhom6 không đổi.
        #expect(reopened.workspace.userTables.count == state.workspace.userTables.count)

        // Lần lưu thứ hai: thêm bảng Excel và một measure trên bảng đã lưu.
        let excel = try await open(reopened, kind: .excel, file: "sales_2026.xlsx")
        #expect(reopened.loadFromGetData(try await load(reopened, excel, pick: ["Customers"])) == nil)
        reopened.beginNewMeasure(table: "sales_2026")
        reopened.measureDraft?.text = "Tong Qty = SUM(sales_2026[Qty])"
        await reopened.applyMeasureDraft()
        _ = try DocumentSaver.save(editor: reopened.layout, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: backups)
        let again = DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
        #expect(again.workspace.rowCount("Customers") == 50)
        #expect(again.workspace.rowCount("sales_2026") == 10_000)
        #expect(try await scalar(again, "[Tong Qty]") == 99_742)
    }

    /// Cột tiền tệ (Fixed decimal): trước T103 bị từ chối khi lưu (FR-051); nay lưu được như Desktop và đọc lại đúng giá trị.
    @Test func cotTienTeLuuDuocVaDocLaiDung() async throws {
        let dir = try EFixtures.outputDirectory("F-getdata")
        let source = dir.appendingPathComponent("Nhom6_f_save2.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: dir.appendingPathComponent("Backups")) }
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
        let data = try TableData(columns: [TableColumn(name: "Tien", data: ColumnBuilder.currency([10_000, 20_000]))])
        #expect(state.loadFromGetData([LoadedTable(name: "Logic", data: data)]) == nil)
        #expect(try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                       readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups")).didWrite)
        let again = DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
        #expect(again.workspace.rowCount("Logic") == 2)
        #expect(again.workspace.metadata?.columns.first { $0.tableName == "Logic" && $0.name == "Tien" }?.dataType == .decimal)
    }
}
