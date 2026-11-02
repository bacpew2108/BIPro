// Test bind và đánh giá SUMMARIZE có cặp (tên, biểu thức) (LANG, đợt 3 — sửa lỗi tích hợp).
// Lỗi gốc: ArgumentMatcher gán tham số cột nhóm (tableOrColumn, lặp) tham lam, nên chuỗi "Số GD"
// bị coi là cột nhóm và báo "tham số 'groupBy' của SUMMARIZE phải là bảng hoặc cột".
// Đáp án của ca đánh giá: RELATED(Dim_Client[client_region]) trên Fact_Trans là Unknown 7, Miền Bắc 16,
// Miền Trung 16, BLANK 1 (tổng 40), theo ghi chú F-TABLE và MiniBankExpected.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

/// Bind một biểu thức và trả về lỗi (nil nếu thành công), dùng cho ca lỗi.
private func langSummarizeError(_ text: String) -> DAXError? {
    do {
        _ = try Binder.bind(try parseExpression(text), catalog: Catalog(schema: MiniBank.schema))
        return nil
    } catch {
        return error
    }
}

/// Môi trường đánh giá MiniBank tối thiểu, không phụ thuộc file test khác.
private struct LANGSummarizeEnv {
    let store: ColumnStore
    let catalog: Catalog
    let evaluator: Evaluator

    init() {
        store = MiniBank.makeStore()
        catalog = Catalog(schema: MiniBank.schema)
        evaluator = Evaluator(store: store, catalog: catalog)
    }

    /// Đánh giá một biểu thức bảng không có row context và không có bộ lọc.
    func table(_ text: String) throws -> TableValue {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        let base = FilterContext.empty.bound(to: store.schema)
        return try evaluator.table(expr, in: EvalContext(filter: base, row: nil))
    }
}

@Suite struct LANGSummarizeBindTests {

    // MARK: - Bind

    @Test func summarizeCoCapTenBieuThucBindDuoc() throws {
        let text = "SUMMARIZE(Fact_Trans, Dim_Client[client_region], \"Số GD\", COUNTROWS(Fact_Trans))"
        let bound = try Binder.bind(try parseExpression(text), catalog: Catalog(schema: MiniBank.schema))
        guard case .call(let fid, let args) = bound else {
            Issue.record("SUMMARIZE phải bind thành lời gọi hàm")
            return
        }
        #expect(FunctionRegistry.all[Int(fid.raw)].name == "SUMMARIZE")
        #expect(args.count == 4, "bảng, một cột nhóm, tên, biểu thức")
        guard let first = args[0], case .table = first else {
            Issue.record("đối số 0 phải là bảng")
            return
        }
        if case .column(let column)? = args[1] {
            #expect(column == MiniBank.Columns.DimClient.clientRegion, "cột nhóm của bảng liên quan")
        } else {
            Issue.record("đối số 1 phải là cột Dim_Client[client_region]")
        }
        if case .literal(.string(let name))? = args[2] {
            #expect(name == "Số GD", "tên cột giữ nguyên là chuỗi")
        } else {
            Issue.record("đối số 2 phải là chuỗi tên cột")
        }
        if case .call(let cid, _)? = args[3] {
            #expect(FunctionRegistry.all[Int(cid.raw)].name == "COUNTROWS")
        } else {
            Issue.record("đối số 3 phải là lời gọi COUNTROWS")
        }
    }

    @Test func summarizeNhieuCotNhomRoiCapTen() throws {
        let text = "SUMMARIZE(Fact_Trans, Dim_Client[client_region], Fact_Trans[account_key], \"a\", 1, \"b\", 2)"
        #expect(langSummarizeError(text) == nil)
    }

    @Test func summarizeKhongCotNhomChiCapTen() throws {
        #expect(langSummarizeError("SUMMARIZE(Fact_Trans, \"Số GD\", COUNTROWS(Fact_Trans))") == nil)
    }

    @Test func summarizeBieuThucIgnoreChiBaoIgnoreChuaCo() throws {
        // Biểu thức là lời gọi bất kỳ: không báo lỗi tham số. IGNORE không có trong registry của SUMMARIZE,
        // nên lỗi duy nhất là tên hàm chưa nhận ra.
        let error = langSummarizeError("SUMMARIZE(Fact_Trans, Dim_Client[client_region], \"n\", IGNORE(COUNTROWS(Fact_Trans)))")
        #expect(error?.kind == .unknownName)
        #expect(error?.message.contains("IGNORE") == true)
    }

    @Test func tenCotSaiTrongSummarizeCoViTri() throws {
        // Dim_Client[khongco] bắt đầu ở cột 23 của dòng 1.
        let error = langSummarizeError("SUMMARIZE(Fact_Trans, Dim_Client[khongco], \"Số GD\", COUNTROWS(Fact_Trans))")
        #expect(error?.kind == .unknownName)
        #expect(error?.range?.line == 1)
        #expect(error?.range?.column == 23)
    }

    @Test func hamLapKhacKhongBiAnhHuong() throws {
        // Hồi quy: các hàm có tham số lặp vẫn bind đúng như trước.
        let cases = [
            "IF(1 > 0, 1, 2)",
            "SWITCH(1, 1, \"a\", \"b\")",
            "COALESCE(1, 2)",
            "CONCATENATEX(Dim_Account, Dim_Account[card_type], \",\")",
            "RANKX(ALL(Dim_Account), Dim_Account[branch_city], , DESC, DENSE)",
            "TOPN(3, Dim_Account, Dim_Account[account_key], DESC)",
            "ADDCOLUMNS(Dim_Account, \"x\", 1)",
            "CROSSJOIN(Dim_Account, Dim_District)",
            "VALUES(Dim_Account[card_type])",
            "ALL(Dim_Account[card_type], Dim_Account[branch_city])",
            "SUMMARIZE(Dim_Account, Dim_Account[card_type])",
        ]
        for text in cases {
            #expect(langSummarizeError(text) == nil, "bind lỗi: \(text)")
        }
    }

    // MARK: - Đánh giá

    @Test func summarizeCoCapTenDanhGiaDungSoDong() throws {
        let env = LANGSummarizeEnv()
        let tv = try env.table("SUMMARIZE(Fact_Trans, Dim_Client[client_region], \"Số GD\", COUNTROWS(Fact_Trans))")
        #expect(tv.columns == ["Dim_Client[client_region]", "Số GD"], "tên cột nhóm theo Bảng[cột], rồi tên đặt ở \"tên\"")
        #expect(tv.rows.count == 4, "Unknown, Miền Bắc, Miền Trung, BLANK")

        var counts: [String: Value] = [:]
        for row in tv.rows {
            let key: String
            if case .string(let s) = row[0] { key = s } else { key = "BLANK" }
            counts[key] = row[1]
        }
        #expect(counts["Unknown"] == .integer(7))
        #expect(counts["Miền Bắc"] == .integer(16))
        #expect(counts["Miền Trung"] == .integer(16))
        #expect(counts["BLANK"] == .integer(1))
    }
}
