import DAXEngine
import Foundation

enum ChartAxis {
    /// Tính vạch "đẹp" (bước 1, 2, 2.5, 5 × 10^k), bao trọn [min, max] và bắt đầu từ 0 khi min ≥ 0.
    static func niceTicks(min: Double, max: Double, targetCount: Int = 4) -> [Double] {
        var minVal = min
        var maxVal = max
        if minVal > maxVal {
            swap(&minVal, &maxVal)
        }
        
        let startFromZero = minVal >= 0
        let effectiveMin = startFromZero ? 0.0 : minVal
        let effectiveMax = maxVal
        
        if effectiveMax <= effectiveMin {
            if effectiveMax == 0 && effectiveMin == 0 {
                return [0.0, 1.0]
            } else if effectiveMax > 0 {
                return [0.0, effectiveMax]
            } else {
                return [effectiveMin, 0.0]
            }
        }
        
        let span = effectiveMax - effectiveMin
        let count = Swift.max(2, targetCount)
        let rawStep = span / Double(count - 1)
        
        let exponent = floor(log10(rawStep))
        let fraction = rawStep / pow(10.0, exponent)
        
        let niceMultiplier: Double
        if fraction <= 1.25 {
            niceMultiplier = 1.0
        } else if fraction <= 2.25 {
            niceMultiplier = 2.0
        } else if fraction <= 3.75 {
            niceMultiplier = 2.5
        } else if fraction <= 7.5 {
            niceMultiplier = 5.0
        } else {
            niceMultiplier = 10.0
        }
        
        let step = niceMultiplier * pow(10.0, exponent)
        
        let startIdx: Int
        if startFromZero {
            startIdx = 0
        } else {
            startIdx = Int(floor((effectiveMin / step) + 1e-9))
        }
        
        let endIdx = Int(ceil((effectiveMax / step) - 1e-9))
        
        let prec = Swift.max(0, Int(ceil(-exponent)) + 2)
        let factor = pow(10.0, Double(prec))
        
        var ticks: [Double] = []
        for i in startIdx...endIdx {
            var val = Double(i) * step
            if abs(val) < step * 1e-9 {
                val = 0.0
            } else {
                val = (val * factor).rounded() / factor
            }
            ticks.append(val)
        }
        
        if ticks.count < 2 {
            var lastVal = (ticks.last ?? 0) + step
            lastVal = (lastVal * factor).rounded() / factor
            ticks.append(lastVal)
        }
        return ticks
    }
    
    /// Định dạng danh sách nhãn:
    /// - mọi vạch cùng một đơn vị, chọn theo giá trị tuyệt đối lớn nhất;
    /// - chữ số thập phân vừa đủ để các vạch khác nhau;
    /// - ví dụ:
    ///   - (0…30M, `$#,0`) → `["$0M","$10M","$20M","$30M"]`
    ///   - (0…1bn bước 0.5bn) → `["$0.0bn","$0.5bn","$1.0bn"]`
    ///   - định dạng `0%` → `["0%","5%","10%","15%"]`
    /// Vạch của trục log: các luỹ thừa của 10 từ luỹ thừa ngay dưới `low` đến luỹ thừa ngay trên `high` (ít nhất hai vạch).
    static func logTicks(low: Double, high: Double) -> [Double] {
        guard low > 0, high >= low else { return [1, 10] }
        let first = Int(floor(log10(low) + 1e-9))
        var last = Int(ceil(log10(high) - 1e-9))
        if last <= first { last = first + 1 }
        return (first...last).map { pow(10.0, Double($0)) }
    }

    static func labels(
        ticks: [Double],
        units: DisplayUnits = .auto,
        precision: Int? = nil,
        formatString: String? = nil
    ) -> [String] {
        guard !ticks.isEmpty else { return [] }
        
        let isPercent = (formatString ?? "").contains("%")
        if isPercent {
            let scaled = ticks.map { $0 * 100 }
            let p: Int
            if let precision = precision {
                p = Swift.max(0, precision)
            } else {
                p = optimalPrecision(for: scaled)
            }
            return scaled.map { NumberDisplay.decimal($0, precision: p) + "%" }
        }
        
        let maxAbs = ticks.map { abs($0) }.max() ?? 0
        let unit = NumberDisplay.resolve(units, reference: maxAbs)
        let div = NumberDisplay.divisor(unit)
        let sfx = NumberDisplay.suffix(unit)
        let (prefix, patternSuffix) = NumberDisplay.affixes(of: formatString ?? "")
        
        let scaled = ticks.map { $0 / div }
        let p: Int
        if let precision = precision {
            p = Swift.max(0, precision)
        } else {
            p = optimalPrecision(for: scaled)
        }
        
        return scaled.map { val in
            prefix + NumberDisplay.decimal(val, precision: p) + sfx + patternSuffix
        }
    }
    
    private static func optimalPrecision(for values: [Double]) -> Int {
        guard values.count > 1 else { return 0 }
        for p in 0...6 {
            let formatted = values.map { NumberDisplay.decimal($0, precision: p) }
            let distinct = Set(formatted).count == values.count
            let allFit = values.allSatisfy { val in
                let mult = pow(10.0, Double(p))
                let s = val * mult
                return abs(s - s.rounded()) < 1e-4
            }
            if distinct && allFit {
                return p
            }
        }
        return 0
    }
}

/// Nhãn danh mục xoay dọc: giới hạn chiều dài để không lấn vùng vẽ (cắt bằng "…"), dùng chiều cao chart đo được.
struct CategoryLabelFit {
    /// Tỉ lệ chiều cao chart tối đa dành cho nhãn xoay: Desktop cắt Pareto D3 còn ~19 ký tự ở cao 380 và ~8 ký tự ở cao 220
    /// (`docs/phase-d-evidence/vm-d9/QUAN-SAT.md` mục 6), khớp 0,5 của chiều cao vùng chart.
    static let heightShare: CGFloat = 0.5
    static let fallbackHeight: CGFloat = 300
    static let minLength = 8

    let fontSize: CGFloat
    let chartHeight: CGFloat

    /// Số ký tự tối đa (kể cả "…").
    var maxLength: Int {
        let height = chartHeight > 0 ? chartHeight : Self.fallbackHeight
        return max(Self.minLength, Int(height * Self.heightShare / (fontSize * 0.6)))
    }

    func text(_ label: String) -> String {
        guard label.count > maxLength else { return label }
        return String(label.prefix(maxLength - 1)) + "…"
    }

    /// Độ rộng chung (trước khi xoay) của nhãn dài nhất sau khi cắt, để các nhãn thẳng hàng.
    func width(for labels: [String]) -> CGFloat {
        CGFloat(labels.map { min($0.count, maxLength) }.max() ?? 0) * fontSize * 0.62
    }
}

/// Cửa sổ danh mục đang thấy khi trục chữ cuộn ngang.
enum CategoryWindow {
    /// `count` danh mục liên tiếp bắt đầu từ `first` (không có thì từ đầu), kẹp để không trượt quá cuối.
    static func slice(_ categories: [String], from first: String, count: Int) -> [String] {
        let visible = max(1, count)
        let start = max(0, min(categories.count - visible, categories.firstIndex(of: first) ?? 0))
        return Array(categories[start..<min(categories.count, start + visible)])
    }
}
