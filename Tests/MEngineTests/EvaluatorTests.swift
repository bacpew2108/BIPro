// Phase F, T049: bộ chạy M (lõi ngôn ngữ, chưa có thư viện hàm). Seam: contracts/m-engine.md (MEvaluator).
// Giá trị kỳ vọng là hằng viết tay theo định nghĩa ngôn ngữ (không tính lại bằng chính mã đang test).
import Testing
import ColumnStore
@testable import MEngine

@Suite struct MEvaluatorTests {
    private func eval(_ source: String, step: String? = nil, rowLimit: Int? = nil, env: MEnvironment = MEnvironment()) async throws -> MValue {
        try await MEvaluator(environment: env).evaluate(source: source, upTo: step, rowLimit: rowLimit)
    }

    private func fails(_ source: String, reason: String = "Expression.Error", containing: String? = nil) async {
        do {
            _ = try await eval(source)
            Issue.record("phải lỗi: \(source)")
        } catch let e as MError {
            #expect(e.reason == reason, "\(source): \(e.reason)")
            if let containing { #expect(e.message.contains(containing), "\(source): \(e.message)") }
        } catch { Issue.record("sai loại lỗi: \(error)") }
    }

    @Test func arithmeticAndText() async throws {
        #expect(try await eval("1 + 2 * 3") == .number(7))
        #expect(try await eval("(1 + 2) * 3") == .number(9))
        #expect(try await eval("10 / 4") == .number(2.5))
        #expect(try await eval("-(3 - 5)") == .number(2))
        #expect(try await eval("\"a\" & \"b\"") == .text("ab"))
        #expect(try await eval("1 / 0") == .number(.infinity))
        #expect(try await eval("1 + null") == .null)
        #expect(try await eval("\"a\" & null") == .null)
        #expect(try await eval("{1} & {2, 3}") == .list([.number(1), .number(2), .number(3)]))
        await fails("1 + \"a\"", containing: "+")
        await fails("\"a\" - 1")
    }

    @Test func comparisonsAndLogic() async throws {
        #expect(try await eval("1 = 1") == .logical(true))
        #expect(try await eval("1 = \"1\"") == .logical(false))
        #expect(try await eval("null = null") == .logical(true))
        #expect(try await eval("1 <> 2") == .logical(true))
        #expect(try await eval("\"abc\" < \"abd\"") == .logical(true))
        #expect(try await eval("\"B\" < \"a\"") == .logical(true))     // so sánh theo thứ tự ký tự, phân biệt hoa thường
        #expect(try await eval("2 >= 2 and 3 > 1") == .logical(true))
        #expect(try await eval("false and (1/0 = 0)") == .logical(false))   // ngắn mạch
        #expect(try await eval("true or (error \"x\")") == .logical(true))
        #expect(try await eval("not false") == .logical(true))
        #expect(try await eval("{1, 2} = {1, 2}") == .logical(true))
        #expect(try await eval("[a = 1, b = 2] = [b = 2, a = 1]") == .logical(true))
        await fails("1 and true")
        await fails("not 1")
    }

    @Test func letIsLazyAndDetectsCycles() async throws {
        #expect(try await eval("let a = 1, b = a + 1 in b * 2") == .number(4))
        #expect(try await eval("let bad = error \"x\", ok = 5 in ok") == .number(5))          // bước lỗi không dùng không làm hỏng
        #expect(try await eval("let b = a + 1, a = 1 in b") == .number(2))                    // tham chiếu tới sau
        await fails("let a = b, b = a in a", containing: "vòng")
        #expect(try await eval("let a = 1, b = 2, c = 3 in c", step: "b") == .number(2))
        #expect(try await eval("let Source = 10, #\"Step 2\" = Source * 2 in #\"Step 2\"", step: "Step 2") == .number(20))
        do {
            _ = try await eval("let a = 1 in a", step: "zzz")
            Issue.record("phải lỗi")
        } catch let e as MError {
            #expect(e.message.contains("Bước") && e.message.contains("zzz"))
        }
        #expect(try await eval("let x = 1 in let x = 2 in x") == .number(2))                  // che khuất
    }

    @Test func functionsClosuresAndEach() async throws {
        #expect(try await eval("let f = (x) => x + 1 in f(2)") == .number(3))
        #expect(try await eval("let n = 10, f = (x) => x + n in f(1)") == .number(11))
        #expect(try await eval("let f = (x, optional y) => if y = null then x else x + y in {f(1), f(1, 2)}") == .list([.number(1), .number(3)]))
        #expect(try await eval("let fact = (n) => if n <= 1 then 1 else n * @fact(n - 1) in fact(5)") == .number(120))
        #expect(try await eval("(each _ * 2)(4)") == .number(8))
        #expect(try await eval("(each [a] + 1)([a = 4])") == .number(5))
        #expect(try await eval("let compose = (f, g) => (x) => f(g(x)) in compose((a) => a + 1, (b) => b * 2)(5)") == .number(11))
        await fails("let f = (x) => x in f()", containing: "đối số")
        await fails("let f = (x) => x in f(1, 2)", containing: "đối số")
        await fails("5(1)", containing: "hàm")
    }

    @Test func recordsAndLists() async throws {
        #expect(try await eval("[a = 1, b = a + 1][b]") == .number(2))                         // trường tham chiếu trường
        #expect(try await eval("[a = 1][c]?") == .null)
        await fails("[a = 1][c]", containing: "c")
        #expect(try await eval("[Order Date = 5][Order Date]") == .number(5))
        #expect(try await eval("[a = 1, b = error \"boom\"][a]") == .number(1))                // trường lỗi chỉ ném khi truy cập
        await fails("[a = 1, b = error \"boom\"][b]", containing: "boom")
        #expect(try await eval("{10, 20, 30}{1}") == .number(20))
        #expect(try await eval("{1..4}") == .list([.number(1), .number(2), .number(3), .number(4)]))
        #expect(try await eval("{10}{5}?") == .null)
        await fails("{10}{5}", containing: "Chỉ mục")
        await fails("{10}{-1}")
        #expect(try await eval("{} = {}") == .logical(true))
    }

    @Test func conditionalsTryAndError() async throws {
        #expect(try await eval("if 1 < 2 then \"y\" else \"n\"") == .text("y"))
        await fails("if 1 then 1 else 2", containing: "logic")
        #expect(try await eval("try error \"x\" otherwise 7") == .number(7))
        #expect(try await eval("try 1 + 1 otherwise 7") == .number(2))
        #expect(try await eval("try 1 + 1") == .record([MField(name: "HasError", value: .logical(false)), MField(name: "Value", value: .number(2))]))
        guard case .record(let fields) = try await eval("try error \"boom\"") else { Issue.record("không phải bản ghi"); return }
        #expect(fields.map(\.name) == ["HasError", "Error"])
        #expect(try await eval("(try error \"boom\")[Error][Message]") == .text("boom"))
        #expect(try await eval("(try error [Reason = \"My.Reason\", Message = \"m\", Detail = 5])[Error][Reason]") == .text("My.Reason"))
        await fails("error \"boom\"", containing: "boom")
    }

    @Test func typesAreValuesAndConformanceWorks() async throws {
        #expect(try await eval("1 is number") == .logical(true))
        #expect(try await eval("\"a\" is number") == .logical(false))
        #expect(try await eval("null is nullable number") == .logical(true))
        #expect(try await eval("null is number") == .logical(false))
        #expect(try await eval("1 is Int64.Type") == .logical(true))
        #expect(try await eval("1.5 is Int64.Type") == .logical(false))
        #expect(try await eval("{1} is list") == .logical(true))
        #expect(try await eval("[a = 1] is record") == .logical(true))
        #expect(try await eval("\"x\" as text") == .text("x"))
        await fails("1 as text", containing: "text")
        #expect(try await eval("type text") == .type(MType(.text)))
        #expect(try await eval("type nullable number") == .type(MType(.number, isNullable: true)))
        #expect(try await eval("Int64.Type") == .type(MType(.int64)))
        #expect(try await eval("Currency.Type") == .type(MType(.currency)))
        #expect(try await eval("type table [A = number, optional B = text]") == .type(MType(.table, fields: [
            MTypeField(name: "A", type: MType(.number)), MTypeField(name: "B", type: MType(.text), isOptional: true)])))
        #expect(try await eval("type {text}") == .type(MType(.list, listItem: [MType(.text)])))
    }

    @Test func tableLiteralsAndAccess() async throws {
        let t = try await eval("#table({\"A\", \"B\"}, {{1, \"x\"}, {2, null}})")
        guard case .table(let table) = t else { Issue.record("không phải bảng"); return }
        #expect(table.rowCount == 2 && table.columns.map(\.name) == ["A", "B"])
        #expect(table.columns.map(\.data.type) == [.double, .string])
        #expect(table.value(row: 0, column: 0) == .double(1))
        #expect(table.value(row: 1, column: 1) == .blank)
        #expect(try await eval("#table({\"A\"}, {{1}, {2}})[A]") == .list([.number(1), .number(2)]))
        #expect(try await eval("#table({\"A\", \"B\"}, {{1, \"x\"}, {2, \"y\"}}){1}") == .record([MField(name: "A", value: .number(2)), MField(name: "B", value: .text("y"))]))
        #expect(try await eval("#table({\"A\"}, {{1}}){3}?") == .null)
        let typed = try await eval("#table(type table [Q = Int64.Type, P = Currency.Type, N = text, D = date, F = logical], {{3, 2.5, \"a\", #date(2026,1,1), true}})")
        guard case .table(let tt) = typed else { Issue.record("không phải bảng"); return }
        #expect(tt.columns.map(\.data.type) == [.integer, .currency, .string, .dateTime, .boolean])
        #expect(tt.value(row: 0, column: 0) == .integer(3))
        #expect(tt.value(row: 0, column: 1) == .currency(25_000))
        #expect(tt.value(row: 0, column: 3) == .dateTime(46023))
        await fails("#table({\"A\", \"A\"}, {})", containing: "A")
        await fails("#table({\"A\"}, {{1, 2}})", containing: "cột")
    }

    @Test func rowLimitTruncatesTheFinalTable() async throws {
        let rows = (1...50).map { "{\($0)}" }.joined(separator: ", ")
        guard case .table(let table) = try await eval("#table({\"N\"}, {\(rows)})", rowLimit: 5) else { Issue.record("không phải bảng"); return }
        #expect(table.rowCount == 5)
        #expect(table.value(row: 4, column: 0) == .double(5))
        guard case .table(let full) = try await eval("#table({\"N\"}, {\(rows)})") else { return }
        #expect(full.rowCount == 50)
    }

    @Test func datesAndDurations() async throws {
        #expect(try await eval("#date(1899, 12, 30)") == .date(0))
        #expect(try await eval("#date(2026, 1, 1)") == .date(46023))
        #expect(try await eval("#date(2026, 1, 31) + #duration(1, 0, 0, 0)") == .date(46054))     // 2026-02-01
        #expect(try await eval("#date(2026, 3, 1) - #date(2026, 2, 1)") == .duration(28))
        #expect(try await eval("#datetime(2026, 1, 1, 12, 0, 0)") == .dateTime(46023.5))
        #expect(try await eval("#duration(1, 12, 0, 0)") == .duration(1.5))
        #expect(try await eval("#date(2026, 1, 1) < #date(2026, 1, 2)") == .logical(true))
        #expect(try await eval("#time(6, 0, 0)") == .time(0.25))
        await fails("#date(2026, 13, 1)", containing: "tháng")
    }

    @Test func unknownNamesAndUnsupportedFunctions() async throws {
        do {
            _ = try await eval("let\n  a = 1,\n  b = Table.Fuzzy(a)\nin b")
            Issue.record("phải lỗi")
        } catch let e as MError {
            #expect(e.reason == "Expression.Unsupported" && e.message.contains("Table.Fuzzy") && e.message.contains("3"))
        }
        await fails("nope + 1", containing: "nope")
    }

    @Test func environmentBindingsAreVisible() async throws {
        let env = MEnvironment(bindings: ["Threshold": .number(10)])
        #expect(try await eval("Threshold * 2", env: env) == .number(20))
        let twice = MFunction(name: "My.Twice", parameters: [MParameter(name: "x")], observed: true) { args in
            guard case .number(let n) = args[0] else { throw MError.expression("cần số") }
            return .number(n * 2)
        }
        let env2 = MEnvironment(bindings: ["My.Twice": .function(twice)])
        #expect(try await eval("My.Twice(21)", env: env2) == .number(42))
    }

    @Test func syntaxErrorsSurfaceAsSyntaxErrors() async {
        do {
            _ = try await eval("1 +")
            Issue.record("phải lỗi")
        } catch is MSyntaxError {
        } catch { Issue.record("sai loại: \(error)") }
    }
}
