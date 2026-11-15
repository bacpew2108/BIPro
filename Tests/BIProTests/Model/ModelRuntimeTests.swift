import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T008): `ModelRuntime` giữ mô hình hiệu lực và engine nạp lại khi `ModelEdits` đổi. Chạy trên Nhom6 thật
/// (BIPRO_HEAVY=1, vì mở Workspace giải nén cả mô hình).
@Suite("Phase E: ModelRuntime", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
struct ModelRuntimeTests {
    private func firstNumber(_ result: QueryResult) -> Double? {
        guard let value = result.tables.first?.rows.first?.first else { return nil }
        switch value {
        case .integer(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    private func workspace() throws -> Workspace {
        try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6)))
    }

    @Test func measureMoiChayQuaEngineVaDoiBieuThucDoiSo() async throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let baseCount = try await workspace.daxEngine().execute("EVALUATE ROW(\"x\", COUNTROWS(Dim_Account))")
        let accounts = try #require(firstNumber(baseCount))

        let version0 = runtime.version
        try runtime.setEdits(ModelEdits([.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "COUNTROWS(Dim_Account)+1"))]))
        #expect(runtime.version > version0)
        #expect(workspace.metadata?.measures.contains { $0.name == "E_Test" } == true)
        let first = try await workspace.daxEngine().execute("EVALUATE ROW(\"x\", [E_Test])")
        #expect(firstNumber(first) == accounts + 1)

        try runtime.setEdits(ModelEdits([
            .addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "COUNTROWS(Dim_Account)+1")),
            .updateMeasure(table: "Dim_Account", name: "E_Test", patch: MeasurePatch(expression: "COUNTROWS(Dim_Account)+2")),
        ]))
        let second = try await workspace.daxEngine().execute("EVALUATE ROW(\"x\", [E_Test])")
        #expect(firstNumber(second) == accounts + 2)

        // Quay về mô hình gốc: measure biến mất khỏi catalog.
        try runtime.setEdits(ModelEdits())
        #expect(workspace.metadata?.measures.contains { $0.name == "E_Test" } == false)
        await #expect(throws: (any Error).self) { try await workspace.daxEngine().execute("EVALUATE ROW(\"x\", [E_Test])") }
    }

    @Test func doiMeasureDungLaiColumnStore() throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let storeBefore = try runtime.engine().store
        try runtime.setEdits(ModelEdits([.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "1"))]))
        #expect(try runtime.engine().store === storeBefore)
    }

    @Test func editsLoiGiuNguyenMoHinh() throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let version = runtime.version
        #expect(throws: ModelEditError.self) {
            try runtime.setEdits(ModelEdits([.deleteMeasure(table: "Dim_Account", name: "khong co")]))
        }
        #expect(runtime.version == version)
        #expect(runtime.edits.isEmpty)
    }

    @Test func edit_giongNhauKhongTangPhienBan() throws {
        let workspace = try workspace()
        let runtime = try #require(workspace.runtime)
        let edits = ModelEdits([.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "1"))])
        try runtime.setEdits(edits)
        let version = runtime.version
        try runtime.setEdits(edits)
        #expect(runtime.version == version)
    }
}
