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
}
