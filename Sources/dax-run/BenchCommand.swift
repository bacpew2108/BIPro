// Lệnh bench của dax-run (CS, đợt 1a): `dax-run bench <file.pbix> [--verify]`.
//
// Đo thời gian mở file, dựng lược đồ, rồi nạp mọi cột: tuần tự, và song song bằng `prefetchAll`.
// Mỗi phép đo dùng kho mới để không tận dụng cache của phép trước.
// `--verify` đối chiếu số distinct của từng cột với engine statistics trong metadata,
// cùng quy tắc với `pbix-dump verify`.
//
// File này không tự đăng ký lệnh. `main.swift` (LEAD) cần một nhánh: `case "bench": exit(runBenchCommand(arguments: arguments))`.

import ColumnStore
import Foundation

func runBenchCommand(arguments: [String]) -> Int32 {
    guard arguments.count >= 2 else {
        writeError("dùng: dax-run bench <file.pbix> [--verify]\n")
        return 2
    }
    let url = URL(fileURLWithPath: arguments[1])
    let verify = arguments.dropFirst(2).contains("--verify")
    let clock = ContinuousClock()

    do {
        var source: PBIXColumnSource?
        let open = try clock.measure {
            source = try PBIXColumnSource(url: url)
        }
        guard let source else { return 1 }
        let schema = source.schema
        let columns = schema.tables.flatMap { $0.columns.map(\.id) }
        print("file:      \(url.lastPathComponent)")
        print("bảng:      \(schema.tables.count), cột: \(columns.count)")
        print("mở file, đọc DataModel và metadata: \(seconds(open)) s")

        let serialStore = ColumnStore(source: source)
        let serial = try clock.measure {
            for id in columns { _ = try serialStore.column(id) }
        }
        print("nạp tuần tự \(columns.count) cột: \(seconds(serial)) s")

        let parallelStore = ColumnStore(source: source)
        let parallel = try clock.measure {
            try parallelStore.prefetchAll()
        }
        print("nạp song song \(columns.count) cột (prefetchAll): \(seconds(parallel)) s")

        try printPayloadSummary(store: parallelStore, schema: schema)
        if verify {
            let mismatches = try verifyDistinctCounts(store: parallelStore, source: source)
            if mismatches > 0 { return 2 }
        }
        return 0
    } catch {
        writeError("lỗi: \(error)\n")
        return 1
    }
}

/// Tóm tắt dạng lưu trữ: số cột mã hoá, dense, rỗng, và danh sách cột dense.
private func printPayloadSummary(store: ColumnStore, schema: ModelSchema) throws {
    var encoded = 0, dense = 0, blank = 0
    var denseNames: [String] = []
    var bytes = 0
    for table in schema.tables {
        for column in table.columns {
            let data = try store.column(column.id)
            switch data.payload {
            case .encoded(let codes, let dictionary):
                encoded += 1
                bytes += codes.count * codeWidth(codes)
                if case .strings(let pool) = dictionary {
                    bytes += pool.footprint
                } else {
                    bytes += dictionary.count * 8
                }
            case .dense:
                dense += 1
                denseNames.append("\(table.name)[\(column.name)]")
                bytes += data.rowCount * 8
            case .allBlank:
                blank += 1
            }
        }
    }
    print("dạng cột: mã hoá \(encoded), dense \(dense), rỗng \(blank); bộ nhớ ước lượng \(bytes / 1_048_576) MB")
    if !denseNames.isEmpty {
        print("cột dense: \(denseNames.joined(separator: ", "))")
    }
}

private func codeWidth(_ codes: Codes) -> Int {
    switch codes {
    case .u8: 1
    case .u16: 2
    case .u32: 4
    }
}

/// Giống `pbix-dump verify`: số distinct (có hoặc không kể BLANK) phải khớp `DistinctStates` của engine.
/// Trả về số cột lệch.
private func verifyDistinctCounts(store: ColumnStore, source: PBIXColumnSource) throws -> Int {
    var checked = 0, mismatched = 0
    for table in store.schema.tables {
        for column in table.columns where source.hasStorage(column.id) {
            let data = try store.column(column.id)
            var distinct = Set<StoredValue>()
            for row in 0..<data.rowCount { distinct.insert(data.value(at: row)) }
            let nonBlank = distinct.subtracting([.blank]).count
            let expected = source.cardinality(of: column.id) ?? -1
            checked += 1
            if nonBlank != expected && distinct.count != expected {
                mismatched += 1
                print("LỆCH \(table.name)[\(column.name)]: \(nonBlank) distinct (+blank: \(distinct.count)), engine ghi \(expected)")
            }
        }
    }
    print("verified \(checked) columns, \(mismatched) mismatches")
    return mismatched
}

private func seconds(_ duration: Duration) -> String {
    let parts = duration.components
    let value = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    return String(format: "%.3f", value)
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
