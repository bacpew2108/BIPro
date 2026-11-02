// Hàm bảng F-TABLE (đợt 3): DISTINCT, SUMMARIZE, ADDCOLUMNS, CROSSJOIN, TOPN, RELATEDTABLE trên MiniBank.
// Đáp án: script Python stdlib độc lập scratchpad/oracle/ftable_oracle.py (đọc MiniBankData.swift). Số liệu chính:
//   - Fact_Trans 40 dòng; Dim_Account 5 dòng + 1 dòng BLANK ảo (fact FK 99 không khớp).
//   - Dim_Client 6 dòng (có Unknown khoá -1); Dim_District 3 dòng.
//   - DISTINCT card_type: Credit, Debit, No Card, BLANK (4).
//   - SUMMARIZE(Fact_Trans, Dim_Client[client_region]): Unknown, Miền Bắc, Miền Trung, BLANK (4 dòng).
//   - RELATED region trên Fact_Trans: Unknown 7, Miền Bắc 16, Miền Trung 16, BLANK 1.
//   - TOPN 3 DESC amount: 69748700, 64000000, 58835900. TOPN 3 ASC amount: -9505400, -8926400, -7916100.
//   - Số tài khoản theo khách (Dim_Client key -1, 1, 2, 3, 4, 5): 1, 1, 2, 0, 1, 0.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FTABLEDistinctTests {

    @Test func distinctCotCoBlankTuDongBlankAo() throws {
        let env = FTEnv()
        // Fact_Trans có FK 99 không khớp, nên dòng BLANK ảo của Dim_Account thấy được khi không lọc.
        let tv = try env.table("DISTINCT ( Dim_Account[card_type] )")
        #expect(tv.rows.count == 4)
        let values = Set(tv.rows.map { $0[0] })
        #expect(values == [.string("Credit"), .string("Debit"), .string("No Card"), .blank])
        #expect(try env.count("DISTINCT ( Dim_Account[card_type] )") == 4)
    }

    @Test func distinctBangVatLyKhongVatChatHetNguon() throws {
        let env = FTEnv()
        // Dim_District có 3 dòng khác nhau: DISTINCT giữ cả 3, chỉ các dòng đầu ra được vật chất hoá.
        let tv = try env.table("DISTINCT ( Dim_District )")
        #expect(tv.rows.count == 3)
        #expect(tv.lineage.allSatisfy { $0 != nil })
        #expect(tv.columns == ["city", "state_name"])
        #expect(env.evaluator.materializedRowCount == 3)
    }

    @Test func distinctBangAoBoTrung() throws {
        let env = FTEnv()
        // VALUES(Dim_Account[card_type]) có 4 giá trị; DISTINCT trên bảng ảo đó vẫn là 4.
        let tv = try env.table("DISTINCT ( VALUES ( Dim_Account[card_type] ) )")
        #expect(tv.rows.count == 4)
    }
}

@Suite struct FTABLESummarizeTests {

    @Test func summarizeNhomTheoCotLienQuanKhongMaterialize() throws {
        let env = FTEnv()
        // Đáp án Python: 4 nhóm (Unknown, Miền Bắc, Miền Trung, BLANK từ FK 99).
        let tv = try env.table("SUMMARIZE ( Fact_Trans, Dim_Client[client_region] )")
        #expect(tv.rows.count == 4)
        let values = Set(tv.rows.map { $0[0] })
        #expect(values == [.string("Unknown"), .string("Miền Bắc"), .string("Miền Trung"), .blank])
        #expect(tv.columns == ["Dim_Client[client_region]"])
        // Lineage giữ cột nhóm (cột của Dim_Client).
        let cotNhom = try env.column("Dim_Client", "client_region")
        #expect(tv.lineage == [cotNhom])
        // Nguồn 40 dòng không bị vật chất hoá khi lặp.
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func summarizeCotCungBangSoNhomDungVoiDoc() throws {
        let env = FTEnv()
        // Đáp án Python: 6 tài khoản khác nhau trong Fact_Trans (kể cả 99).
        #expect(try env.count("SUMMARIZE ( Fact_Trans, Fact_Trans[account_key] )") == 6)
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func summarizeKhongTongHopGiongDistinctTrenCotNhom() throws {
        let env = FTEnv()
        // SUMMARIZE không tổng hợp trên Dim_Account[card_type] (có dòng BLANK ảo) cho cùng tập giá trị với DISTINCT.
        let summarized = try env.table("SUMMARIZE ( Dim_Account, Dim_Account[card_type] )")
        let distinct = try env.table("DISTINCT ( Dim_Account[card_type] )")
        #expect(Set(summarized.rows.map { $0[0] }) == Set(distinct.rows.map { $0[0] }))
        #expect(summarized.rows.count == 4)
    }

    @Test func summarizeCoCapTenBieuThucTinhTrongBoLocNhom() throws {
        let env = FTEnv()
        // Dựng trực tiếp biểu thức (Binder chưa bind được cặp tên/biểu thức sau cột nhóm, xem báo cáo).
        // Đáp án Python: tổng amount theo account_key, gồm 99 có tổng -2031000.
        guard let summarizeIndex = FunctionRegistry.all.firstIndex(where: { $0.name == "SUMMARIZE" }),
              let sumIndex = FunctionRegistry.all.firstIndex(where: { $0.name == "SUM" }) else {
            Issue.record("thiếu SUMMARIZE hoặc SUM trong registry")
            return
        }
        let expr: BoundExpr = .call(FunctionID(raw: Int32(summarizeIndex)), [
            .table(MiniBank.Tables.factTrans),
            .column(MiniBank.Columns.FactTrans.accountKey),
            .literal(.string("Tổng")),
            .call(FunctionID(raw: Int32(sumIndex)), [.column(MiniBank.Columns.FactTrans.amount)]),
        ])
        let tv = try env.evaluator.table(expr, in: EvalContext(filter: env.base, row: nil))
        #expect(tv.columns == ["Fact_Trans[account_key]", "Tổng"])
        var tongTheoTaiKhoan: [Int64: Int64] = [:]
        for row in tv.rows {
            if case .integer(let ak) = row[0], let tong = ftSoNguyen(row[1]) {
                tongTheoTaiKhoan[ak] = tong
            }
        }
        #expect(tongTheoTaiKhoan == [
            5: 192_866_700, 4: 288_729_400, 2: 128_598_800,
            1: 268_034_100, 3: 378_100_000, 99: -2_031_000,
        ])
    }
}

@Suite struct FTABLEAddColumnsTests {

    @Test func addColumnsCoRelatedTrenNguonVatLy() throws {
        let env = FTEnv()
        // Đáp án Python: 40 dòng; 1 BLANK (FK 99), 7 Unknown, 16 Miền Bắc, 16 Miền Trung.
        let tv = try env.table("ADDCOLUMNS ( Fact_Trans, \"vùng\", RELATED ( Dim_Client[client_region] ) )")
        #expect(tv.rows.count == 40)
        #expect(tv.columns.count == 7)
        #expect(tv.columns.last == "vùng")
        let regions = tv.rows.map { $0[6] }
        #expect(regions.filter { $0 == .blank }.count == 1)
        #expect(regions.filter { $0 == .string("Unknown") }.count == 7)
        #expect(regions.filter { $0 == .string("Miền Bắc") }.count == 16)
        #expect(regions.filter { $0 == .string("Miền Trung") }.count == 16)
        // Cột gốc giữ lineage; cột mới không có lineage.
        #expect(tv.lineage[0] != nil)
        #expect(tv.lineage[6] == nil)
        // Chỉ dòng đầu ra được vật chất hoá (40), không tính nguồn lặp.
        #expect(env.evaluator.materializedRowCount == 40)
    }

    @Test func addColumnsTrenDimAccountVaDongBlankAo() throws {
        let env = FTEnv()
        // Theo thứ tự dòng của Dim_Account: Miền Bắc, Miền Trung, Miền Trung, Miền Bắc, Unknown, BLANK ảo.
        let tv = try env.table("ADDCOLUMNS ( Dim_Account, \"vùng\", RELATED ( Dim_Client[client_region] ) )")
        #expect(tv.rows.count == 6)
        #expect(tv.rows.map { $0[4] } == [
            .string("Miền Bắc"), .string("Miền Trung"), .string("Miền Trung"),
            .string("Miền Bắc"), .string("Unknown"), .blank,
        ])
    }

    @Test func addColumnsBieuThucTinhTrongDongCuaChinhDong() throws {
        let env = FTEnv()
        // Biểu thức dùng cột của chính dòng: trans_key * 10 theo từng dòng, không trộn dòng.
        let tv = try env.table("ADDCOLUMNS ( Fact_Trans, \"kt\", Fact_Trans[trans_key] * 10 )")
        #expect(tv.rows.count == 40)
        for row in tv.rows {
            guard case .integer(let key) = row[0], case .integer(let kt) = row[6] else {
                Issue.record("kiểu cột không đúng")
                return
            }
            #expect(kt == key * 10)
        }
    }
}

@Suite struct FTABLECrossJoinTests {

    @Test func crossJoinDimDistrictDimClient() throws {
        let env = FTEnv()
        // Đáp án Python: 3 x 6 = 18 dòng.
        let tv = try env.table("CROSSJOIN ( Dim_District, Dim_Client )")
        // Đầu vào được vật chất hoá một lần mỗi bảng: 3 + 6 = 9 (kiểm ngay sau lần đánh giá đầu tiên).
        #expect(env.evaluator.materializedRowCount == 9)
        #expect(tv.rows.count == 18)
        #expect(tv.columns == ["city", "state_name", "client_key", "client_region"])
        #expect(tv.lineage.allSatisfy { $0 != nil })
        #expect(try env.count("CROSSJOIN ( Dim_District, Dim_Client )") == 18)
    }
}

@Suite struct FTABLETopNTests {

    @Test func topNBaDongLonNhat() throws {
        let env = FTEnv()
        // Đáp án Python: amount 69748700 (khoá 13), 64000000 (khoá 23), 58835900 (khoá 17).
        let tv = try env.table("TOPN ( 3, Fact_Trans, Fact_Trans[amount], DESC )")
        #expect(tv.rows.count == 3)
        #expect(tv.rows.map { ftSoNguyen($0[3]) ?? 0 } == [69_748_700, 64_000_000, 58_835_900])
        #expect(tv.rows.map { ftSoNguyen($0[0]) ?? 0 } == [13, 23, 17])
        // Chỉ ba dòng đầu ra được vật chất hoá, không phải 40 dòng nguồn.
        #expect(env.evaluator.materializedRowCount == 3)
    }

    @Test func topNMacDinhTangDan() throws {
        let env = FTEnv()
        // Không có từ khoá là ASC. Đáp án Python: -9505400 (khoá 8), -8926400 (khoá 21), -7916100 (khoá 16).
        let tv = try env.table("TOPN ( 3, Fact_Trans, Fact_Trans[amount] )")
        #expect(tv.rows.map { ftSoNguyen($0[3]) ?? 0 } == [-9_505_400, -8_926_400, -7_916_100])
        #expect(tv.rows.map { ftSoNguyen($0[0]) ?? 0 } == [8, 21, 16])
    }

    @Test func topNGiuMoiDongBangNguong() throws {
        let env = FTEnv()
        // Dim_Account theo client_key DESC: 4, rồi hai dòng cùng 2 (acc 2, acc 3). N = 2, ngưỡng là 2,
        // nên giữ cả ba dòng (quy tắc DAX giữ mọi dòng bằng giá trị dòng thứ n). Đáp án Python: 3 dòng.
        let tv = try env.table("TOPN ( 2, Dim_Account, Dim_Account[client_key], DESC )")
        #expect(tv.rows.count == 3)
        #expect(tv.rows.map { ftSoNguyen($0[0]) ?? -1 }.sorted() == [2, 3, 4])
    }

    @Test func topNTrenBangAoBlankDungTruoc() throws {
        let env = FTEnv()
        // VALUES(card_type) gồm BLANK; ASC đặt BLANK trước. Đáp án Python: [BLANK, Credit].
        let tv = try env.table("TOPN ( 2, VALUES ( Dim_Account[card_type] ), Dim_Account[card_type], ASC )")
        #expect(tv.rows.map { $0[0] } == [.blank, .string("Credit")])
    }

    @Test func topNThieuBieuThucSapXepBaoLoi() throws {
        let env = FTEnv()
        // Không có biểu thức sắp xếp thì báo lỗi .arity (quy tắc [SUY ĐOÁN] của F-TABLE).
        #expect(ftLoai { try env.value("COUNTROWS ( TOPN ( 3, Fact_Trans ) )") } == .arity)
    }
}

@Suite struct FTABLERelatedTableTests {

    @Test func relatedTableTuDimClientSangDimAccount() throws {
        let env = FTEnv()
        // Đáp án Python theo khoá khách: -1→1, 1→1, 2→2, 3→0, 4→1, 5→0 (dòng BLANK ảo không thuộc khách nào).
        // 0 dòng: COUNTROWS là BLANK (Golden Power BI (buổi 1): đếm trên tập rỗng cho BLANK).
        let tv = try env.table("ADDCOLUMNS ( Dim_Client, \"n\", COUNTROWS ( RELATEDTABLE ( Dim_Account ) ) )")
        #expect(tv.rows.count == 6)
        var dem: [Int64: Value] = [:]
        for row in tv.rows {
            if case .integer(let ck) = row[0] {
                dem[ck] = row[2]
            }
        }
        #expect(dem == [-1: .integer(1), 1: .integer(1), 2: .integer(2), 3: .blank, 4: .integer(1), 5: .blank])
    }

    @Test func relatedTableKhongCoRowContextLaBangDich() throws {
        let env = FTEnv()
        // Không có row context: RELATEDTABLE như bảng đích thường, gồm dòng BLANK ảo (5 + 1 = 6).
        #expect(try env.count("RELATEDTABLE ( Dim_Account )") == 6)
    }
}

extension FTEnv {
    /// ColumnID của cột theo tên bảng và tên cột (để so lineage).
    func column(_ table: String, _ name: String) throws -> ColumnID {
        guard let meta = store.schema.column(table: table, name: name) else {
            throw DAXError(.unknownName, "không có cột \(table)[\(name)]")
        }
        return meta.id
    }
}
