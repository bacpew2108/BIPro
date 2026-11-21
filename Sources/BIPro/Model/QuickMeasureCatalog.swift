// Wave 4B (T007): Thư viện 8 mẫu Quick Measures chuẩn Power BI sinh công thức DAX hợp lệ.
import DAXEngine
import Foundation

enum QuickMeasureTemplate: String, CaseIterable, Identifiable, Sendable {
    case ytdTotal
    case runningTotal
    case rollingAverage
    case percentOfGrandTotal
    case filteredValue
    case weightedAverage
    case yoyPercentChange
    case safeDivision

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .ytdTotal: bi("Tổng luỹ kế năm (YTD)", "Year-to-date total")
        case .runningTotal: bi("Tổng luỹ kế (Running total)", "Running total")
        case .rollingAverage: bi("Trung bình trượt (Rolling average)", "Rolling average")
        case .percentOfGrandTotal: bi("Tỷ trọng % tổng (% of grand total)", "% of grand total")
        case .filteredValue: bi("Giá trị có bộ lọc (Filtered value)", "Filtered value")
        case .weightedAverage: bi("Trung bình có trọng số (Weighted average)", "Weighted average")
        case .yoyPercentChange: bi("Tăng trưởng YoY % (Year-over-year %)", "Year-over-year % change")
        case .safeDivision: bi("Phép chia an toàn (Division)", "Division")
        }
    }

    var needsDateColumn: Bool {
        switch self {
        case .ytdTotal, .rollingAverage, .yoyPercentChange: true
        default: false
        }
    }

    var needsCategoryColumn: Bool {
        switch self {
        case .runningTotal, .percentOfGrandTotal, .filteredValue: true
        default: false
        }
    }

    var needsSecondMeasureOrColumn: Bool {
        switch self {
        case .weightedAverage, .safeDivision: true
        default: false
        }
    }

    var needsFilterLiteral: Bool { self == .filteredValue }
    var needsWindowLength: Bool { self == .rollingAverage }

    /// Sinh tên gợi ý và biểu thức DAX chuẩn cho mẫu hiện tại.
    func generate(
        baseMeasure: String,
        secondaryRef: String = "",
        dateTable: String = "",
        dateColumn: String = "",
        categoryTable: String = "",
        categoryColumn: String = "",
        filterValue: String = "",
        rollingDays: Int = 30
    ) -> (suggestedName: String, expression: String) {
        let baseRef = DAXEngine.formatBracketIdentifier(baseMeasure)
        let dateRef = "\(DAXEngine.formatTableIdentifier(dateTable))\(DAXEngine.formatBracketIdentifier(dateColumn))"
        let catRef = "\(DAXEngine.formatTableIdentifier(categoryTable))\(DAXEngine.formatBracketIdentifier(categoryColumn))"
        let secRef = secondaryRef.contains("[") ? secondaryRef : DAXEngine.formatBracketIdentifier(secondaryRef)

        switch self {
        case .ytdTotal:
            return (
                "\(baseMeasure) YTD",
                "TOTALYTD(\(baseRef), \(dateRef))"
            )
        case .runningTotal:
            return (
                "\(baseMeasure) Running Total",
                """
                CALCULATE(
                    \(baseRef),
                    FILTER(
                        ALLSELECTED(\(catRef)),
                        ISONORAFTER(\(catRef), MAX(\(catRef)), DESC)
                    )
                )
                """
            )
        case .rollingAverage:
            let n = max(1, rollingDays)
            return (
                "\(baseMeasure) Rolling Avg \(n)D",
                """
                AVERAGEX(
                    DATESINPERIOD(\(dateRef), MAX(\(dateRef)), -\(n), DAY),
                    \(baseRef)
                )
                """
            )
        case .percentOfGrandTotal:
            return (
                "\(baseMeasure) % of Total",
                "DIVIDE(\(baseRef), CALCULATE(\(baseRef), ALLSELECTED(\(catRef))))"
            )
        case .filteredValue:
            let escaped = filterValue.replacingOccurrences(of: "\"", with: "\"\"")
            return (
                "\(baseMeasure) for \(filterValue.isEmpty ? "Filter" : filterValue)",
                "CALCULATE(\(baseRef), \(catRef) = \"\(escaped)\")"
            )
        case .weightedAverage:
            let tblRef = DAXEngine.formatTableIdentifier(categoryTable.isEmpty ? dateTable : categoryTable)
            return (
                "\(baseMeasure) Weighted Avg",
                "DIVIDE(SUMX(\(tblRef), \(baseRef) * \(secRef)), SUMX(\(tblRef), \(secRef)))"
            )
        case .yoyPercentChange:
            return (
                "\(baseMeasure) YoY %",
                """
                VAR __curr = \(baseRef)
                VAR __prev = CALCULATE(\(baseRef), SAMEPERIODLASTYEAR(\(dateRef)))
                RETURN
                    DIVIDE(__curr - __prev, __prev)
                """
            )
        case .safeDivision:
            return (
                "\(baseMeasure) Ratio",
                "DIVIDE(\(baseRef), \(secRef), 0)"
            )
        }
    }
}
