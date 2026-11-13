import Foundation
import PBIXKit

/// Một thuộc tính trong danh mục định dạng (`specs/006-d4-format-pane/data-model.md`).
struct FormatProperty: Equatable {
    /// Tên thuộc tính trong file.
    let key: String
    /// Tên hiển thị tiếng Việt.
    let title: String
    let kind: FormatKind
    /// Công tắc đầu thẻ (`show`, hoặc `areaShow` ở thẻ Kiểu đường).
    let isCardSwitch: Bool
    /// Nguồn quan sát: Nhom6 hoặc mục của `docs/phase-d-evidence/vm-d4/QUAN-SAT.md`. Bắt buộc có (không bịa khoá).
    let observed: String
    /// Đường vẽ của BI Pro có đọc thuộc tính này (R9); `false` thì ghi chú "BI Pro chưa vẽ".
    let rendered: Bool
    /// Thêm được khi chưa có trong file (R4: tổng phụ và nút chỉ sửa giá trị có sẵn).
    let addable: Bool
    /// Giá trị bật/tắt Desktop hiển thị khi file chưa có thuộc tính (đã quan sát ở VM-D4); nil: chưa biết.
    let defaultOn: Bool?
}

/// Một thẻ (một khoá của `objects` hoặc `visualContainerObjects`).
struct FormatCard: Equatable {
    let scope: FormatScope
    /// Khoá trong file (không trùng tên thẻ trên giao diện của Desktop: R3).
    let objectKey: String
    let title: String
    let properties: [FormatProperty]
    /// Mục mới ghi `selector:{id:"default"}` sau `properties` (`cardVisual`, R6).
    let usesDefaultSelector: Bool
    /// Thuộc tính đặt riêng cho từng chuỗi (mục có `selector.metadata` = `queryRef` của measure; VM-D8 mục 6).
    /// Rỗng: thẻ không có định dạng theo chuỗi.
    var seriesProperties: [FormatProperty] = []

    var cardSwitch: FormatProperty? { properties.first(where: \.isCardSwitch) }
}

/// Một chỗ trong file mà Format pane không sửa được (khoá ngoài danh mục, thuộc tính lạ, mục theo trường).
struct FormatReadOnlyItem: Equatable {
    let scope: FormatScope
    let object: String
    /// nil: cả khoá (hoặc mục theo trường) chỉ-đọc.
    let property: String?
    let reason: String
}

/// Danh mục thẻ và thuộc tính của Format pane theo phạm vi và loại visual (R4). Chỉ gồm thuộc tính đã quan sát ở Nhom6
/// hoặc VM-D4; thuộc tính ngoài danh mục chỉ-đọc. Mở rộng khi quan sát thêm (R12): chỉ sửa file này và test.
enum FormatCatalog {
    // MARK: Kiểu dùng chung

    private static let fontSize = FormatKind.number(min: 1, max: 50, step: 1, tail: .d)
    private static let percent = FormatKind.number(min: 0, max: 100, step: 1, tail: .d)
    private static let pixels = FormatKind.number(min: 0, max: 100, step: 1, tail: .d)
    private static let units = FormatKind.choice([FormatChoice(title: "Tự động", literal: "0D"), FormatChoice(title: "Không", literal: "1D")])
    private static let precision = FormatKind.number(min: 0, max: 10, step: 1, tail: .l)
    private static let plainText = FormatKind.text(maxLength: 200, allowsEmpty: false)

    private static func prop(_ key: String, _ title: String, _ kind: FormatKind, _ observed: String, rendered: Bool = true,
                             cardSwitch: Bool = false, addable: Bool = true, defaultOn: Bool? = nil) -> FormatProperty {
        FormatProperty(key: key, title: title, kind: kind, isCardSwitch: cardSwitch, observed: observed, rendered: rendered,
                       addable: addable, defaultOn: defaultOn)
    }

    private static func card(_ scope: FormatScope, _ key: String, _ title: String, selector: Bool = false, _ properties: [FormatProperty],
                             series: [FormatProperty] = []) -> FormatCard {
        FormatCard(scope: scope, objectKey: key, title: title, properties: properties, usesDefaultSelector: selector, seriesProperties: series)
    }

    private static let nhom6 = "Nhom6"
    private static let vm = "VM-D4"
    /// `docs/phase-d-evidence/vm-d8/QUAN-SAT.md` mục 6.
    private static let vm8 = "VM-D8 mục 6"
    /// Cỡ chữ tiêu đề: Desktop kẹp 8 đến 60 (VM-D8).
    private static let titleFontSize = FormatKind.number(min: 8, max: 60, step: 1, tail: .d)

    private static let axisCharts: Set<String> = ["clusteredColumnChart", "columnChart", "clusteredBarChart", "hundredPercentStackedColumnChart",
                                                  "lineChart", "lineClusteredColumnComboChart", "lineStackedColumnComboChart"]

    // MARK: Thẻ

    static func cards(for type: String, scope: FormatScope) -> [FormatCard] {
        scope == .container ? containerCards : visualCards(for: type)
    }

    /// Phạm vi Chung: giống nhau cho mọi loại visual.
    private static let containerCards: [FormatCard] = [
        card(.container, "title", "Tiêu đề", [
            prop("show", "Hiện tiêu đề", .bool, "\(nhom6), \(vm) mục 5", cardSwitch: true, defaultOn: true),
            prop("text", "Nội dung", plainText, "\(nhom6), \(vm) mục 1"),
            prop("fontSize", "Cỡ chữ", titleFontSize, "\(vm) mục 1, \(vm8)"),
            prop("fontFamily", "Phông chữ", .choice([
                FormatChoice(title: "Segoe UI Semibold", literal: "'''Segoe UI Semibold'', wf_segoe-ui_semibold, helvetica, arial, sans-serif'"),
                FormatChoice(title: "Georgia", literal: "'Georgia'")]), vm8, rendered: false),
            prop("heading", "Cấp tiêu đề", .choice([FormatChoice(title: "Heading 2", literal: "'Heading2'")]), vm8, rendered: false),
            prop("titleWrap", "Ngắt dòng", .bool, vm8, rendered: false, defaultOn: true),
            prop("bold", "Đậm", .bool, "\(vm) mục 3"),
            prop("alignment", "Căn lề", .choice([FormatChoice(title: "Trái", literal: "'left'"), FormatChoice(title: "Giữa", literal: "'center'"),
                                                   FormatChoice(title: "Phải", literal: "'right'")]), "\(vm) mục 1, vòng 2"),
            prop("fontColor", "Màu chữ", .color, "\(vm) mục 1"),
        ]),
        card(.container, "subTitle", "Phụ đề", [
            prop("show", "Hiện phụ đề", .bool, nhom6, rendered: false, cardSwitch: true),
            prop("text", "Nội dung", plainText, nhom6, rendered: false),
            prop("fontSize", "Cỡ chữ", fontSize, nhom6, rendered: false),
            prop("fontColor", "Màu chữ", .color, nhom6, rendered: false),
        ]),
        card(.container, "divider", "Đường kẻ dưới tiêu đề", [
            prop("show", "Hiện đường kẻ", .bool, vm8, rendered: false, cardSwitch: true, defaultOn: false),
        ]),
        card(.container, "background", "Nền", [
            prop("show", "Hiện nền", .bool, nhom6, cardSwitch: true, defaultOn: true),
            prop("color", "Màu", .color, nhom6),
            prop("transparency", "Độ trong suốt (%)", percent, "\(nhom6), \(vm) mục 2"),
        ]),
        card(.container, "border", "Viền", [
            prop("show", "Hiện viền", .bool, "\(nhom6), \(vm) mục 2", cardSwitch: true, defaultOn: true),
            prop("color", "Màu", .color, "\(vm) vòng 2"),
            prop("radius", "Bo góc (px)", pixels, "\(vm) mục 2"),
            prop("width", "Độ dày (px)", .number(min: 0, max: 20, step: 1, tail: .d), "\(vm) mục 2"),
        ]),
        card(.container, "dropShadow", "Đổ bóng", [
            prop("show", "Hiện bóng", .bool, "\(nhom6), \(vm) mục 2", cardSwitch: true, defaultOn: false),
            prop("color", "Màu", .color, vm8, rendered: false),
            // Desktop ghi cả bộ số theo preset khi bật bóng (kiểu nguyên `L`); chỉ sửa khi file đã có, không tự thêm lẻ.
            prop("transparency", "Độ trong suốt (%)", .number(min: 0, max: 100, step: 1, tail: .l), vm8, rendered: false, addable: false),
            prop("shadowBlur", "Độ nhoè (px)", .number(min: 0, max: 100, step: 1, tail: .l), vm8, rendered: false, addable: false),
            prop("shadowSpread", "Kích thước (px)", .number(min: 0, max: 100, step: 1, tail: .l), vm8, rendered: false, addable: false),
            prop("shadowDistance", "Khoảng cách (px)", .number(min: 0, max: 100, step: 1, tail: .l), vm8, rendered: false, addable: false),
            prop("angle", "Góc (độ)", .number(min: 0, max: 360, step: 1, tail: .l), vm8, rendered: false, addable: false),
        ]),
        card(.container, "padding", "Khoảng đệm", [
            prop("top", "Trên (px)", pixels, nhom6, rendered: false),
            prop("bottom", "Dưới (px)", pixels, nhom6, rendered: false),
            prop("left", "Trái (px)", pixels, nhom6, rendered: false),
            prop("right", "Phải (px)", pixels, nhom6, rendered: false),
        ]),
        card(.container, "visualHeader", "Biểu tượng tiêu đề", [
            prop("show", "Hiện biểu tượng", .bool, "\(vm) mục 2", rendered: false, cardSwitch: true, defaultOn: true),
        ]),
    ]

    private static func visualCards(for type: String) -> [FormatCard] {
        switch type {
        case "card":
            return [
                card(.objects, "labels", "Giá trị", [
                    prop("fontSize", "Cỡ chữ", fontSize, "\(nhom6), \(vm) mục 6"),
                    prop("color", "Màu", .color, nhom6),
                    prop("bold", "Đậm", .bool, nhom6),
                    prop("labelDisplayUnits", "Đơn vị hiển thị", units, nhom6),
                    prop("labelPrecision", "Số chữ số thập phân", precision, "\(nhom6), \(vm) mục 6"),
                ]),
                card(.objects, "categoryLabels", "Nhãn danh mục", [
                    prop("show", "Hiện nhãn", .bool, "\(nhom6), \(vm) mục 6", cardSwitch: true),
                    prop("color", "Màu", .color, nhom6),
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                ]),
            ]
        case "cardVisual":
            return [card(.objects, "cardImage", "Ảnh thẻ", selector: true, [
                prop("show", "Hiện ảnh", .bool, "\(vm) mục 6", rendered: false, cardSwitch: true, defaultOn: false),
            ])]
        case "slicer":
            return [
                card(.objects, "header", "Tiêu đề slicer", [
                    prop("show", "Hiện tiêu đề", .bool, "\(nhom6), \(vm) mục 6", cardSwitch: true),
                    prop("fontColor", "Màu chữ", .color, nhom6),
                    prop("textSize", "Cỡ chữ", fontSize, nhom6),
                ]),
                card(.objects, "items", "Mục", [
                    prop("padding", "Khoảng đệm (px)", pixels, "\(vm) mục 6", rendered: false),
                ]),
            ]
        case _ where axisCharts.contains(type):
            return [
                card(.objects, "legend", "Chú giải", [
                    prop("show", "Hiện chú giải", .bool, "\(nhom6), \(vm) mục 3", cardSwitch: true),
                    prop("position", "Vị trí", .choice([FormatChoice(title: "Dưới", literal: "'Bottom'"), FormatChoice(title: "Trên", literal: "'Top'")]), nhom6),
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                ]),
                card(.objects, "labels", "Nhãn dữ liệu", [
                    prop("show", "Hiện nhãn", .bool, "\(nhom6), \(vm) mục 2", cardSwitch: true, defaultOn: false),
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                    prop("labelOrientation", "Hướng", .choice([FormatChoice(title: "Dọc", literal: "0D")]), "\(vm) mục 2", rendered: false),
                    prop("labelDisplayUnits", "Đơn vị hiển thị", units, nhom6),
                    prop("labelPrecision", "Số chữ số thập phân", precision, nhom6),
                ]),
                card(.objects, "valueAxis", "Trục Y", [
                    prop("show", "Hiện giá trị trục", .bool, "\(vm) mục 3", rendered: false, defaultOn: true),
                    prop("showAxisTitle", "Hiện tiêu đề trục", .bool, "\(vm) mục 3", rendered: false, defaultOn: false),
                    prop("invertAxis", "Đảo trục", .bool, "\(vm) mục 3", rendered: false, defaultOn: false),
                    prop("start", "Nhỏ nhất", .number(min: -1_000_000_000, max: 1_000_000_000, step: 1, tail: .d), nhom6),
                    prop("end", "Lớn nhất", .number(min: -1_000_000_000, max: 1_000_000_000, step: 1, tail: .d), nhom6),
                    prop("labelDisplayUnits", "Đơn vị hiển thị", units, nhom6),
                    prop("labelPrecision", "Số chữ số thập phân", precision, nhom6),
                ]),
                card(.objects, "categoryAxis", "Trục X", [
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                ]),
                card(.objects, "zoom", "Thanh thu phóng", [
                    prop("show", "Hiện thanh thu phóng", .bool, "\(vm) mục 3", rendered: false, cardSwitch: true, defaultOn: false),
                ]),
                card(.objects, "lineStyles", "Vùng tô và đường", [
                    prop("areaShow", "Tô vùng dưới đường", .bool, "\(vm) mục 3", rendered: false, cardSwitch: true, defaultOn: false),
                ]),
                // Mục chung (Series = All) chỉ có độ trong suốt; màu đặt theo từng chuỗi ở mục có `selector.metadata`
                // (Desktop khoá ô màu khi chọn All).
                card(.objects, "dataPoint", "Cột và thanh", [
                    prop("fillTransparency", "Độ trong suốt (%)", percent, vm8, rendered: false),
                ], series: [
                    prop("fill", "Màu", .color, "\(nhom6), \(vm8)"),
                ]),
            ]
        case "donutChart":
            return [
                card(.objects, "legend", "Chú giải", [
                    prop("show", "Hiện chú giải", .bool, nhom6, cardSwitch: true),
                    prop("position", "Vị trí", .choice([FormatChoice(title: "Dưới", literal: "'Bottom'"), FormatChoice(title: "Trên", literal: "'Top'")]), nhom6),
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                ]),
                card(.objects, "labels", "Nhãn dữ liệu", [
                    prop("show", "Hiện nhãn", .bool, nhom6, cardSwitch: true),
                    prop("labelStyle", "Kiểu nhãn", .choice([FormatChoice(title: "Phần trăm tổng", literal: "'Percent of total'")]), nhom6),
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                    prop("labelDisplayUnits", "Đơn vị hiển thị", units, nhom6),
                ]),
            ]
        case "pivotTable":
            return [
                card(.objects, "columnHeaders", "Tiêu đề cột", [
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                    prop("autoSizeColumnWidth", "Tự co độ rộng cột", .bool, nhom6),
                ]),
                card(.objects, "rowHeaders", "Tiêu đề hàng", [
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                    prop("unfrozen", "Bỏ cố định tiêu đề hàng", .bool, vm8, rendered: false, defaultOn: false),
                ]),
                card(.objects, "values", "Giá trị", [
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6),
                ]),
                card(.objects, "grid", "Lưới", [
                    prop("rowPadding", "Đệm hàng (px)", .number(min: 0, max: 50, step: 1, tail: .d), nhom6),
                    prop("gridHorizontal", "Đường kẻ ngang", .bool, vm8, rendered: false, defaultOn: false),
                    prop("gridVertical", "Đường kẻ dọc", .bool, vm8, rendered: false, defaultOn: false),
                ]),
                card(.objects, "general", "Bố cục", [
                    // Danh sách của Desktop: Compact, Outline, Tabular; mới thấy literal của Tabular trong file.
                    prop("layout", "Kiểu bố cục", .choice([FormatChoice(title: "Gọn (Compact)", literal: "'Compact'"), FormatChoice(title: "Phác thảo (Outline)", literal: "'Outline'"),
                                                                           FormatChoice(title: "Dạng bảng (Tabular)", literal: "'Tabular'")]), vm8, rendered: false),
                ]),
                card(.objects, "subTotals", "Tổng phụ", [
                    prop("rowSubtotals", "Tổng phụ theo hàng", .bool, "\(nhom6), \(vm8)", defaultOn: true),
                    prop("columnSubtotals", "Tổng phụ theo cột", .bool, "\(nhom6), \(vm8)", defaultOn: true),
                ]),
            ]
        case "actionButton":
            return [
                card(.objects, "text", "Văn bản", [
                    prop("show", "Hiện văn bản", .bool, nhom6, cardSwitch: true, addable: false),
                    prop("text", "Nội dung", plainText, nhom6, addable: false),
                    prop("fontColor", "Màu chữ", .color, nhom6, addable: false),
                    prop("fontSize", "Cỡ chữ", fontSize, nhom6, addable: false),
                    prop("bold", "Đậm", .bool, nhom6, addable: false),
                ]),
                card(.objects, "fill", "Tô màu", [
                    prop("show", "Hiện màu tô", .bool, nhom6, cardSwitch: true, addable: false),
                    prop("fillColor", "Màu", .color, nhom6, addable: false),
                    prop("transparency", "Độ trong suốt (%)", percent, nhom6, addable: false),
                ]),
                card(.objects, "outline", "Viền ngoài", [
                    prop("show", "Hiện viền", .bool, nhom6, cardSwitch: true, addable: false),
                    prop("lineColor", "Màu", .color, nhom6, addable: false),
                    prop("weight", "Độ dày (px)", .number(min: 0, max: 20, step: 1, tail: .d), nhom6, addable: false),
                ]),
            ]
        default:
            return []
        }
    }

    // MARK: Chỉ-đọc

    /// Những chỗ trong khoá phạm vi `scopeJSON` (`visual.objects` hoặc `visual.visualContainerObjects`) mà danh mục không phủ.
    static func readOnlyItems(in scopeJSON: JSONValue?, type: String, scope: FormatScope) -> [FormatReadOnlyItem] {
        guard let scopeJSON else { return [] }
        let cards = cards(for: type, scope: scope)
        var out: [FormatReadOnlyItem] = []
        for key in scopeJSON.object.keys.sorted() {
            guard let card = cards.first(where: { $0.objectKey == key }) else {
                out.append(FormatReadOnlyItem(scope: scope, object: key, property: nil, reason: "Chưa quan sát ở Power BI Desktop"))
                continue
            }
            let known = Set(card.properties.map(\.key))
            let knownPerSeries = Set(card.seriesProperties.map(\.key))
            var boundToFields = false
            for entry in scopeJSON[key]?.array ?? [] {
                if isEditable(entry) {
                    for property in (entry["properties"]?.object.keys.sorted() ?? []) where !known.contains(property) {
                        out.append(FormatReadOnlyItem(scope: scope, object: key, property: property, reason: "Chưa quan sát ở Power BI Desktop"))
                    }
                } else if !knownPerSeries.isEmpty, seriesRef(of: entry) != nil {
                    for property in (entry["properties"]?.object.keys.sorted() ?? []) where !knownPerSeries.contains(property) {
                        out.append(FormatReadOnlyItem(scope: scope, object: key, property: property, reason: "Theo chuỗi, chưa quan sát ở Power BI Desktop"))
                    }
                } else {
                    boundToFields = true
                }
            }
            if boundToFields {
                out.append(FormatReadOnlyItem(scope: scope, object: key, property: nil, reason: "Định dạng riêng theo trường hoặc điểm dữ liệu, chưa sửa được"))
            }
        }
        return out
    }

    /// Mục chung: không có `selector`, hoặc chỉ có `{id: "default"}` (R6).
    static func isEditable(_ entry: JSONValue) -> Bool {
        guard let selector = entry["selector"] else { return true }
        let keys = Set(selector.object.keys)
        return keys == ["id"] && selector["id"]?.string == "default"
    }

    /// `queryRef` của chuỗi mà mục này định dạng riêng: selector chỉ có `metadata` (VM-D8 mục 6). nil với mục khác.
    /// Hoặc, khi selector chỉ có `data` (một `scopeId.Comparison` bằng một giá trị của cột ở ô Chú giải, VM-D8c mục 2):
    /// `"data:<literal>"`, ví dụ `data:'Female'`. nil với mục khác (nhiều điều kiện, so sánh khác, kèm `metadata`).
    static func seriesRef(of entry: JSONValue) -> String? {
        guard let selector = entry["selector"] else { return nil }
        let keys = Set(selector.object.keys)
        if keys == ["metadata"] { return selector["metadata"]?.string }
        return legendValue(of: entry).map { "\(legendPrefix)\($0.literal)" }
    }

    /// Tiền tố của khoá chuỗi theo giá trị Chú giải (khoá chuỗi measure là `Bảng.Tên`, không bắt đầu bằng đây).
    static let legendPrefix = PBIRFormatPatch.legendPrefix

    /// Cột và literal của mục theo giá trị Chú giải; nil nếu mục không đúng dạng đó.
    static func legendValue(of entry: JSONValue) -> (entity: String, property: String, literal: String)? {
        guard let selector = entry["selector"], Set(selector.object.keys) == ["data"],
              let data = selector["data"]?.array, data.count == 1, Set(data[0].object.keys) == ["scopeId"],
              let comparison = data[0]["scopeId"]?["Comparison"],
              comparison["ComparisonKind"]?.number == 0,
              let column = comparison["Left"]?["Column"],
              let entity = column["Expression"]?["SourceRef"]?["Entity"]?.string, let property = column["Property"]?.string,
              let literal = comparison["Right"]?["Literal"]?["Value"]?.string else { return nil }
        return (entity, property, literal)
    }

    /// Tên hiển thị của giá trị Chú giải từ literal: `'Female'` → `Female`, `1L` → `1`.
    static func legendTitle(_ literal: String) -> String {
        if literal.count >= 2, literal.hasPrefix("'"), literal.hasSuffix("'") {
            return String(literal.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if let last = literal.last, "LDM".contains(last), Double(literal.dropLast()) != nil { return String(literal.dropLast()) }
        return literal
    }

    /// Ô chứa measure mà mỗi measure là một chuỗi (cột/thanh ở `Y`, đường của combo ở `Y2`).
    static let seriesRoles: Set<String> = ["Y", "Y2"]
    /// Ô Chú giải: có trường ở đây thì chuỗi sinh từ giá trị của cột, màu theo chuỗi kiểu đó chưa quan sát.
    static let legendRole = "Series"
}
