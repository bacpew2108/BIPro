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
}
