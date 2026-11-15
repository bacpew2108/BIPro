// Phase F, T047/T048: lõi M so với kết quả Desktop 2.159 (VM-F3, 2026-11-15, `docs/phase-f-evidence/vm-f3/SUY-DOAN-M.md`).
// Giá trị kỳ vọng là kết quả Desktop trả cho cùng biểu thức (`m-suy-doan.m` chạy bằng Expression.Evaluate trong Power Query).
import Testing
import ColumnStore
@testable import MEngine

@Suite struct DesktopObservedTests {
    private func eval(_ source: String) async throws -> MValue { try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil) }

    @Test func soSanhVoiNullTraNull() async throws {
        #expect(try await eval("null < 1") == .null)
        #expect(try await eval("null >= 1") == .null)
        #expect(try await eval("\"a\" & null") == .null)
    }

    /// Desktop: `#date = #datetime` là false (khác kiểu), `#date < #datetime` báo lỗi.
    @Test func dateVaDatetimeKhongSoDuocVoiNhau() async throws {
        #expect(try await eval("#date(2026,1,1) = #datetime(2026,1,1,0,0,0)") == .logical(false))
        do {
            _ = try await eval("#date(2026,1,1) < #datetime(2026,1,2,0,0,0)")
            Issue.record("phải lỗi")
        } catch let error as MError { #expect(error.reason == "Expression.Error") }
    }

    @Test func chuoiTheoGiaTriKyTuVaBanGhiKhongTheoThuTu() async throws {
        #expect(try await eval("\"B\" < \"a\"") == .logical(true))
        #expect(try await eval("\"a\" = \"A\"") == .logical(false))
        #expect(try await eval("[a=1,b=2] = [b=2,a=1]") == .logical(true))
        #expect(try await eval("1 = 1.0") == .logical(true))
    }

    @Test func khoangRaVaChiaChoKhong() async throws {
        #expect(try await eval("{5..1}") == .list([]))
        #expect(try await eval("1/0") == .number(.infinity))
        if case .number(let nan) = try await eval("0/0") { #expect(nan.isNaN) } else { Issue.record("0/0 phải là NaN") }
        #expect(try await eval("+1") == .number(1))
        #expect(try await eval("+null") == .null)
    }

    @Test func truongTrenGiaTriKhongPhaiBanGhiBaoLoi() async throws {
        do {
            _ = try await eval("(each [A])(1)")
            Issue.record("phải lỗi")
        } catch let error as MError { #expect(error.reason == "Expression.Error") }
    }
}
