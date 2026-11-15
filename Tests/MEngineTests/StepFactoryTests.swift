// Phase F, T055: MQuery (tách/dựng let … in) và StepFactory (lệnh Ribbon → bước M). Kỳ vọng là M nguyên văn Desktop 2.159
// ở `docs/phase-f-evidence/vm-f3/QUAN-SAT.md` mục 1 và `golden/chuoi-1.m`, `chuoi-2.m` (VM-F3).
import Testing
import ColumnStore
@testable import MEngine

@Suite struct MQueryTests {
    @Test func tachChuoi1ThanhMuoiChinBuoc() throws {
        let q = try MQuery.parse(GoldenFixtures.golden("chuoi-1.m"))
        #expect(q.steps.count == 19)
        #expect(q.steps.map(\.name).prefix(4) == ["Source", "Sales_Sheet", "Promoted Headers", "Changed Type"])
        #expect(q.steps[1].expression == #"Source{[Item="Sales",Kind="Sheet"]}[Data]"#)
        #expect(q.steps[4].expression == #"Table.Sort(#"Changed Type",{{"OrderDate", Order.Ascending}})"#)
        #expect(q.steps.last?.name == "Pivoted Column")
        #expect(q.resultName == "Pivoted Column")
    }

    @Test func dungLaiVaTachLaiRaCungCacBuoc() throws {
        for file in ["chuoi-1.m", "chuoi-2.m"] {
            let q = try MQuery.parse(GoldenFixtures.golden(file))
            let again = try MQuery.parse(q.source)
            #expect(again == q)
            _ = try MParser.parse(q.source)
        }
    }

    @Test func dungLaiDungDangDesktop() {
        let q = MQuery(steps: [MStep(name: "Source", expression: "#table({\"A\"}, {{1}})"),
                               MStep(name: "Changed Type", expression: "Table.Skip(Source,0)")], resultName: "Changed Type")
        #expect(q.source == "let\n    Source = #table({\"A\"}, {{1}}),\n    #\"Changed Type\" = Table.Skip(Source,0)\nin\n    #\"Changed Type\"")
    }

    @Test func letLongNhauVaChuoiCoDauPhayKhongBiCat() throws {
        let q = try MQuery.parse("let\n  A = {1, 2, 3},\n  B = let x = 1, y = 2 in x + y,\n  C = \"a, in, b\"\nin\n  B")
        #expect(q.steps.map(\.name) == ["A", "B", "C"])
        #expect(q.steps[1].expression == "let x = 1, y = 2 in x + y")
        #expect(q.steps[2].expression == "\"a, in, b\"")
        #expect(q.resultName == "B")
    }

    @Test func biThuongKhongPhaiLetThanhMotBuocSource() throws {
        let q = try MQuery.parse("#table({\"A\"}, {{1}})")
        #expect(q.steps == [MStep(name: "Source", expression: "#table({\"A\"}, {{1}})")])
        #expect(q.resultName == "Source")
    }

    @Test func loiCuPhapKemViTri() {
        #expect(throws: MSyntaxError.self) { try MQuery.parse("let A = 1, B =  in B") }
        #expect(throws: MSyntaxError.self) { try MQuery.parse("let A = 1") }
    }

    @Test func chenBuocGiuaNoiLaiBuocKeTiep() throws {
        // QUAN-SAT mục 2: bước chèn nằm ngay sau bước đang chọn; bước kế tiếp đổi tham chiếu sang bước mới.
        var q = try MQuery.parse("let\n  Source = 1,\n  #\"Removed Columns\" = Table.RemoveColumns(Source,{\"Price\"}),\n  #\"Removed Top Rows\" = Table.Skip(#\"Removed Columns\",2)\nin\n  #\"Removed Top Rows\"")
        let inserted = StepFactory.steps(for: .keepTopRows(100), after: "Source", existingNames: Set(q.steps.map(\.name)))
        q.insert(inserted, afterStepAt: 0)
        #expect(q.steps.map(\.name) == ["Source", "Kept First Rows", "Removed Columns", "Removed Top Rows"])
        #expect(q.steps[1].expression == "Table.FirstN(Source,100)")
        // Bước kế tiếp trỏ vào bước mới (như Desktop: bước sau đổi tham chiếu sang bước vừa chèn).
        #expect(q.steps[2].expression == #"Table.RemoveColumns(#"Kept First Rows",{"Price"})"#)
        // Bước xa hơn không phụ thuộc Source nên giữ nguyên.
        #expect(q.steps[3].expression == #"Table.Skip(#"Removed Columns",2)"#)
        #expect(q.resultName == "Removed Top Rows")
    }

    @Test func chenSauBuocCuoiDoiKetQua() throws {
        var q = try MQuery.parse("let Source = 1 in Source")
        q.insert(StepFactory.steps(for: .reverseRows, after: "Source", existingNames: ["Source"]), afterStepAt: 0)
        #expect(q.steps.map(\.name) == ["Source", "Reversed Rows"])
        #expect(q.resultName == "Reversed Rows")
    }

    @Test func xoaBuocNoiBuocSauVeBuocTruoc() throws {
        // [SUY ĐOÁN] Desktop khi xoá bước giữa: bước phụ thuộc trỏ về bước đứng trước bước bị xoá.
        var q = try MQuery.parse("let\n  Source = 1,\n  A = f(Source),\n  B = g(A)\nin\n  B")
        q.removeStep(at: 1)
        #expect(q.steps.map(\.name) == ["Source", "B"])
        #expect(q.steps[1].expression == "g(Source)")
        q.removeStep(at: 1)
        #expect(q.resultName == "Source")
    }

    @Test func doiTenBuocSuaThamChieuSau() throws {
        var q = try MQuery.parse("let\n  Source = 1,\n  A = f(Source),\n  B = g(A, [A = 2])\nin\n  B")
        q.renameStep(at: 1, to: "Bước mới")
        #expect(q.steps[1].name == "Bước mới")
        #expect(q.steps[2].expression == #"g(#"Bước mới", [A = 2])"#)   // tên trường [A = 2] không đổi
        q.renameStep(at: 2, to: "Z")
        #expect(q.resultName == "Z")
    }

    @Test func tenKhongPhaiDinhDanhThiBocNgoac() {
        #expect(MQuery.reference(to: "Source") == "Source")
        #expect(MQuery.reference(to: "Sales_Sheet") == "Sales_Sheet")
        #expect(MQuery.reference(to: "Changed Type") == "#\"Changed Type\"")
        #expect(MQuery.reference(to: "Đổi \"kiểu\"") == "#\"Đổi \"\"kiểu\"\"\"")
        #expect(MQuery.reference(to: "let") == "#\"let\"")
        #expect(MQuery.reference(to: "1st") == "#\"1st\"")
    }
}

@Suite struct StepFactoryTests {
    private func one(_ command: StepCommand, after previous: String, existing: Set<String> = []) -> MStep {
        let steps = StepFactory.steps(for: command, after: previous, existingNames: existing)
        #expect(steps.count == 1)
        return steps[0]
    }

    private func expect(_ command: StepCommand, after previous: String, name: String, _ expression: String, existing: Set<String> = [],
                        sourceLocation: SourceLocation = #_sourceLocation) {
        let step = one(command, after: previous, existing: existing)
        #expect(step.name == name, sourceLocation: sourceLocation)
        #expect(step.expression == expression, sourceLocation: sourceLocation)
    }

    @Test func lenhRibbonKhopMNguyenVanDesktop() {
        expect(.sortRows([SortKey(column: "OrderDate", descending: false)]), after: "Changed Type",
               name: "Sorted Rows", #"Table.Sort(#"Changed Type",{{"OrderDate", Order.Ascending}})"#)
        expect(.sortRows([SortKey(column: "Qty", descending: true), SortKey(column: "OrderDate", descending: false)]), after: "Source",
               name: "Sorted Rows", #"Table.Sort(Source,{{"Qty", Order.Descending}, {"OrderDate", Order.Ascending}})"#)
        expect(.removeColumns(["Price"]), after: "Sorted Rows", name: "Removed Columns", #"Table.RemoveColumns(#"Sorted Rows",{"Price"})"#)
        expect(.renameColumns([ColumnRename(old: "Region", new: "Vung")]), after: "Removed Columns",
               name: "Renamed Columns", #"Table.RenameColumns(#"Removed Columns",{{"Region", "Vung"}})"#)
        expect(.replaceValue(old: .text("North"), new: .text("Bac"), columns: ["Vung"]), after: "Renamed Columns",
               name: "Replaced Value", #"Table.ReplaceValue(#"Renamed Columns","North","Bac",Replacer.ReplaceText,{"Vung"})"#)
        expect(.filterEquals(column: "Qty", values: [.number(1), .number(2)]), after: "Replaced Value",
               name: "Filtered Rows", #"Table.SelectRows(#"Replaced Value", each ([Qty] = 1 or [Qty] = 2))"#)
        expect(.addIndexColumn(start: 0, step: 1), after: "Filtered Rows",
               name: "Added Index", #"Table.AddIndexColumn(#"Filtered Rows", "Index", 0, 1, Int64.Type)"#)
        expect(.addCustomColumn(name: "Custom", formula: "[Qty] * 2"), after: "Added Index",
               name: "Added Custom", #"Table.AddColumn(#"Added Index", "Custom", each [Qty] * 2)"#)
        expect(.reverseRows, after: "Added Custom", name: "Reversed Rows", #"Table.ReverseRows(#"Added Custom")"#)
        expect(.fillDown(["Vung"]), after: "Reversed Rows", name: "Filled Down", #"Table.FillDown(#"Reversed Rows",{"Vung"})"#)
        expect(.format(.uppercase, columns: ["Product"]), after: "Changed Type1",
               name: "Uppercased Text", #"Table.TransformColumns(#"Changed Type1",{{"Product", Text.Upper, type text}})"#)
        expect(.groupByCount(keys: ["Product"], newColumn: "Count"), after: "Uppercased Text",
               name: "Grouped Rows", #"Table.Group(#"Uppercased Text", {"Product"}, {{"Count", each Table.RowCount(_), Int64.Type}})"#)
        expect(.unpivotOtherColumns(keep: ["Product"]), after: "Grouped Rows",
               name: "Unpivoted Other Columns", #"Table.UnpivotOtherColumns(#"Grouped Rows", {"Product"}, "Attribute", "Value")"#)
        expect(.pivot(attributeColumn: "Attribute", valueColumn: "Value"), after: "Unpivoted Other Columns",
               name: "Pivoted Column",
               #"Table.Pivot(#"Unpivoted Other Columns", List.Distinct(#"Unpivoted Other Columns"[Attribute]), "Attribute", "Value", List.Sum)"#)
        expect(.removeDuplicates(["Vung"]), after: "Replaced Value", name: "Removed Duplicates", #"Table.Distinct(#"Replaced Value", {"Vung"})"#)
        expect(.keepTopRows(100), after: "Changed Type", name: "Kept First Rows", #"Table.FirstN(#"Changed Type",100)"#)
        expect(.removeTopRows(2), after: "Removed Columns", name: "Removed Top Rows", #"Table.Skip(#"Removed Columns",2)"#)
        expect(.replaceErrors([ErrorReplacement(column: "Region", value: .number(0))]), after: "Changed Type1",
               name: "Replaced Errors", #"Table.ReplaceErrorValues(#"Changed Type1", {{"Region", 0}})"#)
        expect(.promoteHeaders, after: "Sales_Sheet",
               name: "Promoted Headers", #"Table.PromoteHeaders(Sales_Sheet, [PromoteAllScalars=true])"#)
    }

    @Test func doiKieuGhiKieuDesktop() {
        expect(.changeType([ColumnTypeChange(column: "OrderID", type: .wholeNumber), ColumnTypeChange(column: "OrderDate", type: .date),
                            ColumnTypeChange(column: "Region", type: .text), ColumnTypeChange(column: "Price", type: .decimal)]),
               after: "Promoted Headers", name: "Changed Type",
               #"Table.TransformColumnTypes(#"Promoted Headers",{{"OrderID", Int64.Type}, {"OrderDate", type date}, {"Region", type text}, {"Price", type number}})"#)
    }

    @Test func tenBuocTrungThemSo() {
        expect(.changeType([ColumnTypeChange(column: "Region", type: .wholeNumber)]), after: "Removed Top Rows",
               name: "Changed Type1", #"Table.TransformColumnTypes(#"Removed Top Rows",{{"Region", Int64.Type}})"#,
               existing: ["Source", "Changed Type"])
        expect(.keepTopRows(5), after: "Source", name: "Kept First Rows2", "Table.FirstN(Source,5)",
               existing: ["Kept First Rows", "Kept First Rows1"])
    }

    @Test func tachCotTheoDauPhanCachSinhHaiBuoc() {
        let steps = StepFactory.steps(for: .splitByDelimiter(column: "Vung", delimiter: " ", into: ["Vung.1", "Vung.2"]),
                                      after: "Filled Down", existingNames: ["Changed Type", "Changed Type1"])
        #expect(steps.map(\.name) == ["Split Column by Delimiter", "Changed Type2"])
        #expect(steps[0].expression == #"Table.SplitColumn(#"Filled Down", "Vung", Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv), {"Vung.1", "Vung.2"})"#)
        #expect(steps[1].expression == #"Table.TransformColumnTypes(#"Split Column by Delimiter",{{"Vung.1", type text}, {"Vung.2", type text}})"#)
    }

    @Test func kyTuDacBietTrongTenVaGiaTriDuocThoat() {
        let step = one(.renameColumns([ColumnRename(old: "a\"b", new: "c d")]), after: "Source")
        #expect(step.expression == #"Table.RenameColumns(Source,{{"a""b", "c d"}})"#)
        #expect(one(.replaceValue(old: .null, new: .logical(true), columns: ["X"]), after: "Source").expression
                == #"Table.ReplaceValue(Source,null,true,Replacer.ReplaceValue,{"X"})"#)
        #expect(one(.filterEquals(column: "Tên", values: [.text("a")]), after: "Source").expression == #"Table.SelectRows(Source, each ([Tên] = "a"))"#)
        #expect(one(.filterEquals(column: "Order Date", values: [.number(1.5)]), after: "Source").expression
                == #"Table.SelectRows(Source, each ([Order Date] = 1.5))"#)
    }

    @Test func tatCaBuocSinhRaPhanTichDuoc() throws {
        let commands: [StepCommand] = [
            .promoteHeaders, .changeType([ColumnTypeChange(column: "A", type: .wholeNumber)]), .sortRows([SortKey(column: "A", descending: true)]),
            .removeColumns(["B"]), .renameColumns([ColumnRename(old: "A", new: "X Y")]), .reverseRows, .fillDown(["X Y"]), .fillUp(["X Y"]),
            .keepTopRows(3), .removeTopRows(1), .removeDuplicates(["X Y"]), .addIndexColumn(start: 1, step: 1),
            .addCustomColumn(name: "C", formula: "[Index] * 2"), .format(.trim, columns: ["X Y"]),
            .groupByCount(keys: ["X Y"], newColumn: "N"), .unpivotOtherColumns(keep: ["X Y"]), .pivot(attributeColumn: "Attribute", valueColumn: "Value"),
        ]
        var q = MQuery(steps: [MStep(name: "Source", expression: "1")], resultName: "Source")
        for command in commands {
            let names = Set(q.steps.map(\.name))
            q.insert(StepFactory.steps(for: command, after: q.resultName, existingNames: names), afterStepAt: q.steps.count - 1)
        }
        #expect(q.steps.count == commands.count + 1)
        _ = try MParser.parse(q.source)
        #expect(Set(q.steps.map(\.name)).count == q.steps.count)
    }

    @Test func chuoiLenhGiongGoldenTungBuoc() throws {
        // Dựng lại chuỗi 2 của Desktop bằng lệnh Ribbon: mỗi bước sinh ra phải trùng nguyên văn golden.
        let golden = try MQuery.parse(GoldenFixtures.golden("chuoi-2.m"))
        let commands: [StepCommand] = [
            .keepTopRows(100), .removeColumns(["Price"]), .removeTopRows(2),
            .changeType([ColumnTypeChange(column: "Region", type: .wholeNumber)]), .replaceErrors([ErrorReplacement(column: "Region", value: .number(0))]),
        ]
        var q = MQuery(steps: Array(golden.steps.prefix(4)), resultName: golden.steps[3].name)   // đến "Changed Type"
        for command in commands {
            q.insert(StepFactory.steps(for: command, after: q.resultName, existingNames: Set(q.steps.map(\.name))), afterStepAt: q.steps.count - 1)
        }
        #expect(q.steps.map(\.name) == golden.steps.map(\.name))
        #expect(q.steps.map(\.expression) == golden.steps.map(\.expression))
    }

    @Test func truyVanDungTuLenhChayRaCungBangGolden() async throws {
        guard let promoted = try await GoldenFixtures.salesPromoted(), let expected = try await GoldenFixtures.run("chuoi-2.m") else { return }
        let types = ["OrderID": MColumnType.wholeNumber, "OrderDate": .date, "Region": .text, "CustomerID": .wholeNumber,
                     "Product": .text, "Qty": .wholeNumber, "Price": .decimal, "Amount": .decimal]
        let commands: [StepCommand] = [
            .changeType(promoted.columns.map { ColumnTypeChange(column: $0.name, type: types[$0.name]!) }),
            .keepTopRows(100), .removeColumns(["Price"]), .removeTopRows(2),
            .changeType([ColumnTypeChange(column: "Region", type: .wholeNumber)]), .replaceErrors([ErrorReplacement(column: "Region", value: .number(0))]),
        ]
        var q = MQuery(steps: [MStep(name: "Promoted Headers", expression: "Promoted")], resultName: "Promoted Headers")
        for command in commands {
            q.insert(StepFactory.steps(for: command, after: q.resultName, existingNames: Set(q.steps.map(\.name))), afterStepAt: q.steps.count - 1)
        }
        let env = MEnvironment(bindings: ["Promoted": .table(promoted)])
        let result = try await MEvaluator(environment: env).evaluate(source: q.source)
        #expect(result == expected)
    }
}
