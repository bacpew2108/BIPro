// E2 (Phase C, lead): measure ẩn `_<M> FormatString` sinh từ định dạng động của measure M.
// Power BI đưa nó vào truy vấn visual: `"v_X_FormatString", IGNORE('T'[_X FormatString])` (PA-D2-2, C1.md §2.1).
import DAXEngine
import DAXTestSupport
import Testing

@Suite struct FormatStringMeasureTests {
    private func engine() -> DAXEngine {
        let catalog = Catalog(schema: MiniBank.schema, measures: [
            ModelMeasureInput(table: "Fact_Trans", name: "Ratio", expression: "0.25", formatString: "0%",
                              formatStringDefinition: "IF([Ratio] < 0.5, \"0.0%\", \"0%\")"),
            ModelMeasureInput(table: "Fact_Trans", name: "Plain", expression: "1", formatString: "#,0"),
        ])
        return DAXEngine(store: MiniBank.makeStore(), catalog: catalog)
    }

    @Test func measureAnDuocSinhCungBang() async throws {
        let result = try await engine().execute(
            "EVALUATE ROW(\"f\", 'Fact_Trans'[_Ratio FormatString], \"v\", [Ratio])")
        // [Ratio] = 0.25 < 0.5 nên định dạng động là "0.0%".
        #expect(result.tables[0].rows == [[.string("0.0%"), .double(0.25)]])
    }

    @Test func dungTrongSummarizeColumnsVoiIgnore() async throws {
        let result = try await engine().execute("""
            EVALUATE SUMMARIZECOLUMNS("Ratio", [Ratio], "v_Ratio_FormatString", IGNORE('Fact_Trans'[_Ratio FormatString]))
            """)
        #expect(result.tables[0].columns == ["[Ratio]", "[v_Ratio_FormatString]"])
        #expect(result.tables[0].rows == [[.double(0.25), .string("0.0%")]])
    }

    @Test func measureKhongCoDinhDangDongThiKhongCoMeasureAn() {
        let issues = engine().validate("EVALUATE ROW(\"f\", 'Fact_Trans'[_Plain FormatString])")
        #expect(!issues.isEmpty)
    }

    @Test func tenMeasureAn() {
        #expect(ModelMeasureInput.formatStringMeasureName("Bad_Debt_Ratio_Count") == "_Bad_Debt_Ratio_Count FormatString")
    }
}

@Suite struct FormatStringSelectedMeasureTests {
    @Test func selectedMeasureLaChinhMeasure() async throws {
        let catalog = Catalog(schema: MiniBank.schema, measures: [
            ModelMeasureInput(table: "Fact_Trans", name: "Ratio", expression: "0.75", formatString: "0%",
                              formatStringDefinition: "IF(SELECTEDMEASURE() < 0.5, \"0.0%\", \"0%\")"),
        ])
        let engine = DAXEngine(store: MiniBank.makeStore(), catalog: catalog)
        let result = try await engine.execute("EVALUATE ROW(\"f\", 'Fact_Trans'[_Ratio FormatString])")
        // SELECTEDMEASURE() = [Ratio] = 0.75 ≥ 0.5 nên "0%".
        #expect(result.tables[0].rows == [[.string("0%")]])
    }
}
