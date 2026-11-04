// PERFMiniBankTests.swift
// Gói E3 (Phase C, đợt 2): các tối ưu hiệu năng không được đổi kết quả.
// - Tách bộ lọc cục bộ khỏi lan truyền (R(T) = R(T | phần còn lại) ∩ dòng cục bộ) phải trùng đường lan truyền đầy đủ.
// - Ô SUMMARIZECOLUMNS chạy song song phải trùng từng ô tính riêng lẻ.
// - Cache VALUES có cache phải trùng `FilterContext.visibleValues`.

import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct PERFMiniBankTests {
    private typealias Col = MiniBank.Columns

    private func makeEngine() -> (DAXEngine, Evaluator, ColumnStore) {
        let store = MiniBank.makeStore()
        let measures = MiniBank.measures.map { ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression) }
        let catalog = Catalog(schema: MiniBank.schema, measures: measures)
        return (DAXEngine(store: store, catalog: catalog), Evaluator(store: store, catalog: catalog), store)
    }

    private func context(_ items: [FilterItem]) -> FilterContext {
        var ctx = FilterContext.empty.bound(to: MiniBank.schema)
        for item in items { ctx = ctx.applying(item, keep: false) }
        return ctx
    }

    @Test func tachBoLocCucBoTrungLanTruyenDayDu() throws {
        let (_, evaluator, store) = makeEngine()
        let cases: [[FilterItem]] = [
            // năm (bảng Dim_Date) + tài khoản (chính bảng fact)
            [FilterItem(column: Col.DimDate.year, values: [.integer(2023)]),
             FilterItem(column: Col.FactTrans.accountKey, values: [.integer(2)])],
            // vùng khách hàng + hai tài khoản
            [FilterItem(column: Col.DimClient.clientRegion, values: [.string("Miền Bắc")]),
             FilterItem(column: Col.FactTrans.accountKey, values: [.integer(1), .integer(2)])],
            // chỉ có mục cục bộ (không có gì để tách): vẫn phải đúng
            [FilterItem(column: Col.FactTrans.accountKey, values: [.integer(3)])],
            // mục cục bộ rỗng giá trị
            [FilterItem(column: Col.DimDate.year, values: [.integer(2024)]),
             FilterItem(column: Col.FactTrans.accountKey, values: [])],
        ]
        for items in cases {
            let ctx = context(items)
            let split = try evaluator.visibleRows(of: MiniBank.Tables.factTrans, in: EvalContext(filter: ctx, row: nil))
            let full = try ctx.visibleRows(in: store, table: MiniBank.Tables.factTrans, overrides: [])
            #expect(split == full, "ngữ cảnh \(items.map(\.column))")
        }
    }

    @Test func visibleValuesCoCacheTrungBanGoc() throws {
        let (_, evaluator, store) = makeEngine()
        let ctx = context([FilterItem(column: Col.DimDate.year, values: [.integer(2024)])])
        for column in [Col.FactTrans.accountKey, Col.DimDate.yearMonth, Col.DimClient.clientRegion] {
            let cached = try evaluator.visibleValues(of: column, in: EvalContext(filter: ctx, row: nil))
            let again = try evaluator.visibleValues(of: column, in: EvalContext(filter: ctx, row: nil))
            let direct = try ctx.visibleValues(of: column, in: store)
            #expect(cached == direct)
            #expect(again == direct)
        }
    }

    @Test func oSongSongTrungTungOTinhRieng() async throws {
        let (engine, _, _) = makeEngine()
        let grouped = try await engine.execute("""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], Dim_Date[month], "avg", [Avg Balance], "amt", [Trans Amount])
            ORDER BY Dim_Date[year], Dim_Date[month]
            """).tables[0]
        #expect(grouped.rows.count > 2)
        for row in grouped.rows {
            guard case .integer(let year) = row[0], case .integer(let month) = row[1] else {
                Issue.record("khoá nhóm không phải số nguyên: \(row[0]), \(row[1])"); continue
            }
            // Fresh engine mỗi ô: không dùng chung cache với lần chạy song song.
            let (single, _, _) = makeEngine()
            let one = try await single.execute("""
                EVALUATE ROW("avg", CALCULATE([Avg Balance], Dim_Date[year] = \(year), Dim_Date[month] = \(month)),
                             "amt", CALCULATE([Trans Amount], Dim_Date[year] = \(year), Dim_Date[month] = \(month)))
                """).tables[0].rows[0]
            #expect(row[2] == one[0], "avg \(year)-\(month)")
            #expect(row[3] == one[1], "amt \(year)-\(month)")
        }
    }

    @Test func huyTruyVanDungOSongSong() async throws {
        let (engine, _, _) = makeEngine()
        let task = Task { try await engine.execute("EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], Dim_Date[month], \"avg\", [Avg Balance])") }
        task.cancel()
        // Huỷ trước hoặc trong lúc chạy: hoặc xong bình thường, hoặc ném .cancelled; không được treo hay sai loại lỗi.
        do { _ = try await task.value } catch let error as DAXError { #expect(error.kind == .cancelled) }
    }
}
