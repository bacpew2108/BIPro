// ISFILTERED, ISCROSSFILTERED, HASONEVALUE và SELECTEDVALUE (F-FILTER đợt 3), architecture.md §4.6.
// Đáp án: cấu trúc bộ lọc của MiniBank (xem FFSupport.swift) và ffilter_oracle.py (tập dòng, BLANK).
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FFInformationTests {

    // MARK: ISFILTERED

    @Test func isFilteredBoLocTrucTiep() throws {
        let env = FFEnv()
        #expect(try env.value("CALCULATE ( ISFILTERED ( Dim_Date[year] ), Dim_Date[year] = 2023 )") == .boolean(true))
        // Cột khác của cùng bảng không được lọc trực tiếp.
        #expect(try env.value("CALCULATE ( ISFILTERED ( Dim_Date[year] ), Dim_Date[month] = 5 )") == .boolean(false))
        // Bảng được lọc khi có một cột của bảng bị lọc.
        #expect(try env.value("CALCULATE ( ISFILTERED ( Dim_Date ), Dim_Date[month] = 5 )") == .boolean(true))
    }

    @Test func isFilteredKhongTinhBoLocQuaQuanHe() throws {
        let env = FFEnv()
        // Lọc Dim_Date không phải bộ lọc trực tiếp của Fact_Trans.
        #expect(try env.value("CALCULATE ( ISFILTERED ( Fact_Trans[client_region] ), Dim_Date[year] = 2023 )") == .boolean(false))
        #expect(try env.value("CALCULATE ( ISFILTERED ( Fact_Trans ), Dim_Date[year] = 2023 )") == .boolean(false))
        // Lọc Dim_Client không phải bộ lọc trực tiếp của Dim_Account.
        #expect(try env.value("CALCULATE ( ISFILTERED ( Dim_Account[card_type] ), Dim_Client[client_region] = \"Miền Bắc\" )")
                == .boolean(false))
    }

    @Test func isFilteredBoLocTuBangFILTER() throws {
        let env = FFEnv()
        // FILTER(Fact_Trans, …) là bộ lọc theo bảng: mọi cột của bảng đó được coi là bị lọc (chưa chiếu).
        let expr = """
        CALCULATE (
            ISFILTERED ( Fact_Trans[amount] ),
            FILTER ( Fact_Trans, Fact_Trans[client_region] = "Miền Bắc" )
        )
        """
        #expect(try env.value(expr) == .boolean(true))
        #expect(try env.value("ISFILTERED ( Fact_Trans )") == .boolean(false))
    }

    // MARK: ISCROSSFILTERED

    @Test func isCrossFilteredTuBangKhac() throws {
        let env = FFEnv()
        // Lọc năm 2023 của Dim_Date lan tới Fact_Trans.
        #expect(try env.value("CALCULATE ( ISCROSSFILTERED ( Fact_Trans[amount] ), Dim_Date[year] = 2023 )") == .boolean(true))
        // Dim_Account được Dim_Client lọc (một → nhiều).
        #expect(try env.value("CALCULATE ( ISCROSSFILTERED ( Dim_Account[card_type] ), Dim_Client[client_region] = \"Miền Bắc\" )")
                == .boolean(true))
    }

    @Test func isCrossFilteredKhongTinhBoLocTrucTiep() throws {
        let env = FFEnv()
        // Bộ lọc trực tiếp trên chính bảng không tính là cross-filter.
        #expect(try env.value("CALCULATE ( ISCROSSFILTERED ( Dim_Date[year] ), Dim_Date[year] = 2023 )") == .boolean(false))
        #expect(try env.value("CALCULATE ( ISCROSSFILTERED ( Fact_Trans ), Fact_Trans[client_region] = \"Miền Bắc\" )")
                == .boolean(false))
        // Dim_Account lọc không lan ngược lên Dim_Client (quan hệ một chiều từ Dim_Client).
        #expect(try env.value("CALCULATE ( ISCROSSFILTERED ( Dim_Client[client_region] ), Dim_Account[card_type] = \"Debit\" )")
                == .boolean(false))
        // Không có bộ lọc nào thì không cross-filter.
        #expect(try env.value("ISCROSSFILTERED ( Fact_Trans[amount] )") == .boolean(false))
    }

    // MARK: HASONEVALUE

    @Test func hasOneValueCoVaKhongBlank() throws {
        let env = FFEnv()
        #expect(try env.value("CALCULATE ( HASONEVALUE ( Dim_Account[card_type] ), Dim_Account[card_type] = \"Debit\" )")
                == .boolean(true))
        #expect(try env.value("HASONEVALUE ( Dim_Account[card_type] )") == .boolean(false))
        // Lọc BLANK trực tiếp trên Dim_Account: chỉ còn dòng BLANK ảo (FK 99), nên VALUES(branch_city) là {BLANK}.
        let blankCity = "CALCULATE ( HASONEVALUE ( Dim_Account[branch_city] ), Dim_Account[branch_city] = BLANK () )"
        #expect(try env.value(blankCity) == .boolean(true))
        // Lọc fact không lan ngược lên Dim_Account (quan hệ một chiều): branch_city vẫn có 3 giá trị và BLANK.
        let blankRegion = "CALCULATE ( HASONEVALUE ( Dim_Account[branch_city] ), Fact_Trans[client_region] = BLANK () )"
        #expect(try env.value(blankRegion) == .boolean(false))
        #expect(try env.value("HASONEVALUE ( Dim_Account[branch_city] )") == .boolean(false))
        #expect(try env.table("VALUES ( Dim_Account[branch_city] )").rows.count == FFExpected.allBranchCity)
    }

    // MARK: SELECTEDVALUE

    @Test func selectedValueMotGiaTriHoacAlt() throws {
        let env = FFEnv()
        #expect(try env.value("CALCULATE ( SELECTEDVALUE ( Dim_Account[card_type], \"nhiều\" ), Dim_Account[card_type] = \"Credit\" )")
                == .string("Credit"))
        #expect(try env.value("SELECTEDVALUE ( Dim_Account[card_type], \"nhiều\" )") == .string("nhiều"))
        // Không có alt thì BLANK khi không có đúng một giá trị.
        #expect(try env.value("SELECTEDVALUE ( Dim_Account[card_type] )") == .blank)
        let hai = "CALCULATE ( SELECTEDVALUE ( Dim_Account[card_type], \"nhiều\" ), Dim_Account[card_type] = \"Credit\" || Dim_Account[card_type] = \"Debit\" )"
        #expect(try env.value(hai) == .string("nhiều"))
    }

    @Test func selectedValueVoiBlank() throws {
        let env = FFEnv()
        // Chỉ BLANK còn lại: HASONEVALUE đúng và SELECTEDVALUE trả BLANK, không trả alt [SUY ĐOÁN, xem Information.swift].
        let blankCity = "CALCULATE ( SELECTEDVALUE ( Dim_Account[branch_city], \"x\" ), Dim_Account[branch_city] = BLANK () )"
        #expect(try env.value(blankCity) == .blank)
        #expect(try env.value("SELECTEDVALUE ( Dim_Account[branch_city], \"x\" )") == .string("x"))
    }

    // MARK: Trong SUMMARIZECOLUMNS (mỗi ô là một ngữ cảnh lọc)

    @Test func summarizeSelectedValueTheoTungO() async throws {
        let env = FFEnv()
        let rows = try await env.query("""
        EVALUATE
        SUMMARIZECOLUMNS (
            Dim_Account[card_type],
            "sv", SELECTEDVALUE ( Dim_Account[card_type], "nhiều" )
        )
        """)
        // Ô BLANK có SELECTEDVALUE là BLANK nên dòng bị bỏ (mọi biểu thức BLANK).
        #expect(rows.rows.count == 3)
        for row in rows.rows {
            #expect(row[1] == row[0], "SELECTEDVALUE của ô \(ffNhan(row[0])) phải là chính nó")
        }
    }

    @Test func summarizeISFILTEREDVaHASONEVALUE() async throws {
        let env = FFEnv()
        let rows = try await env.query("""
        EVALUATE
        SUMMARIZECOLUMNS (
            Dim_Account[card_type],
            "f_card", ISFILTERED ( Dim_Account[card_type] ),
            "f_year", ISFILTERED ( Dim_Date[year] ),
            "one", HASONEVALUE ( Dim_Account[card_type] )
        )
        """)
        // Bốn ô (Credit, Debit, No Card, BLANK): cột nhóm là bộ lọc trực tiếp; năm không lọc; mỗi ô một giá trị.
        #expect(rows.rows.count == 4)
        for row in rows.rows {
            #expect(row[1] == .boolean(true), "ISFILTERED(card_type) trong ô \(ffNhan(row[0]))")
            #expect(row[2] == .boolean(false), "ISFILTERED(year) trong ô \(ffNhan(row[0]))")
            #expect(row[3] == .boolean(true), "HASONEVALUE(card_type) trong ô \(ffNhan(row[0]))")
        }
    }
}
