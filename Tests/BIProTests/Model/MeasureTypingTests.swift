import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T012): kiểu và định dạng mặc định của measure suy từ kết quả của biểu thức (R3, QUAN-SAT mục 1).
@Suite("Phase E: MeasureTyping (ánh xạ)") struct MeasureTypingMappingTests {
    @Test func soNguyenLaInt64VoiDinhDangKhongNhuDesktop() {
        let info = MeasureTyping.info(for: .integer(42))
        #expect(info.dataType == .int64 && info.formatString == "0")   // QUAN-SAT: COUNTROWS()+1 → DataType 6, FormatString '0'
    }

    @Test func chuoiLogicVaBlankNhuDesktopGhi() {
        // VM-E2 (docs/phase-e-evidence/vm-e2/rows.txt)
        #expect(MeasureTyping.info(for: .string("abc")) == (.string, nil))
        #expect(MeasureTyping.info(for: .boolean(true)) == (.boolean, "\"TRUE\";\"TRUE\";\"FALSE\""))
        #expect(MeasureTyping.info(for: .blank) == (.int64, "0"))
        #expect(MeasureTyping.info(for: .dateTime(45000)) == (.dateTime, "General Date"))
        #expect(MeasureTyping.info(for: .double(0.33)) == (.double, nil))
    }

    @Test func cacKieuChuaQuanSatChiDatKieuKhongDoanDinhDang() {
        for (value, type) in [(Value.currency(100), ModelMetadata.DataType.decimal)] {
            let info = MeasureTyping.info(for: value)
            #expect(info.dataType == type, Comment(rawValue: "\(value)"))
            #expect(info.formatString == nil, "định dạng kiểu này chưa quan sát: để trống thay vì đoán")
        }
    }
}

@Suite("Phase E: MeasureTyping (engine)", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
struct MeasureTypingEngineTests {
    private func engine() throws -> DAXEngine {
        try Workspace(data: Data(contentsOf: #require(EFixtures.nhom6))).daxEngine()
    }

    @Test func bieuThucHopLeChoKieuVaGiaTri() async throws {
        let engine = try engine()
        guard case .ok(let count) = await MeasureTyping.check("COUNTROWS(Dim_Account)+1", using: engine) else { Issue.record("phải ok"); return }
        #expect(count.dataType == .int64 && count.formatString == "0")
        #expect(count.value == .integer(4502))
        guard case .ok(let ratio) = await MeasureTyping.check("DIVIDE(1, 3)", using: engine) else { Issue.record("phải ok"); return }
        #expect(ratio.dataType == .double)
        guard case .ok(let text) = await MeasureTyping.check("\"abc\"", using: engine) else { Issue.record("phải ok"); return }
        #expect(text.dataType == .string)
    }

    @Test func loiCuPhapVaTenKemViTriTinhTrongBieuThuc() async throws {
        let engine = try engine()
        guard case .failed(let syntax) = await MeasureTyping.check("COUNTROWS(", using: engine) else { Issue.record("phải lỗi"); return }
        #expect(syntax.line == 1 && (syntax.column ?? 0) >= 1 && (syntax.column ?? 0) <= "COUNTROWS(".count + 2)
        guard case .failed(let unknown) = await MeasureTyping.check("1 + SUM(Khong_Co[x])", using: engine) else { Issue.record("phải lỗi"); return }
        #expect(!unknown.message.isEmpty)
        // biểu thức rỗng
        guard case .failed(let empty) = await MeasureTyping.check("   ", using: engine) else { Issue.record("phải lỗi"); return }
        #expect(empty.message.contains("trống"))
    }
}
