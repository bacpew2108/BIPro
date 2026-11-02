import Foundation
import Testing
@testable import PBIXKit
import DAXEngine
@testable import BIPro

@Suite struct DAXCompletionTests {
    private static func makeMeasure(table: String, name: String, expression: String = "") -> ModelMetadata.Measure {
        ModelMetadata.Measure(
            tableName: table,
            name: name,
            expression: expression,
            formatString: nil,
            displayFolder: nil,
            isHidden: false,
            description: nil,
            lineageTag: nil,
            dataType: .int64,
            state: 1,
            formatStringDefinition: nil
        )
    }

    private let sampleModel = CompletionModel(
        functions: ["SUM", "SUMX", "SUMMARIZE", "SUMMARIZECOLUMNS", "CALCULATE", "FILTER"],
        tables: ["Dim_Date", "Sales Details", "Customer"],
        columnsByTable: [
            "Dim_Date": ["Date", "year", "Month", "Quarter"],
            "Sales Details": ["OrderNo", "Quantity", "Amount"],
            "Customer": ["ID", "Name"]
        ],
        measuresByTable: [
            "Sales Details": [
                makeMeasure(table: "Sales Details", name: "Trans Count", expression: "COUNTROWS('Sales Details')"),
                makeMeasure(table: "Sales Details", name: "Total Amount", expression: "SUM('Sales Details'[Amount])")
            ],
            "Dim_Date": [
                makeMeasure(table: "Dim_Date", name: "Year Count", expression: "DISTINCTCOUNT('Dim_Date'[year])")
            ]
        ]
    )

    @Test func goSUMMRaSUMMARIZECOLUMNSDungDau() {
        let text = "SUMM"
        let cursor = 4
        let result = DAXCompletion.suggestions(text: text, cursor: cursor, model: sampleModel)

        #expect(result != nil)
        let first = result?.items.first
        #expect(first?.label == "SUMMARIZECOLUMNS")
        #expect(first?.insertText == "SUMMARIZECOLUMNS(")
        #expect(first?.kind == .function)
        #expect(result?.replaceRange == NSRange(location: 0, length: 4))
    }

    @Test func sauBangMoNgoacChiRaCotVaMeasureCuaBangDo() {
        let text = "'Dim_Date'[ye"
        let cursor = (text as NSString).length // 13
        let result = DAXCompletion.suggestions(text: text, cursor: cursor, model: sampleModel)

        #expect(result != nil)
        let items = result?.items ?? []
        // Chỉ ra cột và measure của Dim_Date, có "year"
        let hasYearColumn = items.contains { $0.label == "year" && $0.kind == .column && $0.insertText == "year]" }
        let hasYearMeasure = items.contains { $0.label == "Year Count" && $0.kind == .measure }
        let hasSalesColumn = items.contains { $0.label == "OrderNo" || $0.label == "Amount" }

        #expect(hasYearColumn)
        #expect(hasYearMeasure)
        #expect(!hasSalesColumn)

        // replaceRange tính từ sau [ tới con trỏ (phần "ye" có độ dài 2 từ vị trí 11)
        #expect(result?.replaceRange == NSRange(location: 11, length: 2))
    }

    @Test func ngaySauMoNgoacVuongRaMeasure() {
        let text = "[Tra"
        let cursor = (text as NSString).length // 4
        let result = DAXCompletion.suggestions(text: text, cursor: cursor, model: sampleModel)

        #expect(result != nil)
        let items = result?.items ?? []
        let transCountItem = items.first { $0.label == "Trans Count" }

        #expect(transCountItem != nil)
        #expect(transCountItem?.kind == .measure)
        #expect(transCountItem?.insertText == "Trans Count]")
        #expect(result?.replaceRange == NSRange(location: 1, length: 3))
    }

    @Test func trongChuoiHoacCommentTraVeNil() {
        // Trong chuỗi ""
        let stringText = "EVALUATE \"SUMM\""
        let cursorInString = 12 // giữa 'U' và 'M'
        #expect(DAXCompletion.suggestions(text: stringText, cursor: cursorInString, model: sampleModel) == nil)

        // Trong comment //
        let lineComment1 = "// SUMM"
        let cursorInComment1 = 5
        #expect(DAXCompletion.suggestions(text: lineComment1, cursor: cursorInComment1, model: sampleModel) == nil)

        // Trong comment --
        let lineComment2 = "-- SUMM"
        let cursorInComment2 = 5
        #expect(DAXCompletion.suggestions(text: lineComment2, cursor: cursorInComment2, model: sampleModel) == nil)
    }

    @Test func daCoNgoacDongSauConTroKhongChenThemNgoacDong() {
        // 'Dim_Date'[ye] với con trỏ nằm trước ]
        let text = "'Dim_Date'[ye]"
        let cursor = (text as NSString).range(of: "]").location // 13
        let result = DAXCompletion.suggestions(text: text, cursor: cursor, model: sampleModel)

        #expect(result != nil)
        let yearItem = result?.items.first { $0.label == "year" }
        #expect(yearItem != nil)
        // insertText không có "]"
        #expect(yearItem?.insertText == "year")

        // Tương tự cho [Tra]
        let bracketText = "[Tra]"
        let bracketCursor = (bracketText as NSString).range(of: "]").location // 4
        let bracketResult = DAXCompletion.suggestions(text: bracketText, cursor: bracketCursor, model: sampleModel)
        let transItem = bracketResult?.items.first { $0.label == "Trans Count" }
        #expect(transItem != nil)
        #expect(transItem?.insertText == "Trans Count")
    }

    @Test func bangCoDauCachDuocBocNhay() {
        let textSales = "Sales"
        let resultSales = DAXCompletion.suggestions(text: textSales, cursor: 5, model: sampleModel)

        #expect(resultSales != nil)
        // Bảng có dấu cách "Sales Details" phải được bọc '...'
        let salesTableItem = resultSales?.items.first { $0.label == "Sales Details" }
        #expect(salesTableItem != nil)
        #expect(salesTableItem?.insertText == "'Sales Details'")

        // Bảng không có dấu cách "Dim_Date" giữ nguyên
        let textDim = "Dim"
        let resultDim = DAXCompletion.suggestions(text: textDim, cursor: 3, model: sampleModel)
        #expect(resultDim != nil)
        let dateTableItem = resultDim?.items.first { $0.label == "Dim_Date" }
        #expect(dateTableItem != nil)
        #expect(dateTableItem?.insertText == "Dim_Date")
    }
}

@Suite struct DAXCompletionRegistryTests {
    /// Danh sách hàm thật mà app dùng (registry + dạng truy vấn) phải có SUMMARIZECOLUMNS và ROW.
    @Test func danhSachHamThatCoSummarizeColumns() {
        let functions = Array(Set(FunctionRegistry.all.map(\.name) + DAXCompletion.queryForms)).sorted()
        let model = CompletionModel(functions: functions, tables: [], columnsByTable: [:], measuresByTable: [:])
        let result = DAXCompletion.suggestions(text: "EVALUATE\nSUMM", cursor: 13, model: model)
        #expect(result?.items.first?.label == "SUMMARIZECOLUMNS")
        #expect(result?.items.first?.detail == "Hàm")
    }
}
