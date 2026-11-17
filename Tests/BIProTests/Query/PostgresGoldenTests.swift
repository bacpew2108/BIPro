// Phase F, T092–T093 (US8): nạp PostgreSQL như Desktop. Golden: `docs/phase-f-evidence/vm-f7/f7db-desktop.pbix` do Desktop 2.159 lưu
// sau khi nạp `public.north_sales`, `kho.ton_kho`, `public.sales` và câu SQL `Query1` từ máy chủ `10.211.55.2:55432` (VM-F7b,
// `QUAN-SAT-DB.md`): văn bản M, kiểu cột mô hình và từng dòng VertiPaq. Cần máy chủ thử (biến `BIPRO_PG`, xem `PostgresSourceTests`):
// địa chỉ `10.211.55.2` là chính máy Mac (cầu Parallels) nên M của Desktop chạy nguyên văn. Thiếu tệp hoặc máy chủ thì bỏ qua.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite(.serialized) struct PostgresGoldenTests {
    private static let goldenURL = FFixtures.root.appendingPathComponent("docs/phase-f-evidence/vm-f7/f7db-desktop.pbix")
    static let desktopServer = "10.211.55.2:55432"
    static let sql = "select region, count(*) as so_don, sum(amount) as doanh_thu from sales group by region order by region"

    /// Máy chủ thử ghi dưới tên máy chủ Desktop dùng (cùng máy), chỉ trong phiên. `nil` khi thiếu golden hoặc máy chủ.
    private static func setUp() throws -> (golden: Workspace, vault: CredentialVault)? {
        guard FileManager.default.fileExists(atPath: goldenURL.path), let raw = ProcessInfo.processInfo.environment["BIPRO_PG"] else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else { return nil }
        let vault = CredentialVault(service: "BI Pro test \(UUID().uuidString)")
        try vault.set(PostgresCredential(user: parts[2], password: parts[3], allowUnencrypted: true), for: desktopServer, persist: false)
        return (try Workspace(data: Data(contentsOf: goldenURL)), vault)
    }

    private func squeeze(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    private func navigator(_ vault: CredentialVault, sql: String = "") async -> NavigatorState {
        let state = NavigatorState(credentials: vault)
        state.beginDatabase(.postgres)
        state.databaseForm?.server = Self.desktopServer
        state.databaseForm?.database = "sales"
        state.databaseForm?.sql = sql
        await state.submitDatabaseAddress()
        return state
    }

    /// Bảng khớp bảng Desktop lưu: tên, kiểu cột mô hình, số dòng, từng ô sau khi xếp theo cột đầu (VertiPaq không giữ thứ tự dòng).
    /// Ngày giờ so với dung sai 1/300 giây (độ phân giải Desktop, VM-F7a).
    private func expectMatchesDesktop(_ data: TableData, desktopName: String, golden: Workspace) throws {
        let model = try #require(golden.metadata)
        let engine = try golden.daxEngine()
        let columns = model.columns.filter { $0.tableName == desktopName && $0.kind == .data }
        #expect(data.columns.map(\.name) == columns.map(\.name))
        #expect(data.columns.map { TableLoader.modelType($0.data.type) } == columns.map(\.dataType))
        let rows = try engine.store.rowCount(try #require(engine.store.schema.column(table: desktopName, name: columns[0].name)?.id).table)
        #expect(data.rowCount == rows)
        var desktop = Array(repeating: [StoredValue](), count: rows)
        for column in columns {
            let stored = try engine.store.column(try #require(engine.store.schema.column(table: desktopName, name: column.name)?.id))
            for row in 0..<rows { desktop[row].append(stored.value(at: row)) }
        }
        let ours = (0..<data.rowCount).map { row in data.columns.map { $0.data.value(at: row) } }
        func key(_ r: [StoredValue]) -> String { "\(r[0])" }
        let tick = 1.0 / (86_400 * 300) + 1e-12
        var mismatches: [String] = []
        for (a, b) in zip(ours.sorted { key($0) < key($1) }, desktop.sorted { key($0) < key($1) }) {
            for (x, y) in zip(a, b) where x != y {
                if case .dateTime(let u) = x, case .dateTime(let v) = y, abs(u - v) <= tick { continue }
                if case .double(let u) = x, case .double(let v) = y, abs(u - v) <= 1e-9 * max(1, abs(v)) { continue }
                mismatches.append("\(a[0]): \(x) ≠ \(y)")
            }
        }
        #expect(mismatches.isEmpty, Comment(rawValue: "\(desktopName): \(mismatches.count) ô lệch, ví dụ \(mismatches.prefix(4))"))
    }

    @Test func navigatorNapNhuDesktop() async throws {
        guard let (golden, vault) = try Self.setUp() else { return }
        let state = await navigator(vault)
        #expect(state.phase == .ready)
        #expect(state.items.map(\.name) == ["public.north_sales", "kho.ton_kho", "public.customers", "public.sales"])
        for name in ["public.north_sales", "kho.ton_kho", "public.sales"] {
            state.toggle(try #require(state.items.first { $0.name == name }).id)
        }
        let tables = try #require(await state.load())
        #expect(tables.map(\.name) == ["public north_sales", "kho ton_kho", "public sales"])
        let queries = try #require(golden.metadata?.partitionQueries)
        for table in tables {
            #expect(squeeze(try #require(table.queryDefinition)) == squeeze(try #require(queries[table.name])))
            try expectMatchesDesktop(table.data, desktopName: table.name, golden: golden)
        }
    }

    @Test func cauSQLNhuDesktop() async throws {
        guard let (golden, vault) = try Self.setUp() else { return }
        let state = await navigator(vault, sql: Self.sql)
        #expect(state.items.map(\.name) == ["Query1"])
        #expect(state.checkedItemIDs.count == 1)   // một mục, đánh dấu sẵn
        let table = try #require(await state.load()?.first)
        #expect(table.name == "Query1")
        #expect(squeeze(try #require(table.queryDefinition)) == squeeze(try #require(golden.metadata?.partitionQueries["Query1"])))
        try expectMatchesDesktop(table.data, desktopName: "Query1", golden: golden)
    }

    /// M của Desktop (Refresh, sửa tay) chạy nguyên văn trong BI Pro và ra đúng bảng Desktop.
    @Test func mCuaDesktopChayDuoc() async throws {
        guard let (golden, vault) = try Self.setUp() else { return }
        for (name, text) in try #require(golden.metadata?.partitionQueries) where !name.contains("DateTable") {
            let environment = MEnvironment(bindings: SourceFunctions.bindings(credentials: vault))
            let value = try await MEvaluator(environment: environment).evaluate(source: text)
            guard case .table(let data) = value else { Issue.record("\(name): không phải bảng"); continue }
            try expectMatchesDesktop(data, desktopName: name, golden: golden)
        }
    }

    @Test func saiMatKhauQuayLaiBuocDangNhap() async throws {
        guard let (_, vault) = try Self.setUp() else { return }
        let good = try #require(vault.credential(for: Self.desktopServer))
        try vault.set(PostgresCredential(user: good.user, password: "sai", allowUnencrypted: true), for: Self.desktopServer, persist: false)
        let state = await navigator(vault)
        #expect(state.phase == .choosingSource)
        #expect(state.databaseForm?.step == .credentials)
        #expect(state.databaseForm?.user == good.user)
        #expect(state.databaseForm?.warning == "Không xác thực được bằng thông tin đăng nhập đã nhập. Hãy thử lại.")
        state.databaseForm?.password = good.password
        state.databaseForm?.savePassword = false
        await state.submitDatabaseCredentials()
        #expect(state.phase == .ready)
        #expect(state.items.count == 4)
    }

    @Test func khongMaHoaPhaiHoi() async throws {
        guard let (_, vault) = try Self.setUp() else { return }
        var credential = try #require(vault.credential(for: Self.desktopServer))
        credential.allowUnencrypted = false
        try vault.set(credential, for: Self.desktopServer, persist: false)
        let state = await navigator(vault)
        #expect(state.databaseForm?.step == .encryption)
        await state.acceptUnencrypted()
        #expect(state.phase == .ready)
        #expect(vault.credential(for: Self.desktopServer)?.allowUnencrypted == true)
    }
}
