// Test nặng D3 trên Nhom6 thật: BIPRO_HEAVY=1 (tên có "D3Nhom6"). File: BIPRO_NHOM6, hoặc
// ~/Downloads/Nhom6_Dashboard.pbix, hoặc ~/Downloads/bipro-golden/Nhom6_work.pbix.
import CoreGraphics
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

@Suite("D3: D3Nhom6", .enabled(if: heavy && nhom6 != nil), .serialized)
@MainActor
struct D3Nhom6Tests {
    static let page = "d1_giaodich"
    static let line = "c36625920078b7e0c75a"     // lineChart month_start, Y Trans Amount, Tooltips Trans Count
    static let combo = "69ca295f8b26f0422c5c"    // combo cột + đường: year_month, Y Neg Balance Trans, Y2 Avg_Account_Balance, Tooltips
    static let donut = "b1106ee1bf9281ad7b51"    // donut: Category 3 cột, Y Trans Amount, Tooltips 2 measure
    static let view = CGRect(x: 200, y: 150, width: 1400, height: 800)
    static let title = "26265d5a69c35d3f0976"     // hộp văn bản tiêu đề D1: hai đoạn có kiểu chữ

    private func outputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/d-out/D3", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func number(_ value: Value) -> Double? {
        switch value {
        case .integer(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }

    @Test func themDoiLoaiLuuMoLaiVaSoSanh() async throws {
        let source = try #require(nhom6)
        let sourceStamp = try FileStamp.of(source)
        let original = try PBIXFile(url: source)
        let archive = original.archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor(report: workspace.report, sourceJSON: { page, id in
            try? archive.read(LayoutEditor.visualPath(page: page, id: id))
        })
        editor.showPage(Self.page)

        // 1. Thêm card và biểu đồ thanh nhóm, thả trường.
        let card = try #require(editor.insertVisual(type: "card", visibleRect: Self.view))
        #expect(editor.addField(FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Net_Cashflow"), to: "Values", visual: card) == nil)
        let bar = try #require(editor.insertVisual(type: "clusteredBarChart", visibleRect: Self.view))
        #expect(editor.addField(FieldRef(kind: .column, entity: "Dim_Date", property: "month_name", family: .text), to: "Category", visual: bar) == nil)
        #expect(editor.addField(FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Total_Credit_Inflow"), to: "Y", visual: bar) == nil)

        // 2. Đổi loại: đường → thanh nhóm, combo → đường, donut → treemap. In kết quả để theo dõi.
        var results: [String: String?] = [:]
        results["line→bar"] = editor.changeType(of: Self.line, to: "clusteredBarChart")
        results["combo→line"] = editor.changeType(of: Self.combo, to: "lineChart")
        results["donut→treemap"] = editor.changeType(of: Self.donut, to: "treemap")
        for (key, value) in results.sorted(by: { $0.key < $1.key }) { print("D3Nhom6: \(key) = \(value ?? "ok") | notice=\(editor.notice ?? "-")") }
        #expect(results["line→bar"]! == nil, "đường sang thanh nhóm phải đổi được")
        #expect(results["donut→treemap"]! == nil, "donut sang treemap phải đổi được")
        // combo → đường có thể bị chặn nếu trường bị bỏ còn được nhắc ở nơi khác: nếu chặn thì phải nêu lý do và không đổi gì.
        if let reason = results["combo→line"]! {
            #expect(!reason.isEmpty && editor.visual(Self.combo)?.type == "lineClusteredColumnComboChart")
        } else {
            #expect(editor.visual(Self.combo)?.type == "lineChart")
        }
        #expect(editor.visual(Self.line)?.type == "clusteredBarChart" && editor.visual(Self.donut)?.type == "treemap")
        // Sửa chữ đoạn đầu của hộp văn bản tiêu đề (giữ kiểu chữ và đoạn thứ hai).
        let titleBefore = try #require(editor.visual(Self.title))
        var titleLines = LayoutEditor.paragraphTexts(of: titleBefore.raw)
        let titleStyle = titleBefore.raw["visual"]?["objects"]?["general"]?[0]?["properties"]?["paragraphs"]?[0]?["textRuns"]?[0]?["textStyle"]
        titleLines[0] += " (đã sửa chữ)"
        #expect(editor.setText(titleLines.joined(separator: "\n"), visual: Self.title) == nil)
        #expect(editor.isDirty)

        // 3. Vẽ các visual đã sửa bằng engine (trước khi lưu).
        let interaction = ReportInteraction(workspace: workspace)
        let editedPage = try #require(editor.page(Self.page))
        let ids = [card, bar, Self.line, Self.donut, Self.combo]
        var queriesBefore: [String: String] = [:]
        var redrawMs: [String: Double] = [:]
        for id in ids {
            let visual = try #require(editedPage.visuals.first { $0.id == id })
            let t0 = ContinuousClock.now
            let data = try await interaction.load(page: editedPage, visual: visual, state: interaction.state(for: editedPage))
            let d = t0.duration(to: .now)
            redrawMs[id] = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            queriesBefore[id] = data.query
            if case .empty(let reason) = data.view { Issue.record("\(visual.type) \(id) trống: \(reason)") }
        }
        // Số của card mới bằng truy vấn DAX viết tay cùng hai bộ lọc cấp report.
        let engine = try workspace.daxEngine()
        let cardVisual = try #require(editedPage.visuals.first { $0.id == card })
        guard case .single(let single) = try await interaction.load(page: editedPage, visual: cardVisual, state: interaction.state(for: editedPage)).view else {
            Issue.record("card mới không phải card"); return
        }
        let drawn = try #require(number(single.cell.value))
        let filters = "NOT('Dim_Date'[year] IN {9999}), NOT('Dim_Client'[client_region] IN {\"Unknown\"})"
        let expected = try await engine.execute("EVALUATE ROW(\"v\", CALCULATE([Net_Cashflow], \(filters)))")
        let truth = try #require(expected.tables.first?.rows.first?.first.flatMap(number))
        #expect(abs(drawn - truth) <= max(1e-9, abs(truth) * 1e-9), "card mới \(drawn) khác DAX viết tay \(truth)")

        // 4. Lưu thành bản mới.
        let dir = try outputDirectory()
        let output = dir.appendingPathComponent("Nhom6_d3.pbix")
        try? FileManager.default.removeItem(at: output)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-d3-backups-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: backups) }
        let started = Date()
        let outcome = try DocumentSaver.save(editor: editor, source: source, to: output, expectedStamp: sourceStamp, backupDirectory: backups)
        let elapsed = Date().timeIntervalSince(started)
        print("D3Nhom6: lưu \(String(format: "%.3f", elapsed)) s; vẽ lại (ms): \(redrawMs.map { "\($0.key.prefix(8))=\(Int($0.value))" }.sorted().joined(separator: " "))")
        #expect(outcome.didWrite && !editor.isDirty)
        var best = elapsed
        var attempt = 0
        while best >= 1.0, attempt < 2 {
            attempt += 1
            let scratch = backups.appendingPathComponent("retry\(attempt).pbix")
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            let t0 = Date()
            _ = try DocumentSaver.save(editor: editor, source: source, to: scratch, expectedStamp: sourceStamp, backupDirectory: backups)
            best = min(best, Date().timeIntervalSince(t0))
        }
        #expect(best < 1.0, "lưu dưới 1 s, thực tế \(best) s (máy rảnh)")
        #expect(try FileStamp.of(source) == sourceStamp, "nguồn không bị đổi")

        // 5. Mở lại: loại, khung, ô, trường giống; truy vấn sinh ra giống hệt.
        let savedWorkspace = try Workspace(data: Data(contentsOf: output))
        let savedPage = try #require(savedWorkspace.report.pages.first { $0.id == Self.page })
        for id in ids {
            let want = try #require(editedPage.visuals.first { $0.id == id })
            let got = try #require(savedPage.visuals.first { $0.id == id }, Comment(rawValue: "thiếu \(id)"))
            #expect(got.type == want.type && Frame(got) == Frame(want) && Int(got.z) == Int(want.z), Comment(rawValue: id))
            #expect(got.fields == want.fields, Comment(rawValue: id))
        }
        let savedInteraction = ReportInteraction(workspace: savedWorkspace)
        for id in ids {
            let visual = try #require(savedPage.visuals.first { $0.id == id })
            let data = try await savedInteraction.load(page: savedPage, visual: visual, state: savedInteraction.state(for: savedPage))
            #expect(data.query == queriesBefore[id], Comment(rawValue: "truy vấn sau khi mở lại của \(id) phải giống trước khi lưu"))
        }
        // Visual không sửa khớp byte; phần ngoài báo cáo khớp CRC (trừ SecurityBindings và Content_Types).
        let afterZip = try ZipArchive(url: output)
        let savedTitle = try #require(savedPage.visuals.first { $0.id == Self.title })
        #expect(LayoutEditor.paragraphTexts(of: savedTitle.raw) == titleLines, "chữ hộp văn bản giống trước khi lưu")
        #expect(savedTitle.raw["visual"]?["objects"]?["general"]?[0]?["properties"]?["paragraphs"]?[0]?["textRuns"]?[0]?["textStyle"] == titleStyle, "kiểu chữ giữ nguyên")
        let editedPaths = Set([Self.line, Self.donut, Self.combo, Self.title].map { LayoutEditor.visualPath(page: Self.page, id: $0) })
        for entry in archive.entries where !editedPaths.contains(entry.path) {
            if entry.path == "SecurityBindings" { #expect(afterZip.entry(entry.path) == nil); continue }
            if entry.path == "[Content_Types].xml" { continue }
            let now = try #require(afterZip.entry(entry.path), Comment(rawValue: entry.path))
            #expect(now.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        #expect(try afterZip.read("DataModel") == archive.read("DataModel"))
        #expect(afterZip.entry(LayoutEditor.visualPath(page: Self.page, id: card)) != nil && afterZip.entry(LayoutEditor.visualPath(page: Self.page, id: bar)) != nil)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tq", output.path]
        let pipe = Pipe()
        unzip.standardOutput = pipe; unzip.standardError = pipe
        try unzip.run(); unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
    }
}
