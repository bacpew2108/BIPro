import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Danh mục thuộc tính định dạng (D4): chỉ gồm thuộc tính đã quan sát (`specs/006-d4-format-pane/research.md` R4).
@Suite struct FormatCatalogTests {
    static let types = ["card", "cardVisual", "slicer", "clusteredColumnChart", "columnChart", "clusteredBarChart", "hundredPercentStackedColumnChart",
                        "lineChart", "lineClusteredColumnComboChart", "lineStackedColumnComboChart", "donutChart", "treemap", "pivotTable",
                        "actionButton", "textbox", "image", "shapeMap"]

    static var allCards: [FormatCard] {
        var out: [FormatCard] = []
        for type in types { for scope in [FormatScope.objects, .container] { out += FormatCatalog.cards(for: type, scope: scope) } }
        return out
    }

    func card(_ type: String, _ scope: FormatScope, _ key: String) -> FormatCard? {
        FormatCatalog.cards(for: type, scope: scope).first { $0.objectKey == key }
    }

    // MARK: (a), (b) nguồn quan sát và không trùng

    @Test func everyPropertyNamesItsObservation() {
        for card in Self.allCards {
            #expect(!card.title.isEmpty)
            for property in card.properties {
                #expect(!property.observed.isEmpty, "\(card.objectKey).\(property.key) thiếu nguồn quan sát")
                #expect(!property.title.isEmpty)
            }
        }
    }

    @Test func noDuplicateObjectsOrProperties() {
        for type in Self.types {
            for scope in [FormatScope.objects, .container] {
                let cards = FormatCatalog.cards(for: type, scope: scope)
                #expect(Set(cards.map(\.objectKey)).count == cards.count, "\(type) \(scope) trùng khoá")
                for card in cards { #expect(Set(card.properties.map(\.key)).count == card.properties.count, "\(type) \(card.objectKey) trùng thuộc tính") }
            }
        }
    }

    // MARK: (c) danh sách chỉ có giá trị đã quan sát

    @Test func choicesOnlyHoldObservedValues() {
        let allowed: [String: Set<String>] = [
            "position": ["'Bottom'", "'Top'"], "labelDisplayUnits": ["0D", "1D"], "labelOrientation": ["0D"],
            "alignment": ["'left'", "'center'", "'right'"], "labelStyle": ["'Percent of total'"],
            "fontFamily": ["'Georgia'", "'''Segoe UI Semibold'', wf_segoe-ui_semibold, helvetica, arial, sans-serif'"], "heading": ["'Heading2'"],
            "layout": ["'Compact'", "'Outline'", "'Tabular'"],   // VM-D8 mục 6, VM-D8c mục 1
        ]
        for card in Self.allCards {
            for property in card.properties {
                guard case .choice(let options) = property.kind else { continue }
                let permitted = allowed[property.key]
                #expect(permitted != nil, "\(card.objectKey).\(property.key) là danh sách nhưng chưa khai báo giá trị đã quan sát")
                for option in options { #expect(permitted?.contains(option.literal) == true, "\(property.key) có giá trị chưa quan sát \(option.literal)") }
            }
        }
    }

    @Test func numbersCarryAKnownTailAndSaneRange() {
        for card in Self.allCards {
            for property in card.properties {
                guard case .number(let min, let max, let step, _) = property.kind else { continue }
                #expect(min < max && step > 0)
                // Cỡ chữ tiêu đề: Desktop kẹp 8 đến 60 (VM-D8); chỗ khác giữ khoảng cũ.
                if card.scope == .container, card.objectKey == "title", property.key == "fontSize" { #expect(min == 8 && max == 60) }
                else if property.key == "fontSize" || property.key == "textSize" { #expect(min == 1 && max == 50) }
            }
        }
        if case .number(_, _, _, let tail)? = card("card", .objects, "labels")?.properties.first(where: { $0.key == "labelPrecision" })?.kind { #expect(tail == .l) }
        else { Issue.record("labelPrecision phải là số nguyên L") }
    }

    // MARK: (e) thẻ theo loại

    @Test func cardsPerVisualType() {
        #expect(FormatCatalog.cards(for: "card", scope: .objects).map(\.objectKey) == ["labels", "categoryLabels"])
        #expect(FormatCatalog.cards(for: "slicer", scope: .objects).map(\.objectKey) == ["header", "items"])
        #expect(FormatCatalog.cards(for: "cardVisual", scope: .objects).map(\.objectKey) == ["cardImage"])
        #expect(FormatCatalog.cards(for: "textbox", scope: .objects).isEmpty)
        #expect(FormatCatalog.cards(for: "treemap", scope: .objects).isEmpty)
        for type in ["clusteredColumnChart", "columnChart", "clusteredBarChart", "hundredPercentStackedColumnChart", "lineChart", "lineClusteredColumnComboChart", "lineStackedColumnComboChart"] {
            let keys = Set(FormatCatalog.cards(for: type, scope: .objects).map(\.objectKey))
            #expect(keys.isSuperset(of: ["legend", "labels", "valueAxis", "categoryAxis", "zoom", "lineStyles"]), "\(type): \(keys)")
        }
        #expect(Set(FormatCatalog.cards(for: "donutChart", scope: .objects).map(\.objectKey)) == ["legend", "labels"])
        #expect(Set(FormatCatalog.cards(for: "pivotTable", scope: .objects).map(\.objectKey)) == ["columnHeaders", "rowHeaders", "values", "grid", "general", "subTotals"])
        #expect(Set(FormatCatalog.cards(for: "actionButton", scope: .objects).map(\.objectKey)) == ["text", "fill", "outline"])
    }

    @Test func theGeneralScopeIsTheSameForEveryType() {
        let expected = ["title", "subTitle", "divider", "background", "border", "dropShadow", "padding", "visualHeader"]
        for type in Self.types { #expect(FormatCatalog.cards(for: type, scope: .container).map(\.objectKey) == expected, "\(type)") }
    }

    @Test func cardSwitchesMapToTheRealProperty() {
        func switchKey(_ type: String, _ scope: FormatScope, _ key: String) -> String? { card(type, scope, key)?.properties.first(where: \.isCardSwitch)?.key }
        #expect(switchKey("lineChart", .objects, "legend") == "show")
        #expect(switchKey("lineChart", .objects, "lineStyles") == "areaShow")   // "Shade area" ghi lineStyles.areaShow (R3)
        #expect(switchKey("lineChart", .objects, "zoom") == "show")
        #expect(switchKey("lineChart", .objects, "valueAxis") == nil)
        #expect(switchKey("card", .objects, "categoryLabels") == "show")
        #expect(switchKey("card", .objects, "labels") == nil)                   // "Callout value" không có công tắc
        #expect(switchKey("card", .container, "title") == "show")
        #expect(switchKey("card", .container, "visualHeader") == "show")
    }

    @Test func displayTitlesFollowDesktopGroups() {
        #expect(card("card", .objects, "labels")?.title == "Giá trị")
        #expect(card("slicer", .objects, "items")?.title == "Mục")
        #expect(card("lineChart", .objects, "lineStyles")?.title == "Vùng tô và đường")
    }

    // MARK: cờ rendered và addable

    @Test func renderedFlagsFollowTheRenderer() {
        func property(_ type: String, _ scope: FormatScope, _ object: String, _ key: String) -> FormatProperty? {
            card(type, scope, object)?.properties.first { $0.key == key }
        }
        #expect(property("card", .container, "title", "text")?.rendered == true)
        #expect(property("card", .container, "background", "color")?.rendered == true)
        #expect(property("card", .container, "border", "radius")?.rendered == true)
        #expect(property("card", .container, "padding", "top")?.rendered == false)
        #expect(property("card", .container, "subTitle", "text")?.rendered == false)
        #expect(property("card", .container, "visualHeader", "show")?.rendered == false)
        #expect(property("lineChart", .objects, "lineStyles", "areaShow")?.rendered == false)
        #expect(property("lineChart", .objects, "valueAxis", "invertAxis")?.rendered == false)
        #expect(property("lineChart", .objects, "legend", "position")?.rendered == true)
        #expect(property("slicer", .objects, "items", "padding")?.rendered == false)
    }

    /// VM-D8: các thuộc tính quan sát thêm ở Desktop (phông, heading, ngắt dòng, đường kẻ, bóng, lưới và tổng phụ của matrix, độ trong suốt cột).
    @Test func propertiesObservedAtVMD8() {
        func property(_ type: String, _ scope: FormatScope, _ object: String, _ key: String) -> FormatProperty? {
            card(type, scope, object)?.properties.first { $0.key == key }
        }
        #expect(property("card", .container, "title", "fontFamily")?.kind == .choice([
            FormatChoice(title: "Segoe UI Semibold", literal: "'''Segoe UI Semibold'', wf_segoe-ui_semibold, helvetica, arial, sans-serif'"),
            FormatChoice(title: "Georgia", literal: "'Georgia'")]))
        #expect(property("card", .container, "title", "heading")?.kind == .choice([FormatChoice(title: "Heading 2", literal: "'Heading2'")]))
        #expect(property("card", .container, "title", "titleWrap")?.kind == .bool)
        #expect(property("card", .container, "divider", "show")?.isCardSwitch == true)
        #expect(property("card", .container, "divider", "show")?.defaultOn == false)
        #expect(property("card", .container, "dropShadow", "color")?.kind == .color)
        // Số của bóng: Desktop ghi cả bộ theo preset, kiểu nguyên `L`; BI Pro chỉ sửa khi file đã có.
        for key in ["angle", "shadowDistance", "shadowBlur", "shadowSpread", "transparency"] {
            let p = property("card", .container, "dropShadow", key)
            guard case .number(_, _, _, let tail)? = p?.kind else { Issue.record("dropShadow.\(key) thiếu"); continue }
            #expect(tail == .l && p?.addable == false, "\(key)")
        }
        for key in ["gridHorizontal", "gridVertical"] {
            #expect(property("pivotTable", .objects, "grid", key)?.kind == .bool && property("pivotTable", .objects, "grid", key)?.defaultOn == false)
        }
        #expect(property("pivotTable", .objects, "rowHeaders", "unfrozen")?.kind == .bool)
        #expect(card("pivotTable", .objects, "subTotals")?.properties.allSatisfy { $0.addable && $0.defaultOn == true } == true)
        #expect(property("clusteredBarChart", .objects, "dataPoint", "fillTransparency")?.kind == .number(min: 0, max: 100, step: 1, tail: .d))
        for p in ["fontFamily", "heading", "titleWrap"] { #expect(property("card", .container, "title", p)?.observed.contains("VM-D8") == true) }
    }

    @Test func buttonsOnlyEditWhatIsThere() {
        for key in ["text", "fill", "outline"] { #expect(card("actionButton", .objects, key)?.properties.allSatisfy { !$0.addable } == true) }
        #expect(card("card", .objects, "labels")?.properties.allSatisfy(\.addable) == true)
        #expect(card("card", .container, "title")?.properties.allSatisfy(\.addable) == true)
    }

    @Test func cardVisualWritesTheDefaultSelector() {
        #expect(card("cardVisual", .objects, "cardImage")?.usesDefaultSelector == true)
        #expect(card("card", .objects, "labels")?.usesDefaultSelector == false)
    }

    // MARK: readOnlyKeys

    @Test func readOnlyKeysListWhatTheCatalogDoesNotCover() {
        let json = try! JSONValue.parse(#"""
        {"labels":[{"properties":{"fontSize":{"expr":{"Literal":{"Value":"20D"}}},"weird":{"expr":{"Literal":{"Value":"1D"}}}}}],
         "dataPoint":[{"properties":{"fill":{"solid":{"color":{"expr":{"Literal":{"Value":"'#fff'"}}}}}},"selector":{"data":[{}]}}],
         "categoryLabels":[{"properties":{"show":{"expr":{"Literal":{"Value":"true"}}}},"selector":{"metadata":"T.c"}},
                           {"properties":{"color":{"solid":{"color":{"expr":{"Literal":{"Value":"'#fff'"}}}}}}}]}
        """#)
        let items = FormatCatalog.readOnlyItems(in: json, type: "card", scope: .objects)
        #expect(items.contains { $0.object == "labels" && $0.property == "weird" })
        #expect(items.contains { $0.object == "dataPoint" && $0.property == nil })          // khoá ngoài danh mục
        #expect(items.contains { $0.object == "categoryLabels" && $0.property == nil })     // có mục theo trường
        #expect(!items.contains { $0.object == "labels" && $0.property == "fontSize" })
        #expect(FormatCatalog.readOnlyItems(in: nil, type: "card", scope: .objects).isEmpty)
    }

    // MARK: SC-005: không bịa khoá

    static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }

    /// `phạm vi.khoá.thuộc tính` của mọi mục chung trong các `visual.json` Desktop ghi ở VM-D4.
    static func evidenceKeys() throws -> Set<String> {
        let dir = repoRoot.appendingPathComponent("docs/phase-d-evidence/vm-d4/json")
        var keys = Set<String>()
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where name.hasSuffix(".visual.json") {
            let json = try JSONValue.parse(try Data(contentsOf: dir.appendingPathComponent(name)))
            for scope in FormatScope.allCases {
                for (object, entries) in json["visual"]?[scope.key]?.object ?? [:] {
                    for entry in entries.array where FormatCatalog.isEditable(entry) {
                        for property in (entry["properties"]?.object ?? [:]).keys { keys.insert("\(scope.rawValue).\(object).\(property)") }
                    }
                }
            }
        }
        return keys
    }

    @Test func propertiesObservedOnlyAtVMD4AreInTheEvidence() throws {
        let evidence = try Self.evidenceKeys()
        let notes = try String(contentsOf: Self.repoRoot.appendingPathComponent("docs/phase-d-evidence/vm-d4/QUAN-SAT.md"), encoding: .utf8)
        #expect(evidence.count > 20)
        for card in Self.allCards {
            for property in card.properties where property.observed.contains("VM-D4") && !property.observed.contains("Nhom6") {
                let key = "\(card.scope.rawValue).\(card.objectKey).\(property.key)"
                #expect(evidence.contains(key) || notes.contains(property.key), "\(key) ghi là quan sát ở VM-D4 nhưng không có trong bằng chứng")
            }
        }
    }

    /// VM-D12 mục 3: công tắc Desktop bật sẵn cho visual mới.
    @Test func switchesDesktopTurnsOnForANewVisualDefaultToOn() {
        func on(_ type: String, _ object: String) -> Bool? {
            card(type, .objects, object)?.cardSwitch?.defaultOn
        }
        #expect(on("clusteredColumnChart", "legend") == true && on("lineChart", "legend") == true)
        #expect(on("clusteredColumnChart", "labels") == false)       // Nhãn dữ liệu: tắt (VM-D4 mục 2)
        #expect(on("donutChart", "legend") == true && on("donutChart", "labels") == true)
        #expect(on("slicer", "header") == true)
    }
}
