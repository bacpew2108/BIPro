// Kiểm tra CALCULATE và CALCULATETABLE trên MiniBank (CORE, đợt 2), architecture.md §4.1, §5.4.
// Đáp án: 2024 có 20 giao dịch, 2023 có 20; ISBLANK(branch_city) chỉ FK 99 (1 giao dịch).
// Complaint: 12 khiếu nại; sent_date_key = 20240506 có đúng 1 khiếu nại, received_date_key không có 20240506.
// [SUY ĐOÁN] Thứ tự bộ sửa đổi trước bộ lọc (REMOVEFILTERS trước Dim_Date[year] = 2024) theo §5.4 bước 3–4.
import Testing
import ColumnStore
import DAXEngine
import DAXTestSupport

@Suite struct CORECalculateTests {
    @Test func calculateLocTheoCot() throws {
        let env = CoreEnvironment()
        #expect(try evaluateText("CALCULATE ( [Trans Count], Dim_Date[year] = 2024 )", in: env) == .integer(20))
        #expect(try evaluateText("CALCULATE ( [Trans Amount], Dim_Date[year] = 2024 )", in: env)
                == .currency(688_067_300))
    }

    @Test func calculateVoiViNguBlank() throws {
        let env = CoreEnvironment()
        #expect(try evaluateText("CALCULATE ( [Trans Count], ISBLANK ( Dim_Account[branch_city] ) )", in: env)
                == .integer(1))
    }

    @Test func boLocTrongGhiDeNguCanhNgoai() throws {
        // Không KEEPFILTERS: bộ lọc trong CALCULATE trong ghi đè bộ lọc ngoài.
        let env = CoreEnvironment()
        #expect(try evaluateText(
            "CALCULATE ( CALCULATE ( [Trans Count], Dim_Date[year] = 2023 ), Dim_Date[year] = 2024 )", in: env)
            == .integer(20))
        #expect(try evaluateText(
            "CALCULATE ( CALCULATE ( [Trans Count], Dim_Date[year] = 2024 || Dim_Date[year] = 2023 ), Dim_Date[year] = 2024 )",
            in: env) == .integer(40))
    }

    @Test func keepFiltersGiaoVoiNguCanhNgoai() throws {
        // Có KEEPFILTERS trong trong: giao {2024} (ngữ cảnh ngoài) với {2024, 2023} ra {2024}, nên 20.
        let env = CoreEnvironment()
        let value = try evaluateText(
            "CALCULATE ( CALCULATE ( [Trans Count], KEEPFILTERS ( Dim_Date[year] = 2024 || Dim_Date[year] = 2023 ) ), Dim_Date[year] = 2024 )",
            in: env)
        #expect(value == .integer(20))
    }

    @Test func keepFiltersGiaoRong() throws {
        // Ngữ cảnh ngoài {2023}, KEEPFILTERS {2024}: giao rỗng.
        let env = CoreEnvironment()
        let value = try evaluateText(
            "CALCULATE ( CALCULATE ( [Trans Count], KEEPFILTERS ( Dim_Date[year] = 2024 ) ), Dim_Date[year] = 2023 )",
            in: env)
        #expect(value == .integer(0))
    }

    @Test func removeFiltersChieuBoLocNgoai() throws {
        // REMOVEFILTERS(Dim_Date) trong CALCULATE trong xoá bộ lọc năm 2024 của ngữ cảnh ngoài.
        let env = CoreEnvironment()
        let value = try evaluateText(
            "CALCULATE ( CALCULATE ( [Trans Count], REMOVEFILTERS ( Dim_Date ) ), Dim_Date[year] = 2024 )", in: env)
        #expect(value == .integer(40))
    }

    @Test func removeFiltersApDungTruocBoLocTrongCungCalculate() throws {
        // [SUY ĐOÁN] Bộ sửa đổi (bước 3) áp trước bộ lọc (bước 4): bộ lọc 2024 trong cùng CALCULATE vẫn còn.
        let env = CoreEnvironment()
        let value = try evaluateText("CALCULATE ( [Trans Count], Dim_Date[year] = 2024, REMOVEFILTERS ( Dim_Date ) )", in: env)
        #expect(value == .integer(20))
    }

    @Test func userRelationshipKichHoatQuanHeKhongActive() throws {
        // Mặc định Complaint_ReceivedDate (active): không có khiếu nại nhận ngày 20240506.
        // USERELATIONSHIP(sent, date_key): có đúng 1 khiếu nại gửi ngày 20240506.
        let env = CoreEnvironment()
        #expect(try evaluateText("CALCULATE ( COUNTROWS ( Fact_Complaint ), Dim_Date[date_key] = 20240506 )", in: env)
                == .integer(0))
        let value = try evaluateText(
            "CALCULATE ( COUNTROWS ( Fact_Complaint ), USERELATIONSHIP ( Fact_Complaint[sent_date_key], Dim_Date[date_key] ), Dim_Date[date_key] = 20240506 )",
            in: env)
        #expect(value == .integer(1))
    }

    @Test func calculateTableTheoBoLoc() throws {
        let env = CoreEnvironment()
        let value = try evaluateText("COUNTROWS ( CALCULATETABLE ( Fact_Trans, Dim_Date[year] = 2024 ) )", in: env)
        #expect(value == .integer(20))
    }

    @Test func boLocBangVatLyFilterKhongMaterialize() throws {
        // FILTER(Fact_Trans, …) trong CALCULATE đi theo đường tập dòng, không materialize.
        let env = CoreEnvironment()
        let expected = MiniBankExpected.transClientRegion.filter { $0 == "Miền Bắc" }.count
        let value = try evaluateText(
            "CALCULATE ( [Trans Count], FILTER ( Fact_Trans, Fact_Trans[client_region] = \"Miền Bắc\" ) )", in: env)
        #expect(value == .integer(Int64(expected)))
        #expect(env.evaluator.materializedRowCount == 0)
    }

    @Test func coTruongHopMotGiaTriDonTheoBoLoc() throws {
        // Không có row context: cột có đúng một giá trị trong bộ lọc thì trả giá trị đó.
        let env = CoreEnvironment()
        let value = try evaluateText("CALCULATE ( Dim_Account[card_type], Dim_Account[card_type] = \"No Card\" )", in: env)
        #expect(value == .string("No Card"))
    }

    @Test func cotNhieuGiaTriKhongCoRowContextLoi() throws {
        let env = CoreEnvironment()
        do {
            _ = try evaluateText("Dim_Account[card_type]", in: env)
            Issue.record("kỳ vọng lỗi nhiều giá trị")
        } catch let error as DAXError {
            #expect(error.kind == .multipleValues)
        }
    }
}
