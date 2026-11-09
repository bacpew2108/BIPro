// BatchedNhom6Tests.swift
// E3-cấu-trúc (T017, T018): trên Nhom6 thật, đường gộp và đường cũ cho cùng kết quả từng ô với mọi truy vấn visual,
// và chạy song song nhiều lần không đổi kết quả. Chạy khi BIPRO_HEAVY=1 và có file Nhom6.

import ColumnStore
import Foundation
import PBIXKit
import Testing
import DAXTestSupport
@testable import DAXEngine

private let heavyEnabled = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

private let nhom6Engine: Result<DAXEngine, Error> = Result {
    let pbix = try PBIXFile(url: DAXFixtures.nhom6)
    let (abf, _) = try pbix.loadDataModel()
    let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    let store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: metadata))
    try store.prefetchAll()
    return DAXEngine(store: store, catalog: Catalog(metadata: metadata))
}

private func repoRoot() -> URL {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while url.path != "/" {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
        url = url.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

/// Mọi truy vấn visual Nhom6: `pa/`, `interact/` (Phase C) và `PA-*` của observe2 (Phase B).
private func visualQueries() -> [(name: String, text: String)] {
    let root = repoRoot()
    let dirs: [(String, (String) -> Bool)] = [
        ("docs/phase-c-evidence/observe-c1/pa", { $0.hasSuffix(".dax") }),
        ("docs/phase-c-evidence/observe-c1/interact", { $0.hasSuffix(".dax") }),
        ("docs/phase-b-evidence/observe2", { $0.hasPrefix("PA-") && $0.hasSuffix(".dax") }),
    ]
    var out: [(String, String)] = []
    for (dir, accept) in dirs {
        let url = root.appendingPathComponent(dir)
        for file in ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter(accept).sorted() {
            guard var text = try? String(contentsOf: url.appendingPathComponent(file), encoding: .utf8) else { continue }
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
            if file == "PA-D3-1.dax" {
                text = text.replacingOccurrences(of: "= \\\n", with: "=\n").replacingOccurrences(of: "= \\", with: "=")
            }
            out.append(("\(dir.split(separator: "/").last!)/\(file)", text))
        }
    }
    return out
}

extension BatchedSerial {
@Suite(.enabled(if: heavyEnabled && DAXFixtures.exists(DAXFixtures.nhom6)))
struct BatchedNhom6Tests {
    @Test func haiDuongChoCungKetQuaTrenMoiTruyVanVisual() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = try nhom6Engine.get()
        let queries = visualQueries()
        #expect(queries.count >= 60)
        var batchedQueries = 0
        for (name, text) in queries {
            BatchedIteration.overrideEnabled = false
            let old = try await engine.execute(text).tables
            let before = BatchedIteration.takenCount(engine.store)
            BatchedIteration.overrideEnabled = true
            let new = try await engine.execute(text).tables
            #expect(old == new, "\(name): đường gộp khác đường cũ")
            if BatchedIteration.takenCount(engine.store) > before { batchedQueries += 1 }
        }
        print("[E3] \(queries.count) truy vấn; đường gộp chạy ở \(batchedQueries)")
        #expect(batchedQueries > 0, "đường gộp phải chạy ít nhất ở combo thấu chi")
    }

    @Test func chayTheoSongSongKhongDoiKetQua() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = try nhom6Engine.get()
        let root = repoRoot().appendingPathComponent("docs/phase-c-evidence/observe-c1/pa")
        for name in ["D1-combo-thauchi", "D1-matrix-gio-thu"] {
            let text = try String(contentsOf: root.appendingPathComponent("\(name).dax"), encoding: .utf8)
                .replacingOccurrences(of: "\r\n", with: "\n")
            BatchedIteration.overrideEnabled = false
            let reference = try await engine.execute(text).tables
            BatchedIteration.overrideEnabled = true
            // 20 lượt, 4 lượt chạy đồng thời mỗi nhóm (mỗi lượt đã tự chạy ô song song).
            for _ in 0..<5 {
                let results = try await withThrowingTaskGroup(of: [ResultTable].self) { group in
                    for _ in 0..<4 { group.addTask { try await engine.execute(text).tables } }
                    var all: [[ResultTable]] = []
                    for try await r in group { all.append(r) }
                    return all
                }
                for r in results { #expect(r == reference, "\(name): kết quả chạy song song khác bản tham chiếu") }
            }
        }
    }
}
}
