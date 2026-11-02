import DAXEngine
import Foundation

/// Chuẩn đoán lỗi trong editor DAX để gạch chân và hiển thị tooltip.
public struct EditorDiagnostic: Sendable, Hashable, Equatable {
    public let range: NSRange
    public let message: String

    public init(range: NSRange, message: String) {
        self.range = range
        self.message = message
    }

    /// Chuyển đổi danh sách `[DAXError]` thành `[EditorDiagnostic]`:
    /// - Bỏ lỗi không có range.
    /// - Range rỗng hoặc thiếu: gạch 1 ký tự tại start. Nếu start nằm ở cuối văn bản thì gạch ký tự cuối.
    /// - Kẹp range trong độ dài văn bản (UTF-16).
    /// - Thông điệp dạng "Query (dòng, cột) <message>".
    public static func from(errors: [DAXError], text: String) -> [EditorDiagnostic] {
        let textLength = (text as NSString).length
        guard textLength > 0 else { return [] }

        var result: [EditorDiagnostic] = []
        for error in errors {
            guard let r = error.range else { continue }

            let message = "Query (\(r.line), \(r.column)) \(error.message)"
            let finalRange: NSRange

            if r.start >= r.end {
                // Range rỗng hoặc đảo
                let clampedStart = max(0, min(r.start, textLength))
                if clampedStart >= textLength {
                    finalRange = NSRange(location: max(0, textLength - 1), length: 1)
                } else {
                    finalRange = NSRange(location: clampedStart, length: 1)
                }
            } else {
                let clampedStart = max(0, min(r.start, textLength))
                let clampedEnd = max(0, min(r.end, textLength))
                if clampedStart >= clampedEnd {
                    if clampedStart >= textLength {
                        finalRange = NSRange(location: max(0, textLength - 1), length: 1)
                    } else {
                        finalRange = NSRange(location: clampedStart, length: 1)
                    }
                } else {
                    finalRange = NSRange(location: clampedStart, length: clampedEnd - clampedStart)
                }
            }

            result.append(EditorDiagnostic(range: finalRange, message: message))
        }
        return result
    }
}

public typealias EditorDiagnostics = EditorDiagnostic
