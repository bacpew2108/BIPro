// Phase F, T048: bộ tách từ và bộ phân tích M. Seam: contracts/m-engine.md (MParser.parse).
import Testing
@testable import MEngine

@Suite struct MParserTests {
    private func parse(_ s: String) throws -> MExpression { try MParser.parse(s) }
    private func id(_ n: String, _ line: Int = 1) -> MExpression { .identifier(n, line: line) }

    @Test func literals() throws {
        #expect(try parse("1") == .number(1))
        #expect(try parse("1.5e2") == .number(150))
        #expect(try parse("0x1F") == .number(31))
        #expect(try parse(".5") == .number(0.5))
        #expect(try parse("\"a\"\"b\"") == .text("a\"b"))
        #expect(try parse("\"x#(lf)y#(0041)#(cr,lf)#(#)\"") == .text("x\ny\u{41}\r\n#"))
        #expect(try parse("true") == .logical(true))
        #expect(try parse("null") == .null)
        #expect(try parse("#infinity") == .number(.infinity))
    }

    @Test func dottedAndQuotedIdentifiers() throws {
        #expect(try parse("Table.SelectRows") == id("Table.SelectRows"))
        #expect(try parse("#\"Changed Type\"") == id("Changed Type"))
        #expect(try parse("Đơn_giá") == id("Đơn_giá"))
    }

    @Test func operatorPrecedenceFollowsTheSpec() throws {
        #expect(try parse("1 + 2 * 3") == .binary(.add, .number(1), .binary(.multiply, .number(2), .number(3))))
        #expect(try parse("1 - 2 - 3") == .binary(.subtract, .binary(.subtract, .number(1), .number(2)), .number(3)))
        #expect(try parse("a or b and c") == .binary(.or, id("a"), .binary(.and, id("b"), id("c"))))
        #expect(try parse("1 + 2 = 3") == .binary(.equal, .binary(.add, .number(1), .number(2)), .number(3)))
        #expect(try parse("\"a\" & \"b\" & \"c\"") == .binary(.concat, .binary(.concat, .text("a"), .text("b")), .text("c")))
        #expect(try parse("-1 * 2") == .binary(.multiply, .unary(.negate, .number(1)), .number(2)))
        #expect(try parse("not a and b") == .binary(.and, .unary(.not, id("a")), id("b")))
        #expect(try parse("a <> b") == .binary(.notEqual, id("a"), id("b")))
        #expect(try parse("a >= 1 and b <= 2") == .binary(.and, .binary(.greaterOrEqual, id("a"), .number(1)), .binary(.lessOrEqual, id("b"), .number(2))))
    }

    @Test func letInWithQuotedStepNames() throws {
        let m = """
        let
            Source = Csv.Document(File.Contents("C:\\x.csv")),
            #"Promoted Headers" = Table.PromoteHeaders(Source),
            Typed = Table.TransformColumnTypes(#"Promoted Headers", {{"Qty", Int64.Type}})
        in
            Typed
        """
        guard case .letIn(let bindings, let body) = try parse(m) else { Issue.record("không phải let"); return }
        #expect(bindings.map(\.name) == ["Source", "Promoted Headers", "Typed"])
        #expect(body == id("Typed", 6))
        guard case .invoke(let callee, let args, let line) = bindings[2].value else { Issue.record("không phải lời gọi"); return }
        #expect(callee == id("Table.TransformColumnTypes", 4) && line == 4 && args.count == 2)
        #expect(args[1] == .list([.list([.text("Qty"), id("Int64.Type", 4)])]))
    }

    @Test func recordsListsAndAccess() throws {
        #expect(try parse("[a = 1, b = \"x\"]") == .record([MBinding(name: "a", value: .number(1)), MBinding(name: "b", value: .text("x"))]))
        #expect(try parse("[]") == .record([]))
        #expect(try parse("{1, 2..4}") == .list([.number(1), .range(.number(2), .number(4))]))
        #expect(try parse("{}") == .list([]))
        #expect(try parse("r[a]") == .fieldAccess(id("r"), "a", optional: false))
        #expect(try parse("r[Order Date]?") == .fieldAccess(id("r"), "Order Date", optional: true))
        #expect(try parse("t{0}") == .itemAccess(id("t"), .number(0), optional: false))
        #expect(try parse("t{0}?") == .itemAccess(id("t"), .number(0), optional: true))
        #expect(try parse("f(1)(2)") == .invoke(.invoke(id("f"), [.number(1)], line: 1), [.number(2)], line: 1))
        #expect(try parse("[Qty]") == .fieldAccess(id("_"), "Qty", optional: false))
        #expect(try parse("[Qty] * [Price]") == .binary(.multiply, .fieldAccess(id("_"), "Qty", optional: false), .fieldAccess(id("_"), "Price", optional: false)))
        #expect(try parse("Source[Data]{0}[Name]") == .fieldAccess(.itemAccess(.fieldAccess(id("Source"), "Data", optional: false), .number(0), optional: false), "Name", optional: false))
    }

    @Test func functionsEachIfTryError() throws {
        #expect(try parse("each [Qty] > 3") == .function([MParameter(name: "_")], returnType: nil,
            body: .binary(.greater, .fieldAccess(id("_"), "Qty", optional: false), .number(3))))
        #expect(try parse("(x, optional y as number) as number => x") == .function(
            [MParameter(name: "x"), MParameter(name: "y", isOptional: true, type: .primitive("number"))], returnType: .primitive("number"), body: id("x")))
        #expect(try parse("(x) => x + 1") == .function([MParameter(name: "x")], returnType: nil, body: .binary(.add, id("x"), .number(1))))
        #expect(try parse("(1 + 2) * 3") == .binary(.multiply, .binary(.add, .number(1), .number(2)), .number(3)))
        #expect(try parse("if a then 1 else 2") == .ifThenElse(id("a"), .number(1), .number(2)))
        #expect(try parse("try 1 otherwise 2") == .tryOtherwise(.number(1), otherwise: .number(2)))
        #expect(try parse("try 1") == .tryOtherwise(.number(1), otherwise: nil))
        #expect(try parse("error \"boom\"") == .error(.text("boom")))
        #expect(try parse("@f") == id("f"))
    }

    @Test func typesAndTypeOperators() throws {
        #expect(try parse("type text") == .type(.primitive("text")))
        #expect(try parse("type nullable number") == .type(.nullable(.primitive("number"))))
        #expect(try parse("type {number}") == .type(.list(.primitive("number"))))
        #expect(try parse("type table [A = number, optional B = text]") == .type(.table([
            MTypeFieldExpr(name: "A", type: .primitive("number")), MTypeFieldExpr(name: "B", type: .primitive("text"), isOptional: true)])))
        #expect(try parse("x is number") == .isType(id("x"), .primitive("number")))
        #expect(try parse("x as nullable text") == .asType(id("x"), .nullable(.primitive("text"))))
        #expect(try parse("#table(type table [A = number], {{1}})") == .invoke(id("#table"),
            [.type(.table([MTypeFieldExpr(name: "A", type: .primitive("number"))])), .list([.list([.number(1)])])], line: 1))
        #expect(try parse("#date(2026, 1, 15)") == .invoke(id("#date"), [.number(2026), .number(1), .number(15)], line: 1))
    }

    @Test func commentsAndWhitespaceAreSkipped() throws {
        #expect(try parse("1 // hết dòng\n + /* giữa */ 2") == .binary(.add, .number(1), .number(2)))
    }

    @Test func syntaxErrorsCarryLineAndColumn() throws {
        #expect(throws: MSyntaxError.self) { try MParser.parse("let a = in a") }
        do {
            _ = try MParser.parse("1 +\n  * 2")
            Issue.record("phải ném lỗi")
        } catch let e as MSyntaxError {
            #expect(e.line == 2 && e.column == 3)
        } catch { Issue.record("sai loại lỗi") }
        #expect(throws: MSyntaxError.self) { try MParser.parse("\"chưa đóng") }
        #expect(throws: MSyntaxError.self) { try MParser.parse("1 2") }
        // T026: `meta` nay được hỗ trợ (M của Enter Data).
        #expect(try MParser.parse("x meta [a=1]") == .binary(.meta, .identifier("x", line: 1), .record([MBinding(name: "a", value: .number(1))])))
        #expect(throws: MSyntaxError.self) { try MParser.parse("(1") }
    }
}
