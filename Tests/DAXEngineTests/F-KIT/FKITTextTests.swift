// Hàm chuỗi FORMAT (F-KIT, đợt 2): mỗi mẫu Nhom6 có một ca. Đáp án tính bằng quy tắc làm tròn nửa xa số 0
// trên giá trị thập phân (Python 3 decimal, ROUND_HALF_UP trên dạng thập phân của số).
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct FKITTextTests {

    /// Một ca FORMAT: giá trị, mẫu và kết quả kỳ vọng.
    struct CaFormat: Sendable {
        let giaTri: Value
        let mau: String
        let kyVong: String
    }

    /// 12 mẫu khác nhau của Nhom6, mỗi mẫu một ca (kèm dấu, phần 0, dấu âm, phần thập phân).
    static let cacCa: [CaFormat] = [
        CaFormat(giaTri: .double(1_234_567), mau: "#,0", kyVong: "1,234,567"),
        CaFormat(giaTri: .double(-1234), mau: "$#,0", kyVong: "-$1,234"),
        CaFormat(giaTri: .double(0.0523), mau: "+0.0%;-0.0%;0.0%", kyVong: "+5.2%"),
        CaFormat(giaTri: .double(0.125), mau: "0.0%", kyVong: "12.5%"),
        CaFormat(giaTri: .double(1234.5678), mau: "#,0.0", kyVong: "1,234.6"),
        CaFormat(giaTri: .double(0.125), mau: "0%", kyVong: "13%"),
        CaFormat(giaTri: .double(-2.4), mau: "0", kyVong: "-2"),
        CaFormat(giaTri: .double(2.25), mau: "0.0", kyVong: "2.3"),
        CaFormat(giaTri: .integer(12), mau: "0 \"tháng\"", kyVong: "12 tháng"),
        CaFormat(giaTri: .double(1.25), mau: "+0.0;-0.0;0.0", kyVong: "+1.3"),
        CaFormat(giaTri: .double(12_345.678), mau: "$#,0.0", kyVong: "$12,345.7"),
        CaFormat(giaTri: .double(-0.0523), mau: "+0.0%;-0.0%", kyVong: "-5.2%"),
    ]

    @Test func formatMoiMauNhom6() {
        for ca in Self.cacCa {
            let ketQua = fkChay("FORMAT", [fkLit(ca.giaTri), fkLit(.string(ca.mau))])
            #expect(ketQua == .success(.string(ca.kyVong)), "mẫu \(ca.mau), giá trị \(ca.giaTri)")
        }
    }

    @Test func formatBlankRaChuoiRong() {
        #expect(fkChay("FORMAT", [fkLit(.blank), fkLit(.string("0.0%"))]) == .success(.string("")))
    }

    @Test func formatCultureNgoaiEnUSBaoLoi() {
        // Đợt 2 chỉ có en-US; culture khác được VAL báo .runtime rõ ràng, không trả chuỗi sai.
        #expect(fkLoi(fkChay("FORMAT", [fkLit(.integer(1)), fkLit(.string("0")), fkLit(.string("fr-FR"))])) == .runtime)
    }
}
