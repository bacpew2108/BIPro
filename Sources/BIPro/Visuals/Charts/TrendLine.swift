import Foundation

enum TrendLine {
    /// Tính đường hồi quy tuyến tính theo phương pháp bình phương tối thiểu (least squares).
    /// Ít hơn 2 điểm hoặc tất cả hoành độ trùng nhau thì trả về nil.
    static func linearFit(_ points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        let meanX = sumX / n
        let meanY = sumY / n
        
        var ssXX = 0.0
        var ssXY = 0.0
        for p in points {
            let dx = p.x - meanX
            let dy = p.y - meanY
            ssXX += dx * dx
            ssXY += dx * dy
        }
        
        guard abs(ssXX) > 1e-12 else { return nil }
        let slope = ssXY / ssXX
        let intercept = meanY - slope * meanX
        return (slope: slope, intercept: intercept)
    }
}
