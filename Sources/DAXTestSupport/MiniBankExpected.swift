// Đáp án kỳ vọng của MiniBank. SINH TỰ ĐỘNG bởi script Python stdlib (không sửa tay).
// Cách tính: Python đọc đúng các dòng dữ liệu trong MiniBankData.swift và tính bằng số nguyên hoặc Fraction;
// không dùng Swift để tính đáp án. Đơn vị currency là Int64 nhân 10^4.
// Quy ước bộ lọc: 'Bảng[cột]=giá trị' nối bằng ' && '; '(BLANK)' nghĩa là BLANK; chuỗi rỗng là không lọc.
// Avg Balance: VALUES của khoá tài khoản trong Fact_Trans (gồm 99); số dư lấy tại ngày muộn nhất của từng khoá.
// Trans Amount Δ: khuôn Nhom6 (SAMEPERIODLASTYEAR + REMOVEFILTERS), rút gọn cho 2 năm.

public enum MiniBankExpectedValue: Sendable, Equatable {
    case integer(Int64)
    case currency(Int64)
    case double(Double)
    case blank
}

public struct MiniBankExpectation: Sendable, Equatable {
    public let measure: String
    /// Bộ lọc theo quy ước của file này; chuỗi rỗng là không lọc.
    public let filter: String
    public let value: MiniBankExpectedValue
    /// Ghi chú cách tính.
    public let note: String

    public init(measure: String, filter: String, value: MiniBankExpectedValue, note: String) {
        self.measure = measure
        self.filter = filter
        self.value = value
        self.note = note
    }
}

public enum MiniBankExpected {
    public static let all: [MiniBankExpectation] = [
        MiniBankExpectation(measure: "Trans Amount", filter: "", value: .currency(1254298000),
            note: "Tổng cột amount của 40 dòng, nhân 10^4."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Dim_Date[year]=2023", value: .currency(566230700),
            note: "Dòng có năm 2023."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Dim_Date[year]=2024", value: .currency(688067300),
            note: "Dòng có năm 2024."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Dim_Account[branch_city]=Hà Nội", value: .currency(556763500),
            note: "Lan truyền qua Dim_Account (tài khoản 1 và 4)."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Dim_Account[card_type]=No Card", value: .currency(378100000),
            note: "Chỉ tài khoản 3."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Dim_Client[client_region]=Miền Bắc", value: .currency(556763500),
            note: "Hai bước: Fact_Trans -> Dim_Account -> Dim_Client."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Fact_Trans[client_region]=Unknown", value: .currency(192866700),
            note: "Tài khoản 5 thuộc client_key -1."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Dim_Account[branch_city]=(BLANK)", value: .currency(-2031000),
            note: "Dòng FK 99 đi vào blank row của Dim_Account."),
        MiniBankExpectation(measure: "Trans Amount", filter: "Dim_Date[year]=2024 && Dim_Account[branch_city]=Hà Nội", value: .currency(279462800),
            note: "Giao hai bộ lọc."),
        MiniBankExpectation(measure: "Trans Count", filter: "", value: .integer(40),
            note: "COUNTROWS của Fact_Trans."),
        MiniBankExpectation(measure: "Trans Count", filter: "Dim_Date[year]=2024", value: .integer(20),
            note: "Dòng có năm 2024."),
        MiniBankExpectation(measure: "Trans Count", filter: "Dim_Account[branch_city]=(BLANK)", value: .integer(1),
            note: "Chỉ dòng FK 99."),
        MiniBankExpectation(measure: "Avg Balance", filter: "", value: .currency(265716333),
            note: "Trung bình số dư tại ngày muộn nhất trên 6 khoá tài khoản (gồm 99). Đáp án 1 594 294 000 / 6 = 265 716 333,33 đơn vị ×10^4, làm tròn về đơn vị ×10^4 nguyên (kiểu currency)."),
        MiniBankExpectation(measure: "Trans Amount Δ", filter: "", value: .double(0.21517130738407508),
            note: "Δ = (cur - prev) / prev. cur = tổng từ 01/01 năm cuối đến ngày muộn nhất; prev = cùng kỳ năm trước. Không có 28/02 và 29/02 trong dữ liệu nên ánh xạ không mơ hồ."),
    ]

    /// Client_region đúng từng dòng của Fact_Trans (đáp án của cột tính toán O-CC).
    public static let transClientRegion: [String?] = [
        "Unknown", "Miền Bắc", "Miền Trung", "Miền Bắc",
        "Miền Trung", "Miền Trung", "Miền Trung", "Miền Bắc",
        "Miền Bắc", "Miền Bắc", "Miền Bắc", "Miền Bắc",
        "Miền Trung", "Miền Bắc", "Miền Bắc", "Unknown",
        "Miền Trung", "Unknown", "Miền Trung", "Miền Trung",
        "Miền Trung", "Unknown", "Miền Trung", "Miền Trung",
        "Miền Bắc", "Miền Bắc", "Miền Trung", "Miền Trung",
        "Miền Bắc", "Unknown", "Miền Trung", "Unknown",
        nil, "Miền Trung", "Miền Bắc", "Miền Bắc",
        "Miền Trung", "Unknown", "Miền Bắc", "Miền Bắc",
    ]

    /// Tổng amount (currency, nhân 10^4) tính từ dữ liệu thô.
    public static let totalAmount: Int64 = 1254298000
}
