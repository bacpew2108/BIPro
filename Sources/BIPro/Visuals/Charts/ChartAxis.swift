import DAXEngine
import Foundation

enum ChartAxis {
    /// Số vạch muốn có ở trục giá trị chính (VM-D19, Desktop ở cỡ visual 660×380: "Rủi ro thấu chi" 0…≈190 ra 0, 50, 100, 150, 200;
    /// cột "Tiền vào/ra" 0…0,96 tỉ ra 0,0/0,5/1,0). Trục phụ thưa hơn (4): "$0K, $20K, $40K". Chưa đo ở visual cao hơn hoặc thấp hơn.
    static let primaryTargetCount = 5
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
        
        // Làm tròn LÊN theo 1, 2, 5 × 10^k (VM-D19: Desktop cột "Tiền vào/ra" max 0,96 tỉ ra $0,0bn/$0,5bn/$1,0bn, không phải bước 0,25 tỉ;
        // "Rủi ro thấu chi" 0…140 ra 0, 50, 100, 150, 200). Bản cũ có thêm bước 2,5 và làm tròn tới gần nhất.
        let niceMultiplier: Double
        if fraction <= 1.0 + 1e-9 {
            niceMultiplier = 1.0
        } else if fraction <= 2.0 + 1e-9 {
            niceMultiplier = 2.0
        } else if fraction <= 5.0 + 1e-9 {
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
    
    /// Khoảng cách tối thiểu giữa hai vạch (đơn vị trang). Số đo trên Desktop (VM-D19, visual 660×380): trục chính ≥ 47 (cột "Rủi ro thấu chi" giữ
    /// 47,5, "Tiền vào/ra" bỏ 46,6, "Chất lượng nợ" 100% bỏ 47,1); trục phụ thưa hơn, ≥ 60 (Pareto trục phải chỉ 0% và 100% ở vùng vẽ cao ≈100, "$0K, $20K, $40K").
    static let minSpacingPrimary = 47.3
    static let minSpacingSecondary = 60.0
    /// Trục giá trị nằm ngang (thanh ngang): nhãn rộng hơn nên thưa hơn; thanh "Giá trị GD" ($0M, $50M … $200M trên ≈590) và "Khiếu nại" (0K…4K)
    /// bỏ bước cách ≈70 và giữ bước cách ≈125.
    static let minSpacingHorizontal = 100.0
    /// Miền trục chỉ kéo lên vạch kế tiếp khi vạch đó cách dữ liệu không quá phần này của miền (Desktop: 0,96 tỉ lên $1,0bn,
    /// 518 lên 600 ở D3 "TB 3 tháng"; Pareto 5,9K không lên 10K mà giữ đúng 5,9K).
    static let domainExtension = 0.20
    /// Trục giá trị nằm ngang chỉ kéo khi cách ≤ 5% (Desktop: thanh max 4,49K không lên 5K, 210M không lên 250M, 0,989 lên 100%).
    static let horizontalDomainExtension = 0.05

    struct FittedTicks {
        var ticks: [Double]
        var lower: Double
        var upper: Double
    }

    /// Vạch theo chiều cao vùng vẽ: bước 1, 2, 5 × 10^k nhỏ nhất mà các vạch còn cách nhau ít nhất `minSpacing`.
    /// Đường không bắt đầu từ 0 khi giá trị nhỏ nhất ≥ 1/3 giá trị lớn nhất (VM-D19: đường "Dòng tiền ròng" 18M…50M ra $10M…$50M, năm 2018
    /// 128M…211M ra $50M…$250M, "số dư BQ/TK" ≈31K…44K ra $30K…$50K; còn 0,25 của Pareto, 0,15 của "số dư" cả giai đoạn thì bắt đầu từ 0).
    static func floatingLow(values: [Double]) -> Double? {
        guard let low = values.min(), let high = values.max(), low > 0, low >= high / 3 else { return nil }
        return low
    }

    /// `floatingFrom`: giá trị nhỏ nhất của đường khi trục không bắt đầu từ 0; cận dưới là vạch ngay dưới giá trị đó (và dưới cả dải dự báo,
    /// nên truyền `min` đã gồm dự báo), cận trên là vạch ngay trên `max`.
    static func fittingTicks(min: Double, max: Double, plotHeight: Double, minSpacing: Double, floating: Bool = false,
                             extend: Double = domainExtension) -> FittedTicks {
        let low = Swift.min(min, max), high = Swift.max(min, max)
        if floating, low > 0, high > low, plotHeight > 0 {
            var exponent = floor(log10((high - low) / 1000))
            while true {
                for multiplier in [1.0, 2.0, 5.0] {
                    let step = multiplier * pow(10.0, exponent)
                    let lower = floor(low / step + 1e-9) * step, upper = ceil(high / step - 1e-9) * step
                    guard plotHeight * step / (upper - lower) >= minSpacing - 1e-9 else { continue }
                    let factor = pow(10.0, Double(Swift.max(0, Int(ceil(-floor(log10(step)))) + 2)))
                    let first = Int((lower / step).rounded()), last = Int((upper / step).rounded())
                    var indices = Array(first...last)
                    // Bước dạng 1 × 10^k: Desktop chỉ ghi nhãn ở bội chẵn (miền $10M…$50M của "Dòng tiền ròng" ghi $20M và $40M); miền vẫn như cũ.
                    if multiplier == 1, indices.count > 3 { indices = indices.filter { $0 % 2 == 0 } }
                    let ticks: [Double] = indices.map { index in
                        let raw: Double = Double(index) * step
                        return (raw * factor).rounded() / factor
                    }
                    return FittedTicks(ticks: ticks, lower: lower, upper: upper)
                }
                exponent += 1
            }
        }
        let from = low >= 0 ? 0.0 : low
        guard high > from, plotHeight > 0 else {
            let ticks = niceTicks(min: min, max: max, targetCount: primaryTargetCount)
            return FittedTicks(ticks: ticks, lower: ticks.first ?? 0, upper: ticks.last ?? 1)
        }
        let range = high - from
        var exponent = floor(log10(range / 1000))
        while true {
            for multiplier in [1.0, 2.0, 5.0] {
                let step = multiplier * pow(10.0, exponent)
                let upperTick = ceil(high / step - 1e-9) * step
                let lowerTick = low >= 0 ? 0.0 : floor(low / step + 1e-9) * step
                let upper = upperTick - high <= extend * range ? upperTick : high
                let lower = low >= 0 ? 0.0 : (low - lowerTick <= extend * range ? lowerTick : low)
                let spacing = plotHeight * step / (upper - lower)
                guard spacing >= minSpacing - 1e-9 else { continue }
                let factor = pow(10.0, Double(Swift.max(0, Int(ceil(-floor(log10(step)))) + 2)))
                let first = Int(ceil(lower / step - 1e-9)), last = Int(floor(upper / step + 1e-9))
                var ticks = first <= last ? (first...last).map { i -> Double in
                    let value = Double(i) * step
                    return abs(value) < step * 1e-9 ? 0 : (value * factor).rounded() / factor
                } : []
                if ticks.isEmpty { ticks = [lower, upper] }
                return FittedTicks(ticks: ticks, lower: lower, upper: upper)
            }
            exponent += 1
        }
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
        let unit = NumberDisplay.resolve(units, reference: maxAbs, axis: true)
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
