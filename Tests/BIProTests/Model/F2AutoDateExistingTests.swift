// T066 (FR-015): file Desktop đã bật Auto date/time (`w8.3.pbix`, bản sao ở `build/f2-out/f11/w83_f2.pbix`). Nạp thêm bảng có cột ngày,
// thay dữ liệu một bảng có bảng ngày cục bộ, lưu, mở lại: bảng ngày cục bộ theo khoảng năm mới; rồi xoá một bảng có cột ngày, lưu, mở lại:
// bộ bảng ngày của nó đi theo. Để lại file cho gate T037. Thiếu `w8.3.pbix` thì bỏ qua.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite(.enabled(if: F2Fixtures.w83 != nil), .serialized)
struct F2AutoDateExistingTests {
    private static let replaced = "Thông tin nhân viên"
    private static let replacedDate = "Ngày sinh"

    private func state(_ url: URL) throws -> DocumentState {
        DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
    }

    private func save(_ state: DocumentState, _ url: URL) throws {
        let backups = url.deletingLastPathComponent().appendingPathComponent("Backups")
        defer { try? FileManager.default.removeItem(at: backups) }
        #expect(try DocumentSaver.save(editor: state.layout, source: url, to: url, expectedStamp: nil, readOnlyRoots: [], backupDirectory: backups).didWrite)
    }

    /// Bảng đang có, đọc qua engine, với cột ngày `shifted` dời `years` năm.
    private func table(_ name: String, in state: DocumentState, shifting shifted: String, years: Int) async throws -> TableData {
        let engine = try await state.workspace.daxEngine()
        let result = try #require(try await engine.execute("EVALUATE '\(name)'").tables.first)
        let columns = state.workspace.columns(of: name)
        return try TableData(columns: columns.enumerated().map { index, column in
            let cells = result.rows.map { $0[index] }
            let data: ColumnData
            switch column.dataType {
            case .int64: data = ColumnBuilder.integers(cells.map { if case .integer(let i) = $0 { i } else { nil } })
            case .string: data = ColumnBuilder.strings(cells.map { if case .string(let s) = $0 { s } else { nil } })
            case .dateTime:
                let shift = column.name == shifted ? Double(years) * 365.25 : 0
                data = ColumnBuilder.dateTimes(cells.map { if case .dateTime(let d) = $0 { (d + shift).rounded(.down) } else { nil } })
            default: data = ColumnBuilder.doubles(cells.map { if case .double(let d) = $0 { d } else { nil } })
            }
            return TableColumn(name: column.name, data: data)
        })
    }

    private func years(_ workspace: Workspace, table: String, column: String) async throws -> (Int64, Int64)? {
        guard let local = workspace.metadata?.variations.first(where: { $0.table == table && $0.column == column })?.hierarchy.table else { return nil }
        let engine = try await workspace.daxEngine()
        let row = try #require(try await engine.execute("EVALUATE ROW(\"a\", MIN('\(local)'[Year]), \"b\", MAX('\(local)'[Year]))").tables.first?.rows.first)
        guard case .integer(let a) = row[0], case .integer(let b) = row[1] else { return nil }
        return (a, b)
    }

    @Test func napThayXoaRoiLuu() async throws {
        let url = try #require(try F2Fixtures.copy(F2Fixtures.w83, folder: "f11", fileName: "w83_f2.pbix"))
        let first = try state(url)
        let model = try #require(first.workspace.metadata)
        #expect(AutoDateTime.isEnabled(model))
        #expect(model.variations.contains { $0.table == Self.replaced && $0.column == Self.replacedDate }, "\(model.variations.map { "\($0.table)[\($0.column)]" })")

        // Nạp hai bảng mới có cột ngày; thay dữ liệu bảng lương với ngày dời 10 năm.
        let project = try TableData(columns: [
            TableColumn(name: "Mã dự án", data: ColumnBuilder.integers([1, 2])),
            TableColumn(name: "Ngày bắt đầu", data: ColumnBuilder.dateTimes([47_484, 47_900])),   // 2030, 2031
        ])
        let event = try TableData(columns: [
            TableColumn(name: "Mã sự kiện", data: ColumnBuilder.integers([1])),
            TableColumn(name: "Ngày sự kiện", data: ColumnBuilder.dateTimes([51_136])),          // 2040
        ])
        let salary = try await table(Self.replaced, in: first, shifting: Self.replacedDate, years: 10)
        #expect(first.loadFromGetData([LoadedTable(name: "Dự án", data: project), LoadedTable(name: "Sự kiện", data: event),
                                       LoadedTable(name: Self.replaced, data: salary, status: .replaced)]) == nil)
        try save(first, url)

        let second = try state(url)
        let saved = try #require(second.workspace.metadata)
        #expect(saved.variations.contains { $0.table == "Dự án" && $0.column == "Ngày bắt đầu" })
        #expect(saved.variations.contains { $0.table == "Sự kiện" })
        #expect(try await years(second.workspace, table: "Dự án", column: "Ngày bắt đầu").map { [$0.0, $0.1] } == [2030, 2031])
        let engine = try await second.workspace.daxEngine()
        let range = try #require(try await engine.execute("EVALUATE ROW(\"a\", YEAR(MIN('\(Self.replaced)'[\(Self.replacedDate)])), \"b\", YEAR(MAX('\(Self.replaced)'[\(Self.replacedDate)])))").tables.first?.rows.first)
        guard case .integer(let lo) = range[0], case .integer(let hi) = range[1] else { Issue.record("\(range)"); return }
        #expect(try await years(second.workspace, table: Self.replaced, column: Self.replacedDate).map { [$0.0, $0.1] } == [lo, hi])
        #expect(lo >= 1990)   // gốc 1980–1999, dời 10 năm
        // Cột ngày ở phía nhiều của quan hệ (tới bảng `Ngày`) không có bảng ngày, như file Desktop.
        #expect(!saved.variations.contains { $0.table == Self.replaced && $0.column == "Ngày làm việc" })

        // Xoá một bảng có cột ngày: bộ bảng ngày của nó đi theo, bảng mẫu còn.
        let localsBefore = saved.tables.filter { AutoDateTime.isLocalTable($0.name) }.count
        #expect(second.modelEditor.apply(.dropTable(name: "Sự kiện")) == nil)
        try save(second, url)
        let third = try #require(try state(url).workspace.metadata)
        #expect(!third.userTables.contains { $0.name == "Sự kiện" })
        #expect(!third.variations.contains { $0.table == "Sự kiện" })
        #expect(third.tables.filter { AutoDateTime.isLocalTable($0.name) }.count == localsBefore - 1)
        #expect(third.tables.filter { AutoDateTime.isTemplateTable($0.name) }.count == 1)
    }
}
