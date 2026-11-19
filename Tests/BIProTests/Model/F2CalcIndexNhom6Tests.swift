// specs/011, US4 (T051): sửa cột tính toán là cấp phân cấp trên bản sao Nhom6 (`Dim_District[branch_label]`, cấp cuối của phân cấp "Địa lý"
// region → state_name → branch_label), lưu hai lần, mở lại. Đối chiếu từng dòng với công thức mới tính tay từ city, state_abbrev và số liệu
// gộp theo cấp phân cấp qua quan hệ Fact_Loan → Dim_District. Để lại tệp gate `build/f2-out/f13/bipro-f13-nhom6.pbix` (T052).
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Đợt F2: sửa cột tính toán là cấp phân cấp trên Nhom6", .enabled(if: F2Fixtures.heavy && F2Fixtures.nhom6 != nil), .serialized) @MainActor
struct F2CalcIndexNhom6Tests {
    private func rows(_ workspace: Workspace, _ query: String) async throws -> [[Value]] {
        try await workspace.daxEngine().execute(query).tables.first?.rows ?? []
    }

    @Test func suaBranchLabelLuuHaiLanMoLai() async throws {
        let copy = try #require(try F2Fixtures.copy(F2Fixtures.nhom6, folder: "f13", fileName: "bipro-f13-nhom6.pbix"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f13-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backups = root.appendingPathComponent("Backups")
        let original = try Workspace(data: Data(contentsOf: copy))
        let byLabel = """
            EVALUATE SUMMARIZECOLUMNS(Dim_District[region], Dim_District[state_name], Dim_District[city], Dim_District[state_abbrev],
                "n", COUNTROWS(Fact_Loan), "a", SUM(Fact_Loan[loan_amount]))
            """
        let before = try await rows(original, byLabel)
        #expect(before.count >= 8)   // Fact_Loan nằm ở 8 quận

        let state = DocumentState(workspace: original, fileName: copy.lastPathComponent, fileURL: copy)
        #expect(await state.updateCalculatedColumn(table: "Dim_District", name: "branch_label",
                                                   formula: "branch_label = Dim_District[city] & \" - \" & Dim_District[state_abbrev]") == nil)
        #expect(try DocumentSaver.save(editor: state.layout, source: copy, to: copy, expectedStamp: try FileStamp.of(copy), readOnlyRoots: [],
                                       backupDirectory: backups).didWrite)
        // Lần lưu thứ hai (thêm một measure) trên tệp vừa ghi: chỉ mục dựng lại vẫn đọc được và giữ nguyên.
        let second = DocumentState(workspace: try Workspace(data: Data(contentsOf: copy)), fileName: copy.lastPathComponent, fileURL: copy)
        #expect(second.modelEditor.apply(.addMeasure(NewMeasure(table: "Fact_Loan", name: "F13 tổng vay", expression: "SUM(Fact_Loan[loan_amount])"))) == nil)
        #expect(try DocumentSaver.save(editor: second.layout, source: copy, to: copy, expectedStamp: try FileStamp.of(copy), readOnlyRoots: [],
                                       backupDirectory: backups).didWrite)

        let reopened = try Workspace(data: Data(contentsOf: copy))
        let model = try #require(reopened.metadata)
        #expect(model.columns.first { $0.tableName == "Dim_District" && $0.name == "branch_label" }?.expression
                    == "Dim_District[city] & \" - \" & Dim_District[state_abbrev]")
        #expect(model.hierarchies.first { $0.tableName == "Dim_District" && $0.name == "Địa lý" }?.levels.map(\.columnName)
                    == ["region", "state_name", "branch_label"])
        // Từng dòng: nhãn mới = city - state_abbrev.
        let labels = try await rows(reopened, """
            EVALUATE ROW("n", COUNTROWS(Dim_District), "lech", COUNTROWS(FILTER(Dim_District,
                NOT EXACT(Dim_District[branch_label], Dim_District[city] & " - " & Dim_District[state_abbrev]))))
            """)
        #expect(labels == [[.integer(77), .blank]])
        // Số liệu theo cấp phân cấp (qua quan hệ) không đổi; gộp theo nhãn mới bằng gộp theo city + state_abbrev.
        #expect(try await rows(reopened, byLabel) == before)
        let byNewLabel = try await rows(reopened, """
            EVALUATE SUMMARIZECOLUMNS(Dim_District[region], Dim_District[state_name], Dim_District[branch_label], "n", COUNTROWS(Fact_Loan))
            """)
        func total(_ list: [[Value]], _ i: Int) -> Int64 {
            list.reduce(0) { sum, row in if case .integer(let n) = row[i] { sum + n } else { sum } }
        }
        #expect(total(byNewLabel, 3) == total(before, 4))
    }
}
