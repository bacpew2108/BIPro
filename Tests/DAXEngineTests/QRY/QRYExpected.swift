// Đáp án của test QRY trên MiniBank. Sinh bằng Python stdlib đọc MiniBankData.swift (không tính bằng Swift).
// Tổng tiền dạng currency (nhân 10^4): 1254298000 = 125429,8.
enum QRYExpected {
    /// Hai năm trong Dim_Date, sắp tăng dần.
    static let years: [Int64] = [2023, 2024]

    /// SUM(Fact_Trans[amount]) theo năm, currency (nhân 10^4).
    static let amountByYear: [Int64: Int64] = [2023: 566_230_700, 2024: 688_067_300]
    static let amountTotal: Int64 = 1_254_298_000

    /// COUNTROWS(Fact_Trans) theo năm.
    static let countByYear: [Int64: Int64] = [2023: 20, 2024: 20]

    /// Số giao dịch có amount > 0 theo năm (FILTER(Fact_Trans, amount > 0)).
    static let positiveCountByYear: [Int64: Int64] = [2023: 17, 2024: 17]

    /// Số giao dịch theo client_region của Fact_Trans (cột tính toán lưu sẵn); "BLANK" là FK 99.
    static let countByRegion: [String: Int64] = ["BLANK": 1, "Miền Bắc": 16, "Miền Trung": 16, "Unknown": 7]

    /// Số giao dịch theo card_type của Dim_Account; "BLANK" là dòng không khớp (FK 99).
    static let countByCardType: [String: Int64] = ["BLANK": 1, "Credit": 15, "Debit": 16, "No Card": 8]
}
