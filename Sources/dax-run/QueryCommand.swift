// Lệnh query của dax-run (lead, sau buổi 1):
//   dax-run query <file.pbix> <out-dir> <a.dax> [b.dax ...] [--timeout GIÂY]
//
// Nạp model một lần, rồi chạy lần lượt từng file truy vấn DAX qua DAXEngine.execute.
// Mỗi file cho <out-dir>/<tên>.engine.tsv: dòng đầu là tên cột (như ResultTable.columns),
// mỗi ô dạng KIỂU:giá-trị để bộ so khớp golden phân biệt BLANK với chuỗi rỗng, currency với số thực:
//   BLANK:  INT:5  DBL:0.1234 (mô tả Swift, đủ để đọc lại chính xác)  CUR:12345 (đã nhân 10^4)
//   STR:văn bản (\t \n \r \\ được escape)  BOOL:true  DT:43465.5 (serial OLE)
// Nhiều EVALUATE trong một file: các bảng kết quả nối tiếp, cách nhau bằng một dòng "#RESULT n".
// Lỗi: <tên>.engine.error.txt chứa kind và message. Quá giới hạn thời gian: huỷ Task và ghi TIMEOUT.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

private final class QueryOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<QueryResult, DAXError>?

    func set(_ result: Result<QueryResult, DAXError>) {
        lock.lock()
        defer { lock.unlock() }
        stored = result
    }

    var result: Result<QueryResult, DAXError>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

func runQueryCommand(arguments: [String]) -> Int32 {
    // arguments[0] là "query".
    var rest = Array(arguments.dropFirst())
    var timeout = 120.0
    if let i = rest.firstIndex(of: "--timeout"), i + 1 < rest.count, let t = Double(rest[i + 1]) {
        timeout = t
        rest.removeSubrange(i...(i + 1))
    }
    guard rest.count >= 3 else {
        FileHandle.standardError.write(Data(
            "dùng: dax-run query <file.pbix> <out-dir> <a.dax> [b.dax ...] [--timeout GIÂY]\n".utf8))
        return 2
    }
    let pbixURL = URL(fileURLWithPath: rest[0])
    let outDir = URL(fileURLWithPath: rest[1], isDirectory: true)
    let files = rest.dropFirst(2).map { URL(fileURLWithPath: $0) }

    do {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let clock = ContinuousClock()
        let started = clock.now
        let pbix = try PBIXFile(url: pbixURL)
        let (abf, _) = try pbix.loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let source = try PBIXColumnSource(abf: abf, metadata: metadata)
        let store = ColumnStore(source: source)
        let engine = DAXEngine(store: store, catalog: Catalog(metadata: metadata))
        try store.prefetchAll()
        print("nạp model: \(seconds(started.duration(to: clock.now))) s, \(files.count) truy vấn, giới hạn \(timeout) s")
        fflush(stdout)

        var failures = 0
        for file in files {
            let stem = file.deletingPathExtension().lastPathComponent
            let text = try String(contentsOf: file, encoding: .utf8)
            let begin = clock.now
            let outcome = QueryOutcome()
            let done = DispatchSemaphore(value: 0)
            let task = Task.detached {
                do {
                    outcome.set(.success(try await engine.execute(text)))
                } catch {
                    outcome.set(.failure(error as? DAXError ?? DAXError(.runtime, "\(error)")))
                }
                done.signal()
            }
            if done.wait(timeout: .now() + timeout) == .timedOut {
                task.cancel()
                _ = done.wait(timeout: .now() + 5)
            }
            let took = seconds(begin.duration(to: clock.now))
            switch outcome.result {
            case .success(let result)?:
                try write(result, to: outDir.appendingPathComponent("\(stem).engine.tsv"))
                let rows = result.tables.map(\.rows.count).reduce(0, +)
                print("OK   \(stem) \(took) s, \(result.tables.count) bảng, \(rows) dòng")
            case .failure(let error)?:
                failures += 1
                let status = error.kind == .cancelled ? "TIMEOUT" : "ERR"
                try "\(status)\t\(error.kind)\t\(error.message)\n".write(
                    to: outDir.appendingPathComponent("\(stem).engine.error.txt"), atomically: true, encoding: .utf8)
                print("\(status)  \(stem) \(took) s: \(error.kind): \(error.message)")
            case nil:
                failures += 1
                try "TIMEOUT\tkhông dừng sau thời gian ân hạn\n".write(
                    to: outDir.appendingPathComponent("\(stem).engine.error.txt"), atomically: true, encoding: .utf8)
                print("TIMEOUT \(stem) \(took) s: không dừng sau thời gian ân hạn")
            }
            fflush(stdout)
        }
        print("tổng: \(files.count) truy vấn, lỗi \(failures), thời gian \(seconds(started.duration(to: clock.now))) s")
        return failures == 0 ? 0 : 1
    } catch {
        FileHandle.standardError.write(Data("lỗi: \(error)\n".utf8))
        return 1
    }
}

private func write(_ result: QueryResult, to url: URL) throws {
    var lines: [String] = []
    for (index, table) in result.tables.enumerated() {
        if result.tables.count > 1 { lines.append("#RESULT \(index + 1)") }
        lines.append(table.columns.map(escapeQueryField).joined(separator: "\t"))
        for row in table.rows {
            lines.append(row.map(renderTyped).joined(separator: "\t"))
        }
    }
    try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
}

private func renderTyped(_ value: Value) -> String {
    switch value {
    case .blank: "BLANK:"
    case .integer(let v): "INT:\(v)"
    case .double(let v): "DBL:\(v)"
    case .currency(let v): "CUR:\(v)"
    case .string(let v): "STR:" + escapeQueryField(v)
    case .boolean(let v): "BOOL:\(v ? "true" : "false")"
    case .dateTime(let v): "DT:\(v)"
    }
}

private func escapeQueryField(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\t", with: "\\t")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
}

private func seconds(_ duration: Duration) -> String {
    let s = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    return String(format: "%.3f", s)
}
