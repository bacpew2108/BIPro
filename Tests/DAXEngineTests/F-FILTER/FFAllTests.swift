// ALLSELECTED, ALL, ALLNOBLANKROW và ALLEXCEPT (F-FILTER đợt 3), architecture.md §4.5. Đáp án: FFExpected (Python).
// Kịch bản ALLSELECTED chạy qua SUMMARIZECOLUMNS (đẩy shadow) và qua FILTER (một iterator).
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FFAllTests {

    /// Bảng nhóm theo card_type có slicer năm 2024 (ALL(Dim_Date[year]) lọc năm 2024 như bộ lọc bảng của truy vấn).
    private let slicer2024 = """
    FILTER ( ALL ( Dim_Date[year] ), Dim_Date[year] = 2024 )
    """

    @Test func shareALLSELECTEDKhongSlicer() async throws {
        let env = FFEnv()
        let rows = try await env.query("""
        EVALUATE
        SUMMARIZECOLUMNS (
            Dim_Account[card_type],
            "Trans Amount", [Trans Amount],
            "Share", DIVIDE ( [Trans Amount], CALCULATE ( [Trans Amount], ALLSELECTED ( Dim_Account[card_type] ) ) )
        )
        """)
        #expect(rows.rows.count == 4)
        for row in rows.rows {
            let nhan = ffNhan(row[0])
            #expect(row[1] == .currency(FFExpected.cardTotal[nhan] ?? -999), "tổng của \(nhan)")
            guard case .double(let share) = row[2], let dung = FFExpected.shareAll[nhan] else {
                Issue.record("tỉ lệ của \(nhan) phải là số thực")
                continue
            }
            #expect(abs(share - dung) < 1e-12, "tỉ lệ của \(nhan): \(share) so với \(dung)")
        }
    }

    @Test func shareALLSELECTEDCoSlicerNam2024() async throws {
        let env = FFEnv()
        let rows = try await env.query("""
        EVALUATE
        SUMMARIZECOLUMNS (
            Dim_Account[card_type],
            \(slicer2024),
            "Trans Amount", [Trans Amount],
            "Share", DIVIDE ( [Trans Amount], CALCULATE ( [Trans Amount], ALLSELECTED ( Dim_Account[card_type] ) ) )
        )
        """)
        #expect(rows.rows.count == 4)
        for row in rows.rows {
            let nhan = ffNhan(row[0])
            #expect(row[1] == .currency(FFExpected.cardTotal2024[nhan] ?? -999), "tổng 2024 của \(nhan)")
            guard case .double(let share) = row[2], let dung = FFExpected.share2024[nhan] else {
                Issue.record("tỉ lệ 2024 của \(nhan) phải là số thực")
                continue
            }
            #expect(abs(share - dung) < 1e-12, "tỉ lệ 2024 của \(nhan): \(share) so với \(dung)")
        }
    }

    @Test func allSelectedCoNgoaiGiuSlicerNam2024() async throws {
        // ALLSELECTED() không đối số trong CALCULATE: bỏ bộ lọc của ô (card_type) nhưng giữ slicer năm 2024.
        let env = FFEnv()
        let rows = try await env.query("""
        EVALUATE
        SUMMARIZECOLUMNS (
            Dim_Account[card_type],
            \(slicer2024),
            "Tong", CALCULATE ( [Trans Amount], ALLSELECTED () )
        )
        """)
        #expect(rows.rows.count == 4)
        for row in rows.rows {
            #expect(row[1] == .currency(FFExpected.total2024), "ALLSELECTED() phải giữ slicer năm 2024 cho \(ffNhan(row[0]))")
        }
    }

    @Test func allSelectedBangDemDongTheoShadow() async throws {
        // COUNTROWS(ALLSELECTED(Fact_Trans)) trong ô card_type: giữ bộ lọc card_type của ô (bảng khác) và slicer năm 2024.
        let env = FFEnv()
        let rows = try await env.query("""
        EVALUATE
        SUMMARIZECOLUMNS (
            Dim_Account[card_type],
            \(slicer2024),
            "So giao dich", COUNTROWS ( ALLSELECTED ( Fact_Trans ) )
        )
        """)
        #expect(rows.rows.count == 4)
        for row in rows.rows {
            let nhan = ffNhan(row[0])
            #expect(row[1] == .integer(FFExpected.cardCount2024[nhan] ?? -999), "số giao dịch 2024 của \(nhan)")
        }
    }

    @Test func iteratorFILTERTrenALLSELECTED() async throws {
        // FILTER(ALLSELECTED(card_type), tổng >= 35000) đếm số nhóm card_type có tổng lớn; mỗi ô đều nhận cùng kết quả.
        let env = FFEnv()
        let rows = try await env.query("""
        EVALUATE
        SUMMARIZECOLUMNS (
            Dim_Account[card_type],
            "So nhom lon", COUNTROWS ( FILTER ( ALLSELECTED ( Dim_Account[card_type] ), [Trans Amount] >= 35000 ) )
        )
        """)
        #expect(rows.rows.count == 4)
        for row in rows.rows {
            #expect(row[1] == .integer(Int64(FFExpected.groupsAmountAtLeast35000)), "ô \(ffNhan(row[0]))")
        }
    }

    @Test func allBangBoMoiBoLoc() throws {
        let env = FFEnv()
        let nam = try env.filter("Dim_Date", "year", [.integer(2023)])
        // ALL(Dim_Date) trong biểu thức bảng: mọi ngày, bỏ bộ lọc năm 2023.
        #expect(try env.value("COUNTROWS ( ALL ( Dim_Date ) )", filter: nam) == .integer(Int64(FFExpected.allDimDate)))
        // ALL(Dim_Account) có dòng BLANK ảo (FK 99); ALLNOBLANKROW bỏ dòng đó.
        #expect(try env.value("COUNTROWS ( ALL ( Dim_Account ) )") == .integer(Int64(FFExpected.allDimAccount)))
        #expect(try env.value("COUNTROWS ( ALLNOBLANKROW ( Dim_Account ) )") == .integer(Int64(FFExpected.allNoBlankRowDimAccount)))
        #expect(try env.value("COUNTROWS ( ALLNOBLANKROW ( Dim_Account ) )", filter: nam)
                == .integer(Int64(FFExpected.allNoBlankRowDimAccount)))
    }

    @Test func allCotGomCaGiaTriBlank() throws {
        let env = FFEnv()
        let debit = try env.filter("Dim_Account", "card_type", [.string("Debit")])
        // ALL(cột) gồm BLANK (dòng BLANK ảo của Dim_Account) và bỏ qua bộ lọc của ngữ cảnh.
        #expect(try env.value("COUNTROWS ( ALL ( Dim_Account[branch_city] ) )") == .integer(Int64(FFExpected.allBranchCity)))
        #expect(try env.value("COUNTROWS ( ALL ( Dim_Account[branch_city] ) )", filter: debit)
                == .integer(Int64(FFExpected.allBranchCity)))
        #expect(try env.value("COUNTROWS ( ALL ( Dim_Client[client_region] ) )") == .integer(Int64(FFExpected.allClientRegion)))
    }

    @Test func calculateALLDimAccountBoLocTheoCard() throws {
        // ALL(Dim_Account) trong CALCULATE: CORE xoá expanded table, nên bộ lọc card_type biến mất.
        let env = FFEnv()
        let debit = try env.filter("Dim_Account", "card_type", [.string("Debit")])
        #expect(try env.value("CALCULATE ( [Trans Amount], ALL ( Dim_Account ) )", filter: debit)
                == .currency(FFExpected.totalAmount))
        #expect(try env.value("CALCULATE ( [Trans Amount] )", filter: debit) == .currency(FFExpected.debitAmount))
    }

    @Test func allExceptGiuCotDuocLoc() throws {
        // ALLEXCEPT(Dim_Account, card_type): bỏ bộ lọc branch_city, giữ bộ lọc card_type (Debit là tài khoản 1 và 4).
        let env = FFEnv()
        let expr = """
        CALCULATE (
            COUNTROWS ( ALLEXCEPT ( Dim_Account, Dim_Account[card_type] ) ),
            Dim_Account[card_type] = "Debit",
            Dim_Account[branch_city] = "Đà Nẵng"
        )
        """
        #expect(try env.value(expr) == .integer(Int64(FFExpected.debitAccounts)))
        let thuong = """
        CALCULATE (
            COUNTROWS ( Dim_Account ),
            Dim_Account[card_type] = "Debit",
            Dim_Account[branch_city] = "Đà Nẵng"
        )
        """
        // 0 dòng khớp: COUNTROWS là BLANK (Golden Power BI (buổi 1): đếm trên tập rỗng cho BLANK).
        #expect(try env.value(thuong) == .blank)
    }

    @Test func duongRowSetKhopBangVatChatHoa() throws {
        // physicalRows (dùng cho lặp không vật chất hoá) cho cùng số dòng với đường bảng.
        let env = FFEnv()
        let nam = try env.filter("Dim_Date", "year", [.integer(2024)])
        let dimAccount: [BoundExpr?] = [.table(MiniBank.Tables.dimAccount)]
        let factTrans: [BoundExpr?] = [.table(MiniBank.Tables.factTrans)]
        let ctx = EvalContext(filter: env.base)
        #expect(try FilterFunctions.physicalRows("ALL", args: dimAccount, ctx: ctx, evaluator: env.evaluator)?.rows.count
                == FFExpected.allDimAccount)
        #expect(try FilterFunctions.physicalRows("ALLNOBLANKROW", args: dimAccount, ctx: ctx, evaluator: env.evaluator)?.rows.count
                == FFExpected.allNoBlankRowDimAccount)
        // ALLSELECTED(Fact_Trans) không có shadow: giữ slicer năm 2024 (20 giao dịch).
        let ctxNam = EvalContext(filter: nam)
        let selected = try FilterFunctions.physicalRows("ALLSELECTED", args: factTrans, ctx: ctxNam, evaluator: env.evaluator)
        #expect(selected?.rows.count == 20)
        // ALL(cột) không phải dạng bảng vật lý: trả nil để dùng đường bảng.
        let cot: [BoundExpr?] = [.column(MiniBank.Columns.DimAccount.cardType)]
        #expect(try FilterFunctions.physicalRows("ALL", args: cot, ctx: ctx, evaluator: env.evaluator) == nil)
        // Đường bảng (materialize) cho cùng dòng.
        #expect(try env.table("ALLSELECTED ( Fact_Trans )", filter: nam).rows.count == 20)
    }

    @Test func allSelectedNgoaiCalculateKhongPhaiBang() throws {
        // ALLSELECTED() không có đối số không dùng được như bảng.
        let env = FFEnv()
        #expect(ffKindOf { try env.value("COUNTROWS ( ALLSELECTED () )") } == .typeMismatch)
    }
}
