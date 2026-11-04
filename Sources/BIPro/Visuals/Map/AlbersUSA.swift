import Foundation

// MARK: - Conic Equal-Area Projection Helper

private struct ConicEqualArea {
    let n: Double
    let c: Double
    let rho0: Double
    let rotateLon: Double
    let rotateLat: Double
    let centerLonRad: Double
    let centerLatRad: Double

    init(
        phi1Deg: Double,
        phi2Deg: Double,
        rotateLon: Double,
        rotateLat: Double,
        centerLonDeg: Double,
        centerLatDeg: Double
    ) {
        let phi1 = phi1Deg * .pi / 180.0
        let phi2 = phi2Deg * .pi / 180.0
        let nVal = (sin(phi1) + sin(phi2)) / 2.0
        let cVal = cos(phi1) * cos(phi1) + 2.0 * nVal * sin(phi1)
        let phi0 = centerLatDeg * .pi / 180.0
        let v0 = cVal - 2.0 * nVal * sin(phi0)
        let r0 = sqrt(max(0.0, v0)) / nVal

        self.n = nVal
        self.c = cVal
        self.rho0 = r0
        self.rotateLon = rotateLon
        self.rotateLat = rotateLat
        self.centerLonRad = centerLonDeg * .pi / 180.0
        self.centerLatRad = phi0
    }

    func project(lon: Double, lat: Double) -> (Double, Double)? {
        let lambdaR = (lon + rotateLon) * .pi / 180.0
        let phiR = (lat + rotateLat) * .pi / 180.0
        let v = c - 2.0 * n * sin(phiR)
        guard v >= 0 else { return nil }
        let rho = sqrt(v) / n
        let theta = n * (lambdaR - centerLonRad)
        let x = rho * sin(theta)
        let y = rho * cos(theta) - rho0
        return (x, y)
    }
}

// MARK: - AlbersUSA

enum AlbersUSA {
    // [SUY ĐOÁN] Hằng số phép chiếu Albers USA (d3-geo albersUsa)
    // lower48: xoay [96, 0], tâm [-0.6, 38.7], vĩ tuyến chuẩn [29.5, 45.5]
    private static let lower48 = ConicEqualArea(
        phi1Deg: 29.5,
        phi2Deg: 45.5,
        rotateLon: 96.0,
        rotateLat: 0.0,
        centerLonDeg: -0.6,
        centerLatDeg: 38.7
    )

    // [SUY ĐOÁN] Alaska: xoay [154, 0], tâm [-2, 58.5], chuẩn [55, 65], tỉ lệ 0.35
    private static let alaska = ConicEqualArea(
        phi1Deg: 55.0,
        phi2Deg: 65.0,
        rotateLon: 154.0,
        rotateLat: 0.0,
        centerLonDeg: -2.0,
        centerLatDeg: 58.5
    )

    // [SUY ĐOÁN] Hawaii: xoay [157, 0], tâm [-3, 19.9], chuẩn [8, 18], tỉ lệ 1.0
    private static let hawaii = ConicEqualArea(
        phi1Deg: 8.0,
        phi2Deg: 18.0,
        rotateLon: 157.0,
        rotateLat: 0.0,
        centerLonDeg: -3.0,
        centerLatDeg: 19.9
    )

    // [SUY ĐOÁN] Dời vị trí Alaska và Hawaii xuống góc dưới trái:
    // Alaska nằm bên trái Hawaii, cả hai ở góc dưới trái (x < 40%, y > 70%).
    private static let alaskaScale = 0.35
    private static let alaskaOffsetX = -0.28
    private static let alaskaOffsetY = 0.20

    private static let hawaiiScale = 1.0
    private static let hawaiiOffsetX = -0.17
    private static let hawaiiOffsetY = 0.20

    /// Chiếu một điểm kinh/vĩ độ thành toạ độ 2D gộp Albers USA.
    /// - 48 bang liền kề dùng Conic Equal-Area;
    /// - Alaska và Hawaii dùng phép chiếu riêng, thu nhỏ và dời về góc dưới trái.
    static func project(longitude lon: Double, latitude lat: Double) -> CGPoint? {
        guard lon.isFinite, lat.isFinite else { return nil }

        // Nhận diện vùng Alaska: mọi điểm vĩ độ >= 50°N hoặc chuỗi đảo Aleutian
        if lat >= 50.0 || ((lon < -130.0 || lon > 160.0) && lat >= 45.0) {
            let adjustedLon = lon > 0 ? lon - 360.0 : lon
            guard let pt = alaska.project(lon: adjustedLon, lat: lat) else { return nil }
            let x = pt.0 * alaskaScale + alaskaOffsetX
            let y = pt.1 * alaskaScale + alaskaOffsetY
            return CGPoint(x: x, y: y)
        }

        // Nhận diện vùng Hawaii
        if lon >= -165.0 && lon <= -150.0 && lat >= 15.0 && lat <= 25.0 {
            guard let pt = hawaii.project(lon: lon, lat: lat) else { return nil }
            let x = pt.0 * hawaiiScale + hawaiiOffsetX
            let y = pt.1 * hawaiiScale + hawaiiOffsetY
            return CGPoint(x: x, y: y)
        }

        // 48 bang liền kề (Lower 48)
        guard let pt = lower48.project(lon: lon, lat: lat) else { return nil }
        return CGPoint(x: pt.0, y: pt.1)
    }
}
