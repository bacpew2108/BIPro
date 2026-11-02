// VISMiniBankTests.swift
// Test thường cho các hàm visual và tính năng mới của Package E1 (Phase C) trên dữ liệu MiniBank.
// Mọi giá trị kỳ vọng đều được tính tay từ dữ liệu MiniBank và có chú thích giải thích chi tiết.

import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct VISMiniBankTests {

    private func runQuery(_ text: String) async throws -> QueryResult {
        let modelMeasures = MiniBank.measures.map {
            ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression)
        }
        let catalog = Catalog(schema: MiniBank.schema, measures: modelMeasures)
        let engine = DAXEngine(store: MiniBank.makeStore(), catalog: catalog)
        return try await engine.execute(text)
    }

    // MARK: - 1. NATURALLEFTOUTERJOIN

    @Test func naturalLeftOuterJoinDayDu() async throws {
        // Nối trái 2 bảng có cùng cột Dim_Date[year]:
        // Bảng trái: 2 năm 2023, 2024
        // Bảng phải: năm 2023 có amount 56623.07, năm 2024 có amount 68806.73
        // Kỳ vọng: 2 dòng, đầy đủ các cột và giá trị.
        let dax = """
        EVALUATE
        VAR __Left = SUMMARIZECOLUMNS(Dim_Date[year])
        VAR __Right = SUMMARIZECOLUMNS(Dim_Date[year], "Amount", [Trans Amount])
        RETURN
        NATURALLEFTOUTERJOIN(__Left, __Right)
        ORDER BY Dim_Date[year]
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == .integer(2023))
        #expect(table.rows[0][1] == .currency(566_230_700))
        #expect(table.rows[1][0] == .integer(2024))
        #expect(table.rows[1][1] == .currency(688_067_300))
    }

    @Test func naturalLeftOuterJoinKhuyetPhaiThanhBlank() async throws {
        // Bảng phải chỉ lọc năm 2024.
        // Khi nối trái: dòng 2023 ở bảng trái không có match ở bảng phải -> cột Amount nhận BLANK.
        let dax = """
        EVALUATE
        VAR __Left = SUMMARIZECOLUMNS(Dim_Date[year])
        VAR __Right = FILTER(SUMMARIZECOLUMNS(Dim_Date[year], "Amount", [Trans Amount]), Dim_Date[year] = 2024)
        RETURN
        NATURALLEFTOUTERJOIN(__Left, __Right)
        ORDER BY Dim_Date[year]
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == .integer(2023))
        #expect(table.rows[0][1] == .blank)
        #expect(table.rows[1][0] == .integer(2024))
        #expect(table.rows[1][1] == .currency(688_067_300))
    }

    // MARK: - 2. SUBSTITUTEWITHINDEX

    @Test func substituteWithIndexDanhSo() async throws {
        // Thay cột Dim_Date[year] bằng chỉ số ColumnIndex 0-based theo thứ tự sắp xếp ASC.
        // 2023 -> 0, 2024 -> 1.
        let dax = """
        EVALUATE
        VAR __Core = SUMMARIZECOLUMNS(Dim_Date[year], "n", [Trans Count])
        VAR __Secondary = SUMMARIZECOLUMNS(Dim_Date[year])
        RETURN
        SUBSTITUTEWITHINDEX(__Core, "ColumnIndex", __Secondary, Dim_Date[year], ASC)
        ORDER BY [ColumnIndex]
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.columns == ["[n]", "[ColumnIndex]"])
        #expect(table.rows.count == 2)
        // 2023 có 20 giao dịch, index 0
        #expect(table.rows[0][0] == .integer(20))
        #expect(table.rows[0][1] == .integer(0))
        // 2024 có 20 giao dịch, index 1
        #expect(table.rows[1][0] == .integer(20))
        #expect(table.rows[1][1] == .integer(1))
    }

    @Test func substituteWithIndexSemiJoinLocDong() async throws {
        // Bảng chỉ số chỉ có năm 2024.
        // Hàng 2023 không khớp trong bảng chỉ số nên bị loại khỏi kết quả (hành vi semi-join).
        let dax = """
        EVALUATE
        VAR __Core = SUMMARIZECOLUMNS(Dim_Date[year], "n", [Trans Count])
        VAR __Secondary = FILTER(SUMMARIZECOLUMNS(Dim_Date[year]), Dim_Date[year] = 2024)
        RETURN
        SUBSTITUTEWITHINDEX(__Core, "ColumnIndex", __Secondary, Dim_Date[year], ASC)
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 1)
        #expect(table.rows[0][0] == .integer(20))
        #expect(table.rows[0][1] == .integer(0))
    }

    // MARK: - 3. GROUPBY & CURRENTGROUP

    @Test func groupByKhongCotNhomRaMotDong() async throws {
        // MiniBank Fact_Trans có 40 giao dịch:
        // amount nhỏ nhất là -950.54 (-9505400 currency), lớn nhất là 6974.87 (69748700 currency).
        // GROUPBY không có cột nhóm trả ra đúng 1 dòng với min và max tính trên CURRENTGROUP().
        let dax = """
        EVALUATE
        GROUPBY(
            Fact_Trans,
            "MinAmount", MINX(CURRENTGROUP(), Fact_Trans[amount]),
            "MaxAmount", MAXX(CURRENTGROUP(), Fact_Trans[amount])
        )
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.columns == ["[MinAmount]", "[MaxAmount]"])
        #expect(table.rows.count == 1)
        #expect(table.rows[0][0] == .currency(-9_505_400))
        #expect(table.rows[0][1] == .currency(69_748_700))
    }

    @Test func groupByCoCotNhom() async throws {
        // Nhóm theo Dim_Date[year]: 2 nhóm 2023 và 2024.
        // Fact_Trans có 40 giao dịch: 20 giao dịch năm 2023 và 20 giao dịch năm 2024.
        // Đếm số dòng mỗi nhóm bằng COUNTROWS(CURRENTGROUP()).
        let dax = """
        EVALUATE
        VAR __Base = SUMMARIZE(Fact_Trans, Dim_Date[year], Fact_Trans[trans_key])
        RETURN
        GROUPBY(
            __Base,
            Dim_Date[year],
            "RowsPerYear", COUNTROWS(CURRENTGROUP())
        )
        ORDER BY Dim_Date[year]
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == .integer(2023))
        #expect(table.rows[0][1] == .integer(20))
        #expect(table.rows[1][0] == .integer(2024))
        #expect(table.rows[1][1] == .integer(20))
    }

    // MARK: - 4. SAMPLE

    @Test func sampleLayDuKhiSizeLon() async throws {
        // Dim_Date[year] chỉ có 2 dòng (2023, 2024).
        // Size = 10 >= 2 nên lấy đủ cả 2 dòng.
        let dax = """
        EVALUATE
        VAR __T = SUMMARIZECOLUMNS(Dim_Date[year])
        RETURN
        SAMPLE(10, __T, Dim_Date[year], 1)
        ORDER BY Dim_Date[year]
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == .integer(2023))
        #expect(table.rows[1][0] == .integer(2024))
    }

    @Test func sampleLayCachDeuKhiSizeNho() async throws {
        // 5 dòng: 1, 2, 3, 4, 5. Size = 3.
        // Công thức cách đều: i * 4 / 2 -> i=0: index 0 (1); i=1: index 2 (3); i=2: index 4 (5).
        let dax = """
        EVALUATE
        VAR __T = {1, 2, 3, 4, 5}
        RETURN
        SAMPLE(3, __T, [Value], 1)
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 3)
        #expect(table.rows[0][0] == .integer(1))
        #expect(table.rows[1][0] == .integer(3))
        #expect(table.rows[2][0] == .integer(5))
    }

    // MARK: - 5. SAMPLEAXISWITHLOCALMINMAX

    @Test func sampleAxisTraDuDong() async throws {
        // Trong MiniBank chỉ có 19 tháng có phát sinh giao dịch. Size = 3500 >= 19 nên trả đủ 19 dòng.
        let dax = """
        EVALUATE
        VAR __Core = SUMMARIZECOLUMNS(Dim_Date[year_month], "n", [Trans Count])
        RETURN
        SAMPLEAXISWITHLOCALMINMAX(3500, __Core, Dim_Date[year_month], [n], 350, , ALPHABETICAL, ASC, 105000, 60)
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 19)
    }

    @Test func sampleAxisChiaBinKhiVuotNguong() async throws {
        // 4 dòng, size = 2 -> chia thành 1 bin, lấy đầu và cuối (dòng 1 và dòng 4).
        let dax = """
        EVALUATE
        VAR __Core = {10, 20, 30, 40}
        RETURN
        SAMPLEAXISWITHLOCALMINMAX(2, __Core, [Value], [Value], 1)
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == .integer(10))
        #expect(table.rows[1][0] == .integer(40))
    }

    // MARK: - 6. CEILING & SQRT

    @Test func ceilingSoDuongVaBoiSo() async throws {
        // CEILING(4.2, 1) = 5
        // CEILING(1234, 100) = 1300
        let dax = """
        EVALUATE
        ROW("c1", CEILING(4.2, 1), "c2", CEILING(1234, 100))
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows[0][0] == .double(5.0))
        #expect(table.rows[0][1] == .integer(1300))
    }

    @Test func ceilingSoAmVaSoThapPhan() async throws {
        // CEILING(-4.2, 1) trong DAX làm tròn lên (về phía 0) -> -4.0
        // CEILING(2.1, 0.5) -> 2.5
        let dax = """
        EVALUATE
        ROW("c1", CEILING(-4.2, 1), "c2", CEILING(2.1, 0.5))
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows[0][0] == .double(-4.0))
        #expect(table.rows[0][1] == .double(2.5))
    }

    @Test func sqrtSoChinhPhuong() async throws {
        // SQRT(16) = 4, SQRT(0) = 0
        let dax = """
        EVALUATE
        ROW("s1", SQRT(16), "s2", SQRT(0))
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows[0][0] == .double(4.0))
        #expect(table.rows[0][1] == .double(0.0))
    }

    @Test func sqrtSoThuc() async throws {
        // SQRT(2) xấp xỉ 1.41421356...
        let dax = """
        EVALUATE
        ROW("s", SQRT(2))
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        if case .double(let d) = table.rows[0][0] {
            #expect(abs(d - 1.414213562373095) < 1e-9)
        } else {
            Issue.record("SQRT(2) phải ra double")
        }
    }

    // MARK: - 7. MIN(a, b) dạng 2 vô hướng

    @Test func minHaiSoNguyen() async throws {
        // MIN(10, 20) = 10, MIN(-5, -2) = -5
        let dax = """
        EVALUATE
        ROW("m1", MIN(10, 20), "m2", MIN(-5, -2))
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows[0][0] == .integer(10))
        #expect(table.rows[0][1] == .integer(-5))
    }

    @Test func minVoiBlank() async throws {
        // Trong DAX, MIN(BLANK(), 5) bỏ qua BLANK trả 5; MIN(BLANK(), BLANK()) trả BLANK.
        let dax = """
        EVALUATE
        ROW("m1", MIN(BLANK(), 5), "m2", MIN(BLANK(), BLANK()))
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows[0][0] == .integer(5))
        #expect(table.rows[0][1] == .blank)
    }

    // MARK: - 8. Tuple IN

    @Test func tupleInKhopGiaTri() async throws {
        // Lọc Dim_Date có (year, month) IN {(2023, 1), (2024, 12)}.
        // MiniBank có đủ cả tháng 1/2023 và 12/2024 -> giữ đúng 2 dòng.
        let dax = """
        EVALUATE
        FILTER(
            SUMMARIZECOLUMNS(Dim_Date[year], Dim_Date[month]),
            (Dim_Date[year], Dim_Date[month]) IN {(2023, 1), (2024, 12)}
        )
        ORDER BY Dim_Date[year]
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == .integer(2023))
        #expect(table.rows[0][1] == .integer(1))
        #expect(table.rows[1][0] == .integer(2024))
        #expect(table.rows[1][1] == .integer(12))
    }

    @Test func tupleInKhongKhop() async throws {
        // Bộ (2023, 99) không có trong Dim_Date -> kết quả 0 dòng.
        let dax = """
        EVALUATE
        FILTER(
            SUMMARIZECOLUMNS(Dim_Date[year], Dim_Date[month]),
            (Dim_Date[year], Dim_Date[month]) IN {(2023, 99)}
        )
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 0)
    }

    // MARK: - 9. KEEPFILTERS(<bảng>)

    @Test func keepFiltersBangLamBoLocCalculatetable() async throws {
        // KEEPFILTERS(__F) áp như bộ lọc giao trong CALCULATETABLE.
        // VALUES('Dim_Date'[year]) có {2023, 2024}, lọc giao {2024} còn {2024}.
        let dax = """
        EVALUATE
        VAR __F = TREATAS({2024}, Dim_Date[year])
        RETURN
        CALCULATETABLE(
            VALUES(Dim_Date[year]),
            KEEPFILTERS(__F)
        )
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 1)
        #expect(table.rows[0][0] == .integer(2024))
    }

    @Test func keepFiltersBangTrongCalculate() async throws {
        // CALCULATE([Trans Count], KEEPFILTERS(__F)) với __F là TREATAS({2023}, year).
        // 2023 có đúng 20 giao dịch.
        let dax = """
        EVALUATE
        VAR __F = TREATAS({2023}, Dim_Date[year])
        RETURN
        ROW("n", CALCULATE([Trans Count], KEEPFILTERS(__F)))
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows[0][0] == .integer(20))
    }

    // MARK: - 10. SUMMARIZECOLUMNS trong VAR

    @Test func summarizeColumnsTrongVar() async throws {
        // SUMMARIZECOLUMNS gán vào biến bảng VAR __T và trả về ở RETURN.
        // Có 2 năm 2023 (amount 56623.07) và 2024 (amount 68806.73).
        let dax = """
        EVALUATE
        VAR __T = SUMMARIZECOLUMNS(Dim_Date[year], "Amount", [Trans Amount])
        RETURN
        __T
        ORDER BY Dim_Date[year]
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == .integer(2023))
        #expect(table.rows[0][1] == .currency(566_230_700))
        #expect(table.rows[1][0] == .integer(2024))
        #expect(table.rows[1][1] == .currency(688_067_300))
    }

    @Test func summarizeColumnsTrongTopN() async throws {
        // TOPN(1, SUMMARIZECOLUMNS(...), [Amount], 0) lấy năm có amount lớn nhất (2024).
        let dax = """
        EVALUATE
        TOPN(
            1,
            SUMMARIZECOLUMNS(Dim_Date[year], "Amount", [Trans Amount]),
            [Amount],
            0
        )
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 1)
        #expect(table.rows[0][0] == .integer(2024))
        #expect(table.rows[0][1] == .currency(688_067_300))
    }

    // MARK: - 11. ROLLUPADDISSUBTOTAL

    @Test func rollupAddIsSubtotalMotCap() async throws {
        // 1 cặp: ROLLUPADDISSUBTOTAL(Dim_Date[year], "IsGrandTotal")
        // Dòng tổng: Dim_Date[year] = BLANK, IsGrandTotal = true, [Trans Count] = 40 (tổng cả 2 năm)
        // Dòng chi tiết: IsGrandTotal = false, 2023 (20 GD), 2024 (20 GD).
        let dax = """
        EVALUATE
        SUMMARIZECOLUMNS(
            ROLLUPADDISSUBTOTAL(Dim_Date[year], "IsGrandTotal"),
            "n", [Trans Count]
        )
        ORDER BY [IsGrandTotal] DESC, Dim_Date[year] ASC
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.columns == ["Dim_Date[year]", "[IsGrandTotal]", "[n]"])
        #expect(table.rows.count == 3)
        // Dòng grand total
        #expect(table.rows[0][0] == .blank)
        #expect(table.rows[0][1] == .boolean(true))
        #expect(table.rows[0][2] == .integer(40))
        // Dòng 2023
        #expect(table.rows[1][0] == .integer(2023))
        #expect(table.rows[1][1] == .boolean(false))
        #expect(table.rows[1][2] == .integer(20))
        // Dòng 2024
        #expect(table.rows[2][0] == .integer(2024))
        #expect(table.rows[2][1] == .boolean(false))
        #expect(table.rows[2][2] == .integer(20))
    }

    @Test func rollupAddIsSubtotalRollupGroup() async throws {
        // ROLLUPGROUP gộp 2 cột cùng cấp: ROLLUPGROUP(Dim_Date[year], Dim_Date[year_month]).
        // Dòng grand total: cả 2 cột đều BLANK, cờ true, tổng 40 GD.
        // Có 19 tháng chi tiết có giao dịch, mỗi tháng có cờ false -> tổng cộng 20 dòng.
        let dax = """
        EVALUATE
        SUMMARIZECOLUMNS(
            ROLLUPADDISSUBTOTAL(ROLLUPGROUP(Dim_Date[year], Dim_Date[year_month]), "IsGrandTotal"),
            "n", [Trans Count]
        )
        ORDER BY [IsGrandTotal] DESC
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.columns == ["Dim_Date[year]", "Dim_Date[year_month]", "[IsGrandTotal]", "[n]"])
        #expect(table.rows.count == 20) // 1 tổng + 19 tháng
        #expect(table.rows[0][0] == .blank)
        #expect(table.rows[0][1] == .blank)
        #expect(table.rows[0][2] == .boolean(true))
        #expect(table.rows[0][3] == .integer(40))
    }

    @Test func rollupAddIsSubtotalHaiCap() async throws {
        // Hai cấp: ROLLUPADDISSUBTOTAL(Dim_Date[year], "IsTotalYear", Dim_Date[month], "IsTotalMonth")
        // Cấp 0: cả 2 gộp -> Grand total (1 dòng)
        // Cấp 1: month gộp -> Tổng mỗi năm (2 dòng: 2023, 2024)
        // Cấp 2: chi tiết năm + tháng có giao dịch (19 dòng)
        // Tổng số dòng: 1 + 2 + 19 = 22 dòng.
        let dax = """
        EVALUATE
        SUMMARIZECOLUMNS(
            ROLLUPADDISSUBTOTAL(Dim_Date[year], "IsTotalYear", Dim_Date[month], "IsTotalMonth"),
            "n", [Trans Count]
        )
        ORDER BY [IsTotalYear] DESC, [IsTotalMonth] DESC, Dim_Date[year] ASC
        """
        let result = try await runQuery(dax)
        let table = result.tables[0]
        #expect(table.rows.count == 22)
        // Dòng đầu: grand total
        #expect(table.rows[0][0] == .blank)
        #expect(table.rows[0][1] == .boolean(true))
        #expect(table.rows[0][2] == .blank)
        #expect(table.rows[0][3] == .boolean(true))
        #expect(table.rows[0][4] == .integer(40))
    }
}
