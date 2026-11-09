// BatchedIterationTests.swift
// E3-cấu-trúc (T008): đường tính gộp phải cho cùng kết quả với đường từng dòng (hợp đồng C2) và phải thật sự chạy
// khi đủ điều kiện (`takenCount` tăng), nếu không test qua nhờ đường cũ thì vô nghĩa.
// Ghi đè công tắc là trạng thái toàn cục nên suite chạy tuần tự.

import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

extension BatchedSerial {
@Suite struct BatchedIterationTests {
    private typealias Col = MiniBank.Columns

    /// Measure thêm vào MiniBank: các biến thể của mẫu gộp được.
    private static let extra: [ModelMeasureInput] = [
        .init(table: "Fact_Trans", name: "SumMaxBal", expression:
            "SUMX ( VALUES ( Fact_Trans[account_key] ), CALCULATE ( MAX ( Fact_Trans[balance_after] ), REMOVEFILTERS ( Dim_Date ) ) )"),
        .init(table: "Fact_Trans", name: "MaxOfMin", expression:
            "MAXX ( VALUES ( Fact_Trans[account_key] ), CALCULATE ( MIN ( Fact_Trans[amount] ) ) )"),
        .init(table: "Fact_Trans", name: "MinOfMax", expression:
            "MINX ( VALUES ( Fact_Trans[account_key] ), CALCULATE ( MAX ( Fact_Trans[amount] ) ) )"),
        .init(table: "Fact_Trans", name: "AvgBalNoRemove", expression: """
            AVERAGEX ( VALUES ( Fact_Trans[account_key] ),
                VAR t = CALCULATE ( MAX ( Fact_Trans[date_key] ) )
                RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), Fact_Trans[date_key] = t ) )
            """),
        .init(table: "Fact_Trans", name: "AvgBalVar", expression: """
            VAR accts = CALCULATETABLE ( VALUES ( Fact_Trans[account_key] ), REMOVEFILTERS ( Dim_Date ) )
            RETURN AVERAGEX ( accts,
                VAR t = CALCULATE ( MAX ( Fact_Trans[date_key] ), REMOVEFILTERS ( Dim_Date ) )
                RETURN CALCULATE ( MAX ( Fact_Trans[balance_after] ), REMOVEFILTERS ( Dim_Date ), Fact_Trans[date_key] = t ) )
            """),
        // Lồng trong vòng lặp ngoài: ngữ cảnh hàng ngoài phải được chuyển như đường cũ.
        .init(table: "Fact_Trans", name: "AvgBalPerYear", expression:
            "SUMX ( VALUES ( Dim_Date[year] ), [Avg Balance] )"),
        // Bọc ALLSELECTED và lặp lồng hai cấp (SUMX ngoài, đường gộp trong).
        .init(table: "Fact_Trans", name: "AvgBalAllSel", expression:
            "CALCULATE ( [Avg Balance], ALLSELECTED ( Dim_Date ) )"),
        .init(table: "Fact_Trans", name: "AvgBalNested", expression:
            "SUMX ( VALUES ( Dim_Client[client_region] ), SUMX ( VALUES ( Dim_Date[year] ), [Avg Balance] ) )"),
        // Lỗi kiểu: cộng chuỗi. Cả hai đường phải ra cùng lỗi.
        .init(table: "Fact_Trans", name: "SumTextMax", expression:
            "SUMX ( VALUES ( Fact_Trans[account_key] ), CALCULATE ( MAX ( Fact_Trans[client_region] ) ) )"),
        // Ngoài mẫu: phải rơi về đường cũ mà vẫn đúng.
        .init(table: "Fact_Trans", name: "SumBalSum", expression:
            "SUMX ( VALUES ( Fact_Trans[account_key] ), CALCULATE ( SUM ( Fact_Trans[balance_after] ) ) )"),
    ]

    private func makeEngine() -> DAXEngine {
        let all = MiniBank.measures.map { ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression) }
            + Self.extra
        return DAXEngine(store: MiniBank.makeStore(), catalog: Catalog(schema: MiniBank.schema, measures: all))
    }

    private func item(_ column: ColumnID, _ values: [Value]) -> FilterItem { FilterItem(column: column, values: values) }

    /// Các ngữ cảnh lọc: không lọc, lọc chiều ngày/vùng/chi nhánh, lọc ngay cột nhóm, lọc cột bước hai.
    private var contexts: [(name: String, filters: [FilterItem], expectsBatch: Bool)] {
        [
            ("không lọc", [], true),
            ("năm 2024", [item(Col.DimDate.year, [.integer(2024)])], true),
            ("năm 2023", [item(Col.DimDate.year, [.integer(2023)])], true),
            ("vùng Miền Bắc", [item(Col.DimClient.clientRegion, [.string("Miền Bắc")])], true),
            ("chi nhánh Hà Nội", [item(Col.DimAccount.branchCity, [.string("Hà Nội")])], true),
            ("lọc ngay cột nhóm", [item(Col.FactTrans.accountKey, [.integer(2), .integer(3)])], true),
            ("năm không có dữ liệu", [item(Col.DimDate.year, [.integer(1999)])], true),
            ("lọc cột ngày của bước một", [item(Col.FactTrans.dateKey, [.integer(20240124), .integer(20240213)])], false),
        ]
    }

    private let measureNames = ["Avg Balance", "SumMaxBal", "MaxOfMin", "MinOfMax", "AvgBalNoRemove", "AvgBalVar",
                                "AvgBalPerYear", "AvgBalAllSel", "AvgBalNested", "SumBalSum"]

    @Test func haiDuongChoCungKetQuaCuaMeasure() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = makeEngine()
        var batchedHits = 0
        for context in contexts {
            for name in measureNames {
                BatchedIteration.overrideEnabled = false
                let old = try await engine.evaluate(measure: name, table: nil, filters: context.filters)
                let before = BatchedIteration.takenCount(engine.store)
                BatchedIteration.overrideEnabled = true
                let new = try await engine.evaluate(measure: name, table: nil, filters: context.filters)
                let taken = BatchedIteration.takenCount(engine.store) - before
                #expect(old == new, "\(name) @ \(context.name): đường cũ \(old) khác đường gộp \(new)")
                if name != "SumBalSum", context.expectsBatch, !(context.name == "năm không có dữ liệu") {
                    #expect(taken > 0, "\(name) @ \(context.name): đường gộp không chạy")
                    batchedHits += taken
                }
                if name == "SumBalSum" { #expect(taken == 0, "SumBalSum ngoài mẫu mà vẫn gộp") }
            }
        }
        #expect(batchedHits > 0)
    }

    @Test func khongChayGopKhiLocCotBuocMot() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = makeEngine()
        BatchedIteration.overrideEnabled = true
        let before = BatchedIteration.takenCount(engine.store)
        let filters = [item(Col.FactTrans.dateKey, [.integer(20240124)])]
        _ = try await engine.evaluate(measure: "Avg Balance", table: nil, filters: filters)
        #expect(BatchedIteration.takenCount(engine.store) == before)
    }

    @Test func haiDuongChoCungKetQuaCuaTruyVan() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = makeEngine()
        let queries = [
            "EVALUATE SUMMARIZECOLUMNS ( Dim_Date[year], \"v\", [Avg Balance] ) ORDER BY Dim_Date[year]",
            "EVALUATE SUMMARIZECOLUMNS ( Dim_Date[year], Dim_Client[client_region], \"v\", [Avg Balance], \"s\", [SumMaxBal] ) ORDER BY Dim_Date[year], Dim_Client[client_region]",
            "EVALUATE SUMMARIZECOLUMNS ( Dim_Date[year_month], \"v\", [AvgBalVar], \"m\", [MaxOfMin] ) ORDER BY Dim_Date[year_month]",
            "EVALUATE ROW ( \"v\", [Avg Balance], \"w\", [AvgBalPerYear] )",
        ]
        for query in queries {
            BatchedIteration.overrideEnabled = false
            let old = try await engine.execute(query).tables
            let before = BatchedIteration.takenCount(engine.store)
            BatchedIteration.overrideEnabled = true
            let new = try await engine.execute(query).tables
            #expect(old == new, "truy vấn khác kết quả: \(query)")
            #expect(BatchedIteration.takenCount(engine.store) > before, "đường gộp không chạy: \(query)")
        }
    }

    @Test func congTacTatThiKhongGop() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = makeEngine()
        BatchedIteration.overrideEnabled = false
        let before = BatchedIteration.takenCount(engine.store)
        _ = try await engine.evaluate(measure: "Avg Balance", table: nil, filters: [])
        #expect(BatchedIteration.takenCount(engine.store) == before)
    }

    @Test func loiKieuRaCungLoiOHaiDuong() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = makeEngine()
        func outcome(_ enabled: Bool) async -> String {
            BatchedIteration.overrideEnabled = enabled
            do {
                let value = try await engine.evaluate(measure: "SumTextMax", table: nil, filters: [])
                return "giá trị \(value)"
            } catch {
                return "lỗi \(error.kind) \(error.message)"
            }
        }
        let old = await outcome(false)
        let before = BatchedIteration.takenCount(engine.store)
        let new = await outcome(true)
        #expect(old == new, "đường cũ: \(old); đường gộp: \(new)")
        #expect(old.hasPrefix("lỗi"), "phép cộng chuỗi phải báo lỗi, nhận: \(old)")
        #expect(BatchedIteration.takenCount(engine.store) == before, "cột chuỗi không được gộp")
    }

    @Test func huyTruocKhiChayThiNemCancelled() async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = makeEngine()
        BatchedIteration.overrideEnabled = true
        let task = Task { () -> DAXError? in
            // Chờ tới khi đã bị huỷ rồi mới chạy: chắc chắn Task.isCancelled đã bật khi vào engine.
            while !Task.isCancelled { await Task.yield() }
            do {
                _ = try await engine.execute("EVALUATE ROW ( \"v\", [Avg Balance] )")
                return nil
            } catch let error as DAXError {
                return error
            } catch {
                return DAXError(.runtime, "\(error)")
            }
        }
        task.cancel()
        let error = await task.value
        #expect(error?.kind == .cancelled, "nhận \(String(describing: error))")
    }
}
}

// MARK: - Trường hợp biên trên model dựng tay (T028)

/// Model nhỏ: bảng T (acct, dk, ts, bal) và bảng chiều Dim (dk), quan hệ T[dk] → Dim[dk].
/// Dữ liệu cố ý có: hai dòng cùng `ts` trong một nhóm, `ts` BLANK, nhóm mà mọi `ts` đều BLANK, và `bal` BLANK ở dòng thắng.
private enum EdgeModel {
    static let tTable = TableID(raw: 1)
    static let dimTable = TableID(raw: 2)
    static let acct = ColumnID(table: tTable, index: 1)
    static let dk = ColumnID(table: tTable, index: 2)
    static let ts = ColumnID(table: tTable, index: 3)
    static let bal = ColumnID(table: tTable, index: 4)
    static let dimKey = ColumnID(table: dimTable, index: 11)

    //                          0     1     2     3     4     5     6     7     8     9     10    11
    static let accts: [Int64?] = [1,    1,    1,    2,    2,    2,    3,    3,    4,    4,    5,    5]
    static let dks: [Int64?]   = [1,    1,    2,    1,    1,    2,    1,    2,    3,    3,    1,    3]
    static let tss: [Double?]  = [10,   20,   20,   5,    nil,  5,    nil,  nil,  30,   7,    40,   40]
    static let bals: [Int64?]  = [100,  200,  300,  50,   70,   nil,  10,   20,   nil,  77,   400,  450]

    static func makeEngine(dense: Bool) -> DAXEngine {
        let t = ModelSchema.Table(id: tTable, name: "T", isHidden: false, isUserTable: true, isDateTable: false, columns: [
            col(acct, "acct", .integer), col(dk, "dk", .integer), col(ts, "ts", .dateTime), col(bal, "bal", .currency),
        ])
        let dim = ModelSchema.Table(id: dimTable, name: "Dim", isHidden: false, isUserTable: true, isDateTable: false, columns: [
            col(dimKey, "dk", .integer),
        ])
        let rel = RelationshipSchema(id: RelationshipID(raw: 1), name: "T-Dim", manyColumn: dk, oneColumn: dimKey,
                                     isActive: true, crossFilter: .oneDirection)
        let schema = ModelSchema(culture: "en-US", tables: [t, dim], relationships: [rel])
        let n = accts.count
        var columns: [ColumnID: ColumnData] = [
            acct: ColumnBuilder.integers(accts),
            dk: ColumnBuilder.integers(dks),
            dimKey: ColumnBuilder.integers([1, 2, 3]),
        ]
        if dense {
            columns[ts] = ColumnData(type: .dateTime, rowCount: n,
                                     payload: .dense(.dates(tss.map { $0 ?? .nan })))
            let blanks = RowSet(universe: n + 1, sortedRows: bals.enumerated().compactMap { $0.element == nil ? UInt32($0.offset) : nil })
            columns[bal] = ColumnData(type: .currency, rowCount: n,
                                      payload: .dense(.integers(bals.map { $0 ?? 0 }, blanks: blanks)))
        } else {
            columns[ts] = ColumnBuilder.dateTimes(tss)
            columns[bal] = ColumnBuilder.currency(bals)
        }
        let source = InMemoryColumnSource(schema: schema, rowCounts: [tTable: n, dimTable: 3], columns: columns)
        let measures: [ModelMeasureInput] = [
            .init(table: "T", name: "AvgRemove", expression: """
                AVERAGEX ( CALCULATETABLE ( VALUES ( T[acct] ), REMOVEFILTERS ( Dim ) ),
                    VAR t = CALCULATE ( MAX ( T[ts] ), REMOVEFILTERS ( Dim ) )
                    RETURN CALCULATE ( MAX ( T[bal] ), REMOVEFILTERS ( Dim ), T[ts] = t ) )
                """),
            .init(table: "T", name: "AvgKeep", expression: """
                AVERAGEX ( VALUES ( T[acct] ),
                    VAR t = CALCULATE ( MAX ( T[ts] ) )
                    RETURN CALCULATE ( MAX ( T[bal] ), T[ts] = t ) )
                """),
            .init(table: "T", name: "MinOfMinBal", expression:
                "MAXX ( VALUES ( T[acct] ), CALCULATE ( MIN ( T[bal] ) ) )"),
        ]
        return DAXEngine(store: ColumnStore(source: source), catalog: Catalog(schema: schema, measures: measures))
    }

    private static func col(_ id: ColumnID, _ name: String, _ type: DAXType) -> ModelSchema.Column {
        ModelSchema.Column(id: id, name: name, type: type, isCalculated: false, isHidden: false, isKey: false,
                           sortByColumn: nil, formatString: nil)
    }

    /// Đáp án tự tính từ dữ liệu thô, độc lập với cả hai đường của engine.
    /// `ignoreDk`: bỏ bộ lọc dk (REMOVEFILTERS(Dim)). Trả nil nếu một nhóm có dòng mà mọi `ts` BLANK (đường gộp bỏ cuộc).
    static func oracleAvg(accounts: Set<Int64>?, dkValues: Set<Int64>?, ignoreDk: Bool) -> Value {
        func visible(_ r: Int) -> Bool {
            if let accounts, !accounts.contains(accts[r]!) { return false }
            if !ignoreDk, let dkValues, !dkValues.contains(dks[r]!) { return false }
            return true
        }
        var byAccount: [Int64: [Int]] = [:]
        for r in 0..<accts.count where visible(r) { byAccount[accts[r]!, default: []].append(r) }
        var sum: Int64 = 0
        var count = 0
        for rows in byAccount.values {
            let t = rows.compactMap { tss[$0] }.max()
            // t BLANK: ts = BLANK khớp các dòng ts BLANK.
            let winners = rows.filter { t == nil ? tss[$0] == nil : tss[$0] == t }
            if let best = winners.compactMap({ bals[$0] }).max() { sum += best; count += 1 }
        }
        return count == 0 ? .blank : .currency(fkRoundedDivide(sum, Int64(count)))
    }
}

extension BatchedSerial {
@Suite struct BatchedEdgeCaseTests {
    private func item(_ column: ColumnID, _ values: [Int64]) -> FilterItem {
        FilterItem(column: column, values: values.map { .integer($0) })
    }

    @Test(arguments: [false, true]) func haiDuongVaDapAnTuTinhKhop(dense: Bool) async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = EdgeModel.makeEngine(dense: dense)
        // (tên, bộ lọc, tập tài khoản, tập dk, đường gộp phải chạy?)
        let cases: [(String, [FilterItem], Set<Int64>?, Set<Int64>?, Bool)] = [
            ("bỏ tài khoản 3 (mọi ts BLANK)", [item(EdgeModel.acct, [1, 2, 4, 5])], [1, 2, 4, 5], nil, true),
            ("chỉ tài khoản 1 (ts trùng giữa hai dk)", [item(EdgeModel.acct, [1])], [1], nil, true),
            ("tài khoản 2 (ts trùng, số dư thắng BLANK ở một dòng)", [item(EdgeModel.acct, [2])], [2], nil, true),
            ("tài khoản 4 (số dư ở dòng thắng BLANK)", [item(EdgeModel.acct, [4])], [4], nil, true),
            ("tài khoản 5 (ts trùng, số dư khác nhau)", [item(EdgeModel.acct, [5])], [5], nil, true),
            ("lọc dk = 1", [item(EdgeModel.acct, [1, 2, 4, 5]), item(EdgeModel.dimKey, [1])], [1, 2, 4, 5], [1], true),
            ("lọc dk = 3", [item(EdgeModel.acct, [1, 2, 4, 5]), item(EdgeModel.dimKey, [3])], [1, 2, 4, 5], [3], true),
            ("có tài khoản 3: t BLANK, đường gộp bỏ cuộc", [], nil, nil, false),
            ("tài khoản không có dữ liệu", [item(EdgeModel.acct, [99])], [99], nil, false),
        ]
        for (name, filters, accounts, dkValues, expectsBatch) in cases {
            for (measure, ignoreDk) in [("AvgRemove", true), ("AvgKeep", false)] {
                BatchedIteration.overrideEnabled = false
                let old = try await engine.evaluate(measure: measure, table: nil, filters: filters)
                let before = BatchedIteration.takenCount(engine.store)
                BatchedIteration.overrideEnabled = true
                let new = try await engine.evaluate(measure: measure, table: nil, filters: filters)
                let taken = BatchedIteration.takenCount(engine.store) - before
                let oracle = EdgeModel.oracleAvg(accounts: accounts, dkValues: dkValues, ignoreDk: ignoreDk)
                let label = "\(measure) @ \(name) (dense=\(dense))"
                #expect(old == new, "\(label): đường cũ \(old) khác đường gộp \(new)")
                #expect(new == oracle, "\(label): đáp án tự tính \(oracle), engine \(new)")
                if expectsBatch { #expect(taken > 0, "\(label): đường gộp không chạy") }
                else if name.hasPrefix("có tài khoản 3") { #expect(taken == 0, "\(label): t BLANK phải bỏ cuộc (taken=\(taken))") }
            }
        }
    }

    @Test(arguments: [false, true]) func nhomRongVaMinMax(dense: Bool) async throws {
        defer { BatchedIteration.overrideEnabled = nil }
        let engine = EdgeModel.makeEngine(dense: dense)
        for filters in [[], [item(EdgeModel.acct, [1, 2])], [item(EdgeModel.acct, [4])], [item(EdgeModel.dimKey, [2])]] {
            BatchedIteration.overrideEnabled = false
            let old = try await engine.evaluate(measure: "MinOfMinBal", table: nil, filters: filters)
            BatchedIteration.overrideEnabled = true
            let new = try await engine.evaluate(measure: "MinOfMinBal", table: nil, filters: filters)
            #expect(old == new, "MinOfMinBal @ \(filters) (dense=\(dense)): \(old) khác \(new)")
        }
    }
}
}
