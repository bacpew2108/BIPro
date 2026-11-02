// Kiểm tra lan truyền bộ lọc trên MiniBank (REL, đợt 1b). Đáp án lấy từ MiniBankExpected.swift
// và được kiểm lại bằng Python stdlib (đọc MiniBankData.swift). Chỉ số dòng là 0-based, và
// dòng i của Fact_Trans có trans_key i+1, dòng i của Fact_Complaint có complaint_key i+1.
import Dispatch
import Foundation
import Testing
@testable import ColumnStore
@testable import DAXTestSupport

/// Hộp nhận kết quả từ nhiều luồng (test đồng thời). Mọi thao tác đều giữ khoá.
final class RELResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func append(_ item: T) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    var all: [T] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

@Suite struct RELPropagationMiniBankTests {

    // MARK: - Hỗ trợ

    /// CodeSet cho một giá trị của cột. `.blank` cho mã 0.
    private func filter(_ store: ColumnStore, _ column: ColumnID, _ value: StoredValue) throws -> CodeSet {
        let index = try store.index(column)
        let code = try #require(index.code(of: value), "không có mã cho \(value) ở \(column)")
        return CodeSet(column: column, codes: [UInt32(code)])
    }

    private func visible(_ store: ColumnStore, _ table: TableID, _ filters: [CodeSet],
                         _ overrides: [RelationshipOverride] = []) throws -> RowSet {
        try Propagation.visibleRows(in: store, table: table, localFilters: filters, overrides: overrides)
    }

    /// Tổng amount (currency, nhân 10^4) của các dòng Fact_Trans thấy được.
    private func amountSum(_ store: ColumnStore, _ rows: RowSet) throws -> Int64 {
        let amount = try store.column(MiniBank.Columns.FactTrans.amount)
        var total: Int64 = 0
        rows.forEach { row in
            if case .currency(let value) = amount.value(at: row) { total += value }
        }
        return total
    }

    private var miniBankStore: ColumnStore { MiniBank.makeStore() }

    // MARK: - Lọc từ Dim_Date và Dim_Account

    /// Dim_Date năm 2023: 20 dòng, amount 566230700 (MiniBankExpected, "Dim_Date[year]=2023").
    @Test func filterDimDateYear2023ReachesFactTrans() throws {
        let store = miniBankStore
        let year = try filter(store, MiniBank.Columns.DimDate.year, .integer(2023))
        let rows = try visible(store, MiniBank.Tables.factTrans, [year])
        #expect(rows.count == 20, "Trans Count năm 2023")
        #expect(try amountSum(store, rows) == 566230700)
    }

    /// Dim_Date năm 2024: 20 dòng, amount 688067300 (MiniBankExpected).
    @Test func filterDimDateYear2024ReachesFactTrans() throws {
        let store = miniBankStore
        let year = try filter(store, MiniBank.Columns.DimDate.year, .integer(2024))
        let rows = try visible(store, MiniBank.Tables.factTrans, [year])
        #expect(rows.count == 20)
        #expect(try amountSum(store, rows) == 688067300)
    }

    /// Dim_Account[card_type] = No Card: chỉ tài khoản 3, 8 dòng, amount 378100000 (MiniBankExpected).
    @Test func filterDimAccountCardTypePropagatesThroughAccountKey() throws {
        let store = miniBankStore
        let card = try filter(store, MiniBank.Columns.DimAccount.cardType, .string("No Card"))
        let rows = try visible(store, MiniBank.Tables.factTrans, [card])
        #expect(rows.count == 8)
        #expect(try amountSum(store, rows) == 378100000)
    }

    /// Dim_Account[branch_city] = Hà Nội: tài khoản 1 và 4, 16 dòng, amount 556763500.
    @Test func filterDimAccountBranchPropagatesToFactTrans() throws {
        let store = miniBankStore
        let city = try filter(store, MiniBank.Columns.DimAccount.branchCity, .string("Hà Nội"))
        let rows = try visible(store, MiniBank.Tables.factTrans, [city])
        #expect(rows.count == 16)
        #expect(try amountSum(store, rows) == 556763500)
    }

    /// Giao hai bộ lọc: năm 2024 và Hà Nội, 7 dòng, amount 279462800.
    @Test func combinedDateAndAccountFiltersIntersect() throws {
        let store = miniBankStore
        let year = try filter(store, MiniBank.Columns.DimDate.year, .integer(2024))
        let city = try filter(store, MiniBank.Columns.DimAccount.branchCity, .string("Hà Nội"))
        let rows = try visible(store, MiniBank.Tables.factTrans, [year, city])
        #expect(rows.count == 7)
        #expect(try amountSum(store, rows) == 279462800)
    }

    /// Không có bộ lọc: mọi 40 dòng, kể cả dòng FK 99 đi vào blank row. Tổng bằng `totalAmount`.
    @Test func unfilteredFactTransKeepsEveryRowIncludingUnmatched() throws {
        let store = miniBankStore
        let rows = try visible(store, MiniBank.Tables.factTrans, [])
        #expect(rows.count == 40)
        #expect(rows.universe == 41)
        #expect(try amountSum(store, rows) == MiniBankExpected.totalAmount)
    }

    // MARK: - Hai bước và cột tính toán

    /// Dim_Client[client_region] = Miền Bắc qua Dim_Account: hai bước, amount 556763500.
    @Test func twoHopFilterFromDimClientReachesFactTrans() throws {
        let store = miniBankStore
        let region = try filter(store, MiniBank.Columns.DimClient.clientRegion, .string("Miền Bắc"))
        let rows = try visible(store, MiniBank.Tables.factTrans, [region])
        #expect(try amountSum(store, rows) == 556763500)
        #expect(rows.count == 16)
    }

    /// Miền Nam chỉ có khách 3 và 5, mà không tài khoản nào thuộc hai khách này, nên không dòng nào.
    @Test func filterWithNoMatchingAccountsGivesNoFactRows() throws {
        let store = miniBankStore
        let region = try filter(store, MiniBank.Columns.DimClient.clientRegion, .string("Miền Nam"))
        let rows = try visible(store, MiniBank.Tables.factTrans, [region])
        #expect(rows.count == 0)
    }

    /// Cột tính toán client_region của Fact_Trans (lọc tại chỗ): Unknown là khách -1, amount 192866700.
    @Test func calculatedColumnFilterOnFactTransItself() throws {
        let store = miniBankStore
        let unknown = try filter(store, MiniBank.Columns.FactTrans.clientRegion, .string("Unknown"))
        let rows = try visible(store, MiniBank.Tables.factTrans, [unknown])
        #expect(try amountSum(store, rows) == 192866700)
        #expect(rows.rows == [0, 15, 17, 21, 29, 31, 37], "trans_key 1,16,18,22,30,32,38")
    }

    // MARK: - Blank row

    /// FK 99 không khớp Dim_Account, nên Dim_Account có blank row. Lọc BLANK giữ đúng dòng đó.
    @Test func blankDimAccountKeepsOnlyTheUnmatchedFactRow() throws {
        let store = miniBankStore
        let blank = try filter(store, MiniBank.Columns.DimAccount.branchCity, .blank)
        let rows = try visible(store, MiniBank.Tables.factTrans, [blank])
        #expect(rows.count == 1, "Trans Count (BLANK) = 1")
        #expect(rows.rows == [32], "trans_key 33, FK 99")
        #expect(try amountSum(store, rows) == -2031000)
    }

    /// Blank row ảo của Dim_Account (chỉ số 5) hiện ra khi lọc BLANK, và chỉ dòng đó.
    @Test func blankRowOfDimAccountIsTheOnlyVisibleRowWhenSelected() throws {
        let store = miniBankStore
        let blank = try filter(store, MiniBank.Columns.DimAccount.branchCity, .blank)
        let rows = try visible(store, MiniBank.Tables.dimAccount, [blank])
        #expect(rows.universe == 6)
        #expect(rows.rows == [5])
    }

    /// Không lọc: Dim_Account có blank row (vì có FK không khớp), nên universe có cả 5 dòng và blank.
    @Test func blankRowExistsWhenSomeFactRowIsUnmatched() throws {
        let store = miniBankStore
        let rows = try visible(store, MiniBank.Tables.dimAccount, [])
        #expect(rows.count == 6)
        #expect(rows.contains(5))
    }

    /// Dim_Client không có FK không khớp, nên không có blank row, và kết quả không có chỉ số 6.
    @Test func noBlankRowWhenEveryKeyMatches() throws {
        let store = miniBankStore
        let rows = try visible(store, MiniBank.Tables.dimClient, [])
        #expect(rows.count == 6)
        #expect(rows.contains(6) == false)
    }

    /// Không phải BLANK: 39 dòng, loại dòng FK 99.
    @Test func notBlankFilterExcludesUnmatchedFactRow() throws {
        let store = miniBankStore
        let all = try store.index(MiniBank.Columns.DimAccount.branchCity).codeLimit ?? 0
        let codes = (1..<all).map { UInt32($0) }
        let notBlank = CodeSet(column: MiniBank.Columns.DimAccount.branchCity, codes: codes)
        let rows = try visible(store, MiniBank.Tables.factTrans, [notBlank])
        #expect(rows.count == 39)
    }

    // MARK: - Quan hệ không hoạt động

    /// Quan hệ Complaint_SentDate không hoạt động. Mặc định chỉ Complaint_ReceivedDate lan truyền.
    /// Tháng 2024-05 theo ngày nhận: complaint 5, 7, 12.
    @Test func inactiveSentDateIsNotPropagatedByDefault() throws {
        let store = miniBankStore
        let month = try filter(store, MiniBank.Columns.DimDate.yearMonth, .string("2024-05"))
        let rows = try visible(store, MiniBank.Tables.factComplaint, [month])
        #expect(rows.rows == [4, 6, 11], "theo received_date_key: complaint 5, 7, 12")
    }

    /// USERELATIONSHIP bật Complaint_SentDate (id 4) và tắt Complaint_ReceivedDate cùng cặp bảng.
    /// Tháng 2024-05 theo ngày gửi: complaint 1, 5, 7, 12.
    @Test func userelationshipActivatesSentDatePropagation() throws {
        let store = miniBankStore
        let month = try filter(store, MiniBank.Columns.DimDate.yearMonth, .string("2024-05"))
        let override = RelationshipOverride(relationship: RelationshipID(raw: 4), isActive: true)
        let rows = try visible(store, MiniBank.Tables.factComplaint, [month], [override])
        #expect(rows.rows == [0, 4, 6, 11], "theo sent_date_key: complaint 1, 5, 7, 12")
    }

    // MARK: - Hai chiều

    /// Mặc định Fact_Complaint không lọc Dim_Client. Với CROSSFILTER both (id 5) thì lọc lan sang khách.
    /// Complaint 1 thuộc khách -1, nên Dim_Client chỉ còn dòng 0, và Fact_Trans qua tài khoản 5.
    @Test func crossFilterBothPropagatesFromComplaintToClientAndAccounts() throws {
        let store = miniBankStore
        let complaint = try filter(store, MiniBank.Columns.FactComplaint.complaintKey, .integer(1))

        let oneWay = try visible(store, MiniBank.Tables.dimClient, [complaint])
        #expect(oneWay.count == 6, "một chiều: không lan ngược")

        let both = RelationshipOverride(relationship: RelationshipID(raw: 5), crossFilter: .bothDirections)
        let clients = try visible(store, MiniBank.Tables.dimClient, [complaint], [both])
        #expect(clients.rows == [0], "chỉ khách -1")

        let trans = try visible(store, MiniBank.Tables.factTrans, [complaint], [both])
        #expect(trans.rows == [0, 15, 17, 21, 29, 31, 37])
        #expect(try amountSum(store, trans) == 192866700)
    }

    /// Lọc khách 1 đi xuống Fact_Complaint (dòng 2, 9, 11) và Fact_Trans (tài khoản 1, 8 dòng), cả hai chiều.
    @Test func bothDirectionsKeepsDownwardPropagationFromClient() throws {
        let store = miniBankStore
        let client = try filter(store, MiniBank.Columns.DimClient.clientKey, .integer(1))
        let both = RelationshipOverride(relationship: RelationshipID(raw: 5), crossFilter: .bothDirections)
        let complaints = try visible(store, MiniBank.Tables.factComplaint, [client], [both])
        #expect(complaints.rows == [1, 8, 10])
        let trans = try visible(store, MiniBank.Tables.factTrans, [client], [both])
        #expect(trans.count == 8)
        #expect(try amountSum(store, trans) == 268034100)
    }

    /// Hai chiều trên Complaint_Client nhưng Fact_Complaint không bị lọc: mọi khách vẫn thấy được,
    /// kể cả khách 2 không có khiếu nại nào (không ẩn dòng bên một chỉ vì bên nhiều không có bộ lọc).
    @Test func unfilteredFactDoesNotHideDimensionRowsUnderBothDirections() throws {
        let store = miniBankStore
        let both = RelationshipOverride(relationship: RelationshipID(raw: 5), crossFilter: .bothDirections)
        let clients = try visible(store, MiniBank.Tables.dimClient, [], [both])
        #expect(clients.count == 6)
        #expect(clients.contains(2))
    }

    /// Hai chiều trên Complaint_Client tạo hai đường có hướng từ Dim_Date tới Fact_Trans.
    /// Không có bộ lọc đi từ Dim_Date thì không lan truyền nào đi qua hai đường đó, nên không báo lỗi.
    /// Có bộ lọc năm từ Dim_Date thì báo mơ hồ.
    @Test func ambiguityIsReportedOnlyWhenAFilterStartsAtTheAmbiguousSource() throws {
        let store = miniBankStore
        let both = RelationshipOverride(relationship: RelationshipID(raw: 5), crossFilter: .bothDirections)
        let unfiltered = try visible(store, MiniBank.Tables.factTrans, [], [both])
        #expect(unfiltered.count == 40)

        let year = try filter(store, MiniBank.Columns.DimDate.year, .integer(2023))
        do {
            _ = try visible(store, MiniBank.Tables.factTrans, [year], [both])
            Issue.record("phải báo mơ hồ từ Dim_Date tới Fact_Trans")
        } catch let error as PropagationError {
            #expect(error == .ambiguousPath(from: MiniBank.Tables.dimDate, to: MiniBank.Tables.factTrans))
        }
    }

    // MARK: - Đồng thời

    /// Nhiều luồng cùng hỏi một kết quả thì mọi luồng nhận cùng đáp án, và chỉ số được dựng một lần.
    @Test func concurrentPropagationGivesIdenticalResults() throws {
        let store = miniBankStore
        let city = try filter(store, MiniBank.Columns.DimAccount.branchCity, .string("Hà Nội"))
        let results = RELResultBox<[UInt32]>()
        let failures = RELResultBox<Int>()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            do {
                let rows = try Propagation.visibleRows(in: store, table: MiniBank.Tables.factTrans,
                                                       localFilters: [city], overrides: [])
                results.append(rows.rows)
            } catch {
                failures.append(1)
            }
        }
        #expect(failures.all.isEmpty)
        #expect(results.all.count == 32)
        #expect(Set(results.all).count == 1, "32 luồng cho cùng một kết quả")
    }
}
