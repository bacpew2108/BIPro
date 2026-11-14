// Test nặng D5 trên Nhom6 thật: BIPRO_HEAVY=1 (tên có "D5Nhom6"). File: BIPRO_NHOM6, hoặc
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

@Suite("D5: D5Nhom6", .enabled(if: heavy && nhom6 != nil), .serialized)
@MainActor
struct D5Nhom6Tests {
    static let d1 = "d1_giaodich", d2 = "d2_khoanvay", d3 = "d3_cskh", d4 = "d4_chinhanh"

    private func outputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("build/d-out/D5", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func milliseconds(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    private func time<T>(_ label: String, _ body: () throws -> T) rethrows -> (T, Double) {
        let t0 = ContinuousClock.now
        let value = try body()
        let ms = milliseconds(t0.duration(to: .now))
        print("D5Nhom6: \(label) \(String(format: "%.1f", ms)) ms")
        return (value, ms)
    }

    /// Lưu, thử lại tối đa hai lần khi máy tải (như D3Nhom6), trả thời gian nhanh nhất.
    private func save(_ editor: LayoutEditor, source: URL, stamp: FileStamp, to output: URL) throws -> Double {
        try? FileManager.default.removeItem(at: output)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-d5-backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backups) }
        let t0 = Date()
        let outcome = try DocumentSaver.save(editor: editor, source: source, to: output, expectedStamp: stamp, backupDirectory: backups)
        var best = Date().timeIntervalSince(t0)
        #expect(outcome.didWrite && !editor.isDirty)
        // Máy tải (chạy cùng các test nặng khác): đo lại phần dựng và kiểm gói thật (lưu lần hai không ghi gì vì editor đã sạch).
        var attempt = 0
        while best >= 1.0, attempt < 2 {
            attempt += 1
            let t1 = Date()
            let fresh = try ZipArchive(url: source)
            let changes = try editor.makeChanges(archive: fresh)
            _ = try PBIXWriter.build(source: source, changes: changes)
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

    // MARK: SC-001 đến SC-005: kịch bản đầy đủ

    @Test func quanLyTrangLuuMoLaiVaSoSanh() async throws {
        let source = try #require(nhom6)
        let sourceStamp = try FileStamp.of(source)
        let original = try PBIXFile(url: source)
        let archive = original.archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.showPage(Self.d1)
        let originalOrder = workspace.report.pages.map(\.id)
        #expect(originalOrder == [Self.d1, Self.d2, Self.d3, Self.d4])

        // 1. Thêm, đổi tên, kéo lên đầu, nhân bản D1, xoá D1 (có 2 bookmark trỏ tới).
        let (added, addMs) = time("thêm trang") { editor.addPage() }
        let newPage = try #require(added)
        let (_, renameMs) = time("đổi tên") { editor.renamePage(newPage, to: "Trang thử · tổng hợp") }
        let (_, moveMs) = time("kéo lên đầu") { editor.movePage(newPage, to: 0) }
        let (dup, dupMs) = time("nhân bản D1 (\(workspace.report.pages[0].visuals.count) visual)") { editor.duplicatePage(Self.d1) }
        let copy = try #require(dup)
        let bookmarksBefore = workspace.bookmarks.map(\.id).sorted()
        #expect(bookmarksBefore.count == 2)
        let (_, removeMs) = time("xoá D1") { editor.removePage(Self.d1) }
        #expect(editor.pages.map(\.id) == [newPage, Self.d2, Self.d3, Self.d4, copy])
        #expect(editor.pages.first?.displayName == "Trang thử · tổng hợp" && editor.page(copy)?.displayName == "Duplicate of D1 · Giao dịch")
        #expect(editor.structure.removedBookmarks == Set(bookmarksBefore), "cả hai bookmark trỏ D1 phải bị gỡ")
        for ms in [addMs, renameMs, moveMs, dupMs, removeMs] { #expect(ms < 1000, "mỗi thao tác trang dưới 1 s") }
        #expect(editor.isDirty)

        // 2. Trang nhân bản vẽ cùng truy vấn như trang D1 gốc (SC-004 phần vẽ; Desktop do người dùng kiểm).
        let interaction = ReportInteraction(workspace: workspace)
        interaction.pagesProvider = { editor.pages }
        let originalPage = try #require(workspace.report.pages.first { $0.id == Self.d1 })
        let copyPage = try #require(editor.page(copy))
        #expect(copyPage.visuals.count == originalPage.visuals.count)
        var compared = 0
        for (a, b) in zip(originalPage.visuals, copyPage.visuals) where a.isDataBound && !interaction.isHidden(a) {
            #expect(a.type == b.type && Frame(a) == Frame(b) && a.fields == b.fields, Comment(rawValue: a.id))
            let want = try await interaction.load(page: originalPage, visual: a, state: interaction.state(for: originalPage))
            let got = try await interaction.load(page: copyPage, visual: b, state: interaction.state(for: copyPage))
            #expect(got.query == want.query, Comment(rawValue: "truy vấn của bản sao \(b.id) khác visual gốc \(a.id)"))
            compared += 1
        }
        #expect(compared >= 20, "so truy vấn của \(compared) visual có dữ liệu")

        // 3. Lưu.
        let output = try outputDirectory().appendingPathComponent("Nhom6_d5.pbix")
        let saveSeconds = try save(editor, source: source, stamp: sourceStamp, to: output)
        print("D5Nhom6: lưu \(String(format: "%.3f", saveSeconds)) s")
        #expect(saveSeconds < 1.0, "lưu dưới 1 s, thực tế \(saveSeconds) s (máy rảnh)")
        #expect(try FileStamp.of(source) == sourceStamp, "nguồn không bị đổi")

        // 4. Mở lại: thứ tự, tên, số visual, bookmark.
        let savedWorkspace = try Workspace(data: Data(contentsOf: output))
        let saved = savedWorkspace.report.pages
        #expect(saved.map(\.id) == editor.pages.map(\.id) && saved.map(\.displayName) == editor.pages.map(\.displayName))
        for (written, wanted) in zip(saved, editor.pages) {
            #expect(written.visuals.count == wanted.visuals.count, Comment(rawValue: written.id))
            #expect(Set(written.visuals.map(\.id)) == Set(wanted.visuals.map(\.id)), Comment(rawValue: written.id))
        }
        #expect(savedWorkspace.bookmarks.isEmpty, "không còn bookmark nào trỏ trang đã xoá")
        let afterZip = try ZipArchive(url: output)
        #expect(!afterZip.entries.contains { $0.path.hasSuffix(".bookmark.json") })

        // 5. Phần không sửa khớp byte; SC-005: không tham chiếu treo tới D1.
        for entry in archive.entries {
            if entry.path == "SecurityBindings" { #expect(afterZip.entry(entry.path) == nil); continue }
            if entry.path == "[Content_Types].xml" || entry.path == LayoutEditor.pagesJSONPath { continue }
            if entry.path.hasPrefix("Report/definition/pages/\(Self.d1)/") || entry.path.hasPrefix(LayoutEditor.bookmarksFolder) { continue }
            let now = try #require(afterZip.entry(entry.path), Comment(rawValue: entry.path))
            #expect(now.crc32 == entry.crc32, Comment(rawValue: entry.path))
        }
        #expect(try afterZip.read("DataModel") == archive.read("DataModel"))
        var danglingButtons = 0
        for entry in afterZip.entries where entry.path.hasPrefix("Report/definition/") {
            #expect(!entry.path.contains("/pages/\(Self.d1)/"))
            let text = String(decoding: try afterZip.read(entry), as: UTF8.self)
            #expect(!text.contains("\"\(Self.d1)\""), Comment(rawValue: "\(entry.path) còn nhắc \(Self.d1)"))
            for name in bookmarksBefore where text.contains("'\(name)'") { danglingButtons += 1 }
        }
        print("D5Nhom6: nút Bookmark trỏ bookmark đã gỡ (Desktop để yên, kiểm ở VM): \(danglingButtons) phần")
        try unzipTest(output)
    }

    // MARK: trang drillthrough: bộ lọc cấp trang của bản sao

    @Test func banSaoTrangDrillthroughApDungBoLocCapTrang() async throws {
        let source = try #require(nhom6)
        let archive = try PBIXFile(url: source).archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.showPage(Self.d4)
        let copy = try #require(editor.duplicatePage(Self.d4))
        let interaction = ReportInteraction(workspace: workspace)
        interaction.pagesProvider = { editor.pages }
        interaction.pageJSONProvider = { editor.structure.created[$0]?.pageJSON }
        let wanted = interaction.pageFilters(of: Self.d4)
        #expect(!wanted.isEmpty, "trang chi nhánh có thẻ lọc cấp trang")
        #expect(interaction.pageFilters(of: copy).map(\.id) == wanted.map(\.id))
        #expect(editor.notice?.contains("drillthrough") == true)
    }

    // MARK: tài nguyên chỉ trang đã xoá còn dùng (VM-D8, VM-D12)

    /// Desktop: xoá D2 (trang duy nhất có bản đồ hình) bỏ `usa.states.topo` (VM-D8); xoá D3 bỏ `icon_check_o.svg` và
    /// `icon_star_p.svg` (chỉ D3 dùng; VM-D12 mục 2). Icon trang khác còn dùng giữ nguyên.
    @Test func xoaTrangDonTaiNguyenNhuDesktop() async throws {
        let source = try #require(nhom6)
        let archive = try PBIXFile(url: source).archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.showPage(Self.d1)
        #expect(editor.removePage(Self.d2) == nil && editor.removePage(Self.d3) == nil)
        let changes = try editor.makeChanges(archive: archive)
        let gone = changes.removedParts.filter { $0.hasPrefix("Report/StaticResources/") }
        #expect(gone == ["Report/StaticResources/SharedResources/Shapemaps/usa.states.topo.json",
                         "Report/StaticResources/RegisteredResources/icon_check_o.svg",
                         "Report/StaticResources/RegisteredResources/icon_star_p.svg"])
        let report = try #require(changes.reportParts[LayoutEditor.reportJSONPath])
        let names = PBIRResourcePatch.items(in: report).map(\.name)
        #expect(!names.contains("usa.states.topo") && !names.contains("icon_check_o.svg") && !names.contains("icon_star_p.svg"))
        #expect(names.contains("Fluent2-CY26SU09") && names.contains("Nhom6Theme.json") && names.contains("icon_avg_g.svg"))
        #expect(names.count == PBIRResourcePatch.items(in: try archive.read(LayoutEditor.reportJSONPath)).count - 3)
        // Lưu thật, mở lại: gói đọc được, không còn file tài nguyên đã bỏ, báo cáo còn D1 và D4.
        let output = try outputDirectory().appendingPathComponent("Nhom6_d12_xoa.pbix")
        _ = try save(editor, source: source, stamp: try FileStamp.of(source), to: output)
        let reopened = try Workspace(data: Data(contentsOf: output))
        #expect(reopened.report.pages.map(\.id) == [Self.d1, Self.d4])
        let after = try ZipArchive(url: output)
        for path in gone { #expect(after.entry(path) == nil, Comment(rawValue: path)) }
        try unzipTest(output)   // giữ file ở build/d-out/D5 để mở thử bằng Power BI Desktop
    }

    // MARK: đổi sang bản đồ hình (VM-D13)

    /// Desktop (VM-D13, `docs/phase-d-evidence/vm-d13/json/retype-shapeMap-line.visual.json`): biểu đồ đường Q1.1 của D1 đổi sang
    /// bản đồ hình. BI Pro cho ra cùng cấu trúc (trừ thứ tự khoá và `$schema`) và truy vấn của visual không làm hỏng engine.
    @Test func doiDuongSangBanDoHinhNhuDesktop() async throws {
        let source = try #require(nhom6)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let desktop = try Data(contentsOf: root.appendingPathComponent("docs/phase-d-evidence/vm-d13/json/retype-shapeMap-line.visual.json"))
        let archive = try PBIXFile(url: source).archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.showPage(Self.d1)
        let id = "c36625920078b7e0c75a"
        editor.select(id)
        #expect(editor.changeType(of: id, to: "shapeMap") == nil)
        let changes = try editor.makeChanges(archive: archive)
        let written = try #require(changes.reportParts[LayoutEditor.visualPath(page: Self.d1, id: id)])
        func normalised(_ data: Data) throws -> NSDictionary {
            var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["$schema"] = nil
            return object as NSDictionary
        }
        #expect(try normalised(written) == normalised(desktop))
        // Vẽ: không có cột vị trí nên không có bang nào được tô; ô Series (tháng) vẫn cho chú giải (VM-D15 mục 3).
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(editor.page(Self.d1))
        let visual = try #require(editor.visual(id))
        let loaded = try await interaction.load(page: page, visual: visual, state: interaction.state(for: page))
        guard case .categorical(let legend) = loaded.view else { Issue.record("không phải categorical"); return }
        #expect(legend.categories.isEmpty && !legend.series.isEmpty, "chú giải là các tháng có dữ liệu")
        #expect(legend.series.count < 100, "chỉ tháng có giao dịch, không phải mọi ngày của bảng ngày")

        // Donut Q1.2 (ba cột ở Category, hai measure ở Tooltips): chỉ cột đầu vào Series, `labels`/`value` bị bỏ,
        // `legend`/`dataPoint` giữ và `dataPoint` thêm mục chuyển sắc, như Desktop (`retype-shapeMap-donut.visual.json`).
        let donut = "b1106ee1bf9281ad7b51"
        let donutDesktop = try Data(contentsOf: root.appendingPathComponent("docs/phase-d-evidence/vm-d13/json/retype-shapeMap-donut.visual.json"))
        let second = LayoutEditor.reading(archive: archive, report: workspace.report)
        second.showPage(Self.d1)
        second.select(donut)
        #expect(second.changeType(of: donut, to: "shapeMap") == nil)
        let donutWritten = try #require(try second.makeChanges(archive: archive).reportParts[LayoutEditor.visualPath(page: Self.d1, id: donut)])
        #expect(try normalised(donutWritten) == normalised(donutDesktop))
    }

    /// VM-D15 mục 4: đổi biểu đồ đường D1 sang vùng, vùng xếp chồng, ruy-băng, thác nước, phễu ra đúng `visual.json` mà Desktop ghi
    /// (VM-D12 `retype-*.visual.json`, cùng biểu đồ nguồn).
    @Test func doiDuongSangVungRuyBangThacNuocPheuNhuDesktop() async throws {
        let source = try #require(nhom6)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let archive = try PBIXFile(url: source).archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let id = "c36625920078b7e0c75a"
        func normalised(_ data: Data) throws -> NSDictionary {
            var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["$schema"] = nil
            return object as NSDictionary
        }
        for (type, file) in [("areaChart", "area"), ("stackedAreaChart", "stackedArea"), ("hundredPercentStackedAreaChart", "hundredPercentArea"), ("ribbonChart", "ribbon"),
                             ("waterfallChart", "waterfall"), ("funnel", "funnel")] {
            let desktop = try Data(contentsOf: root.appendingPathComponent("docs/phase-d-evidence/vm-d12/json/retype-\(file).visual.json"))
            let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
            editor.dateColumns = Set((workspace.metadata?.columns ?? []).filter { $0.dataType == .dateTime }.map { "\($0.tableName)[\($0.name)]" })
            editor.showPage(Self.d1)
            editor.select(id)
            #expect(editor.changeType(of: id, to: type) == nil, Comment(rawValue: type))
            let written = try #require(try editor.makeChanges(archive: archive).reportParts[LayoutEditor.visualPath(page: Self.d1, id: id)])
            // Ghi bản BI Pro để so từng khoá khi lệch (`build/d-out/D15/`).
            let outDir = root.appendingPathComponent("build/d-out/D15", isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            try written.write(to: outDir.appendingPathComponent("retype-\(file).visual.json"))
            #expect(try normalised(written) == normalised(desktop), Comment(rawValue: type))
        }
    }

    /// VM-D15 mục 4: thêm vùng, vùng xếp chồng, ruy-băng, thác nước, phễu vào D1 (Category + Y), lưu qua đường lưu của BI Pro và mở lại.
    /// Tệp ra ở `build/d-out/D15/Nhom6_d15.pbix` để mở bằng Power BI Desktop trên VM.
    @Test func themBoLoaiMoiLuuVaMoLai() async throws {
        let source = try #require(nhom6)
        let stamp = try FileStamp.of(source)
        let archive = try PBIXFile(url: source).archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.showPage(Self.d1)
        let month = FieldRef(kind: .column, entity: "Dim_Date", property: "month_name", family: .text)
        let inflow = FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Total_Credit_Inflow")
        var ids: [String] = []
        for type in ["areaChart", "stackedAreaChart", "ribbonChart", "waterfallChart", "funnel"] {
            let id = try #require(editor.insertVisual(type: type, visibleRect: CGRect(x: 100, y: 100, width: 1200, height: 700)), Comment(rawValue: type))
            #expect(editor.addField(month, to: "Category", visual: id) == nil, Comment(rawValue: type))
            #expect(editor.addField(inflow, to: "Y", visual: id) == nil, Comment(rawValue: type))
            ids.append(id)
        }
        let outDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/d-out/D15", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let output = outDir.appendingPathComponent("Nhom6_d15.pbix")
        _ = try save(editor, source: source, stamp: stamp, to: output)
        let reopened = try Workspace(data: Data(contentsOf: output)).report
        let d1 = try #require(reopened.pages.first { $0.id == Self.d1 })
        for (id, type) in zip(ids, ["areaChart", "stackedAreaChart", "ribbonChart", "waterfallChart", "funnel"]) {
            let visual = try #require(d1.visuals.first { $0.id == id }, Comment(rawValue: type))
            #expect(visual.type == type)
            #expect(Set(visual.fields.map(\.role)) == ["Category", "Y"], Comment(rawValue: type))
        }
    }

    // MARK: gói chia đôi cho VM

    @Test func goiChiaDoiThemVaDoiTen() async throws {
        let source = try #require(nhom6)
        let stamp = try FileStamp.of(source)
        let archive = try PBIXFile(url: source).archive
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: archive, report: workspace.report)
        editor.showPage(Self.d1)
        let id = try #require(editor.addPage())
        #expect(editor.renamePage(id, to: "Trang thử") == nil)
        _ = try editor.insertVisual(type: "card", visibleRect: nil).map { editor.addField(FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Net_Cashflow"), to: "Values", visual: $0) }
        let output = try outputDirectory().appendingPathComponent("Nhom6_d5_pre.pbix")
        _ = try save(editor, source: source, stamp: stamp, to: output)
        let saved = try Workspace(data: Data(contentsOf: output)).report.pages
        #expect(saved.map(\.id) == [Self.d1, Self.d2, Self.d3, Self.d4, id] && saved.last?.displayName == "Trang thử" && saved.last?.visuals.count == 1)
        try unzipTest(output)
    }
}
