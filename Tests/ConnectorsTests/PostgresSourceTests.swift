import Testing
import Foundation
import ColumnStore
@testable import Connectors

/// Máy chủ thử: biến môi trường `BIPRO_PG = "máy:cổng;cơ_sở_dữ_liệu;người_dùng;mật_khẩu"` (không ghi mật khẩu vào repo).
/// Dữ liệu như buổi VM-F7b (`docs/phase-f-evidence/vm-f7/QUAN-SAT-DB.md`): `public.sales` (1 000 dòng của `sales_2026.sqlite`),
/// `public.customers` (50), khung nhìn `public.north_sales` (region = 'North'), `kho.ton_kho` (3 dòng đủ kiểu). Thiếu biến thì test bỏ qua.
enum PGFixture {
    static var config: (address: PostgresAddress, credential: PostgresCredential)? {
        guard let raw = ProcessInfo.processInfo.environment["BIPRO_PG"] else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else { return nil }
        return (PostgresAddress(server: parts[0], database: parts[1]), PostgresCredential(user: parts[2], password: parts[3], allowUnencrypted: true))
    }
}

@Suite struct PostgresSourceTests {
    @Test func addressParsesServerAndPort() {
        let a = PostgresAddress(server: "10.211.55.2:55432", database: "sales")
        #expect(a.host == "10.211.55.2" && a.port == 55432 && a.location == "10.211.55.2:55432;sales")
        #expect(PostgresAddress(server: "db.local", database: "x").port == 5432)
        #expect(PostgresAddress(location: "10.211.55.2:55432;sales") == a)
    }

    @Test func listsViewsThenTablesLikeDesktop() async throws {
        guard let (address, credential) = PGFixture.config else { return }
        let items = try await PostgresSource(address: address, credential: credential).items()
        // Desktop (VM-F7b): khung nhìn trước, rồi bảng theo lược đồ và tên; không có lược đồ hệ thống.
        #expect(items.map(\.name) == ["public.north_sales", "kho.ton_kho", "public.customers", "public.sales"])
        #expect(items.map(\.kind) == [.view, .table, .table, .table])
        // Tên truy vấn và bảng khi nạp: dấu chấm thành dấu cách.
        #expect(items.map(\.loadName) == ["public north_sales", "kho ton_kho", "public customers", "public sales"])
    }

    @Test func loadsTypesLikeDesktop() async throws {
        guard let (address, credential) = PGFixture.config else { return }
        let items = try await PostgresSource(address: address, credential: credential).items()
        let item = try #require(items.first { $0.name == "kho.ton_kho" })
        let table = try await item.load(progress: nil)
        #expect(table.rowCount == 3)
        #expect(table.columns.map(\.name) == ["id", "sku", "con_hang", "so_luong", "gia_von", "cap_nhat", "ghi_chu", "ma", "thuoc_tinh"])
        // Kiểu mô hình Desktop: bigint/integer → Int64, numeric → Double, boolean, timestamp → DateTime, uuid/jsonb → chữ.
        #expect(table.columns.map(\.data.type) == [.integer, .string, .boolean, .integer, .double, .dateTime, .string, .string, .string])
        let c = Dictionary(uniqueKeysWithValues: table.columns.map { ($0.name, $0.data) })
        #expect(c["id"]?.value(at: 0) == .integer(1))
        #expect(c["con_hang"]?.value(at: 1) == .boolean(false))
        #expect(c["con_hang"]?.value(at: 2) == .blank)
        #expect(c["gia_von"]?.value(at: 2) == .double(7.125))
        #expect(c["gia_von"]?.value(at: 1) == .blank)
        // 2026-03-02 17:45:12.5: ngày 46083 kể từ 1899-12-30.
        #expect(c["cap_nhat"]?.value(at: 1) == .dateTime(46083 + (17 * 3600 + 45 * 60 + 12.5) / 86400))
        #expect(c["ghi_chu"]?.value(at: 2) == .string("Ghi chú có dấu: Đà Nẵng"))
        #expect(c["ma"]?.value(at: 0) == .string("a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"))
        #expect(c["thuoc_tinh"]?.value(at: 0) == .string("{\"mau\": \"do\"}"))
    }

    @Test func salesMatchSQLiteSampleCellByCell() async throws {
        guard let (address, credential) = PGFixture.config, let url = FFixtures.sample("sales_2026.sqlite") else { return }
        let pgItem = try #require(try await PostgresSource(address: address, credential: credential).items().first { $0.name == "public.sales" })
        let sqliteItem = try #require(try await SQLiteSource(url: url).items().first { $0.name == "Sales" })
        let pg = try await pgItem.load(progress: nil)
        let lite = try await sqliteItem.load(progress: nil)
        #expect(pg.rowCount == 1000 && lite.rowCount == 1000)
        #expect(pg.columns.map(\.data.type) == [.integer, .dateTime, .string, .integer, .string, .integer, .double, .double])
        for (p, l) in zip(pg.columns, lite.columns) {
            // OrderDate trong tệp SQLite là TEXT "yyyy-MM-dd"; bên PostgreSQL là date.
            func expected(_ row: Int) -> StoredValue {
                guard p.name == "orderdate", case .string(let s) = l.data.value(at: row), let d = DateHelper.parseDateTime(s) else { return l.data.value(at: row) }
                return .dateTime(d)
            }
            for row in 0..<1000 where p.data.value(at: row) != expected(row) {
                Issue.record("\(p.name) dòng \(row): \(p.data.value(at: row)) ≠ \(l.data.value(at: row))")
                return
            }
        }
        let preview = try await pgItem.preview(limit: 7)
        #expect(preview.rowCount == 7)
    }

    @Test func nativeQueryIsOneItemNamedQuery1() async throws {
        guard let (address, credential) = PGFixture.config else { return }
        let sql = "select region, count(*) as so_don, sum(amount) as doanh_thu from sales group by region order by region"
        let items = try await PostgresSource(address: address, credential: credential, query: sql).items()
        #expect(items.map(\.name) == ["Query1"])
        #expect(items.first?.kind == .query)
        let table = try await items[0].load(progress: nil)
        #expect(table.columns.map(\.name) == ["region", "so_don", "doanh_thu"])
        #expect(table.columns.map(\.data.type) == [.string, .integer, .double])
        #expect(table.rowCount == 5)
        #expect(table.columns[1].data.value(at: 0) == .integer(205))   // East, như Desktop
    }

    @Test func wrongPasswordIsAuthenticationErrorWithoutPassword() async throws {
        guard let (address, credential) = PGFixture.config else { return }
        let wrong = PostgresCredential(user: credential.user, password: "sai-mat-khau-\(UUID().uuidString)", allowUnencrypted: true)
        do {
            _ = try await PostgresSource(address: address, credential: wrong).items()
            Issue.record("phải lỗi xác thực")
        } catch let SourceError.authentication(message) {
            #expect(!message.contains(wrong.password))
            #expect(!message.contains(credential.password))
        }
    }

    @Test func unencryptedNeedsConsent() async throws {
        guard let (address, credential) = PGFixture.config else { return }
        var noConsent = credential
        noConsent.allowUnencrypted = false
        await #expect(throws: SourceError.self) { _ = try await PostgresSource(address: address, credential: noConsent).items() }
        do { _ = try await PostgresSource(address: address, credential: noConsent).items() } catch SourceError.insecureConnection {
        } catch { Issue.record("mong insecureConnection, nhận \(error)") }
    }

    @Test func unsupportedTypeIsNamed() async throws {
        guard let (address, credential) = PGFixture.config else { return }
        let items = try await PostgresSource(address: address, credential: credential, query: "select interval '1 day' as khoang").items()
        do { _ = try await items[0].load(progress: nil); Issue.record("phải báo chưa hỗ trợ") } catch let SourceError.unsupported(what) {
            #expect(what.contains("interval") && what.contains("khoang"))
        }
    }

    @Test func unreachableServerIsReadableError() async throws {
        let address = PostgresAddress(server: "127.0.0.1:1", database: "x")
        do { _ = try await PostgresSource(address: address, credential: PostgresCredential(user: "u", password: "p")).items() }
        catch let SourceError.unreadable(message) { #expect(message.contains("127.0.0.1:1")) }
    }

    /// Hiệu năng (chỉ khi `BIPRO_HEAVY=1`, bản release): 1 triệu dòng × 4 cột (số nguyên, số thực, chữ, ngày) qua câu SQL.
    @Test func millionRowsLoadQuickly() async throws {
        guard ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1", let (address, credential) = PGFixture.config else { return }
        let sql = "select g as id, g * 1.5 as x, 'r' || (g % 50) as s, date '2026-01-01' + (g % 365) as d from generate_series(1, 1000000) g"
        let item = try #require(try await PostgresSource(address: address, credential: credential, query: sql).items().first)
        let clock = ContinuousClock()
        let start = clock.now
        let table = try await item.load(progress: nil)
        let elapsed = clock.now - start
        print("PostgreSQL 1 triệu dòng: \(elapsed)")
        #expect(table.rowCount == 1_000_000)
        #expect(table.columns.map(\.data.type) == [.integer, .double, .string, .dateTime])
        #expect(elapsed < .seconds(10))
    }
}
