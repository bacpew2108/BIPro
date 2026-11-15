// Phase F, T061 (FR-014): liệt kê đúng truy vấn và biểu thức Desktop đã ghi trong file (Nhom6, mười một bảng nạp từ CSV bằng M nhiều bước).
import ColumnStore
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@MainActor
@Suite("Phase F: đọc truy vấn trong file", .enabled(if: EFixtures.metadata != nil)) struct QueryListingTests {
    let metadata = EFixtures.metadata!

    @Test func moFileDesktopLietKeDungTruyVanVaBieuThuc() throws {
        let state = QueryEditorState()
        state.addQueries(from: metadata) { _ in nil }
        let userTables = metadata.userTables.filter { metadata.partitionQueries[$0.name] != nil }
        #expect(state.queries.map(\.name) == userTables.map(\.name))
        #expect(state.queries.count >= 11)
        for query in state.queries {
            // Mỗi truy vấn tách thành nhiều bước đúng văn bản của file; dựng lại rồi tách lại cho cùng bước.
            let original = try MQuery.parse(try #require(metadata.partitionQueries[query.name]))
            #expect(query.steps.map(\.name) == original.steps.map(\.name))
            #expect(query.steps.map(\.expression) == original.steps.map(\.expression))
            #expect(try MQuery.parse(query.source).steps == original.steps)
            #expect(query.lockedStepCount == query.steps.count && query.loadedTableName == query.name && !query.isModified)
        }
        let account = try #require(state.queries.first { $0.name == "Dim_Account" })
        #expect(account.steps.prefix(3).map(\.name) == ["Source", "Headers", "Cleaned"])
        #expect(account.steps[0].expression == #"Csv.Document(File.Contents(DataFolder & "Dim_Account.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv])"#)
        #expect(!state.hasPendingChanges && !state.hasUnappliedQueries)
    }

    @Test func xemTruocBuocKhoaDungBangDangCoVaThemBuocSau() async throws {
        let table = try TableData(columns: [TableColumn(name: "Id", data: ColumnBuilder.integers([1, 2, 3]))])
        let state = QueryEditorState()
        state.addQueries(from: metadata) { $0 == "Dim_Account" ? table : nil }
        state.selectQuery(try #require(state.queries.first { $0.name == "Dim_Account" }).id)
        await state.refresh()
        #expect(state.preview?.rowCount == 3)
        #expect(state.perform(.keepTopRows(2)) == .applied)
        await state.refresh()
        #expect(state.preview?.rowCount == 2)
        #expect(state.hasUnappliedQueries)
        // Truy vấn khác không có dữ liệu: báo thiếu nguồn, không hỏng truy vấn đang sửa.
        state.selectQuery(try #require(state.queries.first { $0.name == "Dim_Client" }).id)
        await state.refresh()
        #expect(state.errorMessage == "Chưa có dữ liệu nguồn của truy vấn này.")
    }
}
