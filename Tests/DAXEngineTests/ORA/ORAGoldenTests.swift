// ORA-1: golden runner. So kết quả engine với golden copy từ Power BI Desktop (buổi 1), theo quy tắc
// docs/PHASE_B_PLAN.md §5.3 và định dạng Copy đã quan sát ở O2 (docs/phase-b-evidence/BUOI1.md).
//
// - ORAGoldenNhom6Tests: chạy G0, G1, G3 trên Nhom6 thật. Chỉ chạy khi BIPRO_HEAVY=1 và có
//   ~/Downloads/Nhom6_Dashboard.pbix. Lệnh: BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing
//   --scratch-path .build-rel --filter ORAGolden
// - ORAGoldenComparatorTests: kiểm chính bộ so khớp, chạy trong lượt test thường.
//
// Bản Python tương đương để chạy tay: scripts/oracle/compare-golden.py (cùng quy tắc).
import ColumnStore
import Foundation
import PBIXKit
import Testing
import DAXTestSupport
@testable import DAXEngine

// MARK: - Bộ so khớp

/// Golden copy từ DAX Query View: dòng tiêu đề rồi các dòng giá trị, ô là văn bản.
struct GoldenTable {
    let columns: [String]
    let rows: [[String]]

    init(text: String) {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        body = body.replacingOccurrences(of: "\r\n", with: "\n")
        while body.hasSuffix("\n") { body.removeLast() }
        let lines = body.components(separatedBy: "\n")
        columns = lines.first?.components(separatedBy: "\t") ?? []
        rows = lines.dropFirst().map { $0.components(separatedBy: "\t") }
    }
}

enum GoldenComparator {
    static let probeSuffix = " · ISBLANK"

    /// Một ô lệch: cột, dòng (từ 1), mô tả.
    struct Mismatch: CustomStringConvertible {
        let column: String
        let row: Int
        let problem: String
        var description: String { "\(column) dòng \(row): \(problem)" }
    }

    /// So bảng kết quả engine với golden. Cột so theo tên; dòng theo thứ tự (golden có ORDER BY hoặc một dòng).
    static func compare(golden: GoldenTable, engine: ResultTable) -> [Mismatch] {
        var out: [Mismatch] = []
        let engineIndex = Dictionary(engine.columns.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let missing = golden.columns.filter { engineIndex[$0] == nil }
        if !missing.isEmpty {
            out.append(Mismatch(column: "(cột)", row: 0, problem: "engine thiếu cột \(missing)"))
        }
        if golden.rows.count != engine.rows.count {
            out.append(Mismatch(column: "(dòng)", row: 0,
                                problem: "số dòng golden \(golden.rows.count), engine \(engine.rows.count)"))
        }
        for (r, goldenRow) in golden.rows.prefix(engine.rows.count).enumerated() {
            let engineRow = engine.rows[r]
            for (c, column) in golden.columns.enumerated() {
                guard let e = engineIndex[column], c < goldenRow.count else { continue }
                var isBlank: Bool?
                if !column.hasSuffix(probeSuffix + "]"), column.hasSuffix("]") {
                    let probe = String(column.dropLast()) + probeSuffix + "]"
                    if let p = golden.columns.firstIndex(of: probe), p < goldenRow.count {
                        isBlank = goldenRow[p].lowercased() == "true" ? true
                            : goldenRow[p].lowercased() == "false" ? false : nil
                    }
                }
                if let problem = compareCell(golden: goldenRow[c], engine: engineRow[e], goldenIsBlank: isBlank) {
                    out.append(Mismatch(column: column, row: r + 1, problem: problem))
                }
            }
        }
        return out
    }

    /// nil nếu khớp. `goldenIsBlank` lấy từ cột thăm dò ISBLANK (nil khi không có cột thăm dò).
    static func compareCell(golden: String, engine: Value, goldenIsBlank: Bool?) -> String? {
        if case .blank = engine {
            if !golden.isEmpty { return "engine BLANK, golden \(golden)" }
            if goldenIsBlank == false { return "engine BLANK, golden là chuỗi rỗng (ISBLANK = false)" }
            return nil
        }
        if golden.isEmpty, goldenIsBlank == true { return "golden BLANK, engine \(engine)" }
        switch engine {
        case .blank:
            return nil
        case .string(let s):
            return golden == s.replacingOccurrences(of: "\r\n", with: "\n") ? nil : "chuỗi khác: golden \(golden), engine \(s)"
        case .boolean(let b):
            return golden.lowercased() == (b ? "true" : "false") ? nil : "golden \(golden), engine \(b)"
        case .integer(let v):
            guard let g = number(golden) else { return "không đọc được số \(golden)" }
            return g == Double(v) ? nil : "golden \(golden), engine \(v)"
        case .double(let v):
            guard let g = number(golden) else { return "không đọc được số \(golden)" }
            return sameDouble(g, v) ? nil : "golden \(golden), engine \(v)"
        case .currency(let raw):
            guard let g = number(golden) else { return "không đọc được số \(golden)" }
            return Int64((g * 10_000).rounded()) == raw ? nil : "golden \(golden), engine \(Double(raw) / 10_000)"
        case .dateTime(let serial):
            guard let g = oleSerial(golden) else { return "không đọc được ngày \(golden)" }
            return abs(g - serial) * 86_400_000 <= 3.34 ? nil : "golden \(golden), engine \(serial)"
        }
    }

    static func number(_ text: String) -> Double? {
        switch text {
        case "Infinity": return .infinity
        case "-Infinity": return -.infinity
        case "NaN": return .nan
        default: return Double(text)
        }
    }

    static func sameDouble(_ a: Double, _ b: Double) -> Bool {
        if a.isNaN || b.isNaN { return a.isNaN && b.isNaN }
        if a.isInfinite || b.isInfinite { return a == b }
        return abs(a - b) <= 1e-9 * max(1, abs(a), abs(b))
    }

    /// "Mon, 31 Dec 2018 16:03:36" (O2) thành serial OLE (ngày 0 là 1899-12-30).
    static func oleSerial(_ text: String) -> Double? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        guard let date = formatter.date(from: text) else { return nil }
        return date.timeIntervalSince1970 / 86_400 + 25_569
    }
}

// MARK: - Đường dẫn và engine dùng chung

enum GoldenPaths {
    /// Gốc repo, tính từ vị trí file test này (Tests/DAXEngineTests/ORA/).
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let golden = repo.appendingPathComponent("Tests/DAXEngineTests/Golden/nhom6")
    static let queries = repo.appendingPathComponent("docs/phase-b-oracle/queries")
    /// Thư mục truy vấn theo thứ tự tìm: buổi sau ghi đè buổi trước (G6f1/G6f2 sửa ở buổi 3).
    static let queryDirs = ["queries-buoi3", "queries-buoi2", "queries"].map {
        repo.appendingPathComponent("docs/phase-b-oracle/\($0)")
    }

    /// File truy vấn theo tên, tìm lần lượt trong `queryDirs`.
    static func query(_ name: String) -> URL {
        let candidates = queryDirs.map { $0.appendingPathComponent("\(name).dax") }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates.last!
    }
}

private let heavyEnabled = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

/// Engine Nhom6, nạp một lần cho mọi ca (biến toàn cục `let` được khởi tạo lười và an toàn luồng).
private let nhom6Engine: Result<DAXEngine, Error> = Result {
    let pbix = try PBIXFile(url: DAXFixtures.nhom6)
    let (abf, _) = try pbix.loadDataModel()
    let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    let store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: metadata))
    try store.prefetchAll()
    return DAXEngine(store: store, catalog: Catalog(metadata: metadata))
}

/// Các golden đã có (buổi 1, 2, 3). Thêm tên vào đây khi có golden mới.
let goldenNhom6Names = [
    "G0-total__FT", "G0-total__LN", "G0-total__CR", "G0-total__DIM",
    "G1-year__FT", "G1-year__LN", "G1-year__CR", "G1-year__DIM",
    "G2-region__FT", "G2-region__LN", "G2-region__CR", "G2-region__DIM",
    "G3-rf-year__FT", "G3-rf-year__LN", "G3-rf-year__CR", "G3-rf-year__DIM",
    "G4-inactive", "G5-month",
    "G6a-issue-pareto", "G6b-channel", "G6c-channel-response", "G6d-trans-type", "G6e-heatmap",
    "T1-blank-arith", "T2-time-edges", "T3-context", "T4-count-empty",
    "G6f1-district", "G6f2-account-branch", "T5-edges",
]

@Suite(.enabled(if: heavyEnabled && DAXFixtures.exists(DAXFixtures.nhom6)))
struct ORAGoldenNhom6Tests {
    @Test(arguments: goldenNhom6Names)
    func goldenKhopPowerBI(_ name: String) async throws {
        let engine = try nhom6Engine.get()
        let query = try String(contentsOf: GoldenPaths.query(name), encoding: .utf8)
        let golden = GoldenTable(text: try String(
            contentsOf: GoldenPaths.golden.appendingPathComponent("\(name).tsv"), encoding: .utf8))
        let result = try await engine.execute(query)
        try #require(result.tables.count == 1, "\(name): cần đúng một bảng kết quả")
        let mismatches = GoldenComparator.compare(golden: golden, engine: result.tables[0])
        #expect(mismatches.isEmpty, "\(name): \(mismatches.count) ô lệch; đầu tiên: \(mismatches.prefix(5).map(\.description))")
    }
}

// MARK: - Huỷ truy vấn nặng (tiêu chí UI1: dừng trong khoảng 100 ms)

@Suite(.enabled(if: heavyEnabled && DAXFixtures.exists(DAXFixtures.nhom6)))
struct ORACancelLatencyTests {
    @Test func huyTruyVanNangDungNhanh() async throws {
        let engine = try nhom6Engine.get()
        let query = try String(contentsOf: GoldenPaths.queries.appendingPathComponent("G1-year__FT.dax"), encoding: .utf8)
        let task = Task { () -> DAXError? in
            do {
                _ = try await engine.execute(query)
                return nil
            } catch let error as DAXError {
                return error
            } catch {
                return DAXError(.runtime, "\(error)")
            }
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        let clock = ContinuousClock()
        let cancelledAt = clock.now
        task.cancel()
        let error = await task.value
        let latency = cancelledAt.duration(to: clock.now)
        #expect(error?.kind == .cancelled, "truy vấn phải dừng với lỗi cancelled, nhận \(String(describing: error))")
        #expect(latency < .milliseconds(100), "thời gian từ lúc huỷ tới lúc dừng: \(latency)")
    }
}

// MARK: - Kiểm bộ so khớp (lượt test thường)

@Suite struct ORAGoldenComparatorTests {
    @Test func blankVaChuoiRongPhanBietBangCotThamDo() {
        #expect(GoldenComparator.compareCell(golden: "", engine: .blank, goldenIsBlank: true) == nil)
        #expect(GoldenComparator.compareCell(golden: "", engine: .string(""), goldenIsBlank: false) == nil)
        #expect(GoldenComparator.compareCell(golden: "", engine: .blank, goldenIsBlank: false) != nil)
        #expect(GoldenComparator.compareCell(golden: "", engine: .string(""), goldenIsBlank: true) != nil)
    }

    @Test func soTheoQuyTacO2() {
        #expect(GoldenComparator.compareCell(golden: "0.3333333333333333", engine: .double(1.0 / 3), goldenIsBlank: nil) == nil)
        #expect(GoldenComparator.compareCell(golden: "1.2346", engine: .currency(12_346), goldenIsBlank: nil) == nil)
        #expect(GoldenComparator.compareCell(golden: "Infinity", engine: .double(.infinity), goldenIsBlank: nil) == nil)
        #expect(GoldenComparator.compareCell(golden: "NaN", engine: .double(.nan), goldenIsBlank: nil) == nil)
        #expect(GoldenComparator.compareCell(golden: "5369", engine: .integer(5368), goldenIsBlank: nil) != nil)
        #expect(GoldenComparator.compareCell(golden: "true", engine: .boolean(true), goldenIsBlank: nil) == nil)
    }

    @Test func ngayDangCopyCuaPowerBI() {
        // 31/12/2018 16:03:36 = serial 43465 + (16*3600 + 3*60 + 36) / 86400.
        let seconds: Double = 16 * 3600 + 3 * 60 + 36
        let serial: Double = 43_465 + seconds / 86_400
        #expect(GoldenComparator.compareCell(golden: "Mon, 31 Dec 2018 16:03:36", engine: .dateTime(serial),
                                             goldenIsBlank: nil) == nil)
    }

    @Test func doiCotTheoTenVaBaoThieuDong() {
        let golden = GoldenTable(text: "Dim_Date[year]\t[m]\t[m · ISBLANK]\r\n2017\t5\tfalse\r\n2018\t\ttrue\r\n")
        let ok = ResultTable(columns: ["[m]", "Dim_Date[year]", "[m · ISBLANK]"],
                             rows: [[.integer(5), .integer(2017), .boolean(false)],
                                    [.blank, .integer(2018), .boolean(true)]])
        #expect(GoldenComparator.compare(golden: golden, engine: ok).isEmpty)
        let short = ResultTable(columns: ok.columns, rows: [ok.rows[0]])
        #expect(!GoldenComparator.compare(golden: golden, engine: short).isEmpty)
    }
}
