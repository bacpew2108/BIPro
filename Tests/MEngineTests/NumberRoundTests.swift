// Lỗi T096 (`/code-review`): `Number.Round` làm tròn nửa xa số 0 và bỏ qua roundingMode. Giá trị mong đợi lấy từ Desktop 2.159
// (2026-11-17, Blank Query trên VM, ảnh `docs/phase-f-evidence/vm-f7/t1-number-round.png`): mặc định ToEven, làm tròn theo giá trị
// thập phân (2.675 → 2.68, 1.005 → 1), RoundingMode chỉ quyết điểm giữa (Up(2.4) = 2), mã Up 0, Down 1, AwayFromZero 2, TowardZero 3, ToEven 4.
import Testing
@testable import MEngine

@Suite struct NumberRoundTests {
    private func number(_ source: String) async throws -> Double? {
        guard case .number(let n) = try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil) else { return nil }
        return n
    }

    @Test(arguments: [
        ("Number.Round(2.5)", 2.0), ("Number.Round(3.5)", 4), ("Number.Round(-2.5)", -2), ("Number.Round(0.125, 2)", 0.12),
        ("Number.Round(1.2345, 3)", 1.234), ("Number.Round(2.675, 2)", 2.68), ("Number.Round(1.005, 2)", 1), ("Number.Round(1235, -1)", 1240),
        ("Number.Round(2.5, 0, RoundingMode.AwayFromZero)", 3), ("Number.Round(2.5, 0, RoundingMode.Down)", 2),
        ("Number.Round(-2.5, 0, RoundingMode.Up)", -2), ("Number.Round(-2.5, 0, RoundingMode.TowardZero)", -2),
        ("Number.Round(-2.5, 0, RoundingMode.Down)", -3), ("Number.Round(2.4, 0, RoundingMode.Up)", 2),
        ("RoundingMode.Up + RoundingMode.Down * 10 + RoundingMode.AwayFromZero * 100 + RoundingMode.TowardZero * 1000 + RoundingMode.ToEven * 10000", 43210),
    ])
    func matchesDesktop(_ source: String, _ expected: Double) async throws {
        #expect(try await number(source) == expected)
    }
}
