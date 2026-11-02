// Kiểm thử SUMMARIZECOLUMNS (QRY, đợt 2) trên MiniBank: nhóm, bảng bộ lọc, BLANK, IGNORE, crossjoin.
// Đáp án nằm ở QRYExpected.swift, tính bằng Python độc lập. Các quy tắc chưa đối chiếu được ghi [SUY ĐOÁN].
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

/// Bảng kết quả hai cột (nhãn, số đếm) thành từ điển, để so không phụ thuộc thứ tự dòng.
private func theoNhan(_ rows: [[Value]], nhanCot: Int = 0, soCot: Int = 1) -> [String: Int64] {
    var out: [String: Int64] = [:]
    for row in rows {
        if case .integer(let v) = row[soCot] {
            out[qryNhan(row[nhanCot]), default: 0] += v
        }
    }
    return out
}

@Suite struct QRYSummarizeTests {

    // MARK: Cột nhóm và tên cột

    @Test func khongCoBieuThucChiTraToHopNhom() async throws {
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Dim_Date[year])"#)
        let table = result.tables[0]
        #expect(table.columns == ["Dim_Date[year]"])
        #expect(table.rows.map { $0[0] } == QRYExpected.years.map { .integer($0) }, "chỉ tổ hợp nhóm, theo thứ tự năm")
    }

    @Test func khongCoNhomChiMotDong() async throws {
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS("n", [Trans Count])"#)
        #expect(result.tables[0].columns == ["[n]"])
        #expect(result.tables[0].rows == [[.integer(40)]], "không có cột nhóm thì một dòng với measure trên toàn bộ bộ lọc")
    }

    // MARK: BLANK và IGNORE

    @Test func measureBlankLoaiMoiDong() async throws {
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "x", BLANK())"#)
        #expect(result.tables[0].rows.isEmpty, "mọi biểu thức BLANK thì dòng bị bỏ")
    }

    @Test func motMeasureKhacBlankGiuDong() async throws {
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "x", BLANK(), "n", [Trans Count])"#)
        let rows = result.tables[0].rows
        #expect(rows.count == QRYExpected.years.count, "có một biểu thức khác BLANK thì dòng được giữ")
        #expect(rows.allSatisfy { $0[1] == .blank }, "cột x là BLANK")
        #expect(rows.map { $0[2] } == QRYExpected.years.map { .integer(QRYExpected.countByYear[$0] ?? -1) })
    }

    @Test func ignoreKhongThamGiaKiemTraBlank() async throws {
        // [SUY ĐOÁN]: khi mọi biểu thức đều IGNORE thì không có gì để kiểm, dòng được giữ.
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "x", IGNORE(BLANK()))"#)
        #expect(result.tables[0].rows.count == QRYExpected.years.count, "IGNORE không làm dòng bị bỏ [SUY ĐOÁN]")
    }

    @Test func ignoreKhiKhacBlankVanBoDong() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], "x", IGNORE([Trans Count]), "y", BLANK())
            """#)
        #expect(result.tables[0].rows.isEmpty, "biểu thức không IGNORE đều BLANK thì dòng bị bỏ, dù IGNORE có giá trị")
    }

    // MARK: Nhóm có giá trị BLANK

    @Test func nhomCardTypeCoDongBlank() async throws {
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Dim_Account[card_type], "n", [Trans Count])"#)
        #expect(result.tables[0].columns == ["Dim_Account[card_type]", "[n]"])
        #expect(theoNhan(result.tables[0].rows) == QRYExpected.countByCardType,
                "FK 99 không khớp tạo nhóm BLANK với 1 giao dịch")
    }

    @Test func nhomVungCoDongBlank() async throws {
        let result = try await qryRun(#"EVALUATE SUMMARIZECOLUMNS(Fact_Trans[client_region], "n", [Trans Count])"#)
        #expect(theoNhan(result.tables[0].rows) == QRYExpected.countByRegion)
    }

    // MARK: Bảng bộ lọc

    @Test func bangBoLocTheoKhoaDimension() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Client[client_region], FILTER(Dim_Client, Dim_Client[client_key] = 1), "k", 1)
            """#)
        #expect(result.tables[0].rows == [[.string("Miền Bắc"), .integer(1)]],
                "FILTER theo khoá chỉ giữ client_key = 1")
    }

    @Test func bangBoLocTheoFactDuaTrenDieuKien() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], FILTER(Fact_Trans, Fact_Trans[amount] > 0), "n", [Trans Count])
            """#)
        let rows = result.tables[0].rows
        #expect(rows.map { $0[0] } == QRYExpected.years.map { .integer($0) })
        #expect(rows.map { $0[1] } == QRYExpected.years.map { .integer(QRYExpected.positiveCountByYear[$0] ?? -1) },
                "chỉ đếm giao dịch có amount > 0 theo năm")
    }

    @Test func bangBoLocTheoGiaTriDaNamTrongBiendoi() async throws {
        // Bảng bộ lọc chỉ một cột (VALUES chưa gộp): dùng FILTER trên khoá Dim_Date.
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], FILTER(Dim_Date, Dim_Date[year] = 2023), "n", [Trans Count])
            """#)
        #expect(result.tables[0].rows == [[.integer(2023), .integer(20)]])
    }

    // MARK: Crossjoin giữa hai bảng

    @Test func cotKhacBangDuocCrossjoin() async throws {
        let result = try await qryRun(#"""
            EVALUATE SUMMARIZECOLUMNS(Dim_Date[year], Dim_Account[card_type], "n", [Trans Count])
            """#)
        let table = result.tables[0]
        #expect(table.columns == ["Dim_Date[year]", "Dim_Account[card_type]", "[n]"], "cột nhóm giữ thứ tự khai báo")
        // [SUY ĐOÁN]: khác bảng thì crossjoin (§8.2 bước 3), nên có cả tổ hợp 0 giao dịch.
        var got: [String: Int64] = [:]
        for row in table.rows {
            if case .integer(let n) = row[2] {
                got["\(qryNhan(row[0]))|\(qryNhan(row[1]))"] = n
            }
        }
        let expected: [String: Int64] = [
            "2023|BLANK": 0, "2023|Credit": 8, "2023|Debit": 9, "2023|No Card": 3,
            "2024|BLANK": 1, "2024|Credit": 7, "2024|Debit": 7, "2024|No Card": 5,
        ]
        #expect(got == expected, "crossjoin 2 năm × 4 loại thẻ, tổng 40 giao dịch")
        #expect(table.rows.count == expected.count)
    }

    // MARK: Trạng thái shadow

    @Test func pushVaPopShadowTraVeNguyenTrang() {
        let ctx = FilterContext()
        #expect(ctx.pushingShadow().poppingShadow() == ctx, "đẩy rồi bật lại shadow trả về đúng ngữ cảnh")
    }
}
