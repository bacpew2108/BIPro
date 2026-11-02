// Kiểm tra cache measure và cache tập dòng (CORE, đợt 2), architecture.md §7.4.
// Đếm lần chạy: thân SUM tăng `CallCounter`. Lần đánh giá thứ hai cùng khoá không chạy thân nữa.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct CORECacheTests {
    @Test func danhGiaHaiLanCungMeasureChoKetQuaGiongNhauChiChayMotLan() throws {
        let env = CoreEnvironment()
        let first = try evaluateText("[Trans Amount]", in: env)
        let runsAfterFirst = env.counter.value
        let second = try evaluateText("[Trans Amount]", in: env)
        #expect(first == second)
        #expect(first == .currency(MiniBankExpected.totalAmount))
        #expect(runsAfterFirst == 1)
        #expect(env.counter.value == runsAfterFirst)
        #expect(env.cache.measures.statistics.hits >= 1)
    }

    @Test func boLocKhacThiKhongDungChungKetQua() throws {
        let env = CoreEnvironment()
        _ = try evaluateText("[Trans Amount]", in: env)
        let filtered = try evaluateText("CALCULATE ( [Trans Amount], Dim_Date[year] = 2024 )", in: env)
        #expect(filtered == .currency(688_067_300))
        #expect(env.counter.value == 2)
    }

    @Test func cacheDungChungGiuaCacEvaluator() throws {
        let env = CoreEnvironment()
        _ = try evaluateText("[Trans Amount]", in: env)
        let otherEvaluator = Evaluator(store: env.store, catalog: env.catalog, cache: env.cache,
                                       functions: coreTestFunctions(counter: env.counter))
        let expr = try Binder.bind(try parseExpression("[Trans Amount]"), catalog: env.catalog)
        let value = try otherEvaluator.scalar(expr, in: EvalContext(filter: env.baseFilter, row: nil))
        #expect(value == .currency(MiniBankExpected.totalAmount))
        #expect(env.counter.value == 1)
    }

    @Test func cacheTrongContextTransitionCoKhoaRieng() throws {
        // Sáu khoá tài khoản khác nhau: lần đầu chạy thân 6 lần; lần hai không chạy thêm.
        let env = CoreEnvironment()
        let text = "SUMX ( VALUES ( Fact_Trans[account_key] ), [Trans Amount] )"
        let first = try evaluateText(text, in: env)
        let runsAfterFirst = env.counter.value
        let second = try evaluateText(text, in: env)
        #expect(first == .currency(MiniBankExpected.totalAmount))
        #expect(second == first)
        #expect(runsAfterFirst == 6)
        #expect(env.counter.value == runsAfterFirst)
    }

    @Test func xoaCacheBatChayLai() throws {
        let env = CoreEnvironment()
        _ = try evaluateText("[Trans Amount]", in: env)
        env.cache.clear()
        _ = try evaluateText("[Trans Amount]", in: env)
        #expect(env.counter.value == 2)
    }

    @Test func varTableTrongVongLapKhongMaterialize() throws {
        // Lặp trên bảng vật lý qua SUMX: không có TableValue nào của Fact_Trans được tạo.
        let env = CoreEnvironment()
        let value = try evaluateText("SUMX ( Fact_Trans, Fact_Trans[amount] )", in: env)
        #expect(value == .currency(MiniBankExpected.totalAmount))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func chuTrinhMeasureBaoLoiKhongDeQuyVoHan() throws {
        // DAX cấm chu trình measure: Vòng A gọi Vòng B, Vòng B gọi lại Vòng A.
        let env = CoreEnvironment(extraMeasures: [
            ModelMeasureInput(table: "Fact_Trans", name: "Vòng A", expression: "[Vòng B] + 1"),
            ModelMeasureInput(table: "Fact_Trans", name: "Vòng B", expression: "[Vòng A] + 1"),
        ])
        do {
            _ = try evaluateText("[Vòng A]", in: env)
            Issue.record("kỳ vọng lỗi chu trình")
        } catch let error as DAXError {
            #expect(error.kind == .circularDependency)
        }
    }
}
