// MiniBank: model nhỏ dựng tay để test engine DAX (PHASE_B_PLAN §3.5, architecture.md §8.4).
// Không đọc file .pbix. Dữ liệu thô nằm ở MiniBankData.swift, đáp án ở MiniBankExpected.swift,
// measure ở MiniBankMeasures.swift. Lead sở hữu mọi file MiniBank*.swift (đợt 0).
import ColumnStore

public enum MiniBank {

    // MARK: - Định danh bảng và cột

    /// Số thứ tự bảng là `TableID.raw`, duy nhất trong model.
    public enum Tables {
        public static let dimDate = TableID(raw: 1)
        public static let dimClient = TableID(raw: 2)
        public static let dimAccount = TableID(raw: 3)
        public static let dimDistrict = TableID(raw: 4)
        public static let factTrans = TableID(raw: 5)
        public static let factComplaint = TableID(raw: 6)
    }

    /// `ColumnID.index` được gán theo bảng (10 khoảng cho mỗi bảng), nên duy nhất trong model.
    public enum Columns {
        public enum DimDate {
            public static let dateKey = ColumnID(table: Tables.dimDate, index: 1)
            public static let fullDate = ColumnID(table: Tables.dimDate, index: 2)
            public static let year = ColumnID(table: Tables.dimDate, index: 3)
            public static let month = ColumnID(table: Tables.dimDate, index: 4)
            public static let monthIndex = ColumnID(table: Tables.dimDate, index: 5)
            public static let yearMonth = ColumnID(table: Tables.dimDate, index: 6)
        }
        public enum DimClient {
            public static let clientKey = ColumnID(table: Tables.dimClient, index: 11)
            public static let clientRegion = ColumnID(table: Tables.dimClient, index: 12)
        }
        public enum DimAccount {
            public static let accountKey = ColumnID(table: Tables.dimAccount, index: 21)
            public static let clientKey = ColumnID(table: Tables.dimAccount, index: 22)
            public static let branchCity = ColumnID(table: Tables.dimAccount, index: 23)
            public static let cardType = ColumnID(table: Tables.dimAccount, index: 24)
        }
        public enum DimDistrict {
            public static let city = ColumnID(table: Tables.dimDistrict, index: 31)
            public static let stateName = ColumnID(table: Tables.dimDistrict, index: 32)
        }
        public enum FactTrans {
            public static let transKey = ColumnID(table: Tables.factTrans, index: 41)
            public static let dateKey = ColumnID(table: Tables.factTrans, index: 42)
            public static let accountKey = ColumnID(table: Tables.factTrans, index: 43)
            public static let amount = ColumnID(table: Tables.factTrans, index: 44)
            public static let balanceAfter = ColumnID(table: Tables.factTrans, index: 45)
            /// Cột tính toán = RELATED(Dim_Client[client_region]) qua Dim_Account, lưu sẵn.
            public static let clientRegion = ColumnID(table: Tables.factTrans, index: 46)
        }
        public enum FactComplaint {
            public static let complaintKey = ColumnID(table: Tables.factComplaint, index: 51)
            public static let receivedDateKey = ColumnID(table: Tables.factComplaint, index: 52)
            public static let sentDateKey = ColumnID(table: Tables.factComplaint, index: 53)
            public static let clientKey = ColumnID(table: Tables.factComplaint, index: 54)
        }
    }

    // MARK: - Lược đồ

    public static let culture = "en-US"

    /// Lược đồ dựng thủ công bằng `ModelSchema(culture:tables:relationships:)`.
    public static let schema = ModelSchema(
        culture: culture,
        tables: [
            table(Tables.dimDate, "Dim_Date", isDateTable: true, columns: [
                column(Columns.DimDate.dateKey, "date_key", .integer, isKey: true),
                column(Columns.DimDate.fullDate, "full_date", .dateTime),
                column(Columns.DimDate.year, "year", .integer),
                column(Columns.DimDate.month, "month", .integer),
                column(Columns.DimDate.monthIndex, "MonthIndex", .integer),
                column(Columns.DimDate.yearMonth, "year_month", .string),
            ]),
            table(Tables.dimClient, "Dim_Client", columns: [
                column(Columns.DimClient.clientKey, "client_key", .integer, isKey: true),
                column(Columns.DimClient.clientRegion, "client_region", .string),
            ]),
            table(Tables.dimAccount, "Dim_Account", columns: [
                column(Columns.DimAccount.accountKey, "account_key", .integer, isKey: true),
                column(Columns.DimAccount.clientKey, "client_key", .integer),
                column(Columns.DimAccount.branchCity, "branch_city", .string),
                column(Columns.DimAccount.cardType, "card_type", .string),
            ]),
            table(Tables.dimDistrict, "Dim_District", columns: [
                column(Columns.DimDistrict.city, "city", .string),
                column(Columns.DimDistrict.stateName, "state_name", .string),
            ]),
            table(Tables.factTrans, "Fact_Trans", columns: [
                column(Columns.FactTrans.transKey, "trans_key", .integer, isKey: true),
                column(Columns.FactTrans.dateKey, "date_key", .integer),
                column(Columns.FactTrans.accountKey, "account_key", .integer),
                column(Columns.FactTrans.amount, "amount", .currency),
                column(Columns.FactTrans.balanceAfter, "balance_after", .currency),
                column(Columns.FactTrans.clientRegion, "client_region", .string, isCalculated: true),
            ]),
            table(Tables.factComplaint, "Fact_Complaint", columns: [
                column(Columns.FactComplaint.complaintKey, "complaint_key", .integer, isKey: true),
                column(Columns.FactComplaint.receivedDateKey, "received_date_key", .integer),
                column(Columns.FactComplaint.sentDateKey, "sent_date_key", .integer),
                column(Columns.FactComplaint.clientKey, "client_key", .integer),
            ]),
        ],
        relationships: [
            // Thứ tự là RelationshipID.raw. Mọi quan hệ đều crossFilter một chiều.
            relationship(0, "Trans_Account", many: Columns.FactTrans.accountKey, one: Columns.DimAccount.accountKey),
            relationship(1, "Trans_Date", many: Columns.FactTrans.dateKey, one: Columns.DimDate.dateKey),
            relationship(2, "Account_Client", many: Columns.DimAccount.clientKey, one: Columns.DimClient.clientKey),
            relationship(3, "Complaint_ReceivedDate", many: Columns.FactComplaint.receivedDateKey,
                         one: Columns.DimDate.dateKey),
            // Quan hệ thứ hai tới Dim_Date là inactive, chỉ dùng qua USERELATIONSHIP.
            relationship(4, "Complaint_SentDate", many: Columns.FactComplaint.sentDateKey,
                         one: Columns.DimDate.dateKey, isActive: false),
            relationship(5, "Complaint_Client", many: Columns.FactComplaint.clientKey,
                         one: Columns.DimClient.clientKey),
        ])

    // MARK: - Nguồn và kho cột

    /// Nguồn cột dựng trong bộ nhớ. Số dòng và cột lấy từ `MiniBankRaw` và lịch Dim_Date.
    public static func makeSource() -> InMemoryColumnSource {
        let days = calendarDays(fromYear: 2023, toYear: 2024)
        var columns: [ColumnID: ColumnData] = [:]
        var rowCounts: [TableID: Int] = [:]

        // Dim_Date
        rowCounts[Tables.dimDate] = days.count
        columns[Columns.DimDate.dateKey] = ColumnBuilder.integers(optional(days.map(\.dateKey)))
        columns[Columns.DimDate.fullDate] = ColumnData(
            type: .dateTime, rowCount: days.count, payload: .dense(.dates(days.map(\.serial))))
        columns[Columns.DimDate.year] = ColumnBuilder.integers(optional(days.map(\.year)))
        columns[Columns.DimDate.month] = ColumnBuilder.integers(optional(days.map(\.month)))
        columns[Columns.DimDate.monthIndex] = ColumnBuilder.integers(optional(days.map(\.monthIndex)))
        columns[Columns.DimDate.yearMonth] = ColumnBuilder.strings(days.map { Optional($0.yearMonth) })

        // Dim_Client
        rowCounts[Tables.dimClient] = MiniBankRaw.clientKey.count
        columns[Columns.DimClient.clientKey] = ColumnBuilder.integers(optional(MiniBankRaw.clientKey))
        columns[Columns.DimClient.clientRegion] = ColumnBuilder.strings(optional(MiniBankRaw.clientRegion))

        // Dim_Account
        rowCounts[Tables.dimAccount] = MiniBankRaw.accountKey.count
        columns[Columns.DimAccount.accountKey] = ColumnBuilder.integers(optional(MiniBankRaw.accountKey))
        columns[Columns.DimAccount.clientKey] = ColumnBuilder.integers(optional(MiniBankRaw.accountClientKey))
        columns[Columns.DimAccount.branchCity] = ColumnBuilder.strings(optional(MiniBankRaw.accountBranchCity))
        columns[Columns.DimAccount.cardType] = ColumnBuilder.strings(optional(MiniBankRaw.accountCardType))

        // Dim_District
        rowCounts[Tables.dimDistrict] = MiniBankRaw.districtCity.count
        columns[Columns.DimDistrict.city] = ColumnBuilder.strings(optional(MiniBankRaw.districtCity))
        columns[Columns.DimDistrict.stateName] = ColumnBuilder.strings(optional(MiniBankRaw.districtStateName))

        // Fact_Trans
        rowCounts[Tables.factTrans] = MiniBankRaw.transKey.count
        columns[Columns.FactTrans.transKey] = ColumnBuilder.integers(optional(MiniBankRaw.transKey))
        columns[Columns.FactTrans.dateKey] = ColumnBuilder.integers(optional(MiniBankRaw.transDateKey))
        columns[Columns.FactTrans.accountKey] = ColumnBuilder.integers(optional(MiniBankRaw.transAccountKey))
        // amount: dạng dense (không mã hoá), không có BLANK.
        columns[Columns.FactTrans.amount] = ColumnData(
            type: .currency, rowCount: MiniBankRaw.transAmount.count,
            payload: .dense(.integers(MiniBankRaw.transAmount, blanks: nil)))
        // balance_after: dạng encoded (mã hoá theo giá trị).
        columns[Columns.FactTrans.balanceAfter] = ColumnBuilder.currency(optional(MiniBankRaw.transBalanceAfter))
        columns[Columns.FactTrans.clientRegion] = ColumnBuilder.strings(MiniBankRaw.transClientRegion)

        // Fact_Complaint
        rowCounts[Tables.factComplaint] = MiniBankRaw.complaintKey.count
        columns[Columns.FactComplaint.complaintKey] = ColumnBuilder.integers(optional(MiniBankRaw.complaintKey))
        columns[Columns.FactComplaint.receivedDateKey] =
            ColumnBuilder.integers(optional(MiniBankRaw.complaintReceivedDateKey))
        columns[Columns.FactComplaint.sentDateKey] = ColumnBuilder.integers(optional(MiniBankRaw.complaintSentDateKey))
        columns[Columns.FactComplaint.clientKey] = ColumnBuilder.integers(optional(MiniBankRaw.complaintClientKey))

        return InMemoryColumnSource(schema: schema, rowCounts: rowCounts, columns: columns)
    }

    /// Kho cột đọc lười trên nguồn MiniBank.
    public static func makeStore() -> ColumnStore {
        ColumnStore(source: makeSource())
    }

    // MARK: - Hỗ trợ dựng lược đồ

    private static func table(_ id: TableID, _ name: String, isDateTable: Bool = false,
                              columns: [ModelSchema.Column]) -> ModelSchema.Table {
        ModelSchema.Table(id: id, name: name, isHidden: false, isUserTable: true,
                          isDateTable: isDateTable, columns: columns)
    }

    private static func column(_ id: ColumnID, _ name: String, _ type: DAXType,
                               isCalculated: Bool = false, isKey: Bool = false) -> ModelSchema.Column {
        ModelSchema.Column(id: id, name: name, type: type, isCalculated: isCalculated, isHidden: false,
                           isKey: isKey, sortByColumn: nil, formatString: nil)
    }

    private static func relationship(_ raw: Int, _ name: String, many: ColumnID, one: ColumnID,
                                     isActive: Bool = true) -> RelationshipSchema {
        RelationshipSchema(id: RelationshipID(raw: raw), name: name, manyColumn: many, oneColumn: one,
                           isActive: isActive, crossFilter: .oneDirection)
    }

    private static func optional<T>(_ values: [T]) -> [T?] {
        values.map { Optional($0) }
    }

    // MARK: - Lịch Dim_Date

    private struct CalendarDay {
        let dateKey: Int64
        let serial: Double
        let year: Int64
        let month: Int64
        let monthIndex: Int64
        let yearMonth: String
    }

    /// Sinh mọi ngày từ 01/01 `fromYear` đến 31/12 `toYear`, kể cả 29/02 năm nhuận.
    private static func calendarDays(fromYear: Int, toYear: Int) -> [CalendarDay] {
        var days: [CalendarDay] = []
        for year in fromYear...toYear {
            for month in 1...12 {
                for day in 1...daysInMonth(year: year, month: month) {
                    // Số ngày OLE: 1899-12-30 là 0. 1970-01-01 là 25569 ngày sau gốc đó.
                    let serial = Double(daysFromUnixEpoch(year: year, month: month, day: day) + 25569)
                    let monthIndex = (year - fromYear) * 12 + month
                    days.append(CalendarDay(
                        dateKey: Int64(year * 10000 + month * 100 + day),
                        serial: serial,
                        year: Int64(year),
                        month: Int64(month),
                        monthIndex: Int64(monthIndex),
                        yearMonth: yearMonthText(year: year, month: month)))
                }
            }
        }
        return days
    }

    private static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Chuỗi "yyyy-MM" cho cột year_month, không cần Foundation.
    private static func yearMonthText(year: Int, month: Int) -> String {
        let mm = month < 10 ? "0\(month)" : "\(month)"
        return "\(year)-\(mm)"
    }

    /// Công thức ngày civil (thuật toán chuẩn, không phụ thuộc Foundation). Kết quả là số ngày từ 01/01/1970.
    private static func daysFromUnixEpoch(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}
