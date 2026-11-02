// VISNhom6Tests.swift
// Test nặng cho 72 truy vấn visual của Nhom6 (Package E1, Phase C).
// Chạy khi BIPRO_HEAVY=1 và có ~/Downloads/Nhom6_Dashboard.pbix.

import ColumnStore
import Foundation
import PBIXKit
import Testing
import DAXTestSupport
@testable import DAXEngine

private let heavyEnabled = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

/// Engine Nhom6, nạp một lần cho mọi ca
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
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            return url
        }
        url = url.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

struct VisualQueryInfo: Sendable, CustomStringConvertible {
    let name: String
    let category: String
    let daxURL: URL
    let tsvURL: URL?

    var description: String { "[\(category)] \(name)" }
}

private func collectQueries() -> [VisualQueryInfo] {
    let root = repoRoot()
    var items: [VisualQueryInfo] = []

    let paDir = root.appendingPathComponent("docs/phase-c-evidence/observe-c1/pa")
    let paResultsDir = root.appendingPathComponent("docs/phase-c-evidence/observe-c1/results")
    if let files = try? FileManager.default.contentsOfDirectory(atPath: paDir.path) {
        for file in files.filter({ $0.hasSuffix(".dax") }).sorted() {
            let baseName = String(file.dropLast(4))
            let daxURL = paDir.appendingPathComponent(file)
            let tsvURL = paResultsDir.appendingPathComponent("\(baseName).tsv")
            let hasTSV = FileManager.default.fileExists(atPath: tsvURL.path)
            items.append(VisualQueryInfo(name: baseName, category: "pa", daxURL: daxURL, tsvURL: hasTSV ? tsvURL : nil))
        }
    }

    let interactDir = root.appendingPathComponent("docs/phase-c-evidence/observe-c1/interact")
    if let files = try? FileManager.default.contentsOfDirectory(atPath: interactDir.path) {
        for file in files.filter({ $0.hasSuffix(".dax") }).sorted() {
            let baseName = String(file.dropLast(4))
            let daxURL = interactDir.appendingPathComponent(file)
            items.append(VisualQueryInfo(name: baseName, category: "interact", daxURL: daxURL, tsvURL: nil))
        }
    }

    let pa2Dir = root.appendingPathComponent("docs/phase-b-evidence/observe2")
    if let files = try? FileManager.default.contentsOfDirectory(atPath: pa2Dir.path) {
        for file in files.filter({ $0.hasPrefix("PA-") && $0.hasSuffix(".dax") }).sorted() {
            let baseName = String(file.dropLast(4))
            let daxURL = pa2Dir.appendingPathComponent(file)
            let tsvURL = pa2Dir.appendingPathComponent("\(baseName).tsv")
            let hasTSV = FileManager.default.fileExists(atPath: tsvURL.path)
            items.append(VisualQueryInfo(name: baseName, category: "observe2", daxURL: daxURL, tsvURL: hasTSV ? tsvURL : nil))
        }
    }

    return items
}

private let allVisualQueries = collectQueries()

@Suite(.enabled(if: heavyEnabled && DAXFixtures.exists(DAXFixtures.nhom6)))
struct VISNhom6Tests {

    private static func parseGoldenTables(text: String) -> [GoldenTable] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        body = body.replacingOccurrences(of: "\r\n", with: "\n")
        if body.contains("#RESULT") {
            let lines = body.components(separatedBy: "\n")
            var chunks: [String] = []
            var currentChunk: [String] = []
            for line in lines {
                if line.hasPrefix("#RESULT") {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk.joined(separator: "\n"))
                        currentChunk = []
                    }
                } else {
                    currentChunk.append(line)
                }
            }
            if !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: "\n"))
            }
            return chunks.map { GoldenTable(text: $0) }
        } else {
            return [GoldenTable(text: body)]
        }
    }

    @Test(arguments: allVisualQueries)
    func testVisualQuery(_ item: VisualQueryInfo) async throws {
        let engine = try nhom6Engine.get()
        var query = try String(contentsOf: item.daxURL, encoding: .utf8)
        query = query.replacingOccurrences(of: "\r\n", with: "\n")
        if item.daxURL.lastPathComponent == "PA-D3-1.dax" {
            query = query.replacingOccurrences(of: "= \\\n", with: "=\n")
            query = query.replacingOccurrences(of: "= \\", with: "=")
        }

        let clock = ContinuousClock()
        let start = clock.now
        let result = try await engine.execute(query)
        let duration = start.duration(to: clock.now)

        var status = "OK (no tsv)"
        if let tsvURL = item.tsvURL {
            let tsvText = try String(contentsOf: tsvURL, encoding: .utf8)
            let goldenTables = Self.parseGoldenTables(text: tsvText)

            var allMismatches: [String] = []
            for (idx, golden) in goldenTables.enumerated() {
                guard idx < result.tables.count else { break }
                let engineTable = result.tables[idx]
                let mismatches = GoldenComparator.compare(golden: golden, engine: engineTable)
                if !mismatches.isEmpty {
                    allMismatches.append("Bảng \(idx + 1): \(mismatches.count) ô lệch (\(mismatches.prefix(3).map(\.description).joined(separator: "; ")))")
                }
            }

            if allMismatches.isEmpty {
                status = "KHỚP (\(goldenTables.count) bảng)"
            } else {
                status = "LỆCH: " + allMismatches.joined(separator: " | ")
                #expect(allMismatches.isEmpty, "\(item.name): \(allMismatches.joined(separator: "; "))")
            }
        }

        print("[VIS-BENCHMARK] \(item.category)/\(item.name) | \(status) | \(duration)")
    }
}
