// specs/011, US5 (T058): bảng lớn qua đường app đầy đủ.
// - Tài liệu mới + `big_10m.parquet` (10 triệu dòng × 10 cột, hơn một đoạn dữ liệu) + bảng nhỏ `Khach` (quan hệ tự phát hiện
//   `big_10m[CustomerID] → Khach[CustomerID]`) + cột tính toán → lưu < 2 phút, bộ nhớ đỉnh < 4 GB (SC-007), mở lại: số dòng, tổng,
//   đếm khác nhau và lọc qua quan hệ trùng số tính từ nguồn.
// - `repeat_1m.csv` (run dài): lưu, ghi cỡ tệp. So với `f14-rle-desktop.pbix` (≤ 125 %, SC-006) khi có tệp Desktop của buổi VM-F14.
// Chỉ chạy khi BIPRO_HEAVY=1, bản release:
// `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter F2LargeSaveTests`.
// Để lại tệp gate ở `build/f2-out/f14/`. Số đo ghi vào `specs/011-ton-dong-sau-phase-f/measurements.md`.
import ColumnStore
import Connectors
import DAXEngine
import Foundation
@testable import PBIXKit
import Testing
@testable import BIPro

@Suite("Đợt F2: lưu bảng lớn nhiều đoạn và RLE", .enabled(if: F2Fixtures.heavy), .serialized) @MainActor
struct F2LargeSaveTests {
    private func peakMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576
    }

    private func seconds(_ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    private func newDocument(_ root: URL) throws -> (DocumentState, URL) {
        let untitled = try UntitledDocuments.create(root: root)
        return (DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled), untitled)
    }

    private func load(_ state: DocumentState, kind: SourceKind, file: URL) async throws -> [LoadedTable] {
        state.showGetData(kind: kind, pickFile: { _ in file.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<2_000 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        state.closeGetData()
        return loaded
    }

    private func number(_ engine: DAXEngine, _ query: String) async throws -> [Value] {
        try await engine.run(query).tables.first?.rows.first ?? []
    }

    @Test func big10mNhieuDoanQuanHeCotTinhToan() async throws {
        let parquet = try #require(F2Fixtures.sample("big_10m.parquet"), "chạy python3 scripts/f2-samples/make_f2_samples.py --large")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f2big-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (state, untitled) = try newDocument(root)

        var loadSeconds = 0.0
        var big: [LoadedTable] = []
        let start = DispatchTime.now().uptimeNanoseconds
        big = try await load(state, kind: .parquet, file: parquet)
        let table = try #require(big.first)
        #expect(table.data.rowCount == 10_000_000)
        let khach = LoadedTable(name: "Khach", data: try TableData(columns: [
            TableColumn(name: "CustomerID", data: ColumnBuilder.integers((1...50).map { Int64($0) })),
            TableColumn(name: "Hang", data: ColumnBuilder.strings((1...50).map { $0 <= 10 ? "VIP" : "Thường" })),
        ]))
        #expect(state.loadFromGetData(big + [khach]) == nil)
        loadSeconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        let relationships = try #require(state.workspace.metadata).relationships
        #expect(relationships.contains { $0.fromTable == table.name && $0.fromColumn == "CustomerID" && $0.toTable == "Khach" })
        #expect(await state.addCalculatedColumn(table: table.name, formula: "Thanh tien = [Qty] * [Price]") == nil)

        let gate = try F2Fixtures.outputDirectory("f14").appendingPathComponent("bipro-f14-big.pbix")
        try? FileManager.default.removeItem(at: gate)
        let save = try seconds {
            let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: gate, readOnlyRoots: [],
                                                         backupDirectory: root.appendingPathComponent("Backups"))
            #expect(outcome.didWrite)
        }
        let peak = peakMegabytes()
        let size = (try FileManager.default.attributesOfItem(atPath: gate.path)[.size] as? Int) ?? 0
        print("BENCHMARK T058 [big_10m]: tải \(String(format: "%.1f", loadSeconds)) s, lưu \(String(format: "%.1f", save)) s, "
              + "tệp \(size / 1_048_576) MB, bộ nhớ đỉnh \(String(format: "%.0f", peak)) MB")
        #expect(save < 120, "SC-007: lưu \(save) s")
        #expect(peak < 4_096, "SC-007: bộ nhớ đỉnh \(peak) MB")

        // Số đúng tính thẳng từ dữ liệu nguồn.
        let data = table.data
        func ints(_ name: String) -> [Int64] {
            let column = data.columns.first { $0.name == name }!.data
            return (0..<data.rowCount).map { if case .integer(let v) = column.value(at: $0) { v } else { 0 } }
        }
        let customer = ints("CustomerID"), qty = ints("Qty")
        let vipQty = zip(customer, qty).reduce(Int64(0)) { $0 + ($1.0 <= 10 ? $1.1 : 0) }
        let totalQty = qty.reduce(0, +)

        let reopened = try Workspace(data: Data(contentsOf: gate))
        let model = try #require(reopened.metadata)
        #expect(model.relationships.contains { $0.fromTable == table.name && $0.toTable == "Khach" })
        let engine = try reopened.daxEngine()
        let name = "'\(table.name)'"
        let row = try await number(engine, """
            EVALUATE ROW("n", COUNTROWS(\(name)), "q", SUM(\(name)[Qty]), "c", DISTINCTCOUNT(\(name)[Batch]),
                "vip", CALCULATE(SUM(\(name)[Qty]), Khach[Hang] = "VIP"), "tt", COUNTROWS(FILTER(\(name), [Thanh tien] <> [Qty] * [Price])))
            """)
        #expect(row == [.integer(10_000_000), .integer(totalQty), .integer(1_000), .integer(vipQty), .blank], "\(row)")
        let segments = try VertiPaq.parseIDFMeta(
            Data(try #require(reopened.abf).contents(named: try #require(model.storage(table: table.name, column: "Qty")).idfFiles[0] + "meta")), file: "m")
        // Một đoạn: bố cục nhiều đoạn chưa được Desktop nhận (gate VM-F14), Desktop đọc được bảng một đoạn.
        #expect(segments.map(\.records) == [10_000_000])
    }

    @Test func repeat1mRLE() async throws {
        let csv = try #require(F2Fixtures.sample("repeat_1m.csv"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f2rle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (state, untitled) = try newDocument(root)
        let loaded = try await load(state, kind: .csv, file: csv)
        #expect(state.loadFromGetData(loaded) == nil)
        let gate = try F2Fixtures.outputDirectory("f14").appendingPathComponent("bipro-f14-rle.pbix")
        try? FileManager.default.removeItem(at: gate)
        let save = try seconds {
            let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: gate, readOnlyRoots: [],
                                                         backupDirectory: root.appendingPathComponent("Backups"))
            #expect(outcome.didWrite)
        }
        let size = (try FileManager.default.attributesOfItem(atPath: gate.path)[.size] as? Int) ?? 0
        let reopened = try Workspace(data: Data(contentsOf: gate))
        let model = try #require(reopened.metadata)
        let batch = try #require(model.storage(table: "repeat_1m", column: "Batch"))
        let segment = try VertiPaq.parseIDF(Data(try #require(reopened.abf).contents(named: batch.idfFiles[0])), file: "b")[0]
        let rle = segment.runs.filter { $0.repeats > 0 && $0.value < 0xF000_0000 }.count
        print("BENCHMARK T058 [repeat_1m]: lưu \(String(format: "%.1f", save)) s, tệp \(size) byte, Batch \(rle) run RLE")
        #expect(rle == 100, "Batch: 100 giá trị × 10 000 dòng liền nhau")
        let engine = try reopened.daxEngine()
        #expect(try await number(engine, "EVALUATE ROW(\"n\", COUNTROWS(repeat_1m), \"b\", DISTINCTCOUNT(repeat_1m[Batch]), \"f\", SUM(repeat_1m[Flag]))")
                    == [.integer(1_000_000), .integer(100), .integer(20)])
        if let desktop = F2Fixtures.desktop("vm-f14", "f14-rle-desktop.pbix") {
            let reference = (try FileManager.default.attributesOfItem(atPath: desktop.path)[.size] as? Int) ?? 1
            #expect(Double(size) <= 1.25 * Double(reference), "SC-006: \(size) so với Desktop \(reference)")
        }
    }
}
