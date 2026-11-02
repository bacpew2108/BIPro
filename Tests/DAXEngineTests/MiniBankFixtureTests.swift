// Kiểm tra bộ dữ liệu MiniBank (đợt 0, lead): số dòng, Dim_Date, FK không khớp, cột tính toán,
// tổng amount so với đáp án Python và quan hệ với cờ isActive.
import Testing
import ColumnStore
import DAXTestSupport

/// Đọc cột số nguyên thành mảng, BLANK là nil.
private func integers(_ column: ColumnData, rows: Int) -> [Int64?] {
    (0..<rows).map { row in
        if case .integer(let v) = column.value(at: row) { return v }
        return nil
    }
}

/// Đọc cột chuỗi thành mảng, BLANK là nil.
private func strings(_ column: ColumnData, rows: Int) -> [String?] {
    (0..<rows).map { row in
        if case .string(let v) = column.value(at: row) { return v }
        return nil
    }
}

@Suite struct MiniBankFixtureTests {

    private let source = MiniBank.makeSource()

    @Test func rowCountsPerTable() throws {
        let expected: [(String, TableID, Int)] = [
            ("Dim_Date", MiniBank.Tables.dimDate, 731),
            ("Dim_Client", MiniBank.Tables.dimClient, 6),
            ("Dim_Account", MiniBank.Tables.dimAccount, 5),
            ("Dim_District", MiniBank.Tables.dimDistrict, 3),
            ("Fact_Trans", MiniBank.Tables.factTrans, 40),
            ("Fact_Complaint", MiniBank.Tables.factComplaint, 12),
        ]
        for (name, table, count) in expected {
            #expect(try source.rowCount(table) == count, "số dòng của \(name)")
        }
    }

    @Test func dimDateHasTwoFullYearsWithLeapDay() throws {
        let rows = try source.rowCount(MiniBank.Tables.dimDate)
        let keys = try integers(source.loadColumn(MiniBank.Columns.DimDate.dateKey), rows: rows)
        let fullDate = try source.loadColumn(MiniBank.Columns.DimDate.fullDate)

        #expect(rows == 731)
        #expect(keys.first == 20230101)
        #expect(keys.last == 20241231)

        // 29/02/2024 phải có mặt, và số ngày OLE của nó là 45351 (1899-12-30 là 0).
        let leapRow = keys.firstIndex(of: 20240229)
        #expect(leapRow != nil, "thiếu 29/02/2024")
        if let leapRow {
            #expect(fullDate.value(at: leapRow) == .dateTime(45351))
        }
        #expect(fullDate.value(at: 0) == .dateTime(44927))
        #expect(fullDate.value(at: rows - 1) == .dateTime(45657))
    }

    @Test func factTransHasExactlyOneUnmatchedAccountKey() throws {
        let accountRows = try source.rowCount(MiniBank.Tables.dimAccount)
        let dimAccountKeys = Set(try integers(
            source.loadColumn(MiniBank.Columns.DimAccount.accountKey), rows: accountRows).compactMap { $0 })

        let factRows = try source.rowCount(MiniBank.Tables.factTrans)
        let factKeys = try integers(source.loadColumn(MiniBank.Columns.FactTrans.accountKey), rows: factRows)
        let unmatched = factKeys.compactMap { $0 }.filter { !dimAccountKeys.contains($0) }

        #expect(unmatched == [99], "phải đúng một FK không khớp, khoá 99")
    }

    @Test func calculatedClientRegionHasStoredValues() throws {
        let rows = try source.rowCount(MiniBank.Tables.factTrans)
        let column = try source.loadColumn(MiniBank.Columns.FactTrans.clientRegion)

        #expect(MiniBank.schema.column(MiniBank.Columns.FactTrans.clientRegion)?.isCalculated == true)
        #expect(column.type == .string)
        #expect(strings(column, rows: rows) == MiniBankExpected.transClientRegion)

        // Dòng FK không khớp (khoá 99) phải có client_region là BLANK.
        let orphanRow = try integers(source.loadColumn(MiniBank.Columns.FactTrans.accountKey), rows: rows)
            .firstIndex(of: 99)
        #expect(orphanRow != nil)
        if let orphanRow {
            #expect(column.value(at: orphanRow) == .blank)
        }
    }

    @Test func totalAmountMatchesPythonExpectation() throws {
        let rows = try source.rowCount(MiniBank.Tables.factTrans)
        let column = try source.loadColumn(MiniBank.Columns.FactTrans.amount)

        var total: Int64 = 0
        for row in 0..<rows {
            guard case .currency(let v) = column.value(at: row) else {
                Issue.record("amount dòng \(row) không phải currency")
                continue
            }
            total += v
        }

        #expect(total == MiniBankExpected.totalAmount)
        let expectation = MiniBankExpected.all.first { $0.measure == "Trans Amount" && $0.filter.isEmpty }
        #expect(expectation?.value == .currency(total), "Trans Amount không lọc phải khớp đáp án Python")
    }

    @Test func relationshipCountAndActiveFlags() {
        let rels = MiniBank.schema.relationships

        #expect(rels.count == 6)
        #expect(rels.map(\.id.raw) == [0, 1, 2, 3, 4, 5])
        #expect(rels.allSatisfy { $0.crossFilter == .oneDirection })
        // Chỉ quan hệ Fact_Complaint.sent_date_key -> Dim_Date là inactive.
        #expect(rels.filter { !$0.isActive }.map(\.name) == ["Complaint_SentDate"])

        let sent = rels[4]
        #expect(sent.manyColumn == MiniBank.Columns.FactComplaint.sentDateKey)
        #expect(sent.oneColumn == MiniBank.Columns.DimDate.dateKey)
        #expect(rels[0].manyColumn == MiniBank.Columns.FactTrans.accountKey)
        #expect(rels[0].oneColumn == MiniBank.Columns.DimAccount.accountKey)
    }

    @Test func dimDateIsMarkedAsDateTable() {
        #expect(MiniBank.schema.table(MiniBank.Tables.dimDate)?.isDateTable == true)
        #expect(MiniBank.schema.table(MiniBank.Tables.factTrans)?.isDateTable == false)
    }

    @Test func tableAndColumnIDsAreUniqueAndLoadable() throws {
        let tableIDs = MiniBank.schema.tables.map(\.id)
        #expect(Set(tableIDs).count == tableIDs.count)

        let columnIDs = MiniBank.schema.tables.flatMap(\.columns).map(\.id)
        #expect(Set(columnIDs).count == columnIDs.count)

        // Mọi cột trong lược đồ phải nạp được và có đúng kiểu đã khai báo.
        for column in MiniBank.schema.tables.flatMap(\.columns) {
            let data = try source.loadColumn(column.id)
            #expect(data.type == column.type, "kiểu của \(column.id)")
        }
    }
}
