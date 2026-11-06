// Test nặng gói P trên file thật: BIPRO_HEAVY=1 và có ~/Downloads/Nhom6_Dashboard.pbix.
import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

private let heavy = ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1"
private let nhom6 = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Nhom6_Dashboard.pbix")

@Suite("Gói P: Nhom6", .enabled(if: heavy && FileManager.default.fileExists(atPath: nhom6.path)))
struct PanesNhom6Tests {
    @Test @MainActor func haiBookmarkDocDuocTuFile() throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let byID = Dictionary(uniqueKeysWithValues: workspace.bookmarks.map { ($0.id, $0) })
        let gioThu = try #require(byID["Bookmark_Q13_GioThu"]), muaVu = try #require(byID["Bookmark_Q13_MuaVu"])
        #expect(workspace.bookmarks.count == 2)
        #expect(gioThu.suppressData && gioThu.targetVisualNames?.count == 6)
        #expect(gioThu.hidden["52888e846d301d4a1205"] == true, "line ẩn khi áp 'Giờ × Thứ'")
        #expect(gioThu.hidden["2132ddc1caa56c2879e6"] == false, "matrix hiện")
        #expect(muaVu.hidden["52888e846d301d4a1205"] == false)
        #expect(muaVu.hidden["2132ddc1caa56c2879e6"] == true)
    }

    @Test @MainActor func ganBookmarkDoiMatrixVaLine() throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.report.pages.first { $0.id == "d1_giaodich" })
        let matrix = try #require(page.visuals.first { $0.id == "2132ddc1caa56c2879e6" })
        let line = try #require(page.visuals.first { $0.id == "52888e846d301d4a1205" })
        _ = interaction.applyBookmark(id: "Bookmark_Q13_MuaVu")
        #expect(interaction.isHidden(matrix) && !interaction.isHidden(line))
        _ = interaction.applyBookmark(id: "Bookmark_Q13_GioThu")
        #expect(!interaction.isHidden(matrix) && interaction.isHidden(line))
    }

    @Test @MainActor func giaTriPhanBietCuaCot() async throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let years = try await interaction.distinctValues(of: QueryColumn(table: "Dim_Date", column: "year"))
        #expect(years.contains(.integer(2016)))
        #expect(years == years.sorted(by: FilterTranslator.valuePrecedes), "tăng dần")
        let regions = try await interaction.distinctValues(of: QueryColumn(table: "Dim_Client", column: "client_region"))
        #expect(regions.contains(.string("Unknown")))
        let capped = try await interaction.distinctValues(of: QueryColumn(table: "Dim_Date", column: "year"), limit: 3)
        #expect(capped.count == 3)
    }

    /// Mỗi thẻ ngầm cấp visual trên D1: đặt một giá trị rồi nạp lại, không được lỗi và không được treo.
    @Test @MainActor func boLocCapVisualTrenMoiThe() async throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.report.pages.first { $0.id == "d1_giaodich" })
        for visual in page.visuals {
            for field in visual.fields where field.kind == .column {
                let column = QueryColumn(table: field.entity, column: field.property)
                guard let first = try await interaction.distinctValues(of: column, limit: 1).first else { continue }
                let key = UserFilterKey(level: .visual, scope: visual.id, filterID: "implicit-\(field.queryRef)-\(field.role)")
                interaction.setUserFilter(UserFilter(column: column, values: [first], exclude: false), for: key)
                let data = try await interaction.load(page: page, visual: visual, state: interaction.state(for: page))
                if case .empty(let reason) = data.view { Issue.record("\(visual.type) \(field.property)=\(first): \(reason)") }
                interaction.setUserFilter(nil, for: key)
            }
        }
    }

    private func firstCategories(_ view: DataView) -> [String] {
        guard case .categorical(let c) = view else { return [] }
        return c.categories.map { $0.values.map { $0.asText() }.joined(separator: " ") }
    }

    /// Advanced và Top N chạy trên engine thật: lọc cột Dim_Client[age_group_current] của matrix Q1.6 (hàng nhóm tuổi).
    @Test @MainActor func advancedVaTopNTrenEngineThat() async throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.report.pages.first { $0.id == "d1_giaodich" })
        let age = QueryColumn(table: "Dim_Client", column: "age_group_current")
        let visual = try #require(page.visuals.first { $0.type == "pivotTable" && $0.fields.contains { $0.property == "age_group_current" } })
        let key = UserFilterKey(level: .visual, scope: visual.id, filterID: "added-Dim_Client.age_group_current")
        func rows() async throws -> [String] {
            let data = try await interaction.load(page: page, visual: visual, state: interaction.state(for: page))
            guard case .matrix(let m) = data.view else { Issue.record("không phải matrix"); return [] }
            return m.rows.filter { !$0.isGrandTotal && $0.level == 0 }.compactMap { $0.path.last?.asText() }.sorted()
        }
        func set(_ rule: FilterRule) { interaction.setUserFilter(UserFilter(column: age, rule: rule), for: key) }
        let all = try await rows()
        #expect(all == ["25-34", "35-49", "50-64", "65+", "<25"])
        set(.advanced(first: .init(kind: .contains, operand: "-"), second: nil, useOr: false, numeric: false))
        #expect(try await rows() == ["25-34", "35-49", "50-64"])
        set(.advanced(first: .init(kind: .isEqual, operand: "65+"), second: .init(kind: .isEqual, operand: "<25"), useOr: true, numeric: false))
        #expect(try await rows() == ["65+", "<25"])
        set(.advanced(first: .init(kind: .startsWith, operand: "<"), second: .init(kind: .doesNotContain, operand: "x"), useOr: false, numeric: false))
        #expect(try await rows() == ["<25"])
        let rule = TopNRule(count: 2, top: true, measureTable: "Fact_Transaction", measureName: "Trans Count")
        set(.topN(rule))
        let high = try await rows()
        #expect(high.count == 2)
        var bottom = rule; bottom.top = false
        set(.topN(bottom))
        let low = try await rows()
        #expect(low.count == 2)
        #expect(Set(low).isDisjoint(with: high), "Top 2 và Bottom 2 trong 5 nhóm tuổi không trùng nhau")
    }

    /// Bookmark không `suppressData` (dựng tay theo schema PBIR) khôi phục bộ lọc báo cáo và lựa chọn slicer.
    @Test @MainActor func bookmarkKhoiPhucBoLocVaSlicer() throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.report.pages.first { $0.id == "d1_giaodich" })
        let slicer = try #require(page.visuals.first { $0.type == "slicer" && $0.fields.contains { $0.property == "trans_type" } })
        let yearFilter = try #require(workspace.reportFilters.first { $0.field?.property == "year" })
        let json = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"name":"B1","displayName":"Có dữ liệu","options":{"suppressData":false},
         "explorationState":{"activeSection":"d1_giaodich",
           "filters":{"byExpr":[{"name":"\(yearFilter.id)","type":"Categorical",
              "expression":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"year"}},
              "filter":{"Where":[{"Condition":{"In":{"Values":[[{"Literal":{"Value":"2016L"}}]]}}}]}}]},
           "sections":{"d1_giaodich":{"filters":{"byExpr":[]},"visualContainers":{
              "\(slicer.id)":{"filters":{"byExpr":[]},"singleVisual":{"visualType":"slicer","objects":{"general":[{"properties":{"filter":{"filter":
                {"Where":[{"Condition":{"In":{"Values":[[{"Literal":{"Value":"'Credit'"}}]]}}}]}}}}]}}}}}}}}
        """.utf8))
        let bookmark = ReportBookmark.parse(json, fallbackName: "B1", group: nil)
        #expect(bookmark.data?.reportFilters.count == 1)
        interaction.apply(bookmark)
        let key = UserFilterKey(level: .report, scope: "", filterID: yearFilter.id)
        #expect(interaction.userFilters[key]?.values == [.integer(2016)] && interaction.userFilters[key]?.exclude == false)
        let selected = interaction.state(for: page).slicers[slicer.id]?.selection.paths
        #expect(selected == [[.string("Credit")]])
        // Áp bookmark chỉ-hiển-thị (suppressData) không đụng bộ lọc.
        let before = interaction.userFilters
        interaction.apply(ReportBookmark(id: "B2", displayName: "Chỉ hiển thị", group: nil, suppressData: true))
        #expect(interaction.userFilters == before)
    }

    /// Cấu trúc bookmark lấy từ file thật của Power BI (VM C2 B1): lựa chọn slicer ở `objects.merge.general`,
    /// thẻ lọc không đổi chỉ có tên, loại và `expression` (không có `filter`).
    @Test func bookmarkThatCuaPowerBIGhiSlicerODuoiMerge() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"name":"a75f","displayName":"Bookmark 3","options":{"targetVisualNames":["c366"],"preserveNewVisualVisibility":true},
         "explorationState":{"version":"1.3","activeSection":"d1_giaodich",
          "filters":{"byExpr":[{"name":"fNoUnknownYear","type":"Advanced",
             "expression":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Property":"year"}},"howCreated":0}]},
          "sections":{"d1_giaodich":{"visualContainers":{
            "83b9":{"filters":{"byExpr":[]},"singleVisual":{"visualType":"slicer","objects":{"merge":{"general":[{"properties":{"filter":{"filter":
              {"Version":2,"From":[{"Name":"d","Entity":"Dim_Trans_Type","Type":0}],"Where":[{"Condition":{"In":{"Expressions":[{"Column":
               {"Expression":{"SourceRef":{"Source":"d"}},"Property":"trans_type"}}],"Values":[[{"Literal":{"Value":"'Credit'"}}]]}}}]}}}}]}}}},
            "f4c4":{"singleVisual":{"visualType":"slicer","objects":{"merge":{"general":[{"properties":{"filter":{"filter":
              {"Version":2,"From":[{"Name":"d","Entity":"Dim_Date","Type":0}],"Where":[{"Condition":{"In":{"Expressions":[{"Column":
               {"Expression":{"SourceRef":{"Source":"d"}},"Property":"year"}}],"Values":[[{"Literal":{"Value":"2016L"}}]]}}}]}}}}]}}}}}}}}}
        """.utf8))
        let bookmark = ReportBookmark.parse(json, fallbackName: "a75f", group: nil)
        #expect(bookmark.suppressData == false)
        #expect(Set(bookmark.data?.slicerFilters.keys ?? [:].keys) == ["83b9", "f4c4"])
        #expect(ReportInteraction.slicerPaths(try #require(bookmark.data?.slicerFilters["83b9"])) == [[.string("Credit")]])
        #expect(ReportInteraction.slicerPaths(try #require(bookmark.data?.slicerFilters["f4c4"])) == [[.integer(2016)]])
        // Thẻ không có `filter` không được coi là bộ lọc người dùng đặt.
        #expect(bookmark.data?.reportFilters.allSatisfy { UserFilter.from($0) == nil } ?? false)
    }

    /// File thật của VM C2 B1 (bookmark có Data, slicer trans_type = Credit và năm = 2016): áp lại phải khôi phục đúng hai slicer.
    @Test @MainActor func bookmarkThatTuFilePbixCuaVM() throws {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/C2_A/bookmark-data.pbix")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let workspace = try Workspace(data: Data(contentsOf: url))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.page(id: "d1_giaodich"))
        let bookmark = try #require(workspace.bookmarks.first { $0.id == "a75f6610730ae7536ee0" })
        #expect(bookmark.suppressData == false && bookmark.data != nil)
        _ = interaction.apply(bookmark)
        let slicers = interaction.state(for: page).slicers
        #expect(slicers["83b988953b0219bc8d85"]?.selection.paths == [[.string("Credit")]])
        #expect(slicers["f4c48650b7886e94cdb1"]?.selection.paths == [[.integer(2016)]])
        #expect(slicers["b3cf5dc619216596bec9"]?.selection.paths.isEmpty ?? true, "slicer không ghi lựa chọn = Tất cả")
    }

    /// Thêm bookmark: chụp bộ lọc, slicer, ẩn/hiện, trang; đổi tiếp rồi áp lại phải về đúng lúc chụp; tuỳ chọn Data/Display/Current page.
    @Test @MainActor func themBookmarkChupVaKhoiPhuc() throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.report.pages.first { $0.id == "d1_giaodich" })
        let slicer = try #require(page.visuals.first { $0.type == "slicer" && $0.fields.contains { $0.property == "trans_type" } })
        let other = try #require(page.visuals.first { !interaction.isHidden($0) && $0.type != "slicer" })
        let column = QueryColumn(table: "Dim_Trans_Type", column: "trans_type")
        let key = UserFilterKey(level: .report, scope: "", filterID: "added-Dim_Trans_Type.trans_type")
        interaction.addFilter(column: column, level: .report, scope: "")
        interaction.setUserFilter(UserFilter(column: column, values: [.string("Credit")], exclude: false), for: key)
        interaction.setSlicer(page: page, visualID: slicer.id, columns: [column], selection: SlicerSelection([[.string("Credit")]]))
        let id = interaction.addBookmark(currentPageID: page.id)
        #expect(interaction.bookmarkRows.contains { $0.id == id && $0.isUser })

        interaction.setUserFilter(nil, for: key)
        interaction.setSlicer(page: page, visualID: slicer.id, columns: [column], selection: SlicerSelection())
        interaction.toggleHidden(other)
        #expect(interaction.isHidden(other))
        #expect(interaction.applyAnyBookmark(id: id) == page.id)
        #expect(interaction.userFilters[key]?.values == [.string("Credit")])
        #expect(interaction.state(for: page).slicers[slicer.id]?.selection.paths == [[.string("Credit")]])
        #expect(!interaction.isHidden(other), "Display khôi phục ẩn/hiện lúc chụp")

        // Tắt Data: áp lại chỉ đổi hiển thị, không đụng bộ lọc.
        interaction.setBookmarkOption(id: id, data: false)
        interaction.setUserFilter(nil, for: key)
        _ = interaction.applyAnyBookmark(id: id)
        #expect(interaction.userFilters[key] == nil)

        // Đổi tên, cập nhật, xoá; bookmark trong file cũng xoá và đổi tên được.
        interaction.renameBookmark(id: id, to: "  Của tôi ")
        #expect(interaction.bookmarkRows.first { $0.id == id }?.name == "Của tôi")
        interaction.deleteBookmark(id: id)
        #expect(!interaction.bookmarkRows.contains { $0.id == id })
        let fileID = try #require(workspace.bookmarks.first?.id)
        interaction.renameBookmark(id: fileID, to: "Tên mới")
        #expect(interaction.bookmarkRows.first { $0.id == fileID }?.name == "Tên mới")
        interaction.updateBookmark(id: fileID, currentPageID: page.id)
        #expect(interaction.bookmarkRows.first { $0.id == fileID }?.isUser == true, "cập nhật bookmark của file tạo bản người dùng thế chỗ")
        interaction.deleteBookmark(id: fileID)
        #expect(!interaction.bookmarkRows.contains { $0.id == fileID })
    }

    /// Thẻ measure của visual (bạn báo "Số GD", "Giá trị GD" không bấm được): lọc theo measure giữ các dòng thoả điều kiện.
    @Test @MainActor func boLocTheoMeasureCuaVisual() async throws {
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.report.pages.first { $0.id == "d1_giaodich" })
        let visual = try #require(page.visuals.first { $0.type == "lineChart" && $0.fields.contains { $0.property == "Trans Amount" } })
        let field = try #require(visual.fields.first { $0.property == "Trans Amount" && $0.kind == .measure })
        let key = UserFilterKey(level: .visual, scope: visual.id, filterID: "implicit-\(field.queryRef)-\(field.role)")
        func values() async throws -> (count: Int, text: String, ys: [Double]) {
            let data = try await interaction.load(page: page, visual: visual, state: interaction.state(for: page))
            guard case .categorical(let c) = data.view else { Issue.record("không phải biểu đồ"); return (0, data.query, []) }
            let ys = (0..<c.categories.count).flatMap { cat in (0..<max(1, c.series.count)).compactMap { s in
                NumberDisplay.numericValue(c.cell(measure: 0, series: s, category: cat).value) } }
            return (c.categories.count, data.query, ys)
        }
        let all = try await values()
        #expect(all.count > 20 && !all.text.contains("ValueFilterDM0"))
        let column = QueryColumn(table: field.entity, column: field.property)
        let rule = FilterRule.advanced(first: .init(kind: .greaterThan, operand: "100000000"), second: nil, useOr: false, numeric: true)
        interaction.setUserFilter(UserFilter(column: column, rule: rule, isMeasure: true), for: key)
        let filtered = try await values()
        #expect(filtered.text.contains("ValueFilterDM0"))
        #expect(filtered.count > 0 && filtered.count < all.count, "còn \(filtered.count) trên \(all.count) dòng")
        #expect(filtered.ys.allSatisfy { $0 > 100_000_000 })
        interaction.setUserFilter(nil, for: key)
        #expect(try await values().count == all.count)

        // Văn bản khớp truy vấn Power BI sinh cho "Giá trị GD nhỏ hơn 100000000" (VM C2, sau chuẩn hoá khoảng trắng).
        let less = FilterRule.advanced(first: .init(kind: .lessThan, operand: "100000000"), second: nil, useOr: false, numeric: true)
        interaction.setUserFilter(UserFilter(column: column, rule: less, isMeasure: true), for: key)
        let text = DAXQueryBuilder.normalized(try await values().text)
        let oracle = DAXQueryBuilder.normalized("""
        VAR __ValueFilterDM0 =
            FILTER(
                KEEPFILTERS(
                    SUMMARIZECOLUMNS(
                        'Dim_Date'[month_start],
                        __DS0FilterTable,
                        __DS0FilterTable2,
                        "Trans_Amount", 'Fact_Transaction'[Trans Amount],
                        "Trans_Count2", IGNORE('Fact_Transaction'[Trans Count])
                    )
                ),
                [Trans_Amount] < 100000000
            )
        VAR __DS0Core =
            SUMMARIZECOLUMNS(
                'Dim_Date'[month_start],
                __DS0FilterTable,
                __DS0FilterTable2,
                __ValueFilterDM0,
                "Trans_Amount", 'Fact_Transaction'[Trans Amount],
                "Trans_Count2", IGNORE('Fact_Transaction'[Trans Count])
            )
        """)
        #expect(text.contains(oracle), "\(text)")
    }

    /// Matrix Q1.6 mở nút nhiều cấp (Vùng › Bang › Chi nhánh): văn bản khớp truy vấn Power BI (VM C2 b5-1, b5-2) và cột trả về đúng.
    @Test @MainActor func matrixMoNutNhieuCap() async throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/C2_A")
        guard let one = try? String(contentsOf: dir.appendingPathComponent("b5-1.dax"), encoding: .utf8),
              let two = try? String(contentsOf: dir.appendingPathComponent("b5-2.dax"), encoding: .utf8) else { return }
        let workspace = try Workspace(data: Data(contentsOf: nhom6))
        let interaction = ReportInteraction(workspace: workspace)
        let page = try #require(workspace.report.pages.first { $0.id == "d1_giaodich" })
        let visual = try #require(page.visuals.first { $0.type == "pivotTable" && $0.fields.contains { $0.property == "age_group_current" } && $0.fields.contains { $0.entity == "Dim_Account" } })
        func load() async throws -> LiveVisualData { try await interaction.load(page: page, visual: visual, state: interaction.state(for: page)) }
        let (reader, _) = (VisualQuerySpecReader(metadata: try #require(workspace.metadata)), 0)
        let spec = try reader.spec(for: visual, filters: [])
        guard case .matrix(let m0) = try await load().view else { Issue.record("không phải matrix"); return }
        interaction.expandMatrix(visual: visual, spec: spec, path: [.string("Midwest")])
        let first = try await load()
        #expect(DAXQueryBuilder.normalized(first.query) == DAXQueryBuilder.normalized(one), "\(DAXQueryBuilder.normalized(first.query))")
        guard case .matrix(let m1) = first.view else { Issue.record("không phải matrix"); return }
        #expect(m1.columns.contains { $0.path == [.string("Midwest"), .string("Iowa")] && $0.hasChildren && !$0.isExpanded })
        #expect(m1.columns.contains { $0.path == [.string("Midwest")] && $0.isExpanded }, "cột tổng của nút đang mở")

        interaction.expandMatrix(visual: visual, spec: spec, path: [.string("Midwest"), .string("Iowa")])
        let second = try await load()
        #expect(DAXQueryBuilder.normalized(second.query) == DAXQueryBuilder.normalized(two), "\(DAXQueryBuilder.normalized(second.query))")
        guard case .matrix(let m2) = second.view else { Issue.record("không phải matrix"); return }
        #expect(m2.columns.contains { $0.path == [.string("Midwest"), .string("Iowa"), .string("Des Moines")] })
        #expect(m2.columns.contains { $0.path == [.string("Midwest"), .string("Iowa")] && $0.isExpanded })
        #expect(m2.columnLevels.count == 3)
        // Xuất ảnh để xem tiêu đề nhiều tầng (build/c-out/visuals/matrixExpand3.png).
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/c-out/visuals")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, data) in [("matrixExpand1", m0), ("matrixExpand2", m1), ("matrixExpand3", m2)] {
            let view = MatrixVisualView(data: data, context: VisualRenderContext(format: VisualFormat(objects: visual.objects)), scrollable: false)
            let renderer = ImageRenderer(content: view.frame(width: 2300, height: 330, alignment: .topLeading).background(Color.white))
            renderer.scale = 1.5
            if let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try png.write(to: out.appendingPathComponent(name + ".png"))
            }
        }

        // Bấm − ở Midwest đóng cả Midwest lẫn Iowa.
        interaction.expandMatrix(visual: visual, spec: spec, path: [.string("Midwest")])
        #expect((interaction.matrixExpansion[visual.id] ?? []).isEmpty)
    }
}
