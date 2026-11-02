import Foundation

enum ComboChart {
    /// Quy đổi giá trị Y2 về toạ độ dải Y1 (hoặc dải đích) theo dải vạch Y2 riêng.
    static func secondaryScale(value: Double, y2Min: Double, y2Max: Double, targetMin: Double, targetMax: Double) -> Double {
        guard y2Max > y2Min else { return targetMin }
        let fraction = (value - y2Min) / (y2Max - y2Min)
        return targetMin + fraction * (targetMax - targetMin)
    }
    
    static func secondaryScale(value: Double, y2Range: ClosedRange<Double>, targetRange: ClosedRange<Double>) -> Double {
        secondaryScale(
            value: value,
            y2Min: y2Range.lowerBound,
            y2Max: y2Range.upperBound,
            targetMin: targetRange.lowerBound,
            targetMax: targetRange.upperBound
        )
    }
}
