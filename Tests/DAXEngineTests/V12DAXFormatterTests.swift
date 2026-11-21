import DAXEngine
import Testing

@Suite("Wave 4 (v1.2) — DAX Formatter")
struct V12DAXFormatterTests {
    @Test("Định dạng DEFINE / MEASURE / VAR / RETURN / EVALUATE / ORDER BY và bảo toàn chuỗi/chú thích")
    func formatsComplexDAXPreservingStringsAndComments() {
        let ugly = """
        // Comment header
        DEFINE MEASURE 'Fact Sales'[YTD Total] = VAR cur = CALCULATE(SUM('Fact Sales'[Amount]), FILTER('Dim Date', 'Dim Date'[Year] = 2024 && 'Dim Date'[Note] = "DEFINE VAR (a,b)")) RETURN IF(cur > 0, cur, -1) EVALUATE SUMMARIZECOLUMNS('Dim Date'[Year], "V", [YTD Total]) ORDER BY 'Dim Date'[Year] DESC
        """
        let formatted = DAXEngine.format(ugly)
        #expect(formatted.contains("// Comment header"))
        #expect(formatted.contains("DEFINE\n"))
        #expect(formatted.contains("    MEASURE 'Fact Sales'[YTD Total] =\n"))
        #expect(formatted.contains("        VAR cur = CALCULATE(\n"))
        #expect(formatted.contains("        RETURN IF(\n"))
        #expect(formatted.contains(#""DEFINE VAR (a,b)""#))
        #expect(formatted.contains("\nEVALUATE\n"))
        #expect(formatted.contains("\nORDER BY\n"))
        #expect(formatted.contains("-1"))
    }
}
