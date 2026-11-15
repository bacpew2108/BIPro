// Phase F: Test chuỗi golden Desktop 2.159 (chuoi-1.m và chuoi-2.m).
import Testing
import Foundation
import ColumnStore
@testable import MEngine

@Suite struct GoldenChainTests {
    @Test func goldenChuoi2ChayTron() async throws {
        guard let res = try await GoldenFixtures.run("chuoi-2.m") else {
            Issue.record("sales_2026.xlsx không tồn tại hoặc không nạp được")
            return
        }
        guard case .table(let t) = res else {
            Issue.record("kết quả phải là TableData")
            return
        }

        // Bảng 98 dòng, 7 cột
        #expect(t.rowCount == 98)
        #expect(t.columns.count == 7)
        let colNames = t.columns.map(\.name)
        #expect(colNames == ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Amount"])

        // Cột Region kiểu số nguyên, không ô lỗi
        guard let regionIdx = t.index(ofColumn: "Region") else {
            Issue.record("thiếu cột Region")
            return
        }
        #expect(t.columns[regionIdx].data.type == .integer)
        #expect(t.errorMask[regionIdx] == nil || t.errorMask[regionIdx]?.isEmpty == true)

        // Đối chiếu từng ô với golden TSV
        let tsvData = try GoldenFixtures.tsv("chuoi-2-98-dong.tsv")
        #expect(tsvData.header == colNames)
        #expect(tsvData.rows.count == 98)

        for r in 0..<98 {
            let expectedRow = tsvData.rows[r]
            for c in 0..<7 {
                let colName = colNames[c]
                let exp = expectedRow[c]
                let cellVal = MTables.cell(t, row: r, column: c)

                if colName == "OrderDate" {
                    // So ngày dạng yyyy-MM-dd
                    switch cellVal {
                    case .date(let d), .dateTime(let d):
                        let civil = ValueDateHelper.civilFromSerial(d)
                        let dateStr = String(format: "%04d-%02d-%02d", civil.year, civil.month, civil.day)
                        #expect(dateStr == exp, "Dòng \(r) cột OrderDate: \(dateStr) != \(exp)")
                    default:
                        Issue.record("Dòng \(r) cột OrderDate không phải date: \(cellVal)")
                    }
                } else if colName == "Product" {
                    guard case .text(let s) = cellVal else {
                        Issue.record("Dòng \(r) cột Product không phải text: \(cellVal)")
                        continue
                    }
                    #expect(s == exp, "Dòng \(r) cột Product: \(s) != \(exp)")
                } else {
                    // Các cột số: OrderID, Region, CustomerID, Qty, Amount
                    guard let n = MOperators.number(cellVal) else {
                        Issue.record("Dòng \(r) cột \(colName) không phải số: \(cellVal)")
                        continue
                    }
                    guard let expNum = Double(exp) else {
                        Issue.record("Giá trị kỳ vọng không phải số: \(exp)")
                        continue
                    }
                    #expect(abs(n - expNum) < 1e-5, "Dòng \(r) cột \(colName): \(n) != \(expNum)")
                }
            }
        }
    }

    @Test func goldenChuoi1DenUppercasedTextVaTungBuoc() async throws {
        // Kiểm các bước trung gian
        // 1. "Sorted Rows" tăng dần theo OrderDate
        guard let stepSorted = try await GoldenFixtures.run("chuoi-1.m", upTo: "Sorted Rows"),
              case .table(let tSorted) = stepSorted else {
            Issue.record("không chạy được bước Sorted Rows")
            return
        }
        guard let orderDateIdx = tSorted.index(ofColumn: "OrderDate"),
              let orderIdIdx = tSorted.index(ofColumn: "OrderID") else {
            Issue.record("thiếu cột OrderDate hoặc OrderID")
            return
        }
        func dateVal(_ v: MValue) -> Double? {
            switch v {
            case .date(let d), .dateTime(let d): d
            case .number(let d): d
            default: nil
            }
        }
        for r in 0..<(tSorted.rowCount - 1) {
            let d1 = try #require(dateVal(MTables.cell(tSorted, row: r, column: orderDateIdx)))
            let d2 = try #require(dateVal(MTables.cell(tSorted, row: r + 1, column: orderDateIdx)))
            #expect(d1 <= d2, "OrderDate không tăng dần tại dòng \(r)")
            if d1 == d2 {
                let id1 = try #require(MOperators.number(MTables.cell(tSorted, row: r, column: orderIdIdx)))
                let id2 = try #require(MOperators.number(MTables.cell(tSorted, row: r + 1, column: orderIdIdx)))
                #expect(id1 <= id2, "OrderID không ổn định khi OrderDate trùng tại dòng \(r)")
            }
        }

        // 2. "Removed Columns" không còn Price
        guard let stepRem = try await GoldenFixtures.run("chuoi-1.m", upTo: "Removed Columns"),
              case .table(let tRem) = stepRem else {
            Issue.record("không chạy được bước Removed Columns")
            return
        }
        #expect(tRem.index(ofColumn: "Price") == nil)

        // 3. "Replaced Value" không còn dòng nào có Vung chứa North
        guard let stepRep = try await GoldenFixtures.run("chuoi-1.m", upTo: "Replaced Value"),
              case .table(let tRep) = stepRep else {
            Issue.record("không chạy được bước Replaced Value")
            return
        }
        guard let vungIdx = tRep.index(ofColumn: "Vung") else {
            Issue.record("thiếu cột Vung")
            return
        }
        for r in 0..<tRep.rowCount {
            if case .text(let s) = MTables.cell(tRep, row: r, column: vungIdx) {
                #expect(!s.contains("North"), "Dòng \(r) cột Vung còn chứa North: \(s)")
            }
        }

        // 4. "Filtered Rows" 43 dòng
        guard let stepFilt = try await GoldenFixtures.run("chuoi-1.m", upTo: "Filtered Rows"),
              case .table(let tFilt) = stepFilt else {
            Issue.record("không chạy được bước Filtered Rows")
            return
        }
        #expect(tFilt.rowCount == 43)

        // 5. "Added Index" Index 0...42
        guard let stepIdx = try await GoldenFixtures.run("chuoi-1.m", upTo: "Added Index"),
              case .table(let tIdx) = stepIdx else {
            Issue.record("không chạy được bước Added Index")
            return
        }
        guard let indexColIdx = tIdx.index(ofColumn: "Index") else {
            Issue.record("thiếu cột Index")
            return
        }
        for r in 0..<43 {
            #expect(MTables.cell(tIdx, row: r, column: indexColIdx) == .number(Double(r)))
        }

        // 6. "Reversed Rows" đảo thứ tự bước trước
        guard let stepRev = try await GoldenFixtures.run("chuoi-1.m", upTo: "Reversed Rows"),
              case .table(let tRev) = stepRev else {
            Issue.record("không chạy được bước Reversed Rows")
            return
        }
        guard let revIndexIdx = tRev.index(ofColumn: "Index") else {
            Issue.record("thiếu cột Index trong Reversed Rows")
            return
        }
        #expect(MTables.cell(tRev, row: 0, column: revIndexIdx) == .number(42))
        #expect(MTables.cell(tRev, row: 42, column: revIndexIdx) == .number(0))

        // 7. "Split Column by Delimiter" có Vung.1, Vung.2
        guard let stepSplit = try await GoldenFixtures.run("chuoi-1.m", upTo: "Split Column by Delimiter"),
              case .table(let tSplit) = stepSplit else {
            Issue.record("không chạy được bước Split Column by Delimiter")
            return
        }
        #expect(tSplit.index(ofColumn: "Vung.1") != nil)
        #expect(tSplit.index(ofColumn: "Vung.2") != nil)

        // 8. Chạy đến bước "Uppercased Text"
        guard let stepUpper = try await GoldenFixtures.run("chuoi-1.m", upTo: "Uppercased Text"),
              case .table(let tUpper) = stepUpper else {
            Issue.record("không chạy được bước Uppercased Text")
            return
        }
        #expect(tUpper.rowCount == 43)

        guard tUpper.index(ofColumn: "Vung.1") != nil,
              tUpper.index(ofColumn: "Vung.2") != nil,
              let productIdx = tUpper.index(ofColumn: "Product") else {
            Issue.record("thiếu cột Vung.1, Vung.2 hoặc Product")
            return
        }

        // Đếm số dòng theo Product bằng Dictionary Swift, so khớp với chuoi-1-pivot-6-dong.tsv
        var productCounts: [String: Int] = [:]
        for r in 0..<tUpper.rowCount {
            guard case .text(let prod) = MTables.cell(tUpper, row: r, column: productIdx) else {
                Issue.record("Dòng \(r) cột Product không phải text")
                continue
            }
            productCounts[prod, default: 0] += 1
        }

        let pivotTsv = try GoldenFixtures.tsv("chuoi-1-pivot-6-dong.tsv")
        // Header: Product, Count
        #expect(pivotTsv.rows.count == 6)
        for row in pivotTsv.rows {
            let prodName = row[0]
            let expectedCount = Int(row[1]) ?? 0
            #expect(productCounts[prodName] == expectedCount, "Product \(prodName): count \(productCounts[prodName] ?? 0) != \(expectedCount)")
        }
    }

    @Test func testLoiChuyenKieuVaReplaceErrorValues() async throws {
        // Dựng bảng có cột văn bản South, North, 5
        let col = TableColumn(name: "Cột", data: ColumnBuilder.strings(["South", "North", "5"]))
        let table = try TableData(columns: [col])
        let env = MEnvironment(bindings: ["Source": .table(table)])

        // Table.TransformColumnTypes sang Int64.Type
        let m1 = """
        let
            Transformed = Table.TransformColumnTypes(Source, {{"Cột", Int64.Type}})
        in
            Transformed
        """
        guard case .table(let tTrans) = try await MEvaluator(environment: env).evaluate(source: m1) else {
            Issue.record("phải là TableData")
            return
        }
        #expect(tTrans.columns[0].data.type == .integer)
        #expect(tTrans.error(row: 0, column: 0)?.contains("DataFormat.Error") == true)
        #expect(tTrans.error(row: 0, column: 0)?.contains("We couldn't convert to Number.") == true)
        #expect(tTrans.error(row: 1, column: 0)?.contains("DataFormat.Error") == true)
        #expect(tTrans.error(row: 2, column: 0) == nil)
        #expect(tTrans.value(row: 2, column: 0) == .integer(5))

        // Table.ReplaceErrorValues(..., {{"Cột", 0}}) cho 0, 0, 5
        let env2 = MEnvironment(bindings: ["TTrans": .table(tTrans)])
        let m2 = """
        let
            Replaced = Table.ReplaceErrorValues(TTrans, {{"Cột", 0}})
        in
            Replaced
        """
        guard case .table(let tRep) = try await MEvaluator(environment: env2).evaluate(source: m2) else {
            Issue.record("phải là TableData")
            return
        }
        #expect(tRep.columns[0].data.type == .integer)
        #expect(tRep.errorMask.isEmpty)
        #expect(tRep.value(row: 0, column: 0) == .integer(0))
        #expect(tRep.value(row: 1, column: 0) == .integer(0))
        #expect(tRep.value(row: 2, column: 0) == .integer(5))
    }

    @Test func motTrieuDongHieuNang() async throws {
        guard ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1" else { return }

        // Dựng bảng 1 triệu dòng × 10 cột
        let N = 1_000_000
        let c0 = TableColumn(name: "ID", data: ColumnBuilder.integers((0..<N).map { Int64($0) }))
        let c1 = TableColumn(name: "ValInt", data: ColumnBuilder.integers((0..<N).map { Int64($0 % 1000) }))
        let c2 = TableColumn(name: "Amount", data: ColumnBuilder.doubles((0..<N).map { Double($0) * 1.5 }))
        let c3 = TableColumn(name: "Rate", data: ColumnBuilder.doubles((0..<N).map { Double($0 % 100) * 0.1 }))
        let c4 = TableColumn(name: "Date", data: ColumnBuilder.dateTimes((0..<N).map { 46000.0 + Double($0 % 365) }))
        let c5 = TableColumn(name: "Cat1", data: ColumnBuilder.strings((0..<N).map { "Cat_\($0 % 50)" }))
        let c6 = TableColumn(name: "Cat2", data: ColumnBuilder.strings((0..<N).map { "Region_\($0 % 5)" }))
        let c7 = TableColumn(name: "Code", data: ColumnBuilder.strings((0..<N).map { "CODE_\($0 % 200)" }))
        let c8 = TableColumn(name: "Status", data: ColumnBuilder.strings((0..<N).map { $0 % 2 == 0 ? "Active" : "Inactive" }))
        let c9 = TableColumn(name: "Flag", data: ColumnBuilder.booleans((0..<N).map { $0 % 2 == 0 }))

        let table = try TableData(columns: [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9])
        #expect(table.rowCount == N)
        #expect(table.columns.count == 10)

        func measure(_ name: String, block: () throws -> TableData) rethrows -> Double {
            let start = DispatchTime.now()
            let res = try block()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
            print("BENCHMARK 1M rows [\(name)]: \(String(format: "%.3f", elapsed))s, rows=\(res.rowCount)")
            #expect(elapsed < 5.0, "\(name) chạy mất \(elapsed)s (vượt quá 5s)")
            return elapsed
        }

        let firstNFn = TableColumnsLibrary.functions.first(where: { $0.name == "Table.RowCount" })!
        _ = firstNFn

        let tFirstN = TableRowsLibrary.functions.first(where: { $0.name == "Table.FirstN" })!
        let tSkip = TableRowsLibrary.functions.first(where: { $0.name == "Table.Skip" })!
        let tSort = TableRowsLibrary.functions.first(where: { $0.name == "Table.Sort" })!
        let tDistinct = TableRowsLibrary.functions.first(where: { $0.name == "Table.Distinct" })!
        let tTrans = TableColumnsLibrary.functions.first(where: { $0.name == "Table.TransformColumnTypes" })!

        _ = try measure("Table.FirstN") {
            guard case .table(let t) = try tFirstN.call([.table(table), .number(100)]) else { fatalError() }
            return t
        }

        _ = try measure("Table.Skip") {
            guard case .table(let t) = try tSkip.call([.table(table), .number(100)]) else { fatalError() }
            return t
        }

        _ = try measure("Table.Distinct") {
            guard case .table(let t) = try tDistinct.call([.table(table), .list([.text("Cat2")])]) else { fatalError() }
            return t
        }

        _ = try measure("Table.TransformColumnTypes") {
            guard case .table(let t) = try tTrans.call([.table(table), .list([.list([.text("Amount"), .type(MType(.int64))])])]) else { fatalError() }
            return t
        }

        _ = try measure("Table.Sort") {
            guard case .table(let t) = try tSort.call([.table(table), .list([.list([.text("ValInt"), .number(0)])])]) else { fatalError() }
            return t
        }
    }
}
