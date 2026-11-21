import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Wave 4 (v1.2) — Cut/Copy/Paste, Format Painter, Quick Measures, Mark as Date Table, RLS View As & DAX Update Model")
@MainActor
struct V12FeaturesTests {
    private func makeBlankState(root: URL) throws -> (state: DocumentState, docURL: URL) {
        let doc = try UntitledDocuments.create(root: root)
        let ws = try Workspace(data: try Data(contentsOf: doc))
        let state = DocumentState(workspace: ws, fileName: "v12-test.pbix", fileURL: doc)
        return (state, doc)
    }

    @Test("Cut/Copy/Paste visual sang trang khác và Format Painter hỗ trợ hoàn tác ⌘Z")
    func clipboardCrossPageAndFormatPainter() throws {
        let savedLast = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedLast { UserDefaults.standard.set(savedLast, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("v12-clip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let (state, _) = try makeBlankState(root: root)
        state.mode = .report
        state.editMode = true
        let page1 = try #require(state.pageID)
        let v1 = try #require(state.layout.insertVisual(type: "card", visibleRect: CGRect(x: 20, y: 20, width: 200, height: 120)))
        let v2 = try #require(state.layout.insertVisual(type: "card", visibleRect: CGRect(x: 260, y: 20, width: 200, height: 120)))

        // Đặt tiêu đề trên v1 rồi dùng Format Painter chép sang v2
        #expect(state.layout.setFormat(.bool(true), scope: .container, object: "title", property: "show", visual: v1) == nil)
        #expect(state.layout.setFormat(.text("Painted Title"), scope: .container, object: "title", property: "text", visual: v1) == nil)
        state.layout.select(v1)
        state.layout.beginFormatPainter()
        #expect(state.layout.isFormatPainterActive)
        #expect(state.layout.applyFormatPainter(to: v2))
        #expect(!state.layout.isFormatPainterActive)
        #expect(state.layout.visual(v2, page: page1)?.containerObjects.string("title", "text") == "Painted Title")

        // Undo 1 bước -> v2 mất tiêu đề đã sao
        state.layout.undo()
        #expect(state.layout.visual(v2, page: page1)?.containerObjects.string("title", "text") != "Painted Title")

        // Copy v1 -> tạo trang 2 -> Paste sang trang 2
        state.layout.select(v1)
        state.layout.copy()
        #expect(state.layout.hasClipboard)
        let page2 = try #require(state.layout.addPage())
        state.layout.showPage(page2)
        state.pageID = page2
        let pasted = state.layout.paste()
        #expect(pasted.count == 1)
        #expect(pasted[0] != v1)
        #expect(state.layout.visuals(of: page2).count == 1)

        // Cut trên trang 2 -> visual biến mất, Undo đưa lại
        state.layout.select(pasted[0])
        state.layout.cut()
        #expect(state.layout.visuals(of: page2).isEmpty)
        state.layout.undo()
        #expect(state.layout.visuals(of: page2).count == 1)
    }

    @Test("Quick Measures sinh đủ 8 mẫu DAX, Mark as Date Table kiểm tra duy nhất/trống, RLS View As lọc chính xác DAX & DAX Update Model")
    func quickMeasuresDateTableRLSAndDAXSync() async throws {
        let savedLast = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedLast { UserDefaults.standard.set(savedLast, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("v12-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let (state, _) = try makeBlankState(root: root)
        state.mode = .table

        var sales = EnterDataTable(name: "Sales")
        _ = try sales.paste("OrderDate\tRegion\tAmount\n2024-01-01\tNorth\t100\n2024-01-02\tSouth\t250\n2024-01-03\tNorth\t150")
        #expect(await state.loadEnterData(sales) == nil)
        // Đảm bảo OrderDate là kiểu dateTime để kiểm Mark as Date Table
        var dupDates = EnterDataTable(name: "BadDates")
        _ = try dupDates.paste("Dt\n2024-01-01\n2024-01-01")
        #expect(await state.loadEnterData(dupDates) == nil)

        // 1. Mark as Date Table: Sales[OrderDate] hợp lệ (3 ngày duy nhất), BadDates[Dt] bị từ chối (ngày trùng)!
        #expect(state.markAsDateTable(table: "BadDates", enabled: true, dateColumn: "Dt") != nil)
        #expect(state.markAsDateTable(table: "Sales", enabled: true, dateColumn: "OrderDate") == nil)
        #expect(state.workspace.metadata?.tables.first { $0.name == "Sales" }?.dataCategory == "Time")
        #expect(state.workspace.metadata?.columns.first { $0.tableName == "Sales" && $0.name == "OrderDate" }?.isKey == true)

        // 2. Quick Measures: kiểm cả 8 mẫu sinh DAX không rỗng
        for tpl in QuickMeasureTemplate.allCases {
            let gen = tpl.generate(baseMeasure: "TotalAmt", secondaryRef: "Base2",
                                   dateTable: "Sales", dateColumn: "OrderDate",
                                   categoryTable: "Sales", categoryColumn: "Region",
                                   filterValue: "North", rollingDays: 7)
            #expect(!gen.suggestedName.isEmpty)
            #expect(!gen.expression.isEmpty)
        }

        // 3. DAX Update Model (`DEFINE MEASURE ...`) tạo mới + cập nhật measure trong 1 bước ⌘Z
        let daxScript = """
        DEFINE
            MEASURE Sales[TotalAmt] = SUM(Sales[Amount])
            MEASURE Sales[NorthOnlyAmt] = CALCULATE([TotalAmt], Sales[Region] = "North")
        EVALUATE
            ROW("T", [TotalAmt])
        """
        let meta0 = try #require(state.workspace.metadata)
        let extracted = DAXModelSync.extractMeasures(from: daxScript, existingModel: meta0)
        #expect(extracted.count == 2)
        #expect(extracted.allSatisfy { $0.kind == .create })
        #expect(await state.applyDAXDefinedMeasures(extracted) == nil)
        #expect(state.workspace.measure(table: "Sales", name: "TotalAmt") != nil)
        #expect(state.workspace.measure(table: "Sales", name: "NorthOnlyAmt") != nil)

        // 4. RLS Manage Roles + View As lọc trực tiếp kết quả visual Card qua ReportInteraction!
        let northRole = ModelMetadata.RoleDefinition(
            name: "NorthManager",
            description: "Chỉ miền Bắc",
            modelPermission: 2,
            tablePermissions: [ModelMetadata.TablePermission(tableName: "Sales", filterExpression: #"Sales[Region] = "North""#)]
        )
        #expect(state.saveRLSRoles([(previous: nil, role: northRole)]) == nil)
        #expect(state.workspace.metadata?.roleDefinitions.count == 1)

        state.mode = .report
        state.editMode = true
        _ = try #require(state.pageID)
        let cardID = try #require(state.layout.insertVisual(type: "card", visibleRect: nil))
        #expect(state.layout.addField(FieldRef(kind: .measure, entity: "Sales", property: "TotalAmt"), to: "Values", visual: cardID) == nil)
        let page = try #require(state.page)
        let cardVisual = try #require(page.visuals.first { $0.id == cardID })

        // Không bật View As: tổng toàn bộ = 500
        let allLoaded = try await state.interaction.load(page: page, visual: cardVisual, state: FilterState())
        guard case .single(let sAll) = allLoaded.view else { Issue.record("Expected single"); return }
        #expect(try sAll.cell.value.asDouble() == 500)

        // Bật View As "NorthManager": tổng chỉ còn North (100 + 150 = 250)!
        state.setActiveRLSRoles(["NorthManager"])
        let rlsLoaded = try await state.interaction.load(page: page, visual: cardVisual, state: FilterState())
        guard case .single(let sRLS) = rlsLoaded.view else { Issue.record("Expected single"); return }
        #expect(try sRLS.cell.value.asDouble() == 250)

        // Dừng xem -> quay về 500!
        state.setActiveRLSRoles([])
        let stopLoaded = try await state.interaction.load(page: page, visual: cardVisual, state: FilterState())
        guard case .single(let sStop) = stopLoaded.view else { Issue.record("Expected single"); return }
        #expect(try sStop.cell.value.asDouble() == 500)

        // 5. Unhide All: ẩn cột & bảng rồi gọi unhideAllModelItems -> bỏ ẩn hết!
        #expect(state.setTableHidden("BadDates", hidden: true) == nil)
        #expect(state.updateColumn(table: "Sales", name: "Region", patch: ColumnPatch(isHidden: true)) == nil)
        #expect(state.unhideAllModelItems() == nil)
        #expect(state.workspace.metadata?.tables.first { $0.name == "BadDates" }?.isHidden == false)
        #expect(state.workspace.metadata?.columns.first { $0.tableName == "Sales" && $0.name == "Region" }?.isHidden == false)
    }
}
