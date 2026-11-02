// Kiểm tra cách PBIXColumnSource đổi kết quả VertiPaq sang ColumnData (CS, đợt 1a),
// trên dữ liệu dựng tay để không cần file .pbix.
import Testing
@testable import ColumnStore
import PBIXKit

@Suite struct CSPBIXConvertTests {

    @Test func dictionaryCodesShiftByOneAndMinusOneIsBlank() throws {
        // -1 là null; k là mục k-1, nên mã lưu là k+1.
        let column = try PBIXColumnSource.convertDictionary(
            codes: [-1, 0, 1, 0], dictionary: [.int(5), .int(7)], type: .integer)
        #expect(column.isEncoded)
        #expect(column.value(at: 0) == .blank)
        #expect(column.value(at: 1) == .integer(5))
        #expect(column.value(at: 2) == .integer(7))
        #expect(column.value(at: 3) == .integer(5))
        #expect(column.code(atRow: 0) == 0)
        #expect(column.code(atRow: 2) == 2)
        guard case .encoded(let codes, _) = column.payload else {
            Issue.record("phải mã hoá khi ít giá trị")
            return
        }
        if case .u8 = codes {} else { Issue.record("distinct 2 phải dùng mã u8") }
    }

    @Test func codeWidthFollowsDictionarySize() {
        // Mã cao nhất là distinct, nên 255 mục vẫn đủ u8, 256 mục cần u16.
        if case .u8 = PBIXColumnSource.encodeCodes([0], distinct: 255) {} else { Issue.record("255 → u8") }
        if case .u16 = PBIXColumnSource.encodeCodes([0], distinct: 256) {} else { Issue.record("256 → u16") }
        if case .u16 = PBIXColumnSource.encodeCodes([0], distinct: 65_535) {} else { Issue.record("65535 → u16") }
        if case .u32 = PBIXColumnSource.encodeCodes([0], distinct: 65_536) {} else { Issue.record("65536 → u32") }
    }

    @Test func largeNumericDictionaryBecomesDense() throws {
        let dictionary = (0..<70_000).map { CellValue.int(Int64($0) * 3) }
        let column = try PBIXColumnSource.convertDictionary(
            codes: [-1, 0, 69_999, 12_345], dictionary: dictionary, type: .integer)
        #expect(!column.isEncoded, "hơn 65535 giá trị khác nhau phải dense")
        #expect(column.value(at: 0) == .blank)
        #expect(column.value(at: 1) == .integer(0))
        #expect(column.value(at: 2) == .integer(69_999 * 3))
        #expect(column.value(at: 3) == .integer(12_345 * 3))
    }

    @Test func currencyDecimalsRoundToTenThousandths() throws {
        // CellValue.decimal lưu v/10⁴; nhân lại và làm tròn để có số nguyên chính xác.
        let column = try PBIXColumnSource.convertDictionary(
            codes: [0, 1, -1], dictionary: [.decimal(12.3456), .decimal(-0.0001)], type: .currency)
        #expect(column.value(at: 0) == .currency(123_456))
        #expect(column.value(at: 1) == .currency(-1))
        #expect(column.value(at: 2) == .blank)
    }

    @Test func emptyStringIsValueAndNullIsBlank() throws {
        let column = try PBIXColumnSource.convertDictionary(
            codes: [0, -1, 1], dictionary: [.string(""), .string("Hà Nội")], type: .string)
        #expect(column.value(at: 0) == .string(""))
        #expect(column.value(at: 1) == .blank)
        #expect(column.value(at: 2) == .string("Hà Nội"))
        #expect(column.dictionaryCount == 2)
    }

    @Test func booleanAndDateTimeAndDoubleDictionaries() throws {
        let flags = try PBIXColumnSource.convertDictionary(
            codes: [0, 1, -1], dictionary: [.bool(false), .bool(true)], type: .boolean)
        #expect(flags.value(at: 0) == .boolean(false))
        #expect(flags.value(at: 1) == .boolean(true))
        #expect(flags.value(at: 2) == .blank)

        let dates = try PBIXColumnSource.convertDictionary(
            codes: [0, -1], dictionary: [.dateTime(45_000.5)], type: .dateTime)
        #expect(dates.value(at: 0) == .dateTime(45_000.5))
        #expect(dates.value(at: 1) == .blank)

        let doubles = try PBIXColumnSource.convertDictionary(
            codes: [1, 0], dictionary: [.double(0.25), .double(-3.5)], type: .double)
        #expect(doubles.value(at: 0) == .double(-3.5))
        #expect(doubles.value(at: 1) == .double(0.25))
    }

    @Test func emptyDictionaryIsAllBlank() throws {
        let column = try PBIXColumnSource.convertDictionary(codes: [-1, -1], dictionary: [], type: .string)
        #expect(column.value(at: 0) == .blank)
        #expect(column.dictionaryCount == 0)
        #expect(column.code(atRow: 1) == 0)
    }

    @Test func invalidCodesAndMismatchedValuesThrow() {
        #expect(throws: PBIXColumnSourceError.self) {
            _ = try PBIXColumnSource.convertDictionary(codes: [2], dictionary: [.int(1), .int(2)], type: .integer)
        }
        #expect(throws: PBIXColumnSourceError.self) {
            _ = try PBIXColumnSource.convertDictionary(codes: [-2], dictionary: [.int(1)], type: .integer)
        }
        #expect(throws: PBIXColumnSourceError.self) {
            _ = try PBIXColumnSource.convertDictionary(codes: [0], dictionary: [.string("x")], type: .integer)
        }
    }

    @Test func valueEncodedColumnsUseDenseLayout() throws {
        // Cột giá trị trực tiếp: NaN là BLANK, decimal giữ nguyên số đã nhân 10⁴ (round).
        let currency = try PBIXColumnSource.convertValues([1_234.0, .nan, -5.0], type: .currency)
        #expect(!currency.isEncoded)
        #expect(currency.value(at: 0) == .currency(1_234))
        #expect(currency.value(at: 1) == .blank)
        #expect(currency.value(at: 2) == .currency(-5))

        let integers = try PBIXColumnSource.convertValues([7, .nan], type: .integer)
        #expect(integers.value(at: 0) == .integer(7))
        #expect(integers.value(at: 1) == .blank)

        let doubles = try PBIXColumnSource.convertValues([1.5, .nan], type: .double)
        #expect(doubles.value(at: 0) == .double(1.5))
        #expect(doubles.value(at: 1) == .blank)

        let flags = try PBIXColumnSource.convertValues([1, 0, .nan], type: .boolean)
        #expect(flags.value(at: 0) == .boolean(true))
        #expect(flags.value(at: 1) == .boolean(false))
        #expect(flags.value(at: 2) == .blank)
    }

    @Test func denseFromDictionaryKeepsBlanksAndValues() throws {
        let dictionary = (0..<70_000).map { CellValue.decimal(Double($0) / 10_000) }
        let column = try PBIXColumnSource.convertDictionary(
            codes: [-1, 1, -1, 500], dictionary: dictionary, type: .currency)
        #expect(!column.isEncoded)
        #expect(column.value(at: 0) == .blank)
        #expect(column.value(at: 1) == .currency(1))
        #expect(column.value(at: 2) == .blank)
        #expect(column.value(at: 3) == .currency(500))
    }

    @Test func prefersDenseRule() {
        #expect(PBIXColumnSource.prefersDense(type: .integer, distinct: 70_000, rows: 10))
        #expect(!PBIXColumnSource.prefersDense(type: .currency, distinct: 100, rows: 200))
        #expect(PBIXColumnSource.prefersDense(type: .string, distinct: 70_000, rows: 100_000) == false,
                "chuỗi không bao giờ dense")
        #expect(!PBIXColumnSource.prefersDense(type: .boolean, distinct: 70_000, rows: 100_000))
    }
}
