// specs/011, US6 (T041): các kiểu PostgreSQL timestamptz, time, interval, bytea và mảng như Desktop 2.159 (VM-F15,
// `docs/phase-f2-evidence/vm-f15/QUAN-SAT.md`): timestamptz → ngày giờ theo múi giờ máy; time → giờ trong ngày (Time, ngày 1899-12-30);
// interval → khoảng thời gian, đơn vị ngày, tháng = 30 ngày; bytea → Binary (mô hình bỏ cột); mảng → chữ dạng PostgreSQL in ra.
// Phần đổi chữ chạy không cần máy chủ; phần đọc bảng `f15.public.types_f15` cần `BIPRO_PG` (CSDL thay bằng f15), thiếu thì bỏ qua.
import Foundation
import Testing
import ColumnStore
@testable import Connectors

@Suite struct PostgresTypesTests {
    @Test func doiChuInterval() {
        #expect(PostgresTableBuilder.intervalDays("1 day 02:03:04") == 1 + Double(2 * 3600 + 3 * 60 + 4) / 86_400)
        #expect(PostgresTableBuilder.intervalDays("-02:30:00") == -2.5 / 24)
        #expect(PostgresTableBuilder.intervalDays("1 mon 2 days") == 32)
        #expect(PostgresTableBuilder.intervalDays("-1 years -2 mons +3 days") == -417)
        #expect(PostgresTableBuilder.intervalDays("00:00:00.5") == 0.5 / 86_400)
        #expect(PostgresTableBuilder.intervalDays("3 days -01:00:00") == 3 - 1.0 / 24)
    }

    @Test func doiChuTimeVaTimestamptz() throws {
        #expect(PostgresTableBuilder.timeOfDay("23:59:59.5") == 86_399.5 / 86_400)
        #expect(PostgresTableBuilder.timeOfDay("08:30:00") == 8.5 / 24)
        let bangkok = try #require(TimeZone(identifier: "Asia/Bangkok"))
        // VM-F15: 08:30+07 → 08:30 giờ máy (+07); 08:30:00.25-05 → 20:30:00.25.
        let a = try #require(PostgresTableBuilder.localDateTime("2026-03-01 01:30:00+00", zone: bangkok))
        #expect(abs(a - (46_082 + 8.5 / 24)) < 1e-9)
        let b = try #require(PostgresTableBuilder.localDateTime("2026-03-01 08:30:00.25-05", zone: bangkok))
        #expect(abs(b - (46_082 + (20.5 * 3600 + 0.25) / 86_400)) < 1e-9)
        let c = try #require(PostgresTableBuilder.localDateTime("1999-06-15 12:00:00+05:30", zone: bangkok))
        #expect(abs(c - (36_326 + 13.5 / 24)) < 1e-9)
    }

    @Test func napBangKieuMoi() async throws {
        guard let (address, credential) = PGFixture.config else { return }
        let f15 = PostgresAddress(server: address.server, database: "f15")
        let item = try #require(try await PostgresSource(address: f15, credential: credential).items().first { $0.name == "public.types_f15" })
        let table = try await item.load(progress: nil)
        #expect(table.columns.map(\.name) == ["id", "tz", "t", "iv", "b", "ia", "ta"])
        let c = Dictionary(uniqueKeysWithValues: table.columns.map { ($0.name, $0) })
        #expect(c["tz"]?.sourceType == nil && c["tz"]?.data.type == .dateTime)
        #expect(c["t"]?.sourceType == .time && c["t"]?.data.type == .dateTime)
        #expect(c["iv"]?.sourceType == .duration && c["iv"]?.data.type == .double)
        #expect(c["b"]?.sourceType == .binary)
        #expect(c["ia"]?.data.type == .string && c["ta"]?.data.type == .string)
        #expect(c["iv"]?.data.value(at: 2) == .double(32))
        #expect(c["iv"]?.data.value(at: 4) == .double(-417))
        #expect(c["iv"]?.data.value(at: 3) == .blank)
        #expect(c["t"]?.data.value(at: 1) == .dateTime(86_399.5 / 86_400))
        #expect(c["ia"]?.data.value(at: 1) == .string("{1,NULL,3}"))
        #expect(c["ia"]?.data.value(at: 2) == .string("{{1,2},{3,4}}"))
        #expect(c["ta"]?.data.value(at: 5) == .string("{\"có \\\"ngoặc\\\"\",\"x,y\"}"))
        #expect(c["ia"]?.data.value(at: 4) == .string("{}"))
        // timestamptz theo múi giờ máy chạy BI Pro (như Desktop theo múi giờ Windows).
        let expected = try #require(PostgresTableBuilder.localDateTime("2026-12-31 23:00:00+00", zone: .current))
        #expect(c["tz"]?.data.value(at: 2) == .dateTime(expected))
    }
}
