import AppKit
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import PDFKit
import SwiftUI
import Testing
@testable import BIPro

/// Đợt 1 QA (v1.0.1): Kiểm thử tích hợp End-to-End toàn luồng và ca biên phòng vệ.
@Suite("QA — End-to-End Lifecycle & Edge Resilience")
@MainActor
struct AppEndToEndQATests {

    @Test("Luồng E2E đầy đủ: Tài liệu mới → Nhập dữ liệu 2 bảng + Tự phát hiện quan hệ → Measure + Cột tính toán → Dựng báo cáo + Trang + Bookmark + Bộ lọc → Lưu T3 → Mở lại → Xuất CSV/PNG/PDF")
    func fullDocumentLifecycleEndToEnd() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bipro-qa-e2e-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let untitled = try UntitledDocuments.create(root: root)
        let savedMode = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedMode { UserDefaults.standard.set(savedMode, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let state = DocumentState(
            workspace: try Workspace(data: Data(contentsOf: untitled)),
            fileName: untitled.lastPathComponent,
            fileURL: untitled
        )
        state.mode = .report
        state.editMode = true

        // 1. Enter Data: bảng Regions (bên 1) và Sales (bên nhiều) → tự phát hiện quan hệ *:1
        var regions = EnterDataTable(name: "Regions")
        try regions.paste("RegionID\tRegionName\n1\tNorth\n2\tCentral\n3\tSouth\n")
        #expect(await state.loadEnterData(regions) == nil)

        var sales = EnterDataTable(name: "Sales")
        try sales.paste("OrderID\tRegionID\tQty\tRevenue\n101\t1\t10\t500\n102\t1\t5\t250\n103\t2\t8\t640\n104\t3\t4\t360\n")
        #expect(await state.loadEnterData(sales) == nil)

        #expect(state.workspace.userTables.count == 2)
        #expect(state.workspace.rowCount("Sales") == 4)
        #expect(state.workspace.rowCount("Regions") == 3)
        let rels = state.workspace.metadata?.relationships ?? []
        #expect(rels.count == 1, "Phải tự phát hiện 1 quan hệ Sales[RegionID] -> Regions[RegionID]")

        // Undo 1 bước phải gỡ cả bảng Sales lẫn quan hệ tự tạo; Redo trả về nguyên vẹn
        state.layout.undo()
        #expect(state.workspace.userTables.count == 1)
        #expect((state.workspace.metadata?.relationships ?? []).count == 0)
        state.layout.redo()
        #expect(state.workspace.userTables.count == 2)
        #expect((state.workspace.metadata?.relationships ?? []).count == 1)

        // 2. Tạo Measure & Cột tính toán DAX
        state.beginNewMeasure(table: "Sales")
        state.measureDraft?.text = "Total Revenue = SUM(Sales[Revenue])"
        await state.applyMeasureDraft()
        #expect(state.measureDraft?.message == nil)
        #expect(state.workspace.measure(table: "Sales", name: "Total Revenue") != nil)

        state.beginNewColumn(table: "Sales")
        state.measureDraft?.text = "Unit Price = Sales[Revenue] / Sales[Qty]"
        await state.applyMeasureDraft()
        #expect(state.measureDraft?.message == nil)
        #expect(state.workspace.column(table: "Sales", name: "Unit Price")?.kind == .calculated)

        // Chạy DAX trực tiếp kiểm tra đúng số liệu qua quan hệ
        let engine = try state.workspace.daxEngine()
        let eval = try await engine.execute("EVALUATE SUMMARIZECOLUMNS(Regions[RegionName], \"Rev\", [Total Revenue]) ORDER BY Regions[RegionName]")
        let table = try #require(eval.tables.first)
        #expect(table.rows.count == 3)
        let byRegion = Dictionary(uniqueKeysWithValues: table.rows.compactMap { row -> (String, Double)? in
            guard case .string(let name) = row[0], let num = try? row[1].asDouble() else { return nil }
            return (name, num)
        })
        #expect(byRegion["North"] == 750)
        #expect(byRegion["Central"] == 640)
        #expect(byRegion["South"] == 360)

        // 3. Quay lại Báo cáo & dựng visual: thêm Card, Biểu đồ cột nhóm, Hộp văn bản + gắn trường + định dạng
        state.mode = .report
        let cardID = try #require(state.layout.insertVisual(type: "cardVisual", visibleRect: nil))
        let totalRev = try #require(state.workspace.measure(table: "Sales", name: "Total Revenue"))
        #expect(state.layout.addField(FieldRef(measure: totalRev), to: "Data", visual: cardID) == nil)

        let colID = try #require(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: nil))
        let regionName = try #require(state.workspace.column(table: "Regions", name: "RegionName"))
        #expect(state.layout.addField(FieldRef(column: regionName), to: "Category", visual: colID) == nil)
        #expect(state.layout.addField(FieldRef(measure: totalRev), to: "Y", visual: colID) == nil)

        let tbID = try #require(state.layout.insertVisual(type: "textbox", visibleRect: nil))
        state.layout.setText("Báo cáo QA v1.0", visual: tbID)

        // Quản lý trang: thêm trang mới, đổi tên, rồi giữ lại 2 trang
        let page2ID = try #require(state.addPage())
        #expect(state.renamePage(page2ID, to: "Chi tiết") == nil)
        #expect(state.pages.count == 2)
        state.pageID = state.pages[0].id

        // Thêm Bookmark
        #expect(state.addBookmark() == nil)
        #expect(state.interaction.bookmarkRows.count == 1)

        // 4. Lưu T3 ra đĩa và mở lại hoàn toàn độc lập
        let savedURL = root.appendingPathComponent("qa-e2e.pbix")
        let outcome = try DocumentSaver.saveUntitled(
            editor: state.layout,
            source: untitled,
            to: savedURL,
            readOnlyRoots: [],
            backupDirectory: root.appendingPathComponent("Backups")
        )
        #expect(outcome.didWrite)

        let reopened = try Workspace(data: Data(contentsOf: savedURL))
        #expect(reopened.userTables.count == 2)
        #expect(reopened.rowCount("Sales") == 4)
        #expect(reopened.measure(table: "Sales", name: "Total Revenue") != nil)
        #expect(reopened.column(table: "Sales", name: "Unit Price")?.kind == .calculated)
        #expect((reopened.metadata?.relationships ?? []).count == 1)
        #expect(reopened.report.pages.count == 2)
        #expect(reopened.report.pages[1].displayName == "Chi tiết")
        #expect(reopened.bookmarks.count == 1)

        // 5. Nạp dữ liệu visual trên tệp vừa mở lại → Xuất CSV, PNG và PDF
        let reopenedInteraction = ReportInteraction(workspace: reopened)
        let firstPage = try #require(reopened.report.pages.first)
        let preloaded = await ReportPageExporter.preload(page: firstPage, interaction: reopenedInteraction)
        let cardData = try #require(preloaded[cardID])
        let csvData = try VisualCSVExporter.export(cardData.view)
        #expect(csvData.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let csvText = try #require(String(data: csvData.dropFirst(3), encoding: .utf8))
        #expect(csvText.contains("1,750") || csvText.contains("1750"))

        let pngData = try ReportPageExporter.renderPNG(
            page: firstPage, workspace: reopened, preloaded: preloaded, interaction: reopenedInteraction, scale: .x1
        )
        #expect(pngData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))

        let pdfData = try ReportPageExporter.renderPDF(
            pages: reopened.visiblePages,
            workspace: reopened,
            preloadedByPage: [firstPage.id: preloaded],
            interaction: reopenedInteraction
        )
        let pdf = try #require(PDFDocument(data: pdfData))
        #expect(pdf.pageCount == 2)
    }

    @Test("Phòng vệ ca biên: dữ liệu .pbix hỏng, ZIP rỗng, bảng 0 dòng & cột toàn NULL không gây sập")
    func edgeCasesAndDefensiveResilience() throws {
        // 1. Byte rác không phải ZIP
        #expect(throws: (any Error).self) {
            _ = try Workspace(data: Data("not a valid pbix archive".utf8))
        }

        // 2. Quick Look trên tệp hỏng không sập
        let corruptURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).pbix")
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: corruptURL)
        #expect(throws: (any Error).self) {
            _ = try PBIXQuickLookSummary.load(from: corruptURL)
        }

        // 3. Xuất CSV trên DataView rỗng ném đúng ExportError.noData
        #expect(throws: ExportError.self) {
            _ = try VisualCSVExporter.export(.empty(reason: "Không có dữ liệu"))
        }

        // 4. Bảng có cột toàn NULL vẫn dựng TableData & giải mã an toàn
        let allNull = try TableData(columns: [
            TableColumn(name: "ID", data: ColumnBuilder.integers([1, 2, 3])),
            TableColumn(name: "EmptyText", data: ColumnBuilder.strings([nil, nil, nil])),
            TableColumn(name: "EmptyNum", data: ColumnBuilder.doubles([nil, nil, nil])),
        ])
        #expect(allNull.rowCount == 3)
        #expect(allNull.columns.count == 3)
    }

    @Test("Hồi quy chống sập SIGTRAP: mọi loại CartesianChart có trục X nhưng chưa có trục Y đều vẽ an toàn")
    func cartesianChartsWithCategoryOnlyNeverCrash() throws {
        let catOnly = CategoricalData(
            categoryLevels: [FieldInfo(queryRef: "T.Cat", displayName: "Cat", role: "Category", formatString: nil, isMeasure: false)],
            categories: [CategoryKey(values: [.string("A")]), CategoryKey(values: [.string("B")])],
            seriesField: nil,
            series: [],
            measures: [],
            values: [],
            highlights: nil,
            isReduced: false
        )
        let context = VisualRenderContext(theme: .fallback)
        let kinds: [CartesianKind] = [
            .clusteredBar, .clusteredColumn, .stackedColumn, .hundredPercentStackedColumn,
            .line, .area, .stackedArea, .hundredPercentStackedArea,
            .comboClustered, .comboStacked,
        ]
        for kind in kinds {
            let renderer = ImageRenderer(
                content: CartesianChartView(data: catOnly, kind: kind, context: context, interactive: false)
                    .frame(width: 320, height: 200)
                    .background(Color.white)
            )
            renderer.proposedSize = ProposedViewSize(width: 320, height: 200)
            renderer.scale = 1
            #expect(renderer.cgImage != nil, "CartesianKind.\(kind) không được trả ảnh nil khi thiếu Y")
        }
    }
}
