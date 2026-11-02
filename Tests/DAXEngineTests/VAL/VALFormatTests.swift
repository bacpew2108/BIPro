// FORMAT và định dạng số (architecture.md §5.6). Mẫu lấy từ measures.nhom6.dax:
// 12 mẫu khác nhau: 10 mẫu trong chú thích [format: ...] và 2 mẫu chỉ có trong FORMAT(...) là "$#,0.0" và "+0.0%;-0.0%".
// Ca [SUY ĐOÁN] chờ O1 (∞, NaN), O2 (boolean, ngày) và O15 (làm tròn).
import Testing
@testable import DAXEngine

@Suite struct VALFormatTests {

    /// Mọi mẫu của Nhom6 cần có ít nhất một ca trong `cases` bên dưới.
    static let nhom6Patterns: [String] = [
        "#,0",                    // [format: #,0] 24 lần
        "$#,0",                   // [format: $#,0] 21 lần
        "+0.0%;-0.0%;0.0%",       // [format: +0.0%;-0.0%;0.0%] 17 lần
        "0.0%",                   // FORMAT(..., "0.0%") và [format: 0.0%]
        "#,0.0",                  // FORMAT(..., "#,0.0") và [format: #,0.0]
        "0%",                     // FORMAT(..., "0%") và IF(..., "0.0%", "0%")
        "0",                      // [format: 0]
        "0.0",                    // FORMAT(..., "0.0") và [format: 0.0]
        "0 \"tháng\"",            // [format: 0 "tháng"]
        "+0.0;-0.0;0.0",          // [format: +0.0;-0.0;0.0]
        "$#,0.0",                 // FORMAT([Loan Amount] / 1e6, "$#,0.0")
        "+0.0%;-0.0%",            // FORMAT(..., "+0.0%;-0.0%")
    ]

    struct Ca: Sendable {
        let giaTri: Value
        let mau: String
        let kyVong: String
    }

    static let cases: [Ca] = [
        // #,0
        Ca(giaTri: .double(1_234_567), mau: "#,0", kyVong: "1,234,567"),
        Ca(giaTri: .double(0.5), mau: "#,0", kyVong: "1"),           // nửa làm tròn lên theo độ lớn
        Ca(giaTri: .double(2.5), mau: "#,0", kyVong: "3"),
        Ca(giaTri: .double(-0.5), mau: "#,0", kyVong: "-1"),
        Ca(giaTri: .double(999.5), mau: "#,0", kyVong: "1,000"),     // tràn làm tròn sang hàng nghìn
        Ca(giaTri: .blank, mau: "#,0", kyVong: ""),
        // $#,0
        Ca(giaTri: .double(1_234_567), mau: "$#,0", kyVong: "$1,234,567"),
        Ca(giaTri: .double(-1234), mau: "$#,0", kyVong: "-$1,234"),  // dấu âm đứng trước ký hiệu tiền
        Ca(giaTri: .integer(0), mau: "$#,0", kyVong: "$0"),
        // +0.0%;-0.0%;0.0%
        Ca(giaTri: .double(0.0523), mau: "+0.0%;-0.0%;0.0%", kyVong: "+5.2%"),
        Ca(giaTri: .double(-0.0523), mau: "+0.0%;-0.0%;0.0%", kyVong: "-5.2%"),
        Ca(giaTri: .integer(0), mau: "+0.0%;-0.0%;0.0%", kyVong: "0.0%"),   // phần thứ 3 cho số 0
        Ca(giaTri: .double(0.125), mau: "+0.0%;-0.0%;0.0%", kyVong: "+12.5%"),
        // 0.0%
        Ca(giaTri: .double(0.1234), mau: "0.0%", kyVong: "12.3%"),
        Ca(giaTri: .double(0.125), mau: "0.0%", kyVong: "12.5%"),
        Ca(giaTri: .double(0.0005), mau: "0.0%", kyVong: "0.1%"),    // 0.05% làm tròn lên ở chữ số thứ hai
        Ca(giaTri: .double(-0.05), mau: "0.0%", kyVong: "-5.0%"),
        Ca(giaTri: .integer(0), mau: "0.0%", kyVong: "0.0%"),
        Ca(giaTri: .blank, mau: "0.0%", kyVong: ""),
        // #,0.0
        Ca(giaTri: .double(1234.5678), mau: "#,0.0", kyVong: "1,234.6"),
        Ca(giaTri: .double(1.25), mau: "#,0.0", kyVong: "1.3"),
        Ca(giaTri: .double(-2.5), mau: "#,0.0", kyVong: "-2.5"),
        Ca(giaTri: .integer(0), mau: "#,0.0", kyVong: "0.0"),
        Ca(giaTri: .double(999.95), mau: "#,0.0", kyVong: "1,000.0"),
        // 0%
        Ca(giaTri: .double(0.1234), mau: "0%", kyVong: "12%"),
        Ca(giaTri: .double(0.125), mau: "0%", kyVong: "13%"),
        Ca(giaTri: .double(0.005), mau: "0%", kyVong: "1%"),         // 0.5% làm tròn lên
        // 0
        Ca(giaTri: .double(3.7), mau: "0", kyVong: "4"),
        Ca(giaTri: .integer(0), mau: "0", kyVong: "0"),
        Ca(giaTri: .double(-2.4), mau: "0", kyVong: "-2"),
        // 0.0
        Ca(giaTri: .double(1.25), mau: "0.0", kyVong: "1.3"),
        Ca(giaTri: .double(0.05), mau: "0.0", kyVong: "0.1"),
        Ca(giaTri: .double(2.25), mau: "0.0", kyVong: "2.3"),
        Ca(giaTri: .double(-2.345), mau: "0.0", kyVong: "-2.3"),
        Ca(giaTri: .double(12.345), mau: "0.0", kyVong: "12.3"),     // dạng FORMAT(ABS(d) * 100, "0.0")
        // 0 "tháng"
        Ca(giaTri: .integer(12), mau: "0 \"tháng\"", kyVong: "12 tháng"),
        Ca(giaTri: .integer(0), mau: "0 \"tháng\"", kyVong: "0 tháng"),
        // +0.0;-0.0;0.0
        Ca(giaTri: .double(1.25), mau: "+0.0;-0.0;0.0", kyVong: "+1.3"),
        Ca(giaTri: .double(-2.5), mau: "+0.0;-0.0;0.0", kyVong: "-2.5"),
        Ca(giaTri: .integer(0), mau: "+0.0;-0.0;0.0", kyVong: "0.0"),
        // $#,0.0
        Ca(giaTri: .double(12_345.678), mau: "$#,0.0", kyVong: "$12,345.7"),
        Ca(giaTri: .double(1234.5), mau: "$#,0.0", kyVong: "$1,234.5"),
        Ca(giaTri: .double(-1234.5), mau: "$#,0.0", kyVong: "-$1,234.5"),
        Ca(giaTri: .double(0.04), mau: "$#,0.0", kyVong: "$0.0"),
        // +0.0%;-0.0%
        Ca(giaTri: .double(0.0523), mau: "+0.0%;-0.0%", kyVong: "+5.2%"),
        Ca(giaTri: .double(-0.0523), mau: "+0.0%;-0.0%", kyVong: "-5.2%"),
        Ca(giaTri: .integer(0), mau: "+0.0%;-0.0%", kyVong: "+0.0%"),  // hai phần: số 0 dùng phần dương
    ]

    @Test func moiMauNhom6CoItNhatMotCa() {
        let covered = Set(Self.cases.map(\.mau))
        #expect(covered.isSuperset(of: Set(Self.nhom6Patterns)), "thiếu ca cho: \(Set(Self.nhom6Patterns).subtracting(covered).sorted())")
        #expect(Self.nhom6Patterns.count == 12)
    }

    @Test func bangCaFormatNhom6() throws {
        for ca in Self.cases {
            let got = try FormatString.format(ca.giaTri, pattern: ca.mau, culture: "en-US")
            #expect(got == ca.kyVong, "mẫu \(ca.mau), giá trị \(ca.giaTri): được \(got), kỳ vọng \(ca.kyVong)")
        }
    }

    @Test func kieuNguyenTienTeVaChuoi() throws {
        #expect(try FormatString.format(.integer(1234), pattern: "#,0", culture: "en-US") == "1,234")
        // Currency 12.3456 làm tròn còn hai chữ số.
        #expect(try FormatString.format(.currency(123_456), pattern: "0.00", culture: "en-US") == "12.35")
        #expect(try FormatString.format(.currency(-15_000), pattern: "0.0", culture: "en-US") == "-1.5")
        #expect(try FormatString.format(.string("12.5"), pattern: "0.0", culture: "en-US") == "12.5")
        #expect(loiDAX { _ = try FormatString.format(.string("abc"), pattern: "0", culture: "en-US"); return .blank }?.kind == .typeMismatch)
    }

    @Test func soDacBietInfVaNan() throws {
        // [SUY ĐOÁN, chờ O1] ∞, -∞ và NaN hiển thị như dưới đây.
        #expect(try FormatString.format(.double(.infinity), pattern: "0.0", culture: "en-US") == "∞")
        #expect(try FormatString.format(.double(-.infinity), pattern: "0.0%", culture: "en-US") == "-∞")
        #expect(try FormatString.format(.double(.nan), pattern: "0", culture: "en-US") == "NaN")
    }

    @Test func kieuBooleanVaNgayTheoGiaDinh() throws {
        // [SUY ĐOÁN, chờ O2] Boolean không áp mẫu số; ngày áp mẫu số dưới dạng số serial.
        #expect(try FormatString.format(.boolean(true), pattern: "0", culture: "en-US") == "TRUE")
        #expect(try FormatString.format(.dateTime(45_000), pattern: "0", culture: "en-US") == "45000")
    }

    @Test func mauRongLaDangMacDinh() throws {
        // [SUY ĐOÁN] Mẫu rỗng trả dạng chuỗi mặc định.
        #expect(try FormatString.format(.double(1.5), pattern: "", culture: "en-US") == "1.5")
    }

    @Test func mauChuaHoTroBaoRuntimeRo() {
        // Mẫu ngày, E+0, định dạng đặt tên, nhiều hơn 3 phần, ký tự lạ, và culture khác en-US đều báo .runtime.
        let mauLoi = ["yyyy", "d mmm", "0E+0", "General Number", "Fixed", "0;0;0;0", "0.0.0", "\"abc", "0 ;\"x", "abc", "0;;0"]
        for mau in mauLoi {
            let loi = loiDAX { _ = try FormatString.format(.double(1), pattern: mau, culture: "en-US"); return .blank }
            #expect(loi?.kind == .runtime, "mẫu \(mau) phải báo .runtime")
        }
        let loiVi = loiDAX { _ = try FormatString.format(.double(1), pattern: "0.0", culture: "vi-VN"); return .blank }
        #expect(loiVi?.kind == .runtime)
    }
}
