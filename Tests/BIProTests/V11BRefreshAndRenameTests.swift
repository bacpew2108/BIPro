import ColumnStore
import Connectors
import DAXEngine
import Foundation
import MEngine
import PBIXKit
import Testing
@testable import BIPro

@Suite("Wave 3C (v1.1b) — One-Click Refresh & Cascade Rename")
@MainActor
struct V11BRefreshAndRenameTests {
    private func makeBlankState(root: URL) throws -> (state: DocumentState, docURL: URL) {
        let doc = try UntitledDocuments.create(root: root)
        let ws = try Workspace(data: try Data(contentsOf: doc))
        let state = DocumentState(workspace: ws, fileName: "test.pbix", fileURL: doc)
        return (state, doc)
    }

    @Test("One-Click Refresh cập nhật dữ liệu CSV ngoài, giữ quan hệ/measure, lưu T3 & chịu lỗi khi mất file")
    func oneClickRefreshPreservesModelAndHandlesMissingSource() async throws {
        let savedLast = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedLast { UserDefaults.standard.set(savedLast, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("v11b-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let csvURL = root.appendingPathComponent("Sales.csv")
        try "Product,Amount\nA,100\nB,200\n".write(to: csvURL, atomically: true, encoding: .utf8)

        let (state, docURL) = try makeBlankState(root: root)
        state.mode = .table

        // 1. Nạp bảng Sales từ CSV thật (M source: Csv.Document(File.Contents(...)))
        let mSource = """
        let
            Source = Csv.Document(File.Contents("\(csvURL.path)"),[Delimiter=",", Columns=2, Encoding=65001, QuoteStyle=QuoteStyle.None]),
            #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
            #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"Product", type text}, {"Amount", Int64.Type}})
        in
            #"Changed Type"
        """
        let initialVal = try await MEvaluator(environment: MEnvironment(bindings: SourceFunctions.bindings)).evaluate(source: mSource)
        guard case .table(let initialTable) = initialVal else { Issue.record("CSV load failed"); return }
        let loadedSales = LoadedTable(name: "Sales", queryName: "Sales", data: initialTable, status: .new, queryText: mSource)
        #expect(state.modelEditor.apply(TableLoader.edits(for: [loadedSales])) == nil)

        // 2. Nạp thêm bảng Products (Enter Data) + quan hệ Sales[Product] -> Products[Product] + measure TotalAmt
        var products = EnterDataTable(name: "Products")
        _ = try products.paste("Product\tCategory\nA\tHardware\nB\tSoftware\nC\tCloud")
        #expect(await state.loadEnterData(products) == nil)
        let rel = NewRelationship(fromTable: "Sales", fromColumn: "Product", toTable: "Products", toColumn: "Product")
        #expect(state.modelEditor.apply(.addRelationship(rel)) == nil)
        state.newMeasureInTableView(table: "Sales")
        state.measureDraft?.text = "TotalAmt = SUM(Sales[Amount])"
        await state.applyMeasureDraft()

        // Kiểm tổng ban đầu = 300
        let v0 = try await state.workspace.daxEngine().evaluate(measure: "TotalAmt", table: nil, filters: [])
        #expect(try v0.asDouble() == 300)

        // 3. Sửa file CSV trên đĩa (A=150, B=200, C=300 → tổng 650) rồi bấm One-Click Refresh!
        try "Product,Amount\nA,150\nB,200\nC,300\n".write(to: csvURL, atomically: true, encoding: .utf8)
        let summary1 = await state.performRefreshAll()
        #expect(summary1.applyError == nil)
        #expect(summary1.succeeded == 1)
        #expect(summary1.skipped >= 1) // Products là Enter Data
        #expect(summary1.failed == 0)
        #expect(summary1.changedTables == ["Sales"])

        // Quan hệ & measure được giữ nguyên, giá trị cập nhật ngay thành 650!
        #expect(state.workspace.metadata?.relationships.contains(where: { $0.fromTable == "Sales" && $0.toTable == "Products" }) == true)
        let v1 = try await state.workspace.daxEngine().evaluate(measure: "TotalAmt", table: nil, filters: [])
        #expect(try v1.asDouble() == 650)

        // Lưu T3 ra đĩa và mở lại → vẫn đúng 650!
        let savedURL = root.appendingPathComponent("refreshed.pbix")
        let stamp = try FileStamp.of(docURL)
        _ = try DocumentSaver.save(editor: state.layout, source: docURL, to: savedURL, expectedStamp: stamp)
        let reopened = try Workspace(data: try Data(contentsOf: savedURL))
        let vReopen = try await reopened.daxEngine().evaluate(measure: "TotalAmt", table: nil, filters: [])
        #expect(try vReopen.asDouble() == 650)

        // 4. Xoá file CSV nguồn → Refresh báo lỗi cho Sales nhưng GIỮ NGUYÊN dữ liệu 650!
        try FileManager.default.removeItem(at: csvURL)
        let summary2 = await state.performRefreshAll()
        #expect(summary2.failed == 1)
        let vAfterFail = try await state.workspace.daxEngine().evaluate(measure: "TotalAmt", table: nil, filters: [])
        #expect(try vAfterFail.asDouble() == 650)
    }

    @Test("DAXEngine.rewriteReferences không bao giờ đụng chuỗi literal, tên hàm hay tiền tố gần giống")
    func daxTokenRewriterSafety() {
        let expr = #"IF(Sales[Amount] > 0, "Sales[Amount]" & Sales2[Amount], SUM(Sales[Amount]) + [TotalAmt])"#
        let rTable = DAXEngine.rewriteReferences(in: expr, target: .table(old: "Sales", new: "Fact Sales"))
        #expect(rTable.contains("'Fact Sales'[Amount] > 0"))
        #expect(rTable.contains(#""Sales[Amount]""#)) // literal giữ nguyên!
        #expect(rTable.contains("Sales2[Amount]")) // bảng khác giữ nguyên!
        #expect(rTable.contains("SUM('Fact Sales'[Amount])"))

        let rCol = DAXEngine.rewriteReferences(in: expr, target: .column(table: "Sales", old: "Amount", new: "Revenue"))
        #expect(rCol.contains("Sales[Revenue] > 0"))
        #expect(rCol.contains(#""Sales[Amount]""#))
        #expect(rCol.contains("Sales2[Amount]"))

        let rMeasure = DAXEngine.rewriteReferences(in: expr, target: .measure(table: "Sales", old: "TotalAmt", new: "Net Sales"))
        #expect(rMeasure.contains("+ [Net Sales])"))
        #expect(rMeasure.contains(#""Sales[Amount]""#))
    }

    @Test("Cascade Rename đổi tên measure, cột, bảng đang được dùng trong DAX & PBIR và hoàn tác 1 bước ⌘Z")
    func cascadeRenameEndToEndAndUndo() async throws {
        let savedLast = UserDefaults.standard.string(forKey: "lastWorkspace")
        defer {
            if let savedLast { UserDefaults.standard.set(savedLast, forKey: "lastWorkspace") }
            else { UserDefaults.standard.removeObject(forKey: "lastWorkspace") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("v11b-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let (state, _) = try makeBlankState(root: root)
        state.mode = .table
        var sales = EnterDataTable(name: "Sales")
        _ = try sales.paste("Region\tAmount\nNorth\t100\nSouth\t250")
        #expect(await state.loadEnterData(sales) == nil)

        state.newMeasureInTableView(table: "Sales")
        state.measureDraft?.text = "TotalAmt = SUM(Sales[Amount])"
        await state.applyMeasureDraft()

        state.newMeasureInTableView(table: "Sales")
        state.measureDraft?.text = "DoubleAmt = [TotalAmt] * 2"
        await state.applyMeasureDraft()

        // Chèn visual trên trang báo cáo dùng cả cột Sales[Region] và measure Sales[TotalAmt]
        state.mode = .report
        state.editMode = true
        let pageID = try #require(state.pageID)
        let visualID = try #require(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: nil))
        let colRef = FieldRef(kind: .column, entity: "Sales", property: "Region", family: .text)
        let mRef = FieldRef(kind: .measure, entity: "Sales", property: "TotalAmt")
        #expect(state.layout.addField(colRef, to: "Category", visual: visualID) == nil)
        #expect(state.layout.addField(mRef, to: "Y", visual: visualID) == nil)

        // 1. Cascade Rename measure TotalAmt -> GrossAmt
        let model1 = try #require(state.workspace.metadata)
        let mPlan = CascadeRenamePlanner.buildPlan(target: .measure(table: "Sales", old: "TotalAmt", new: "GrossAmt"),
                                                   model: model1, layout: state.layout, workspace: state.workspace)
        #expect(mPlan.validationError == nil)
        #expect(mPlan.affectedDAXItems.contains { $0.contains("DoubleAmt") })
        #expect(mPlan.visualUpdates.count == 1)
        #expect(state.executeCascadeRename(mPlan) == nil)

        #expect(state.workspace.measure(table: "Sales", name: "GrossAmt") != nil)
        #expect(state.workspace.measure(table: "Sales", name: "DoubleAmt")?.expression.contains("[GrossAmt]") == true)
        let vAfterM = try #require(state.layout.visual(visualID, page: pageID))
        #expect(vAfterM.fields.contains { $0.property == "GrossAmt" && $0.queryRef == "Sales.GrossAmt" })
        let valAfterM = try await state.workspace.daxEngine().evaluate(measure: "DoubleAmt", table: nil, filters: [])
        #expect(try valAfterM.asDouble() == 700)

        // 2. Cascade Rename column Sales[Amount] -> Sales[Revenue]
        let model2 = try #require(state.workspace.metadata)
        let cPlan = CascadeRenamePlanner.buildPlan(target: .column(table: "Sales", old: "Amount", new: "Revenue"),
                                                   model: model2, layout: state.layout, workspace: state.workspace)
        #expect(cPlan.validationError == nil)
        #expect(state.executeCascadeRename(cPlan) == nil)
        #expect(state.workspace.measure(table: "Sales", name: "GrossAmt")?.expression.contains("Sales[Revenue]") == true)

        // 3. Cascade Rename table Sales -> FactSales
        let model3 = try #require(state.workspace.metadata)
        let tPlan = CascadeRenamePlanner.buildPlan(target: .table(old: "Sales", new: "FactSales"),
                                                   model: model3, layout: state.layout, workspace: state.workspace)
        #expect(tPlan.validationError == nil)
        #expect(state.executeCascadeRename(tPlan) == nil)
        #expect(state.workspace.metadata?.userTables.contains { $0.name == "FactSales" } == true)
        #expect(state.workspace.measure(table: "FactSales", name: "GrossAmt")?.expression.contains("FactSales[Revenue]") == true)
        let vAfterT = try #require(state.layout.visual(visualID, page: pageID))
        #expect(vAfterT.fields.allSatisfy { $0.entity == "FactSales" })
        let valAfterT = try await state.workspace.daxEngine().evaluate(measure: "DoubleAmt", table: nil, filters: [])
        #expect(try valAfterT.asDouble() == 700)

        // 4. Undo 1 bước -> khôi phục lại tên bảng Sales cả trong model lẫn PBIR!
        state.layout.undo()
        #expect(state.workspace.metadata?.userTables.contains { $0.name == "Sales" } == true)
        let vAfterUndo = try #require(state.layout.visual(visualID, page: pageID))
        #expect(vAfterUndo.fields.allSatisfy { $0.entity == "Sales" })
    }
}
