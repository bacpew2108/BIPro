// Dữ liệu thô của MiniBank. SINH TỰ ĐỘNG bởi script Python stdlib (không sửa tay).
// Dim_Date không nằm ở đây: MiniBank.swift sinh 731 ngày bằng công thức lịch.
// Cột client_region của Fact_Trans là giá trị lưu sẵn do Python tính (cột tính toán, isCalculated = true).

enum MiniBankRaw {
    // MARK: Dim_Client (6 dòng, dòng đầu là Unknown với khoá -1)
    static let clientKey: [Int64] = [
        -1, 1, 2, 3, 4, 5,
    ]
    static let clientRegion: [String] = [
        "Unknown", "Miền Bắc", "Miền Trung", "Miền Nam",
        "Miền Bắc", "Miền Nam",
    ]

    // MARK: Dim_Account (5 dòng)
    static let accountKey: [Int64] = [1, 2, 3, 4, 5]
    static let accountClientKey: [Int64] = [1, 2, 2, 4, -1]
    static let accountBranchCity: [String] = ["Hà Nội", "Đà Nẵng", "TP. Hồ Chí Minh", "Hà Nội", "Đà Nẵng"]
    static let accountCardType: [String] = ["Debit", "Credit", "No Card", "Debit", "Credit"]

    // MARK: Dim_District (3 dòng, không có quan hệ với Dim_Account)
    static let districtCity: [String] = ["Hà Nội", "Đà Nẵng", "TP. Hồ Chí Minh"]
    static let districtStateName: [String] = ["Thành phố Hà Nội", "Thành phố Đà Nẵng", "Thành phố Hồ Chí Minh"]

    // MARK: Fact_Trans (40 dòng, sắp theo ngày; FK 99 không khớp Dim_Account đúng 1 dòng)
    static let transKey: [Int64] = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
        11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
        31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    ]
    static let transDateKey: [Int64] = [
        20230110, 20230117, 20230127, 20230202, 20230408, 20230418, 20230421, 20230425, 20230623, 20230805,
        20230809, 20230817, 20230826, 20230917, 20230919, 20230920, 20230925, 20231012, 20231028, 20231203,
        20240124, 20240213, 20240223, 20240312, 20240415, 20240430, 20240518, 20240527, 20240603, 20240629,
        20240711, 20240716, 20240817, 20240823, 20240906, 20240924, 20241104, 20241106, 20241202, 20241225,
    ]
    static let transAccountKey: [Int64] = [
        5, 4, 2, 4, 2, 2, 2, 1, 1, 4,
        4, 4, 3, 4, 4, 5, 3, 5, 3, 2,
        2, 5, 2, 3, 1, 1, 2, 3, 1, 5,
        3, 5, 99, 3, 1, 1, 3, 5, 4, 1,
    ]
    /// Đơn vị currency: Int64 đã nhân 10^4 (ví dụ 1,5 = 15000).
    static let transAmount: [Int64] = [
        32613500, 32355100, 5314400, 27559500, 6161800, 19186000, -6389400, -9505400, 39292200, 46886400,
        33685800, 47612300, 69748700, 27788500, 31626300, -7916100, 58835900, 46248900, 39071000, 26055300,
        -8926400, 25495000, 64000000, 16154000, 56235200, 49856300, 23197100, 48655500, 34205800, -1758200,
        56979900, 42641700, -2031000, 34494400, 37531800, 47467800, 54160600, 55541900, 41215500, 12950400,
    ]
    /// Số dư sau giao dịch, dạng currency (nhân 10^4). Lưu dạng encoded.
    static let transBalanceAfter: [Int64] = [
        22613500, 232355100, 55314400, 259914600, 61476200, 80662200, 74272800, 90494600, 129786800, 306801000,
        340486800, 388099100, 69748700, 415887600, 447513900, 14697400, 128584600, 60946300, 167655600, 100328100,
        91401700, 86441300, 155401700, 183809600, 186022000, 235878300, 178598800, 232465100, 270084100, 84683100,
        289445000, 127324800, -2031000, 323939400, 307615900, 355083700, 378100000, 182866700, 488729400, 368034100,
    ]
    /// Cột tính toán client_region = RELATED(Dim_Client[client_region]) qua Dim_Account; nil là BLANK (FK 99).
    static let transClientRegion: [String?] = [
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

    // MARK: Fact_Complaint (12 dòng)
    static let complaintKey: [Int64] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    static let complaintReceivedDateKey: [Int64] = [20240430, 20230315, 20230507, 20240825, 20240527, 20240416, 20240509, 20230415, 20240602, 20230501, 20240727, 20240516]
    static let complaintSentDateKey: [Int64] = [20240506, 20230319, 20230512, 20240830, 20240530, 20240429, 20240523, 20230422, 20240617, 20230521, 20240731, 20240526]
    static let complaintClientKey: [Int64] = [-1, 1, 4, 5, 3, -1, -1, -1, 1, -1, 1, 5]
}
