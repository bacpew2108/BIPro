// Hỗ trợ test cho WP F-FILTER (đợt 3): ALL, ALLSELECTED, ALLNOBLANKROW, ALLEXCEPT, TREATAS, USERELATIONSHIP,
// CROSSFILTER, ISFILTERED, ISCROSSFILTERED, HASONEVALUE, SELECTEDVALUE trên MiniBank.
// Mọi đáp án trong FFExpected lấy từ ffilter_oracle.py (Python 3 stdlib, đọc MiniBankData.swift). Không dùng Swift để tính
// đáp án. Đơn vị currency là Int64 nhân 10^4; khi so với số hiển thị thì chia 10^4.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

/// Môi trường MiniBank có measure (Trans Amount, Trans Count…), dùng cả đường trực tiếp lẫn DAXEngine.
struct FFEnv {
    let store: ColumnStore
    let catalog: Catalog
    let evaluator: Evaluator
    let engine: DAXEngine

    init() {
        let store = MiniBank.makeStore()
        let catalog = Catalog(
            schema: MiniBank.schema,
            measures: MiniBank.measures.map { ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression) })
        self.store = store
        self.catalog = catalog
        self.evaluator = Evaluator(store: store, catalog: catalog)
        self.engine = DAXEngine(store: store, catalog: catalog)
    }

    /// Ngữ cảnh gốc: không lọc, có lược đồ để tra quan hệ (USERELATIONSHIP, CROSSFILTER).
    var base: FilterContext {
        FilterContext.empty.bound(to: store.schema)
    }

    /// Bộ lọc một cột theo tên bảng và tên cột trong MiniBank.
    func filter(_ table: String, _ column: String, _ values: [Value]) throws -> FilterContext {
        guard let meta = store.schema.column(table: table, name: column) else {
            throw DAXError(.unknownName, "không có cột \(table)[\(column)]")
        }
        return FilterContext(items: [FilterItem(column: meta.id, values: values)]).bound(to: store.schema)
    }

    /// Đánh giá một biểu thức vô hướng (không row context).
    func value(_ text: String, filter: FilterContext? = nil) throws -> Value {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        return try evaluator.scalar(expr, in: EvalContext(filter: filter ?? base, row: nil))
    }

    /// Đánh giá một biểu thức bảng (không row context).
    func table(_ text: String, filter: FilterContext? = nil) throws -> TableValue {
        let expr = try Binder.bind(try parseExpression(text), catalog: catalog)
        return try evaluator.table(expr, in: EvalContext(filter: filter ?? base, row: nil))
    }

    /// Chạy một truy vấn DAX và lấy bảng kết quả đầu tiên.
    func query(_ text: String) async throws -> ResultTable {
        let result = try await engine.execute(text)
        return result.tables[0]
    }
}

/// Loại lỗi DAX của một lời gọi; nil nếu thành công.
func ffKindOf(_ body: () throws -> Value) -> DAXError.Kind? {
    do {
        _ = try body()
        return nil
    } catch let error as DAXError {
        return error.kind
    } catch {
        return nil
    }
}

/// Nhãn nhóm của một ô cột nhóm: tên card_type, hoặc "BLANK".
func ffNhan(_ value: Value) -> String {
    switch value {
    case .string(let s): return s
    case .blank: return "BLANK"
    default: return "\(value)"
    }
}

/// Đáp án MiniBank cho WP F-FILTER (ffilter_oracle.py).
enum FFExpected {
    // Tổng và theo card_type (BLANK là FK 99 không khớp Dim_Account, dòng 33 của Fact_Trans).
    static let totalAmount: Int64 = 1_254_298_000
    static let cardTotal: [String: Int64] = ["Credit": 321_465_500, "Debit": 556_763_500, "No Card": 378_100_000, "BLANK": -2_031_000]
    static let cardTotal2024: [String: Int64] = ["Credit": 200_191_100, "Debit": 279_462_800, "No Card": 210_444_400, "BLANK": -2_031_000]
    static let total2024: Int64 = 688_067_300
    static let cardCount2024: [String: Int64] = ["Credit": 7, "Debit": 7, "No Card": 5, "BLANK": 1]

    // Tỉ lệ (amount nhóm / tổng), không slicer và có slicer năm 2024.
    static let shareAll: [String: Double] = [
        "Credit": 0.25629116844641386, "Debit": 0.44388454737231503,
        "No Card": 0.30144351661247965, "BLANK": -0.0016192324312085326,
    ]
    static let share2024: [String: Double] = [
        "Credit": 0.2909469756810126, "Debit": 0.4061562001275166,
        "No Card": 0.3058485703360703, "BLANK": -0.002951746144599518,
    ]

    // Số nhóm card_type có tổng (đơn vị hiển thị) >= 35000: Debit (55676,35) và No Card (37810).
    static let groupsAmountAtLeast35000 = 2

    // Bảng ALL: Dim_Date 731 ngày; Dim_Account 5 dòng + 1 dòng BLANK ảo (FK 99); bỏ BLANK ảo còn 5;
    // branch_city có 3 giá trị + BLANK = 4; client_region có 4 giá trị (không có BLANK).
    static let allDimDate = 731
    static let allDimAccount = 6
    static let allNoBlankRowDimAccount = 5
    static let allBranchCity = 4
    static let allClientRegion = 4

    // Tài khoản Debit là 1 và 4; không tài khoản Debit nào ở Đà Nẵng.
    static let debitAccounts = 2
    static let debitAndDaNang = 0

    // Fact_Complaint: 12 dòng. Tháng 5 theo sent_date_key là 6, theo received_date_key là 5. Sent năm 2023 là 4.
    static let complaintSentMonth5 = 6
    static let complaintReceivedMonth5 = 5
    static let complaintSentYear2023 = 4

    // Fact_Trans có client_region Miền Trung: 16 dòng, tổng 506698800 (currency nhân 10^4).
    static let mienTrungAmount: Int64 = 506_698_800

    // Dim_District: 3 dòng (Hà Nội/Thành phố Hà Nội, Đà Nẵng/Thành phố Đà Nẵng, TP. Hồ Chí Minh/Thành phố Hồ Chí Minh).
    static let districtTuplesMatchHcmHn = 2
    static let districtTuplesMismatch = 0
    static let districtTuplesAll = 3

    // Cross-filter: Dim_Account có 5 dòng khi không có bộ lọc; với Fact_Trans[client_region]=Miền Bắc và
    // CROSSFILTER BOTH, còn 2 tài khoản (1 và 4) có giao dịch Miền Bắc.
    static let dimAccountRowsPlain = 5
    static let dimAccountRowsMienBacBoth = 2
    static let debitAmount: Int64 = 556_763_500
}
