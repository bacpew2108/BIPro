// Phase F, T084 (US6): cột và bảng tính toán trên bản sao Nhom6 (bảng có quan hệ, cột tính toán sẵn của Desktop), lưu, mở lại, đối chiếu từng
// dòng với giá trị tính độc lập bằng Swift từ cột đã lưu. Để lại `build/f-out/f6/Nhom6_f4.pbix` cho gate Desktop (T085). BIPRO_HEAVY=1.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: cột/bảng tính toán trên Nhom6", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized) @MainActor
struct F6Nhom6CalcTests {
    private func stored(_ workspace: Workspace, _ table: String, _ column: String) throws -> [Value] {
        let engine = try workspace.daxEngine()
        let id = try #require(engine.store.schema.column(table: table, name: column)?.id)
        let data = try engine.store.column(id)
        return (0..<(try engine.store.rowCount(id.table))).map { Value(stored: data.value(at: $0)) }
    }

    @Test func themCotVaBangTinhToanLuuMoLaiKhopTungDong() async throws {
        let dir = try FFixtures.outputDirectory("f6")
        let url = dir.appendingPathComponent("Nhom6_f4.pbix")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: url)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        state.mode = .table

        #expect(await state.addCalculatedColumn(table: "Dim_District", formula: "Nhãn đầy đủ = Dim_District[city] & \" (\" & Dim_District[state_abbrev] & \")\"") == nil)
        #expect(await state.addCalculatedColumn(table: "Fact_Loan",
                                                formula: "Tuổi năm sau = IF(ISBLANK(Fact_Loan[age_at_loan]), BLANK(), Fact_Loan[age_at_loan] + 1)") == nil)
        #expect(await state.addCalculatedTable(formula: "Lịch 2026 = CALENDAR(DATE(2026,1,1), DATE(2026,12,31))") == nil)
        #expect(state.workspace.runtime?.calculationErrors.isEmpty == true)

        let stamp = try FileStamp.of(url)
        let backups = dir.appendingPathComponent("Backups")
        defer { try? FileManager.default.removeItem(at: backups) }
        #expect(try DocumentSaver.save(editor: state.layout, source: url, to: url, expectedStamp: stamp, readOnlyRoots: [], backupDirectory: backups).didWrite)

        let reopened = try Workspace(data: Data(contentsOf: url))
        let model = try #require(reopened.metadata)
        #expect(model.columns.first { $0.tableName == "Dim_District" && $0.name == "Nhãn đầy đủ" }?.kind == .calculated)
        #expect(model.tables.first { $0.name == "Lịch 2026" }?.isCalculatedUserTable == true)

        let city = try stored(reopened, "Dim_District", "city"), state2 = try stored(reopened, "Dim_District", "state_abbrev")
        let label = try stored(reopened, "Dim_District", "Nhãn đầy đủ")
        #expect(label.count == 77)
        for i in label.indices {
            func text(_ v: Value) -> String { if case .string(let s) = v { s } else { "" } }
            #expect(label[i] == .string("\(text(city[i])) (\(text(state2[i])))"), Comment(rawValue: "dòng \(i)"))
        }
        let age = try stored(reopened, "Fact_Loan", "age_at_loan"), next = try stored(reopened, "Fact_Loan", "Tuổi năm sau")
        #expect(next.count == 682)
        #expect(zip(age, next).allSatisfy { a, n in
            if case .integer(let x) = a { return n == .integer(x + 1) }
            return n == .blank
        })
        let days = try stored(reopened, "Lịch 2026", "Date")
        #expect(days.count == 365)
        #expect(days.first == .dateTime(46_023) && days.last == .dateTime(46_387))      // 2026-01-01 và 2026-12-31
        // Phần cũ của mô hình còn nguyên: quan hệ, cột tính toán của Desktop.
        #expect(model.relationships.count == (EFixtures.metadata?.relationships.count ?? -1))
        #expect(model.columns.filter { $0.kind == .calculated }.count == 7 + 2)
    }
}
