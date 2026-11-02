// Chữ ký và thân hàm của các hàm F-KIT đợt 2 (Logical, MathFns, Text, DateTime, ISBLANK).
// Kiểm: tên và tên tham số giữ nguyên; không còn .pending (lỗi .unsupportedFunction) cho các hàm này.
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct FKITSignatureTests {

    /// Tên hàm và tên tham số theo khai báo của lead ở đợt 0. Không được đổi.
    static let chuKyKyVong: [(ten: String, tham: [String])] = [
        ("IF", ["logical_test", "value_if_true", "value_if_false"]),
        ("SWITCH", ["expression", "value", "result", "else"]),
        ("AND", ["logical1", "logical2"]),
        ("OR", ["logical1", "logical2"]),
        ("NOT", ["logical"]),
        ("TRUE", []),
        ("FALSE", []),
        ("BLANK", []),
        ("COALESCE", ["value"]),
        ("ABS", ["number"]),
        ("INT", ["number"]),
        ("MOD", ["number", "divisor"]),
        ("DIVIDE", ["numerator", "denominator", "alternateResult"]),
        ("ROUND", ["number", "num_digits"]),
        ("FLOOR", ["number", "significance"]),
        ("FORMAT", ["value", "format_string", "locale"]),
        ("DATE", ["year", "month", "day"]),
        ("YEAR", ["date"]),
        ("MONTH", ["date"]),
        ("DAY", ["date"]),
        ("QUARTER", ["date"]),
        ("HOUR", ["datetime"]),
        ("DATEDIFF", ["start_date", "end_date", "interval"]),
        ("ISBLANK", ["value"]),
    ]

    @Test func chuKyGiuNguyen() {
        for (ten, tham) in Self.chuKyKyVong {
            guard let spec = FunctionRegistry.byName[ten] else {
                Issue.record("thiếu hàm \(ten) trong registry")
                continue
            }
            #expect(spec.params.map(\.name) == tham, "tham số của \(ten)")
        }
    }

    @Test func khongConPendingCuaDotNay() {
        // Hàm pending báo .unsupportedFunction. Hàm đã cài thì không bao giờ báo lỗi đó, dù đối số sai.
        for (ten, _) in Self.chuKyKyVong {
            let ketQua = fkChay(ten, [])
            #expect(fkLoi(ketQua) != .unsupportedFunction, "\(ten) vẫn là .pending")
        }
    }

    @Test func impXacNhanLaScalar() {
        for (ten, _) in Self.chuKyKyVong {
            guard let spec = FunctionRegistry.byName[ten] else { continue }
            if case .scalar = spec.impl {
                continue
            }
            Issue.record("\(ten) phải là hàm scalar")
        }
    }
}
