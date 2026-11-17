// Phase F, T039: luồng Get Data → Navigator (chọn nguồn, liệt kê mục, xem trước, nạp). Seam: `NavigatorState` (API công khai)
// chạy trên file mẫu thật `build/f-out/samples/` (thiếu thì test bỏ qua, như các test Nhom6), cộng `TableNaming` (đặt tên bảng).
// Giá trị mong đợi lấy từ tính độc lập bằng Python trên file mẫu (docs/tasks/f-conn1.md, bảng "golden facts").
import Testing
import Foundation
import ColumnStore
import Connectors
@testable import BIPro

@MainActor
@Suite struct NavigatorStateTests {

    // MARK: Chọn nguồn → liệt kê → xem trước

    @Test func openingCSVListsOneFileItemAndBecomesReady() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: url.path)
        #expect(state.phase == .ready)
        #expect(state.sourceKind == .csv)
        #expect(state.items.map(\.name) == ["sales_2026"])
        #expect(state.items.first?.kind == .file)
        #expect(state.checkedItemIDs.isEmpty)
        #expect(!state.canLoad)
    }

    @Test func openingExcelListsNamedTablesThenSheetsAlphabetically() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .excel, location: url.path)
        #expect(state.phase == .ready)
        #expect(state.items.map(\.name) == ["SalesTable", "Customers", "Notes", "Sales"])   // thứ tự Navigator của Desktop 2.159
        #expect(state.items.map(\.kind) == [.namedTable, .sheet, .sheet, .sheet])
        #expect(Set(state.items.map(\.id)).count == state.items.count)   // id duy nhất để giao diện chọn
    }

    @Test func previewShowsAtMostTwoHundredRowsOfTheChosenItem() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: url.path)
        let id = try #require(state.items.first?.id)
        await state.showPreview(id)
        #expect(state.previewItemID == id)
        let preview = try #require(state.preview)
        #expect(preview.rowCount == 200)
        #expect(preview.columns.map(\.name) == ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"])
        #expect(state.phase == .ready)
    }

    @Test func previewOfUnknownItemIsIgnored() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: url.path)
        await state.showPreview("khong-co")
        #expect(state.preview == nil)
        #expect(state.previewItemID == nil)
    }

    // MARK: Lỗi: báo tiếng Việt, không đổi gì khác

    @Test func openingMissingFileFailsWithVietnameseReason() async {
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: "/khong/co/file.csv")
        guard case .failed(let message) = state.phase else { Issue.record("phase = \(state.phase)"); return }
        #expect(!message.isEmpty)
        #expect(message.contains("Không") || message.contains("không"))
        #expect(state.items.isEmpty)
        #expect(!state.canLoad)
    }

    /// Parquet đã nối (T089): tệp không có báo lỗi đọc tiếng Việt; PostgreSQL vẫn chưa.
    @Test func missingParquetFailsAndPostgresIsNotYetSupported() async {
        let state = NavigatorState()
        await state.openSource(kind: .parquet, location: "/tmp/khong-co-\(UUID().uuidString).parquet")
        guard case .failed(let message) = state.phase else { Issue.record("phase = \(state.phase)"); return }
        #expect(message.contains("Không thể đọc file"))
        await state.openSource(kind: .postgres, location: "localhost/db")
        guard case .failed = state.phase else { Issue.record("phase = \(state.phase)"); return }
    }

    @Test func reopeningASourceClearsPreviousItemsAndChecks() async throws {
        guard let csv = FFixtures.sample("sales_2026.csv"), let xlsx = FFixtures.sample("sales_2026.xlsx") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: csv.path)
        state.toggle(try #require(state.items.first?.id))
        await state.showPreview(try #require(state.items.first?.id))
        await state.openSource(kind: .excel, location: xlsx.path)
        #expect(state.checkedItemIDs.isEmpty)
        #expect(state.preview == nil)
        #expect(state.previewItemID == nil)
        #expect(state.items.count == 4)
    }

    // MARK: Nạp: tên bảng, thứ tự, tiến độ

    @Test func loadingCSVGivesOneNewTableNamedAfterTheFile() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: url.path)
        state.toggle(try #require(state.items.first?.id))
        #expect(state.canLoad)
        let tables = try #require(await state.load())
        #expect(tables.count == 1)
        #expect(tables[0].name == "sales_2026")
        #expect(tables[0].queryName == "sales_2026")
        #expect(tables[0].status == .new)
        #expect(tables[0].data.rowCount == 10_000)
        #expect(tables[0].data.columns.count == 8)
        #expect(state.loaded.map(\.name) == ["sales_2026"])
        #expect(state.phase == .ready)
        #expect(state.progress == 1)
    }

    @Test func loadedNameGetsSuffixWhenTheModelAlreadyHasIt() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: url.path)
        state.toggle(try #require(state.items.first?.id))
        let tables = try #require(await state.load(existingNames: ["SALES_2026"]))   // không phân biệt hoa thường
        #expect(tables.map(\.name) == ["sales_2026 (2)"])
        #expect(tables[0].queryName == "sales_2026 (2)")
    }

    @Test func loadingSeveralExcelItemsFollowsListOrderNotCheckOrder() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .excel, location: url.path)
        let byName = Dictionary(uniqueKeysWithValues: state.items.map { ($0.name, $0.id) })
        state.toggle(try #require(byName["SalesTable"]))   // đánh dấu ngược thứ tự danh sách
        state.toggle(try #require(byName["Customers"]))
        state.toggle(try #require(byName["Sales"]))
        let tables = try #require(await state.load(existingNames: ["Customers"]))
        #expect(tables.map(\.name) == ["SalesTable", "Customers (2)", "Sales"])
        #expect(tables.map(\.data.rowCount) == [500, 50, 500])
    }

    @Test func progressNeverGoesBackwardsWhileLoading() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .excel, location: url.path)
        for item in state.items { state.toggle(item.id) }
        var seen: [Double] = []
        let watcher = Task { @MainActor in
            while !Task.isCancelled { seen.append(state.progress); try? await Task.sleep(for: .milliseconds(1)) }
        }
        _ = await state.load()
        watcher.cancel()
        #expect(zip(seen, seen.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(state.progress == 1)
    }

    @Test func loadDoesNothingWhenNothingIsChecked() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .csv, location: url.path)
        #expect(await state.load() == nil)
        #expect(state.phase == .ready)
        #expect(state.loaded.isEmpty)
    }

    // MARK: Lỗi và huỷ: không trả bảng nào, không đổi mô hình (FR-005)

    @Test func aFailingItemFailsTheWholeLoadWithItsReason() async throws {
        let state = NavigatorState(makeSource: { _, _ in
            StubSource(items: [StubItem(name: "Tốt", behaviour: .succeed), StubItem(name: "Hỏng", behaviour: .fail("Tệp bị hỏng ở dòng 7."))])
        })
        await state.openSource(kind: .csv, location: "x")
        for item in state.items { state.toggle(item.id) }
        #expect(await state.load() == nil)
        #expect(state.phase == .failed("Tệp bị hỏng ở dòng 7."))
        #expect(state.loaded.isEmpty)
        #expect(state.progress == 0)
    }

    @Test func cancellingMidLoadReturnsNilAndGoesBackToReady() async throws {
        let state = NavigatorState(makeSource: { _, _ in StubSource(items: [StubItem(name: "Chậm", behaviour: .hang)]) })
        await state.openSource(kind: .csv, location: "x")
        state.toggle(try #require(state.items.first?.id))
        let running = Task { @MainActor in await state.load() }
        while state.progress < 0.5 { try await Task.sleep(for: .milliseconds(2)) }   // mục "Chậm" báo 0,5 rồi treo
        #expect(state.phase == .loading)
        state.cancelLoad()
        let result = await running.value
        #expect(result == nil)
        #expect(state.phase == .ready)
        #expect(state.loaded.isEmpty)
        #expect(state.canLoad)   // bấm Load lại được
    }

    @Test func cancellingTheCallerTaskAlsoCancelsTheLoad() async throws {
        let state = NavigatorState(makeSource: { _, _ in StubSource(items: [StubItem(name: "Chậm", behaviour: .hang)]) })
        await state.openSource(kind: .csv, location: "x")
        state.toggle(try #require(state.items.first?.id))
        let running = Task { @MainActor in await state.load() }
        while state.progress < 0.5 { try await Task.sleep(for: .milliseconds(2)) }
        running.cancel()
        #expect(await running.value == nil)
        #expect(state.phase == .ready)
    }

    @Test func aBrokenPreviewDoesNotBreakTheNavigator() async throws {
        let state = NavigatorState(makeSource: { _, _ in StubSource(items: [StubItem(name: "A", behaviour: .previewFails("Cột BLOB chưa hỗ trợ."))]) })
        await state.openSource(kind: .sqlite, location: "x")
        await state.showPreview(try #require(state.items.first?.id))
        #expect(state.preview == nil)
        #expect(state.previewError == "Cột BLOB chưa hỗ trợ.")
        #expect(state.phase == .ready)
    }
}

// MARK: - Tên bảng

@Suite struct TableNamingTests {
    @Test func freeNameIsKeptAsIs() {
        #expect(TableNaming.uniqueName("Sales", taken: ["Customers"]) == "Sales")
    }

    @Test func takenNameGetsCounterStartingAtTwoAndSkipsUsedOnes() {
        #expect(TableNaming.uniqueName("Sales", taken: ["Sales"]) == "Sales (2)")
        #expect(TableNaming.uniqueName("Sales", taken: ["sales", "Sales (2)", "SALES (3)"]) == "Sales (4)")
    }

    @Test func blankNameBecomesTable() {
        #expect(TableNaming.uniqueName("  ", taken: []) == "Table")
        #expect(TableNaming.uniqueName("", taken: ["Table"]) == "Table (2)")
    }
}

// MARK: - Nguồn giả cho ca lỗi và huỷ (biên của giao thức, không có file nào gây đúng các lỗi này)

private struct StubSource: DataSource {
    let kind: SourceKind = .csv
    let items: [StubItem]
    func items() async throws -> [any SourceItem] { items }
}

private struct StubItem: SourceItem {
    enum Behaviour: Sendable { case succeed, fail(String), hang, previewFails(String) }
    let name: String
    let behaviour: Behaviour
    var kind: SourceItemKind { .sheet }
    var columns: [SourceColumn]? { nil }
    var rowCountHint: Int? { nil }

    func preview(limit: Int) async throws -> TableData {
        if case .previewFails(let reason) = behaviour { throw SourceError.unreadable(reason) }
        return try Self.table()
    }

    func load(progress: SourceProgress?) async throws -> TableData {
        switch behaviour {
        case .succeed, .previewFails:
            progress?(1)
            return try Self.table()
        case .fail(let reason):
            throw SourceError.unreadable(reason)
        case .hang:
            progress?(0.5)
            while true {
                try Task.checkCancellation()   // CancellationError hoặc SourceError.cancelled đều phải được xử lý như huỷ
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    private static func table() throws -> TableData {
        try TableData(columns: [TableColumn(name: "A", data: ColumnBuilder.integers([1, 2, 3]))])
    }
}
