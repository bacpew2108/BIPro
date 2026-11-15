import CoreGraphics
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T034, T035): kéo thẻ bảng ở Model view, hoàn tác chung, lưu vào `DiagramLayout`.
@Suite @MainActor struct DiagramEditorUndoTests {
    typealias Env = FieldEditingTests.Env

    @Test func keoTheLaMotBuocHoanTacVaLamDirty() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(!env.editor.isDirty)
        var edits = env.editor.diagramEdits
        edits.move(table: "Dim_Client", in: "All tables", to: CGPoint(x: 100, y: 200), original: CGPoint(x: 10, y: 20))
        #expect(env.editor.commitDiagram(edits))
        #expect(env.editor.isDirty && env.editor.undoDepth == 1)
        #expect(env.editor.diagramEdits.positions["All tables"]?["Dim_Client"] == CGPoint(x: 100, y: 200))
        env.editor.undo()
        #expect(env.editor.diagramEdits.isEmpty && !env.editor.isDirty)
        env.editor.redo()
        #expect(env.editor.diagramEdits.positions["All tables"]?["Dim_Client"] == CGPoint(x: 100, y: 200))
    }

    @Test func keoLienTiepCungTheGopThanhMotBuoc() throws {
        let env = try Env(); defer { env.cleanUp() }
        var clock = Date(timeIntervalSince1970: 1_000)
        env.editor.now = { clock }
        for x in [10.0, 20, 30] {
            var edits = env.editor.diagramEdits
            edits.move(table: "T", in: "All tables", to: CGPoint(x: x, y: 0), original: .zero)
            env.editor.commitDiagram(edits, coalesceKey: "drag-T")
            clock += 0.1
        }
        #expect(env.editor.undoDepth == 1 && env.editor.diagramEdits.positions["All tables"]?["T"]?.x == 30)
    }

    @Test func thuPhongVeGocThiBoMucSua() {
        var edits = DiagramEdits()
        edits.setZoom(50, in: "D", original: 60)
        edits.setZoom(70, in: "D", original: 50)           // original thứ hai bị bỏ
        #expect(edits.zoom["D"] == 70 && edits.zoomBaseline["D"] == 60)
        edits.setZoom(60, in: "D", original: 70)
        #expect(edits.isEmpty && edits.zoomBaseline.isEmpty)
    }

    @Test func viTriGocLaViTriLucDauKhiKeoNhieuLan() {
        var edits = DiagramEdits()
        edits.move(table: "T", in: "D", to: CGPoint(x: 1, y: 1), original: CGPoint(x: 5, y: 5))
        edits.move(table: "T", in: "D", to: CGPoint(x: 2, y: 2), original: CGPoint(x: 1, y: 1))   // original thứ hai bị bỏ
        #expect(edits.baseline["D"]?["T"] == CGPoint(x: 5, y: 5) && edits.positions["D"]?["T"] == CGPoint(x: 2, y: 2))
        // kéo về đúng chỗ gốc: bỏ mục sửa
        edits.move(table: "T", in: "D", to: CGPoint(x: 5, y: 5), original: CGPoint(x: 2, y: 2))
        #expect(edits.isEmpty)
    }

    // MARK: Tab bố cục (VM-E6)

    @Test func themTabDungSoKeTiepVaHoanTacDuoc() throws {
        let env = try Env(); defer { env.cleanUp() }
        var edits = env.editor.diagramEdits
        #expect(edits.addTab(existing: ["All tables"]) == "Layout 1")
        #expect(edits.addTab(existing: ["All tables"]) == "Layout 2")
        #expect(edits.tabs == ["All tables", "Layout 1", "Layout 2"] && !edits.isEmpty)
        #expect(env.editor.commitDiagram(edits) && env.editor.isDirty)
        env.editor.undo()
        #expect(env.editor.diagramEdits.tabs == nil && env.editor.diagramEdits.isEmpty && !env.editor.isDirty)
    }

    @Test func tenTabMoiBoQuaTenDaCoKhongPhanBietHoaThuong() {
        var edits = DiagramEdits()
        #expect(edits.addTab(existing: ["All tables", "layout 1"]) == "Layout 2")
    }

    @Test func doiTenTabChuyenMucSuaSangTenMoi() throws {
        var edits = DiagramEdits()
        let existing = ["All tables", "A"]
        edits.move(table: "T", in: "A", to: CGPoint(x: 1, y: 1), original: CGPoint(x: 5, y: 5))
        edits.setZoom(70, in: "A", original: 100)
        #expect(edits.renameTab(from: "A", to: "B", existing: existing) == nil)
        #expect(edits.tabs == ["All tables", "B"])
        #expect(edits.positions["B"]?["T"] == CGPoint(x: 1, y: 1) && edits.positions["A"] == nil)
        #expect(edits.baseline["B"]?["T"] == CGPoint(x: 5, y: 5) && edits.zoom["B"] == 70 && edits.zoomBaseline["B"] == 100)
    }

    @Test func doiTenBiTuChoiKemLyDo() {
        var edits = DiagramEdits()
        let existing = ["All tables", "A", "B"]
        #expect(edits.renameTab(from: "All tables", to: "X", existing: existing) != nil)      // tab đầu cố định như Desktop
        #expect(edits.renameTab(from: "A", to: "  ", existing: existing) != nil)
        #expect(edits.renameTab(from: "A", to: "b", existing: existing) != nil)               // trùng tab khác
        #expect(edits.renameTab(from: "Z", to: "Q", existing: existing) != nil)
        #expect(edits.isEmpty)
        #expect(edits.renameTab(from: "A", to: "A", existing: existing) == nil && edits.isEmpty)   // cùng tên: không đổi gì
    }

    @Test func doiTenVeTenGocBoMucSua() {
        var edits = DiagramEdits()
        let existing = ["All tables", "A"]
        _ = edits.renameTab(from: "A", to: "B", existing: existing)
        _ = edits.renameTab(from: "B", to: "A", existing: existing)
        #expect(edits.tabs == nil && edits.isEmpty)
    }

    // MARK: Xoá tab, gỡ bảng khỏi tab (VM-E7)

    @Test func xoaTabBoMucSuaCuaTabVaKhongXoaTabDau() {
        var edits = DiagramEdits()
        let existing = ["All tables", "A", "B"]
        edits.place(table: "T", in: "B", at: CGPoint(x: 1, y: 2))
        edits.setZoom(70, in: "B", original: 100)
        #expect(edits.deleteTab("B", existing: existing) == nil)
        #expect(edits.tabs == ["All tables", "A"] && edits.entries?.map(\.source) == [0, 1])
        #expect(edits.positions["B"] == nil && edits.zoom["B"] == nil && edits.added["B"] == nil)
        #expect(edits.deleteTab("All tables", existing: existing) != nil)       // tab đầu cố định như Desktop
        #expect(edits.deleteTab("Z", existing: existing) != nil)
    }

    @Test func themRoiXoaTabMoiVeKhongSua() {
        var edits = DiagramEdits()
        let name = edits.addTab(existing: ["All tables", "A"])
        #expect(edits.deleteTab(name, existing: ["All tables", "A"]) == nil && edits.isEmpty && edits.entries == nil)
    }

    @Test func tabFileBiXoaRoiThemTabCungTenLaTabMoi() {
        var edits = DiagramEdits()
        let existing = ["All tables", "Layout 1", "Layout 2"]
        #expect(edits.deleteTab("Layout 1", existing: existing) == nil)
        #expect(edits.addTab(existing: existing) == "Layout 1")
        #expect(edits.entries == [.init(name: "All tables", source: 0), .init(name: "Layout 2", source: 2), .init(name: "Layout 1", source: nil)])
    }

    @Test func goBangKhoiTabRoiDatLaiBoDauGo() throws {
        let env = try Env(); defer { env.cleanUp() }
        var edits = env.editor.diagramEdits
        edits.removeTable("A", from: "Tab", inFile: true)
        #expect(env.editor.commitDiagram(edits) && env.editor.isDirty && !env.editor.diagramEdits.isEmpty)
        #expect(env.editor.diagramEdits.removed["Tab"] == ["A"])
        env.editor.undo()
        #expect(env.editor.diagramEdits.isEmpty)
        edits.place(table: "A", in: "Tab", at: CGPoint(x: 9, y: 9))
        #expect(edits.removed.isEmpty && edits.added.isEmpty && edits.positions["Tab"]?["A"] == CGPoint(x: 9, y: 9))   // nút còn trong file: chỉ dời
    }

    @Test func goBangMoiThemKhongCanGhiGoNut() {
        var edits = DiagramEdits()
        edits.place(table: "T", in: "Tab", at: .zero)
        edits.removeTable("T", from: "Tab", inFile: false)
        #expect(edits.isEmpty && edits.added.isEmpty && edits.removed.isEmpty)
    }

    @Test func datTheVaoTabKhongBiMatKhiKeoVeChoCu() {
        var edits = DiagramEdits()
        edits.place(table: "T", in: "Layout 1", at: CGPoint(x: 40, y: 40))
        edits.move(table: "T", in: "Layout 1", to: CGPoint(x: 90, y: 90), original: CGPoint(x: 40, y: 40))
        edits.move(table: "T", in: "Layout 1", to: CGPoint(x: 40, y: 40), original: CGPoint(x: 90, y: 90))   // về đúng chỗ đặt ban đầu
        #expect(edits.positions["Layout 1"]?["T"] == CGPoint(x: 40, y: 40))
        edits.resetPositions(in: "Layout 1")      // "Đặt lại bố cục" không gỡ thẻ đã thêm
        #expect(edits.positions["Layout 1"]?["T"] == CGPoint(x: 40, y: 40))
    }
}

@Suite("Phase E: lưu DiagramLayout", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct DiagramSaveTests {
    @Test func keoTheLuuMoLaiChiDoiDiagramLayout() throws {
        let dir = try EFixtures.outputDirectory("E4")
        let source = dir.appendingPathComponent("Nhom6_e4.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let original = try ZipArchive(url: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        let tab = try #require(state.diagramName)
        let before = try #require(workspace.diagramLayout?.diagrams.first { $0.name == tab }?.nodes.first { $0.table == "Dim_Client" })

        state.moveCard(table: "Dim_Client", to: CGPoint(x: 321.5, y: 654.25))
        #expect(state.layout.isDirty)
        let outcome = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                             readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        #expect(outcome.didWrite && !state.layout.isDirty)

        let saved = try ZipArchive(url: source)
        // chỉ DiagramLayout đổi: mô hình giữ nguyên byte, SecurityBindings còn
        for entry in original.entries where entry.path != "DiagramLayout" {
            let now = try #require(saved.entry(entry.path), Comment(rawValue: entry.path))
            #expect(now.crc32 == entry.crc32, Comment(rawValue: "\(entry.path) không được đổi"))
        }
        let after = try #require(PBIXFile(url: source).loadDiagramLayout()?.diagrams.first { $0.name == tab })
        let moved = try #require(after.nodes.first { $0.table == "Dim_Client" })
        #expect(moved.x == 321.5 && moved.y == 654.25 && moved.width == before.width && moved.height == before.height)
        let others = after.nodes.filter { $0.table != "Dim_Client" }
        let oldOthers = try #require(workspace.diagramLayout?.diagrams.first { $0.name == tab }?.nodes.filter { $0.table != "Dim_Client" })
        #expect(others == oldOthers)

        // hoàn tác về vị trí gốc rồi lưu: file trở về đúng vị trí cũ
        state.layout.undo()
        _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        let restored = try #require(PBIXFile(url: source).loadDiagramLayout()?.diagrams.first { $0.name == tab }?.nodes.first { $0.table == "Dim_Client" })
        #expect(restored.x == before.x && restored.y == before.y)
    }

    /// Đổi thu phóng, lưu, hoàn tác về thu phóng cũ, lưu lại: file trở về thu phóng ban đầu (không giữ giá trị đã lưu trước).
    @Test func thuPhongHoanTacSauKhiLuuGhiLaiThuPhongCu() throws {
        let dir = try EFixtures.outputDirectory("E4z")
        let source = dir.appendingPathComponent("Nhom6_e4z.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        let tab = try #require(state.diagramName)
        let original = try #require(workspace.diagramLayout?.diagrams.first { $0.name == tab }?.zoom)
        state.modelZoom = 0.5
        state.commitDiagramZoom()
        func save() throws {
            _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                       readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        }
        try save()
        #expect(try #require(PBIXFile(url: source).loadDiagramLayout()?.diagrams.first { $0.name == tab }).zoom == 50)
        state.layout.undo()
        try save()
        #expect(try #require(PBIXFile(url: source).loadDiagramLayout()?.diagrams.first { $0.name == tab }).zoom == original)
    }

    /// Kéo thẻ, ẩn bảng và đổi thu phóng cùng một lần lưu (T2 vì có đổi mô hình). Ghi `build/e-out/E4/Nhom6_e4b.pbix` cho Desktop.
    @Test func keoTheAnBangThuPhongCungLanLuu() throws {
        let dir = try EFixtures.outputDirectory("E4")
        let source = dir.appendingPathComponent("Nhom6_e4b.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        let tab = try #require(state.diagramName)
        state.moveCard(table: "Dim_Date", to: CGPoint(x: 700, y: 900))
        #expect(state.setTableHidden("Dim_Trans_Type", hidden: true) == nil)
        state.modelZoom = 0.5
        state.commitDiagramZoom()
        #expect(workspace.metadata?.tables.first { $0.name == "Dim_Trans_Type" }?.isHidden == true)
        _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        let layout = try #require(PBIXFile(url: source).loadDiagramLayout()?.diagrams.first { $0.name == tab })
        #expect(layout.nodes.first { $0.table == "Dim_Date" }.map { $0.x == 700 && $0.y == 900 } == true)
        #expect(layout.zoom == 50)
        let (abf, _) = try PBIXFile(url: source).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        #expect(model.tables.first { $0.name == "Dim_Trans_Type" }?.isHidden == true)
        // hoàn tác ẩn bảng: bảng hiện lại
        state.layout.undo(); state.layout.undo()
        #expect(workspace.metadata?.tables.first { $0.name == "Dim_Trans_Type" }?.isHidden == false)
    }

    /// VM-E6: thêm tab, đổi tên, đặt bảng vào tab, lưu, mở lại; hoàn tác sau lưu rồi lưu lần hai thì tab biến mất khỏi file.
    @Test func themDoiTenTabLuuMoLai() throws {
        let dir = try EFixtures.outputDirectory("E6")
        let source = dir.appendingPathComponent("Nhom6_e6.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .model
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        func save() throws {
            _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                       readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        }
        func tabs() throws -> [DiagramLayout.Diagram] { try #require(PBIXFile(url: source).loadDiagramLayout()).diagrams }
        let originalCount = try tabs().count

        state.addDiagramTab()
        #expect(state.diagramTabs.last == "Layout 1" && state.currentDiagram == "Layout 1" && state.diagramTables("Layout 1") == [])
        state.addTableToCurrentDiagram("Fact_Loan", frames: [:])
        #expect(state.diagramTables("Layout 1") == ["Fact_Loan"])
        #expect(state.renameDiagramTab("Layout 1", to: "Bố cục vay") == nil && state.currentDiagram == "Bố cục vay")
        #expect(state.renameDiagramTab("All tables", to: "X") != nil && state.relationshipNotice != nil)
        try save()

        var saved = try tabs()
        #expect(saved.count == originalCount + 1)
        let added = try #require(saved.last)
        #expect(added.name == "Bố cục vay" && added.ordinal == originalCount && added.nodes.map(\.table) == ["Fact_Loan"] && added.zoom == 100)
        let guid = try #require(workspace.userTables.first { $0.name == "Fact_Loan" }?.lineageTag)
        let raw = try PBIXFile(url: source).utf16Part("DiagramLayout")
        #expect(raw.contains(#""nodeLineageTag":"\#(guid)""#) && raw.contains(#""selectedDiagram":"Bố cục vay""#))
        #expect(saved.first?.name == "All tables")

        // mở lại: tab và bảng trong tab đúng
        let reopened = DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
        #expect(reopened.diagramTabs.last == "Bố cục vay" && reopened.diagramTables("Bố cục vay") == ["Fact_Loan"])

        // hoàn tác về trước khi có tab (đổi tên, đặt bảng, thêm tab) rồi lưu lần hai: file về đúng như gốc
        state.layout.undo(); state.layout.undo(); state.layout.undo()
        #expect(state.diagramTabs.count == originalCount)
        try save()
        saved = try tabs()
        #expect(saved.count == originalCount && saved.last?.name != "Bố cục vay")
    }

    /// VM-E7: xoá tab, gỡ bảng khỏi tab, thêm tab trùng tên tab đã xoá; hoàn tác sau khi lưu trả file về như trước.
    @Test func xoaTabGoBangLuuMoLai() throws {
        let dir = try EFixtures.outputDirectory("E7")
        let source = dir.appendingPathComponent("Nhom6_e7.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        func open() throws -> DocumentState {
            let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: source)), fileName: source.lastPathComponent, fileURL: source)
            state.mode = .model
            var clock = Date(timeIntervalSince1970: 1_000)
            state.layout.now = { clock += 10; return clock }
            return state
        }
        func save(_ state: DocumentState) throws {
            _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                       readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        }
        func tabs() throws -> [DiagramLayout.Diagram] { try #require(PBIXFile(url: source).loadDiagramLayout()).diagrams }
        func summary(_ diagrams: [DiagramLayout.Diagram]) -> [String] { diagrams.map { "\($0.ordinal):\($0.name):\($0.nodes.map(\.table).sorted().joined(separator: ","))" } }

        // Dựng file có ba tab: Layout 1 (Fact_Loan, Dim_Client), Layout 2 (Dim_Client, Dim_Loan_Profile), Layout 3 (Fact_Loan).
        let setup = try open()
        for (_, tables) in [("Layout 1", ["Fact_Loan", "Dim_Client"]), ("Layout 2", ["Dim_Client", "Dim_Loan_Profile"]), ("Layout 3", ["Fact_Loan"])] {
            setup.addDiagramTab()
            var frames: [String: CGRect] = [:]
            for (i, table) in tables.enumerated() {
                setup.addTableToCurrentDiagram(table, frames: frames)
                frames[table] = CGRect(x: 40 + 300 * CGFloat(i), y: 40, width: 234, height: 300)
            }
        }
        try save(setup)
        let before = summary(try tabs())
        #expect(before.suffix(3) == ["1:Layout 1:Dim_Client,Fact_Loan", "2:Layout 2:Dim_Client,Dim_Loan_Profile", "3:Layout 3:Fact_Loan"])
        let layout1 = try #require(try tabs().first { $0.name == "Layout 1" })
        let clientOriginal = try #require(layout1.nodes.first { $0.table == "Dim_Client" })

        // Mở lại: kéo Dim_Client, gỡ Fact_Loan khỏi Layout 1, xoá Layout 2, lưu.
        let state = try open()
        state.selectDiagram("Layout 1")
        state.moveCard(table: "Dim_Client", to: CGPoint(x: 500, y: 500))
        state.removeTableFromCurrentDiagram("Fact_Loan")
        #expect(state.diagramTables("Layout 1") == ["Dim_Client"])
        #expect(state.deleteDiagramTab("Layout 2") == nil && state.diagramTabs.suffix(2) == ["Layout 1", "Layout 3"])
        try save(state)
        #expect(summary(try tabs()).suffix(2) == ["1:Layout 1:Dim_Client", "2:Layout 3:Fact_Loan"])
        let raw = try PBIXFile(url: source).utf16Part("DiagramLayout")
        #expect(raw.contains(#""selectedDiagram":"Layout 1""#) && !raw.contains("Layout 2"))
        #expect(try tabs().first { $0.name == "Layout 1" }?.nodes.first?.x == 500)
        // Mô hình không đổi: Fact_Loan vẫn ở trong mô hình và "All tables"
        #expect(state.workspace.userTables.contains { $0.name == "Fact_Loan" })
        #expect(try tabs().first?.nodes.contains { $0.table == "Fact_Loan" } == true)

        // Thêm tab trùng tên tab đã xoá: là tab mới, không mang vị trí cũ của Layout 2.
        state.addDiagramTab()
        #expect(state.diagramTabs.last == "Layout 2")
        state.addTableToCurrentDiagram("Dim_Date", frames: [:])
        try save(state)
        let afterAdd = try tabs()
        #expect(afterAdd.map(\.name).suffix(3) == ["Layout 1", "Layout 3", "Layout 2"] && afterAdd.map(\.ordinal) == Array(0..<afterAdd.count))
        #expect(afterAdd.last?.nodes.map(\.table) == ["Dim_Date"])

        // Hoàn tác mọi thứ (kéo, gỡ, xoá, thêm tab, đặt bảng) rồi lưu: file về như trước khi sửa.
        for _ in 0..<5 { state.layout.undo() }
        try save(state)
        #expect(summary(try tabs()) == before)
        let restored = try #require(try tabs().first { $0.name == "Layout 1" }?.nodes.first { $0.table == "Dim_Client" })
        #expect(restored.x == clientOriginal.x && restored.y == clientOriginal.y)
    }
}
