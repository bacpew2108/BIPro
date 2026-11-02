import DAXEngine
import Foundation
import Testing
@testable import BIPro

@Suite struct EditorDiagnosticsTests {
    @Test func chuyenDoiRangeVaThongDiepQueryDongCot() {
        let text = "EVALUATE 123"
        let error = DAXError(
            .syntax,
            "Cú pháp không hợp lệ",
            range: SourceRange(start: 9, end: 12, line: 1, column: 10)
        )

        let diagnostics = EditorDiagnostics.from(errors: [error], text: text)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].range == NSRange(location: 9, length: 3))
        #expect(diagnostics[0].message == "Query (1, 10) Cú pháp không hợp lệ")
        #expect(diagnostics[0].message.contains("Query (1, 10)"))
    }

    @Test func kepRangeTrongDoDaiVanBan() {
        let text = "EVALUATE"
        // Range vượt quá độ dài văn bản
        let error = DAXError(
            .syntax,
            "Vượt quá",
            range: SourceRange(start: 4, end: 20, line: 1, column: 5)
        )

        let diagnostics = EditorDiagnostics.from(errors: [error], text: text)
        #expect(diagnostics.count == 1)
        // Range phải được kẹp từ 4 đến 8 -> length = 4
        #expect(diagnostics[0].range == NSRange(location: 4, length: 4))
    }

    @Test func rangeRongOCuoiVanBanVaGiuaVanBan() {
        let text = "EVALUATE"

        // Range rỗng ở cuối văn bản (start == end == 8)
        let errorAtEnd = DAXError(
            .syntax,
            "Thiếu token ở cuối",
            range: SourceRange(start: 8, end: 8, line: 1, column: 9)
        )
        let diagsAtEnd = EditorDiagnostics.from(errors: [errorAtEnd], text: text)
        #expect(diagsAtEnd.count == 1)
        // Gạch ký tự cuối cùng (vị trí 7, độ dài 1)
        #expect(diagsAtEnd[0].range == NSRange(location: 7, length: 1))

        // Range rỗng ở giữa văn bản (start == end == 3)
        let errorMiddle = DAXError(
            .syntax,
            "Lỗi tại vị trí 3",
            range: SourceRange(start: 3, end: 3, line: 1, column: 4)
        )
        let diagsMiddle = EditorDiagnostics.from(errors: [errorMiddle], text: text)
        #expect(diagsMiddle.count == 1)
        // Gạch 1 ký tự tại start (vị trí 3, độ dài 1)
        #expect(diagsMiddle[0].range == NSRange(location: 3, length: 1))
    }

    @Test func vanBanCoTiengVietCoDauKhopUTF16NSRange() {
        // Tiếng Việt có dấu kiểm tra khớp offset UTF-16 với NSRange
        let text = "Truy vấn dữ liệu tiếng Việt có dấu: DEFINE MEASURE 'Bảng'[Số lượng] = 1"
        let ns = text as NSString

        let targetSubstring = "'Bảng'[Số lượng]"
        let targetRange = ns.range(of: targetSubstring)
        #expect(targetRange.location != NSNotFound)

        let error = DAXError(
            .unknownName,
            "Không tìm thấy measure",
            range: SourceRange(
                start: targetRange.location,
                end: targetRange.location + targetRange.length,
                line: 1,
                column: targetRange.location + 1
            )
        )

        let diagnostics = EditorDiagnostics.from(errors: [error], text: text)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].range == targetRange)
        #expect(ns.substring(with: diagnostics[0].range) == targetSubstring)
    }

    @Test func boLoiKhongCoRangeVaVanBanRong() {
        let text = "EVALUATE 1"
        let errorWithoutRange = DAXError(.runtime, "Lỗi runtime không có vị trí")
        let diagnostics = EditorDiagnostics.from(errors: [errorWithoutRange], text: text)
        #expect(diagnostics.isEmpty)

        let errorWithRange = DAXError(
            .syntax,
            "Lỗi",
            range: SourceRange(start: 0, end: 1, line: 1, column: 1)
        )
        let emptyTextDiagnostics = EditorDiagnostics.from(errors: [errorWithRange], text: "")
        #expect(emptyTextDiagnostics.isEmpty)
    }
}
