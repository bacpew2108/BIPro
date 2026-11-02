// Hợp đồng Phase C (đợt 0, lead): định dạng của visual, đọc một lần từ `objects` thành struct có kiểu.
//
// Chỉ có những thuộc tính Nhom6 thật sự dùng (đếm ở PHASE_C_PLAN §1.2). Giá trị nil nghĩa là visual không ghi,
// renderer dùng mặc định của Power BI (ghi [SUY ĐOÁN] tại chỗ dùng nếu chưa quan sát).
//
// Màu giữ ở dạng `ReportLiteral` để renderer tự giải theo theme: `theme.color(literal)` (Formatting.swift).
// Màu lấy từ measure KHÔNG nằm ở đây theo từng điểm: mapper đã đưa vào `DataCell.fillColor/fontColor/backColor`.
// Ở đây chỉ ghi lại "thuộc tính nào lấy từ measure nào" (`measureDriven`) để bộ đọc truy vấn thêm cột IGNORE.
import Foundation
import PBIXKit

/// Đơn vị hiển thị (`labelDisplayUnits`): 0 = Tự động, 1 = Không, 1000 = K, 1e6 = M, 1e9 = bn, 1e12 = T.
enum DisplayUnits: Hashable, Sendable {
    case auto, none, thousands, millions, billions, trillions

    init(code: Double?) {
        switch code {
        case 1: self = .none
        case 1_000: self = .thousands
        case 1_000_000: self = .millions
        case 1_000_000_000: self = .billions
        case 1_000_000_000_000: self = .trillions
        default: self = .auto
        }
    }
}

/// Thuộc tính định dạng lấy giá trị từ một measure (`{"solid":{"color":{"expr":{"Measure":…}}}}` hoặc icon).
struct MeasureDrivenProperty: Hashable, Sendable {
    var object: String            // "dataPoint", "labels", "values"
    var property: String          // "fill", "color", "fontColor", "backColor", "icon"
    /// Measure mà thuộc tính áp vào (selector.metadata), ví dụ "Fact_Loan.Bad_Debt_Ratio_Count". nil = mọi giá trị.
    var target: String?
    /// Measure nguồn, ví dụ ("Fact_Loan", "NPL Group Color").
    var sourceTable: String
    var sourceMeasure: String
}

/// Thang màu (`FillRule.linearGradient2/3`) cho tô nền/chữ theo giá trị.
struct GradientRule: Hashable, Sendable {
    var property: String          // "backColor" hoặc "fontColor"
    var target: String?           // selector.metadata
    var inputTable: String
    var inputMeasure: String
    var minColor: ReportLiteral
    var midColor: ReportLiteral?
    var maxColor: ReportLiteral
    /// `nullColoringStrategy`: "asZero", "asBlank"…
    var nullStrategy: String?
}

struct DataLabelsFormat: Hashable, Sendable {
    var show: Bool?
    var fontSize: Double?
    var color: ReportLiteral?
    var bold: Bool?
    var displayUnits: DisplayUnits = .auto
    var precision: Int?
    /// Donut: `labelStyle` ("Category", "Data value", "Percent of total", "Category, data value"…).
    var labelStyle: String?
}

struct CategoryLabelsFormat: Hashable, Sendable {
    var show: Bool?
    var fontSize: Double?
    var color: ReportLiteral?
}

struct LegendFormat: Hashable, Sendable {
    var show: Bool?
    /// "Top", "Bottom", "Left", "Right", "TopCenter", "BottomCenter"…
    var position: String?
    var fontSize: Double?
}

struct ValueAxisFormat: Hashable, Sendable {
    var start: Double?
    var end: Double?
    var displayUnits: DisplayUnits = .auto
    var precision: Int?
    var secondaryStart: Double?
    var secondaryEnd: Double?
    var secondaryDisplayUnits: DisplayUnits = .auto
    var secondaryPrecision: Int?
}

struct CategoryAxisFormat: Hashable, Sendable {
    var fontSize: Double?
    /// "Categorical" hoặc "Scalar" (trục liên tục; line chart D1 dùng Scalar).
    var axisType: String?
}

struct DataPointFormat: Hashable, Sendable {
    /// Màu mặc định của mọi điểm (dataPoint.fill không có selector).
    var defaultFill: ReportLiteral?
    /// Màu theo measure (selector chỉ có `metadata`), khoá là queryRef measure.
    var fillByMeasure: [String: ReportLiteral] = [:]
    /// Màu theo giá trị danh mục/series (selector `scopeId` = Comparison), khoá là (queryRef cột, giá trị).
    var fillByValue: [ScopedValue: ReportLiteral] = [:]
}

struct ScopedValue: Hashable, Sendable {
    /// "Bảng.cột", ví dụ "Dim_Loan_Profile.status_vn".
    var column: String
    var value: ReportLiteral
}

struct MatrixFormat: Hashable, Sendable {
    var columnHeaderFontSize: Double?
    var rowHeaderFontSize: Double?
    var valuesFontSize: Double?
    var rowPadding: Double?
    var autoSizeColumnWidth: Bool?
    /// Độ rộng cột theo queryRef (`columnWidth` với selector.metadata).
    var columnWidths: [String: Double] = [:]
    var rowSubtotals: Bool?
    var columnSubtotals: Bool?
}

struct SlicerFormat: Hashable, Sendable {
    /// "Dropdown", "Basic" (danh sách), "Tile"…
    var mode: String?
    var headerShow: Bool?
    var headerFontColor: ReportLiteral?
    var headerTextSize: Double?
}

struct AnalyticsFormat: Hashable, Sendable {
    var trendShow: Bool?
    var forecastShow: Bool?
    var forecastDisplayName: String?
    /// Tham số `transform.parameters` của forecast: "Unit", "ForecastLength", "IgnoreLast", "ConfidenceLevel".
    var forecastParameters: [String: Double] = [:]
}

struct ShapeMapFormat: Hashable, Sendable {
    /// Tên tài nguyên bản đồ, ví dụ "usa.states.topo" (nằm trong `Report/StaticResources/SharedResources/Shapemaps/`).
    var mapResource: String?
    /// "albersUsa", "mercator"…
    var projection: String?
    var defaultColor: ReportLiteral?
    var defaultShow: Bool?
}

struct VisualFormat: Hashable, Sendable {
    var dataLabels = DataLabelsFormat()
    var categoryLabels = CategoryLabelsFormat()
    var legend = LegendFormat()
    var valueAxis = ValueAxisFormat()
    var categoryAxis = CategoryAxisFormat()
    var dataPoint = DataPointFormat()
    var matrix = MatrixFormat()
    var slicer = SlicerFormat()
    var analytics = AnalyticsFormat()
    var shapeMap = ShapeMapFormat()
    var measureDriven: [MeasureDrivenProperty] = []
    var gradients: [GradientRule] = []

    init() {}

    /// Đọc từ `visual.objects`.
    init(objects o: ObjectProperties) {
        dataLabels = DataLabelsFormat(
            show: o.bool("labels", "show"), fontSize: o.number("labels", "fontSize"), color: o.color("labels", "color"),
            bold: o.bool("labels", "bold"), displayUnits: DisplayUnits(code: o.number("labels", "labelDisplayUnits")),
            precision: o.number("labels", "labelPrecision").map { Int($0) }, labelStyle: o.string("labels", "labelStyle"))
        // Donut ghi đơn vị/độ chính xác của giá trị ở object "value".
        if o.has("value") {
            dataLabels.displayUnits = DisplayUnits(code: o.number("value", "labelDisplayUnits"))
            dataLabels.precision = o.number("value", "labelPrecision").map { Int($0) } ?? dataLabels.precision
        }
        categoryLabels = CategoryLabelsFormat(
            show: o.bool("categoryLabels", "show"), fontSize: o.number("categoryLabels", "fontSize"),
            color: o.color("categoryLabels", "color"))
        legend = LegendFormat(show: o.bool("legend", "show"), position: o.string("legend", "position"),
                              fontSize: o.number("legend", "fontSize"))
        valueAxis = ValueAxisFormat(
            start: o.number("valueAxis", "start"), end: o.number("valueAxis", "end"),
            displayUnits: DisplayUnits(code: o.number("valueAxis", "labelDisplayUnits")),
            precision: o.number("valueAxis", "labelPrecision").map { Int($0) },
            secondaryStart: o.number("valueAxis", "secStart"), secondaryEnd: o.number("valueAxis", "secEnd"),
            secondaryDisplayUnits: DisplayUnits(code: o.number("valueAxis", "secLabelDisplayUnits")),
            secondaryPrecision: o.number("valueAxis", "secLabelPrecision").map { Int($0) })
        categoryAxis = CategoryAxisFormat(fontSize: o.number("categoryAxis", "fontSize"),
                                          axisType: o.string("categoryAxis", "axisType"))
        matrix = MatrixFormat(
            columnHeaderFontSize: o.number("columnHeaders", "fontSize"), rowHeaderFontSize: o.number("rowHeaders", "fontSize"),
            valuesFontSize: Self.firstNumber(o, "values", "fontSize"), rowPadding: o.number("grid", "rowPadding"),
            autoSizeColumnWidth: o.bool("columnHeaders", "autoSizeColumnWidth"),
            columnWidths: Self.columnWidths(o), rowSubtotals: o.bool("subTotals", "rowSubtotals"),
            columnSubtotals: o.bool("subTotals", "columnSubtotals"))
        slicer = SlicerFormat(mode: o.string("data", "mode"), headerShow: o.bool("header", "show"),
                              headerFontColor: o.color("header", "fontColor"), headerTextSize: o.number("header", "textSize"))
        analytics = AnalyticsFormat(trendShow: o.bool("trend", "show"), forecastShow: o.bool("forecast", "show"),
                                    forecastDisplayName: o.string("forecast", "displayName"),
                                    forecastParameters: Self.forecastParameters(o))
        shapeMap = ShapeMapFormat(
            mapResource: o.raw("shape", "map")?["geoJson"]?["name"]?["expr"].flatMap { ReportLiteral(expression: $0)?.string },
            projection: o.string("shape", "projectionEnum"), defaultColor: o.color("defaultColors", "defaultColor"),
            defaultShow: o.bool("defaultColors", "defaultShow"))
        dataPoint = Self.dataPoints(o)
        (measureDriven, gradients) = Self.conditional(o)
    }

    // MARK: - Đọc chi tiết

    private static func instances(_ o: ObjectProperties, _ object: String) -> [JSONValue] {
        o.json[object]?.array ?? []
    }

    /// Giá trị đầu tiên có trong mọi instance (matrix ghi fontSize của values ở instance không selector, sau instance có selector).
    private static func firstNumber(_ o: ObjectProperties, _ object: String, _ property: String) -> Double? {
        for item in instances(o, object) {
            if let n = ReportLiteral(expression: item["properties"]?[property]?["expr"])?.number { return n }
        }
        return nil
    }

    private static func columnWidths(_ o: ObjectProperties) -> [String: Double] {
        var result: [String: Double] = [:]
        for item in instances(o, "columnWidth") {
            guard let key = item["selector"]?["metadata"]?.string,
                  let n = ReportLiteral(expression: item["properties"]?["value"]?["expr"])?.number else { continue }
            result[key] = n
        }
        return result
    }

    private static func forecastParameters(_ o: ObjectProperties) -> [String: Double] {
        var result: [String: Double] = [:]
        for item in instances(o, "forecast") {
            for p in item["properties"]?["transform"]?["parameters"]?.array ?? [] {
                if let name = p["Name"]?.string, let n = ReportLiteral(expression: p)?.number { result[name] = n }
            }
        }
        return result
    }

    private static func dataPoints(_ o: ObjectProperties) -> DataPointFormat {
        var f = DataPointFormat()
        for item in instances(o, "dataPoint") {
            guard let expr = item["properties"]?["fill"]?["solid"]?["color"]?["expr"],
                  let color = ReportLiteral(expression: expr) else { continue }   // màu từ measure: xem `conditional`
            let selector = item["selector"]
            if let scope = selector?["data"]?[0]?["scopeId"]?["Comparison"],
               let entity = scope["Left"]?["Column"]?["Expression"]?["SourceRef"]?["Entity"]?.string,
               let property = scope["Left"]?["Column"]?["Property"]?.string,
               let value = ReportLiteral(expression: scope["Right"]) {
                f.fillByValue[ScopedValue(column: "\(entity).\(property)", value: value)] = color
            } else if let metadata = selector?["metadata"]?.string {
                f.fillByMeasure[metadata] = color
            } else {
                f.defaultFill = color
            }
        }
        return f
    }

    private static func measureRef(_ json: JSONValue?) -> (String, String)? {
        guard let m = json?["Measure"], let table = m["Expression"]?["SourceRef"]?["Entity"]?.string,
              let name = m["Property"]?.string else { return nil }
        return (table, name)
    }

    private static func conditional(_ o: ObjectProperties) -> ([MeasureDrivenProperty], [GradientRule]) {
        var driven: [MeasureDrivenProperty] = []
        var gradients: [GradientRule] = []
        for (object, list) in o.json.object.sorted(by: { $0.key < $1.key }) {
            for item in list.array {
                let target = item["selector"]?["metadata"]?.string
                for (property, value) in (item["properties"]?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
                    let expr = value["solid"]?["color"]?["expr"] ?? value["value"]?["expr"]
                    if let (table, name) = measureRef(expr) {
                        driven.append(MeasureDrivenProperty(object: object, property: property, target: target,
                                                            sourceTable: table, sourceMeasure: name))
                    } else if let rule = expr?["FillRule"], let (table, name) = measureRef(rule["Input"]) {
                        let g = rule["FillRule"]?["linearGradient3"] ?? rule["FillRule"]?["linearGradient2"]
                        guard let minC = ReportLiteral(expression: g?["min"]?["color"]),
                              let maxC = ReportLiteral(expression: g?["max"]?["color"]) else { continue }
                        gradients.append(GradientRule(
                            property: property, target: target, inputTable: table, inputMeasure: name, minColor: minC,
                            midColor: ReportLiteral(expression: g?["mid"]?["color"]), maxColor: maxC,
                            nullStrategy: ReportLiteral(expression: g?["nullColoringStrategy"]?["strategy"])?.string))
                    }
                }
            }
        }
        return (driven, gradients)
    }
}
