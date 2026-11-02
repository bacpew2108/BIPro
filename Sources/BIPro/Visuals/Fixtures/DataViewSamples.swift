// Dữ liệu mẫu cho renderer (đợt 0, lead). Worker dùng để vẽ và test mà không cần engine hay file Nhom6.
//
// Nguồn:
// - [PA] giá trị thật từ kết quả Power BI (docs/phase-b-evidence/observe2/PA-*.tsv) hoặc engine đã khớp Power BI;
// - [GIẢ LẬP] số tự đặt cho đủ hình dạng (số series, số cấp…), chỉ để vẽ, không dùng làm golden.
import DAXEngine
import Foundation

enum DataViewSamples {
    // MARK: Trường dùng chung

    static func measure(_ ref: String, _ name: String, role: String, format: String? = nil) -> FieldInfo {
        FieldInfo(queryRef: ref, displayName: name, role: role, formatString: format, isMeasure: true)
    }

    static func column(_ ref: String, _ name: String, role: String, format: String? = nil) -> FieldInfo {
        FieldInfo(queryRef: ref, displayName: name, role: role, formatString: format, isMeasure: false)
    }

    private static func cells(_ numbers: [Double], format: String? = nil) -> [DataCell] {
        numbers.map { DataCell(.double($0), formatString: format) }
    }

    private static func ints(_ numbers: [Int64], format: String? = nil) -> [DataCell] {
        numbers.map { DataCell(.integer($0), formatString: format) }
    }

    // MARK: Card

    /// [PA] card "Tiền vào" D1 (engine, đã khớp cách tính của Power BI). Định dạng là [GIẢ LẬP].
    static let cardCreditInflow = DataView.single(SingleValueData(
        measure: measure("Fact_Transaction.Total_Credit_Inflow", "Tiền vào", role: "Values", format: "\\$#,0"),
        cell: DataCell(.double(3_227_472_424.5), formatString: "\\$#,0")))

    /// [GIẢ LẬP] card "Δ Label": văn bản, màu chữ lấy từ measure `… Δ Color`.
    static let cardDeltaLabel = DataView.single(SingleValueData(
        measure: measure("Fact_Transaction.Total_Credit_Inflow Δ Label", "Total_Credit_Inflow Δ Label", role: "Values"),
        cell: DataCell(.string("▲ 12.4% so với kỳ trước"), fontColor: "#2E7D32")))

    // MARK: Combo (PA-D2-1)

    /// [PA] combo D2 "Giải ngân thay đổi thế nào theo thời gian?" ở cấp Năm: cột Y = Loan Amount, đường Y2 = Loan Count.
    static let comboLoansByYear = DataView.categorical(CategoricalData(
        categoryLevels: [column("Dim_Date.Thời gian.Năm", "Năm", role: "Category")],
        categories: (2013...2018).map { CategoryKey(values: [.integer(Int64($0))]) },
        seriesField: nil, series: [],
        measures: [measure("Fact_Loan.Loan Amount", "Giải ngân", role: "Y", format: "\\$#,0"),
                   measure("Fact_Loan.Loan Count", "Số khoản vay", role: "Y2", format: "#,0")],
        values: [[cells([2_619_276, 13_379_904, 13_344_372, 18_317_676, 30_731_364, 24_869_148], format: "\\$#,0")],
                 [ints([20, 101, 90, 117, 196, 158], format: "#,0")]],
        highlights: nil, isReduced: false))

    // MARK: Bar có màu từ measure (PA-D2-2)

    /// [PA] bar D2 "Nhóm tuổi lúc vay nào có tỷ lệ nợ xấu cao?": màu cột từ `NPL Group Color`, định dạng động "0%".
    static let barNPLByAge: DataView = {
        let colors = ["#C0392B", "#E65100", "#C0392B", "#C0392B"]
        let ratio = [0.13636363636363635, 0.08383233532934131, 0.1145374449339207, 0.11538461538461539]
        return .categorical(CategoricalData(
            categoryLevels: [column("Fact_Loan.age_group_at_loan", "Nhóm tuổi lúc vay", role: "Category")],
            categories: ["<25", "25-34", "35-49", "50-64"].map { CategoryKey(values: [.string($0)]) },
            seriesField: nil, series: [],
            measures: [measure("Fact_Loan.Bad_Debt_Ratio_Count", "NPL% (số HĐ)", role: "Y"),
                       measure("Fact_Loan.Bad_Debt_Ratio_Value", "NPL% (giá trị)", role: "Tooltips"),
                       measure("Fact_Loan.Bad Debt Loans", "Số HĐ nợ xấu", role: "Tooltips", format: "#,0"),
                       measure("Fact_Loan.Loan Count", "Số HĐ", role: "Tooltips", format: "#,0")],
            values: [[zip(ratio, colors).map { DataCell(.double($0), formatString: "0%", fillColor: $1) }],
                     [cells([0.1881770967769385, 0.1271969017255879, 0.14246748238773063, 0.15599505667412694], format: "0%")],
                     [ints([18, 14, 26, 18], format: "#,0")],
                     [ints([132, 167, 227, 156], format: "#,0")]],
            highlights: nil, isReduced: false))
    }()

    // MARK: Line trục liên tục (PA-D4-1)

    private static let monthly: [(String, Double, Int64)] = [
        ("2013-01", 702157.6, 177), ("2013-02", 2726925.3, 395), ("2013-03", 4730318.6, 676), ("2013-04", 7378367.8, 913),
        ("2013-05", 11680753.4, 1306), ("2013-06", 18291948.9, 1880), ("2013-07", 18021294.7, 2399), ("2013-08", 21028811.6, 2938),
        ("2013-09", 23438701.6, 3441), ("2013-10", 27570899.7, 3989), ("2013-11", 28525741.1, 4422), ("2013-12", 40212608.4, 5669),
        ("2014-01", 42592232.5, 9139), ("2014-02", 31281776.7, 5601), ("2014-03", 37383802.6, 6255), ("2014-04", 37491620.6, 6549),
        ("2014-05", 41734136.9, 7059), ("2014-06", 59676368.5, 7916), ("2014-07", 42474508.7, 7398), ("2014-08", 43566089.1, 7600),
        ("2014-09", 46479839.6, 7844), ("2014-10", 46615494, 8197), ("2014-11", 47591232.6, 8275), ("2014-12", 61903629, 9795),
        ("2015-01", 66245579.7, 15493), ("2015-02", 45126076.7, 8682), ("2015-03", 54113431.3, 9304), ("2015-04", 54844143.6, 9519),
        ("2015-05", 59914969.2, 9938), ("2015-06", 81612628.1, 10930), ("2015-07", 59959795.5, 10431), ("2015-08", 61914115.8, 10766),
        ("2015-09", 63051038.8, 11013), ("2015-10", 66593805.4, 11431), ("2015-11", 67447282.3, 11741), ("2015-12", 86907597.7, 13774),
        ("2016-01", 93622315.9, 21405), ("2016-02", 67669651, 12507), ("2016-03", 76962100.5, 13297), ("2016-04", 79176075.7, 13754),
        ("2016-05", 84998109.4, 14308), ("2016-06", 118709525, 15885), ("2016-07", 90753727.6, 15500), ("2016-08", 96292853.7, 16299),
        ("2016-09", 100840753.2, 16883), ("2016-10", 105841653.9, 17538), ("2016-11", 107962328.5, 17943), ("2016-12", 141022373.9, 21460),
        ("2017-01", 149308207.7, 33060), ("2017-02", 105167650, 19202), ("2017-03", 120829178.8, 20491), ("2017-04", 123419806, 20922),
        ("2017-05", 130633542.8, 21686), ("2017-06", 180533012.8, 23832), ("2017-07", 132462485.1, 22481), ("2017-08", 135565258, 22979),
        ("2017-09", 140446254.2, 23324), ("2017-10", 143934150.5, 23995), ("2017-11", 142695523.3, 24168), ("2017-12", 183333941.9, 28269),
        ("2018-01", 192082358.2, 42940), ("2018-02", 128749327, 23995), ("2018-03", 148188410.7, 25341), ("2018-04", 147273342.6, 25297),
        ("2018-05", 149884936.1, 25634), ("2018-06", 209902026.5, 27833), ("2018-07", 147337119.2, 25582), ("2018-08", 150639332.7, 25622),
        ("2018-09", 148297693.4, 25450), ("2018-10", 151889623.6, 25689), ("2018-11", 148842093.6, 25341), ("2018-12", 171697093.7, 23553),
    ]

    /// [PA] line "Giá trị giao dịch theo tháng" (72 tháng), tooltip Số GD.
    static let lineMonthlyAmount = DataView.categorical(CategoricalData(
        categoryLevels: [column("Dim_Date.year_month", "Tháng", role: "Category")],
        categories: monthly.map { CategoryKey(values: [.string($0.0)]) },
        seriesField: nil, series: [],
        measures: [measure("Dim_District.D4 Trans Amount", "Giá trị GD", role: "Y", format: "\\$#,0"),
                   measure("Dim_District.D4 Trans Count", "Số GD", role: "Tooltips", format: "#,0")],
        values: [[cells(monthly.map(\.1), format: "\\$#,0")], [ints(monthly.map(\.2), format: "#,0")]],
        highlights: nil, isReduced: false))

    // MARK: Combo cột chồng có Series (khuôn PA-D3-1)

    private static let channels = ["Email", "Fax", "Phone", "Postal mail", "Referral", "Web"]

    /// [GIẢ LẬP] combo D3 "Khiếu nại thay đổi theo thời gian và kênh nào?": cột chồng theo kênh (Y), đường TB 3 tháng (Y2).
    static let stackedComplaintsByChannel: DataView = {
        let months = (1...12).map { String(format: "2017-%02d", $0) }
        let base: [Double] = [5, 40, 150, 60, 180, 900]
        let y: [[DataCell]] = base.enumerated().map { s, b in
            months.indices.map { c in DataCell(.integer(Int64(b * (1 + 0.04 * Double(c)) + Double((s * 7 + c * 3) % 11))), formatString: "#,0") }
        }
        let totals = months.indices.map { c in y.reduce(0.0) { $0 + (NumberDisplay.numericValue($1[c].value) ?? 0) } }
        let ma3 = months.indices.map { c -> DataCell in
            let window = totals[max(0, c - 2)...c]
            return DataCell(.double(window.reduce(0, +) / Double(window.count)), formatString: "#,0")
        }
        return .categorical(CategoricalData(
            categoryLevels: [column("Dim_Date.year_month", "Tháng", role: "Category")],
            categories: months.map { CategoryKey(values: [.string($0)]) },
            seriesField: column("Dim_CRM_Channel_Response.submitted_via", "Kênh", role: "Series"),
            series: channels.map { .string($0) },
            measures: [measure("Fact_CRM_Complaint.Complaints", "Số khiếu nại", role: "Y", format: "#,0"),
                       measure("Fact_CRM_Complaint.Complaints MA3", "TB 3 tháng", role: "Y2", format: "#,0")],
            // Đường Y2 không theo series: chiều `s` có 1 phần tử ở measure thứ hai.
            values: [y, [ma3]],
            highlights: nil, isReduced: false))
    }()

    // MARK: Cột chồng 100%

    /// [GIẢ LẬP] D2 "Chất lượng nợ A/B/C/D thay đổi theo năm giải ngân?" (màu theo trạng thái lấy từ `dataPoint.fillByValue`).
    static let percentStackedStatus: DataView = {
        let statuses = ["Đã tất toán", "Đang chạy – tốt", "Đang chạy – nợ xấu", "Kết thúc – nợ xấu"]
        let counts: [[Int64]] = [[12, 60, 55, 70, 110, 40], [5, 30, 28, 36, 70, 104], [2, 6, 4, 6, 10, 9], [1, 5, 3, 5, 6, 5]]
        return .categorical(CategoricalData(
            categoryLevels: [column("Fact_Loan.loan_year", "Năm giải ngân", role: "Category")],
            categories: (2013...2018).map { CategoryKey(values: [.integer(Int64($0))]) },
            seriesField: column("Dim_Loan_Profile.status_vn", "Trạng thái", role: "Series"),
            series: statuses.map { .string($0) },
            measures: [measure("Fact_Loan.Loan Count", "Số khoản vay", role: "Y", format: "#,0")],
            values: [counts.map { ints($0, format: "#,0") }],
            highlights: nil, isReduced: false))
    }()

    // MARK: Donut

    /// [GIẢ LẬP] D2 "Danh mục cho vay phân bổ theo mục đích, kỳ hạn?" ở cấp mục đích.
    static let donutPurpose = DataView.categorical(CategoricalData(
        categoryLevels: [column("Dim_Loan_Profile.purpose", "purpose", role: "Category")],
        categories: ["Mua nhà", "Mua xe", "Tiêu dùng", "Kinh doanh", "Học tập"].map { CategoryKey(values: [.string($0)]) },
        seriesField: nil, series: [],
        measures: [measure("Fact_Loan.Loan Amount", "Giá trị", role: "Y", format: "\\$#,0"),
                   measure("Fact_Loan.Avg Duration", "Kỳ hạn BQ", role: "Tooltips", format: "0.0")],
        values: [[cells([41_000_000, 28_500_000, 17_200_000, 12_900_000, 3_700_000], format: "\\$#,0")],
                 [cells([36.2, 24.8, 18.1, 30.5, 12.0], format: "0.0")]],
        highlights: nil, isReduced: false))

    // MARK: Treemap (2 cấp)

    /// [GIẢ LẬP, 2 số đầu là PA-D3-2] D3 "Sản phẩm nào nhận nhiều khiếu nại nhất?": Group = Sản phẩm › Sản phẩm con.
    static let treemapProducts = DataView.categorical(CategoricalData(
        categoryLevels: [column("Dim_CRM_Issue.product", "Sản phẩm", role: "Group"),
                         column("Dim_CRM_Issue.sub_product", "Sản phẩm con", role: "Group")],
        categories: [
            ["Bank account or service", "Checking account"], ["Bank account or service", "Savings account"],
            ["Bank account or service", "Other bank product"], ["Credit card", "General-purpose card"],
            ["Credit card", "Store card"], ["Mortgage", "Conventional"], ["Mortgage", "FHA"], ["Student loan", "Private"],
        ].map { CategoryKey(values: $0.map { .string($0) }) },
        seriesField: nil, series: [],
        measures: [measure("Fact_CRM_Complaint.Complaints", "Số khiếu nại", role: "Values", format: "#,0"),
                   measure("Fact_CRM_Complaint.SLA_Timely_Rate", "% đúng hạn", role: "Tooltips", format: "0%")],
        values: [[ints([9_120, 3_480, 1_491, 7_400, 1_928, 6_300, 2_100, 1_250], format: "#,0")],
                 [cells([0.99, 0.985, 0.97, 0.977, 0.975, 0.96, 0.955, 0.93], format: "0%")]],
        highlights: nil, isReduced: false))

    // MARK: Shape map

    /// [GIẢ LẬP] D2 "Bang / chi nhánh nào cho vay nhiều, nợ xấu cao?": Category = mã bang, màu từ `Branch NPL Color`.
    static let shapeMapStates = DataView.categorical(CategoricalData(
        categoryLevels: [column("Dim_District.state", "Bang", role: "Category")],
        categories: ["CA", "TX", "NY", "FL", "IL", "WA"].map { CategoryKey(values: [.string($0)]) },
        seriesField: nil, series: [],
        measures: [measure("Fact_Loan.Loan Amount", "Giá trị cho vay", role: "Tooltips", format: "\\$#,0"),
                   measure("Fact_Loan.NPL Rate", "Tỷ lệ nợ xấu", role: "Tooltips", format: "0.0%")],
        values: [[zip([21e6, 15e6, 12e6, 9e6, 7e6, 4e6], ["#C0392B", "#E65100", "#81B29A", "#E65100", "#81B29A", "#81B29A"])
                    .map { DataCell(.double($0), formatString: "\\$#,0", fillColor: $1) }],
                 [cells([0.14, 0.11, 0.07, 0.12, 0.06, 0.05], format: "0.0%")]],
        highlights: nil, isReduced: false))

    // MARK: Matrix (khuôn PA-D1-2)

    /// [GIẢ LẬP trong khoảng min/max PA-D1-2: 190,67–253,64] D1 "Nhóm tuổi, địa bàn nào giao dịch nhiều nhất?":
    /// Rows = Nhóm tuổi, Columns = Vùng (chưa mở cấp Bang/Chi nhánh), có dòng/cột tổng, gradient theo `Trans per Client`.
    static let matrixAgeByRegion: DataView = {
        let ages = ["<25", "25-34", "35-49", "50-64", "65+"]
        let regions = ["Midwest", "Northeast", "South", "West"]
        let body: [[Double]] = [[201.3, 190.67, 212.9, 205.4], [233.1, 241.0, 226.5, 238.2], [248.7, 253.64, 239.9, 246.3],
                                [222.4, 230.8, 219.6, 227.1], [196.2, 199.8, 193.5, 201.0]]
        let rowTotal = body.map { $0.reduce(0, +) / Double($0.count) }
        let colTotal = regions.indices.map { c in body.reduce(0) { $0 + $1[c] } / Double(body.count) }
        let grand = rowTotal.reduce(0, +) / Double(rowTotal.count)
        let fmt = "#,0.00"
        var cells: [[[DataCell]]] = body.enumerated().map { r, row in
            (row + [rowTotal[r]]).map { [DataCell(.double($0), formatString: fmt)] }
        }
        cells.append((colTotal + [grand]).map { [DataCell(.double($0), formatString: fmt)] })
        return .matrix(MatrixData(
            rowLevels: [column("Dim_Client.age_group_current", "Nhóm tuổi", role: "Rows")],
            columnLevels: [column("Dim_Account.branch_region", "Vùng", role: "Columns"),
                           column("Dim_Account.branch_state", "Bang", role: "Columns"),
                           column("Dim_Account.branch_city", "Chi nhánh", role: "Columns")],
            measures: [measure("Fact_Transaction.Trans per Client", "GD / KH", role: "Values", format: fmt)],
            rows: ages.map { MatrixHeader(path: [.string($0)], level: 0) } + [MatrixHeader(path: [], level: -1, isGrandTotal: true)],
            columns: regions.map { MatrixHeader(path: [.string($0)], level: 0, hasChildren: true) }
                + [MatrixHeader(path: [], level: -1, isGrandTotal: true)],
            cells: cells, isReduced: false))
    }()

    /// Gradient của matrix trên (đúng như visual.json của Nhom6).
    static let matrixAgeByRegionGradient = GradientRule(
        property: "backColor", target: "Fact_Transaction.Trans per Client", inputTable: "Fact_Transaction",
        inputMeasure: "Trans per Client", minColor: .string("#F7FCF5"), midColor: .string("#A1D99B"),
        maxColor: .string("#31A354"), nullStrategy: "asZero")

    // MARK: Slicer (hierarchy Năm › Quý › Tháng)

    /// [PA về số năm, còn lại GIẢ LẬP] slicer D1 "Năm, Quý, Tháng".
    static let slicerYearQuarterMonth: DataView = {
        func quarter(_ q: Int) -> SlicerNode {
            let first = (q - 1) * 3 + 1
            let months: [SlicerNode] = (first...(first + 2)).map { (m: Int) -> SlicerNode in SlicerNode(.integer(Int64(m))) }
            return SlicerNode(.string("Q\(q)"), children: months)
        }
        let roots: [SlicerNode] = (2013...2018).map { (year: Int) -> SlicerNode in
            SlicerNode(.integer(Int64(year)), children: (1...4).map(quarter))
        }
        return .slicer(SlicerData(
            levels: [column("Dim_Date.Thời gian.Năm", "Năm", role: "Values"),
                     column("Dim_Date.Thời gian.Quý", "Quý", role: "Values"),
                     column("Dim_Date.Thời gian.Tháng", "Tháng", role: "Values")],
            roots: roots))
    }()

    /// Mọi mẫu, theo tên (để test/xuất ảnh hàng loạt).
    static let all: [(name: String, view: DataView)] = [
        ("cardCreditInflow", cardCreditInflow), ("cardDeltaLabel", cardDeltaLabel),
        ("comboLoansByYear", comboLoansByYear), ("barNPLByAge", barNPLByAge), ("lineMonthlyAmount", lineMonthlyAmount),
        ("stackedComplaintsByChannel", stackedComplaintsByChannel), ("percentStackedStatus", percentStackedStatus),
        ("donutPurpose", donutPurpose), ("treemapProducts", treemapProducts), ("shapeMapStates", shapeMapStates),
        ("matrixAgeByRegion", matrixAgeByRegion), ("slicerYearQuarterMonth", slicerYearQuarterMonth),
    ]
}
