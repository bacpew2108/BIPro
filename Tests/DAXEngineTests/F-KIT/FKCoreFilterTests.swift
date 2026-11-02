// REMOVEFILTERS và KEEPFILTERS (F-KIT lõi, đợt 2). Gọi trực tiếp thân hàm (CallFrame) và qua CALCULATE.
// Đáp án: MiniBankExpected (tổng 2023 = 566230700; tổng toàn bộ = 1254298000) và script Python độc lập
// (8 dòng tài khoản 3 'No Card').
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FKCoreFilterTests {

    /// Thân `.modifier` đã đăng ký cho một hàm.
    private func modifierBody(_ ten: String) throws -> FunctionSpec.ModifierBody {
        guard let spec = FunctionRegistry.byName[ten], case .modifier(let body) = spec.impl else {
            throw DAXError(.unsupportedFunction, "\(ten) không phải hàm bộ sửa đổi")
        }
        return body
    }

    // MARK: REMOVEFILTERS

    @Test func removeFiltersBangXoaExpandedTable() throws {
        let env = FKCoreEnv()
        let body = try modifierBody("REMOVEFILTERS")
        let dimDate = MiniBank.Tables.dimDate
        let frame = CallFrame(args: [.table(dimDate)], ctx: EvalContext(filter: env.base), eval: env.evaluator)
        let modifiers = try body(frame)
        guard case .removeExpandedTable(let table)? = modifiers.first, modifiers.count == 1 else {
            Issue.record("REMOVEFILTERS(bảng) phải ra .removeExpandedTable")
            return
        }
        #expect(table == dimDate)
    }

    @Test func removeFiltersKhongDoiSoXoaHet() throws {
        let body = try modifierBody("REMOVEFILTERS")
        let frame = CallFrame(args: [], ctx: EvalContext(), eval: Evaluator(store: MiniBank.makeStore(), catalog: Catalog(schema: MiniBank.schema)))
        let modifiers = try body(frame)
        guard case .removeAll? = modifiers.first, modifiers.count == 1 else {
            Issue.record("REMOVEFILTERS() phải ra .removeAll")
            return
        }
    }

    @Test func removeFiltersCotXoaDungCot() throws {
        let env = FKCoreEnv()
        let body = try modifierBody("REMOVEFILTERS")
        let year = MiniBank.Columns.DimDate.year
        let frame = CallFrame(args: [.column(year)], ctx: EvalContext(filter: env.base), eval: env.evaluator)
        let modifiers = try body(frame)
        guard case .removeColumns(let columns)? = modifiers.first else {
            Issue.record("REMOVEFILTERS(cột) phải ra .removeColumns")
            return
        }
        #expect(columns == [year])
    }

    @Test func removeFiltersApDungXoaBoLocBang() throws {
        let env = FKCoreEnv()
        let nam = try env.filter("Dim_Date", "year", [.integer(2023)])
        let body = try modifierBody("REMOVEFILTERS")
        let frame = CallFrame(args: [.table(MiniBank.Tables.dimDate)], ctx: EvalContext(filter: nam), eval: env.evaluator)
        let sau = nam.applying(try body(frame))
        #expect(sau.values(for: MiniBank.Columns.DimDate.year) == nil)
    }

    @Test func calculateRemoveFiltersDimDateRaTongDayDu() throws {
        let env = FKCoreEnv()
        let nam = try env.filter("Dim_Date", "year", [.integer(2023)])
        #expect(try env.value("SUM ( Fact_Trans[amount] )", filter: nam) == .currency(566_230_700))
        #expect(try env.value("CALCULATE ( SUM ( Fact_Trans[amount] ), REMOVEFILTERS ( Dim_Date ) )", filter: nam)
                == .currency(1_254_298_000))
    }

    @Test func calculateRemoveFiltersDimAccountBoQuaLanTruyen() throws {
        let env = FKCoreEnv()
        let haNoi = try env.filter("Dim_Account", "branch_city", [.string("Hà Nội")])
        #expect(try env.value("CALCULATE ( SUM ( Fact_Trans[amount] ), REMOVEFILTERS ( Dim_Account ) )", filter: haNoi)
                == .currency(1_254_298_000))
        #expect(try env.value("CALCULATE ( SUM ( Fact_Trans[amount] ), REMOVEFILTERS ( Dim_Account[branch_city] ) )",
                              filter: haNoi) == .currency(1_254_298_000))
    }

    @Test func calculateRemoveFiltersKhongDoiSoXoaHet() throws {
        let env = FKCoreEnv()
        let nam = try env.filter("Dim_Date", "year", [.integer(2024)])
        #expect(try env.value("CALCULATE ( SUM ( Fact_Trans[amount] ), REMOVEFILTERS () )", filter: nam)
                == .currency(1_254_298_000))
    }

    // MARK: KEEPFILTERS

    @Test func keepFiltersGiaoVoiBoLocHienCo() throws {
        let env = FKCoreEnv()
        let cardType = MiniBank.Columns.DimAccount.cardType
        // Bộ lọc ngoài: Debit và No Card. Vị ngữ: thẻ = No Card. Giao cho ra No Card.
        let ngoai = FilterContext(items: [FilterItem(column: cardType, values: [.string("Debit"), .string("No Card")])])
            .bound(to: env.store.schema)
        let body = try modifierBody("KEEPFILTERS")
        let predicate = try Binder.bind(try parseExpression("Dim_Account[card_type] = \"No Card\""), catalog: env.catalog)
        let frame = CallFrame(args: [predicate], ctx: EvalContext(filter: ngoai), eval: env.evaluator)
        let modifiers = try body(frame)
        guard case .filter(let item, let keep)? = modifiers.first, modifiers.count == 1 else {
            Issue.record("KEEPFILTERS phải ra .filter")
            return
        }
        #expect(keep)
        #expect(item == FilterItem(column: cardType, values: [.string("No Card")]))
    }

    @Test func calculateKeepFiltersGiaoKetQuaRong() throws {
        let env = FKCoreEnv()
        let cardType = MiniBank.Columns.DimAccount.cardType
        let debitCredit = FilterContext(items: [FilterItem(column: cardType, values: [.string("Debit"), .string("Credit")])])
            .bound(to: env.store.schema)
        // Không KEEPFILTERS: No Card ghi đè Debit và Credit, nên lấy 8 dòng tài khoản 3.
        #expect(try env.count("CALCULATE ( COUNTROWS ( Fact_Trans ), Dim_Account[card_type] = \"No Card\" )",
                              filter: debitCredit) == 8)
        // Có KEEPFILTERS: giao rỗng với {Debit, Credit}, không dòng nào: COUNTROWS là BLANK
        // (golden Power BI, buổi 1: đếm trên tập rỗng cho BLANK).
        #expect(try env.value("CALCULATE ( COUNTROWS ( Fact_Trans ), KEEPFILTERS ( Dim_Account[card_type] = \"No Card\" ) )",
                              filter: debitCredit) == .blank)
    }

    @Test func calculateKeepFiltersGiuGiaTriChung() throws {
        let env = FKCoreEnv()
        let cardType = MiniBank.Columns.DimAccount.cardType
        let debitNoCard = FilterContext(items: [FilterItem(column: cardType, values: [.string("Debit"), .string("No Card")])])
            .bound(to: env.store.schema)
        #expect(try env.count("CALCULATE ( COUNTROWS ( Fact_Trans ), KEEPFILTERS ( Dim_Account[card_type] = \"No Card\" ) )",
                              filter: debitNoCard) == 8)
    }
}
