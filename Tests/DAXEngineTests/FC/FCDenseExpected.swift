// FCDenseExpected.swift: đáp án của test lọc theo giá trị trên cột dense (FC, đợt 3).
// SINH TỰ ĐỘNG bởi scratchpad/fc3b/fc_dense_oracle.py (Python 3 stdlib, đọc MiniBankData.swift).
// Không sửa tay. Số đếm: dim = số ngày của Dim_Date thấy được, fact = số giao dịch thấy được, sum = tổng amount (×10^4).

enum FCDenseExpected {
    static let D1Dim = 1
    static let D1Fact = 1
    static let D1Sum: Int64 = 25495000
    static let R_JANDim = 31
    static let R_JANFact = 1
    static let R_JANSum: Int64 = -8926400
    static let R_Q1Dim = 91
    static let R_Q1Fact = 4
    static let R_Q1Sum: Int64 = 96722600
    static let SETDim = 3
    static let SETFact = 3
    static let SETSum: Int64 = 92450300
    static let NODATADim = 1
    static let NODATAFact = 0
    static let NODATASum: Int64 = 0
    static let R_JAN_AND_2023Dim = 0
    static let R_JAN_AND_2023Fact = 0
    static let R_JAN_AND_2023Sum: Int64 = 0
    static let R_JAN_AND_2024Dim = 31
    static let R_JAN_AND_2024Fact = 1
    static let R_JAN_AND_2024Sum: Int64 = -8926400
    static let R_Q1_KEEP_KEEPDim = 1
    static let R_Q1_KEEP_KEEPFact = 1
    static let R_Q1_KEEP_KEEPSum: Int64 = -8926400
    static let ALLDim = 731
    static let ALLFact = 40
    static let ALLSum: Int64 = 1254298000
    static let amountPairFact = 2
    static let amountPairSum: Int64 = 30582500
    static let amount203Fact = 1
}

/// Số serial OLE của các ngày dùng trong test (ngày 0 là 1899-12-30).
enum FCDenseSerial {
    static let d20230101: Double = 44927
    static let d20230110: Double = 44936
    static let d20230805: Double = 45143
    static let d20231231: Double = 45291
    static let d20240101: Double = 45292
    static let d20240124: Double = 45315
    static let d20240131: Double = 45322
    static let d20240213: Double = 45335
    static let d20240331: Double = 45382
    static let d20240601: Double = 45444
    static let d20241225: Double = 45651
    static let d20241231: Double = 45657
    static let d20300101: Double = 47484
}
