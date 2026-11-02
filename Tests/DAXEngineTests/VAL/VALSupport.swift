// Tiện ích dùng chung cho các test VAL (đợt 1b).
import Testing
@testable import DAXEngine

/// So số thực với kỳ vọng, sai số tương đối 1e-9. NaN khớp NaN; ∞ khớp đúng dấu.
func xapXiSo(_ got: Value, _ want: Double) -> Bool {
    guard case .double(let d) = got else { return false }
    if want.isNaN { return d.isNaN }
    if want.isInfinite { return d == want }
    return abs(d - want) <= 1e-9 * max(1, abs(want))
}

/// Lỗi DAX do một phép tính ném ra, nil nếu không ném.
func loiDAX(_ body: () throws -> Value) -> DAXError? {
    do {
        _ = try body()
        return nil
    } catch let loi as DAXError {
        return loi
    } catch {
        return DAXError(.runtime, "lỗi không phải DAXError: \(error)")
    }
}

/// Giá trị serial OLE của một ngày giờ; 45000 là 2023-03-15 00:00.
let ngay2023_03_15: Double = 45_000
