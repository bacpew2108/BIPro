// Kiểm thử QueryExecutor (QRY, đợt 2): ROW, nhiều EVALUATE, ORDER BY, START AT, DEFINE, cắt dòng, huỷ.
// Đáp án nằm ở QRYExpected.swift, tính bằng Python độc lập.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct QRYExecutorTests {

    // MARK: ROW và nhiều EVALUATE

    @Test func rowMotDong() async throws {
        let result = try await qryRun(#"EVALUATE ROW("a", 3, "tong", [Trans Count])"#)
        #expect(result.tables.count == 1, "một EVALUATE cho một bảng")
        let table = result.tables[0]
        #expect(table.columns == ["[a]", "[tong]"], "ROW đặt tên cột theo dạng [tên]")
        #expect(table.rows == [[.integer(3), .integer(40)]], "một dòng, Trans Count của cả 40 giao dịch")
        #expect(table.isTruncated == false, "mặc định không cắt dòng")
    }

    @Test func nhieuEvaluateChoNhieuBang() async throws {
        let result = try await qryRun(#"EVALUATE ROW("a", 1) EVALUATE ROW("b", 2)"#)
        #expect(result.tables.count == 2, "mỗi EVALUATE thành một ResultTable, theo thứ tự")
        #expect(result.tables[0].columns == ["[a]"])
        #expect(result.tables[1].rows == [[.integer(2)]])
    }

    @Test func thoiGianThucThiDuocDo() async throws {
        let result = try await qryRun(#"EVALUATE ROW("a", 1)"#)
        #expect(result.elapsedNanoseconds > 0, "elapsedNanoseconds được đo")
    }

    // MARK: SUMMARIZECOLUMNS và ORDER BY

    @Test func tongTheoNamDungThuTuVaTen() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "Trans Amount", [Trans Amount], "Trans Count", [Trans Count])
            """#)
        let table = result.tables[0]
        #expect(table.columns == ["Dim_Date[year]", "[Trans Amount]", "[Trans Count]"], "cột nhóm trước, rồi tên đặt ở \"tên\"")
        #expect(table.rows.count == QRYExpected.years.count)
        for (k, year) in QRYExpected.years.enumerated() {
            #expect(table.rows[k][0] == .integer(year))
            #expect(table.rows[k][1] == .currency(QRYExpected.amountByYear[year] ?? -1), "tổng tiền năm \(year)")
            #expect(table.rows[k][2] == .integer(QRYExpected.countByYear[year] ?? -1), "số giao dịch năm \(year)")
        }
    }

    @Test func orderByDescDoiThuTu() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "Trans Count", [Trans Count]) ORDER BY Dim_Date[year] DESC
            """#)
        let rows = result.tables[0].rows
        #expect(rows.map { $0[0] } == [.integer(2024), .integer(2023)], "DESC đảo thứ tự năm")
    }

    @Test func startAtBoQuaDongDangTruoc() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "Trans Count", [Trans Count]) ORDER BY Dim_Date[year] START AT 2024
            """#)
        #expect(result.tables[0].rows == [[.integer(2024), .integer(20)]], "START AT 2024 chỉ còn năm 2024")
    }

    @Test func startAtTheoChieuDesc() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "Trans Count", [Trans Count]) ORDER BY Dim_Date[year] DESC START AT 2023
            """#)
        #expect(result.tables[0].rows.map { $0[0] } == [.integer(2023)], "với DESC, START AT 2023 bỏ năm 2024")
    }

    @Test func startAtKhongCoOrderByLaLoi() async {
        let loi = await qryLoi(#"EVALUATE ROW("a", 1) START AT 1"#)
        #expect(loi?.kind == .syntax, "START AT cần ORDER BY")
    }

    @Test func orderByCotKhongCoTrongKetQuaLaLoi() async {
        let loi = await qryLoi(#"EVALUATE ROW("a", 1) ORDER BY [khong_co]"#)
        #expect(loi?.kind == .unknownName, "ORDER BY chỉ nhận cột có trong kết quả")
    }

    @Test func orderByChuoiBlankDungDau() async throws {
        // [SUY ĐOÁN, chờ O18]: BLANK đứng đầu khi ASC.
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Fact_Trans[client_region], "Trans Count", [Trans Count]) ORDER BY Fact_Trans[client_region]
            """#)
        let rows = result.tables[0].rows
        #expect(rows.first?[0] == .blank, "BLANK đứng đầu khi ASC [SUY ĐOÁN]")
        #expect(rows.count == QRYExpected.countByRegion.count)
    }

    // MARK: DEFINE

    @Test func defineMeasureDuocDanhGia() async throws {
        let result = try await qryRun(#"""
            DEFINE MEASURE Fact_Trans[Gap] = [Trans Amount] + [Trans Amount]
            EVALUATE ROW("v", [Gap])
            """#)
        let value = result.tables[0].rows[0][0]
        let expected = Double(QRYExpected.amountTotal) * 2 / 10_000
        #expect(abs((qrySo(value) ?? -1) - expected) < 1e-6, "measure DEFINE = 2 × tổng tiền, bằng \(expected)")
    }

    @Test func defineVarScalarDuocTinhMotLan() async throws {
        let result = try await qryRun(#"""
            DEFINE VAR y = 2024
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], FILTER(Dim_Date, Dim_Date[year] = y), "Trans Amount", [Trans Amount])
            """#)
        #expect(result.tables[0].rows == [[.integer(2024), .currency(QRYExpected.amountByYear[2024] ?? -1)]],
                "VAR y thay bằng 2024 trước khi đánh giá")
    }

    @Test func defineTableDuocThayLaBieuThuc() async throws {
        let result = try await qryRun(#"""
            DEFINE TABLE d2024 = FILTER(Dim_Date, Dim_Date[year] = 2024)
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], d2024, "Trans Amount", [Trans Amount])
            """#)
        #expect(result.tables[0].rows == [[.integer(2024), .currency(QRYExpected.amountByYear[2024] ?? -1)]],
                "TABLE d2024 là bộ lọc, chỉ còn năm 2024")
    }

    // MARK: Lỗi, cắt dòng, huỷ

    @Test func tenKhongCoLaLoiBind() async {
        let loi = await qryLoi(#"EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "x", [khong_co])"#)
        #expect(loi?.kind == .unknownName, "lỗi tên do binder báo")
    }

    @Test func catDongKhiCoGioiHan() async throws {
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "n", [Trans Count])"#,
                                      options: QueryExecutor.Options(rowLimit: 1))
        #expect(result.tables[0].rows.count == 1, "giới hạn 1 dòng")
        #expect(result.tables[0].isTruncated, "cờ isTruncated bật khi bị cắt")
    }

    @Test func huyGiuaChung() async {
        // Measure "Trans Count" huỷ Task hiện tại lúc được tính; vòng lặp kế tiếp phải ném .cancelled.
        let task = Task {
            try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "n", [Trans Count])"#, cancelOn: "Trans Count")
        }
        do {
            _ = try await task.value
            #expect(Bool(false), "phải ném lỗi khi bị huỷ")
        } catch let loi as DAXError {
            #expect(loi.kind == .cancelled, "lỗi .cancelled khi Task bị huỷ")
        } catch {
            #expect(Bool(false), "lỗi không phải DAXError: \(error)")
        }
    }

    @Test func huyTruocKhiChayLaLoi() async {
        let task = Task { () -> DAXError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await qryRun(#"EVALUATE ROW("a", 1)"#)
                return nil
            } catch {
                return error as? DAXError
            }
        }
        let loi = await task.value
        #expect(loi?.kind == .cancelled, "Task đã huỷ thì không chạy tiếp")
    }
}
