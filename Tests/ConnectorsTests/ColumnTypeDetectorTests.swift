import Testing
import ColumnStore
@testable import Connectors

@Suite struct ColumnTypeDetectorTests {
    // MARK: - ColumnNaming

    @Test func uniqueNamingReplacesEmptyWithColumnIndex() {
        let headers: [String?] = [nil, "", "Name", nil]
        let result = ColumnNaming.unique(headers)
        #expect(result == ["Column1", "Column2", "Name", "Column4"])
    }

    @Test func uniqueNamingHandlesDuplicatesWithDotSuffix() {
        let headers: [String?] = ["Qty", "Qty", "Qty"]
        let result = ColumnNaming.unique(headers)
        #expect(result == ["Qty", "Qty.1", "Qty.2"])
    }

    @Test func uniqueNamingHandlesCollisionsWithGeneratedNames() {
        let headers: [String?] = ["Column1", nil, "Column1"]
        let result = ColumnNaming.unique(headers)
        #expect(result == ["Column1", "Column2", "Column1.1"])
    }

    // MARK: - ColumnTypeDetector

    @Test func detectsIntegerColumn() {
        let values: [String?] = ["1", "-20", "300", nil, "0"]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "IntCol")
        #expect(col.type == .integer)
        #expect(errors.isEmpty)
        #expect(col.value(at: 0) == .integer(1))
        #expect(col.value(at: 1) == .integer(-20))
        #expect(col.value(at: 2) == .integer(300))
        #expect(col.value(at: 3) == .blank)
        #expect(col.value(at: 4) == .integer(0))
    }

    @Test func detectsDoubleColumnWithDecimalsOrExponents() {
        let values: [String?] = ["1.5", "-2.25", "3e2", "100.0"]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "DoubleCol")
        #expect(col.type == .double)
        #expect(errors.isEmpty)
        #expect(col.value(at: 0) == .double(1.5))
        #expect(col.value(at: 1) == .double(-2.25))
        #expect(col.value(at: 2) == .double(300.0))
        #expect(col.value(at: 3) == .double(100.0))
    }

    @Test func detectsDoubleWhenIntegersMixedWithDoubles() {
        let values: [String?] = ["1", "2.5", "3"]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "MixedNum")
        #expect(col.type == .double)
        #expect(errors.isEmpty)
        #expect(col.value(at: 0) == .double(1.0))
        #expect(col.value(at: 1) == .double(2.5))
        #expect(col.value(at: 2) == .double(3.0))
    }

    @Test func detectsDoubleWhenNumberExceedsInt64() {
        // 99999999999999999999 exceeds Int64.max (9223372036854775807)
        let values: [String?] = ["99999999999999999999", "12345"]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "HugeNum")
        #expect(col.type == .double)
        #expect(errors.isEmpty)
    }

    @Test func detectsBooleanColumnCaseInsensitive() {
        let values: [String?] = ["true", "False", "TRUE", "false", nil]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "BoolCol")
        #expect(col.type == .boolean)
        #expect(errors.isEmpty)
        #expect(col.value(at: 0) == .boolean(true))
        #expect(col.value(at: 1) == .boolean(false))
        #expect(col.value(at: 2) == .boolean(true))
        #expect(col.value(at: 3) == .boolean(false))
        #expect(col.value(at: 4) == .blank)
    }

    @Test func detectsDateTimeColumn() {
        let values: [String?] = ["2026-03-02", "2026-04-25 12:30:00", "2026-09-09T08:15:30"]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "DateCol")
        #expect(col.type == .dateTime)
        #expect(errors.isEmpty)
        #expect(col.value(at: 0) == .dateTime(46083.0))
    }

    @Test func detectsStringColumnWhenAnyValueIsText() {
        let values: [String?] = ["1", "abc", "3"]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "StrCol")
        #expect(col.type == .string)
        #expect(errors.isEmpty)
        #expect(col.value(at: 0) == .string("1"))
        #expect(col.value(at: 1) == .string("abc"))
        #expect(col.value(at: 2) == .string("3"))
    }

    @Test func allEmptyColumnBecomesStringWithAllNil() {
        let values: [String?] = [nil, "", nil]
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "EmptyCol")
        #expect(col.type == .string)
        #expect(errors.isEmpty)
        #expect(col.value(at: 0) == .blank)
        #expect(col.value(at: 1) == .blank)
        #expect(col.value(at: 2) == .blank)
    }

    @Test func valueOutsideSampleProducesBlankAndError() {
        // 250 rows: 0..249. Row 230 has "abc", others are integers
        var values = (0..<250).map { String($0) }
        values[230] = "abc"
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "IntWithBadTail")
        #expect(col.type == .integer)
        #expect(errors.count == 1)
        #expect(errors[230]?.contains("Không thể chuyển 'abc' sang số nguyên") == true)
        #expect(col.value(at: 230) == .blank)
        #expect(col.value(at: 229) == .integer(229))
        #expect(col.value(at: 231) == .integer(231))
    }

    @Test func invalidValueWithinSampleMakesWholeColumnString() {
        // Row 4 has "n/a", within first 200 rows
        var values = (0..<30).map { String($0) }
        values[4] = "n/a"
        let (col, errors) = ColumnTypeDetector.column(from: values, name: "StringBecauseSampleHasNA")
        #expect(col.type == .string)
        #expect(errors.isEmpty)
        #expect(col.value(at: 4) == .string("n/a"))
    }
}
