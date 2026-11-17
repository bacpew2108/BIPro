// Đợt tồn đọng sau Phase F, US1 (T011): hàm Desktop dùng cho phép gộp ngầm (VM-F10, `docs/phase-f2-evidence/vm-f10/QUAN-SAT.md`
// mục 3): Count → COUNTA, Median → MEDIAN, Standard deviation → STDEV.P, Variance → VAR.P. Đáp án tính tay trên bảng Kho
// (`so` = 5, BLANK, 3, 5, 1, 7; `nhom` = a, b, a, BLANK, c, b).
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FAggStatisticsTests {
    @Test func countaDemGiaTriKhacBlankMoiKieu() throws {
        let env = FAggEnv.kho()
        #expect(try env.value("COUNTA ( Kho[so] )") == .integer(5))
        #expect(try env.value("COUNTA ( Kho[nhom] )") == .integer(5))
        let khong = try env.filter("Kho", "so", [.integer(99)])
        #expect(try env.value("COUNTA ( Kho[so] )", filter: khong) == .blank)
    }

    @Test func medianSoLeVaSoChan() throws {
        let env = FAggEnv.kho()
        // 1 3 5 5 7 → 5.
        #expect(try env.value("MEDIAN ( Kho[so] )") == .double(5))
        // Bỏ 7: 1 3 5 5 → (3 + 5) / 2 = 4.
        let bon = try env.filter("Kho", "so", [.integer(1), .integer(3), .integer(5)])
        #expect(try env.value("MEDIAN ( Kho[so] )", filter: bon) == .double(4))
    }

    @Test func phuongSaiVaDoLechChuanTongThe() throws {
        let env = FAggEnv.kho()
        // Trung bình 4,2; bình phương độ lệch 0,64 + 1,44 + 0,64 + 10,24 + 7,84 = 20,8; chia 5 = 4,16.
        guard case .double(let variance) = try env.value("VAR.P ( Kho[so] )"),
              case .double(let deviation) = try env.value("STDEV.P ( Kho[so] )") else {
            Issue.record("VAR.P / STDEV.P phải ra số thực"); return
        }
        #expect(abs(variance - 4.16) < 1e-12)
        #expect(abs(deviation - 2.039607805437114) < 1e-12)
    }

    @Test func thongKeTrenCotChuBaoLoiKieu() throws {
        let env = FAggEnv.kho()
        for f in ["MEDIAN", "VAR.P", "STDEV.P"] {
            #expect(fAggKindOf { try env.value("\(f) ( Kho[nhom] )") } == .typeMismatch, Comment(rawValue: f))
        }
    }

    @Test func khongCoDongLaBlank() throws {
        let env = FAggEnv.kho()
        let khong = try env.filter("Kho", "so", [.integer(99)])
        for f in ["MEDIAN", "VAR.P", "STDEV.P"] {
            #expect(try env.value("\(f) ( Kho[so] )", filter: khong) == .blank, Comment(rawValue: f))
        }
    }
}
