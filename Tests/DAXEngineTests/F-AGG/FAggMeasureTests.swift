// WP F-AGG (đợt 3): measure "Avg Balance" của MiniBank qua DAXEngine.evaluate, và ca nặng
// SUMX trên Fact_Trans qua measure có CALCULATE. Đáp án: fagg_expected.py (Python stdlib).
//
// Ghi chú về kiểu: Python cho trung bình 1 594 294 000 / 6 = 265 716 333,33 (đơn vị ×10^4). Measure trả về
// currency (làm tròn về 265 716 333 đơn vị ×10^4). MiniBankExpected ghi `.double(265716333.33…)` nhưng `.double`
// của engine là đơn vị thực, nên test này so sánh theo đơn vị ×10^4 với sai số dưới nửa đơn vị.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FAggMeasureTests {

    private func engine() -> DAXEngine {
        DAXEngine(store: MiniBank.makeStore(), catalog: Catalog(
            schema: MiniBank.schema,
            measures: MiniBank.measures.map { ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression) }))
    }

    @Test func avgBalanceMiniBankKhopDapAn() async throws {
        let value = try await engine().evaluate(measure: "Avg Balance", table: "Fact_Trans", filters: [])
        // Đáp án Python: 265 716 333,33… đơn vị ×10^4; làm tròn về 265 716 333.
        #expect(value == .currency(265_716_333))
        guard case .currency(let raw) = value else {
            Issue.record("Avg Balance không phải currency: \(value)")
            return
        }
        #expect(abs(Double(raw) - 265_716_333.33333334) < 0.5)
    }

    @Test func sumxAvgBalanceTrenFactTransLaTongSoDuDongFact() throws {
        // Mỗi dòng fact được transition thành đúng một dòng, nên Avg Balance của dòng là số dư của dòng đó.
        // Tổng balance_after của 40 dòng = 7 971 533 000 (đơn vị ×10^4). Đo thời gian để ghi nhận chi phí.
        let env = FAggEnv.minibank()
        let expr = try Binder.bind(try parseExpression("SUMX ( Fact_Trans, [Avg Balance] )"), catalog: env.catalog)
        var result: Value = .blank
        let elapsed = try ContinuousClock().measure {
            result = try env.evaluator.scalar(expr, in: EvalContext(filter: env.base, row: nil))
        }
        print("[F-AGG đo] SUMX(Fact_Trans, [Avg Balance]) 40 dòng: \(elapsed)")
        #expect(result == .currency(7_971_533_000))
    }

    @Test func sumxTransCountTrenFactTransCachePhucVu() throws {
        // Measure có CALCULATE ngầm được lặp 40 lần. Các dòng khác nhau nên mỗi lần là một khoá cache,
        // lặp lại cùng biểu thức phải trúng cache của measure (không tính lại).
        let env = FAggEnv.minibank()
        let expr = try Binder.bind(try parseExpression("SUMX ( Fact_Trans, [Trans Count] )"), catalog: env.catalog)
        let first = try env.evaluator.scalar(expr, in: EvalContext(filter: env.base, row: nil))
        let before = env.evaluator.cache.measures.statistics.hits
        let second = try env.evaluator.scalar(expr, in: EvalContext(filter: env.base, row: nil))
        let after = env.evaluator.cache.measures.statistics.hits
        #expect(first == .integer(40))
        #expect(second == .integer(40))
        #expect(after > before)
    }
}
