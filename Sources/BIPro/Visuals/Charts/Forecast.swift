// Dự báo của line chart (Phase C, [SUY ĐOÁN]): Power BI không công bố thuật toán, chỉ quan sát được hình: đường dự báo nối từ
// điểm cuối, có dải tin cậy xám loe dần, lặp lại mùa vụ của dữ liệu (D1 "Dự báo 6 tháng", ảnh VM-P/d1.png).
// Ở đây dùng Holt-Winters cộng tính (mùa vụ 12 khi có từ 2 năm dữ liệu tháng, không thì Holt tuyến tính), tham số chọn
// bằng lưới sao cho tổng bình phương sai số một bước nhỏ nhất; dải tin cậy theo công thức phương sai của ETS(A,A,A).
// Số liệu dự báo vì thế chỉ gần đúng, không khớp từng số với Power BI.
import Foundation

enum Forecast {
    struct Point: Hashable, Sendable {
        var y: Double
        var lower: Double
        var upper: Double
    }

    /// `values`: chuỗi theo thứ tự thời gian, bước đều. `length`: số bước dự báo. `confidence`: 0…1. nil nếu quá ngắn.
    static func project(_ values: [Double], length: Int, confidence: Double, season: Int = 12) -> [Point]? {
        let n = values.count
        // [SUY ĐOÁN] Cần ít nhất hai mùa: ngắn hơn thì dải tin cậy loe vô nghĩa (D1 lọc một năm), nên không dự báo.
        guard length > 0, n >= 2 * season else { return nil }
        let seasonal = true
        let m = season

        var best: (sse: Double, alpha: Double, beta: Double, gamma: Double, state: State)?
        let alphas = [0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9]
        let betas = [0.005, 0.01, 0.03, 0.06, 0.1, 0.25]
        let gammas = seasonal ? [0.02, 0.05, 0.1, 0.2, 0.4, 0.6, 0.8] : [0.0]
        for a in alphas { for b in betas { for g in gammas {
            let run = fit(values, m: m, seasonal: seasonal, alpha: a, beta: b, gamma: g)
            if best == nil || run.sse < best!.sse { best = (run.sse, a, b, g, run.state) }
        } } }
        guard let best else { return nil }

        let dof = Double(max(1, n - (seasonal ? m : 2)))
        let sigma = (best.sse / dof).squareRoot()
        let z = zScore(confidence)
        var out: [Point] = []
        for h in 1...length {
            let yHat = best.state.level + Double(h) * best.state.trend + (seasonal ? best.state.seasonals[(h - 1) % m] : 0)
            var variance = 1.0
            if h > 1 {
                for j in 1..<h {
                    var c = best.alpha * (1 + Double(j) * best.beta)
                    if seasonal, j % m == 0 { c += best.gamma * (1 - best.alpha) }
                    variance += c * c
                }
            }
            let half = z * sigma * variance.squareRoot()
            out.append(Point(y: yHat, lower: yHat - half, upper: yHat + half))
        }
        return out
    }

    private struct State { var level: Double; var trend: Double; var seasonals: [Double] }

    /// Chạy bộ lọc; `seasonals[i]` là thành phần mùa của bước kế tiếp thứ i sau điểm cuối.
    private static func fit(_ y: [Double], m: Int, seasonal: Bool, alpha: Double, beta: Double, gamma: Double) -> (sse: Double, state: State) {
        let n = y.count
        var level: Double, trend: Double
        var season = [Double](repeating: 0, count: m)
        if seasonal {
            let first = y[0..<m].reduce(0, +) / Double(m)
            let second = y[m..<(2 * m)].reduce(0, +) / Double(m)
            trend = (second - first) / Double(m)
            // Mức trước điểm 0, sao cho y[i] ≈ level + (i+1)·trend + season[i] và tổng mùa ≈ 0.
            level = first - trend * Double(m + 1) / 2
            for i in 0..<m { season[i] = y[i] - level - Double(i + 1) * trend }
        } else {
            level = y[0]
            trend = (y[min(n - 1, 3)] - y[0]) / Double(min(n - 1, 3))
        }
        var sse = 0.0
        let start = seasonal ? m : 1
        for t in start..<n {
            let s = seasonal ? season[t % m] : 0
            let predicted = level + trend + s
            let error = y[t] - predicted
            sse += error * error
            let newLevel = alpha * (y[t] - s) + (1 - alpha) * (level + trend)
            trend = beta * (newLevel - level) + (1 - beta) * trend
            if seasonal { season[t % m] = gamma * (y[t] - newLevel) + (1 - gamma) * s }
            level = newLevel
        }
        // Mùa của bước n, n+1, … nằm ở season[n % m], season[(n+1) % m], …
        let next = seasonal ? (0..<m).map { season[(n + $0) % m] } : []
        return (sse, State(level: level, trend: trend, seasonals: next))
    }

    private static func zScore(_ confidence: Double) -> Double {
        switch confidence {
        case ..<0.85: 1.2816
        case ..<0.925: 1.6449
        case ..<0.97: 1.96
        default: 2.5758
        }
    }
}
