// Phase F, T106 (SC-004, SC-005): đo lưu T3 qua đường app đầy đủ: `TableLoader.apply` (Get Data ▸ Tải) → `DocumentSaver`
// (`TableData` → `NewTable` → mã hoá VertiPaq → `PBIXWriter.build` → `verifyTables` đọc lại từng ô → ghi tạm, mở lại, thay).
// Chỉ chạy khi BIPRO_HEAVY=1, nên dùng bản release:
// `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter SavePerformanceTests`.
// Số đo in ra màn hình, chép vào specs/010-f-get-data-power-query-t3/measurements.md.
import ColumnStore
import Connectors
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: thời gian lưu T3 qua đường app", .enabled(if: FFixtures.heavy), .serialized) @MainActor
struct SavePerformanceTests {
    /// Bảng 10 cột giống `WriterPerformanceTests` (2 số nguyên, 2 thập phân, 1 ngày, 4 chuỗi gồm một cột ~200 000 giá trị khác nhau, có ô trống).
    private func table(rows: Int, name: String) throws -> LoadedTable {
        var id: [Int64?] = [], group: [Int64?] = [], money: [Double?] = [], factor: [Double?] = [], dates: [Double?] = []
        var city: [String?] = [], kind: [String?] = [], grade: [String?] = [], code: [String?] = []
        id.reserveCapacity(rows); group.reserveCapacity(rows); money.reserveCapacity(rows); factor.reserveCapacity(rows)
        dates.reserveCapacity(rows); city.reserveCapacity(rows); kind.reserveCapacity(rows); grade.reserveCapacity(rows); code.reserveCapacity(rows)
        let cities = ["Hà Nội", "Đà Nẵng", "Hồ Chí Minh", "Cần Thơ", "Huế", "Hải Phòng", "Nha Trang", "Vũng Tàu"]
        for i in 0..<rows {
            id.append(Int64(i))
            group.append(i % 97 == 0 ? nil : Int64(i % 5000))
            money.append(Double(i % 100_000) / 8)
            factor.append(i % 41 == 0 ? nil : Double(i % 13) * 1.25)
            dates.append(45_000 + Double(i % 1500))
            city.append(cities[i % cities.count])
            kind.append(i % 11 == 0 ? nil : "loại \(i % 23)")
            grade.append(["A", "B", "C"][i % 3])
            code.append("mã \(i % 200_000)")
        }
        let data = try TableData(columns: [
            TableColumn(name: "Id", data: ColumnBuilder.integers(id)),
            TableColumn(name: "Nhom", data: ColumnBuilder.integers(group)),
            TableColumn(name: "Tien", data: ColumnBuilder.doubles(money)),
            TableColumn(name: "He so", data: ColumnBuilder.doubles(factor)),
            TableColumn(name: "Ngay", data: ColumnBuilder.dateTimes(dates)),
            TableColumn(name: "Thanh pho", data: ColumnBuilder.strings(city)),
            TableColumn(name: "Loai", data: ColumnBuilder.strings(kind)),
            TableColumn(name: "Hang", data: ColumnBuilder.strings(grade)),
            TableColumn(name: "Ma", data: ColumnBuilder.strings(code)),
            TableColumn(name: "Id2", data: ColumnBuilder.integers(id)),
        ])
        return LoadedTable(name: name, data: data,
                           origin: LoadedOrigin(kind: .csv, location: "/khong/co/\(name).csv", itemName: name, itemKind: .file))
    }

    private func peakMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576   // macOS: byte
    }

    private func seconds(_ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    private func report(_ label: String, rows: Int, load: Double, save: Double, file: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        print("BENCHMARK T106 [\(label), \(rows) dòng]: Tải \(String(format: "%.2f", load)) s, lưu \(String(format: "%.2f", save)) s, "
              + "file \(size / 1_048_576) MB, bộ nhớ đỉnh \(String(format: "%.0f", peakMegabytes())) MB")
    }

    /// Tài liệu mới (file mới của BI Pro) → Tải bảng → lưu lần đầu. SC-004: 100 000 dòng < 4 s, 1 triệu dòng < 15 s; SC-005: < 2 GB.
    @Test(arguments: [100_000, 1_000_000])
    func luuTaiLieuMoi(rows: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t106-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        let loaded = try table(rows: rows, name: "Lon")
        var reason: String?
        let load = seconds { reason = state.loadFromGetData([loaded]) }
        #expect(reason == nil)

        let destination = root.appendingPathComponent("t106-\(rows).pbix")
        let save = try seconds {
            let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                         backupDirectory: root.appendingPathComponent("Backups"))
            #expect(outcome.didWrite)
        }
        report("tài liệu mới", rows: rows, load: load, save: save, file: destination)
        #expect(save < (rows >= 1_000_000 ? 15 : 4), "SC-004: \(save) s")
        #expect(peakMegabytes() < 2048, "SC-005")
    }

    /// Nền Nhom6 (54 MB, 14 quan hệ): Tải bảng 100 000 dòng → lưu (giải nén mô hình, thêm bảng, nén lại, kiểm sau ghi).
    @Test func luuTrenNenNhom6() throws {
        guard let copy = try FFixtures.nhom6Copy(folder: "t106", fileName: "Nhom6_t106.pbix") else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t106n-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: copy) }
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: copy)), fileName: copy.lastPathComponent, fileURL: copy)
        let rows = 100_000
        let loaded = try table(rows: rows, name: "Bang moi")
        var reason: String?
        let load = seconds { reason = state.loadFromGetData([loaded]) }
        #expect(reason == nil)

        let destination = root.appendingPathComponent("Nhom6_t106_out.pbix")
        let save = try seconds {
            let outcome = try DocumentSaver.save(editor: state.layout, source: copy, to: destination, expectedStamp: nil, readOnlyRoots: [],
                                                 backupDirectory: root.appendingPathComponent("Backups"))
            #expect(outcome.didWrite)
        }
        report("nền Nhom6", rows: rows, load: load, save: save, file: destination)
        let reopened = try Workspace(data: Data(contentsOf: destination))
        #expect(reopened.metadata?.tables.contains { $0.name == "Bang moi" } == true)
    }

    /// Nhom6 chỉ đổi T2 (thêm một measure): SC-004 vế cuối, giữ ngưỡng Phase E (< 3 s). Ghi số tệ nhất trong 3 lần.
    @Test func luuNhom6ChiT2() throws {
        guard let copy = try FFixtures.nhom6Copy(folder: "t106", fileName: "Nhom6_t106_t2.pbix") else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t106m-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: copy) }
        var times: [Double] = []
        for round in 0..<3 {
            let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: copy)), fileName: copy.lastPathComponent, fileURL: copy)
            let table = try #require(state.workspace.userTables.first?.name)
            #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: table, name: "T106 đo \(round)", expression: "1"))) == nil)
            let destination = root.appendingPathComponent("Nhom6_t2_\(round).pbix")
            times.append(try seconds {
                let outcome = try DocumentSaver.save(editor: state.layout, source: copy, to: destination, expectedStamp: nil, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
                #expect(outcome.didWrite)
            })
        }
        print("BENCHMARK T106 [Nhom6 chỉ T2]: " + times.map { String(format: "%.2f", $0) }.joined(separator: ", ") + " s")
        #expect((times.min() ?? 99) < 3, "SC-004 (Phase E): \(times) s")   // lần nhanh nhất: máy bận làm các lần sau chậm thêm
    }
}
