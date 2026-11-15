// Phase F, T049: khung đăng ký thư viện hàm và trợ giúp đối số (cho gói F-MFUN).
import Testing
import ColumnStore
@testable import MEngine

@Suite struct MLibraryTests {
    @Test func registryHasNoDuplicateNames() {
        #expect(MLibrary.functions.count == MLibrary.all.count)
    }

    @Test func libraryFunctionsAreCallableFromM() async throws {
        let double = MFunction(name: "Test.Double", parameters: [MParameter(name: "n")], observed: true) { args in
            .number(try args.number(0, "Test.Double") * 2)
        }
        let env = MEnvironment(bindings: ["Test.Double": .function(double)])
        #expect(try await MEvaluator(environment: env).evaluate(source: "Test.Double(4)") == .number(8))
    }

    @Test func argumentHelpersReportReadableErrors() throws {
        let args: [MValue] = [.text("x"), .null]
        #expect(try args.text(0, "F") == "x")
        #expect(args.optional(1) == nil)
        #expect(throws: MError.self) { try args.table(0, "Table.F") }
        #expect(throws: MError.self) { try args.number(0, "Number.F") }
    }

    @Test func callPadsOptionalArgumentsWithNull() throws {
        let f = MFunction(name: "F", parameters: [MParameter(name: "a"), MParameter(name: "b", isOptional: true)], observed: true) { args in
            .list(args)
        }
        #expect(try f.call([.number(1)]) == .list([.number(1), .null]))
        #expect(throws: MError.self) { try f.call([.null, .null, .null]) }
    }
}
