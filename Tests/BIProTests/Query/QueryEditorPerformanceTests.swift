// Phase F, T064 (SC-003): Query Editor và Navigator trên file 1 triệu dòng. Xem trước 1000 dòng ở một bước đã tính phải đổi trong < 500 ms
// khi chuyển giữa các bước Applied Steps; Navigator mở và xem trước CSV 1 triệu dòng < 3 s. Chạy bản release:
// `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter QueryEditorPerformanceTests`.
// Con số đo được ghi ở specs/010-f-get-data-power-query-t3/measurements.md.
import ColumnStore
import Connectors
import Foundation
import MEngine
import Testing
@testable import BIPro

@Suite("Phase F: hiệu năng Query Editor 1 triệu dòng", .enabled(if: EFixtures.heavy), .serialized)
@MainActor
struct QueryEditorPerformanceTests {
    private static let rows = 1_000_000

    private func millionRows() throws -> TableData {
        let n = Self.rows
        return try TableData(columns: [
            TableColumn(name: "ID", data: ColumnBuilder.integers((0..<n).map { Int64($0) })),
            TableColumn(name: "ValInt", data: ColumnBuilder.integers((0..<n).map { Int64($0 % 1000) })),
            TableColumn(name: "Amount", data: ColumnBuilder.doubles((0..<n).map { Double($0) * 1.5 })),
            TableColumn(name: "Rate", data: ColumnBuilder.doubles((0..<n).map { Double($0 % 100) * 0.1 })),
            TableColumn(name: "Date", data: ColumnBuilder.dateTimes((0..<n).map { 46_000.0 + Double($0 % 365) })),
            TableColumn(name: "Cat1", data: ColumnBuilder.strings((0..<n).map { "Cat_\($0 % 50)" })),
            TableColumn(name: "Region", data: ColumnBuilder.strings((0..<n).map { "Region_\($0 % 5)" })),
            TableColumn(name: "Code", data: ColumnBuilder.strings((0..<n).map { "CODE_\($0 % 200)" })),
            TableColumn(name: "Status", data: ColumnBuilder.strings((0..<n).map { $0 % 2 == 0 ? "Active" : "Inactive" })),
            TableColumn(name: "Flag", data: ColumnBuilder.booleans((0..<n).map { $0 % 2 == 0 })),
        ])
    }

    private func seconds(_ body: () async throws -> Void) async rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try await body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    @Test func chuyenBuocApplyStepsDuoi500ms() async throws {
        let state = QueryEditorState()
        state.addQuery(from: LoadedTable(name: "Big", data: try millionRows(),
                                         origin: LoadedOrigin(kind: .csv, location: "/khong/co/big.csv", itemName: "Big", itemKind: .file)))
        await state.refresh()
        #expect(state.preview?.rowCount == 1000)

        // Thêm bước: tính mỗi bước một lần từ kết quả đầy đủ của bước trước (ghi lại, không là ngưỡng của SC-003).
        let commands: [(String, StepCommand)] = [
            ("lọc Region", .filterEquals(column: "Region", values: [.text("Region_1")])),
            ("sắp xếp giảm dần Amount", .sortRows([SortKey(column: "Amount", descending: true)])),
            ("bỏ cột Code", .removeColumns(["Code"])),
            ("giữ 500 dòng đầu", .keepTopRows(500)),
        ]
        var addTimes: [(String, Double)] = []
        for (label, command) in commands {
            let t = await seconds {
                #expect(state.perform(command) == .applied)
                await state.refresh()
            }
            #expect(state.errorMessage == nil, Comment(rawValue: "\(label): \(state.errorMessage ?? "")"))
            addTimes.append((label, t))
        }
        for (label, t) in addTimes { print("BENCHMARK QE 1M [thêm bước \(label)]: \(String(format: "%.3f", t)) s") }

        // Chuyển qua lại giữa các bước đã tính: SC-003 < 500 ms mỗi lần.
        let steps = try #require(state.selectedQuery?.steps.count)
        var worst = 0.0
        for round in 0..<3 {
            for index in (0..<steps).reversed() {
                let t = await seconds {
                    state.selectStep(index)
                    await state.refresh()
                }
                worst = max(worst, t)
                #expect(state.preview != nil && state.errorMessage == nil)
                #expect(t < 0.5, "vòng \(round), bước \(index): \(t) s")
            }
        }
        print("BENCHMARK QE 1M [chuyển bước, tệ nhất]: \(String(format: "%.3f", worst)) s")
    }

    @Test func navigatorXemTruocCSVMotTrieuDongDuoi3s() async throws {
        let dir = try FFixtures.outputDirectory("F-perf")
        let url = dir.appendingPathComponent("1m.csv")
        defer { try? FileManager.default.removeItem(at: url) }
        var text = "ID,ValInt,Amount,Region,Status\n"
        text.reserveCapacity(Self.rows * 40)
        for i in 0..<Self.rows { text += "\(i),\(i % 1000),\(Double(i) * 1.5),Region_\(i % 5),\(i % 2 == 0 ? "Active" : "Inactive")\n" }
        try text.write(to: url, atomically: true, encoding: .utf8)

        let navigator = NavigatorState()
        var itemID = ""
        let open = await seconds {
            await navigator.openSource(kind: .csv, location: url.path)
            itemID = navigator.items.first?.id ?? ""
            await navigator.showPreview(itemID)
        }
        print("BENCHMARK Navigator 1M CSV [mở + xem trước]: \(String(format: "%.3f", open)) s")
        #expect(navigator.phase == .ready && navigator.previewError == nil)
        #expect(navigator.preview?.rowCount == 200)
        #expect(open < 3.0, "\(open) s")
    }
}
