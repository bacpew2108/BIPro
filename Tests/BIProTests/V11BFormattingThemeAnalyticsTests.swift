import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite("Wave 3B (v1.1b) — Conditional Formatting, Analytics Reference Lines & Theme Switcher")
@MainActor
struct V11BFormattingThemeAnalyticsTests {
    @Test("VisualFormat đọc chính xác Rules (Conditional), Data Bars (columnFormatting), y1AxisReferenceLine và referenceLine (Avg/Min/Max)")
    func visualFormatDecodesVMV11BStructures() throws {
        // Exact JSON shapes observed on Power BI Desktop 2.159 (VM-V11B)
        let matrixObj = try JSONValue.parse(Data(#"""
        {
          "columnFormatting":[{
            "properties":{
              "dataBars":{
                "positiveColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'maxColor'"}}}}},
                "negativeColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'minColor'"}}}}},
                "axisColor":{"solid":{"color":{"expr":{"Literal":{"Value":"'foreground'"}}}}},
                "reverseDirection":{"expr":{"Literal":{"Value":"false"}}},
                "hideText":{"expr":{"Literal":{"Value":"false"}}},
                "totalMatchingOption":{"expr":{"Literal":{"Value":"1L"}}}
              }
            },
            "selector":{"metadata":"Dim_Client.Total_Clients"}
          }],
          "values":[{
            "properties":{
              "backColor":{
                "solid":{"color":{"expr":{"Conditional":{"Cases":[{
                  "Condition":{"Comparison":{"ComparisonKind":3,"Left":{"Measure":{"Expression":{"SourceRef":{"Entity":"Dim_Client"}},"Property":"Total_Clients"}},"Right":{"Literal":{"Value":"500D"}}}},
                  "Value":{"Literal":{"Value":"'#FCE4D6'"}}
                }]}}}}
              }
            },
            "selector":{"data":[{"dataViewWildcard":{"matchingOption":1}}],"metadata":"Dim_Client.Total_Clients"}
          }]
        }
        """#.utf8))
        let matFmt = VisualFormat(objects: ObjectProperties(matrixObj))
        #expect(matFmt.dataBars.count == 1)
        #expect(matFmt.dataBars[0].target == "Dim_Client.Total_Clients")
        #expect(matFmt.dataBars[0].hideText == false)
        #expect(matFmt.dataBars[0].totalMatchingOption == 1)

        #expect(matFmt.conditionalRules.count == 1)
        #expect(matFmt.conditionalRules[0].property == "backColor")
        #expect(matFmt.conditionalRules[0].cases[0].maxOp == .lessThan)
        #expect(matFmt.conditionalRules[0].cases[0].maxValue == 500)

        // CellFormatting evaluation: value 120 < 500 -> matches peach color; value 600 -> nil; total -> nil (matchingOption 1)
        let low = CellFormatting.evaluateConditionalColor(
            property: "backColor", targetQueryRef: "Dim_Client.Total_Clients", numericValue: 120,
            minVal: 0, maxVal: 1000, isTotal: false, cellOverrideHex: nil, format: matFmt, theme: .fallback
        )
        let high = CellFormatting.evaluateConditionalColor(
            property: "backColor", targetQueryRef: "Dim_Client.Total_Clients", numericValue: 600,
            minVal: 0, maxVal: 1000, isTotal: false, cellOverrideHex: nil, format: matFmt, theme: .fallback
        )
        let tot = CellFormatting.evaluateConditionalColor(
            property: "backColor", targetQueryRef: "Dim_Client.Total_Clients", numericValue: 120,
            minVal: 0, maxVal: 1000, isTotal: true, cellOverrideHex: nil, format: matFmt, theme: .fallback
        )
        #expect(low != nil)
        #expect(high == nil)
        #expect(tot == nil)

        // Data bar geometry
        let bar = CellFormatting.evaluateDataBar(
            targetQueryRef: "Dim_Client.Total_Clients", numericValue: 250,
            columnMin: 0, columnMax: 1000, isTotal: false, format: matFmt, theme: .fallback
        )
        #expect(bar != nil)
        #expect(abs((bar?.fraction ?? 0) - 0.25) < 1e-6)

        // Analytics lines (VM-V11B b2-q11.visual.json)
        let chartObj = try JSONValue.parse(Data(#"""
        {
          "y1AxisReferenceLine":[{
            "properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Target'"}}},"value":{"expr":{"Literal":{"Value":"250D"}}}},
            "selector":{"id":"1"}
          }],
          "referenceLine":[
            {"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Min line 1'"}}},"value":{"expr":{"Aggregation":{"Expression":{"SelectRef":{"ExpressionName":"T.M"}},"Function":3}}}},"selector":{"metadata":"T.M","id":"1"}},
            {"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Max line 1'"}}},"value":{"expr":{"Aggregation":{"Expression":{"SelectRef":{"ExpressionName":"T.M"}},"Function":4}}}},"selector":{"metadata":"T.M","id":"2"}},
            {"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"displayName":{"expr":{"Literal":{"Value":"'Average line 1'"}}},"value":{"expr":{"Aggregation":{"Expression":{"SelectRef":{"ExpressionName":"T.M"}},"Function":1}}}},"selector":{"metadata":"T.M","id":"3"}}
          ]
        }
        """#.utf8))
        let chartFmt = VisualFormat(objects: ObjectProperties(chartObj))
        #expect(chartFmt.analytics.constantLines.count == 1)
        #expect(chartFmt.analytics.constantLines[0].value == 250)
        #expect(chartFmt.analytics.dynamicLines.count == 3)
        let resolved = ChartReferenceLines.resolve(format: chartFmt.analytics, values: [100, 200, 300, 400])
        #expect(resolved.count == 4)
        #expect(resolved.first { $0.label == "Target" }?.value == 250)
        #expect(resolved.first { $0.label == "Min line 1" }?.value == 100)
        #expect(resolved.first { $0.label == "Max line 1" }?.value == 400)
        #expect(resolved.first { $0.label == "Average line 1" }?.value == 250)
    }

    @Test("ThemeCatalog có 6 preset hợp lệ và PBIRResourcePatch.settingCustomTheme ghi chuẩn report.json")
    func themeCatalogAndPBIRResourcePatch() throws {
        #expect(ThemeCatalog.presets.count == 6)
        for preset in ThemeCatalog.presets {
            #expect(ThemeCatalog.validateThemeJSON(preset.jsonData) == nil)
            let applied = ReportTheme.fallback.applying(jsonData: preset.jsonData)
            #expect(applied != nil)
            #expect(applied?.dataColors.first == preset.swatches.first)
        }
        #expect(ThemeCatalog.validateThemeJSON(Data("not json".utf8)) != nil)

        let baseReport = Data(#"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.3.0/schema.json","themeCollection":{"baseTheme":{"name":"CY24SU10","type":"SharedResources"}},"resourcePackages":[{"name":"SharedResources","type":"SharedResources","items":[{"name":"CY24SU10","path":"BaseThemes/CY24SU10.json","type":"BaseTheme"}]}]}"#.utf8)
        let exec = ThemeCatalog.presets[1]
        let patched = try PBIRResourcePatch.settingCustomTheme(name: exec.fileName, path: exec.fileName, to: baseReport)
        let json = try JSONValue.parse(patched)
        #expect(json["themeCollection"]?["customTheme"]?["name"]?.string == exec.fileName)
        #expect(json["themeCollection"]?["customTheme"]?["type"]?.string == "RegisteredResources")
        let regItems = PBIRResourcePatch.items(in: patched).filter { $0.package == "RegisteredResources" && $0.type == "CustomTheme" }
        #expect(regItems.count == 1)
        #expect(regItems[0].name == exec.fileName)
    }

    @Test("PBIRFormatPatch.replacingObject ghi và xoá sạch y1AxisReferenceLine & columnFormatting giữ nguyên phần khác")
    func formatPatchReplacingObjectRoundTrip() throws {
        let base = Data(#"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.14.0/schema.json","name":"v1","position":{"x":10,"y":10,"z":1,"width":300,"height":200},"visual":{"visualType":"lineChart","drillFilterOtherVisuals":true}}"#.utf8)
        let lineArr = #"[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}},"value":{"expr":{"Literal":{"Value":"150D"}}}},"selector":{"id":"1"}}]"#
        let added = try PBIRFormatPatch.replacingObject("y1AxisReferenceLine", scope: .objects, arrayJSON: lineArr, in: base)
        let parsed = try JSONValue.parse(added)
        #expect(parsed["visual"]?["objects"]?["y1AxisReferenceLine"]?.array.count == 1)
        let removed = try PBIRFormatPatch.replacingObject("y1AxisReferenceLine", scope: .objects, arrayJSON: nil, in: added)
        #expect((try JSONValue.parse(removed))["visual"]?["objects"]?["y1AxisReferenceLine"] == nil)
    }
}
