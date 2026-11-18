// Đợt tồn đọng sau Phase F, US2 (T034): trường phân cấp ngày của Auto date/time (`HierarchyLevel` trên `PropertyVariationSource`) quy về
// cột của bảng ngày cục bộ qua `Variation`. Golden: `f11-desktop.pbix` (VM-F11b, ngoài git, thiếu thì bỏ qua) và văn bản Performance
// Analyzer `vm-f11/pa-year.dax`, `pa-quarter.dax` (biểu đồ cột Sum of Amount theo OrderDate ở cấp Year, rồi "Go to next level" Quarter).
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private struct F11Report: @unchecked Sendable {
    let metadata: ModelMetadata
    let visualJSON: String
}

private let f11: Result<F11Report, Error> = Result {
    let url = try #require(F2Fixtures.desktop("vm-f11", "f11-desktop.pbix"))
    let pbix = try PBIXFile(url: url)
    let (abf, _) = try pbix.loadDataModel()
    let json = try ZipArchive(url: url).read("Report/definition/pages/588de769552ed3d9c823/visuals/9d96e9ddb2ba23715440/visual.json")
    return F11Report(metadata: try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")),
                     visualJSON: String(decoding: json, as: UTF8.self))
}

/// Visual của f11 với cấp `level` đang hiện (file lưu lúc đang ở Month).
private func chart(activeLevel level: String) throws -> ReportVisual {
    var text = try f11.get().visualJSON.replacingOccurrences(of: "\"active\":true", with: "\"active\":false")
    let marker = "\"nativeQueryRef\":\"OrderDate \(level)\",\"active\":false"
    #expect(text.contains(marker))
    text = text.replacingOccurrences(of: marker, with: "\"nativeQueryRef\":\"OrderDate \(level)\",\"active\":true")
    let raw = try JSONValue.parse(text)
    var visual = ReportVisual(id: "9d96e9ddb2ba23715440", type: "clusteredColumnChart")
    visual.raw = raw
    return visual
}

private func golden(_ name: String) throws -> String {
    let url = F2Fixtures.root.appendingPathComponent("docs/phase-f2-evidence/vm-f11/\(name)")
    return try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "// DAX Query\n", with: "")
}

@Suite(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil))
struct VariationQueryGoldenTests {
    @Test(arguments: [("Year", "pa-year.dax"), ("Quarter", "pa-quarter.dax")])
    func vanBanGiongPerformanceAnalyzer(_ level: String, _ file: String) throws {
        let spec = try VisualQuerySpecReader(metadata: try f11.get().metadata).spec(for: try chart(activeLevel: level), filters: [])
        let ours = DAXQueryBuilder.normalized(DAXQueryBuilder.build(spec))
        let theirs = DAXQueryBuilder.normalized(try golden(file))
        #expect(ours == theirs, "\(level)\n--- Power BI\n\(theirs)\n--- BI Pro\n\(ours)")
    }

    @Test func capPhanCapQuyVeBangNgayCucBo() throws {
        let model = try f11.get().metadata
        let local = try #require(model.variations.first { $0.table == "Sales" && $0.column == "OrderDate" }).hierarchy.table
        let spec = try VisualQuerySpecReader(metadata: model).spec(for: try chart(activeLevel: "Year"), filters: [])
        #expect(spec.drillLevels.map(\.column) == ["Year", "Quarter", "Month", "Day"].map { QueryColumn(table: local, column: $0) })
        // Cột sắp xếp theo của bảng ngày (Month theo MonthNo) đi kèm như cột thường.
        #expect(spec.drillLevels.map(\.sortBy?.column) == [nil, "QuarterNo", "MonthNo", nil])
    }
}

/// Thêm phân cấp ngày vào ô: phần tử mới đúng từng byte dạng Desktop ghi (`visual-theo-nam.json`), và đọc lại quy về bảng ngày cục bộ.
@Suite(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil))
struct VariationFieldTests {
    @Test func phanTuMoiTrungByteDesktop() throws {
        let json = Data(try f11.get().visualJSON.utf8)
        let wells = try PBIRQueryPatch.wells(in: json)
        var rebuilt = wells
        let category = try #require(rebuilt.firstIndex { $0.role == "Category" })
        let active = "Month"   // file lưu lúc đang ở Month
        rebuilt[category].elements = AutoDateTime.hierarchyLevels.map {
            PBIRQueryPatch.newVariationLevel(entity: "Sales", column: "OrderDate", variation: "Variation", hierarchy: "Date Hierarchy",
                                             level: $0, role: "Category", active: $0 == active)
        }
        #expect(rebuilt[category].elements.map(\.field) == wells[category].elements.map(\.field))
        #expect(try PBIRQueryPatch.apply(rebuilt, to: json) == json)
    }

    @Test func tickCotNgayThemCaPhanCap() throws {
        let model = try f11.get().metadata
        let variation = try #require(model.variations.first { $0.table == "Sales" && $0.column == "OrderDate" })
        let ref = FieldRef(variation: variation, levels: AutoDateTime.hierarchyLevels)
        #expect(ref.queryRef == "Sales.OrderDate.Variation.Date Hierarchy")
        var visual = ReportVisual(id: "v", type: "clusteredColumnChart")
        visual.raw = try JSONValue.parse(#"{"visual":{"visualType":"clusteredColumnChart","query":{"queryState":{}}}}"#)
        guard case .changed(let wells) = FieldEditor.add(ref, to: "Category", wells: [], visual: visual) else {
            Issue.record("không thêm được phân cấp ngày"); return
        }
        let levels = try #require(wells.first { $0.role == "Category" }).elements.map(\.field)
        #expect(levels.map(\.queryRef) == AutoDateTime.hierarchyLevels.map { "Sales.OrderDate.Variation.Date Hierarchy.\($0)" })
        #expect(levels.map(\.nativeQueryRef) == AutoDateTime.hierarchyLevels.map { "OrderDate \($0)" })
        #expect(levels.map(\.active) == [true, false, false, false])
    }
}

/// Tài liệu mới: nạp bảng có cột ngày, tick cột ngày rồi cột số vào biểu đồ cột → nhóm theo Year của bảng ngày cục bộ; lưu rồi mở lại
/// vẫn đọc được phân cấp.
@MainActor
@Suite struct VariationFlowTests {
    @Test func bieuDoCotTheoNamCuaCotNgay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("variation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        // 45 292 = 1/1/2024, 45 700 = 13/2/2025.
        let data = try TableData(columns: [
            TableColumn(name: "OrderDate", data: ColumnBuilder.dateTimes([45_292, 45_400, 45_700])),
            TableColumn(name: "Amount", data: ColumnBuilder.integers([10, 20, 5])),
        ])
        #expect(state.loadFromGetData([LoadedTable(name: "Sales", data: data)]) == nil)
        let ref = try #require(state.workspace.dateHierarchy(table: "Sales", column: "OrderDate"))
        #expect(ref.levels == ["Year", "Quarter", "Month", "Day"])
        #expect(state.workspace.dateHierarchy(table: "Sales", column: "Amount") == nil)

        // Không đổi `state.mode`: chế độ được nhớ trong UserDefaults và ảnh hưởng test khác.
        let id = try #require(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: nil))
        state.visualID = id
        #expect(state.layout.addField(ref, to: "Category", visual: id) == nil)
        let amount = try #require(state.workspace.columns(of: "Sales").first { $0.name == "Amount" })
        #expect(state.layout.addField(FieldRef(column: amount), to: "Y", visual: id) == nil)

        let visual = try #require(state.visual)
        let page = try #require(state.page)
        let loaded = try await state.interaction.load(page: page, visual: visual, state: FilterState())
        let local = try #require(state.workspace.metadata?.variations.first).hierarchy.table
        #expect(loaded.spec.primary.map(\.column) == [QueryColumn(table: local, column: "Year")])
        guard case .categorical(let chart) = loaded.view else { Issue.record("không phải dữ liệu danh mục"); return }
        #expect(chart.categories.map(\.values) == [[Value.integer(2024)], [Value.integer(2025)]])

        let destination = root.appendingPathComponent("v.pbix")
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)
        let reopened = try Workspace(data: Data(contentsOf: destination))
        let saved = try #require(reopened.report.pages.flatMap(\.visuals).first { $0.id == id })
        let spec = try VisualQuerySpecReader(metadata: try #require(reopened.metadata)).spec(for: saved, filters: [])
        #expect(spec.primary.map(\.column) == [QueryColumn(table: local, column: "Year")])
        #expect(spec.drillLevels.count == 4)
    }
}

/// T038: tiêu đề tự động chỉ kể cấp phân cấp đang hiện (Desktop "Sum of Amount by Year", VM-F11b ảnh b6).
@Suite struct VariationTitleTests {
    @Test func tieuDeChiCoCapDangHien() {
        func level(_ name: String, active: Bool?) -> ReportField {
            ReportField(role: "Category", kind: .hierarchyLevel, entity: "Sales", property: name,
                        queryRef: "Sales.OrderDate.Variation.Date Hierarchy.\(name)", active: active)
        }
        let y = ReportField(role: "Y", kind: .aggregation, entity: "Sales", property: "Amount", function: "Tổng", queryRef: "Sum(Sales.Amount)")
        let levels = ["Year", "Quarter", "Month", "Day"]
        #expect(VisualContainerView.defaultTitle(levels.enumerated().map { level($1, active: $0 == 0) } + [y]) == "Tổng của Amount theo Year")
        #expect(VisualContainerView.defaultTitle(levels.enumerated().map { level($1, active: $0 == 2) } + [y]) == "Tổng của Amount theo Month")
        // Không có cờ active (file cũ, trường thường): kể hết như trước.
        #expect(VisualContainerView.defaultTitle(levels.prefix(2).map { level($0, active: nil) } + [y]) == "Tổng của Amount theo Year và Quarter")
    }
}

/// T038 (bấm thử app): tắt Auto date/time khi visual còn dùng phân cấp ngày làm visual ra một cột "Blank" mang tổng (sai mà không
/// báo). Desktop viết lại visual thành cột ngày thường (VM-F11b step4); BI Pro chưa làm nên chặn kèm lý do, bỏ phân cấp khỏi visual
/// thì tắt được.
@MainActor
@Suite struct VariationToggleGuardTests {
    @Test func chanTatAutoDateKhiVisualDungPhanCap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vartoggle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        let data = try TableData(columns: [
            TableColumn(name: "OrderDate", data: ColumnBuilder.dateTimes([45_292, 45_700])),
            TableColumn(name: "Amount", data: ColumnBuilder.integers([10, 5])),
        ])
        #expect(state.loadFromGetData([LoadedTable(name: "Sales", data: data)]) == nil)
        let ref = try #require(state.workspace.dateHierarchy(table: "Sales", column: "OrderDate"))
        let id = try #require(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: nil))
        state.visualID = id
        #expect(state.layout.addField(ref, to: "Category", visual: id) == nil)
        let depth = state.layout.undoDepth

        let refusal = try #require(state.applyFileOptions(FileOptions(autoDateTime: false, autodetectRelationships: true)))
        #expect(refusal.contains("phân cấp ngày") && refusal.contains("Page 1"))
        #expect(state.fileOptions.autoDateTime && state.layout.undoDepth == depth)

        // Bỏ visual thì tắt được.
        state.layout.undo()
        #expect(state.applyFileOptions(FileOptions(autoDateTime: false, autodetectRelationships: true)) == nil)
        #expect(!state.fileOptions.autoDateTime)
    }
}

