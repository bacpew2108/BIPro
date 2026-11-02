import Foundation
import Testing
@testable import BIPro
@testable import PBIXKit

@Suite struct QuickQueryTests {
    private static let evidenceDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/phase-b-evidence/observe2")

    private static func loadEvidence(_ filename: String) throws -> String {
        let fileURL = evidenceDir.appendingPathComponent(filename)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
    }

    // Dữ liệu model nhỏ dựng bằng tay khớp với ví dụ
    private static let transAmount = MeasureInfo(
        tableName: "Fact_Transaction",
        name: "Trans Amount",
        expression: "SUM ( Fact_Transaction[amount] )",
        description: nil
    )

    private static let totalCreditInflow = MeasureInfo(
        tableName: "Fact_Transaction",
        name: "Total_Credit_Inflow",
        expression: "CALCULATE ( [Trans Amount], KEEPFILTERS ( Dim_Trans_Type[trans_type] = \"Credit\" ) )",
        description: "Tổng tiền vào = Σ amount với trans_type = Credit (OLAP v4)"
    )

    private static let totalDebitOutflow = MeasureInfo(
        tableName: "Fact_Transaction",
        name: "Total_Debit_Outflow",
        expression: "CALCULATE ( [Trans Amount], KEEPFILTERS ( Dim_Trans_Type[trans_type] = \"Debit\" ) )",
        description: "Tổng tiền ra = Σ amount với trans_type = Debit (OLAP v4)"
    )

    private static let netCashflow = MeasureInfo(
        tableName: "Fact_Transaction",
        name: "Net_Cashflow",
        expression: "[Total_Credit_Inflow] - [Total_Debit_Outflow]",
        description: "Dòng tiền ròng = Tiền vào − Tiền ra"
    )

    private static let allMeasures = [
        transAmount,
        totalCreditInflow,
        totalDebitOutflow,
        netCashflow
    ]

    private static let dimDateColumns: [ColumnInfo] = [
        ColumnInfo(tableName: "Dim_Date", name: "date_key", isKey: false, isDateTime: false),
        ColumnInfo(tableName: "Dim_Date", name: "full_date", isKey: true, isDateTime: true),
        ColumnInfo(tableName: "Dim_Date", name: "day_of_month"),
        ColumnInfo(tableName: "Dim_Date", name: "day_name"),
        ColumnInfo(tableName: "Dim_Date", name: "day_of_week"),
        ColumnInfo(tableName: "Dim_Date", name: "is_weekend"),
        ColumnInfo(tableName: "Dim_Date", name: "week_of_year"),
        ColumnInfo(tableName: "Dim_Date", name: "month_num"),
        ColumnInfo(tableName: "Dim_Date", name: "month_name"),
        ColumnInfo(tableName: "Dim_Date", name: "quarter_num"),
        ColumnInfo(tableName: "Dim_Date", name: "quarter_name"),
        ColumnInfo(tableName: "Dim_Date", name: "year"),
        ColumnInfo(tableName: "Dim_Date", name: "year_month"),
        ColumnInfo(tableName: "Dim_Date", name: "MonthIndex"),
        ColumnInfo(tableName: "Dim_Date", name: "month_start")
    ]

    @Test func mau1DanhGiaMeasure() throws {
        let expected = try Self.loadEvidence("O8-query-1.dax")
        let actual = QuickQueries.evaluate(measure: Self.netCashflow)
        #expect(Self.normalize(actual) == Self.normalize(expected))
    }

    @Test func mau2DinhNghiaVaDanhGiaMeasure() throws {
        let expected = try Self.loadEvidence("O8-query-2.dax")
        let actual = QuickQueries.defineAndEvaluate(measure: Self.netCashflow)
        #expect(Self.normalize(actual) == Self.normalize(expected))
    }

    @Test func mau3DinhNghiaKemThamChieuVaDanhGiaMeasure() throws {
        let expected = try Self.loadEvidence("O8-query-3.dax")
        let actual = QuickQueries.defineWithReferencesAndEvaluate(
            measure: Self.netCashflow,
            allMeasures: Self.allMeasures
        )
        #expect(Self.normalize(actual) == Self.normalize(expected))
    }

    @Test func mau4BangHien100DongDau() throws {
        let expected = try Self.loadEvidence("O8-query-4.dax")
        let actual = QuickQueries.top100Rows(table: "Dim_Date", columns: Self.dimDateColumns)
        #expect(Self.normalize(actual) == Self.normalize(expected))
    }

    @Test func mau5CotXemTruocDuLieu() throws {
        let expected = try Self.loadEvidence("O8-query-5.dax")
        let actual = QuickQueries.previewData(tableName: "Dim_Date", columnName: "year")
        #expect(Self.normalize(actual) == Self.normalize(expected))
    }

    @Test func mau6DinhNghiaMeasureMoi() {
        let actual = QuickQueries.defineNewMeasure(tableName: "Fact_Transaction")
        let expected = """
        DEFINE
            MEASURE 'Fact_Transaction'[Measure mới] = 

        EVALUATE
            SUMMARIZECOLUMNS(
                "Measure mới", [Measure mới]
            )
        """
        #expect(Self.normalize(actual) == Self.normalize(expected))

        let actualEscaped = QuickQueries.defineNewMeasure(tableName: "Fact'Transaction")
        #expect(actualEscaped.contains("MEASURE 'Fact''Transaction'[Measure mới] = "))
    }

    @Test func mau7DinhNghiaMoiMeasureTrongMoHinh() {
        let actual = QuickQueries.defineAllMeasures(
            clickedMeasure: Self.netCashflow,
            allMeasures: Self.allMeasures
        )
        #expect(actual.hasPrefix("DEFINE\n"))
        #expect(actual.contains("MEASURE 'Fact_Transaction'[Net_Cashflow] = "))
        #expect(actual.contains("MEASURE 'Fact_Transaction'[Total_Credit_Inflow] = "))
        #expect(actual.contains("MEASURE 'Fact_Transaction'[Total_Debit_Outflow] = "))
        #expect(actual.contains("MEASURE 'Fact_Transaction'[Trans Amount] = "))

        // Kiểm tra thứ tự A-Z
        let rNet = actual.range(of: "MEASURE 'Fact_Transaction'[Net_Cashflow]")!
        let rCredit = actual.range(of: "MEASURE 'Fact_Transaction'[Total_Credit_Inflow]")!
        let rDebit = actual.range(of: "MEASURE 'Fact_Transaction'[Total_Debit_Outflow]")!
        let rTrans = actual.range(of: "MEASURE 'Fact_Transaction'[Trans Amount]")!
        #expect(rNet.lowerBound < rCredit.lowerBound)
        #expect(rCredit.lowerBound < rDebit.lowerBound)
        #expect(rDebit.lowerBound < rTrans.lowerBound)

        let expectedSuffix = """
        EVALUATE
            SUMMARIZECOLUMNS(
                "Net_Cashflow", [Net_Cashflow]
            )
        """
        #expect(actual.hasSuffix(expectedSuffix))
    }

    // MARK: - Tests cho LeftContextMenu items và LeftMenuBuilder

    @Test func leftMenuChoBang() {
        var actionsTriggered = [String]()
        let items = LeftMenuBuilder.tableMenuItems(
            tableName: "Dim_Date",
            onTop100: { actionsTriggered.append("top100") },
            onDefineNewMeasure: { actionsTriggered.append("def_new") },
            onCollapseAll: { actionsTriggered.append("collapse") },
            onExpandAll: { actionsTriggered.append("expand") }
        )

        #expect(items.count == 7)

        guard case .submenu(let subTitle, let subItems) = items[0] else {
            Issue.record("Expected submenu")
            return
        }
        #expect(subTitle == "Truy vấn nhanh")
        #expect(subItems.count == 3)
        #expect(subItems[0].title == "Hiện 100 dòng đầu" && subItems[0].isEnabled)
        #expect(subItems[1] == .separator)
        #expect(subItems[2].title == "Định nghĩa measure mới" && subItems[2].isEnabled)

        #expect(items[1].title == "Đổi tên" && !items[1].isEnabled)
        #expect(items[2].title == "Xoá khỏi mô hình" && !items[2].isEnabled)
        #expect(items[3].title == "Ẩn trong chế độ báo cáo" && !items[3].isEnabled)
        #expect(items[4] == .separator)
        #expect(items[5].title == "Thu gọn tất cả" && items[5].isEnabled)
        #expect(items[6].title == "Mở rộng tất cả" && items[6].isEnabled)

        if case .action(_, _, let act) = subItems[0] {
            act()
            #expect(actionsTriggered.contains("top100"))
        }
        if case .action(_, _, let act) = subItems[2] {
            act()
            #expect(actionsTriggered.contains("def_new"))
        }
        if case .action(_, _, let act) = items[5] {
            act()
            #expect(actionsTriggered.contains("collapse"))
        }
        if case .action(_, _, let act) = items[6] {
            act()
            #expect(actionsTriggered.contains("expand"))
        }
    }

    @Test func leftMenuChoMeasure() {
        var actionsTriggered = [String]()
        let items = LeftMenuBuilder.measureMenuItems(
            onEvaluate: { actionsTriggered.append("eval") },
            onDefineAndEvaluate: { actionsTriggered.append("def_eval") },
            onDefineWithReferencesAndEvaluate: { actionsTriggered.append("def_ref_eval") },
            onDefineNewMeasure: { actionsTriggered.append("def_new") },
            onDefineAllMeasures: { actionsTriggered.append("def_all") },
            onCollapseAll: { actionsTriggered.append("collapse") },
            onExpandAll: { actionsTriggered.append("expand") },
            onCopyFormula: { actionsTriggered.append("copy") }
        )

        #expect(items.count == 11)

        guard case .submenu(let subTitle, let subItems) = items[0] else {
            Issue.record("Expected submenu")
            return
        }
        #expect(subTitle == "Truy vấn nhanh")
        #expect(subItems.count == 6)
        #expect(subItems[0].title == "Đánh giá" && subItems[0].isEnabled)
        #expect(subItems[1].title == "Định nghĩa và đánh giá" && subItems[1].isEnabled)
        #expect(subItems[2].title == "Định nghĩa kèm tham chiếu và đánh giá" && subItems[2].isEnabled)
        #expect(subItems[3] == .separator)
        #expect(subItems[4].title == "Định nghĩa measure mới" && subItems[4].isEnabled)
        #expect(subItems[5].title == "Định nghĩa mọi measure trong mô hình" && subItems[5].isEnabled)

        #expect(items[1].title == "Đổi tên" && !items[1].isEnabled)
        #expect(items[2].title == "Xoá khỏi mô hình" && !items[2].isEnabled)
        #expect(items[3].title == "Ẩn trong chế độ báo cáo" && !items[3].isEnabled)
        #expect(items[4] == .separator)
        #expect(items[5].title == "Hiện tất cả" && !items[5].isEnabled)
        #expect(items[6] == .separator)
        #expect(items[7].title == "Thu gọn tất cả" && items[7].isEnabled)
        #expect(items[8].title == "Mở rộng tất cả" && items[8].isEnabled)
        #expect(items[9] == .separator)
        #expect(items[10].title == "Sao chép công thức" && items[10].isEnabled)

        if case .action(_, _, let act) = items[10] {
            act()
            #expect(actionsTriggered.contains("copy"))
        }
        if case .action(_, _, let act) = subItems[4] {
            act()
            #expect(actionsTriggered.contains("def_new"))
        }
        if case .action(_, _, let act) = subItems[5] {
            act()
            #expect(actionsTriggered.contains("def_all"))
        }
    }

    @Test func leftMenuChoCot() {
        var actionsTriggered = [String]()
        let regularItems = LeftMenuBuilder.columnMenuItems(
            isCalculated: false,
            hasExpression: false,
            onPreviewData: { actionsTriggered.append("preview") },
            onCollapseAll: { actionsTriggered.append("collapse") },
            onExpandAll: { actionsTriggered.append("expand") }
        )
        #expect(regularItems.count == 7)
        guard case .submenu(let subTitle, let subItems) = regularItems[0] else {
            Issue.record("Expected submenu")
            return
        }
        #expect(subTitle == "Truy vấn nhanh")
        #expect(subItems.count == 1)
        #expect(subItems[0].title == "Xem trước dữ liệu")

        #expect(regularItems[1].title == "Đổi tên" && !regularItems[1].isEnabled)
        #expect(regularItems[2].title == "Xoá khỏi mô hình" && !regularItems[2].isEnabled)
        #expect(regularItems[3].title == "Ẩn trong chế độ báo cáo" && !regularItems[3].isEnabled)
        #expect(regularItems[4] == .separator)
        #expect(regularItems[5].title == "Thu gọn tất cả" && regularItems[5].isEnabled)
        #expect(regularItems[6].title == "Mở rộng tất cả" && regularItems[6].isEnabled)

        let calcItems = LeftMenuBuilder.columnMenuItems(
            isCalculated: true,
            hasExpression: true,
            onPreviewData: {},
            onCollapseAll: {},
            onExpandAll: {},
            onCopyFormula: { actionsTriggered.append("copy") }
        )
        #expect(calcItems.count == 9)
        #expect(calcItems[7] == .separator)
        #expect(calcItems[8].title == "Sao chép công thức" && calcItems[8].isEnabled)

        if case .action(_, _, let act) = calcItems[8] {
            act()
            #expect(actionsTriggered.contains("copy"))
        }
    }
}
