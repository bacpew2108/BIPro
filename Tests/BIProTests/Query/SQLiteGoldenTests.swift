// Phase F, T091–T093 (US8): nạp SQLite như Desktop. Desktop 2.159 không có connector SQLite riêng; đi qua Get Data ▸ ODBC với driver
// "Devart ODBC Driver for SQLite" (VM-F7b, `docs/phase-f-evidence/vm-f7/QUAN-SAT-DB.md`). Golden `vm-f7/f7sqlite-desktop.pbix`: văn bản M,
// kiểu cột mô hình và từng dòng của `Sales`, `Customers`, khung nhìn `NorthSales` từ `sales_2026.sqlite`. Driver Devart mặc định đổi chữ
// sang mã ANSI nên Desktop làm hỏng chữ tiếng Việt ("Đồng hồ" → "Ð?ng h?"): ô chữ chỉ so khi giá trị là ASCII; BI Pro giữ đúng UTF-8.
// Thiếu tệp thì bỏ qua.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite struct SQLiteGoldenTests {
    private static let goldenURL = FFixtures.root.appendingPathComponent("docs/phase-f-evidence/vm-f7/f7sqlite-desktop.pbix")
    private static let desktopPath = #"C:\Users\bacpew\f7db\sales_2026.sqlite"#

    private static func golden() throws -> (Workspace, URL)? {
        guard FileManager.default.fileExists(atPath: goldenURL.path), let sample = FFixtures.sample("sales_2026.sqlite") else { return nil }
        return (try Workspace(data: Data(contentsOf: goldenURL)), sample)
    }

    private func squeeze(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

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
        func key(_ r: [StoredValue]) -> Int64 { if case .integer(let v) = r[0] { v } else { .min } }
        var mismatches: [String] = []
        var compared = 0
        for (a, b) in zip(ours.sorted { key($0) < key($1) }, desktop.sorted { key($0) < key($1) }) {
            for (x, y) in zip(a, b) {
                if case .string(let s) = x, !s.allSatisfy(\.isASCII) { continue }   // Desktop + Devart hỏng chữ có dấu
                compared += 1
                if x != y { mismatches.append("\(a[0]): \(x) ≠ \(y)") }
            }
        }
        #expect(compared > rows)
        #expect(mismatches.isEmpty, Comment(rawValue: "\(desktopName): \(mismatches.count) ô lệch, ví dụ \(mismatches.prefix(4))"))
    }

    @Test func navigatorNapNhuDesktop() async throws {
        guard let (golden, sample) = try Self.golden() else { return }
        let state = NavigatorState()
        await state.openSource(kind: .sqlite, location: sample.path)
        #expect(state.phase == .ready)
        // Desktop (VM-F7b): khung nhìn trước, rồi bảng theo tên.
        #expect(state.items.map(\.name) == ["NorthSales", "Customers", "Sales"])
        for item in state.items { state.toggle(item.id) }
        let tables = try #require(await state.load())
        #expect(tables.map(\.name) == ["NorthSales", "Customers", "Sales"])
        let queries = try #require(golden.metadata?.partitionQueries)
        for table in tables {
            let desktopM = try #require(queries[table.name]).replacingOccurrences(of: Self.desktopPath, with: sample.path)
            #expect(squeeze(try #require(table.queryDefinition)) == squeeze(desktopM))
            try expectMatchesDesktop(table.data, desktopName: table.name, golden: golden)
        }
    }

    /// M của Desktop (đổi đường dẫn tệp sang máy này) chạy được trong BI Pro: `Odbc.DataSource` với driver SQLite đọc thẳng tệp.
    @Test func mCuaDesktopChayDuoc() async throws {
        guard let (golden, sample) = try Self.golden() else { return }
        for (name, text) in try #require(golden.metadata?.partitionQueries) where !name.contains("DateTable") {
            let source = text.replacingOccurrences(of: Self.desktopPath, with: sample.path)
            let value = try await MEvaluator(environment: MEnvironment(bindings: SourceFunctions.bindings)).evaluate(source: source)
            guard case .table(let data) = value else { Issue.record("\(name): không phải bảng"); continue }
            try expectMatchesDesktop(data, desktopName: name, golden: golden)
        }
    }

    @Test func driverKhacBaoChuaHoTro() async {
        let m = #"Odbc.DataSource("Driver={Microsoft Access Driver (*.mdb, *.accdb)};Dbq=C:\x.accdb", [HierarchicalNavigation=true])"#
        do {
            _ = try await MEvaluator(environment: MEnvironment(bindings: SourceFunctions.bindings)).evaluate(source: m)
            Issue.record("phải báo chưa hỗ trợ")
        } catch let error as MError {
            #expect(error.message.contains("Microsoft Access Driver"))
        } catch { Issue.record("lỗi lạ: \(error)") }
    }
}
