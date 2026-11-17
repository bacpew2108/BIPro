// Lỗi T096 (`/code-review`): số NaN, ±vô cực hoặc quá lớn đưa vào hàm cần số nguyên làm sập cả app (`Int(Double)`); nay là lỗi M.
import ColumnStore
import Testing
@testable import MEngine

@Suite struct NonFiniteNumberTests {
    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil)
    }

    @Test(arguments: [
        "Text.Start(\"abc\", 1/0)", "Text.End(\"abc\", -1/0)", "Text.PadStart(\"a\", 0/0)",
        "Number.Round(1.5, 1/0)", "Number.RoundUp(1.5, 0/0)", "Number.RoundDown(1.5, 1e300)",
        "List.Numbers(1, 1/0)", "{1, 2}{1/0}",
        "Table.FirstN(#table({\"a\"}, {{1}}), Number.PositiveInfinity)", "Table.Skip(#table({\"a\"}, {{1}}), 1/0)",
        "Table.Range(#table({\"a\"}, {{1}}), 0, 1/0)", "Table.LastN(#table({\"a\"}, {{1}}), 1/0)",
        "Date.AddMonths(#date(2026, 1, 1), 1/0)", "#date(1/0, 1, 1)",
    ])
    func infiniteCountIsAnMError(_ source: String) async {
        await #expect(throws: MError.self) { _ = try await eval(source) }
    }
}

/// Lỗi T096: `\uD83DA` (surrogate cao không có surrogate thấp) làm tràn số UInt32 và sập app; nay thành U+FFFD rồi "A".
@Suite struct JsonBadSurrogateTests {
    @Test func loneHighSurrogateDoesNotCrash() async throws {
        let value = try await MEvaluator(environment: MEnvironment()).evaluate(source: #"Json.Document("[""\uD83DA""]")"#, upTo: nil, rowLimit: nil)
        guard case .list(let items) = value, case .text(let text) = items.first else { Issue.record("sai: \(value)"); return }
        #expect(text == "\u{FFFD}A")
    }
}
