// Kiểm tra contract của DAXEngine ở đợt 0 (lead): registry không trùng tên, stub báo đúng lỗi.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct DAXContractSmokeTests {
    @Test func registryHasNoDuplicateNames() {
        let names = FunctionRegistry.all.map(\.name)
        #expect(Set(names).count == names.count, "trùng tên hàm giữa các họ")
    }

    @Test func registryCoversRequiredFunctions() {
        // Hàm bắt buộc của mốc 119 measure (scope.md §8.1), kèm ba hàm thêm cho 168 measure.
        let required = ["SUM", "AVERAGE", "COUNTROWS", "DISTINCTCOUNT", "MAX", "SUMX", "AVERAGEX", "MINX", "MAXX",
                        "CONCATENATEX", "PERCENTILEX.INC", "CALCULATE", "CALCULATETABLE", "FILTER", "REMOVEFILTERS",
                        "KEEPFILTERS", "ALLSELECTED", "TREATAS", "ISBLANK", "ISFILTERED", "HASONEVALUE",
                        "SELECTEDVALUE", "SAMEPERIODLASTYEAR", "IF", "SWITCH", "TRUE", "COALESCE", "DIVIDE", "INT",
                        "MOD", "ABS", "FORMAT", "DATE", "YEAR", "MONTH", "DATEDIFF", "VALUES", "SUMMARIZE",
                        "ADDCOLUMNS", "TOPN", "CROSSJOIN", "RELATED", "BLANK", "ALL", "RANKX", "USERELATIONSHIP"]
        let registered = Set(FunctionRegistry.all.map(\.name))
        #expect(registered.isSuperset(of: required), "thiếu: \(Set(required).subtracting(registered).sorted())")
    }

    @Test func pendingFunctionReportsUnsupported() {
        // Kiểm chính stub `pending`: mọi hàm chưa cài dùng đúng cơ chế này. Không dùng hàm thật vì đã có thân.
        guard case .scalar(let body) = FunctionSpec.pending("STUB", [], .scalar).impl else {
            Issue.record("pending(.scalar) phải là hàm vô hướng")
            return
        }
        let frame = CallFrame(args: [], ctx: EvalContext(), eval: Evaluator())
        do {
            _ = try body(frame)
            Issue.record("stub không được trả giá trị")
        } catch {
            #expect(error.kind == .unsupportedFunction)
        }
    }

    /// Từ đợt 2, execute chạy thật: ROW không cần bảng nào.
    @Test func executeRunsRowWithoutTables() async throws {
        let schema = ModelSchema(culture: "en-US", tables: [], relationships: [])
        let source = InMemoryColumnSource(schema: schema, rowCounts: [:], columns: [:])
        let engine = DAXEngine(store: ColumnStore(source: source))
        let result = try await engine.execute("EVALUATE ROW(\"x\", 1 + 2)")
        #expect(result.tables.count == 1)
        #expect(result.tables[0].rows == [[.integer(3)]])
    }

    /// Measure của model đi qua catalog và Evaluator. Dùng measure chỉ có toán tử: COUNTROWS (F-KIT lõi)
    /// chưa được cài đặt ở đợt 2a, nên chưa thể kiểm measure MiniBank "Trans Count" ở đây.
    @Test func engineEvaluatesModelMeasureThroughCatalog() async throws {
        let catalog = Catalog(schema: MiniBank.schema, measures: [
            ModelMeasureInput(table: "Fact_Trans", name: "Two", expression: "1 + 1"),
        ])
        let engine = DAXEngine(store: MiniBank.makeStore(), catalog: catalog)
        let value = try await engine.evaluate(measure: "Two", table: nil, filters: [])
        #expect(value == .integer(2))
    }
}
