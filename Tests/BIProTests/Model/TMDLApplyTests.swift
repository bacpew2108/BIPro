import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T037, T038): sửa văn bản TMDL và áp dụng vào mô hình, trên Nhom6 thật (BIPRO_HEAVY=1).
@Suite("Phase E: TMDL View sửa được", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct TMDLApplyTests {
    private func makeState() throws -> DocumentState {
        let workspace = try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6)))
        let state = DocumentState(workspace: workspace, fileName: "Nhom6_e.pbix")
        state.mode = .tmdl
        var clock = Date(timeIntervalSince1970: 1_000)
        state.layout.now = { clock += 10; return clock }
        return state
    }

    private func doc(_ state: DocumentState, _ path: String) throws -> String {
        try #require(state.workspace.tmdlDocuments.first { $0.path == path }).text
    }

    private func number(_ state: DocumentState, _ expression: String) async throws -> Double {
        let result = try await state.workspace.daxEngine().execute("EVALUATE ROW(\"v\", \(expression))")
        switch result.tables.first?.rows.first?.first {
        case .integer(let i)?: return Double(i)
        case .double(let d)?: return d
        default: Issue.record("không phải số"); return .nan
        }
    }

    @Test func suaBieuThucMeasureQuaTMDLDoiSoVaHoanTacMotBuoc() async throws {
        let state = try makeState()
        // thêm một measure đơn giản bằng TMDL ở bảng Dim_Account, rồi sửa biểu thức của nó bằng TMDL lần nữa
        let path = "tables/Dim_Account.tmdl"
        let original = try doc(state, path)
        let added = original + "\n\tmeasure E_Tmdl = COUNTROWS(Dim_Account)\n\t\tformatString: 0\n\t\tdisplayFolder: Thu muc E\n"
        let t0 = Date()
        var issues = state.applyTMDL(drafts: [path: added])
        let seconds = Date().timeIntervalSince(t0)
        #expect(issues.isEmpty, Comment(rawValue: "\(issues)"))
        print("KEY TMDL áp dụng (debug): \(String(format: "%.0f", seconds * 1000)) ms")
        let accounts = try await number(state, "[E_Tmdl]")
        #expect(accounts > 0)
        let created = try #require(state.workspace.measure(table: "Dim_Account", name: "E_Tmdl"))
        #expect(created.displayFolder == "Thu muc E" && created.formatString == "0")

        // văn bản TMDL sinh lại từ mô hình đã sửa chứa đúng measure vừa thêm (khớp văn bản đã nhập sau chuẩn hoá)
        let regenerated = try doc(state, path)
        #expect(regenerated.contains("measure E_Tmdl = COUNTROWS(Dim_Account)") && regenerated.contains("displayFolder: Thu muc E"))
        let reparsed = try TMDLParser.parse(documents: [(path, regenerated)]).tables[0].measures.first { $0.name == "E_Tmdl" }
        #expect(reparsed?.expression == "COUNTROWS(Dim_Account)" && reparsed?.formatString == "0")

        issues = state.applyTMDL(drafts: [path: regenerated.replacingOccurrences(of: "COUNTROWS(Dim_Account)", with: "COUNTROWS(Dim_Account) + 1")])
        #expect(issues.isEmpty, Comment(rawValue: "\(issues)"))
        #expect(try await number(state, "[E_Tmdl]") == accounts + 1)
        state.layout.undo()
        #expect(try await number(state, "[E_Tmdl]") == accounts)
        state.layout.undo()
        #expect(state.workspace.measure(table: "Dim_Account", name: "E_Tmdl") == nil && !state.layout.isDirty)
    }

    @Test func suaThuocTinhCotQuanHeVaAnBangQuaTMDL() throws {
        let state = try makeState()
        var drafts: [String: String] = [:]
        let account = try doc(state, "tables/Dim_Client.tmdl")
        drafts["tables/Dim_Client.tmdl"] = account.replacingOccurrences(of: "\tcolumn client_city\n", with: "\t/// mo ta tmdl\n\tcolumn client_city\n")
        let trans = try doc(state, "tables/Dim_Trans_Type.tmdl")
        drafts["tables/Dim_Trans_Type.tmdl"] = trans.replacingOccurrences(of: "table Dim_Trans_Type\n", with: "table Dim_Trans_Type\n\tisHidden\n")
        let rels = try doc(state, "relationships.tmdl")
        let first = try #require(state.workspace.metadata?.relationships.first { $0.isActive && $0.crossFilteringBehavior == 1 })
        let block = "relationship '\(first.name)'\n"   // tên GUID có gạch nối nên TMDL đặt trong nháy đơn
        drafts["relationships.tmdl"] = rels.replacingOccurrences(of: block, with: block + "\tcrossFilteringBehavior: bothDirections\n")
        let issues = state.applyTMDL(drafts: drafts)
        #expect(issues.isEmpty, Comment(rawValue: "\(issues)"))
        #expect(state.workspace.column(table: "Dim_Client", name: "client_city")?.description == "mo ta tmdl")
        #expect(state.workspace.metadata?.tables.first { $0.name == "Dim_Trans_Type" }?.isHidden == true)
        #expect(state.workspace.metadata?.relationships.first { $0.name == first.name }?.crossFilteringBehavior == 2)
        // ba thay đổi trong một lần áp dụng = một bước hoàn tác
        #expect(state.layout.undoDepth == 1)
        state.layout.undo()
        #expect(state.workspace.metadata?.relationships.first { $0.name == first.name }?.crossFilteringBehavior == 1 && !state.layout.isDirty)
    }

    @Test func saiCuPhapHoacNgoaiPhamViKhongAptGi() throws {
        let state = try makeState()
        let path = "tables/Dim_Account.tmdl"
        let original = try doc(state, path)
        // cú pháp sai
        var issues = state.applyTMDL(drafts: [path: original + "\n\tmeasure Hong\n"])
        #expect(issues.count == 1 && issues[0].line != nil)
        // bảng mới, cột mới
        issues = state.applyTMDL(drafts: ["tables/Moi.tmdl": "table Moi\n"])
        #expect(issues.contains { $0.message.contains("bảng mới") })
        issues = state.applyTMDL(drafts: [path: original + "\n\tcolumn moi\n\t\tdataType: string\n"])
        #expect(issues.contains { $0.message.contains("cột mới") })
        // đổi kiểu dữ liệu một cột
        let withType = original.replacingOccurrences(of: "dataType: int64", with: "dataType: string")
        issues = state.applyTMDL(drafts: [path: withType])
        #expect(issues.contains { $0.message.contains("kiểu dữ liệu") })
        #expect(!state.layout.isDirty, "áp nguyên khối: có từ chối thì không áp gì")
        // chế độ Xem
        state.mode = .report; state.editMode = false
        issues = state.applyTMDL(drafts: [path: original + "\n\tmeasure E = 1\n"])
        #expect(issues.first?.message.contains("Sửa") == true && !state.layout.isDirty)
    }

    /// Sửa bằng TMDL (thêm measure có thư mục và mô tả, ẩn một cột), lưu T2, mở lại. Ghi `build/e-out/E5/Nhom6_e5.pbix` cho Desktop.
    @Test func luuMoLaiSauKhiAplyTMDL() throws {
        let dir = try EFixtures.outputDirectory("E5")
        let source = dir.appendingPathComponent("Nhom6_e5.pbix")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
        let workspace = try Workspace(data: Data(contentsOf: source))
        let state = DocumentState(workspace: workspace, fileName: source.lastPathComponent, fileURL: source)
        state.mode = .tmdl
        let path = "tables/Dim_Account.tmdl"
        let text = try doc(state, path)
        let edited = text + "\n\t/// do TMDL them vao\n\tmeasure 'E_Tmdl Tong' = COUNTROWS(Dim_Account) + 1\n\t\tformatString: 0\n\t\tdisplayFolder: Thu muc TMDL\n"
        let hidden = edited.replacingOccurrences(of: "\tcolumn branch_division\n", with: "\tcolumn branch_division\n\t\tisHidden\n")
        #expect(state.applyTMDL(drafts: [path: hidden]).isEmpty)
        _ = try DocumentSaver.save(editor: state.layout, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: dir.appendingPathComponent("Backups"))
        let (abf, _) = try PBIXFile(url: source).loadDataModel()
        let read = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let measure = try #require(read.measures.first { $0.name == "E_Tmdl Tong" })
        #expect(measure.expression == "COUNTROWS(Dim_Account) + 1" && measure.displayFolder == "Thu muc TMDL" && measure.description == "do TMDL them vao")
        #expect(read.columns.first { $0.tableName == "Dim_Account" && $0.name == "branch_division" }?.isHidden == true)
    }
}
