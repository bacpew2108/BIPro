import Foundation
import Testing
@testable import BIPro

@Suite("Dự báo line chart")
struct ForecastTests {
    /// Xu hướng tuyến tính cộng mùa vụ 12 tháng, không nhiễu: dự báo phải ra gần đúng giá trị tiếp theo.
    @Test func chuoiXuHuongCongMuaVu() throws {
        let season = [0.0, 3, 6, 9, 6, 3, 0, -3, -6, -9, -6, -3]
        let y = (0..<48).map { 100 + 2 * Double($0) + season[$0 % 12] }
        let out = try #require(Forecast.project(y, length: 6, confidence: 0.95))
        #expect(out.count == 6)
        for (h, p) in out.enumerated() {
            let expected = 100 + 2 * Double(48 + h) + season[(48 + h) % 12]
            #expect(abs(p.y - expected) < 2, "bước \(h + 1): \(p.y) so với \(expected)")
            #expect(p.lower <= p.y && p.y <= p.upper)
        }
    }

    @Test func daiTinCayLoeDan() throws {
        var rng = SystemRandomNumberGenerator()
        let y = (0..<60).map { 50 + Double($0) + Double.random(in: -5...5, using: &rng) + 10 * sin(Double($0) / 12 * 2 * .pi) }
        let out = try #require(Forecast.project(y, length: 6, confidence: 0.95))
        let widths = out.map { $0.upper - $0.lower }
        #expect(widths.first! > 0)
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 }, "dải không hẹp lại theo thời gian")
        let wide = try #require(Forecast.project(y, length: 6, confidence: 0.99))
        #expect(wide[0].upper - wide[0].lower > widths[0], "tin cậy cao hơn thì dải rộng hơn")
    }

    @Test func quaNganThiKhongDuBao() {
        #expect(Forecast.project((0..<20).map(Double.init), length: 6, confidence: 0.95) == nil)
        #expect(Forecast.project((0..<30).map(Double.init), length: 0, confidence: 0.95) == nil)
    }

    @Test func serialNgayVaThangTuongLai() {
        let jan2013 = DateDisplay.serial(year: 2013, month: 1, day: 1)
        #expect(jan2013 == 41275)
        #expect(DateDisplay.serial(year: 2013, month: 13, day: 1) == DateDisplay.serial(year: 2014, month: 1, day: 1))
        #expect(DateDisplay.serial(year: 2018, month: 14, day: 1) == DateDisplay.serial(year: 2019, month: 2, day: 1))
        let back = DateDisplay.civil(serial: DateDisplay.serial(year: 2019, month: 2, day: 1))
        #expect(back.year == 2019 && back.month == 2 && back.day == 1)
    }

    /// Số liệu thật của VM C2 B6: Trans Amount theo tháng 2013–2018 (D1) và dự báo 6 tháng của Power BI.
    /// Thuật toán của Power BI không công bố; ở đây chỉ kiểm hình dạng gần (cùng bậc, dải rộng cùng cỡ), không đòi khớp số.
    @Test func soVoiDuBaoCuaPowerBI() throws {
        let y = "702158,2726925,4730319,7378368,11680753,18291949,18021295,21028812,23438702,27570900,28525741,40212608,42592232,31281777,37383803,37491621,41734137,59676368,42474509,43566089,46479840,46615494,47591233,61903629,66245580,45126077,54113431,54844144,59914969,81612628,59959796,61914116,63051039,66593805,67447282,86907598,93622316,67669651,76962100,79176076,84998109,118709525,90753728,96292854,100840753,105841654,107962328,141022374,149308208,105167650,120829179,123419806,130633543,180533013,132462485,135565258,140446254,143934150,142695523,183333942,192082358,128749327,148188411,147273343,149884936,209902026,147337119,150639333,148297693,151889624,148842094,171697094".split(separator: ",").map { Double($0)! }
        #expect(y.count == 72)
        let power: [Double] = [165_196_846, 148_568_393, 156_943_006, 160_534_293, .nan, 199_593_511]
        let widths: [Int: Double] = [0: 187_508_399 - 142_885_293, 5: 225_186_316 - 174_000_705]
        let ours = try #require(Forecast.project(y, length: 6, confidence: 0.95))
        for (i, expected) in power.enumerated() where !expected.isNaN {
            #expect(abs(ours[i].y - expected) / expected < 0.35, "tháng dự báo \(i + 1): \(ours[i].y) so với Power BI \(expected)")
        }
        for (i, width) in widths { #expect((ours[i].upper - ours[i].lower) / width > 0.3 && (ours[i].upper - ours[i].lower) / width < 3, "độ rộng dải tháng \(i + 1)") }
    }
}
