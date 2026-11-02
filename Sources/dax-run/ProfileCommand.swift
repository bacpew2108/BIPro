// Lệnh profile của dax-run (Phase C, đợt 0, lead):
//   dax-run profile <file.pbix> [--page <id|tên>] [--filter "<biểu thức bảng DAX>"]... [--parallel N] [--timeout GIÂY] [--print]
//
// Đo thời gian truy vấn lõi của từng visual có dữ liệu trên mỗi trang, để biết trước rủi ro hiệu năng của Phase C.
// Truy vấn ở đây là bản XẤP XỈ, chưa phải khuôn Performance Analyzer (việc đó là DAXQueryBuilder, gói Q):
//   EVALUATE SUMMARIZECOLUMNS(<cột nhóm>, <--filter…>, "m1", <measure 1>, …)
// - cột nhóm: Category/Rows/Columns/Series/Group/Values của slicer; cấp hierarchy lấy CẤP ĐẦU của hierarchy (mức mặc định);
// - measure: mọi measure/aggregation trong query + mọi measure nằm trong `objects` (màu, icon, gradient lấy từ measure);
// - slicer: chỉ cột (giá trị phân biệt).
// In từng visual (thời gian, số dòng), tổng tuần tự và thời gian thực khi chạy N truy vấn song song.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

private struct ProfiledQuery {
    let page: String
    let visual: ReportVisual
    let text: String
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    func set(_ value: T) { lock.lock(); stored = value; lock.unlock() }
    var value: T? { lock.lock(); defer { lock.unlock() }; return stored }
}

func runProfileCommand(arguments: [String]) -> Int32 {
    var rest = Array(arguments.dropFirst())
    func option(_ name: String) -> [String] {
        var values: [String] = []
        while let i = rest.firstIndex(of: name), i + 1 < rest.count {
            values.append(rest[i + 1])
            rest.removeSubrange(i...(i + 1))
        }
        return values
    }
    let pageFilter = option("--page").first
    let filters = option("--filter")
    let parallel = option("--parallel").first.flatMap(Int.init) ?? ProcessInfo.processInfo.activeProcessorCount
    let timeout = option("--timeout").first.flatMap(Double.init) ?? 60
    let printText = rest.contains("--print")
    rest.removeAll { $0 == "--print" }
    guard let path = rest.first else {
        FileHandle.standardError.write(Data(
            "dùng: dax-run profile <file.pbix> [--page id|tên] [--filter \"DAX\"]... [--parallel N] [--timeout GIÂY] [--print]\n".utf8))
        return 2
    }

    do {
        let clock = ContinuousClock()
        let started = clock.now
        let pbix = try PBIXFile(url: URL(fileURLWithPath: path))
        let (abf, _) = try pbix.loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: metadata))
        let engine = DAXEngine(store: store, catalog: Catalog(metadata: metadata))
        try store.prefetchAll()
        let report = try pbix.loadReport()
        print("nạp model: \(profileSeconds(started.duration(to: clock.now))) s, song song \(parallel), bộ lọc: \(filters.count)")

        var failures = 0
        for page in report.pages {
            if let pageFilter, page.id != pageFilter, page.displayName != pageFilter { continue }
            let queries = page.visuals.compactMap { visual -> ProfiledQuery? in
                guard visual.isDataBound, let text = coreQuery(visual, metadata: metadata, filters: filters) else { return nil }
                return ProfiledQuery(page: page.displayName, visual: visual, text: text)
            }
            guard !queries.isEmpty else { continue }
            print("\n== \(page.displayName) (\(queries.count) visual có dữ liệu)")

            // 1. Tuần tự: thời gian riêng của từng visual.
            var sequential = 0.0
            var timings: [(Double, String)] = []
            for q in queries {
                let begin = clock.now
                let outcome = run(engine, q.text, timeout: timeout)
                let took = profileDouble(begin.duration(to: clock.now))
                sequential += took
                let label = "\(q.visual.type) \(q.visual.id.prefix(8)) \(q.visual.fields.first(where: { $0.kind != .column })?.label ?? "")"
                switch outcome {
                case .success(let r):
                    timings.append((took, label))
                    print(String(format: "  %7.3f s  %4d dòng  %@", took, r.tables.first?.rows.count ?? 0, label))
                case .failure(let e):
                    failures += 1
                    print(String(format: "  %7.3f s  LỖI  %@: %@ %@", took, label, "\(e.kind)", e.message))
                }
                if printText { print(q.text.split(separator: "\n").map { "      " + $0 }.joined(separator: "\n")) }
            }

            // 2. Song song N truy vấn: thời gian thực của cả trang (cache kết quả của engine bị loại bằng cách tạo engine mới).
            let fresh = DAXEngine(store: store, catalog: Catalog(metadata: metadata))
            let begin = clock.now
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await withTaskGroup(of: Void.self) { group in
                    var next = 0
                    for _ in 0..<min(parallel, queries.count) {
                        let q = queries[next]; next += 1
                        group.addTask { _ = try? await fresh.execute(q.text) }
                    }
                    while await group.next() != nil, next < queries.count {
                        let q = queries[next]; next += 1
                        group.addTask { _ = try? await fresh.execute(q.text) }
                    }
                }
                done.signal()
            }
            done.wait()
            let wall = profileDouble(begin.duration(to: clock.now))
            let slowest = timings.sorted { $0.0 > $1.0 }.prefix(3).map { String(format: "%.2f s %@", $0.0, $0.1) }
            print(String(format: "  tổng tuần tự %.2f s; song song %d: %.2f s", sequential, parallel, wall))
            print("  chậm nhất: " + slowest.joined(separator: " | "))
        }
        return failures == 0 ? 0 : 1
    } catch {
        FileHandle.standardError.write(Data("lỗi: \(error)\n".utf8))
        return 1
    }
}

private func run(_ engine: DAXEngine, _ text: String, timeout: Double) -> Result<QueryResult, DAXError> {
    let box = Box<Result<QueryResult, DAXError>>()
    let done = DispatchSemaphore(value: 0)
    let task = Task.detached {
        do { box.set(.success(try await engine.execute(text))) } catch {
            box.set(.failure(error as? DAXError ?? DAXError(.runtime, "\(error)")))
        }
        done.signal()
    }
    if done.wait(timeout: .now() + timeout) == .timedOut {
        task.cancel()
        _ = done.wait(timeout: .now() + 5)
    }
    return box.value ?? .failure(DAXError(.cancelled, "quá \(timeout) s"))
}

private func quoted(_ table: String, _ column: String) -> String {
    "'\(table.replacingOccurrences(of: "'", with: "''"))'[\(column.replacingOccurrences(of: "]", with: "]]"))]"
}

/// Truy vấn lõi xấp xỉ của một visual; nil nếu không có gì để đo.
private func coreQuery(_ visual: ReportVisual, metadata: ModelMetadata, filters: [String]) -> String? {
    let groupRoles: Set<String> = ["Category", "Rows", "Columns", "Series", "Group", "Legend", "Details"]
    let isSlicer = visual.type.lowercased().contains("slicer")
    var groups: [String] = []
    var seenHierarchies: Set<String> = []
    var measures: [String] = []

    for field in visual.fields {
        let isGroup = groupRoles.contains(field.role) || (isSlicer && field.role == "Values")
        switch field.kind {
        case .column where isGroup:
            groups.append(quoted(field.entity, field.property))
        case .hierarchyLevel where isGroup:
            // Cấp đầu của hierarchy chứa cấp này (mức mặc định khi chưa drill).
            guard let h = metadata.hierarchies.first(where: { $0.tableName == field.entity && $0.levels.contains { $0.name == field.property } }),
                  !seenHierarchies.contains(h.name), let first = h.levels.first else { continue }
            seenHierarchies.insert(h.name)
            groups.append(quoted(field.entity, first.columnName))
        case .measure:
            measures.append(quoted(field.entity, field.property))
        case .aggregation:
            let fn = (field.function ?? "Sum").uppercased()
            let name = ["SUM", "MIN", "MAX", "AVERAGE", "COUNT", "DISTINCTCOUNT"].contains(fn) ? fn : "SUM"
            measures.append("\(name)(\(quoted(field.entity, field.property)))")
        default:
            break
        }
    }
    // Measure trong objects (màu, icon, gradient lấy từ measure).
    func walk(_ json: JSONValue) {
        if let m = json["Measure"], let table = m["Expression"]?["SourceRef"]?["Entity"]?.string, let name = m["Property"]?.string {
            measures.append(quoted(table, name))
        }
        for child in json.object.values { walk(child) }
        for child in json.array { walk(child) }
    }
    walk(visual.objects.json)
    if isSlicer { measures = [] }

    var seen: Set<String> = []
    measures = measures.filter { seen.insert($0).inserted }
    guard !groups.isEmpty || !measures.isEmpty else { return nil }
    var args = groups + filters
    for (i, m) in measures.enumerated() { args.append("\"m\(i + 1)\", \(m)") }
    return "EVALUATE\nSUMMARIZECOLUMNS(\n    " + args.joined(separator: ",\n    ") + "\n)"
}

private func profileDouble(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

private func profileSeconds(_ d: Duration) -> String { String(format: "%.3f", profileDouble(d)) }
