// Measure của MiniBank dưới dạng chuỗi DAX, để binder và test dùng sau (PHASE_B_PLAN §3.5).
// Khuôn Δ theo docs/measures.nhom6.dax (Trans Amount Δ, quanh dòng 840): SAMEPERIODLASTYEAR và
// REMOVEFILTERS(Dim_Date), rút gọn cho hai năm. Avg Balance lặp theo tài khoản bằng hai CALCULATE.

public struct MiniBankMeasure: Sendable, Hashable {
    /// Bảng chủ của measure.
    public let table: String
    /// Tên measure, đúng như trong DAX.
    public let name: String
    /// Biểu thức DAX, không kèm dấu bằng đầu measure.
    public let expression: String

    public init(table: String, name: String, expression: String) {
        self.table = table
        self.name = name
        self.expression = expression
    }
}

extension MiniBank {
    public static let measures: [MiniBankMeasure] = [
        MiniBankMeasure(
            table: "Fact_Trans",
            name: "Trans Amount",
            expression: "SUM ( Fact_Trans[amount] )"),

        MiniBankMeasure(
            table: "Fact_Trans",
            name: "Trans Count",
            expression: "COUNTROWS ( Fact_Trans )"),

        // Lặp theo tài khoản: với mỗi account_key, lấy số dư tại giao dịch muộn nhất (hai CALCULATE).
        MiniBankMeasure(
            table: "Fact_Trans",
            name: "Avg Balance",
            expression: """
            AVERAGEX (
                CALCULATETABLE ( VALUES ( Fact_Trans[account_key] ), REMOVEFILTERS ( Dim_Date ) ),
                VAR t = CALCULATE ( MAX ( Fact_Trans[date_key] ), REMOVEFILTERS ( Dim_Date ) )
                RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), REMOVEFILTERS ( Dim_Date ), Fact_Trans[date_key] = t )
            )
            """),

        // Δ theo khuôn Nhom6: so lũy kế từ 01/01 đến ngày muộn nhất với cùng kỳ năm trước.
        MiniBankMeasure(
            table: "Fact_Trans",
            name: "Trans Amount Δ",
            expression: """
            VAR endKey = MAX ( Fact_Trans[date_key] )
            VAR endDt = DATE ( INT ( endKey / 10000 ), MOD ( INT ( endKey / 100 ), 100 ), MOD ( endKey, 100 ) )
            VAR curDates = FILTER ( VALUES ( Dim_Date[full_date] ), Dim_Date[full_date] >= DATE ( YEAR ( endDt ), 1, 1 ) && Dim_Date[full_date] <= endDt )
            VAR cur = CALCULATE ( [Trans Amount], curDates, REMOVEFILTERS ( Dim_Date ) )
            VAR prev = CALCULATE ( [Trans Amount], SAMEPERIODLASTYEAR ( curDates ), REMOVEFILTERS ( Dim_Date ) )
            RETURN IF ( NOT ISBLANK ( endKey ), DIVIDE ( cur - prev, prev ) )
            """),
    ]
}
