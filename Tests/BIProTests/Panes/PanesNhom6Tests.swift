// Test nặng gói P trên file thật: BIPRO_HEAVY=1 và có ~/Downloads/Nhom6_Dashboard.pbix.
import DAXEngine
import Foundation
import PBIXKit
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
}
