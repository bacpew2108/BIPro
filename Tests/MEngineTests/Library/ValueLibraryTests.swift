// Tests for ValueLibrary (Text, Number, Date, List, Replacer, Splitter, Combiner).
import Testing
import ColumnStore
@testable import MEngine

@Suite struct ValueLibraryTests {
    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil)
    }

    // MARK: - Text Functions

    @Test func textUpper() async throws {
        #expect(try await eval("Text.Upper(\"áo thun\")") == .text("ÁO THUN"))
        #expect(try await eval("Text.Upper(\"hello\")") == .text("HELLO"))
        #expect(try await eval("Text.Upper(null)") == .null)
    }

    @Test func textLower() async throws {
        #expect(try await eval("Text.Lower(\"ÁO THUN\")") == .text("áo thun"))
        #expect(try await eval("Text.Lower(\"HELLO\")") == .text("hello"))
        #expect(try await eval("Text.Lower(null)") == .null)
    }

    @Test func textProper() async throws {
        #expect(try await eval("Text.Proper(\"áo thun việt nam\")") == .text("Áo Thun Việt Nam"))
        #expect(try await eval("Text.Proper(\"hello world\")") == .text("Hello World"))
        #expect(try await eval("Text.Proper(null)") == .null)
    }

    @Test func textTrim() async throws {
        #expect(try await eval("Text.Trim(\"  abc  \")") == .text("abc"))
        #expect(try await eval("Text.Trim(null)") == .null)
        #expect(try await eval("Text.Trim(\"__abc__\", \"_\")") == .text("abc"))
    }

    @Test func textClean() async throws {
        #expect(try await eval("Text.Clean(\"a\u{0000}b\u{001F}c\")") == .text("abc"))
        #expect(try await eval("Text.Clean(null)") == .null)
    }

    @Test func textLength() async throws {
        #expect(try await eval("Text.Length(\"abc\")") == .number(3))
        #expect(try await eval("Text.Length(\"\")") == .number(0))
        #expect(try await eval("Text.Length(null)") == .null)
    }

    @Test func textContains() async throws {
        #expect(try await eval("Text.Contains(\"Hello World\", \"World\")") == .logical(true))
        #expect(try await eval("Text.Contains(\"Hello World\", \"world\")") == .logical(false))
        #expect(try await eval("Text.Contains(null, \"test\")") == .null)
    }

    @Test func textStartsWith() async throws {
        #expect(try await eval("Text.StartsWith(\"Hello World\", \"Hello\")") == .logical(true))
        #expect(try await eval("Text.StartsWith(\"Hello World\", \"world\")") == .logical(false))
        #expect(try await eval("Text.StartsWith(null, \"test\")") == .null)
    }

    @Test func textEndsWith() async throws {
        #expect(try await eval("Text.EndsWith(\"Hello World\", \"World\")") == .logical(true))
        #expect(try await eval("Text.EndsWith(\"Hello World\", \"Hello\")") == .logical(false))
        #expect(try await eval("Text.EndsWith(null, \"test\")") == .null)
    }

    @Test func textReplace() async throws {
        #expect(try await eval("Text.Replace(\"Hello World\", \"World\", \"Swift\")") == .text("Hello Swift"))
        #expect(try await eval("Text.Replace(null, \"a\", \"b\")") == .null)
    }

    @Test func textCombine() async throws {
        #expect(try await eval("Text.Combine({\"a\", \"b\", \"c\"}, \", \")") == .text("a, b, c"))
        #expect(try await eval("Text.Combine({\"a\", \"b\"})") == .text("ab"))
        #expect(try await eval("Text.Combine({\"a\", null, \"b\"}, \"-\")") == .text("a-b"))
        #expect(try await eval("Text.Combine({})") == .text(""))
    }

    @Test func textFrom() async throws {
        #expect(try await eval("Text.From(123)") == .text("123"))
        #expect(try await eval("Text.From(9.99)") == .text("9.99"))
        #expect(try await eval("Text.From(true)") == .text("true"))
        #expect(try await eval("Text.From(false)") == .text("false"))
        #expect(try await eval("Text.From(\"abc\")") == .text("abc"))
        #expect(try await eval("Text.From(null)") == .null)
    }

    @Test func textStart() async throws {
        #expect(try await eval("Text.Start(\"abcdef\", 3)") == .text("abc"))
        #expect(try await eval("Text.Start(\"abc\", 5)") == .text("abc"))
        #expect(try await eval("Text.Start(null, 3)") == .null)
    }

    @Test func textEnd() async throws {
        #expect(try await eval("Text.End(\"abcdef\", 3)") == .text("def"))
        #expect(try await eval("Text.End(\"abc\", 5)") == .text("abc"))
        #expect(try await eval("Text.End(null, 3)") == .null)
    }

    @Test func textPadStart() async throws {
        #expect(try await eval("Text.PadStart(\"123\", 5, \"0\")") == .text("00123"))
        #expect(try await eval("Text.PadStart(\"123\", 5)") == .text("  123"))
        #expect(try await eval("Text.PadStart(null, 5)") == .null)
    }

    // MARK: - Number Functions

    @Test func numberFrom() async throws {
        #expect(try await eval("Number.From(\"1,5\")") == .number(15))
        #expect(try await eval("Number.From(\"123.45\")") == .number(123.45))
        #expect(try await eval("Number.From(42)") == .number(42))
        #expect(try await eval("Number.From(true)") == .number(1))
        #expect(try await eval("Number.From(false)") == .number(0))
        #expect(try await eval("Number.From(null)") == .null)
    }

    @Test func numberRound() async throws {
        #expect(try await eval("Number.Round(1.2345, 2)") == .number(1.23))
        #expect(try await eval("Number.Round(1.5)") == .number(2))
        #expect(try await eval("Number.Round(null)") == .null)
    }

    @Test func numberAbs() async throws {
        #expect(try await eval("Number.Abs(-42.5)") == .number(42.5))
        #expect(try await eval("Number.Abs(42.5)") == .number(42.5))
        #expect(try await eval("Number.Abs(null)") == .null)
    }

    @Test func numberRoundDown() async throws {
        #expect(try await eval("Number.RoundDown(1.99)") == .number(1))
        #expect(try await eval("Number.RoundDown(1.2345, 2)") == .number(1.23))
        #expect(try await eval("Number.RoundDown(null)") == .null)
    }

    @Test func numberRoundUp() async throws {
        #expect(try await eval("Number.RoundUp(1.01)") == .number(2))
        #expect(try await eval("Number.RoundUp(1.2345, 2)") == .number(1.24))
        #expect(try await eval("Number.RoundUp(null)") == .null)
    }

    @Test func numberMod() async throws {
        #expect(try await eval("Number.Mod(10, 3)") == .number(1))
        #expect(try await eval("Number.Mod(null, 3)") == .null)
        #expect(try await eval("Number.Mod(10, null)") == .null)
    }

    @Test func numberIntegerDivide() async throws {
        #expect(try await eval("Number.IntegerDivide(10, 3)") == .number(3))
        #expect(try await eval("Number.IntegerDivide(-10, 3)") == .number(-3))
        #expect(try await eval("Number.IntegerDivide(null, 3)") == .null)
    }

    // MARK: - Date Functions

    @Test func dateParts() async throws {
        #expect(try await eval("Date.Year(#date(2026, 9, 9))") == .number(2026))
        #expect(try await eval("Date.Month(#date(2026, 9, 9))") == .number(9))
        #expect(try await eval("Date.Day(#date(2026, 9, 9))") == .number(9))
        #expect(try await eval("Date.Year(null)") == .null)
        #expect(try await eval("Date.Month(null)") == .null)
        #expect(try await eval("Date.Day(null)") == .null)
    }

    @Test func dateFrom() async throws {
        #expect(try await eval("Date.From(#date(2026, 9, 9))") == .date(46274))
        #expect(try await eval("Date.From(\"2026-09-09\")") == .date(46274))
        #expect(try await eval("Date.From(null)") == .null)
    }

    @Test func dateAddDays() async throws {
        #expect(try await eval("Date.AddDays(#date(2026, 9, 9), 5)") == .date(46279))
        #expect(try await eval("Date.AddDays(#date(2026, 9, 9), -5)") == .date(46269))
        #expect(try await eval("Date.AddDays(null, 5)") == .null)
    }

    @Test func dateAddMonths() async throws {
        #expect(try await eval("Date.AddMonths(#date(2026, 1, 31), 1)") == .date(46081)) // 2026-02-28
        #expect(try await eval("Date.AddMonths(#date(2026, 9, 9), 3)") == .date(46365)) // 2026-12-09
        #expect(try await eval("Date.AddMonths(null, 1)") == .null)
    }

    @Test func dateDayOfWeek() async throws {
        // 2026-09-09 is Wednesday (Sunday=0, Monday=1, Tuesday=2, Wednesday=3)
        #expect(try await eval("Date.DayOfWeek(#date(2026, 9, 9))") == .number(3))
        #expect(try await eval("Date.DayOfWeek(null)") == .null)
    }

    // MARK: - List Functions

    @Test func listSum() async throws {
        #expect(try await eval("List.Sum({1, 2, 3, 4})") == .number(10))
        #expect(try await eval("List.Sum({1, null, 3})") == .number(4))
        #expect(try await eval("List.Sum({})") == .null)
        #expect(try await eval("List.Sum({null, null})") == .null)
    }

    @Test func listCount() async throws {
        #expect(try await eval("List.Count({1, 2, 3})") == .number(3))
        #expect(try await eval("List.Count({})") == .number(0))
    }

    @Test func listDistinct() async throws {
        #expect(try await eval("List.Distinct({1, 2, 2, 3, 1})") == .list([.number(1), .number(2), .number(3)]))
        #expect(try await eval("List.Distinct({})") == .list([]))
    }

    @Test func listMinMaxAverage() async throws {
        #expect(try await eval("List.Max({10, 5, 20, 15})") == .number(20))
        #expect(try await eval("List.Min({10, 5, 20, 15})") == .number(5))
        #expect(try await eval("List.Average({10, 20, 30})") == .number(20))
        #expect(try await eval("List.Max({})") == .null)
        #expect(try await eval("List.Min({})") == .null)
        #expect(try await eval("List.Average({})") == .null)
    }

    @Test func listSort() async throws {
        #expect(try await eval("List.Sort({3, 1, 2})") == .list([.number(1), .number(2), .number(3)]))
        #expect(try await eval("List.Sort({3, 1, 2}, Order.Descending)") == .list([.number(3), .number(2), .number(1)]))
        #expect(try await eval("List.Sort({})") == .list([]))
    }

    @Test func listTransformAndSelect() async throws {
        #expect(try await eval("List.Transform({1, 2, 3}, each _ * 2)") == .list([.number(2), .number(4), .number(6)]))
        #expect(try await eval("List.Select({1, 2, 3, 4}, each _ > 2)") == .list([.number(3), .number(4)]))
    }

    @Test func listContains() async throws {
        #expect(try await eval("List.Contains({1, 2, 3}, 2)") == .logical(true))
        #expect(try await eval("List.Contains({1, 2, 3}, 5)") == .logical(false))
    }

    @Test func listFirstLast() async throws {
        #expect(try await eval("List.First({10, 20, 30})") == .number(10))
        #expect(try await eval("List.First({}, 99)") == .number(99))
        #expect(try await eval("List.First({})") == .null)
        #expect(try await eval("List.Last({10, 20, 30})") == .number(30))
        #expect(try await eval("List.Last({}, 99)") == .number(99))
        #expect(try await eval("List.Last({})") == .null)
    }

    @Test func listNumbersAndReverse() async throws {
        #expect(try await eval("List.Numbers(1, 4)") == .list([.number(1), .number(2), .number(3), .number(4)]))
        #expect(try await eval("List.Numbers(0, 3, 2)") == .list([.number(0), .number(2), .number(4)]))
        #expect(try await eval("List.Reverse({1, 2, 3})") == .list([.number(3), .number(2), .number(1)]))
    }

    // MARK: - Replacer, Splitter, Combiner

    @Test func replacerFunctions() async throws {
        #expect(try await eval("Replacer.ReplaceText(\"Hello North\", \"North\", \"Bac\")") == .text("Hello Bac"))
        #expect(try await eval("Replacer.ReplaceText(null, \"North\", \"Bac\")") == .null)
        #expect(try await eval("Replacer.ReplaceValue(10, 10, 20)") == .number(20))
        #expect(try await eval("Replacer.ReplaceValue(10, 5, 20)") == .number(10))
    }

    @Test func splitterFunction() async throws {
        #expect(try await eval(#"Splitter.SplitTextByDelimiter(" ")("Bac Trung Nam")"#) == .list([.text("Bac"), .text("Trung"), .text("Nam")]))
        #expect(try await eval(#"Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv)("""Bac Trung"" Nam")"#) == .list([.text("Bac Trung"), .text("Nam")]))
        #expect(try await eval(#"Splitter.SplitTextByDelimiter(" ")(null)"#) == .null)
    }

    @Test func combinerFunction() async throws {
        #expect(try await eval("Combiner.CombineTextByDelimiter(\", \")({\"a\", \"b\", \"c\"})") == .text("a, b, c"))
    }
}
