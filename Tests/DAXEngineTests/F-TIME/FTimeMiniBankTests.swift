// Measure time intelligence trên MiniBank (F-TIME, đợt 3): khuôn Δ, cùng kỳ năm trước, tháng trước, và lỗi khi bảng ngày
// chưa được đánh dấu.
// Đáp án Python (scratchpad/ftime3/oracle_ftime.py):
//   Δ = 0.21517130738407508; 2023 = 566230700 (currency ×10^4); tháng trước giao với năm 2024 = 633901400.
//
// Hai giới hạn không thuộc WP F-TIME, nên các test liên quan được tắt có lý do (không đổi đáp án):
// - MAX (F-AGG+TABLE, đợt 3) chưa cài: measure "Trans Amount Δ" gốc dùng MAX(Fact_Trans[date_key]); SUMX cũng vậy.
// - FilterContext chưa lọc theo giá trị trên cột dense (đợt 2a): Dim_Date[full_date] trong MiniBank là cột dense,
//   nên mọi CALCULATE nhận bảng ngày báo `.runtime` "Lọc theo giá trị trên cột dense ... chưa được hỗ trợ".
//   Các test trên MiniBank gốc để trong withKnownIssue; khi FC hỗ trợ thì known issue không xảy ra và Swift Testing báo,
//   lúc đó chuyển thành kiểm tra thường.
// Các test logic chạy trên biến thể FTEncodedDateSource (dữ liệu giống hệt, full_date mã hoá).
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FTimeMiniBankTests {

    private let dapAnDelta = 0.21517130738407508
    private let dapAnNam2023 = Value.currency(566_230_700)

    private func layDouble(_ value: Value) -> Double? {
        if case .double(let d) = value { return d }
        return nil
    }

    // MARK: - Trên biến thể mã hoá (kiểm logic F-TIME)

    @Test func deltaKhuonTrenBienThaiMaHoaKhopDapAn() async throws {
        let engine = ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
        let value = try await engine.evaluate(measure: "Delta Khuon", table: "Fact_Trans", filters: [])
        guard let d = layDouble(value) else {
            Issue.record("kỳ vọng số thực, nhận \(value)")
            return
        }
        #expect(abs(d - dapAnDelta) < 1e-12, "Δ khuôn = \(d), đáp án Python \(dapAnDelta)")
    }

    @Test func deltaMiniBankKhopDapAnKhiCoMax() async throws {
        let engine = ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
        let value = try await engine.evaluate(measure: "Trans Amount Δ", table: "Fact_Trans", filters: [])
        guard let d = layDouble(value) else {
            Issue.record("kỳ vọng số thực, nhận \(value)")
            return
        }
        #expect(abs(d - dapAnDelta) < 1e-12)
    }

    @Test func cungKyNamTruocGiaoBoLocNamThanhBlank() async throws {
        // Ngữ cảnh năm 2024: SAMEPERIODLASTYEAR cho 2023, nhưng bộ lọc năm 2024 còn lại nên giao rỗng: BLANK.
        let engine = ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
        let value = try await engine.evaluate(measure: "Prev Year Amount", table: "Fact_Trans", filters: [ftNam(2024)])
        #expect(value == .blank)
    }

    @Test func cungKyNamTruocBoLocNamRaNam2023() async throws {
        // REMOVEFILTERS(Dim_Date) trước khi áp ngày: 2023 có tổng 566230700.
        let engine = ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
        let value = try await engine.evaluate(measure: "Prev Year Amount Bo Loc Nam", table: "Fact_Trans",
                                              filters: [ftNam(2024)])
        #expect(value == dapAnNam2023)
    }

    @Test func cungKyNamTruocNam2023LaBlank() async throws {
        // Ngữ cảnh năm 2023: năm trước là 2022, không có dữ liệu, nên SUM là BLANK.
        let engine = ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
        let value = try await engine.evaluate(measure: "Prev Year Amount Bo Loc Nam", table: "Fact_Trans",
                                              filters: [ftNam(2023)])
        #expect(value == .blank)
    }

    @Test func thangTruocGiaoNam2024KhopDapAn() async throws {
        // Python: tổng giao dịch có ngày thuộc (DATEADD ngày 2024, -1 tháng) ∩ năm 2024 = 633901400.
        let engine = ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
        let value = try await engine.evaluate(measure: "Prev Month Amount", table: "Fact_Trans", filters: [ftNam(2024)])
        #expect(value == .currency(633_901_400))
    }

    @Test func sumxTheoNgayKhopDapAn() async throws {
        // Row context: 366 ngày của 2024, mỗi ngày lấy giao dịch cùng ngày năm trước; tổng = 566230700 (Python).
        let engine = ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
        let value = try await engine.evaluate(measure: "Prev Year Sumx", table: "Fact_Trans", filters: [])
        #expect(value == dapAnNam2023)
    }

    // MARK: - Trên MiniBank gốc (cột full_date dense; FC lọc theo giá trị cột dense từ đợt 3b)

    @Test func deltaKhuonTrenMiniBankGoc() async throws {
        let engine = ftEngine(MiniBank.makeSource())
        let value = try await engine.evaluate(measure: "Delta Khuon", table: "Fact_Trans", filters: [])
        let d = layDouble(value) ?? .nan
        #expect(abs(d - dapAnDelta) < 1e-12)
    }

    @Test func cungKyNamTruocTrenMiniBankGoc() async throws {
        let engine = ftEngine(MiniBank.makeSource())
        let value = try await engine.evaluate(measure: "Prev Year Amount Bo Loc Nam", table: "Fact_Trans",
                                              filters: [ftNam(2024)])
        #expect(value == dapAnNam2023)
    }

    // MARK: - Lỗi khi bảng ngày chưa được đánh dấu hoặc thiếu cột ngày

    @Test func bangNgayChuaDanhDauBaoLoi() async {
        let engine = ftEngine(FTUnmarkedSource(base: MiniBank.makeSource()))
        await ftExpectDAXError(engine, "EVALUATE SAMEPERIODLASTYEAR ( VALUES ( Dim_Date[full_date] ) )",
                               kind: .runtime, contains: "dataCategory")
        await ftExpectDAXError(engine, "EVALUATE DATEADD ( Dim_Date[full_date], -1, YEAR )",
                               kind: .runtime, contains: "chưa được đánh dấu")
    }

    @Test func thieuCotNgayBaoLoi() async {
        let engine = ftEngine(MiniBank.makeSource())
        // Cột khoá dạng số nguyên (date_key) không phải cột ngày.
        await ftExpectDAXError(engine, "EVALUATE DATEADD ( VALUES ( Dim_Date[date_key] ), -1, YEAR )",
                               kind: .runtime, contains: "không phải cột ngày")
        // Cả bảng không phải một cột ngày.
        await ftExpectDAXError(engine, "EVALUATE SAMEPERIODLASTYEAR ( Dim_Date )",
                               kind: .runtime, contains: "một cột ngày")
    }

    @Test func soKhoangLeBaoLoi() async {
        let engine = ftEngine(MiniBank.makeSource())
        await ftExpectDAXError(engine, "EVALUATE DATEADD ( VALUES ( Dim_Date[full_date] ), 1.5, YEAR )",
                               kind: .typeMismatch, contains: "số nguyên")
    }
}
