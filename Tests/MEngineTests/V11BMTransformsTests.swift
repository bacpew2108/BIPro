import ColumnStore
import Foundation
import MEngine
import Testing

@Suite("Wave 3C (v1.1b) — Power Query Extra Transforms (MEngine & StepFactory)")
struct V11BMTransformsTests {
    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source)
    }

    @Test("Text.BeforeDelimiter, Text.AfterDelimiter, Text.BetweenDelimiters, Text.Range")
    func textExtractFunctions() async throws {
        #expect(try await eval(#"Text.BeforeDelimiter("ABC-123-XYZ", "-")"#) == .text("ABC"))
        #expect(try await eval(#"Text.BeforeDelimiter("ABC-123-XYZ", "-", 1)"#) == .text("ABC-123"))
        #expect(try await eval(#"Text.AfterDelimiter("ABC-123-XYZ", "-")"#) == .text("123-XYZ"))
        #expect(try await eval(#"Text.AfterDelimiter("ABC-123-XYZ", "-", 1)"#) == .text("XYZ"))
        #expect(try await eval(#"Text.BetweenDelimiters("Order (2025-Q1) Done", "(", ")" )"#) == .text("2025-Q1"))
        #expect(try await eval(#"Text.Range("PowerBI", 5, 2)"#) == .text("BI"))
        #expect(try await eval(#"Text.Length("Hello")"#) == .number(5))
        #expect(try await eval(#"Text.Start("Hello", 2)"#) == .text("He"))
        #expect(try await eval(#"Text.End("Hello", 2)"#) == .text("lo"))
    }

    @Test("Date.QuarterOfYear, StartOfMonth, EndOfMonth, MonthName, DayOfWeekName")
    func dateExtractFunctions() async throws {
        #expect(try await eval("Date.QuarterOfYear(#date(2024, 2, 15))") == .number(1))
        #expect(try await eval("Date.QuarterOfYear(#date(2024, 11, 5))") == .number(4))
        #expect(try await eval("Date.MonthName(#date(2024, 3, 10))") == .text("March"))
        #expect(try await eval("Date.DayOfWeekName(#date(2024, 1, 1))") == .text("Monday"))
        #expect(try await eval("Date.Day(Date.StartOfMonth(#date(2024, 2, 19)))") == .number(1))
        #expect(try await eval("Date.Day(Date.EndOfMonth(#date(2024, 2, 19)))") == .number(29)) // leap year 2024
        #expect(try await eval("Date.Day(Date.EndOfMonth(#date(2023, 2, 19)))") == .number(28))
    }

    @Test("Splitter.SplitTextByRepeatedLengths & StepFactory commands execute end-to-end")
    func splitByRepeatedLengthsAndStepFactory() async throws {
        let baseSteps = [
            MStep(name: "Source", expression: #"#table({"Code", "Dt"}, {{"AABBCC", #date(2024, 5, 17)}, {"DDEEFF", #date(2024, 11, 2)}})"#)
        ]
        let splitSteps = StepFactory.steps(for: .splitByRepeatedLengths(column: "Code", length: 2, into: ["Code.1", "Code.2", "Code.3"]),
                                           after: "Source", existingNames: ["Source"])
        let dateStep = StepFactory.steps(for: .extractDate(column: "Dt", kind: .quarter, newColumnName: "Quarter"),
                                         after: splitSteps.last!.name,
                                         existingNames: Set(["Source"] + splitSteps.map(\.name)))
        let textStep = StepFactory.steps(for: .extractText(column: "Code.1", kind: .length, newColumnName: "Len"),
                                         after: dateStep.last!.name,
                                         existingNames: Set(["Source"] + splitSteps.map(\.name) + dateStep.map(\.name)))
        let allSteps = baseSteps + splitSteps + dateStep + textStep
        let query = MQuery(steps: allSteps, resultName: allSteps.last!.name)
        let result = try await eval(query.source)
        guard case .table(let tbl) = result else {
            Issue.record("Expected table")
            return
        }
        #expect(tbl.rowCount == 2)
        #expect(tbl.columns.map(\.name).contains("Code.1"))
        #expect(tbl.columns.map(\.name).contains("Code.3"))
        #expect(tbl.columns.map(\.name).contains("Quarter"))
        #expect(tbl.columns.map(\.name).contains("Len"))

        let code1 = try #require(tbl.columns.first { $0.name == "Code.1" })
        let code3 = try #require(tbl.columns.first { $0.name == "Code.3" })
        let qCol = try #require(tbl.columns.first { $0.name == "Quarter" })
        let lenCol = try #require(tbl.columns.first { $0.name == "Len" })
        #expect(code1.data.value(at: 0) == .string("AA"))
        #expect(code3.data.value(at: 1) == .string("FF"))
        #expect(qCol.data.value(at: 0) == .integer(2) || qCol.data.value(at: 0) == .double(2))
        #expect(qCol.data.value(at: 1) == .integer(4) || qCol.data.value(at: 1) == .double(4))
        #expect(lenCol.data.value(at: 0) == .integer(2) || lenCol.data.value(at: 0) == .double(2))
    }
}
