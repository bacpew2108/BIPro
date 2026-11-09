// BatchedShapeTests.swift
// E3-cấu-trúc (T007): nhận mẫu thân vòng lặp. Mẫu đúng được nhận; các biến thể gần giống bị từ chối
// (hợp đồng C3: nhận mẫu bảo thủ, nghi ngờ thì rơi về đường cũ).

import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct BatchedShapeTests {
    private typealias Col = MiniBank.Columns

    private func shape(ofBody body: String, iterator: String = "AVERAGEX") throws -> BatchedShape? {
        let measure = ModelMeasureInput(table: "Fact_Trans", name: "M",
                                        expression: "\(iterator) ( VALUES ( Fact_Trans[account_key] ), \(body) )")
        let catalog = Catalog(schema: MiniBank.schema, measures: [measure])
        let evaluator = Evaluator(store: MiniBank.makeStore(), catalog: catalog)
        let found = try #require(catalog.measure(named: "M", table: nil))
        let bound = try Binder.bindMeasure(found.id, catalog: catalog)
        guard case .call(_, let args) = bound, args.count == 2, let bodyExpr = args[1] else {
            Issue.record("không bind được \(iterator)")
            return nil
        }
        return try BatchedIteration.recognize(bodyExpr, evaluator: evaluator)
    }

    // MARK: Mẫu đúng

    @Test func nhanMauHaiBuocCuaAvgBalance() throws {
        let s = try #require(try shape(ofBody: """
            VAR t = CALCULATE ( MAX ( Fact_Trans[date_key] ), REMOVEFILTERS ( Dim_Date ) )
            RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), REMOVEFILTERS ( Dim_Date ), Fact_Trans[date_key] = t )
            """))
        #expect(s.first.aggregate == .max)
        #expect(s.first.column == Col.FactTrans.dateKey)
        #expect(s.second?.aggregate == .max)
        #expect(s.second?.column == Col.FactTrans.balanceAfter)
        #expect(s.modifiers.count == 1)
    }

    @Test func nhanMauMotBuoc() throws {
        let max = try #require(try shape(ofBody: "CALCULATE ( MAX ( Fact_Trans[balance_after] ), REMOVEFILTERS ( Dim_Date ) )"))
        #expect(max.first.aggregate == .max)
        #expect(max.second == nil)
        let min = try #require(try shape(ofBody: "CALCULATE ( MIN ( Fact_Trans[amount] ) )", iterator: "SUMX"))
        #expect(min.first.aggregate == .min)
        #expect(min.first.column == Col.FactTrans.amount)
        #expect(min.modifiers.isEmpty)
    }

    @Test func nhanMauHaiBuocMinVaBuocHaiLaMin() throws {
        let s = try #require(try shape(ofBody: """
            VAR t = CALCULATE ( MIN ( Fact_Trans[date_key] ) )
            RETURN CALCULATE ( MIN ( Fact_Trans[amount] ), Fact_Trans[date_key] = t )
            """, iterator: "MAXX"))
        #expect(s.first.aggregate == .min)
        #expect(s.second?.aggregate == .min)
        #expect(s.modifiers.isEmpty)
    }

    // MARK: Biến thể phải bị từ chối

    private let rejected: [(String, String)] = [
        ("KEEPFILTERS trong bộ lọc",
         """
         VAR t = CALCULATE ( MAX ( Fact_Trans[date_key] ) )
         RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), KEEPFILTERS ( Fact_Trans[date_key] = t ) )
         """),
        ("bộ lọc so với cột khác của dòng",
         "CALCULATE ( MAX ( Fact_Trans[balance_after] ), Fact_Trans[date_key] = Fact_Trans[amount] )"),
        ("t lấy từ cột khác với cột lọc",
         """
         VAR t = CALCULATE ( MAX ( Fact_Trans[amount] ) )
         RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), Fact_Trans[date_key] = t )
         """),
        ("USERELATIONSHIP",
         "CALCULATE ( MAX ( Fact_Trans[balance_after] ), USERELATIONSHIP ( Fact_Trans[date_key], Dim_Date[date_key] ) )"),
        ("hàm gộp ngoài MAX/MIN",
         "CALCULATE ( SUM ( Fact_Trans[balance_after] ), REMOVEFILTERS ( Dim_Date ) )"),
        ("hai vô hướng của MAX",
         "CALCULATE ( MAX ( Fact_Trans[balance_after], 1 ) )"),
        ("không phải CALCULATE",
         "Fact_Trans[balance_after]"),
        ("REMOVEFILTERS theo cột",
         "CALCULATE ( MAX ( Fact_Trans[balance_after] ), REMOVEFILTERS ( Fact_Trans[account_key] ) )"),
        ("bộ lọc hằng số",
         "CALCULATE ( MAX ( Fact_Trans[balance_after] ), Fact_Trans[date_key] = 20240101 )"),
        ("biểu thức trên giá trị gộp",
         "CALCULATE ( MAX ( Fact_Trans[balance_after] ) ) + 1"),
        ("hai bước có REMOVEFILTERS khác nhau",
         """
         VAR t = CALCULATE ( MAX ( Fact_Trans[date_key] ), REMOVEFILTERS ( Dim_Date ) )
         RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), Fact_Trans[date_key] = t )
         """),
        ("bước đầu cũng lọc theo t",
         """
         VAR t = CALCULATE ( MAX ( Fact_Trans[date_key] ), Fact_Trans[date_key] = 1 )
         RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), Fact_Trans[date_key] = t )
         """),
    ]

    @Test func tuChoiBienTheGanGiong() throws {
        for (name, body) in rejected {
            let s = try shape(ofBody: body)
            #expect(s == nil, "\(name): phải bị từ chối")
        }
    }
}

