// specs/011, T044 (US6): tên driver ODBC SQLite ghi vào M không cố định "Devart": người dùng chọn driver có trên máy Desktop sẽ Refresh,
// BI Pro nhớ lựa chọn. Desktop không có connector SQLite riêng; M dạng `Odbc.DataSource("Driver={…};Database=…", [HierarchicalNavigation=true])`
// (VM-F7b với Devart). Thoát ký tự đặc biệt theo quy tắc chuỗi kết nối ODBC (`[SUY ĐOÁN]`, Desktop chưa quan sát với tên driver lạ).
import ColumnStore
import Connectors
import Foundation
import MEngine
import Testing
@testable import BIPro

@Suite struct SQLiteDriverTests {
    private func defaults() -> UserDefaults {
        let name = "bipro-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func macDinhLaDevartNhuVMF7b() {
        let d = defaults()
        #expect(SQLiteODBC.savedDriver(in: d) == "Devart ODBC Driver for SQLite")
        #expect(SQLiteODBC.connectionString(path: "C:\\a\\b.sqlite", driver: SQLiteODBC.defaultDriver)
                    == "Driver={Devart ODBC Driver for SQLite};Database=C:\\a\\b.sqlite")
    }

    @Test func nhoDriverDaChon() {
        let d = defaults()
        SQLiteODBC.save(driver: "SQLite3 ODBC Driver", in: d)
        #expect(SQLiteODBC.savedDriver(in: d) == "SQLite3 ODBC Driver")
        // Ô trống: về mặc định.
        SQLiteODBC.save(driver: "   ", in: d)
        #expect(SQLiteODBC.savedDriver(in: d) == SQLiteODBC.defaultDriver)
        #expect(SQLiteODBC.commonDrivers.contains("SQLite3 ODBC Driver") && SQLiteODBC.commonDrivers.first == SQLiteODBC.defaultDriver)
    }

    @Test func thoatKyTuDacBiet() {
        // Giá trị trong ngoặc nhọn: `}` nhân đôi. Đường dẫn có `;` hoặc `{` cũng phải bọc ngoặc.
        let s = SQLiteODBC.connectionString(path: "/tmp/a;b {x}.db", driver: "My }Driver; v2")
        #expect(s == "Driver={My }}Driver; v2};Database={/tmp/a;b {x}}.db}")
        let p = SQLiteODBC.properties(s)
        #expect(p["driver"] == "My }Driver; v2")
        #expect(p["database"] == "/tmp/a;b {x}.db")
        // Đường dẫn thường không bọc (như Desktop ghi).
        #expect(SQLiteODBC.connectionString(path: "/Users/x/My Data/s.sqlite", driver: "SQLite3 ODBC Driver")
                    == "Driver={SQLite3 ODBC Driver};Database=/Users/x/My Data/s.sqlite")
    }

    @Test func mDungDriverDaChon() throws {
        let origin = LoadedOrigin(kind: .sqlite, location: "/tmp/s.sqlite", itemName: "Sales", itemKind: .table, odbcDriver: "SQLite3 ODBC Driver")
        let steps = SourceQuery.steps(for: origin, data: try TableData(columns: [TableColumn(name: "a", data: ColumnBuilder.integers([1]))]))
        #expect(steps.first?.expression == #"Odbc.DataSource("Driver={SQLite3 ODBC Driver};Database=/tmp/s.sqlite", [HierarchicalNavigation=true])"#)
        // Không có driver (file cũ, test cũ): Devart.
        let old = LoadedOrigin(kind: .sqlite, location: "/tmp/s.sqlite", itemName: "Sales", itemKind: .table)
        #expect(SourceQuery.steps(for: old, data: try TableData(columns: [TableColumn(name: "a", data: ColumnBuilder.integers([1]))])).first?
            .expression.contains("Devart ODBC Driver for SQLite") == true)
    }

    /// M có driver lạ (tên không chứa "SQLite") vẫn chạy được trong BI Pro khi `Database=` trỏ tới tệp SQLite thật.
    @Test(.enabled(if: FFixtures.sample("sales_2026.sqlite") != nil))
    func driverLaVanDocDuoc() async throws {
        let path = try #require(FFixtures.sample("sales_2026.sqlite")).path
        for driver in ["Devart ODBC Driver for SQLite", "SQLite3 ODBC Driver", "CData ODBC Driver for SQLite", "Công ty X; bản {2}"] {
            let m = """
            let
                Source = Odbc.DataSource(\(StepFactory.quote(SQLiteODBC.connectionString(path: path, driver: driver))), [HierarchicalNavigation=true]),
                main_Database = Source{[Name="main",Kind="Database"]}[Data],
                Sales_Table = main_Database{[Name="Sales",Kind="Table"]}[Data]
            in
                Sales_Table
            """
            let env = MEnvironment(bindings: SourceFunctions.bindings(credentials: CredentialVault(service: "BI Pro test \(UUID().uuidString)")))
            guard case .table(let t) = try await MEvaluator(environment: env).evaluate(source: m, upTo: nil, rowLimit: nil) else {
                Issue.record("\(driver): không ra bảng"); continue
            }
            #expect(t.rowCount == 1000, "\(driver)")
        }
    }

    /// Tệp không phải SQLite với driver ODBC lạ: báo chưa hỗ trợ, nêu tên driver.
    @Test func khongPhaiSQLiteThiBaoChuaHoTro() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odbc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("x.db")
        try Data("not sqlite".utf8).write(to: file)
        let m = "Odbc.DataSource(\(StepFactory.quote(SQLiteODBC.connectionString(path: file.path, driver: "PostgreSQL Unicode"))), [HierarchicalNavigation=true])"
        let env = MEnvironment(bindings: SourceFunctions.bindings(credentials: CredentialVault(service: "BI Pro test \(UUID().uuidString)")))
        do {
            _ = try await MEvaluator(environment: env).evaluate(source: m, upTo: nil, rowLimit: nil)
            Issue.record("phải lỗi")
        } catch {
            #expect("\(error)".contains("PostgreSQL Unicode"))
        }
    }

    @MainActor @Test func navigatorGhiDriverVaoNguon() async throws {
        let d = defaults()
        let state = NavigatorState(odbcDefaults: d)
        #expect(state.odbcDriver == SQLiteODBC.defaultDriver)
        state.odbcDriver = "SQLite3 ODBC Driver"
        #expect(SQLiteODBC.savedDriver(in: d) == "SQLite3 ODBC Driver")
        #expect(NavigatorState(odbcDefaults: d).odbcDriver == "SQLite3 ODBC Driver")
    }
}
