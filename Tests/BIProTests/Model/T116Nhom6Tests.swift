// Phase F, T116 (FR-060): sửa và xoá cột, bảng tính toán trên bản sao Nhom6, lưu T3 hai lần, mở lại, đối chiếu từng dòng với giá trị tính độc
// lập bằng Swift từ cột nguồn đã lưu. Gồm cột tính toán gốc của Desktop (`Dim_Date[MonthIndex]` 2 922 dòng, `Fact_Transaction[trans_hour]`
// 1 056 320 dòng), cột BI Pro thêm có cột phụ thuộc, xoá cột và bảng tính toán có sẵn trong file. Để lại `build/f-out/f9/Nhom6_t116.pbix`
// cho gate Desktop. BIPRO_HEAVY=1, nên chạy bản release.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: sửa và xoá cột/bảng tính toán trên Nhom6", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized) @MainActor
struct T116Nhom6Tests {
    private func stored(_ workspace: Workspace, _ table: String, _ column: String) throws -> [Value] {
        let engine = try workspace.daxEngine()
        let id = try #require(engine.store.schema.column(table: table, name: column)?.id)
        let data = try engine.store.column(id)
        return (0..<(try engine.store.rowCount(id.table))).map { Value(stored: data.value(at: $0)) }
    }

    private func save(_ state: DocumentState, _ url: URL, backups: URL) throws -> Double {
        let start = Date()
        #expect(try DocumentSaver.save(editor: state.layout, source: url, to: url, expectedStamp: try FileStamp.of(url), readOnlyRoots: [],
                                       backupDirectory: backups).didWrite)
        return Date().timeIntervalSince(start)
    }

    @Test func suaXoaCotVaBangTinhToanLuuHaiLanKhopTungDong() async throws {
        let dir = try FFixtures.outputDirectory("f9")
        let url = dir.appendingPathComponent("Nhom6_t116.pbix")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: url)
        let backups = dir.appendingPathComponent("Backups")
        defer { try? FileManager.default.removeItem(at: backups) }

        // Lần 1: thêm các mục sẽ sửa/xoá ở lần 2 (để chúng nằm sẵn trong file).
        let first = DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        first.mode = .table
        #expect(await first.addCalculatedColumn(table: "Fact_Loan", formula: "Nhãn tuổi = Fact_Loan[age_group_at_loan] & \" tuổi\"") == nil)
        #expect(await first.addCalculatedColumn(table: "Fact_Loan", formula: "Nhãn dài = Fact_Loan[Nhãn tuổi] & \"!\"") == nil)
        #expect(await first.addCalculatedColumn(table: "Fact_Loan", formula: "Bỏ = 1") == nil)
        #expect(await first.addCalculatedTable(formula: "Nhóm tuổi = DISTINCT(Fact_Loan[age_group_at_loan])") == nil)
        #expect(await first.addCalculatedTable(formula: "Tạm = DISTINCT(Dim_Date[year])") == nil)
        print("BENCHMARK T116 [Nhom6 lần 1, thêm 3 cột + 2 bảng]: \(String(format: "%.2f", try save(first, url, backups: backups))) s")

        // Lần 2: sửa công thức cột gốc của Desktop và cột BI Pro (cột phụ thuộc tự ghi lại), sửa và xoá bảng, xoá cột.
        let second = DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url)
        let before = try #require(second.workspace.metadata)
        let ids = Dictionary(before.columns.filter { $0.kind == .calculated }.map { ("\($0.tableName)[\($0.name)]", $0.id) }, uniquingKeysWith: { a, _ in a })
        second.mode = .table
        var reason = await second.updateCalculatedColumn(table: "Dim_Date", name: "MonthIndex",
                                                         formula: "MonthIndex = IF(Dim_Date[date_key] = -1, BLANK(), Dim_Date[year] * 100 + Dim_Date[month_num])")
        #expect(reason == nil, Comment(rawValue: reason ?? ""))
        reason = await second.updateCalculatedColumn(table: "Fact_Transaction", name: "trans_hour",
                                                     formula: "trans_hour = MOD(HOUR(Fact_Transaction[trans_timestamp]) + 7, 24)")
        #expect(reason == nil, Comment(rawValue: reason ?? ""))
        reason = await second.updateCalculatedColumn(table: "Fact_Loan", name: "Nhãn tuổi", formula: "Nhãn tuổi = \"Tuổi \" & Fact_Loan[age_group_at_loan]")
        #expect(reason == nil, Comment(rawValue: reason ?? ""))
        // Cột là cấp của phân cấp: sửa được, bộ ghi dựng lại `U$` (US4, specs/011; trước đây bị chặn).
        let rebuilt = await second.updateCalculatedColumn(table: "Dim_District", name: "branch_label", formula: "branch_label = Dim_District[city]")
        #expect(rebuilt == nil, Comment(rawValue: rebuilt ?? "nil"))
        #expect(second.deleteCalculatedColumn(table: "Fact_Loan", name: "Bỏ") == nil)
        reason = await second.updateCalculatedTable(name: "Nhóm tuổi",
                                                    formula: "Nhóm tuổi = FILTER(DISTINCT(Fact_Loan[age_group_at_loan]), Fact_Loan[age_group_at_loan] <> \"Unknown\")")
        #expect(reason == nil, Comment(rawValue: reason ?? ""))
        #expect(second.deleteCalculatedTable(name: "Tạm") == nil)
        #expect(second.workspace.runtime?.calculationErrors.isEmpty == true)
        print("BENCHMARK T116 [Nhom6 lần 2, sửa 3 cột (1 triệu dòng) + 1 phụ thuộc, xoá cột, sửa và xoá bảng]: "
              + "\(String(format: "%.2f", try save(second, url, backups: backups))) s")

        // Mở lại: đối chiếu dữ liệu đã lưu với giá trị tính bằng Swift từ cột nguồn.
        let reopened = try Workspace(data: Data(contentsOf: url))
        let model = try #require(reopened.metadata)
        for key in ["Dim_Date[MonthIndex]", "Fact_Transaction[trans_hour]", "Fact_Loan[Nhãn tuổi]", "Fact_Loan[Nhãn dài]"] {
            #expect(model.columns.first { "\($0.tableName)[\($0.name)]" == key }?.id == ids[key], Comment(rawValue: "giữ ID \(key)"))
        }
        #expect(!model.columns.contains { $0.name == "Bỏ" })
        #expect(model.userTables.contains { $0.name == "Nhóm tuổi" } && !model.userTables.contains { $0.name == "Tạm" })
        #expect(model.relationships.count == (EFixtures.metadata?.relationships.count ?? -1))

        let key = try stored(reopened, "Dim_Date", "date_key"), year = try stored(reopened, "Dim_Date", "year")
        let month = try stored(reopened, "Dim_Date", "month_num"), index = try stored(reopened, "Dim_Date", "MonthIndex")
        #expect(index.count == 2922)
        for i in index.indices {
            guard case .integer(let k) = key[i], case .integer(let y) = year[i], case .integer(let m) = month[i] else { continue }
            #expect(index[i] == (k == -1 ? .blank : .integer(y * 100 + m)), Comment(rawValue: "MonthIndex dòng \(i)"))
        }
        let stamps = try stored(reopened, "Fact_Transaction", "trans_timestamp"), hours = try stored(reopened, "Fact_Transaction", "trans_hour")
        #expect(hours.count == 1_056_320)
        var wrong = 0
        for i in hours.indices {
            guard case .dateTime(let t) = stamps[i] else { if hours[i] != .blank { wrong += 1 }; continue }
            let hour = Int64(((t - t.rounded(.down)) * 24 + 1e-9).rounded(.down))
            if hours[i] != .integer((hour + 7) % 24) { wrong += 1 }
        }
        #expect(wrong == 0)
        let group = try stored(reopened, "Fact_Loan", "age_group_at_loan"), label = try stored(reopened, "Fact_Loan", "Nhãn tuổi")
        let long = try stored(reopened, "Fact_Loan", "Nhãn dài")
        for i in group.indices {
            guard case .string(let g) = group[i] else { continue }
            #expect(label[i] == .string("Tuổi \(g)") && long[i] == .string("Tuổi \(g)!"), Comment(rawValue: "Fact_Loan dòng \(i)"))
        }
        let groups = Set(group.compactMap { if case .string(let g) = $0, g != "Unknown" { g } else { nil } })
        #expect(Set(try stored(reopened, "Nhóm tuổi", "age_group_at_loan").map { "\($0)" }).count == groups.count)

        // Số cho checklist Desktop (DAX query view tính lại biểu thức trên dữ liệu đã lưu).
        let checks = try await reopened.daxEngine().execute("""
            EVALUATE ROW(
                "MonthIndex lệch", COUNTROWS(FILTER(Dim_Date, Dim_Date[MonthIndex] <> IF(Dim_Date[date_key] = -1, BLANK(), Dim_Date[year] * 100 + Dim_Date[month_num]))),
                "Σ MonthIndex", SUM(Dim_Date[MonthIndex]),
                "trans_hour lệch", COUNTROWS(FILTER(Fact_Transaction, Fact_Transaction[trans_hour] <> MOD(HOUR(Fact_Transaction[trans_timestamp]) + 7, 24))),
                "Σ trans_hour", SUM(Fact_Transaction[trans_hour]),
                "Nhãn dài lệch", COUNTROWS(FILTER(Fact_Loan, Fact_Loan[Nhãn dài] <> "Tuổi " & Fact_Loan[age_group_at_loan] & "!")),
                "Nhóm tuổi", COUNTROWS('Nhóm tuổi'))
            """)
        print("KEY T116 Desktop checks: \(checks.tables.first?.rows.first ?? [])")
        print("KEY T116 file gate: \(url.path)")
    }
}
