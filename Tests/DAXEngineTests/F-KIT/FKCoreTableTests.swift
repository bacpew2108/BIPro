// VALUES, FILTER và RELATED (F-KIT lõi, đợt 2). Đáp án: MiniBankExpected và script Python độc lập
// (34 dòng có amount > 0; 16 dòng Miền Bắc; 16 Miền Trung; 7 Unknown; 1 dòng BLANK).
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FKCoreTableTests {

    // MARK: VALUES

    @Test func valuesCotCoBlankTuDongBlankAo() throws {
        let env = FKCoreEnv()
        // Fact_Trans có dòng FK 99 không khớp, nên dòng BLANK ảo của Dim_Account thấy được khi không lọc.
        let tv = try env.table("VALUES ( Dim_Account[card_type] )")
        #expect(fkChuoi(fkTapGiaTri(tv)) == ["Credit", "Debit", "No Card"])
        #expect(fkTapGiaTri(tv).contains(.blank))
        #expect(try env.count("COUNTROWS ( VALUES ( Dim_Account[card_type] ) )") == 4)
    }

    @Test func valuesSauLocNamKhongCoBlankKhiKhongCoFkLa() throws {
        let env = FKCoreEnv()
        // Năm 2023 không có dòng FK 99, nên không có BLANK; còn đủ ba loại thẻ.
        let nam2023 = try env.filter("Dim_Date", "year", [.integer(2023)])
        let tv = try env.table("VALUES ( Dim_Account[card_type] )", filter: nam2023)
        #expect(fkChuoi(fkTapGiaTri(tv)) == ["Credit", "Debit", "No Card"])
        // Đáp án Python: không có BLANK. Dòng BLANK ảo của Dim_Account chỉ thấy được khi có fact không khớp
        // đang thấy (§3.3). Năm 2023 không có dòng FK 99, nên BLANK không được thấy.
        #expect(!fkTapGiaTri(tv).contains(.blank))
    }

    @Test func valuesNamHaiNghinHaiBlankThayDuoc() throws {
        let env = FKCoreEnv()
        // Năm 2024 có dòng FK 99 (20240817), nên dòng BLANK ảo thấy được.
        let nam2024 = try env.filter("Dim_Date", "year", [.integer(2024)])
        let tv = try env.table("VALUES ( Dim_Account[card_type] )", filter: nam2024)
        #expect(fkTapGiaTri(tv) == [.string("Credit"), .string("Debit"), .string("No Card"), .blank])
    }

    @Test func valuesSauLocConTrenCotKhac() throws {
        let env = FKCoreEnv()
        // Hà Nội là tài khoản 1 và 4, đều là Debit.
        let haNoi = try env.filter("Dim_Account", "branch_city", [.string("Hà Nội")])
        #expect(fkTapGiaTri(try env.table("VALUES ( Dim_Account[card_type] )", filter: haNoi)) == [.string("Debit")])
        // Tài khoản 3 (No Card) ở TP. Hồ Chí Minh.
        let theKhongCo = try env.filter("Dim_Account", "card_type", [.string("No Card")])
        #expect(fkTapGiaTri(try env.table("VALUES ( Dim_Account[branch_city] )", filter: theKhongCo))
                == [.string("TP. Hồ Chí Minh")])
    }

    @Test func valuesBangGiuLineageVaDongBlankAo() throws {
        let env = FKCoreEnv()
        let tv = try env.table("VALUES ( Dim_Account )")
        #expect(tv.rows.count == 6)                       // 5 tài khoản và dòng BLANK ảo
        #expect(tv.rows.last?[3] == .blank)
        #expect(tv.lineage.allSatisfy { $0 != nil })
        #expect(tv.columns.count == 4)
    }

    // MARK: FILTER

    @Test func filterDemDongDuongKhongMaterialize() throws {
        let env = FKCoreEnv()
        #expect(try env.count("COUNTROWS ( FILTER ( Fact_Trans, Fact_Trans[amount] > 0 ) )") == 34)
        // Nguồn vật lý được lặp qua RowSet; không dòng nào bị vật chất hoá.
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func filterTraBangChiVatChatDongKhop() throws {
        let env = FKCoreEnv()
        let tv = try env.table("FILTER ( Fact_Trans, Fact_Trans[amount] > 0 )")
        #expect(tv.rows.count == 34)
        #expect(tv.lineage.allSatisfy { $0 != nil })
        #expect(env.evaluator.materializedRowCount == 34)
        #expect(tv.rows.allSatisfy { row in
            if case .currency(let c) = row[3] { return c > 0 }
            return false
        })
    }

    @Test func filterTrenNguonAoLocDongDung() throws {
        let env = FKCoreEnv()
        // Nguồn ảo: VALUES(card_type) gồm Credit, Debit, No Card và BLANK; chỉ Debit khớp.
        #expect(try env.count("COUNTROWS ( FILTER ( VALUES ( Dim_Account[card_type] ), Dim_Account[card_type] = \"Debit\" ) )") == 1)
    }

    @Test func filterVoiRelatedDemDungMienBac() throws {
        let env = FKCoreEnv()
        // Hai bước: Fact_Trans -> Dim_Account -> Dim_Client. 16 dòng Miền Bắc.
        #expect(try env.count("COUNTROWS ( FILTER ( Fact_Trans, RELATED ( Dim_Client[client_region] ) = \"Miền Bắc\" ) )") == 16)
        #expect(try env.count("COUNTROWS ( FILTER ( Fact_Trans, RELATED ( Dim_Client[client_region] ) = \"Miền Trung\" ) )") == 16)
        #expect(try env.count("COUNTROWS ( FILTER ( Fact_Trans, RELATED ( Dim_Client[client_region] ) = \"Unknown\" ) )") == 7)
    }

    @Test func calculateSumVoiFilterRelatedDungTongMienBac() throws {
        let env = FKCoreEnv()
        // Trùng với Trans Amount có bộ lọc Dim_Client[client_region]=Miền Bắc trong MiniBankExpected.
        #expect(try env.value("CALCULATE ( SUM ( Fact_Trans[amount] ), FILTER ( Fact_Trans, RELATED ( Dim_Client[client_region] ) = \"Miền Bắc\" ) )")
                == .currency(556_763_500))
    }

    @Test func relatedDongFkNamNgoaiBangThiBlank() throws {
        let env = FKCoreEnv()
        // Dòng FK 99 không khớp Dim_Account: RELATED(Dim_Account[branch_city]) và RELATED(Dim_Client...) đều BLANK.
        #expect(try env.count("COUNTROWS ( FILTER ( Fact_Trans, ISBLANK ( RELATED ( Dim_Account[branch_city] ) ) ) )") == 1)
        #expect(try env.count("COUNTROWS ( FILTER ( Fact_Trans, ISBLANK ( RELATED ( Dim_Client[client_region] ) ) ) )") == 1)
    }

    @Test func relatedCungBangVaHaiBuoc() throws {
        let env = FKCoreEnv()
        // Cùng bảng: đọc trực tiếp. Dim_Account đi qua Account_Client: tài khoản 1 và 4 thuộc Miền Bắc.
        #expect(try env.count("COUNTROWS ( FILTER ( Dim_Account, RELATED ( Dim_Account[card_type] ) = \"No Card\" ) )") == 1)
        #expect(try env.count("COUNTROWS ( FILTER ( Dim_Account, RELATED ( Dim_Client[client_region] ) = \"Miền Bắc\" ) )") == 2)
    }

    @Test func relatedNgoaiRowContextBaoLoi() throws {
        let env = FKCoreEnv()
        #expect(fkKindOf { try env.value("RELATED ( Dim_Client[client_region] )") } == .runtime)
    }
}
