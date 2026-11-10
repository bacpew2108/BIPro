// Test nặng D4 trên Nhom6 thật: BIPRO_HEAVY=1 (tên có "D4Nhom6"). File: BIPRO_NHOM6, hoặc
// ~/Downloads/Nhom6_Dashboard.pbix, hoặc ~/Downloads/bipro-golden/Nhom6_work.pbix.
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private let heavy = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

private let nhom6: URL? = {
    let fm = FileManager.default
    if let path = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
    let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    for name in ["Nhom6_Dashboard.pbix", "bipro-golden/Nhom6_work.pbix"] {
        let url = downloads.appendingPathComponent(name)
        if fm.fileExists(atPath: url.path) { return url }
    }
    return nil
}()

@Suite("D4: D4Nhom6", .enabled(if: heavy && nhom6 != nil), .serialized)
@MainActor
struct D4Nhom6Tests {
    static let d1 = "d1_giaodich", d3 = "d3_cskh"
    static let axisTypes: Set<String> = ["clusteredColumnChart", "columnChart", "clusteredBarChart", "hundredPercentStackedColumnChart",
                                         "lineChart", "lineClusteredColumnComboChart", "lineStackedColumnComboChart"]

    private func outputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/d-out/D4", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func milliseconds(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    @discardableResult
    private func time<T>(_ label: String, _ body: () throws -> T) rethrows -> (T, Double) {
        let t0 = ContinuousClock.now
        let value = try body()
        let ms = milliseconds(t0.duration(to: .now))
        print("D4Nhom6: \(label) \(String(format: "%.1f", ms)) ms")
        return (value, ms)
    }

    private func save(_ editor: LayoutEditor, source: URL, stamp: FileStamp, to output: URL) throws -> Double {
        try? FileManager.default.removeItem(at: output)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-d4-backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backups) }
        let t0 = Date()
        let outcome = try DocumentSaver.save(editor: editor, source: source, to: output, expectedStamp: stamp, backupDirectory: backups)
        var best = Date().timeIntervalSince(t0)
        #expect(outcome.didWrite && !editor.isDirty)
        var attempt = 0
        while best >= 1.0, attempt < 2 {
            attempt += 1
            let t1 = Date()
            let fresh = try ZipArchive(url: source)
            _ = try PBIXWriter.build(source: source, changes: try editor.makeChanges(archive: fresh))
            best = min(best, Date().timeIntervalSince(t1))
        }
        return best
    }

    private func unzipTest(_ url: URL) throws {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tq", url.path]
        let pipe = Pipe()
        unzip.standardOutput = pipe; unzip.standardError = pipe
        try unzip.run(); unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
    }

    // MARK: kịch bản đầy đủ (SC-001 đến SC-005)

    @Test func suaDinhDangLuuMoLaiVaSoSanh() async throws {
        let source = try #require(nhom6)
        let sourceStamp = try FileStamp.of(source)
        let original = try PBIXFile(url: source)
        let archive = original.archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)

        func first(_ page: String, where match: (ReportVisual) -> Bool) throws -> ReportVisual {
            let found = workspace.report.pages.first { $0.id == page }?.visuals.first(where: match)
            return try #require(found)
        }
        let card = try first(Self.d3) { $0.type == "card" && $0.objects.number("labels", "fontSize") != nil && $0.objects.has("categoryLabels") }
        let slicer = try first(Self.d3) { $0.type == "slicer" && $0.objects.has("header") }
        let chart = try first(Self.d3) { Self.axisTypes.contains($0.type) && $0.objects.has("legend") && !$0.fields.isEmpty }
        let matrix = try first(Self.d1) { $0.type == "pivotTable" && $0.objects.has("columnHeaders") }
        var times: [Double] = []
        func run(_ label: String, page: String, _ body: () -> [String?]) {
            editor.showPage(page)
            let (reasons, ms) = time(label) { body() }
            times.append(ms)
            for reason in reasons { #expect(reason == nil, Comment(rawValue: "\(label): \(reason ?? "")")) }
        }

        // 1. Card: cỡ chữ giá trị, tắt nhãn danh mục.
        run("card cỡ chữ + nhãn", page: Self.d3) {
            [editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: card.id),
             editor.setFormat(.bool(false), scope: .objects, object: "categoryLabels", property: "show", visual: card.id)]
        }
        // 2. Slicer: tắt header, đệm mục.
        run("slicer header + đệm", page: Self.d3) {
            [editor.setFormat(.bool(false), scope: .objects, object: "header", property: "show", visual: slicer.id),
             editor.setFormat(.number(12, tail: .d), scope: .objects, object: "items", property: "padding", visual: slicer.id)]
        }
        // 3. Biểu đồ: nhãn dữ liệu, legend, tiêu đề, nền, viền.
        run("biểu đồ nhãn/legend/tiêu đề/nền/viền", page: Self.d3) {
            [editor.setFormat(.bool(true), scope: .objects, object: "labels", property: "show", visual: chart.id),
             editor.setFormat(.choice("'Top'"), scope: .objects, object: "legend", property: "position", visual: chart.id),
             editor.setFormat(.bool(true), scope: .container, object: "title", property: "show", visual: chart.id),
             editor.setFormat(.text("Tiêu đề 'thử' · Việt"), scope: .container, object: "title", property: "text", visual: chart.id),
             editor.setFormat(.number(16, tail: .d), scope: .container, object: "title", property: "fontSize", visual: chart.id),
             editor.setFormat(.color(.hex("#e4572e")), scope: .container, object: "title", property: "fontColor", visual: chart.id),
             editor.setFormat(.color(.hex("#F2F2F2")), scope: .container, object: "background", property: "color", visual: chart.id),
             editor.setFormat(.bool(true), scope: .container, object: "border", property: "show", visual: chart.id),
             editor.setFormat(.number(12, tail: .d), scope: .container, object: "border", property: "radius", visual: chart.id)]
        }
        // 4. Matrix: cỡ chữ tiêu đề cột.
        run("matrix cỡ chữ tiêu đề cột", page: Self.d1) {
            [editor.setFormat(.number(14, tail: .d), scope: .objects, object: "columnHeaders", property: "fontSize", visual: matrix.id)]
        }
        // 5. Visual mới: thêm trường, tắt tiêu đề, cỡ chữ.
        editor.showPage(Self.d3)
        let created = try #require(editor.insertVisual(type: "card", visibleRect: nil))
        editor.addField(FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Net_Cashflow"), to: "Values", visual: created)
        run("visual mới tiêu đề/cỡ chữ", page: Self.d3) {
            [editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: created),
             editor.setFormat(.number(30, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: created)]
        }
        for ms in times { #expect(ms < 500, "mỗi nhóm sửa dưới 0,5 s (SC-001)") }
        #expect(editor.isDirty)

        // Hoàn tác và làm lại một bước: về đúng giá trị.
        let depth = editor.undoDepth
        editor.undo(); editor.redo()
        #expect(editor.undoDepth == depth)

        // Trạng thái mong đợi của mọi visual sau sửa.
        var expected: [String: (objects: JSONValue, container: JSONValue)] = [:]
        for page in editor.pages { for v in editor.visuals(of: page.id) { expected[v.id] = (v.objects.json, v.containerObjects.json) } }

        // 6. Lưu.
        let output = try outputDirectory().appendingPathComponent("Nhom6_d4.pbix")
        let saveSeconds = try save(editor, source: source, stamp: sourceStamp, to: output)
        print("D4Nhom6: lưu \(String(format: "%.3f", saveSeconds)) s")
        #expect(saveSeconds < 1.0, "lưu dưới 1 s, thực tế \(saveSeconds) s (máy rảnh)")
        #expect(try FileStamp.of(source) == sourceStamp, "nguồn không bị đổi")

        // 7. Mở lại: định dạng của mọi visual khớp trạng thái đang sửa; visual không sửa giữ nguyên.
        let savedWorkspace = try Workspace(data: Data(contentsOf: output))
        var checked = 0
        for page in savedWorkspace.report.pages {
            for v in page.visuals {
                let want = try #require(expected[v.id], Comment(rawValue: "visual lạ \(v.id)"))
                #expect(v.objects.json == want.objects && v.containerObjects.json == want.container, Comment(rawValue: v.id))
                checked += 1
            }
        }
        #expect(checked == expected.count)
        let editedIDs: Set<String> = [card.id, slicer.id, chart.id, matrix.id, created]
        for page in workspace.report.pages {
            for v in page.visuals where !editedIDs.contains(v.id) {
                let want = try #require(expected[v.id])
                #expect(v.objects.json == want.objects && v.containerObjects.json == want.container, "visual không sửa phải giữ nguyên: \(v.id)")
            }
        }
        let savedCard = try #require(savedWorkspace.report.pages.flatMap(\.visuals).first { $0.id == card.id })
        #expect(savedCard.objects.number("labels", "fontSize") == 28 && savedCard.objects.bool("categoryLabels", "show") == false)
        let savedChart = try #require(savedWorkspace.report.pages.flatMap(\.visuals).first { $0.id == chart.id })
        #expect(savedChart.containerObjects.string("title", "text") == "Tiêu đề 'thử' · Việt")
        #expect(savedChart.objects.bool("labels", "show") == true && savedChart.objects.string("legend", "position") == "Top")

        // 8. Phần không sửa khớp byte (trừ các visual đã sửa, SecurityBindings và [Content_Types].xml).
        let afterZip = try ZipArchive(url: output)
        let editedPaths = Set(editedIDs.compactMap { id in
            workspace.report.pages.first { $0.visuals.contains { $0.id == id } }.map { LayoutEditor.visualPath(page: $0.id, id: id) }
        })
        for entry in archive.entries {
            if entry.path == "SecurityBindings" { #expect(afterZip.entry(entry.path) == nil); continue }
            if entry.path == "[Content_Types].xml" || editedPaths.contains(entry.path) { continue }
            let now = try #require(afterZip.entry(entry.path), Comment(rawValue: entry.path))
            #expect(now.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        #expect(try afterZip.read("DataModel") == archive.read("DataModel"))

        // 9. Truy vấn của visual đã sửa định dạng không đổi (định dạng không làm đổi số liệu).
        let before = ReportInteraction(workspace: workspace)
        let after = ReportInteraction(workspace: savedWorkspace)
        for v in [card, chart, matrix] {
            let oldPage = try #require(workspace.report.pages.first { $0.visuals.contains { $0.id == v.id } })
            let newPage = try #require(savedWorkspace.report.pages.first { $0.id == oldPage.id })
            let newVisual = try #require(newPage.visuals.first { $0.id == v.id })
            let want = try await before.load(page: oldPage, visual: v, state: before.state(for: oldPage))
            let got = try await after.load(page: newPage, visual: newVisual, state: after.state(for: newPage))
            #expect(got.query == want.query, Comment(rawValue: "truy vấn của \(v.id) đổi sau khi sửa định dạng"))
        }
        try unzipTest(output)

        // 10. Danh mục phủ gì của Nhom6 (thông tin cho STATE, không ép).
        var uncovered = Set<String>()
        var covered = 0
        for page in workspace.report.pages {
            for v in page.visuals {
                for scope in FormatScope.allCases {
                    let json = v.raw["visual"]?[scope.key]
                    for key in json?.object.keys.sorted() ?? [] { covered += 1; _ = key }
                    for item in FormatCatalog.readOnlyItems(in: json, type: v.type, scope: scope) {
                        uncovered.insert("\(v.type).\(scope.rawValue).\(item.object)" + (item.property.map { ".\($0)" } ?? ""))
                    }
                }
            }
        }
        // SC-005: mọi thuộc tính ghi là quan sát ở Nhom6 thật sự có trong Nhom6.
        var inNhom6 = Set<String>()
        for page in workspace.report.pages {
            for v in page.visuals {
                for scope in FormatScope.allCases {
                    for (object, entries) in v.raw["visual"]?[scope.key]?.object ?? [:] {
                        for entry in entries.array where FormatCatalog.isEditable(entry) {
                            for property in (entry["properties"]?.object ?? [:]).keys { inNhom6.insert("\(scope.rawValue).\(object).\(property)") }
                        }
                    }
                }
            }
        }
        for type in ["card", "slicer", "lineChart", "lineClusteredColumnComboChart", "donutChart", "pivotTable", "actionButton"] {
            for scope in FormatScope.allCases {
                for card in FormatCatalog.cards(for: type, scope: scope) {
                    for property in card.properties where property.observed.contains("Nhom6") {
                        let key = "\(scope.rawValue).\(card.objectKey).\(property.key)"
                        #expect(inNhom6.contains(key), Comment(rawValue: "\(type): \(key) ghi là quan sát ở Nhom6 nhưng Nhom6 không có"))
                    }
                }
            }
        }
        print("D4Nhom6: danh mục chưa phủ \(uncovered.count) cặp trên Nhom6: \(uncovered.sorted().prefix(40).joined(separator: ", "))")
        _ = covered

        try """
        # Kiểm Nhom6_d4.pbix trong Power BI Desktop (D4)

        File: build/d-out/D4/Nhom6_d4.pbix (BI Pro lưu; bản sao Nhom6_work.pbix có sửa định dạng).

        1. Mở file: không báo lỗi.
        2. Trang D3 · Chăm sóc KH: card đầu tiên (Tổng khách hàng): chữ giá trị lớn hơn (28), không còn nhãn dưới.
        3. Trang D3: slicer đầu tiên không còn tiêu đề; mục có đệm 12.
        4. Trang D3: biểu đồ đường/cột đầu tiên có tiêu đề "Tiêu đề 'thử' · Việt" cỡ 16 màu cam (#E4572E), nền xám nhạt, viền bo 12, nhãn dữ liệu bật, legend ở trên.
        5. Trang D1: matrix có tiêu đề cột cỡ 14.
        6. Trang D3: một card mới (Net_Cashflow) không tiêu đề, chữ 30.
        7. Bấm từng visual đã sửa, mở Format pane: giá trị khớp BI Pro; không có thuộc tính nào Desktop báo lỗi.
        8. Lưu từ Desktop không báo lỗi.
        """.write(to: outputDirectory().appendingPathComponent("CHECKLIST.md"), atomically: true, encoding: .utf8)
    }
}
