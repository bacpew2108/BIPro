// Phase F, T023 (Spike S5): đo mã hoá + ghi + đọc lại bảng sinh 100 000 và 1 000 000 dòng × 10 cột. Chỉ chạy khi BIPRO_HEAVY=1, nên dùng bản release:
// `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter WriterPerformanceTests`.
// Mục tiêu (spec): SC-004 1 triệu dòng < 15 s, 100 000 dòng < 4 s; SC-005 bộ nhớ đỉnh < 2 GB. Số đo ghi ra màn hình (chép vào measurements.md).
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BIPRO_HEAVY"] != nil && FileManager.default.fileExists(atPath: DesktopGolden.path.path)), .serialized)
struct WriterPerformanceTests {
    private func table(rows: Int) -> NewTable {
        var ints: [[Int64?]] = [[], []], doubles: [[Double?]] = [[], []], dates: [Double?] = []
        var low: [[String?]] = [[], [], []], high: [[String?]] = [[]]
        ints[0].reserveCapacity(rows); ints[1].reserveCapacity(rows); doubles[0].reserveCapacity(rows); doubles[1].reserveCapacity(rows)
        let cities = ["Hà Nội", "Đà Nẵng", "Hồ Chí Minh", "Cần Thơ", "Huế", "Hải Phòng", "Nha Trang", "Vũng Tàu"]
        for i in 0..<rows {
            ints[0].append(Int64(i))                                  // khoá duy nhất
            ints[1].append(i % 97 == 0 ? nil : Int64(i % 5000))
            doubles[0].append(Double(i % 100_000) / 8)
            doubles[1].append(i % 41 == 0 ? nil : Double(i % 13) * 1.25)
            dates.append(45_000 + Double(i % 1500))
            low[0].append(cities[i % cities.count])
            low[1].append(i % 11 == 0 ? nil : "loại \(i % 23)")
            low[2].append(["A", "B", "C"][i % 3])
            high[0].append("mã \(i % 200_000)")
        }
        var columns: [NewTableColumn] = []
        columns.append(NewTableColumn(name: "Id", values: .int64(ints[0])))
        columns.append(NewTableColumn(name: "Nhom", values: .int64(ints[1])))
        columns.append(NewTableColumn(name: "Tien", values: .double(doubles[0])))
        columns.append(NewTableColumn(name: "He so", values: .double(doubles[1])))
        columns.append(NewTableColumn(name: "Ngay", values: .dateTime(dates)))
        columns.append(NewTableColumn(name: "Thanh pho", values: .string(low[0])))
        columns.append(NewTableColumn(name: "Loai", values: .string(low[1])))
        columns.append(NewTableColumn(name: "Hang", values: .string(low[2])))
        columns.append(NewTableColumn(name: "Ma", values: .string(high[0])))
        columns.append(NewTableColumn(name: "Id2", values: .int64(ints[0])))
        return NewTable(name: "Lon", columns: columns)
    }

    private func peakMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576   // macOS: byte
    }

    private func measure(rows: Int) throws {
        let source = table(rows: rows)
        var changes = PBIXChanges()
        changes.modelEdits.append(.addTable(source))
        let start = Date()
        let data = try PBIXWriter.build(source: DesktopGolden.path, changes: changes).data
        let write = Date().timeIntervalSince(start)
        let readStart = Date()
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let columns = try VertiPaq.decodeTable("Lon", metadata: metadata, abf: abf)
        let read = Date().timeIntervalSince(readStart)
        #expect(columns.allSatisfy { $0.count == rows })
        print("S5 \(rows) dòng × 10 cột: mã hoá + ghi + xác minh \(String(format: "%.2f", write)) s, đọc lại \(String(format: "%.2f", read)) s, file \(data.count / 1_048_576) MB, bộ nhớ đỉnh \(String(format: "%.0f", peakMegabytes())) MB")
    }

    @Test func motTramNganDong() throws { try measure(rows: 100_000) }
    @Test func motTrieuDong() throws { try measure(rows: 1_000_000) }
}
