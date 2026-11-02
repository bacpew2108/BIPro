// Lệnh measures-run của dax-run (đợt tối ưu engine):
//   dax-run measures-run <file.pbix> <measures.tsv> <out.tsv> [--per-measure-timeout GIÂY] [--limit N]
//
// Đánh giá từng measure của model (không bộ lọc, không row context) và ghi mỗi kết quả ngay sau khi xong:
// - out.tsv được ghi và đồng bộ từng dòng (FileHandle không đệm), nên đọc được tiến trình giữa chừng.
// - stdout in một dòng tiến trình và fflush sau mỗi measure.
// - Mỗi measure có giới hạn thời gian. Quá giới hạn thì huỷ Task (Evaluator kiểm Task.isCancelled), ghi TIMEOUT rồi tiếp tục.
//   Nếu Task không dừng sau thời gian ân hạn, ghi TIMEOUT-KHÔNG-HUỶ và vẫn tiếp tục (luồng kẹt còn lại trong tiến trình).
//
// Cột của out.tsv: stt, tầng, bảng, measure, trạng thái (OK|ERR|TIMEOUT), kiểu giá trị, giá trị, giây, thông báo.
// Giá trị viết theo độ chính xác đầy đủ (mô tả Swift của Double), để so khớp bit-level giữa hai lần chạy.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

/// Một dòng của measures.tsv (cột 1 tầng, cột 3 bảng, cột 4 tên).
private struct MeasureSpec: Sendable {
    let index: Int
    let tier: String
    let table: String
    let name: String
}

/// Kết quả của một lần đánh giá, ghi từ Task và đọc từ luồng chính.
private final class MeasureOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Value, DAXError>?

    func set(_ result: Result<Value, DAXError>) {
        lock.lock()
        defer { lock.unlock() }
        stored = result
    }

    var result: Result<Value, DAXError>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private struct MeasuresOptions {
    var pbix: URL
    var tsv: URL
    var out: URL
    var timeout: Double = 60
    var grace: Double = 5
    var limit: Int?
}

func runMeasuresCommand(arguments: [String]) -> Int32 {
    guard let options = parseMeasuresOptions(arguments) else {
        writeMeasuresError("dùng: dax-run measures-run <file.pbix> <measures.tsv> <out.tsv> [--per-measure-timeout GIÂY] [--limit N]\n")
        return 2
    }
    do {
        let specs = try readMeasureSpecs(options.tsv, limit: options.limit)
        let clock = ContinuousClock()

        let pbix = try PBIXFile(url: options.pbix)
        let (abf, _) = try pbix.loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let source = try PBIXColumnSource(abf: abf, metadata: metadata)
        let store = ColumnStore(source: source)
        let catalog = Catalog(metadata: metadata)
        let engine = DAXEngine(store: store, catalog: catalog)

        // Nạp mọi cột trước để thời gian từng measure không gồm phí nạp cột.
        let load = try clock.measure { try store.prefetchAll() }
        print("nạp \(source.schema.tables.count) bảng, \(specs.count) measure, prefetch cột: \(fmtMeasureSeconds(load)) s")
        print("giới hạn mỗi measure: \(options.timeout) s, ân hạn huỷ: \(options.grace) s")
        fflush(stdout)

        try writeMeasureLine(options.out, header: true, fields: [
            "stt", "tầng", "bảng", "measure", "trạng thái", "kiểu", "giá trị", "giây", "thông báo",
        ])

        var okCount = 0, errCount = 0, timeoutCount = 0, leakedCount = 0
        var total = 0.0
        var slowest: (name: String, seconds: Double) = ("", 0)
        for spec in specs {
            let started = clock.now
            let outcome = MeasureOutcome()
            let done = DispatchSemaphore(value: 0)
            let task = Task.detached {
                do {
                    let value = try await engine.evaluate(measure: spec.name, table: spec.table, filters: [])
                    outcome.set(.success(value))
                } catch {
                    outcome.set(.failure(error as? DAXError ?? DAXError(.runtime, "\(error)")))
                }
                done.signal()
            }

            var leaked = false
            if done.wait(timeout: .now() + options.timeout) == .timedOut {
                task.cancel()
                if done.wait(timeout: .now() + options.grace) == .timedOut {
                    leaked = true
                }
            }
            let elapsed = started.duration(to: clock.now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            total += seconds

            var status = "ERR", kind = "", text = "", message = ""
            switch outcome.result {
            case .success(let value)?:
                status = "OK"
                (kind, text) = renderMeasureValue(value)
                okCount += 1
            case .failure(let error)?:
                if error.kind == .cancelled {
                    status = "TIMEOUT"
                    timeoutCount += 1
                } else {
                    errCount += 1
                }
                message = "\(error.kind): \(error.message)"
            case nil:
                status = leaked ? "TIMEOUT-KHÔNG-HUỶ" : "ERR"
                if leaked {
                    timeoutCount += 1
                    leakedCount += 1
                    message = "Task không dừng sau \(options.grace) s ân hạn"
                } else {
                    errCount += 1
                    message = "không có kết quả"
                }
            }
            if seconds > slowest.seconds {
                slowest = ("\(spec.table)[\(spec.name)]", seconds)
            }

            try writeMeasureLine(options.out, header: false, fields: [
                "\(spec.index)", spec.tier, spec.table, spec.name, status, kind, text,
                String(format: "%.3f", seconds), message,
            ])
            print("[\(spec.index)/\(specs.count)] \(status) \(spec.table)[\(spec.name)] \(String(format: "%.3f", seconds)) s \(kind) \(text.prefix(80)) \(message.prefix(120))")
            fflush(stdout)
        }

        print("")
        print("tổng: \(specs.count) measure, OK \(okCount), ERR \(errCount), TIMEOUT \(timeoutCount) (kẹt không huỷ được \(leakedCount))")
        print("tổng thời gian đánh giá: \(String(format: "%.3f", total)) s; chậm nhất: \(slowest.name) \(String(format: "%.3f", slowest.seconds)) s")
        fflush(stdout)
        return 0
    } catch {
        writeMeasuresError("lỗi: \(error)\n")
        return 1
    }
}

// MARK: - Tham số và đầu vào

private func parseMeasuresOptions(_ arguments: [String]) -> MeasuresOptions? {
    var positional: [String] = []
    var timeout: Double = 60
    var grace: Double = 5
    var limit: Int?
    var i = 1
    while i < arguments.count {
        let arg = arguments[i]
        switch arg {
        case "--per-measure-timeout":
            i += 1
            guard i < arguments.count, let value = Double(arguments[i]), value > 0 else { return nil }
            timeout = value
        case "--grace":
            i += 1
            guard i < arguments.count, let value = Double(arguments[i]), value >= 0 else { return nil }
            grace = value
        case "--limit":
            i += 1
            guard i < arguments.count, let value = Int(arguments[i]), value > 0 else { return nil }
            limit = value
        default:
            positional.append(arg)
        }
        i += 1
    }
    guard positional.count == 3 else { return nil }
    return MeasuresOptions(pbix: URL(fileURLWithPath: positional[0]),
                           tsv: URL(fileURLWithPath: positional[1]),
                           out: URL(fileURLWithPath: positional[2]),
                           timeout: timeout, grace: grace, limit: limit)
}

private func readMeasureSpecs(_ url: URL, limit: Int?) throws -> [MeasureSpec] {
    let text = try String(contentsOf: url, encoding: .utf8)
    var specs: [MeasureSpec] = []
    for line in text.components(separatedBy: "\n").dropFirst() where !line.isEmpty {
        let cols = line.components(separatedBy: "\t")
        guard cols.count >= 4 else { continue }
        specs.append(MeasureSpec(index: specs.count + 1, tier: cols[0], table: cols[2], name: cols[3]))
        if let limit, specs.count >= limit { break }
    }
    return specs
}

// MARK: - Đầu ra

/// Kiểu và chuỗi của một giá trị, đủ chính xác để so sánh giữa hai lần chạy.
private func renderMeasureValue(_ value: Value) -> (String, String) {
    switch value {
    case .blank: ("BLANK", "")
    case .integer(let v): ("INT", "\(v)")
    case .double(let v): ("DBL", "\(v)")
    case .currency(let v): ("CUR", "\(v)")
    case .string(let v): ("STR", escapeMeasureField(v))
    case .boolean(let v): ("BOOL", v ? "true" : "false")
    case .dateTime(let v): ("DT", "\(v)")
    }
}

private func escapeMeasureField(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\t", with: "\\t")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
}

/// Ghi một dòng TSV và đẩy xuống đĩa ngay (FileHandle không đệm), để theo dõi tiến trình từ file.
private func writeMeasureLine(_ url: URL, header: Bool, fields: [String]) throws {
    let line = fields.joined(separator: "\t") + "\n"
    if header {
        try line.write(to: url, atomically: false, encoding: .utf8)
        return
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(line.utf8))
}

private func fmtMeasureSeconds(_ duration: Duration) -> String {
    let parts = duration.components
    let value = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    return String(format: "%.3f", value)
}

private func writeMeasuresError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
