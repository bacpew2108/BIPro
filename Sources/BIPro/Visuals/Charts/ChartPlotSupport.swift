import DAXEngine
import Foundation
import SwiftUI

// Trục giá trị và lưới dùng chung cho các biểu đồ tự vẽ (thác nước, ruy-băng; VM-D15 mục 4). Nhãn trục dùng `ChartAxis` như biểu đồ cột,
// nên đơn vị, độ chính xác và "Nhỏ nhất/Lớn nhất" của thẻ Trục Y áp giống nhau.

struct ValueAxisScale {
    let ticks: [Double]
    let labels: [String]

    var lower: Double { ticks.first ?? 0 }
    var upper: Double { ticks.last ?? 1 }

    /// Miền `[lo, hi]` của dữ liệu → các vạch đẹp; thẻ Trục Y (`start`, `end`) ghi đè hai đầu.
    init(low: Double, high: Double, format: VisualFormat, formatString: String?) {
        ticks = ChartAxis.niceTicks(min: format.valueAxis.start ?? low, max: format.valueAxis.end ?? high, targetCount: 4)
        labels = ChartAxis.labels(ticks: ticks, units: format.valueAxis.displayUnits, precision: format.valueAxis.precision,
                                  formatString: formatString)
    }

    /// Toạ độ y (0 ở trên cùng) của `value` trong chiều cao `height`.
    func y(_ value: Double, height: CGFloat) -> CGFloat {
        let span = upper - lower
        guard span > 0 else { return height }
        return height - CGFloat((value - lower) / span) * height
    }

    /// Bề rộng cột nhãn bên trái.
    func labelWidth(fontSize: CGFloat) -> CGFloat {
        CGFloat((labels.map(\.count).max() ?? 1)) * fontSize * 0.6 + 12
    }
}

/// Lưới ngang mờ và nhãn trục Y ở bên trái, vẽ trong khung `plot` (toạ độ của view cha).
struct ValueAxisGrid: View {
    let scale: ValueAxisScale
    let plot: CGRect
    let fontSize: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(scale.ticks.enumerated()), id: \.offset) { index, tick in
                let y = plot.minY + scale.y(tick, height: plot.height)
                Path { path in
                    path.move(to: CGPoint(x: plot.minX, y: y))
                    path.addLine(to: CGPoint(x: plot.maxX, y: y))
                }
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.6)
                Text(index < scale.labels.count ? scale.labels[index] : "")
                    .font(.system(size: fontSize))
                    .foregroundColor(Color(hex: "#605E5C") ?? .secondary)
                    .lineLimit(1)
                    .position(x: plot.minX - (scale.labelWidth(fontSize: fontSize) - 8) / 2 - 4, y: y)
            }
        }
    }
}

/// Cứ mỗi `stride` nhãn mới hiện một nhãn, để nhãn không chồng lên nhau khi có nhiều danh mục.
enum ChartLabelDensity {
    /// `footprint`: bề rộng (hoặc cao) một nhãn chiếm; `slot`: bề rộng (hoặc cao) của một danh mục.
    static func stride(footprint: CGFloat, slot: CGFloat) -> Int {
        guard slot > 0 else { return 1 }
        return Swift.max(1, Int((footprint / slot).rounded(.up)))
    }
}

/// Số của một ô giá trị, nil khi trống.
func chartNumber(_ cell: DataCell) -> Double? { NumberDisplay.numericValue(cell.value) }

/// Điểm dữ liệu của danh mục `index` (và series `series` khi có), cùng cách đặt khoá như `CartesianChartView`.
func chartPointID(data: CategoricalData, category index: Int, series: Int? = nil) -> DataPointID {
    var dict: [String: Value] = [:]
    if index >= 0, index < data.categories.count {
        for (level, field) in data.categoryLevels.enumerated() where level < data.categories[index].values.count {
            dict[field.queryRef] = data.categories[index].values[level]
        }
    }
    if let series, let field = data.seriesField, series < data.series.count { dict[field.queryRef] = data.series[series] }
    return DataPointID(dict)
}

func chartCategoryNames(_ data: CategoricalData) -> [String] {
    data.categories.map { key in key.values.enumerated().map { data.categoryLevels.text($1, at: $0) }.joined(separator: " ") }
}
