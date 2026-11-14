import AppKit
import Charts
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

enum CartesianKind: Hashable, Sendable {
    case clusteredBar, clusteredColumn, stackedColumn, hundredPercentStackedColumn, line, comboClustered, comboStacked
    /// Vùng chồng lên nhau và vùng xếp chồng (VM-D15 mục 4): vẽ như đường kèm tô phần dưới.
    case area, stackedArea, hundredPercentStackedArea
    
    var isLineLike: Bool { self == .line || isArea }
    var isArea: Bool { self == .area || self == .stackedArea || self == .hundredPercentStackedArea }
    var isStackedArea: Bool { self == .stackedArea || self == .hundredPercentStackedArea }

    init?(visualType: String) {
        switch visualType {
        case "clusteredBarChart", "clusteredBar":
            self = .clusteredBar
        case "clusteredColumnChart", "clusteredColumn":
            self = .clusteredColumn
        case "stackedColumnChart", "stackedColumn", "columnChart":   // Desktop ghi `columnChart` cho cột xếp chồng (VM-D3)
            self = .stackedColumn
        case "hundredPercentStackedColumnChart", "hundredPercentStackedColumn":
            self = .hundredPercentStackedColumn
        case "lineChart", "line":
            self = .line
        case "areaChart":
            self = .area
        case "stackedAreaChart":
            self = .stackedArea
        case "hundredPercentStackedAreaChart":
            self = .hundredPercentStackedArea
        case "lineClusteredColumnComboChart", "lineClusteredColumnCombo", "comboClustered":
            self = .comboClustered
        case "lineStackedColumnComboChart", "lineStackedColumnCombo", "comboStacked":
            self = .comboStacked
        default:
            return nil
        }
    }
}

// MARK: - Stack Layout

struct StackSegment: Hashable, Sendable {
    var seriesIndex: Int
    var rawValue: Double?
    var y0: Double
    var y1: Double
    var isBlank: Bool
    
    init(seriesIndex: Int, rawValue: Double?, y0: Double, y1: Double, isBlank: Bool) {
        self.seriesIndex = seriesIndex
        self.rawValue = rawValue
        self.y0 = y0
        self.y1 = y1
        self.isBlank = isBlank
    }
    
    var length: Double { abs(y1 - y0) }
    var percentage: Double { length }
}

enum StackLayout {
    static func segments(values: [Double?], isNormalized: Bool = false) -> [StackSegment] {
        var result: [StackSegment] = []
        var posAccum = 0.0
        var negAccum = 0.0
        
        for (i, val) in values.enumerated() {
            guard let v = val else {
                result.append(StackSegment(seriesIndex: i, rawValue: nil, y0: 0, y1: 0, isBlank: true))
                continue
            }
            if v > 0 {
                let start = posAccum
                let end = posAccum + v
                posAccum = end
                result.append(StackSegment(seriesIndex: i, rawValue: v, y0: start, y1: end, isBlank: false))
            } else if v < 0 {
                let start = negAccum
                let end = negAccum + v
                negAccum = end
                result.append(StackSegment(seriesIndex: i, rawValue: v, y0: start, y1: end, isBlank: false))
            } else {
                result.append(StackSegment(seriesIndex: i, rawValue: 0, y0: 0, y1: 0, isBlank: false))
            }
        }
        
        if isNormalized {
            let totalPos = posAccum
            let totalNeg = abs(negAccum)
            for idx in 0..<result.count {
                if result[idx].isBlank { continue }
                guard let val = result[idx].rawValue else { continue }
                if val > 0 && totalPos > 0 {
                    result[idx].y0 = result[idx].y0 / totalPos
                    result[idx].y1 = result[idx].y1 / totalPos
                } else if val < 0 && totalNeg > 0 {
                    result[idx].y0 = result[idx].y0 / totalNeg
                    result[idx].y1 = result[idx].y1 / totalNeg
                }
            }
        }
        
        return result
    }
    
    static func segments(cells: [DataCell], isNormalized: Bool = false) -> [StackSegment] {
        let vals = cells.map { NumberDisplay.numericValue($0.value) }
        return segments(values: vals, isNormalized: isNormalized)
    }
}

// MARK: - Color Resolution

extension ReportLiteral {
    init(daxValue: Value) {
        switch daxValue {
        case .string(let s):
            self = .string(s)
        case .integer(let i):
            self = .number(Double(i))
        case .double(let d):
            self = .number(d)
        case .currency(let c):
            self = .number(Double(c) / 10_000)
        case .boolean(let b):
            self = .bool(b)
        case .blank:
            self = .null
        case .dateTime(let dt):
            self = .string(dt.description)
        }
    }
}

enum ChartColorResolver {
    static func resolveLiteral(
        cell: DataCell,
        categoryKey: CategoryKey? = nil,
        categoryLevels: [FieldInfo] = [],
        seriesValue: Value? = nil,
        seriesField: FieldInfo? = nil,
        measure: FieldInfo? = nil,
        format: VisualFormat
    ) -> ReportLiteral? {
        // 1. DataCell.fillColor
        if let fill = cell.fillColor {
            return .string(fill)
        }
        
        // 2. format.dataPoint.fillByValue
        if let sField = seriesField, let sVal = seriesValue {
            let lit = ReportLiteral(daxValue: sVal)
            let scoped = ScopedValue(column: sField.queryRef, value: lit)
            if let matched = format.dataPoint.fillByValue[scoped] {
                return matched
            }
        }
        if let catKey = categoryKey {
            for (level, val) in zip(categoryLevels, catKey.values) {
                let lit = ReportLiteral(daxValue: val)
                let scoped = ScopedValue(column: level.queryRef, value: lit)
                if let matched = format.dataPoint.fillByValue[scoped] {
                    return matched
                }
            }
        }
        
        // 3. format.dataPoint.fillByMeasure[queryRef]
        if let m = measure, let matched = format.dataPoint.fillByMeasure[m.queryRef] {
            return matched
        }
        
        // 4. defaultFill
        if let def = format.dataPoint.defaultFill {
            return def
        }
        
        return nil
    }
    
    static func resolveColor(
        cell: DataCell,
        categoryKey: CategoryKey? = nil,
        categoryLevels: [FieldInfo] = [],
        seriesValue: Value? = nil,
        seriesField: FieldInfo? = nil,
        seriesIndex: Int = 0,
        hasSeries: Bool = false,
        measure: FieldInfo? = nil,
        measureIndex: Int = 0,
        format: VisualFormat,
        theme: ReportTheme
    ) -> Color {
        if let lit = resolveLiteral(
            cell: cell,
            categoryKey: categoryKey,
            categoryLevels: categoryLevels,
            seriesValue: seriesValue,
            seriesField: seriesField,
            measure: measure,
            format: format
        ), let col = theme.color(lit) {
            return col
        }
        let idx = hasSeries ? seriesIndex : measureIndex
        return theme.dataColor(idx)
    }
}

// MARK: - Prepared Chart Data

struct ChartBarDatum: Identifiable, Sendable {
    var id: String { "\(category)-\(series)-\(measureIndex)" }
    var pointID: DataPointID
    var category: String
    var series: String
    var measureIndex: Int
    var value: Double
    var color: Color
    var opacity: Double
    var highlightValue: Double?
    var dataLabel: String?
}

struct ChartStackSegmentDatum: Identifiable, Sendable {
    var id: String { "\(category)-\(seriesIndex)" }
    var pointID: DataPointID
    var category: String
    var seriesIndex: Int
    var seriesName: String
    var y0: Double
    var y1: Double
    var value: Double
    var color: Color
    var opacity: Double
    var highlightValue: Double?
    var dataLabel: String?
}

struct ChartLinePointDatum: Identifiable, Sendable {
    var id: String { "\(seriesName)-\(category)" }
    var pointID: DataPointID
    var category: String
    var seriesName: String
    var value: Double
    var rawValue: Double
    var opacity: Double
    var dataLabel: String?
    /// Mép dưới của phần tô (biểu đồ vùng): 0 hoặc mép dưới của lớp bên dưới khi xếp chồng.
    var base: Double = 0
}

struct ChartLineSeriesDatum: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var color: Color
    var points: [ChartLinePointDatum]
}

struct ChartTrendPointDatum: Identifiable, Sendable {
    var id: String { category }
    var category: String
    var y: Double
}

/// Một điểm dự báo: đường `y` và dải tin cậy `lower…upper`. Điểm đầu nằm đúng điểm dữ liệu cuối (dải rộng 0) để dải nối liền.
struct ChartForecastDatum: Identifiable, Sendable {
    var id: String { category }
    var category: String
    var y: Double
    var lower: Double
    var upper: Double
}

struct PreparedChartLayout: Sendable {
    var isEmpty: Bool
    var kind: CartesianKind
    var categories: [String]
    
    // Bar
    var bars: [ChartBarDatum]
    var barXTicks: [Double]
    var barXLabels: [String]
    var barXDomain: ClosedRange<Double>
    /// Vạch cuối cách mép phải miền dưới 8% (nhãn dễ bị cắt).
    var barLastLabelNearEdge: Bool {
        guard let last = barXTicks.last, barXDomain.upperBound > barXDomain.lowerBound else { return false }
        return (barXDomain.upperBound - last) / (barXDomain.upperBound - barXDomain.lowerBound) < 0.12
    }
    
    // Column (Clustered)
    var columns: [ChartBarDatum]
    var columnYTicks: [Double]
    var columnYLabels: [String]
    var columnYDomain: ClosedRange<Double>
    
    // Stacked
    var stackSegments: [ChartStackSegmentDatum]
    var stackYTicks: [Double]
    var stackYLabels: [String]
    var stackYDomain: ClosedRange<Double>
    
    // Line & Combo
    var lineSeries: [ChartLineSeriesDatum]
    var trendPoints: [ChartTrendPointDatum]
    var showTrend: Bool
    var forecastPoints: [ChartForecastDatum]
    /// Trục Y theo thang log (`valueAxis.logAxisScale`, VM-D17).
    var useLogScale: Bool
    var isScalarAxis: Bool
    var scalarXTicks: [String]
    var scalarXLabels: [String: String]
    
    // Combo secondary axis
    var hasSecondaryAxis: Bool
    var y2Ticks: [Double]
    var y2Labels: [String]
    var scaledY2Ticks: [Double]
    
    // Legend
    var showLegend: Bool
    var legendItems: [LegendItem]
    var legendPosition: String
    var legendFontSize: Double?
    
    // Fonts & Labels
    var categoryFontSize: CGFloat
    /// Có tô sáng chéo: mọi thanh/cột vẽ nhạt (0,4), phần tô sáng phủ lên màu đậm (xf-D2.png).
    var hasHighlights: Bool
    var dataLabelFontSize: CGFloat
    var dataLabelBold: Bool
    var dataLabelColor: Color
    
    init(data: CategoricalData, kind: CartesianKind, context: VisualRenderContext) {
        self.kind = kind
        let numCats = data.categories.count
        self.isEmpty = (numCats == 0)
        
        let format = context.format
        let theme = context.theme
        let sel = context.selection
        
        let catFontSize = ReportUnits.pixels(fromPoints: format.categoryAxis.fontSize ?? ChartDefaults.axisFontSize)
        self.categoryFontSize = catFontSize
        self.hasHighlights = data.highlights != nil
        self.dataLabelFontSize = ReportUnits.pixels(fromPoints: format.dataLabels.fontSize ?? 9)
        self.dataLabelBold = format.dataLabels.bold ?? false
        self.dataLabelColor = theme.color(format.dataLabels.color) ?? (Color(hex: "#252423") ?? .primary)
        
        // Giá trị series cũng hiện theo định dạng của cột series.
        func seriesText(_ value: Value) -> String { data.seriesField?.text(value) ?? value.asText() }

        var catStrings: [String] = []
        for cat in data.categories {
            let str = cat.values.enumerated().map { data.categoryLevels.text($1, at: $0) }.joined(separator: " ")
            catStrings.append(str.isEmpty ? "Blank" : str)
        }
        self.categories = catStrings
        
        let hasSeries = (data.seriesField != nil && !data.series.isEmpty)
        let numSeries = Swift.max(1, data.series.count)
        
        // Helper to construct DataPointID
        func makePointID(c: Int, s: Int) -> DataPointID {
            var dict: [String: Value] = [:]
            for (levelIdx, level) in data.categoryLevels.enumerated() {
                if c < data.categories.count, levelIdx < data.categories[c].values.count {
                    dict[level.queryRef] = data.categories[c].values[levelIdx]
                }
            }
            if let sField = data.seriesField, s < data.series.count {
                dict[sField.queryRef] = data.series[s]
            }
            return DataPointID(dict)
        }
        
        func pointOpacity(ptID: DataPointID) -> Double {
            if sel.isEmpty { return 1.0 }
            return sel.contains(ptID) ? 1.0 : 0.4
        }
        
        // Legend setup
        let yMeasureIndices = data.measures.indices.filter {
            let r = data.measures[$0].role
            return r == "Y" || r == "Y2" || r == "Values"
        }
        let shouldShowLegend = (format.legend.show ?? true) && (hasSeries || yMeasureIndices.count > 1)
        self.showLegend = shouldShowLegend
        self.legendPosition = format.legend.position ?? ChartDefaults.legendPosition
        self.legendFontSize = format.legend.fontSize
        
        var legItems: [LegendItem] = []
        if hasSeries {
            for (sIdx, sVal) in data.series.enumerated() {
                let cellSample = data.values.first?.indices.contains(sIdx) == true && data.values.first?[sIdx].isEmpty == false ? data.values[0][sIdx][0] : DataCell.blank
                let col = ChartColorResolver.resolveColor(
                    cell: cellSample,
                    seriesValue: sVal,
                    seriesField: data.seriesField,
                    seriesIndex: sIdx,
                    hasSeries: true,
                    format: format,
                    theme: theme
                )
                legItems.append(LegendItem(id: "s-\(sIdx)", name: seriesText(sVal), color: col))
            }
            // Combo có Series: đường Y2 cũng có mục legend, màu tiếp sau các series (ảnh page-D3).
            if kind == .comboClustered || kind == .comboStacked {
                for (mOrder, mIdx) in data.measureIndices(role: "Y2").enumerated() {
                    let mField = data.measures[mIdx]
                    let col = ChartColorResolver.resolveColor(
                        cell: .blank, measure: mField, measureIndex: data.series.count + mOrder, format: format, theme: theme)
                    legItems.append(LegendItem(id: "m-\(mIdx)", name: mField.displayName, color: col))
                }
            }
        } else if yMeasureIndices.count > 1 {
            for (mOrder, mIdx) in yMeasureIndices.enumerated() {
                let mField = data.measures[mIdx]
                let cellSample = data.values.indices.contains(mIdx) && data.values[mIdx].first?.isEmpty == false ? data.values[mIdx][0][0] : DataCell.blank
                let col = ChartColorResolver.resolveColor(
                    cell: cellSample,
                    measure: mField,
                    measureIndex: mOrder,
                    format: format,
                    theme: theme
                )
                legItems.append(LegendItem(id: "m-\(mIdx)", name: mField.displayName, color: col))
            }
        }
        self.legendItems = legItems
        
        // Scalar axis setup
        let isScalar = (format.categoryAxis.axisType == "Scalar")
        self.isScalarAxis = isScalar
        var scXTicks: [String] = []
        var scXLabels: [String: String] = [:]
        if isScalar {
            var seenYears = Set<String>()
            for (index, catStr) in catStrings.enumerated() {
                // Năm lấy từ giá trị gốc (chuỗi hiển thị có thể là "Jan 2013" hay "1/1/2013").
                let raw = data.categories[index].values.first
                let yr = raw.flatMap { value -> String? in
                    if case .dateTime(let serial) = value { return String(DateDisplay.civil(serial: serial).year) }
                    return nil
                } ?? String(catStr.prefix(4))
                if !seenYears.contains(yr) {
                    seenYears.insert(yr)
                    scXTicks.append(catStr)
                    scXLabels[catStr] = yr
                }
            }
        }
        self.scalarXTicks = scXTicks
        self.scalarXLabels = scXLabels
        
        // Measures division by role
        let roleYIndices = data.measureIndices(role: "Y").isEmpty ? data.measureIndices(role: "Values") : data.measureIndices(role: "Y")
        let roleY2Indices = data.measureIndices(role: "Y2")
        
        // Initialize default empty values
        var computedBars: [ChartBarDatum] = []
        var computedColumns: [ChartBarDatum] = []
        var computedSegments: [ChartStackSegmentDatum] = []
        var computedLines: [ChartLineSeriesDatum] = []
        var computedTrend: [ChartTrendPointDatum] = []
        
        var minValY1 = 0.0
        var maxValY1 = 0.0
        var minValY2 = 0.0
        var maxValY2 = 0.0
        
        // MARK: 1. Clustered Bar
        if kind == .clusteredBar {
            let mList = roleYIndices.isEmpty ? Array(data.measures.indices.prefix(1)) : roleYIndices
            for (mOrder, mIdx) in mList.enumerated() {
                let mField = data.measures[mIdx]
                let seriesLimit = hasSeries ? numSeries : 1
                for sIdx in 0..<seriesLimit {
                    let sVal = hasSeries && sIdx < data.series.count ? data.series[sIdx] : nil
                    let sName = sVal.map { seriesText($0) } ?? (hasSeries ? "" : mField.displayName)
                    for cIdx in 0..<numCats {
                        let cell = data.cell(measure: mIdx, series: sIdx, category: cIdx)
                        guard let v = NumberDisplay.numericValue(cell.value) else { continue }
                        let ptID = makePointID(c: cIdx, s: sIdx)
                        let col = ChartColorResolver.resolveColor(
                            cell: cell,
                            categoryKey: cIdx < data.categories.count ? data.categories[cIdx] : nil,
                            categoryLevels: data.categoryLevels,
                            seriesValue: sVal,
                            seriesField: data.seriesField,
                            seriesIndex: sIdx,
                            hasSeries: hasSeries,
                            measure: mField,
                            measureIndex: mOrder,
                            format: format,
                            theme: theme
                        )
                        var hlVal: Double? = nil
                        if let hlCells = data.highlights, mIdx < hlCells.count, sIdx < hlCells[mIdx].count, cIdx < hlCells[mIdx][sIdx].count {
                            hlVal = NumberDisplay.numericValue(hlCells[mIdx][sIdx][cIdx].value)
                        }
                        
                        let labelText: String?
                        if format.dataLabels.show == true {
                            labelText = DataLabels.text(cell: cell, format: format.dataLabels)
                        } else {
                            labelText = nil
                        }
                        
                        minValY1 = Swift.min(minValY1, v)
                        maxValY1 = Swift.max(maxValY1, v)
                        if let hl = hlVal {
                            minValY1 = Swift.min(minValY1, hl)
                            maxValY1 = Swift.max(maxValY1, hl)
                        }
                        
                        computedBars.append(ChartBarDatum(
                            pointID: ptID,
                            category: catStrings[cIdx],
                            series: sName,
                            measureIndex: mIdx,
                            value: v,
                            color: col,
                            opacity: pointOpacity(ptID: ptID),
                            highlightValue: hlVal,
                            dataLabel: labelText
                        ))
                    }
                }
            }
        }
        
        // MARK: 2. Clustered Column
        if kind == .clusteredColumn || kind == .comboClustered {
            let mList = roleYIndices.isEmpty ? Array(data.measures.indices.prefix(1)) : roleYIndices
            for (mOrder, mIdx) in mList.enumerated() {
                let mField = data.measures[mIdx]
                let seriesLimit = hasSeries ? numSeries : 1
                for sIdx in 0..<seriesLimit {
                    let sVal = hasSeries && sIdx < data.series.count ? data.series[sIdx] : nil
                    let sName = sVal.map { seriesText($0) } ?? (hasSeries ? "" : mField.displayName)
                    for cIdx in 0..<numCats {
                        let cell = data.cell(measure: mIdx, series: sIdx, category: cIdx)
                        guard let v = NumberDisplay.numericValue(cell.value) else { continue }
                        let ptID = makePointID(c: cIdx, s: sIdx)
                        let col = ChartColorResolver.resolveColor(
                            cell: cell,
                            categoryKey: cIdx < data.categories.count ? data.categories[cIdx] : nil,
                            categoryLevels: data.categoryLevels,
                            seriesValue: sVal,
                            seriesField: data.seriesField,
                            seriesIndex: sIdx,
                            hasSeries: hasSeries,
                            measure: mField,
                            measureIndex: mOrder,
                            format: format,
                            theme: theme
                        )
                        var hlVal: Double? = nil
                        if let hlCells = data.highlights, mIdx < hlCells.count, sIdx < hlCells[mIdx].count, cIdx < hlCells[mIdx][sIdx].count {
                            hlVal = NumberDisplay.numericValue(hlCells[mIdx][sIdx][cIdx].value)
                        }
                        
                        let labelText: String?
                        if format.dataLabels.show == true {
                            labelText = DataLabels.text(cell: cell, format: format.dataLabels)
                        } else {
                            labelText = nil
                        }
                        
                        minValY1 = Swift.min(minValY1, v)
                        maxValY1 = Swift.max(maxValY1, v)
                        if let hl = hlVal {
                            minValY1 = Swift.min(minValY1, hl)
                            maxValY1 = Swift.max(maxValY1, hl)
                        }
                        
                        computedColumns.append(ChartBarDatum(
                            pointID: ptID,
                            category: catStrings[cIdx],
                            series: sName,
                            measureIndex: mIdx,
                            value: v,
                            color: col,
                            opacity: pointOpacity(ptID: ptID),
                            highlightValue: hlVal,
                            dataLabel: labelText
                        ))
                    }
                }
            }
        }
        
        // MARK: 3. Stacked Column & 100% Stacked & Combo Stacked
        if kind == .stackedColumn || kind == .hundredPercentStackedColumn || kind == .comboStacked {
            let isNorm = (kind == .hundredPercentStackedColumn)
            let mIdx = roleYIndices.first ?? 0
            let mField = data.measures.indices.contains(mIdx) ? data.measures[mIdx] : FieldInfo(queryRef: "", displayName: "", role: "Y", formatString: nil, isMeasure: true)
            let seriesCount = hasSeries ? numSeries : Swift.max(1, roleYIndices.count)
            
            for cIdx in 0..<numCats {
                var cellVals: [Double?] = []
                var cells: [DataCell] = []
                for sIdx in 0..<seriesCount {
                    let cell = hasSeries ? data.cell(measure: mIdx, series: sIdx, category: cIdx) : data.cell(measure: roleYIndices[sIdx], series: 0, category: cIdx)
                    cells.append(cell)
                    cellVals.append(NumberDisplay.numericValue(cell.value))
                }
                
                let segs = StackLayout.segments(values: cellVals, isNormalized: isNorm)
                for (sIdx, seg) in segs.enumerated() {
                    guard !seg.isBlank, let v = seg.rawValue, seg.y1 != seg.y0 else { continue }
                    let sVal = hasSeries && sIdx < data.series.count ? data.series[sIdx] : nil
                    let sName = sVal.map { seriesText($0) } ?? (hasSeries ? "" : (sIdx < roleYIndices.count ? data.measures[roleYIndices[sIdx]].displayName : ""))
                    let ptID = makePointID(c: cIdx, s: sIdx)
                    let cell = cells[sIdx]
                    let col = ChartColorResolver.resolveColor(
                        cell: cell,
                        categoryKey: cIdx < data.categories.count ? data.categories[cIdx] : nil,
                        categoryLevels: data.categoryLevels,
                        seriesValue: sVal,
                        seriesField: data.seriesField,
                        seriesIndex: sIdx,
                        hasSeries: hasSeries,
                        measure: mField,
                        measureIndex: sIdx,
                        format: format,
                        theme: theme
                    )
                    
                    var hlVal: Double? = nil
                    if let hlCells = data.highlights, mIdx < hlCells.count, sIdx < hlCells[mIdx].count, cIdx < hlCells[mIdx][sIdx].count {
                        hlVal = NumberDisplay.numericValue(hlCells[mIdx][sIdx][cIdx].value)
                    }
                    
                    let labelText: String?
                    if format.dataLabels.show == true {
                        labelText = DataLabels.text(cell: cell, is100Percent: isNorm, ratio: seg.length, format: format.dataLabels)
                    } else {
                        labelText = nil
                    }
                    
                    minValY1 = Swift.min(minValY1, seg.y0, seg.y1)
                    maxValY1 = Swift.max(maxValY1, seg.y0, seg.y1)
                    
                    computedSegments.append(ChartStackSegmentDatum(
                        pointID: ptID,
                        category: catStrings[cIdx],
                        seriesIndex: sIdx,
                        seriesName: sName,
                        y0: seg.y0,
                        y1: seg.y1,
                        value: v,
                        color: col,
                        opacity: pointOpacity(ptID: ptID),
                        highlightValue: hlVal,
                        dataLabel: labelText
                    ))
                }
            }
        }
        
        // MARK: 4. Lines (Line chart or Combo Y2)
        let hasY2 = (kind == .comboClustered || kind == .comboStacked) && !roleY2Indices.isEmpty
        let lineMeasureIndices = kind.isLineLike ? roleYIndices : roleY2Indices
        
        // Vùng: trục bắt đầu từ 0; vùng xếp chồng: miền lấy theo tổng các series ở mỗi danh mục.
        if kind.isArea {
            minValY1 = Swift.min(minValY1, 0)
            maxValY1 = Swift.max(maxValY1, 0)
        }
        var stackedTotals = [Double](repeating: 0, count: kind.isStackedArea ? numCats : 0)
        if kind.isStackedArea {
            for mIdx in roleYIndices {
                for sIdx in 0..<data.values[mIdx].count {
                    for cIdx in 0..<numCats {
                        if let v = NumberDisplay.numericValue(data.cell(measure: mIdx, series: sIdx, category: cIdx).value) { stackedTotals[cIdx] += v }
                    }
                }
            }
            maxValY1 = Swift.max(maxValY1, kind == .hundredPercentStackedArea ? 1 : (stackedTotals.max() ?? 0))
            minValY1 = Swift.min(minValY1, 0)
        }
        // If line chart, gather Y1 bounds from line measures
        if kind == .line || kind == .area {
            for mIdx in roleYIndices {
                let mValCount = data.values[mIdx].count
                for sIdx in 0..<mValCount {
                    for cIdx in 0..<numCats {
                        let cell = data.cell(measure: mIdx, series: sIdx, category: cIdx)
                        if let v = NumberDisplay.numericValue(cell.value) {
                            minValY1 = Swift.min(minValY1, v)
                            maxValY1 = Swift.max(maxValY1, v)
                        }
                    }
                }
            }
        }
        
        // If combo has Y2, gather raw Y2 bounds first
        if hasY2 {
            for mIdx in roleY2Indices {
                let mValCount = data.values[mIdx].count
                for sIdx in 0..<mValCount {
                    for cIdx in 0..<numCats {
                        let cell = data.cell(measure: mIdx, series: sIdx, category: cIdx)
                        if let v = NumberDisplay.numericValue(cell.value) {
                            minValY2 = Swift.min(minValY2, v)
                            maxValY2 = Swift.max(maxValY2, v)
                        }
                    }
                }
            }
        }
        
        // Dự báo (line chart có trục thời gian): thêm các tháng tương lai vào trục và mở rộng miền Y cho vừa dải tin cậy.
        var forecastRows: [ChartForecastDatum] = []
        if kind == .line, format.analytics.forecastShow == true, data.categoryLevels.count == 1,
           let yIdx = roleYIndices.first, data.series.count <= 1, numCats >= 6,
           case .dateTime(let lastSerial)? = data.categories.last?.values.first {
            let params = format.analytics.forecastParameters
            let length = max(1, Int(params["ForecastLength"] ?? 6))
            let ignore = max(0, Int(params["IgnoreLast"] ?? 0))
            let series = (0..<numCats).compactMap { NumberDisplay.numericValue(data.cell(measure: yIdx, series: 0, category: $0).value) }
            if series.count == numCats, numCats - ignore >= 6,
               let projected = Forecast.project(Array(series.dropLast(ignore)), length: length, confidence: params["ConfidenceLevel"] ?? 0.95) {
                let last = DateDisplay.civil(serial: lastSerial)
                let anchorY = series.last ?? 0
                if ignore == 0, let anchor = catStrings.last {
                    forecastRows.append(ChartForecastDatum(category: anchor, y: anchorY, lower: anchorY, upper: anchorY))
                }
                var futureCats: [String] = []
                var seenYears = Set(scXLabels.values)
                for (k, point) in projected.enumerated() {
                    let serial = DateDisplay.serial(year: last.year, month: last.month + ignore + k + 1, day: last.day)
                    let text = data.categoryLevels.text(.dateTime(serial), at: 0)
                    guard !catStrings.contains(text), !futureCats.contains(text) else { continue }
                    futureCats.append(text)
                    forecastRows.append(ChartForecastDatum(category: text, y: point.y, lower: point.lower, upper: point.upper))
                    minValY1 = Swift.min(minValY1, point.lower)
                    maxValY1 = Swift.max(maxValY1, point.upper)
                    let year = String(DateDisplay.civil(serial: serial).year)
                    if isScalar, seenYears.insert(year).inserted {
                        scXTicks.append(text)
                        scXLabels[text] = year
                    }
                }
                self.categories = catStrings + futureCats
                self.scalarXTicks = scXTicks
                self.scalarXLabels = scXLabels
            }
        }

        // Prepare Y1 and Y2 ticks
        // Định dạng trục: định dạng tĩnh của measure; không có thì lấy định dạng động của ô đầu tiên có giá trị (ví dụ "0%").
        func axisFormat(_ mIdx: Int?) -> String {
            guard let mIdx else { return "" }
            if let f = data.measures[mIdx].formatString, !f.isEmpty { return f }
            return data.values[mIdx].lazy.flatMap { $0 }.first { $0.formatString != nil }?.formatString ?? ""
        }
        let primaryFormatString = axisFormat(roleYIndices.first ?? (kind == .clusteredBar ? data.measures.indices.first : nil))
        let secondaryFormatString = axisFormat(roleY2Indices.first)
        
        // Thang log (VM-D17): vạch tại các luỹ thừa của 10 bao trọn giá trị dương; Desktop chọn đơn vị theo vạch giữa
        // (`$1M`, `$10M`, `$100M`, `$1,000M`). Không áp cho cột xếp chồng, vùng xếp chồng và combo xếp chồng.
        let logAllowed = format.valueAxis.logScale == true && !kind.isStackedArea && kind != .stackedColumn
            && kind != .hundredPercentStackedColumn && kind != .comboStacked
        let positives = logAllowed ? roleYIndices.flatMap { m in
            data.values[m].flatMap { $0 }.compactMap { NumberDisplay.numericValue($0.value) }.filter { $0 > 0 }
        } : []
        var y1Ticks: [Double]
        var y1Labels: [String]
        var logActive = false
        // Chiều cao (thanh ngang: độ rộng) vùng vẽ ước theo số đo Desktop (VM-D19): 0,92 × chiều cao visual − phần cố định 92 (có chú giải; 67 không có) − dải nhãn (khớp 233 và 190 ở visual cao 380, 104 ở cao 240 đo được) (tiêu đề, phụ đề, chú giải, lề) − dải nhãn trục
        // danh mục (nhãn ngang ≈ 18; nhãn xoay dọc: độ dài nhãn dài nhất đã cắt, cộng thanh cuộn 14). Thanh ngang: trục giá trị nằm ngang, không ước.
        let tickPlotHeight: Double? = {
            guard let size = context.visualSize, size.height > 0 else { return nil }
            if kind == .clusteredBar {
                // Thanh ngang: trục giá trị nằm ngang, vùng vẽ rộng = độ rộng visual − dải nhãn danh mục bên trái − lề (VM-D19).
                let longest = catStrings.map(\.count).max() ?? 0
                let labels = isScalar ? 30.0 : Swift.min(Double(size.width) * 0.25, Double(longest) * Double(catFontSize) * 0.6 + 10)
                return Swift.max(60, Double(size.width) - labels - 16)
            }
            let chrome = 67.0 + (shouldShowLegend ? 25.0 : 0.0)
            let longest = catStrings.map(\.count).max() ?? 0
            let plotWidth = Double(size.width) - 90
            let rotated = !isScalar && Double(longest) * Double(catFontSize) * 0.6 + 8 > 0 && plotWidth > 0
                && (Double(longest) * Double(catFontSize) * 0.6 + 8) * Double(catStrings.count) > plotWidth
            var band = Double(catFontSize) * 1.2 + 8
            if rotated {
                let fit = CategoryLabelFit(fontSize: catFontSize, chartHeight: CGFloat(size.height - 110))
                band = Double(Swift.min(longest, fit.maxLength)) * Double(catFontSize) * 0.55 + 14   // 0,55: khớp dải nhãn 68 đo được ở "Rủi ro thấu chi"
            }
            return Swift.max(40, 0.92 * Double(size.height) - chrome - band)
        }()
        var fittedY1: (lower: Double, upper: Double)?
        if let low = positives.min(), let high = positives.max() {
            y1Ticks = ChartAxis.logTicks(low: low, high: high)
            let middle = y1Ticks[y1Ticks.count / 2]
            y1Labels = ChartAxis.labels(ticks: y1Ticks, units: NumberDisplay.resolve(format.valueAxis.displayUnits, reference: middle),
                                        precision: format.valueAxis.precision ?? 0, formatString: primaryFormatString)   // Desktop không ghi số lẻ
            self.useLogScale = true
            logActive = true
        } else {
            if let plotHeight = tickPlotHeight, kind != .hundredPercentStackedArea {
                // Đường (không cột): trục không bắt đầu từ 0 khi dữ liệu nằm xa 0 (VM-D19), kể cả dải dự báo ở cận dưới.
                let lineValues = kind == .line ? roleYIndices.flatMap { m in data.values[m].flatMap { $0 }.compactMap { NumberDisplay.numericValue($0.value) } } : []
                let floatLow = format.valueAxis.start == nil && format.valueAxis.end == nil && format.valueAxis.logScale != true
                    ? ChartAxis.floatingLow(values: lineValues) : nil
                let fit = ChartAxis.fittingTicks(min: format.valueAxis.start ?? (floatLow.map { Swift.min($0, forecastRows.map(\.lower).min() ?? $0) } ?? minValY1),
                                                 max: format.valueAxis.end ?? maxValY1,
                                                 plotHeight: plotHeight,
                                                 minSpacing: kind == .clusteredBar ? ChartAxis.minSpacingHorizontal : ChartAxis.minSpacingPrimary,
                                                 floating: floatLow != nil,
                                                 extend: kind == .clusteredBar ? ChartAxis.horizontalDomainExtension : ChartAxis.domainExtension)
                y1Ticks = fit.ticks
                fittedY1 = (fit.lower, fit.upper)
            } else {
                y1Ticks = ChartAxis.niceTicks(
                    min: format.valueAxis.start ?? minValY1,
                    max: format.valueAxis.end ?? maxValY1,
                    targetCount: ChartAxis.primaryTargetCount
                )
            }
            y1Labels = ChartAxis.labels(
                ticks: y1Ticks,
                units: format.valueAxis.displayUnits,
                precision: format.valueAxis.precision,
                formatString: primaryFormatString
            )
            self.useLogScale = false
        }
        if kind == .hundredPercentStackedArea {
            y1Ticks = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
            y1Labels = y1Ticks.map { "\(Int($0 * 100))%" }
        }
        // Round range tắt (VM-D18, biểu đồ đường): miền trục là đúng [nhỏ nhất, lớn nhất] của dữ liệu (cả dải dự báo), vạch chỉ
        // còn những giá trị đẹp nằm trong miền đó; không ép bắt đầu từ 0 hay kết thúc ở vạch tròn.
        let dataValues = roleYIndices.flatMap { m in data.values[m].flatMap { $0 }.compactMap { NumberDisplay.numericValue($0.value) } }
        let dataLow = Swift.min(dataValues.min() ?? 0, forecastRows.map(\.lower).min() ?? .infinity)
        let dataHigh = Swift.max(maxValY1, dataValues.max() ?? 0)
        let roundOff = format.valueAxis.roundRange == false && kind == .line && !logActive && format.valueAxis.start == nil
            && format.valueAxis.end == nil && dataHigh > dataLow
        if roundOff {
            y1Ticks = ChartAxis.niceTicks(min: dataLow, max: dataHigh, targetCount: ChartAxis.primaryTargetCount).filter { $0 >= dataLow && $0 <= dataHigh }
            y1Labels = ChartAxis.labels(ticks: y1Ticks, units: format.valueAxis.displayUnits, precision: format.valueAxis.precision,
                                        formatString: primaryFormatString)
        }
        let y1MinBound = roundOff ? dataLow : (fittedY1?.lower ?? y1Ticks.first ?? 0)
        let y1MaxBound = roundOff ? dataHigh : (fittedY1?.upper ?? y1Ticks.last ?? 1)
        
        var y2Ticks: [Double] = []
        var fittedY2: (lower: Double, upper: Double)?
        var y2Labels: [String] = []
        var scaledY2Ticks: [Double] = []
        if hasY2 {
            if let plotHeight = tickPlotHeight {
                let lineValues = roleY2Indices.flatMap { m in data.values[m].flatMap { $0 }.compactMap { NumberDisplay.numericValue($0.value) } }
                let floatLow = format.valueAxis.secondaryStart == nil && format.valueAxis.secondaryEnd == nil ? ChartAxis.floatingLow(values: lineValues) : nil
                let fit = ChartAxis.fittingTicks(min: format.valueAxis.secondaryStart ?? floatLow ?? minValY2, max: format.valueAxis.secondaryEnd ?? maxValY2,
                                                 plotHeight: plotHeight, minSpacing: floatLow != nil ? ChartAxis.minSpacingPrimary : ChartAxis.minSpacingSecondary, floating: floatLow != nil)
                y2Ticks = fit.ticks
                fittedY2 = (fit.lower, fit.upper)
            } else {
                y2Ticks = ChartAxis.niceTicks(
                    min: format.valueAxis.secondaryStart ?? minValY2,
                    max: format.valueAxis.secondaryEnd ?? maxValY2,
                    targetCount: 4
                )
            }
            y2Labels = ChartAxis.labels(
                ticks: y2Ticks,
                units: format.valueAxis.secondaryDisplayUnits,
                precision: format.valueAxis.secondaryPrecision,
                formatString: secondaryFormatString
            )
            let y2MinBound = fittedY2?.lower ?? y2Ticks.first ?? 0
            let y2MaxBound = fittedY2?.upper ?? y2Ticks.last ?? 1
            scaledY2Ticks = y2Ticks.map {
                ComboChart.secondaryScale(value: $0, y2Min: y2MinBound, y2Max: y2MaxBound, targetMin: y1MinBound, targetMax: y1MaxBound)
            }
        }
        
        // Vùng xếp chồng: tổng cộng dồn của các series đã vẽ ở mỗi danh mục.
        var stackedBase = [Double](repeating: 0, count: kind.isStackedArea ? numCats : 0)
        // Build line points
        for (mOrder, mIdx) in lineMeasureIndices.enumerated() {
            let mField = data.measures[mIdx]
            let mSeriesCount = data.values[mIdx].count
            // Đường Y2 của combo lấy màu tiếp sau các cột (sau các series, hoặc sau các measure Y), như legend.
            let lineSplitsBySeries = hasSeries && mSeriesCount > 1
            let colorIndex = hasY2 ? (hasSeries ? data.series.count : roleYIndices.count) + mOrder : mOrder
            for sIdx in 0..<mSeriesCount {
                let sVal = lineSplitsBySeries && sIdx < data.series.count ? data.series[sIdx] : nil
                let sName = sVal.map { seriesText($0) } ?? mField.displayName
                var pts: [ChartLinePointDatum] = []
                let col = ChartColorResolver.resolveColor(
                    cell: data.cell(measure: mIdx, series: sIdx, category: 0),
                    seriesValue: sVal,
                    seriesField: data.seriesField,
                    seriesIndex: sIdx,
                    hasSeries: lineSplitsBySeries,
                    measure: mField,
                    measureIndex: colorIndex,
                    format: format,
                    theme: theme
                )
                
                for cIdx in 0..<numCats {
                    let cell = data.cell(measure: mIdx, series: sIdx, category: cIdx)
                    guard let v = NumberDisplay.numericValue(cell.value) else { continue }
                    let ptID = makePointID(c: cIdx, s: sIdx)
                    let scaledV: Double
                    if hasY2 {
                        let y2MinBound = fittedY2?.lower ?? y2Ticks.first ?? 0
                        let y2MaxBound = fittedY2?.upper ?? y2Ticks.last ?? 1
                        scaledV = ComboChart.secondaryScale(value: v, y2Min: y2MinBound, y2Max: y2MaxBound, targetMin: y1MinBound, targetMax: y1MaxBound)
                    } else {
                        scaledV = v
                        minValY1 = Swift.min(minValY1, v)
                        maxValY1 = Swift.max(maxValY1, v)
                    }
                    
                    let labelText: String?
                    if format.dataLabels.show == true {
                        labelText = DataLabels.text(cell: cell, format: format.dataLabels)
                    } else {
                        labelText = nil
                    }
                    
                    var areaBase = Swift.max(y1MinBound, Swift.min(0, y1MaxBound))
                    var plotted = scaledV
                    if kind.isStackedArea {
                        areaBase = stackedBase[cIdx]
                        plotted = areaBase + v
                        stackedBase[cIdx] = plotted
                        // 100%: mỗi danh mục chuẩn hoá về tổng 1 (cột xếp chồng 100% cũng vậy).
                        if kind == .hundredPercentStackedArea {
                            let total = stackedTotals[cIdx] > 0 ? stackedTotals[cIdx] : 1
                            areaBase /= total
                            plotted /= total
                        }
                    }
                    pts.append(ChartLinePointDatum(
                        pointID: ptID,
                        category: catStrings[cIdx],
                        seriesName: sName,
                        value: plotted,
                        rawValue: v,
                        opacity: pointOpacity(ptID: ptID),
                        dataLabel: labelText,
                        base: areaBase
                    ))
                }
                
                if !pts.isEmpty {
                    computedLines.append(ChartLineSeriesDatum(name: sName, color: col, points: pts))
                }
            }
        }
        
        // Trend line fit
        let showTrend = (format.analytics.trendShow == true && kind == .line)
        if showTrend, let firstLine = computedLines.first, firstLine.points.count >= 2 {
            var fitPoints: [(x: Double, y: Double)] = []
            // Hồi quy tuyến tính theo giá trị. Trục log: Desktop chỉ vẽ đoạn thẳng nối hai đầu của đường hồi quy (VM-D17: ở D1 là
            // 0,41M → 173,4M, đúng hai đầu đường thẳng trên trục log), không vẽ đường cong.
            for (idx, pt) in firstLine.points.enumerated() {
                fitPoints.append((x: Double(idx), y: pt.value))
            }
            if let fit = TrendLine.linearFit(fitPoints) {
                let ends: [Int] = logActive ? [0, firstLine.points.count - 1] : Array(firstLine.points.indices)
                for idx in ends {
                    let y = fit.slope * Double(idx) + fit.intercept
                    computedTrend.append(ChartTrendPointDatum(category: firstLine.points[idx].category, y: logActive ? Swift.max(y, 1e-9) : y))
                }
            }
        }
        
        self.bars = computedBars
        self.barXTicks = y1Ticks
        self.barXLabels = y1Labels
        self.barXDomain = y1MinBound...y1MaxBound
        
        self.columns = computedColumns
        self.columnYTicks = y1Ticks
        self.columnYLabels = y1Labels
        self.columnYDomain = y1MinBound...y1MaxBound
        
        if kind == .hundredPercentStackedColumn {
            self.stackSegments = computedSegments
            let pctTicks = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
            self.stackYTicks = pctTicks
            self.stackYLabels = pctTicks.map { "\(Int($0 * 100))%" }
            self.stackYDomain = 0.0...1.0
        } else {
            self.stackSegments = computedSegments
            self.stackYTicks = y1Ticks
            self.stackYLabels = y1Labels
            self.stackYDomain = y1MinBound...y1MaxBound
        }
        
        self.lineSeries = computedLines
        self.trendPoints = computedTrend
        self.showTrend = showTrend
        self.forecastPoints = forecastRows
        
        // Desktop (VM-D21): trục phụ chỉ hiện khi miền của nó khác miền trục chính; trùng miền thì chỉ một trục (D3 "TB 3 tháng" cùng 0…600
        // với cột; đặt Maximum của trục chính 300 thì trục phải 0…600 hiện ra). Đường đã quy về thang chính nên vẽ y hệt.
        let axesCoincide = hasY2 && y2Ticks == y1Ticks && (fittedY2?.lower ?? y2Ticks.first) == (fittedY1?.lower ?? y1Ticks.first)
            && (fittedY2?.upper ?? y2Ticks.last) == (fittedY1?.upper ?? y1Ticks.last)
        self.hasSecondaryAxis = hasY2 && !axesCoincide
        self.y2Ticks = y2Ticks
        self.y2Labels = y2Labels
        self.scaledY2Ticks = scaledY2Ticks
    }
}

// MARK: - Event Interception View (Right Click)

private struct RightClickDetector: NSViewRepresentable {
    var onRightClick: (CGPoint) -> Void
    /// Cuộn chuột/trackpad (dx, dy theo điểm ảnh). Trả `true` nếu biểu đồ tự cuộn; `false` thì sự kiện đi tiếp cho trang.
    var onScroll: (CGFloat, CGFloat) -> Bool = { _, _ in false }
    
    func makeNSView(context: Context) -> ClickInterceptionNSView {
        let view = ClickInterceptionNSView()
        view.onRightClick = onRightClick
        view.onScroll = onScroll
        return view
    }
    
    func updateNSView(_ nsView: ClickInterceptionNSView, context: Context) {
        nsView.onRightClick = onRightClick
        nsView.onScroll = onScroll
    }
    
    class ClickInterceptionNSView: NSView {
        var onRightClick: ((CGPoint) -> Void)?
        var onScroll: ((CGFloat, CGFloat) -> Bool)?

        override func scrollWheel(with event: NSEvent) {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            if onScroll?(event.scrollingDeltaX * scale, event.scrollingDeltaY * scale) != true {
                nextResponder?.scrollWheel(with: event)
            }
        }
        
        override func rightMouseDown(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: loc.x, y: bounds.height - loc.y)
            onRightClick?(flipped)
        }
        
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .scrollWheel else {
                return nil
            }
            return self
        }
    }
}

// MARK: - CartesianChartView

struct CartesianChartView: View {
    let data: CategoricalData
    let kind: CartesianKind
    let context: VisualRenderContext
    let interactive: Bool
    
    private let layout: PreparedChartLayout
    /// Độ rộng vùng vẽ, đo bằng GeometryReader nền; dùng để quyết định xoay nhãn danh mục (như Power BI).
    @State private var plotWidth: CGFloat = 0
    /// Chiều cao vùng chart (gồm trục), để giới hạn chiều dài nhãn xoay dọc.
    @State private var chartHeight: CGFloat = 0
    /// Danh mục đầu tiên đang hiện khi trục cuộn ngang.
    @State private var scrollX: String = ""
    @State private var scrollRemainder: CGFloat = 0
    
    init(data: CategoricalData, kind: CartesianKind, context: VisualRenderContext, interactive: Bool = true) {
        self.data = data
        self.kind = kind
        self.context = context
        self.interactive = interactive
        self.layout = PreparedChartLayout(data: data, kind: kind, context: context)
    }
    
    var body: some View {
        if layout.isEmpty {
            ZStack {
                Color.clear
                Text("Không có dữ liệu")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else {
            chartContainer
        }
    }
    
    @ViewBuilder
    private var chartContainer: some View {
        let pos = layout.legendPosition
        let isSide = (pos == "Left" || pos == "Right" || pos == "LeftCenter" || pos == "RightCenter")
        let isBottom = pos.starts(with: "Bottom")
        
        if layout.showLegend && isSide {
            HStack(spacing: 8) {
                if pos.contains("Left") {
                    ChartLegendView(items: layout.legendItems, position: pos, fontSize: layout.legendFontSize)
                        .padding(.leading, 8)
                }
                chartViewPadded
                if pos.contains("Right") {
                    ChartLegendView(items: layout.legendItems, position: pos, fontSize: layout.legendFontSize)
                        .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 8) {
                if layout.showLegend && !isBottom {
                    ChartLegendView(items: layout.legendItems, position: pos, fontSize: layout.legendFontSize)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                }
                chartViewPadded
                if layout.showLegend && isBottom {
                    ChartLegendView(items: layout.legendItems, position: pos, fontSize: layout.legendFontSize)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    /// Số danh mục hiện cùng lúc khi nhãn đã xoay dọc mà vẫn không đủ chỗ (Power BI cuộn ngang trục chữ, D1 "Rủi ro thấu chi").
    private var visibleCategoryCount: Int {
        // Desktop xếp nhãn xoay dọc cách nhau ≈ 20,5 đơn vị trang (VM-D19: "Khiếu nại thay đổi" 23 nhãn, "Rủi ro thấu chi" 25 nhãn trên ≈ 500), tức 1,46 × cỡ chữ 14.
        max(4, Int(plotWidth / (layout.categoryFontSize * 1.46)))
    }

    /// Danh mục đang vẽ trên trục: cả danh sách, hoặc cửa sổ `visibleCategoryCount` phần tử bắt đầu từ `scrollX`.
    /// Không dùng `chartScrollableAxes`: với canvas thu nhỏ (`scaleEffect`) nó làm SwiftUI vẽ lại liên tục (D3 tốn 40% CPU khi rảnh).
    private var axisCategories: [String] {
        guard needsCategoryScroll else { return layout.categories }
        return CategoryWindow.slice(layout.categories, from: scrollX, count: visibleCategoryCount)
    }

    private var needsCategoryScroll: Bool {
        guard !layout.isScalarAxis, kind != .clusteredBar, plotWidth > 0, rotateCategoryLabels else { return false }
        return layout.categories.count > visibleCategoryCount
    }

    /// Cuộn trục danh mục bằng bánh xe hoặc trackpad. false nếu trục không cuộn (để trang cuộn).
    private func scrollCategories(dx: CGFloat, dy: CGFloat) -> Bool {
        guard needsCategoryScroll else { return false }
        let delta = abs(dx) >= abs(dy) ? dx : dy
        let perCategory = Swift.max(1, plotWidth / CGFloat(visibleCategoryCount))
        scrollRemainder += delta
        let steps = Int((scrollRemainder / perCategory).rounded(.towardZero))
        guard steps != 0 else { return true }
        scrollRemainder -= CGFloat(steps) * perCategory
        let count = layout.categories.count
        let current = layout.categories.firstIndex(of: scrollX) ?? 0
        let next = Swift.max(0, Swift.min(count - visibleCategoryCount, current - steps))
        scrollX = layout.categories[next]
        return true
    }

    private var scrollBar: some View {
        let total = CGFloat(layout.categories.count)
        let visible = CGFloat(min(visibleCategoryCount, layout.categories.count))
        let start = CGFloat(layout.categories.firstIndex(of: scrollX) ?? 0)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.black.opacity(0.08))
            Capsule().fill(Color.black.opacity(0.28))
                .frame(width: max(16, plotWidth * visible / total))
                .offset(x: min(plotWidth * start / total, plotWidth * (1 - visible / total)))
        }
        .frame(height: 6)
        .padding(.horizontal, 8)
        // Kéo hoặc bấm thanh để cuộn: giữa thanh trượt nằm tại điểm bấm.
        .contentShape(Rectangle().inset(by: -6))
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            guard plotWidth > 0, !layout.categories.isEmpty else { return }
            let count = layout.categories.count
            let center = Int((drag.location.x / plotWidth) * CGFloat(count))
            let first = Swift.max(0, Swift.min(count - visibleCategoryCount, center - visibleCategoryCount / 2))
            scrollX = layout.categories[first]
        })
    }

    private var chartViewPadded: some View {
        VStack(spacing: 2) {
            chartViewWithEvents
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { plotWidth = geo.size.width; chartHeight = geo.size.height }
                        .onChange(of: geo.size.width) { _, w in plotWidth = w }
                        .onChange(of: geo.size.height) { _, h in chartHeight = h }
                })
            if needsCategoryScroll { scrollBar }
        }
        .padding(.top, 14)
        .padding(.trailing, layout.hasSecondaryAxis ? 16 : 8)
        .padding(.leading, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var chartViewWithEvents: some View {
        let base = chartBody
            .chartPlotStyle { plot in
                plot.background(Color.clear)
            }
        
        if interactive {
            base
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { loc in
                                let ptID = findPointID(at: loc, proxy: proxy, geometry: geo)
                                let isAdditive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
                                context.actions.select(ptID, isAdditive)
                            }
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    let ptID = hoverPointID(at: loc, proxy: proxy, geometry: geo)
                                    context.actions.hover(ptID, loc)
                                case .ended:
                                    context.actions.hover(nil, .zero)
                                }
                            }
                    }
                }
                .overlay {
                    RightClickDetector(onRightClick: { loc in
                        let ptID = findPointID(at: loc)
                        context.actions.contextMenu(ptID, loc)
                    }, onScroll: { dx, dy in scrollCategories(dx: dx, dy: dy) })
                }
        } else {
            base
        }
    }
    
    @ViewBuilder
    private var chartBody: some View {
        switch kind {
        case .clusteredBar:
            barChart
        case .clusteredColumn:
            columnChart
        case .stackedColumn, .hundredPercentStackedColumn:
            stackedColumnChart
        case .line, .area, .stackedArea, .hundredPercentStackedArea:
            lineChart
        case .comboClustered:
            comboClusteredChart
        case .comboStacked:
            comboStackedChart
        }
    }
    
    // MARK: - Chart Builders
    
    private var barChart: some View {
        Chart {
            ForEach(layout.bars) { bar in
                BarMark(
                    x: .value("Value", bar.value),
                    y: .value("Category", bar.category),
                    height: layout.isScalarAxis ? .ratio(0.85) : .automatic   // trục ngày liên tục: thanh mảnh (VM-D19)
                )
                .position(by: .value("Series", bar.series))
                .foregroundStyle(bar.color.opacity(layout.hasHighlights ? 0.4 : bar.opacity))
                .annotation(position: .trailing, alignment: .leading) {
                    if let label = bar.dataLabel {
                        Text(label)
                            .font(.system(size: layout.dataLabelFontSize))
                            .bold(layout.dataLabelBold)
                            .foregroundColor(layout.dataLabelColor)
                    }
                }
                
                if let hl = bar.highlightValue {
                    // Khoảng [0, hl] phủ lên thanh đầy đủ (không chồng nối tiếp như BarMark(x:)).
                    BarMark(
                        xStart: .value("Start", 0.0),
                        xEnd: .value("Value", hl),
                        y: .value("Category", bar.category)
                    )
                    .position(by: .value("Series", bar.series))
                    .foregroundStyle(bar.color)
                }
            }
        }
        // Trục ngày liên tục (`axisType` Scalar): giá trị nhỏ ở dưới, mới nhất ở trên, chỉ ghi nhãn năm tại vạch đầu năm (VM-D19).
        .chartYScale(domain: layout.isScalarAxis ? axisCategories.reversed() : axisCategories)
        // Chừa chỗ cho nhãn vạch cuối khi nó sát mép phải ("100%" của thanh phần trăm, "$200M"): không thì bị cắt hoặc bỏ.
        .chartXScale(domain: layout.barXDomain, range: .plotDimension(endPadding: layout.barLastLabelNearEdge ? 24 : 0))
        .chartYAxis {
            if layout.isScalarAxis {
                AxisMarks(preset: .extended, position: .leading, values: layout.scalarXTicks) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: []))
                        .foregroundStyle(Color.gray.opacity(0.18))
                    AxisValueLabel(centered: true) {
                        if let str = val.as(String.self), let year = layout.scalarXLabels[str] {
                            Text(year)
                                .font(.system(size: layout.categoryFontSize))
                                .foregroundColor(Color(hex: "#252423") ?? .primary)
                        }
                    }
                }
            } else {
            AxisMarks(preset: .extended, position: .leading, values: layout.categories) { val in
                // Nhãn danh mục ở trục trái, ngoài vùng vẽ, căn giữa theo thanh (như Power BI).
                AxisValueLabel(centered: true) {
                    if let str = val.as(String.self) {
                        Text(str)
                            .font(.system(size: layout.categoryFontSize))
                            .foregroundColor(Color(hex: "#252423") ?? .primary)
                    }
                }
            }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: layout.barXTicks) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: []))
                    .foregroundStyle(Color.gray.opacity(0.18))
                AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                    if let d = val.as(Double.self) {
                        let labelText = formattedTickLabel(d, ticks: layout.barXTicks, labels: layout.barXLabels)
                        Text(labelText)
                            .fixedSize()   // không để Charts cắt nhãn vạch cuối sát mép thành "…" hoặc bỏ
                            .font(.system(size: layout.categoryFontSize))
                            .foregroundColor(Color(hex: "#252423") ?? .primary)
                    }
                }
            }
        }
    }
    
    private var columnChart: some View {
        Chart {
            ForEach(layout.columns) { col in
                BarMark(
                    x: .value("Category", col.category),
                    y: .value("Value", col.value)
                )
                .position(by: .value("Series", col.series))
                .foregroundStyle(col.color.opacity(layout.hasHighlights ? 0.4 : col.opacity))
                .annotation(position: .top, alignment: .center) {
                    if let label = col.dataLabel {
                        Text(label)
                            .font(.system(size: layout.dataLabelFontSize))
                            .bold(layout.dataLabelBold)
                            .foregroundColor(layout.dataLabelColor)
                    }
                }
                
                if let hl = col.highlightValue {
                    BarMark(
                        x: .value("Category", col.category),
                        yStart: .value("Start", 0.0),
                        yEnd: .value("Value", hl)
                    )
                    .position(by: .value("Series", col.series))
                    .foregroundStyle(col.color)
                }
            }
        }
        .chartXScale(domain: axisCategories)
        .chartYScale(domain: layout.columnYDomain, type: layout.useLogScale ? .log : .linear)
        .chartXAxis {
            categoryAxisMarks
        }
        .chartYAxis {
            primaryYAxisMarks(ticks: layout.columnYTicks, labels: layout.columnYLabels)
        }
    }
    
    private var stackedColumnChart: some View {
        Chart {
            ForEach(layout.stackSegments) { seg in
                BarMark(
                    x: .value("Category", seg.category),
                    yStart: .value("Y0", seg.y0),
                    yEnd: .value("Y1", seg.y1)
                )
                .foregroundStyle(seg.color.opacity(layout.hasHighlights ? 0.4 : seg.opacity))
                .annotation(position: .overlay, alignment: .center) {
                    if let label = seg.dataLabel {
                        Text(label)
                            .font(.system(size: layout.dataLabelFontSize))
                            .bold(layout.dataLabelBold)
                            .foregroundColor(layout.dataLabelColor)
                    }
                }
                
                if let hl = seg.highlightValue {
                    let hlHeight = (seg.y1 - seg.y0) * (hl / Swift.max(1e-9, seg.value))
                    BarMark(
                        x: .value("Category", seg.category),
                        yStart: .value("Y0", seg.y0),
                        yEnd: .value("Y1", seg.y0 + hlHeight)
                    )
                    .foregroundStyle(seg.color)
                }
            }
        }
        .chartXScale(domain: axisCategories)
        .chartYScale(domain: layout.stackYDomain)
        .chartXAxis {
            categoryAxisMarks
        }
        .chartYAxis {
            primaryYAxisMarks(ticks: layout.stackYTicks, labels: layout.stackYLabels)
        }
    }
    
    private var lineChart: some View {
        Chart {
            // Vùng (VM-D15 mục 4): phần tô nhạt dưới đường, vẽ trước để đường nằm trên; mờ ≈ 0,43 như Desktop.
            if kind.isArea {
                ForEach(layout.lineSeries) { s in
                    ForEach(s.points) { pt in
                        AreaMark(
                            x: .value("Category", pt.category),
                            yStart: .value("Base", pt.base),
                            yEnd: .value("Value", pt.value),
                            series: .value("AreaSeries", s.name)
                        )
                        .foregroundStyle(s.color.opacity(0.43 * pt.opacity))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            ForEach(layout.lineSeries) { s in
                ForEach(s.points) { pt in
                    LineMark(
                        x: .value("Category", pt.category),
                        y: .value("Value", pt.value),
                        series: .value("Series", s.name)
                    )
                    .foregroundStyle(s.color.opacity(pt.opacity))
                    .lineStyle(StrokeStyle(lineWidth: kind.isArea ? 2 : 3, lineCap: .round, lineJoin: .round)) // Power BI: nét mặc định 3 (so ảnh VM); vùng 2
                    .interpolationMethod(.catmullRom)
                    .annotation(position: .top) {
                        if let label = pt.dataLabel {
                            Text(label)
                                .font(.system(size: layout.dataLabelFontSize))
                                .bold(layout.dataLabelBold)
                                .foregroundColor(layout.dataLabelColor)
                        }
                    }
                }
            }
            
            if layout.showTrend {
                ForEach(layout.trendPoints) { pt in
                    LineMark(
                        x: .value("Category", pt.category),
                        y: .value("Trend", pt.y),
                        series: .value("Series", "TrendLine")
                    )
                    .foregroundStyle(Color(hex: "#333333") ?? .secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
            }

            // Dự báo: dải tin cậy xám và đường mảnh đen (Power BI, d1.png).
            ForEach(layout.forecastPoints) { pt in
                AreaMark(
                    x: .value("Category", pt.category),
                    yStart: .value("Lower", Swift.max(layout.columnYDomain.lowerBound, pt.lower)),
                    yEnd: .value("Upper", Swift.min(layout.columnYDomain.upperBound, pt.upper)),
                    series: .value("Series", "ForecastBand")
                )
                .foregroundStyle(Color(hex: "#B8B8C4")?.opacity(0.55) ?? .gray.opacity(0.4))
                .interpolationMethod(.catmullRom)
            }
            ForEach(layout.forecastPoints) { pt in
                LineMark(
                    x: .value("Category", pt.category),
                    y: .value("Forecast", pt.y),
                    series: .value("Series", "Forecast")
                )
                .foregroundStyle(Color(hex: "#1F1F1F") ?? .black)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXScale(domain: axisCategories)
        .chartYScale(domain: layout.columnYDomain, type: layout.useLogScale ? .log : .linear)
        .chartXAxis {
            if layout.isScalarAxis {
                AxisMarks(position: .bottom, values: layout.scalarXTicks) { val in
                    // Nhãn năm bắt đầu tại vạch đầu năm, không bị cắt ở mép trái.
                    AxisValueLabel(anchor: .topLeading) {
                        if let str = val.as(String.self), let yr = layout.scalarXLabels[str] {
                            Text(yr)
                                .font(.system(size: layout.categoryFontSize))
                                .foregroundColor(Color(hex: "#252423") ?? .primary)
                        }
                    }
                }
            } else {
                categoryAxisMarks
            }
        }
        .chartYAxis {
            primaryYAxisMarks(ticks: layout.columnYTicks, labels: layout.columnYLabels)
        }
    }
    
    private var comboClusteredChart: some View {
        Chart {
            ForEach(layout.columns) { col in
                BarMark(
                    x: .value("Category", col.category),
                    y: .value("Value", col.value)
                )
                .position(by: .value("Series", col.series))
                .foregroundStyle(col.color.opacity(layout.hasHighlights ? 0.4 : col.opacity))
                .annotation(position: .top, alignment: .center) {
                    if let label = col.dataLabel {
                        Text(label)
                            .font(.system(size: layout.dataLabelFontSize))
                            .bold(layout.dataLabelBold)
                            .foregroundColor(layout.dataLabelColor)
                    }
                }
                
                if let hl = col.highlightValue {
                    BarMark(
                        x: .value("Category", col.category),
                        yStart: .value("Start", 0.0),
                        yEnd: .value("Value", hl)
                    )
                    .position(by: .value("Series", col.series))
                    .foregroundStyle(col.color)
                }
            }
            
            ForEach(layout.lineSeries) { s in
                ForEach(s.points) { pt in
                    LineMark(
                        x: .value("Category", pt.category),
                        y: .value("Value", pt.value),
                        series: .value("Series", s.name)
                    )
                    .foregroundStyle(s.color.opacity(pt.opacity))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)) // Power BI: nét mặc định 3 (so ảnh VM)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXScale(domain: axisCategories)
        .chartYScale(domain: layout.columnYDomain, type: layout.useLogScale ? .log : .linear)
        .chartXAxis {
            categoryAxisMarks
        }
        .chartYAxis {
            primaryYAxisMarks(ticks: layout.columnYTicks, labels: layout.columnYLabels)
            if layout.hasSecondaryAxis {
                secondaryYAxisMarks
            }
        }
    }
    
    private var comboStackedChart: some View {
        Chart {
            ForEach(layout.stackSegments) { seg in
                BarMark(
                    x: .value("Category", seg.category),
                    yStart: .value("Y0", seg.y0),
                    yEnd: .value("Y1", seg.y1)
                )
                .foregroundStyle(seg.color.opacity(layout.hasHighlights ? 0.4 : seg.opacity))
                .annotation(position: .overlay, alignment: .center) {
                    if let label = seg.dataLabel {
                        Text(label)
                            .font(.system(size: layout.dataLabelFontSize))
                            .bold(layout.dataLabelBold)
                            .foregroundColor(layout.dataLabelColor)
                    }
                }
                
                if let hl = seg.highlightValue {
                    let hlHeight = (seg.y1 - seg.y0) * (hl / Swift.max(1e-9, seg.value))
                    BarMark(
                        x: .value("Category", seg.category),
                        yStart: .value("Y0", seg.y0),
                        yEnd: .value("Y1", seg.y0 + hlHeight)
                    )
                    .foregroundStyle(seg.color)
                }
            }
            
            ForEach(layout.lineSeries) { s in
                ForEach(s.points) { pt in
                    LineMark(
                        x: .value("Category", pt.category),
                        y: .value("Value", pt.value),
                        series: .value("Series", s.name)
                    )
                    .foregroundStyle(s.color.opacity(pt.opacity))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)) // Power BI: nét mặc định 3 (so ảnh VM)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXScale(domain: axisCategories)
        .chartYScale(domain: layout.stackYDomain)
        .chartXAxis {
            categoryAxisMarks
        }
        .chartYAxis {
            primaryYAxisMarks(ticks: layout.stackYTicks, labels: layout.stackYLabels)
            if layout.hasSecondaryAxis {
                secondaryYAxisMarks
            }
        }
    }
    
    // MARK: - Axis Marks Components
    
    /// Nhãn danh mục không đủ chỗ nằm ngang thì xoay dọc (D1 "Rủi ro thấu chi": 2013-01 … xoay dọc).
    private var rotateCategoryLabels: Bool {
        guard plotWidth > 0, !layout.categories.isEmpty else { return false }
        let longest = layout.categories.map(\.count).max() ?? 0
        let estimated = CGFloat(longest) * layout.categoryFontSize * 0.6 + 8
        return estimated * CGFloat(layout.categories.count) > plotWidth
    }

    private var categoryAxisMarks: some AxisContent {
        AxisMarks(position: .bottom, values: layout.categories) { val in
            AxisValueLabel(orientation: rotateCategoryLabels ? .verticalReversed : .horizontal) {
                if let str = val.as(String.self) {
                    // Nhãn xoay dọc: cùng độ rộng, căn mép gần trục, để các nhãn thẳng hàng (chữ số "1" hẹp hơn chữ số khác).
                    let rotated = rotateCategoryLabels
                    Text(rotated ? labelFit.text(str) : str)
                        .font(.system(size: layout.categoryFontSize).monospacedDigit())
                        .foregroundColor(Color(hex: "#252423") ?? .primary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: rotated ? rotatedLabelWidth : nil, alignment: .trailing)
                }
            }
        }
    }

    /// Độ rộng chung của nhãn danh mục khi xoay dọc: nhãn dài nhất theo số chữ số cùng độ rộng.
    private var rotatedLabelWidth: CGFloat {
        labelFit.width(for: layout.categories)
    }

    private var labelFit: CategoryLabelFit { CategoryLabelFit(fontSize: layout.categoryFontSize, chartHeight: chartHeight) }
    
    private func primaryYAxisMarks(ticks: [Double], labels: [String]) -> some AxisContent {
        AxisMarks(position: .leading, values: ticks) { val in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: []))
                .foregroundStyle(Color.gray.opacity(0.18))
            AxisValueLabel {
                if let d = val.as(Double.self) {
                    let labelText = formattedTickLabel(d, ticks: ticks, labels: labels)
                    Text(labelText)
                        .font(.system(size: layout.categoryFontSize))
                        .foregroundColor(Color(hex: "#252423") ?? .primary)
                }
            }
        }
    }
    
    private var secondaryYAxisMarks: some AxisContent {
        AxisMarks(position: .trailing, values: layout.scaledY2Ticks) { val in
            AxisValueLabel {
                if let d = val.as(Double.self) {
                    let labelText = formattedTickLabel(d, ticks: layout.scaledY2Ticks, labels: layout.y2Labels)
                    Text(labelText)
                        .font(.system(size: layout.categoryFontSize))
                        .foregroundColor(Color(hex: "#252423") ?? .primary)
                }
            }
        }
    }
    
    private func formattedTickLabel(_ val: Double, ticks: [Double], labels: [String]) -> String {
        for (i, tick) in ticks.enumerated() {
            if abs(tick - val) < 1e-6, i < labels.count {
                return labels[i]
            }
        }
        return ""
    }
    
    // MARK: - Hit Testing
    
    private func findPointID(at location: CGPoint, proxy: ChartProxy? = nil, geometry: GeometryProxy? = nil) -> DataPointID? {
        guard !data.categories.isEmpty else { return nil }
        
        let cIdx: Int
        if kind == .clusteredBar {
            guard let geo = geometry, let p = proxy, let plot = p.plotFrame else {
                let normY = location.y / Swift.max(1, geometry?.size.height ?? 300)
                let idx = Int(normY * CGFloat(data.categories.count))
                cIdx = Swift.max(0, Swift.min(data.categories.count - 1, idx))
                return buildPointID(c: cIdx, s: 0)
            }
            let plotRect = geo[plot]
            let plotH = plotRect.height
            let relY = location.y - plotRect.origin.y
            guard relY >= 0 && relY <= plotH else { return nil }
            // Thứ tự có thể đảo (trục ngày liên tục): hỏi biểu đồ danh mục tại vị trí này.
            if let name = p.value(atY: relY, as: String.self), let at = layout.categories.firstIndex(of: name), at < data.categories.count {
                return buildPointID(c: at, s: 0)
            }
            let frac = relY / plotH
            let idx = Int(frac * CGFloat(data.categories.count))
            cIdx = Swift.max(0, Swift.min(data.categories.count - 1, idx))
        } else {
            guard let geo = geometry, let p = proxy, let plot = p.plotFrame else {
                let normX = location.x / Swift.max(1, geometry?.size.width ?? 400)
                let idx = Int(normX * CGFloat(data.categories.count))
                cIdx = Swift.max(0, Swift.min(data.categories.count - 1, idx))
                return buildPointID(c: cIdx, s: 0)
            }
            let plotRect = geo[plot]
            let plotW = plotRect.width
            let relX = location.x - plotRect.origin.x
            guard relX >= 0 && relX <= plotW else { return nil }
            // Trục có thể đang cuộn hoặc có thêm tháng dự báo: hỏi biểu đồ danh mục tại vị trí này thay vì chia đều theo số điểm.
            if let name = p.value(atX: relX, as: String.self), let at = layout.categories.firstIndex(of: name) {
                guard at < data.categories.count else { return nil }
                return buildPointID(c: at, s: areaSeriesIndex(category: at, location: location, proxy: p, geometry: geo))
            }
            let frac = relX / plotW
            let idx = Int(frac * CGFloat(data.categories.count))
            cIdx = Swift.max(0, Swift.min(data.categories.count - 1, idx))
        }
        
        return buildPointID(c: cIdx, s: areaSeriesIndex(category: cIdx, location: location, proxy: proxy, geometry: geometry))
    }

    /// Series ở vị trí chuột trên biểu đồ vùng (VM-D16): vùng xếp chồng lấy lớp chứa giá trị y; vùng chồng lên nhau lấy vùng phủ
    /// phía trên con trỏ có đỉnh thấp nhất (vùng trên cùng ở chỗ đó). Loại khác hoặc không có Series: series đầu.
    private func areaSeriesIndex(category c: Int, location: CGPoint, proxy: ChartProxy?, geometry: GeometryProxy?) -> Int {
        guard kind.isArea, data.seriesField != nil, layout.lineSeries.count > 1, c < layout.categories.count,
              let proxy, let geometry, let plot = proxy.plotFrame,
              let y = proxy.value(atY: location.y - geometry[plot].origin.y, as: Double.self) else { return 0 }
        let name = layout.categories[c]
        let rows = layout.lineSeries.enumerated().compactMap { index, series in
            series.points.first { $0.category == name }.map { (index: index, base: $0.base, top: $0.value) }
        }
        if kind.isStackedArea { return rows.first { y >= $0.base && y <= $0.top }?.index ?? rows.last?.index ?? 0 }
        return rows.filter { $0.top >= y }.min { $0.top < $1.top }?.index ?? rows.max { $0.top < $1.top }?.index ?? 0
    }

    /// Điểm để hiện tooltip: như `findPointID`, nhưng tháng dự báo và điểm neo (tháng cuối thật) mang thêm số dự báo
    /// (`VisualTooltip.forecastKey`). Tooltip của Power BI ở vùng dự báo: tên dự báo, Upper bound, Lower bound (VM C2 B6).
    private func hoverPointID(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> DataPointID? {
        guard !layout.forecastPoints.isEmpty, kind != .clusteredBar,
              let plot = proxy.plotFrame else { return findPointID(at: location, proxy: proxy, geometry: geometry) }
        let rect = geometry[plot]
        let relX = location.x - rect.origin.x
        guard relX >= 0, relX <= rect.width, let name = proxy.value(atX: relX, as: String.self),
              let datum = layout.forecastPoints.first(where: { $0.category == name }) else {
            return findPointID(at: location, proxy: proxy, geometry: geometry)
        }
        var dict: [String: Value] = [:]
        if let at = layout.categories.firstIndex(of: name), at < data.categories.count {
            dict = buildPointID(c: at, s: 0).values
        } else if let level = data.categoryLevels.first {
            dict[level.queryRef] = .string(name)
            dict[VisualTooltip.forecastKey("only")] = .boolean(true)
        }
        dict[VisualTooltip.forecastKey("category")] = .string(name)
        dict[VisualTooltip.forecastKey("name")] = .string(context.format.analytics.forecastDisplayName ?? "Forecast")
        dict[VisualTooltip.forecastKey("y")] = .double(datum.y)
        dict[VisualTooltip.forecastKey("lower")] = .double(datum.lower)
        dict[VisualTooltip.forecastKey("upper")] = .double(datum.upper)
        return DataPointID(dict)
    }

    private func buildPointID(c: Int, s: Int) -> DataPointID {
        var dict: [String: Value] = [:]
        for (levelIdx, level) in data.categoryLevels.enumerated() {
            if c < data.categories.count, levelIdx < data.categories[c].values.count {
                dict[level.queryRef] = data.categories[c].values[levelIdx]
            }
        }
        if let sField = data.seriesField, s < data.series.count {
            dict[sField.queryRef] = data.series[s]
        }
        return DataPointID(dict)
    }
}
