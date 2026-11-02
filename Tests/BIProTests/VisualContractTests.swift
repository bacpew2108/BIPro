// Kiểm hợp đồng Phase C (đợt 0): dữ liệu mẫu đúng hình dạng, VisualFormat đọc đúng JSON thật của Nhom6, NumberDisplay.
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct VisualContractTests {

    // MARK: Dữ liệu mẫu

    @Test func mauCategoricalDungHinhDang() {
        for (name, view) in DataViewSamples.all {
            guard case .categorical(let d) = view else { continue }
            #expect(d.values.count == d.measures.count, "\(name)")
            for m in d.values.indices {
                #expect(d.values[m].count == d.seriesCount || d.values[m].count == 1, "\(name) measure \(m)")
                for s in d.values[m] { #expect(s.count == d.categories.count, "\(name) measure \(m)") }
            }
            for c in d.categories { #expect(c.values.count == d.categoryLevels.count, "\(name)") }
        }
    }

    @Test func mauMatrixDungHinhDang() throws {
        guard case .matrix(let m) = DataViewSamples.matrixAgeByRegion else { Issue.record("không phải matrix"); return }
        #expect(m.cells.count == m.rows.count)
        for row in m.cells {
            #expect(row.count == m.columnCount)
            for cell in row { #expect(cell.count == m.measures.count) }
        }
        #expect(m.rows.last?.isGrandTotal == true)
        #expect(m.columns.last?.isGrandTotal == true)
    }

    @Test func cellNgoaiPhamViTraBlank() {
        guard case .categorical(let d) = DataViewSamples.comboLoansByYear else { return }
        #expect(d.cell(measure: 9, series: 0, category: 0) == .blank)
        #expect(d.cell(measure: 0, series: 0, category: 0).value == .double(2_619_276))
        #expect(d.measureIndices(role: "Y2") == [1])
    }

    // MARK: VisualFormat với JSON thật (trích từ visual.json của Nhom6)

    private func objects(_ json: String) throws -> ObjectProperties {
        ObjectProperties(try JSONValue.parse(json))
    }

    @Test func cardMauChuLayTuMeasure() throws {
        let o = try objects(#"""
        {"labels": [{"properties": {"fontSize": {"expr": {"Literal": {"Value": "9D"}}}, "color": {"solid": {"color": {"expr": {"Measure": {"Expression": {"SourceRef": {"Entity": "Fact_Transaction"}}, "Property": "Total_Debit_Outflow Δ Color"}}}}}}}], "categoryLabels": [{"properties": {"show": {"expr": {"Literal": {"Value": "false"}}}}}]}
        """#)
        let f = VisualFormat(objects: o)
        #expect(f.dataLabels.fontSize == 9)
        #expect(f.dataLabels.color == nil)
        #expect(f.categoryLabels.show == false)
        #expect(f.measureDriven == [MeasureDrivenProperty(object: "labels", property: "color", target: nil,
                                                          sourceTable: "Fact_Transaction", sourceMeasure: "Total_Debit_Outflow Δ Color")])
    }

    @Test func matrixGradientVaIconTuMeasure() throws {
        let o = try objects(#"""
        {"values": [{"properties": {"backColor": {"solid": {"color": {"expr": {"FillRule": {"Input": {"Measure": {"Expression": {"SourceRef": {"Entity": "Fact_Transaction"}}, "Property": "Trans Count (k)"}}, "FillRule": {"linearGradient3": {"min": {"color": {"Literal": {"Value": "'#FFF5F0'"}}}, "mid": {"color": {"Literal": {"Value": "'#FC9272'"}}}, "max": {"color": {"Literal": {"Value": "'#CB181D'"}}}, "nullColoringStrategy": {"strategy": {"Literal": {"Value": "'asZero'"}}}}}}}}}}, "fontColor": {"solid": {"color": {"expr": {"Measure": {"Expression": {"SourceRef": {"Entity": "Fact_Transaction"}}, "Property": "Peak Hour Font Color"}}}}}, "icon": {"kind": "Icon", "layout": {"expr": {"Literal": {"Value": "'Before'"}}}, "verticalAlignment": {"expr": {"Literal": {"Value": "'Middle'"}}}, "value": {"expr": {"Measure": {"Expression": {"SourceRef": {"Entity": "Fact_Transaction"}}, "Property": "Peak Hour Top10 Icon"}}}}}, "selector": {"data": [{"dataViewWildcard": {"matchingOption": 1}}], "metadata": "Fact_Transaction.Trans Count (k)"}}, {"properties": {"fontSize": {"expr": {"Literal": {"Value": "12D"}}}}}],
         "subTotals": [{"properties": {"rowSubtotals": {"expr": {"Literal": {"Value": "true"}}}}}],
         "columnWidth": [{"properties": {"value": {"expr": {"Literal": {"Value": "64D"}}}}, "selector": {"metadata": "Fact_Transaction.trans_hour"}}]}
        """#)
        let f = VisualFormat(objects: o)
        #expect(f.gradients.count == 1)
        #expect(f.gradients.first?.inputMeasure == "Trans Count (k)")
        #expect(f.gradients.first?.midColor == .string("#FC9272"))
        #expect(f.gradients.first?.nullStrategy == "asZero")
        #expect(f.measureDriven.map(\.property).sorted() == ["fontColor", "icon"])
        #expect(f.measureDriven.allSatisfy { $0.target == "Fact_Transaction.Trans Count (k)" })
        #expect(f.matrix.valuesFontSize == 12)
        #expect(f.matrix.rowSubtotals == true)
        #expect(f.matrix.columnWidths["Fact_Transaction.trans_hour"] == 64)
    }

    @Test func dataPointTheoGiaTriVaTheoMeasure() throws {
        let o = try objects(#"""
        {"dataPoint": [
          {"properties": {"fill": {"solid": {"color": {"expr": {"Literal": {"Value": "'#81B29A'"}}}}}}, "selector": {"data": [{"scopeId": {"Comparison": {"ComparisonKind": 0, "Left": {"Column": {"Expression": {"SourceRef": {"Entity": "Dim_Loan_Profile"}}, "Property": "status_vn"}}, "Right": {"Literal": {"Value": "'Đã tất toán'"}}}}}]}},
          {"properties": {"fill": {"solid": {"color": {"expr": {"Literal": {"Value": "'#3D405B'"}}}}}}, "selector": {"metadata": "Fact_Transaction.Net_Cashflow"}},
          {"properties": {"fill": {"solid": {"color": {"expr": {"Measure": {"Expression": {"SourceRef": {"Entity": "Fact_Loan"}}, "Property": "NPL Group Color"}}}}}}, "selector": {"data": [{"dataViewWildcard": {"matchingOption": 1}}], "metadata": "Fact_Loan.Bad_Debt_Ratio_Count"}}]}
        """#)
        let f = VisualFormat(objects: o)
        #expect(f.dataPoint.fillByValue[ScopedValue(column: "Dim_Loan_Profile.status_vn", value: .string("Đã tất toán"))] == .string("#81B29A"))
        #expect(f.dataPoint.fillByMeasure["Fact_Transaction.Net_Cashflow"] == .string("#3D405B"))
        #expect(f.dataPoint.defaultFill == nil)
        #expect(f.measureDriven.first?.sourceMeasure == "NPL Group Color")
        #expect(f.measureDriven.first?.target == "Fact_Loan.Bad_Debt_Ratio_Count")
    }

    @Test func forecastTrendVaShapeMap() throws {
        let o = try objects(#"""
        {"forecast": [{"properties": {"show": {"expr": {"Literal": {"Value": "true"}}}, "displayName": {"expr": {"Literal": {"Value": "'Dự báo 6 tháng'"}}}, "transform": {"algorithm": "Forecast", "parameters": [{"Literal": {"Value": "7L"}, "Name": "Unit"}, {"Literal": {"Value": "6L"}, "Name": "ForecastLength"}, {"Literal": {"Value": "0L"}, "Name": "IgnoreLast"}, {"Literal": {"Value": "0.95D"}, "Name": "ConfidenceLevel"}]}}, "selector": {"id": "1", "metadata": "Fact_Transaction.Trans Amount"}}],
         "trend": [{"properties": {"show": {"expr": {"Literal": {"Value": "true"}}}}}],
         "categoryAxis": [{"properties": {"axisType": {"expr": {"Literal": {"Value": "'Scalar'"}}}}}],
         "shape": [{"properties": {"map": {"geoJson": {"type": {"expr": {"Literal": {"Value": "'shared'"}}}, "name": {"expr": {"Literal": {"Value": "'usa.states.topo'"}}}}}, "projectionEnum": {"expr": {"Literal": {"Value": "'albersUsa'"}}}}}],
         "defaultColors": [{"properties": {"defaultShow": {"expr": {"Literal": {"Value": "true"}}}, "defaultColor": {"solid": {"color": {"expr": {"Literal": {"Value": "'#E0E0E0'"}}}}}}}]}
        """#)
        let f = VisualFormat(objects: o)
        #expect(f.analytics.trendShow == true)
        #expect(f.analytics.forecastDisplayName == "Dự báo 6 tháng")
        #expect(f.analytics.forecastParameters["ForecastLength"] == 6)
        #expect(f.analytics.forecastParameters["ConfidenceLevel"] == 0.95)
        #expect(f.categoryAxis.axisType == "Scalar")
        #expect(f.shapeMap.mapResource == "usa.states.topo")
        #expect(f.shapeMap.projection == "albersUsa")
        #expect(f.shapeMap.defaultColor == .string("#E0E0E0"))
    }

    @Test func donViHienThiVaSecondaryAxis() throws {
        let o = try objects(#"""
        {"valueAxis": [{"properties": {"labelDisplayUnits": {"expr": {"Literal": {"Value": "1000000D"}}}, "labelPrecision": {"expr": {"Literal": {"Value": "1L"}}}, "secLabelDisplayUnits": {"expr": {"Literal": {"Value": "1D"}}}, "secStart": {"expr": {"Literal": {"Value": "0D"}}}}}],
         "donutChart": [], "value": [{"properties": {"labelDisplayUnits": {"expr": {"Literal": {"Value": "1000D"}}}}}]}
        """#)
        let f = VisualFormat(objects: o)
        #expect(f.valueAxis.displayUnits == .millions)
        #expect(f.valueAxis.precision == 1)
        #expect(f.valueAxis.secondaryDisplayUnits == DisplayUnits.none)
        #expect(f.valueAxis.secondaryStart == 0)
        #expect(f.dataLabels.displayUnits == .thousands)
    }

    // MARK: NumberDisplay

    @Test func donViTuDong() {
        #expect(NumberDisplay.text(DataCell(.double(3_227_472_424.5))) == "3.23bn")
        #expect(NumberDisplay.text(DataCell(.integer(1_056_320))) == "1.06M")
        #expect(NumberDisplay.text(DataCell(.double(43_811.6572))) == "43.81K")
        #expect(NumberDisplay.text(DataCell(.integer(20))) == "20")
        #expect(NumberDisplay.text(DataCell(.integer(20_000))) == "20K")
    }

    @Test func giuKyHieuTienTeVaPhanTram() {
        #expect(NumberDisplay.text(DataCell(.double(3_227_472_424.5), formatString: "\\$#,0")) == "$3.23bn")
        #expect(NumberDisplay.text(DataCell(.double(0.1363636), formatString: "0%")) == "14%")
        #expect(NumberDisplay.text(DataCell(.double(2_619_276), formatString: "\\$#,0"), units: DisplayUnits.none) == "$2,619,276")
    }

    @Test func donViCoDinhVaDoChinhXac() {
        #expect(NumberDisplay.text(DataCell(.double(2_619_276)), units: .millions, precision: 1) == "2.6M")
        // Trục: chọn đơn vị theo giá trị lớn nhất của visual.
        #expect(NumberDisplay.text(DataCell(.double(500_000)), reference: 30_731_364) == "0.5M")
        #expect(NumberDisplay.text(.blank) == "")
    }
}
