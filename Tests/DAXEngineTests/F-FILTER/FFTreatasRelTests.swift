// TREATAS, USERELATIONSHIP và CROSSFILTER (F-FILTER đợt 3), architecture.md §4.1 và §3.3.
// TREATAS hai cột trên Dim_District (không có quan hệ với Dim_Account): tuple → tập dòng của bảng đích → applying(rows:).
// Đáp án: FFExpected (ffilter_oracle.py).
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FFTreatasRelTests {

    // MARK: TREATAS

    @Test func treatasMotCotLamBoLoc() throws {
        // TREATAS một cột đi qua CORE (addTable): Dim_District[city] thuộc {Hà Nội, TP. Hồ Chí Minh} còn 2 dòng.
        let env = FFEnv()
        #expect(try env.value("CALCULATE ( COUNTROWS ( Dim_District ), TREATAS ( { \"Hà Nội\", \"TP. Hồ Chí Minh\" }, Dim_District[city] ) )")
                == .integer(Int64(FFExpected.districtTuplesMatchHcmHn)))
        // Giá trị không có trong cột đích bị bỏ; Fact_Trans[client_region] = Miền Trung.
        #expect(try env.value("CALCULATE ( [Trans Amount], TREATAS ( { \"Miền Trung\", \"Không có\" }, Fact_Trans[client_region] ) )")
                == .currency(FFExpected.mienTrungAmount))
    }

    @Test func treatasBangHaiCotDemTuple() throws {
        // Bảng nguồn có hai cột: TREATAS trả tập tuple khác nhau (hai tuple, không phải tích Descartes).
        let env = FFEnv()
        let expr = """
        COUNTROWS (
            TREATAS (
                { ( "Hà Nội", "Thành phố Hà Nội" ), ( "TP. Hồ Chí Minh", "Thành phố Hồ Chí Minh" ) },
                Dim_District[city],
                Dim_District[state_name]
            )
        )
        """
        #expect(try env.value(expr) == .integer(2))
    }

    @Test func treatasHaiCotTrenDimDistrictKhongQuanHe() throws {
        // Dim_District không có quan hệ với Dim_Account hay Fact_Trans: bộ lọc tuple chỉ đổi Dim_District.
        let env = FFEnv()
        let district = MiniBank.Tables.dimDistrict
        let cityCol = MiniBank.Columns.DimDistrict.city
        let stateCol = MiniBank.Columns.DimDistrict.stateName

        func rowFilterKhoa(_ text: String) throws -> FilterContext {
            let tuples = try env.table(text)
            let rowFilter = try FilterFunctions.treatasRowFilter(tuples: tuples, targets: [cityCol, stateCol], store: env.store)
            return env.base.applying(rows: rowFilter, keep: false)
        }

        // Hai tuple khớp hai dòng Dim_District (Hà Nội và TP. Hồ Chí Minh).
        let khop = try rowFilterKhoa("""
        { ( "Hà Nội", "Thành phố Hà Nội" ), ( "TP. Hồ Chí Minh", "Thành phố Hồ Chí Minh" ) }
        """)
        #expect(try env.value("COUNTROWS ( Dim_District )", filter: khop) == .integer(Int64(FFExpected.districtTuplesMatchHcmHn)))
        #expect(try env.value("[Trans Amount]", filter: khop) == .currency(FFExpected.totalAmount))
        #expect(try khop.visibleRows(in: env.store, table: district, overrides: []).count == FFExpected.districtTuplesMatchHcmHn)

        // Ghép sai cặp (Hà Nội với tên tiểu bang của Đà Nẵng): không dòng nào khớp.
        let saiCap = try rowFilterKhoa("{ ( \"Hà Nội\", \"Thành phố Đà Nẵng\" ) }")
        // 0 dòng: COUNTROWS là BLANK (Golden Power BI (buổi 1): đếm trên tập rỗng cho BLANK).
        #expect(try env.value("COUNTROWS ( Dim_District )", filter: saiCap) == .blank)

        // Đủ ba tuple thì giữ đủ ba dòng.
        let day = try rowFilterKhoa("""
        { ( "Hà Nội", "Thành phố Hà Nội" ), ( "Đà Nẵng", "Thành phố Đà Nẵng" ), ( "TP. Hồ Chí Minh", "Thành phố Hồ Chí Minh" ) }
        """)
        #expect(try env.value("COUNTROWS ( Dim_District )", filter: day) == .integer(Int64(FFExpected.districtTuplesAll)))
    }

    // MARK: USERELATIONSHIP

    @Test func userRelationshipQuanHeInactive() throws {
        // Mặc định Fact_Complaint lọc tháng 5 theo received_date_key (quan hệ active).
        let env = FFEnv()
        #expect(try env.value("CALCULATE ( COUNTROWS ( Fact_Complaint ), Dim_Date[month] = 5 )")
                == .integer(Int64(FFExpected.complaintReceivedMonth5)))
        // USERELATIONSHIP chọn sent_date_key (quan hệ inactive) thay quan hệ active.
        let sent = """
        CALCULATE (
            COUNTROWS ( Fact_Complaint ),
            USERELATIONSHIP ( Fact_Complaint[sent_date_key], Dim_Date[date_key] ),
            Dim_Date[month] = 5
        )
        """
        #expect(try env.value(sent) == .integer(Int64(FFExpected.complaintSentMonth5)))
        let sentNam2023 = """
        CALCULATE (
            COUNTROWS ( Fact_Complaint ),
            USERELATIONSHIP ( Fact_Complaint[sent_date_key], Dim_Date[date_key] ),
            Dim_Date[year] = 2023
        )
        """
        #expect(try env.value(sentNam2023) == .integer(Int64(FFExpected.complaintSentYear2023)))
    }

    @Test func userRelationshipKhongCoQuanHeLoi() throws {
        let env = FFEnv()
        let expr = """
        CALCULATE (
            COUNTROWS ( Fact_Complaint ),
            USERELATIONSHIP ( Dim_Client[client_region], Dim_Date[month] )
        )
        """
        #expect(ffKindOf { try env.value(expr) } == .runtime)
    }

    // MARK: CROSSFILTER

    @Test func crossFilterNoneTatLanTruyen() throws {
        // Quan hệ Trans_Account bị tắt lan truyền: lọc Dim_Account không tới Fact_Trans nên tổng là toàn bộ.
        let env = FFEnv()
        let debit = try env.filter("Dim_Account", "card_type", [.string("Debit")])
        #expect(try env.value("CALCULATE ( [Trans Amount] )", filter: debit) == .currency(FFExpected.debitAmount))
        let coNone = """
        CALCULATE (
            [Trans Amount],
            CROSSFILTER ( Fact_Trans[account_key], Dim_Account[account_key], NONE )
        )
        """
        #expect(try env.value(coNone, filter: debit) == .currency(FFExpected.totalAmount))
    }

    @Test func crossFilterBothLanNguoc() throws {
        // Một chiều: lọc theo Fact_Trans[client_region] = Miền Bắc không tới Dim_Account nên còn 5 dòng.
        // BOTH: chỉ tài khoản 1 và 4 có giao dịch Miền Bắc, nên còn 2 dòng.
        let env = FFEnv()
        let mienBac = try env.filter("Fact_Trans", "client_region", [.string("Miền Bắc")])
        #expect(try env.value("COUNTROWS ( Dim_Account )", filter: mienBac) == .integer(Int64(FFExpected.dimAccountRowsPlain)))
        let both = """
        CALCULATE (
            COUNTROWS ( Dim_Account ),
            CROSSFILTER ( Fact_Trans[account_key], Dim_Account[account_key], BOTH )
        )
        """
        #expect(try env.value(both, filter: mienBac) == .integer(Int64(FFExpected.dimAccountRowsMienBacBoth)))
    }
}
