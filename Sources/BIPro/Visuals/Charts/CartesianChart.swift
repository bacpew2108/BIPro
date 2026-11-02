import AppKit
import Charts
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI

enum CartesianKind: Hashable, Sendable {
    case clusteredBar, clusteredColumn, stackedColumn, hundredPercentStackedColumn, line, comboClustered, comboStacked
    
    init?(visualType: String) {
        switch visualType {
        case "clusteredBarChart", "clusteredBar":
            self = .clusteredBar
        case "clusteredColumnChart", "clusteredColumn":
            self = .clusteredColumn
        case "stackedColumnChart", "stackedColumn":
            self = .stackedColumn
        case "hundredPercentStackedColumnChart", "hundredPercentStackedColumn":
            self = .hundredPercentStackedColumn
        case "lineChart", "line":
            self = .line
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

struct PreparedChartLayout: Sendable {
    var isEmpty: Bool
    var kind: CartesianKind
    var categories: [String]
    
    // Bar
    var bars: [ChartBarDatum]
    var barXTicks: [Double]
    var barXLabels: [String]
    var barXDomain: ClosedRange<Double>
    
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
        
        let catFontSize = ReportUnits.pixels(fromPoints: format.categoryAxis.fontSize ?? 9)
        self.categoryFontSize = catFontSize
        self.hasHighlights = data.highlights != nil
        self.dataLabelFontSize = ReportUnits.pixels(fromPoints: format.dataLabels.fontSize ?? 9)
        self.dataLabelBold = format.dataLabels.bold ?? false
        self.dataLabelColor = theme.color(format.dataLabels.color) ?? (Color(hex: "#252423") ?? .primary)
        
        var catStrings: [String] = []
        for cat in data.categories {
            let str = cat.values.map { $0.asText() }.joined(separator: " ")
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
        self.legendPosition = format.legend.position ?? "Top"
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
                legItems.append(LegendItem(id: "s-\(sIdx)", name: sVal.asText(), color: col))
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
            for catStr in catStrings {
                let yr = String(catStr.prefix(4))
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
                    let sName = sVal?.asText() ?? (hasSeries ? "" : mField.displayName)
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
                    let sName = sVal?.asText() ?? (hasSeries ? "" : mField.displayName)
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
                    let sName = sVal?.asText() ?? (hasSeries ? "" : (sIdx < roleYIndices.count ? data.measures[roleYIndices[sIdx]].displayName : ""))
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
        let lineMeasureIndices = (kind == .line) ? roleYIndices : roleY2Indices
        
        // If line chart, gather Y1 bounds from line measures
        if kind == .line {
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
        
        // Prepare Y1 and Y2 ticks
        // Định dạng trục: định dạng tĩnh của measure; không có thì lấy định dạng động của ô đầu tiên có giá trị (ví dụ "0%").
        func axisFormat(_ mIdx: Int?) -> String {
            guard let mIdx else { return "" }
            if let f = data.measures[mIdx].formatString, !f.isEmpty { return f }
            return data.values[mIdx].lazy.flatMap { $0 }.first { $0.formatString != nil }?.formatString ?? ""
        }
        let primaryFormatString = axisFormat(roleYIndices.first ?? (kind == .clusteredBar ? data.measures.indices.first : nil))
        let secondaryFormatString = axisFormat(roleY2Indices.first)
        
        let y1Ticks = ChartAxis.niceTicks(
            min: format.valueAxis.start ?? minValY1,
            max: format.valueAxis.end ?? maxValY1,
            targetCount: 4
        )
        let y1Labels = ChartAxis.labels(
            ticks: y1Ticks,
            units: format.valueAxis.displayUnits,
            precision: format.valueAxis.precision,
            formatString: primaryFormatString
        )
        let y1MinBound = y1Ticks.first ?? 0
        let y1MaxBound = y1Ticks.last ?? 1
        
        var y2Ticks: [Double] = []
        var y2Labels: [String] = []
        var scaledY2Ticks: [Double] = []
        if hasY2 {
            y2Ticks = ChartAxis.niceTicks(
                min: format.valueAxis.secondaryStart ?? minValY2,
                max: format.valueAxis.secondaryEnd ?? maxValY2,
                targetCount: 4
            )
            y2Labels = ChartAxis.labels(
                ticks: y2Ticks,
                units: format.valueAxis.secondaryDisplayUnits,
                precision: format.valueAxis.secondaryPrecision,
                formatString: secondaryFormatString
            )
            let y2MinBound = y2Ticks.first ?? 0
            let y2MaxBound = y2Ticks.last ?? 1
            scaledY2Ticks = y2Ticks.map {
                ComboChart.secondaryScale(value: $0, y2Min: y2MinBound, y2Max: y2MaxBound, targetMin: y1MinBound, targetMax: y1MaxBound)
            }
        }
        
        // Build line points
        for (mOrder, mIdx) in lineMeasureIndices.enumerated() {
            let mField = data.measures[mIdx]
            let mSeriesCount = data.values[mIdx].count
            // Đường Y2 của combo lấy màu tiếp sau các cột (sau các series, hoặc sau các measure Y), như legend.
            let lineSplitsBySeries = hasSeries && mSeriesCount > 1
            let colorIndex = hasY2 ? (hasSeries ? data.series.count : roleYIndices.count) + mOrder : mOrder
            for sIdx in 0..<mSeriesCount {
                let sVal = lineSplitsBySeries && sIdx < data.series.count ? data.series[sIdx] : nil
                let sName = sVal?.asText() ?? mField.displayName
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
                        let y2MinBound = y2Ticks.first ?? 0
                        let y2MaxBound = y2Ticks.last ?? 1
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
                    
                    pts.append(ChartLinePointDatum(
                        pointID: ptID,
                        category: catStrings[cIdx],
                        seriesName: sName,
                        value: scaledV,
                        rawValue: v,
                        opacity: pointOpacity(ptID: ptID),
                        dataLabel: labelText
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
            for (idx, pt) in firstLine.points.enumerated() {
                fitPoints.append((x: Double(idx), y: pt.value))
            }
            if let fit = TrendLine.linearFit(fitPoints) {
                for (idx, pt) in firstLine.points.enumerated() {
                    let y = fit.slope * Double(idx) + fit.intercept
                    computedTrend.append(ChartTrendPointDatum(category: pt.category, y: y))
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
        
        self.hasSecondaryAxis = hasY2
        self.y2Ticks = y2Ticks
        self.y2Labels = y2Labels
        self.scaledY2Ticks = scaledY2Ticks
    }
}

// MARK: - Event Interception View (Right Click)

private struct RightClickDetector: NSViewRepresentable {
    var onRightClick: (CGPoint) -> Void
    
    func makeNSView(context: Context) -> ClickInterceptionNSView {
        let view = ClickInterceptionNSView()
        view.onRightClick = onRightClick
        return view
    }
    
    func updateNSView(_ nsView: ClickInterceptionNSView, context: Context) {
        nsView.onRightClick = onRightClick
    }
    
    class ClickInterceptionNSView: NSView {
        var onRightClick: ((CGPoint) -> Void)?
        
        override func rightMouseDown(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: loc.x, y: bounds.height - loc.y)
            onRightClick?(flipped)
        }
        
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown else {
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
    
    private var chartViewPadded: some View {
        chartViewWithEvents
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { plotWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in plotWidth = w }
            })
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
                .overlay {
                    RightClickDetector { loc in
                        let ptID = findPointID(at: loc)
                        context.actions.contextMenu(ptID, loc)
                    }
                }
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
                                    let ptID = findPointID(at: loc, proxy: proxy, geometry: geo)
                                    context.actions.hover(ptID, loc)
                                case .ended:
                                    context.actions.hover(nil, .zero)
                                }
                            }
                    }
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
        case .line:
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
                    y: .value("Category", bar.category)
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
        .chartYScale(domain: layout.categories)
        .chartXScale(domain: layout.barXDomain)
        .chartYAxis {
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
        .chartXAxis {
            AxisMarks(position: .bottom, values: layout.barXTicks) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: []))
                    .foregroundStyle(Color.gray.opacity(0.18))
                AxisValueLabel {
                    if let d = val.as(Double.self) {
                        let labelText = formattedTickLabel(d, ticks: layout.barXTicks, labels: layout.barXLabels)
                        Text(labelText)
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
        .chartXScale(domain: layout.categories)
        .chartYScale(domain: layout.columnYDomain)
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
        .chartXScale(domain: layout.categories)
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
            ForEach(layout.lineSeries) { s in
                ForEach(s.points) { pt in
                    LineMark(
                        x: .value("Category", pt.category),
                        y: .value("Value", pt.value),
                        series: .value("Series", s.name)
                    )
                    .foregroundStyle(s.color.opacity(pt.opacity))
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
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
        }
        .chartXScale(domain: layout.categories)
        .chartYScale(domain: layout.columnYDomain)
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
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXScale(domain: layout.categories)
        .chartYScale(domain: layout.columnYDomain)
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
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXScale(domain: layout.categories)
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
                    Text(str)
                        .font(.system(size: layout.categoryFontSize))
                        .foregroundColor(Color(hex: "#252423") ?? .primary)
                }
            }
        }
    }
    
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
            let frac = relX / plotW
            let idx = Int(frac * CGFloat(data.categories.count))
            cIdx = Swift.max(0, Swift.min(data.categories.count - 1, idx))
        }
        
        return buildPointID(c: cIdx, s: 0)
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
