// Test suite for F2-DAXTEXT: Text functions golden tests matching Power BI Desktop 2.159.
// Reads golden cases from docs/phase-f2-evidence/vm-f12/golden.tsv and verifies exact match.

import Foundation
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct TextFunctionGoldenTests {

    static let tableID = TableID(raw: 12001)
    static let colID = ColumnID(table: tableID, index: 1)
    static let colTxt = ColumnID(table: tableID, index: 2)
    static let colNfd = ColumnID(table: tableID, index: 3)
    static let colNum = ColumnID(table: tableID, index: 4)

    static func unescape(_ text: String) -> String {
        var out = ""
        var it = text.makeIterator()
        while let c = it.next() {
            if c == "\\" {
                if let next = it.next() {
                    switch next {
                    case "t": out.append("\t")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "\\": out.append("\\")
                    default:
                        out.append("\\")
                        out.append(next)
                    }
                } else {
                    out.append("\\")
                }
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func formatValue(_ v: Value) -> String {
        switch v {
        case .blank:
            return "B"
        case .boolean(let b):
            return "L:\(b ? "TRUE" : "FALSE")"
        case .string(let s):
            return "T:\(s)"
        case .integer, .double, .currency, .dateTime:
            return "N:\(v.asText())"
        }
    }

    struct GoldenRow {
        let caseName: String
        let table: String
        let id: Int?
        let expr: String
        let expectedRaw: String
        let expectedUnescaped: String
    }

    struct TestEnvironment {
        let schema: ModelSchema
        let store: ColumnStore
        let catalog: Catalog
        let evaluator: Evaluator
        let base: FilterContext
        let rows: [GoldenRow]
    }

    static func loadEnvironment() throws -> TestEnvironment {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = fileURL
            .deletingLastPathComponent() // F-TEXT
            .deletingLastPathComponent() // DAXEngineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let goldenURL = repoRoot.appendingPathComponent("docs/phase-f2-evidence/vm-f12/golden.tsv")
        let content = try String(contentsOf: goldenURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        var goldenRows: [GoldenRow] = []
        var txtValues: [Int: String] = [:]
        var nfdValues: [Int: String] = [:]
        var numValues: [Int: Double] = [:]

        for (index, line) in lines.enumerated() {
            if index == 0 { continue } // skip header
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { continue }
            let caseName = parts[0]
            let table = parts[1]
            let id = Int(parts[2])
            let expr = parts[3]
            let expectedRaw = parts[4]
            let expectedUnescaped = unescape(expectedRaw)

            let row = GoldenRow(
                caseName: caseName,
                table: table,
                id: id,
                expr: expr,
                expectedRaw: expectedRaw,
                expectedUnescaped: expectedUnescaped
            )
            goldenRows.append(row)

            if table == "HCol", let id {
                if caseName == "IN-Txt" {
                    // Result format is "T:<string>"
                    let val = expectedUnescaped.hasPrefix("T:") ? String(expectedUnescaped.dropFirst(2)) : expectedUnescaped
                    txtValues[id] = val
                } else if caseName == "IN-Nfd" {
                    let val = expectedUnescaped.hasPrefix("T:") ? String(expectedUnescaped.dropFirst(2)) : expectedUnescaped
                    nfdValues[id] = val
                } else if caseName == "IN-Num" {
                    let numStr = expectedUnescaped.hasPrefix("N:") ? String(expectedUnescaped.dropFirst(2)) : expectedUnescaped
                    numValues[id] = Double(numStr) ?? 0.0
                }
            }
        }

        let sortedIDs = (1...20).map { $0 }
        let txtList: [String?] = sortedIDs.map { txtValues[$0] ?? "" }
        let nfdList: [String?] = sortedIDs.map { nfdValues[$0] ?? "" }
        let numList: [Double?] = sortedIDs.map { numValues[$0] ?? 0.0 }
        let intList: [Int64?] = sortedIDs.map { Int64($0) }

        let schema = ModelSchema(
            culture: "en-US",
            tables: [
                ModelSchema.Table(
                    id: tableID,
                    name: "text_cases",
                    isHidden: false,
                    isUserTable: true,
                    isDateTable: false,
                    columns: [
                        ModelSchema.Column(id: colID, name: "ID", type: .integer, isCalculated: false, isHidden: false, isKey: true, sortByColumn: nil, formatString: nil),
                        ModelSchema.Column(id: colTxt, name: "Txt", type: .string, isCalculated: false, isHidden: false, isKey: false, sortByColumn: nil, formatString: nil),
                        ModelSchema.Column(id: colNfd, name: "Nfd", type: .string, isCalculated: false, isHidden: false, isKey: false, sortByColumn: nil, formatString: nil),
                        ModelSchema.Column(id: colNum, name: "Num", type: .double, isCalculated: false, isHidden: false, isKey: false, sortByColumn: nil, formatString: nil),
                    ]
                )
            ],
            relationships: []
        )

        let source = InMemoryColumnSource(
            schema: schema,
            rowCounts: [tableID: 20],
            columns: [
                colID: ColumnBuilder.integers(intList),
                colTxt: ColumnBuilder.strings(txtList),
                colNfd: ColumnBuilder.strings(nfdList),
                colNum: ColumnBuilder.doubles(numList),
            ]
        )

        let store = ColumnStore(source: source)
        let catalog = Catalog(schema: schema, measures: [])
        let evaluator = Evaluator(store: store, catalog: catalog)
        let base = FilterContext.empty.bound(to: schema)

        return TestEnvironment(
            schema: schema,
            store: store,
            catalog: catalog,
            evaluator: evaluator,
            base: base,
            rows: goldenRows
        )
    }

    /// 4 ô được miễn vì Swift String không giữ được surrogate lẻ.
    static let exemptions: Set<String> = [
        "MID-emoji-u",
        "MID-emoji-u3",
        "RIGHT-emoji-u",
        "LEFT-emoji-u"
    ]

    @Test func testGoldenAllRows() throws {
        let env = try Self.loadEnvironment()
        #expect(env.rows.count == 1198, "golden.tsv phải có đủ 1198 ô kết quả")

        var matchCount = 0
        var failCount = 0
        var exemptCount = 0
        var failures: [(caseName: String, id: Int?, expr: String, expected: String, actual: String)] = []

        for row in env.rows {
            if Self.exemptions.contains(row.caseName) {
                exemptCount += 1
                continue
            }

            var actual = "E"
            if row.table == "HCol", let id = row.id {
                // Đánh giá trong row context của dòng id
                do {
                    let parsed = try parseExpression("ADDCOLUMNS(text_cases, \"v\", \(row.expr))")
                    let bound = try Binder.bind(parsed, catalog: env.catalog)
                    guard case .call(_, let args) = bound, args.count >= 3, let caseBound = args[2] else {
                        throw DAXError(.runtime, "Không trích xuất được biểu thức ca")
                    }

                    var rowVal: Value?
                    var rowErr: DAXError?
                    let rowSet = RowSet(universe: 21, sortedRows: [UInt32(id - 1)])
                    try env.evaluator.iteratePhysical(Self.tableID, rowSet, EvalContext(filter: env.base, row: nil)) { innerCtx in
                        do throws(DAXError) {
                            rowVal = try env.evaluator.scalar(caseBound, in: innerCtx)
                        } catch {
                            rowErr = error
                        }
                    }

                    if rowErr != nil {
                        actual = "E"
                    } else if let rowVal {
                        actual = Self.formatValue(rowVal)
                    } else {
                        actual = "E"
                    }
                } catch {
                    actual = "E"
                }
            } else {
                // Biểu thức hằng HLit*
                do {
                    let parsed = try parseExpression(row.expr)
                    let bound = try Binder.bind(parsed, catalog: env.catalog)
                    let val = try env.evaluator.scalar(bound, in: EvalContext(filter: env.base, row: nil))
                    actual = Self.formatValue(val)
                } catch {
                    actual = "E"
                }
            }

            if actual == row.expectedUnescaped {
                matchCount += 1
            } else {
                failCount += 1
                if failures.count < 30 {
                    failures.append((row.caseName, row.id, row.expr, row.expectedUnescaped, actual))
                }
            }
        }

        print("Kết quả Golden: \(matchCount)/\(env.rows.count) khớp, \(exemptCount) miễn, \(failCount) trượt.")
        if !failures.isEmpty {
            for f in failures.prefix(15) {
                print("TRƯỢT [\(f.caseName)\(f.id.map { "#\($0)" } ?? "")]: Expr=\(f.expr) | Mong đợi=\(f.expected) | Thực tế=\(f.actual)")
            }
        }

        #expect(exemptCount == 4, "Phải có đúng 4 ca miễn")
        #expect(failCount == 0, "\(failCount) ca không khớp golden")
    }

    @Test func testCombineValuesDelimiterValidation() throws {
        let env = try Self.loadEnvironment()
        // Delimiter "" hoặc BLANK() phải ném lỗi
        // Delimiter số 0 được nhận ("a0b")
        let validExpr = "COMBINEVALUES(0, \"a\", \"b\")"
        let parsedValid = try parseExpression(validExpr)
        let boundValid = try Binder.bind(parsedValid, catalog: env.catalog)
        let val = try env.evaluator.scalar(boundValid, in: EvalContext(filter: env.base, row: nil))
        #expect(Self.formatValue(val) == "T:a0b")

        for badDelim in ["\"\"", "BLANK()"] {
            let expr = "COMBINEVALUES(\(badDelim), \"a\", \"b\")"
            var failed = false
            do {
                let parsed = try parseExpression(expr)
                let bound = try Binder.bind(parsed, catalog: env.catalog)
                _ = try env.evaluator.scalar(bound, in: EvalContext(filter: env.base, row: nil))
            } catch let err {
                failed = true
                #expect(err.message.contains("The delimiter value in the 'COMBINEVALUES' function can only be a constant non empty string."))
            }
            #expect(failed, "COMBINEVALUES với delimiter \(badDelim) phải báo lỗi")
        }
    }

    @Test func testFixedLargeDecimalsAndExtremeNumbers() throws {
        let env = try Self.loadEnvironment()

        func evaluateExpr(_ expr: String) throws -> Value {
            let parsed = try parseExpression(expr)
            let bound = try Binder.bind(parsed, catalog: env.catalog)
            return try env.evaluator.scalar(bound, in: EvalContext(filter: env.base, row: nil))
        }

        // FIXED(1.5, 20) = "1.50000000000000000000"
        let val1 = try evaluateExpr("FIXED(1.5, 20)")
        #expect(Self.formatValue(val1) == "T:1.50000000000000000000")

        // FIXED(1.99, 19) không lỗi, bắt đầu "1.99"
        let val2 = try evaluateExpr("FIXED(1.99, 19)")
        let str2 = val2.asText()
        #expect(str2.hasPrefix("1.99"))

        // FIXED(1/3, 127) không lỗi, dài đúng 129 ký tự
        let val3 = try evaluateExpr("FIXED(1/3, 127)")
        let str3 = val3.asText()
        #expect(str3.count == 129)

        // FIXED(1E+300, 2) và FIXED(-1E-300, 127) không lỗi
        let val4 = try evaluateExpr("FIXED(1E+300, 2)")
        let str4 = val4.asText()
        #expect(str4.hasSuffix(".00"))

        let val5 = try evaluateExpr("FIXED(-1E-300, 127)")
        let str5 = val5.asText()
        #expect(str5.count == 129)
        #expect(!str5.hasPrefix("-"))
    }
}
