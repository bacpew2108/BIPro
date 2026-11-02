// Kiểm tra ColumnData và ColumnIndex trên MiniBank (CS, đợt 1a): value(at:) khớp dữ liệu gốc,
// posting list đúng, code(of:) và sortRank nhất quán.
import Testing
@testable import ColumnStore
@testable import DAXTestSupport

@Suite struct CSColumnDataTests {

    @Test func valueAtMatchesRawMiniBankData() throws {
        let store = MiniBank.makeStore()
        let c = MiniBank.Columns.self

        let clientKeys = try store.column(c.DimClient.clientKey)
        for (row, key) in MiniBankRaw.clientKey.enumerated() {
            #expect(clientKeys.value(at: row) == .integer(key), "Dim_Client.client_key dòng \(row)")
        }

        let accountCity = try store.column(c.DimAccount.branchCity)
        for (row, city) in MiniBankRaw.accountBranchCity.enumerated() {
            #expect(accountCity.value(at: row) == .string(city), "Dim_Account.branch_city dòng \(row)")
        }

        let transKey = try store.column(c.FactTrans.transKey)
        let transDate = try store.column(c.FactTrans.dateKey)
        let transAccount = try store.column(c.FactTrans.accountKey)
        for row in 0..<MiniBankRaw.transKey.count {
            #expect(transKey.value(at: row) == .integer(MiniBankRaw.transKey[row]))
            #expect(transDate.value(at: row) == .integer(MiniBankRaw.transDateKey[row]))
            #expect(transAccount.value(at: row) == .integer(MiniBankRaw.transAccountKey[row]))
        }

        // amount là dense, không có BLANK: giá trị là currency nguyên, không đổi.
        let amount = try store.column(c.FactTrans.amount)
        #expect(!amount.isEncoded, "amount phải dense")
        for row in 0..<MiniBankRaw.transAmount.count {
            #expect(amount.value(at: row) == .currency(MiniBankRaw.transAmount[row]), "amount dòng \(row)")
        }

        // balance_after mã hoá theo giá trị, có thể có BLANK.
        let balance = try store.column(c.FactTrans.balanceAfter)
        for row in 0..<MiniBankRaw.transBalanceAfter.count {
            #expect(balance.value(at: row) == .currency(MiniBankRaw.transBalanceAfter[row]), "balance_after dòng \(row)")
        }

        // Cột tính toán có BLANK ở dòng nil; chuỗi rỗng khác BLANK.
        let region = try store.column(c.FactTrans.clientRegion)
        for (row, value) in MiniBankRaw.transClientRegion.enumerated() {
            let expected: StoredValue = value.map { .string($0) } ?? .blank
            #expect(region.value(at: row) == expected, "client_region dòng \(row)")
        }
    }

    @Test func rowBeyondRangeIsBlank() throws {
        let store = MiniBank.makeStore()
        let column = try store.column(MiniBank.Columns.FactTrans.transKey)
        #expect(column.value(at: column.rowCount) == .blank, "blank row ảo")
        #expect(column.value(at: -1) == .blank)
        #expect(column.value(at: column.rowCount + 5) == .blank)
    }

    @Test func postingsMatchBruteForceOnEveryEncodedColumn() throws {
        let store = MiniBank.makeStore()
        var checked = 0
        for table in MiniBank.schema.tables {
            for column in table.columns {
                let data = try store.column(column.id)
                let index = try store.index(column.id)
                guard let limit = index.codeLimit else {
                    #expect(index.postings(forCode: 0) == nil, "cột dense không có posting")
                    continue
                }
                checked += 1
                var total = 0
                for code in 0..<limit {
                    var expected: [UInt32] = []
                    for row in 0..<data.rowCount where data.code(atRow: row) == code {
                        expected.append(UInt32(row))
                    }
                    let actual = Array(index.postings(forCode: code) ?? [])
                    #expect(actual == expected, "posting \(table.name)[\(column.name)] mã \(code)")
                    total += actual.count
                }
                #expect(total == data.rowCount, "tổng posting phải bằng số dòng: \(table.name)[\(column.name)]")
                #expect(index.postings(forCode: limit) == nil, "mã ngoài phạm vi")
            }
        }
        #expect(checked > 0)
    }

    @Test func codeOfRoundTripsEveryValue() throws {
        let store = MiniBank.makeStore()
        for table in MiniBank.schema.tables {
            for column in table.columns {
                let data = try store.column(column.id)
                let index = try store.index(column.id)
                guard index.codeLimit != nil else {
                    #expect(index.code(of: .integer(1)) == nil)
                    continue
                }
                for row in 0..<data.rowCount {
                    let value = data.value(at: row)
                    #expect(index.code(of: value) == data.code(atRow: row),
                            "code(of:) dòng \(row) của \(table.name)[\(column.name)]")
                }
                #expect(index.code(of: .string("không có trong dictionary")) == nil)
            }
        }
    }

    @Test func sortRankOrdersValuesAndPutsBlankFirst() throws {
        let store = MiniBank.makeStore()

        // Số: thứ hạng tăng theo giá trị.
        let keyIndex = try store.index(MiniBank.Columns.DimClient.clientKey)
        let keyOrder = try #require(keyIndex.codesInSortOrder())
        #expect(keyOrder.first == 0, "BLANK đứng đầu")
        let keyValues = keyOrder.dropFirst().map { keyIndex.column.dictionaryValue(code: $0)! }
        #expect(keyValues == keyValues.sorted { lhs, rhs in
            guard case .integer(let a) = lhs, case .integer(let b) = rhs else { return false }
            return a < b
        })

        // Chuỗi: so theo chữ thường Unicode. "hà nội" < "tp. hồ chí minh" < "đà nẵng" (đ có mã lớn hơn t).
        let cityIndex = try store.index(MiniBank.Columns.DimAccount.branchCity)
        let cityOrder = try #require(cityIndex.codesInSortOrder())
        let cities = cityOrder.dropFirst().map { cityIndex.column.dictionaryValue(code: $0)! }
        #expect(cities == [.string("Hà Nội"), .string("TP. Hồ Chí Minh"), .string("Đà Nẵng")])

        // Thứ hạng là hoán vị của 0...k và khớp với codesInSortOrder.
        for code in 0...cityIndex.column.dictionaryCount {
            let rank = try #require(cityIndex.sortRank(ofCode: code))
            #expect(cityOrder[rank] == code)
        }
        #expect(cityIndex.sortRank(ofCode: cityIndex.column.dictionaryCount + 1) == nil)
    }

    @Test func denseColumnHasNoCodeFunctions() throws {
        let store = MiniBank.makeStore()
        let index = try store.index(MiniBank.Columns.FactTrans.amount)
        #expect(index.codeLimit == nil)
        #expect(index.postings(forCode: 0) == nil)
        #expect(index.rowSet(forCode: 0) == nil)
        #expect(index.sortRank(ofCode: 0) == nil)
        #expect(index.codesInSortOrder() == nil)
        #expect(index.code(of: .currency(1)) == nil)
    }

    @Test func rowSetFromPostingsMatchesPostings() throws {
        let store = MiniBank.makeStore()
        let index = try store.index(MiniBank.Columns.DimAccount.clientKey)
        // MiniBank nạp mọi giá trị của client_key như số thường (kể cả -1), nên không có dòng BLANK.
        let blankRows = try #require(index.rowSet(forCode: 0))
        #expect(blankRows.count == 0)
        #expect(blankRows.universe == MiniBankRaw.accountClientKey.count + 1)

        // Mã của giá trị -1 chứa đúng dòng có -1 trong dữ liệu gốc.
        let minusOne = try #require(index.code(of: .integer(-1)))
        let rows = try #require(index.rowSet(forCode: minusOne))
        #expect(rows.rows == (0..<MiniBankRaw.accountClientKey.count)
            .filter { MiniBankRaw.accountClientKey[$0] == -1 }.map { UInt32($0) })
    }
}
