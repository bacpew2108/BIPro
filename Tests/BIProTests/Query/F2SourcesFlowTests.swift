// specs/011, US6 (T045): tài liệu mới → Get Data ▸ PostgreSQL `f15.public.types_f15` (timestamptz, time, interval, bytea, mảng) và
// SQLite với driver ODBC khác Devart → lưu → mở lại. Mô hình như Desktop (VM-F15): bytea bị bỏ, time định dạng "Long Time", interval là số
// ngày, mảng là chữ; M SQLite ghi driver đã chọn. Để lại `build/f2-out/f15/bipro-f15.pbix` cho gate T046. Cần `BIPRO_PG` (CSDL sales; bảng
// thử ở CSDL f15 cùng máy chủ), thiếu thì bỏ qua.
import ColumnStore
import Connectors
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Đợt F2: nguồn PostgreSQL kiểu mới và SQLite driver khác", .serialized) @MainActor
struct F2SourcesFlowTests {
    private static var config: (server: String, user: String, password: String)? {
        guard let raw = ProcessInfo.processInfo.environment["BIPRO_PG"] else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else { return nil }
        return (parts[0], parts[2], parts[3])
    }

    private func waitReady(_ navigator: NavigatorState) async throws {
        for _ in 0..<400 where navigator.phase == .listingItems || navigator.databaseForm?.isConnecting == true {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(navigator.phase == .ready)
    }

    @Test func napPostgresKieuMoiVaSQLiteRoiLuu() async throws {
        guard let config = Self.config, let sqlite = FFixtures.sample("sales_2026.sqlite") else { return }
        let server = config.server.replacingOccurrences(of: "127.0.0.1", with: "10.211.55.2")
        let vault = CredentialVault(service: "BI Pro test \(UUID().uuidString)")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f15-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        state.showGetData(kind: .postgres, credentials: vault)
        let navigator = try #require(state.getDataState)
        navigator.databaseForm?.server = server
        navigator.databaseForm?.database = "f15"
        await navigator.submitDatabaseAddress()
        navigator.databaseForm?.user = config.user
        navigator.databaseForm?.password = config.password
        navigator.databaseForm?.savePassword = false
        await navigator.submitDatabaseCredentials()
        await navigator.acceptUnencrypted()
        try await waitReady(navigator)
        navigator.toggle(try #require(navigator.items.first { $0.name == "public.types_f15" }).id)
        let pg = try #require(await navigator.load(existingNames: state.existingTableNames))
        #expect(state.loadFromGetData(pg) == nil)
        state.closeGetData()

        // SQLite: driver đã chọn ghi vào M (T044).
        let defaultsName = "bipro-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let sqliteNavigator = NavigatorState(odbcDefaults: defaults)
        sqliteNavigator.odbcDriver = "SQLite3 ODBC Driver"
        await sqliteNavigator.openSource(kind: .sqlite, location: sqlite.path)
        sqliteNavigator.toggle(try #require(sqliteNavigator.items.first { $0.name == "Customers" }).id)
        let customers = try #require(await sqliteNavigator.load(existingNames: state.existingTableNames))
        #expect(state.loadFromGetData(customers) == nil)

        let model = try #require(state.workspace.metadata)
        let columns = model.columns.filter { $0.tableName == "public types_f15" && $0.kind == .data }
        #expect(columns.map(\.name) == ["id", "tz", "t", "iv", "ia", "ta"])          // bytea bỏ
        #expect(columns.first { $0.name == "t" }?.formatString == "Long Time")
        #expect(columns.first { $0.name == "iv" }?.dataType == .double)
        #expect(columns.first { $0.name == "ia" }?.dataType == .string)

        let destination = try F2Fixtures.outputDirectory("f15").appendingPathComponent("bipro-f15.pbix")
        try? FileManager.default.removeItem(at: destination)
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)
        let reopened = try Workspace(data: Data(contentsOf: destination))
        let saved = try #require(reopened.metadata)
        #expect(saved.partitionQueries["public types_f15"]?.contains("PostgreSQL.Database(\"\(server)\", \"f15\")") == true)
        #expect(saved.partitionQueries["Customers"]?.contains("Driver={SQLite3 ODBC Driver}") == true)
        #expect(saved.columns.first { $0.tableName == "public types_f15" && $0.name == "t" }?.formatString == "Long Time")
        let result = try await reopened.daxEngine().run("""
            EVALUATE ROW("iv", SUM('public types_f15'[iv]), "n", COUNTROWS('public types_f15'), "a", MAX('public types_f15'[ia]), "c", COUNTROWS(Customers))
            """)
        let row = try #require(result.tables.first?.rows.first)
        // interval: 1.0854… − 0.1041… + 32 + (−417) + 5,787e-6
        if case .double(let sum) = row[0] { #expect(abs(sum - (1 + 7384.0 / 86_400 - 2.5 / 24 + 32 - 417 + 0.5 / 86_400)) < 1e-9) }
        else { Issue.record("iv: \(row[0])") }
        #expect(row[1] == .integer(6) && row[3] == .integer(50))
    }
}
