// Test nặng: sinh `build/d-out/D8/Nhom6_d8.pbix` chứa phần sửa mới sau VM-D8 để mở trong Power BI Desktop.
// BIPRO_HEAVY=1 (tên có "D8Nhom6"). Nguồn như D4Nhom6Tests.
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private let heavy = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"

private let nhom6: URL? = {
    let fm = FileManager.default
    if let path = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
    let url = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/bipro-golden/Nhom6_work.pbix")
    return fm.fileExists(atPath: url.path) ? url : nil
}()

@Suite("D8: D8Nhom6", .enabled(if: heavy && nhom6 != nil), .serialized)
@MainActor
struct D8Nhom6Tests {
    static let d1 = "d1_giaodich", d3 = "d3_cskh"

    @Test func ghiPhanSuaMoiRoiMoLai() throws {
        let source = try #require(nhom6)
        let stamp = try FileStamp.of(source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let editor = LayoutEditor.reading(archive: try PBIXFile(url: source).archive, report: workspace.report)
        editor.decimalColumns = Set((workspace.metadata?.columns ?? []).filter { $0.dataType == .double }.map { "\($0.tableName)[\($0.name)]" })

        // 1. Màu theo từng chuỗi: biểu đồ trục không có Chú giải, ở trang bất kỳ.
        var seriesVisual: (page: String, id: String, ref: String)?
        search: for page in workspace.report.pages {
            editor.showPage(page.id)
            for v in editor.visuals(of: page.id) {
                if let card = editor.formatState(of: v.id)?.objects.first(where: { $0.card.objectKey == "dataPoint" }),
                   let first = card.series.first, first.blocker == nil, card.isEditable {
                    seriesVisual = (page.id, v.id, first.queryRef); break search
                }
            }
        }
        let series = try #require(seriesVisual)
        editor.showPage(series.page)
        #expect(editor.setFormat(.color(.hex("#E4572E")), scope: .objects, object: "dataPoint", property: "fill", visual: series.id, series: series.ref) == nil)

        // 2. Trang D3: cardVisual mới (ô Data), hai nhóm lồng nhau và Merge.
        editor.showPage(Self.d3)
        let card = try #require(editor.insertVisual(type: "cardVisual", visibleRect: nil))
        #expect(editor.addField(FieldRef(kind: .measure, entity: "Fact_Transaction", property: "Net_Cashflow"), to: "Data", visual: card) == nil)
        let others = editor.visuals(of: Self.d3).filter { $0.id != card && !$0.isGroup }.prefix(4).map(\.id)
        #expect(others.count == 4)
        editor.select(others[0]); editor.select(others[1], extend: true)
        let inner = try #require(editor.group())
        editor.select(inner); editor.select(others[2], extend: true)
        let outer = try #require(editor.group())                                  // nhóm ngoài chứa nhóm trong
        editor.select(outer); editor.select(others[3], extend: true)
        #expect(editor.mergeBlocker() == nil)
        #expect(editor.mergeIntoGroup() == outer)

        // 3. Nhóm bookmark.
        let ids = ["0a1b2c3d4e5f60718293", "1a1b2c3d4e5f60718293"]
        for (i, id) in ids.enumerated() { #expect(editor.addBookmark(BookmarkFilterSavingTests.displayBookmark(id, name: "D8 bookmark \(i + 1)", page: Self.d3))) }
        #expect(editor.groupBookmarks(ids, id: "2a1b2c3d4e5f60718293", name: "D8 nhóm"))

        // 4. Bộ lọc Advanced: cột số thực nếu có, 5 < x ≤ 90 (toán hạng nguyên trên cột double ghi `D`).
        let decimal = try #require(workspace.metadata?.columns.first { $0.dataType == .double && !$0.isHidden })
        let column = QueryColumn(table: decimal.tableName, column: decimal.name)
        let rule = FilterRule.advanced(first: FilterCondition(kind: .greaterThan, operand: "5"),
                                       second: FilterCondition(kind: .lessOrEqual, operand: "90"), useOr: false, numeric: true)
        #expect(editor.setFilter(UserFilter(column: column, rule: rule), for: UserFilterKey(level: .page, scope: Self.d3, filterID: "added-d8-decimal")))

        // 5. Matrix: bố cục Tabular.
        editor.showPage(Self.d1)
        let matrix = try #require(editor.visuals(of: Self.d1).first { $0.type == "pivotTable" })
        #expect(editor.setFormat(.choice("'Tabular'"), scope: .objects, object: "general", property: "layout", visual: matrix.id) == nil)

        // Lưu và đọc lại.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/d-out/D8", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let output = dir.appendingPathComponent("Nhom6_d8.pbix")
        try? FileManager.default.removeItem(at: output)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent("bipro-d8-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backups) }
        let outcome = try DocumentSaver.save(editor: editor, source: source, to: output, expectedStamp: stamp, backupDirectory: backups)
        #expect(outcome.didWrite && !editor.isDirty)
        let reopened = try Workspace(data: Data(contentsOf: output))
        let page = try #require(reopened.report.pages.first { $0.id == Self.d3 })
        #expect(page.visuals.contains { $0.id == card && $0.type == "cardVisual" })
        print("D8Nhom6: card=\(card) series=\(series.page)/\(series.id)/\(series.ref) decimal=\(column.table)[\(column.column)] matrix=\(matrix.id)")
    }
}
