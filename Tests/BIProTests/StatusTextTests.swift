import Foundation
import Testing
@testable import BIPro

@Suite struct StatusTextTests {
    @Test func thoiGianDuoiMotGiayDungMs() {
        #expect(StatusText.elapsed(0) == "0,0 ms")
        #expect(StatusText.elapsed(523_100_000) == "523,1 ms")
        #expect(StatusText.elapsed(999_900_000) == "999,9 ms")
        #expect(StatusText.elapsed(45_600_000) == "45,6 ms")
    }

    @Test func thoiGianTuMotGiayTroLenDungGiay() {
        #expect(StatusText.elapsed(1_000_000_000) == "1,00 s")
        #expect(StatusText.elapsed(12_340_000_000) == "12,34 s")
        #expect(StatusText.elapsed(123_456_789_012) == "123,46 s")
    }

    @Test func soCoHangNghinDungDauCham() {
        #expect(StatusText.formatNumber(0) == "0")
        #expect(StatusText.formatNumber(14) == "14")
        #expect(StatusText.formatNumber(96) == "96")
        #expect(StatusText.formatNumber(1_234) == "1.234")
        #expect(StatusText.formatNumber(1_234_567) == "1.234.567")
    }

    @Test func tungTrangThaiKhongPhaiDoneKhongCoSoLieu() {
        #expect(StatusText.summary(status: .idle) == "Chưa chạy")
        #expect(StatusText.summary(status: .running) == "Đang chạy…")
        #expect(StatusText.summary(status: .cancelled) == "Đã huỷ")
        #expect(StatusText.summary(status: .failed) == "Lỗi")
    }

    @Test func trangThaiDoneCoDayDuThongTinTheoMauPowerBI() {
        let text1 = StatusText.summary(
            status: .done,
            elapsedNanoseconds: 523_100_000,
            queryIndex: 1,
            queryCount: 1,
            resultIndex: 1,
            resultCount: 1,
            columns: 14,
            rows: 96
        )
        #expect(text1 == "Thành công (523,1 ms) · Truy vấn 1/1 · Kết quả 1/1 · 14 cột, 96 dòng")

        let text2 = StatusText.summary(
            status: .done,
            elapsedNanoseconds: 12_340_000_000,
            queryIndex: 2,
            queryCount: 3,
            resultIndex: 1,
            resultCount: 2,
            columns: 14,
            rows: 1_234
        )
        #expect(text2 == "Thành công (12,34 s) · Truy vấn 2/3 · Kết quả 1/2 · 14 cột, 1.234 dòng")
    }

    @Test func validOrderNhanTapConVaHoanViKhongTrungNhau() {
        // Hoán vị đủ
        #expect(QueryResultsView.validOrder([2, 0, 1], rowCount: 3) == [2, 0, 1])

        // Tập con (khi có bộ lọc)
        #expect(QueryResultsView.validOrder([2, 0], rowCount: 3) == [2, 0])
        #expect(QueryResultsView.validOrder([1], rowCount: 3) == [1])
        #expect(QueryResultsView.validOrder([], rowCount: 3) == [])

        // Trùng nhau -> nil
        #expect(QueryResultsView.validOrder([1, 1], rowCount: 3) == nil)

        // Ngoài khoảng 0..<rowCount -> nil
        #expect(QueryResultsView.validOrder([3], rowCount: 3) == nil)
        #expect(QueryResultsView.validOrder([-1], rowCount: 3) == nil)

        // order nil -> nil
        #expect(QueryResultsView.validOrder(nil, rowCount: 3) == nil)
    }
}
