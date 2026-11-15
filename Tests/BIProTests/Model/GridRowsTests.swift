import Foundation
import PBIXKit
import Testing
@testable import BIPro
@testable import PBIXKit

/// Phase E (T029): sắp xếp và lọc lưới Table view chỉ để xem (không đụng mô hình): chọn dòng nào, theo thứ tự nào.
@Suite struct GridRowsTests {
    let numbers = DecodedColumn(name: "n", dataType: .int64, storage: .values([30, 10, .nan, 20, 10]))
    let words = DecodedColumn(name: "w", dataType: .string, storage: .dictionary(codes: [1, 0, -1, 2, 0], dictionary: [.string("Beta"), .string("alpha"), .string("Gamma")]))

    @Test func khongSapXepKhongLocLaTatCaDong() {
        #expect(GridRows.compute(columns: [numbers, words], sort: nil, filter: nil) == nil)
    }

    @Test func sapXepSoTangGiamVaDongTrongLenDau() {
        let up = GridRows.compute(columns: [numbers, words], sort: .init(column: 0, ascending: true), filter: nil)
        #expect(up == [2, 1, 4, 3, 0])     // trống, 10, 10 (giữ thứ tự gốc), 20, 30
        let down = GridRows.compute(columns: [numbers, words], sort: .init(column: 0, ascending: false), filter: nil)
        #expect(down == [0, 3, 1, 4, 2])
    }

    @Test func sapXepChuKhongPhanBietHoaThuong() {
        let up = GridRows.compute(columns: [numbers, words], sort: .init(column: 1, ascending: true), filter: nil)
        #expect(up == [2, 0, 1, 4, 3])     // dòng: alpha, Beta, trống, Gamma, Beta → trống, alpha, Beta, Beta, Gamma
    }

    @Test func locChuaChuoiKhongPhanBietHoaThuongRoiSapXep() {
        let rows = GridRows.compute(columns: [numbers, words], sort: nil, filter: .init(column: 1, text: "ALP"))
        #expect(rows == [0])               // chỉ dòng 'alpha'
        let sorted = GridRows.compute(columns: [numbers, words], sort: .init(column: 0, ascending: false), filter: .init(column: 1, text: "a"))
        #expect(sorted == [0, 3, 1, 4])    // dòng có 'a' (Beta, alpha, Gamma, alpha), theo số giảm dần
        #expect(GridRows.compute(columns: [numbers, words], sort: nil, filter: .init(column: 1, text: "zzz")) == [])
        #expect(GridRows.compute(columns: [numbers, words], sort: nil, filter: .init(column: 1, text: "")) == nil)
    }
}
