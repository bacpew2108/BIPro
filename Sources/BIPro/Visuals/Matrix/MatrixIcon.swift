import AppKit
import Foundation

enum MatrixIcon {
    /// Giải mã chuỗi data URI (ví dụ `data:image/svg+xml;utf8,<svg…>`):
    /// - Lấy phần sau dấu phẩy;
    /// - Percent-decode (ví dụ `%23` → `#`);
    /// - Trả về `Data` kiểu UTF-8.
    static func decodeDataURI(_ uri: String) -> Data? {
        guard let commaIndex = uri.firstIndex(of: ",") else { return nil }
        let payload = String(uri[uri.index(after: commaIndex)...])
        let decoded = payload.removingPercentEncoding ?? payload
        return decoded.data(using: .utf8)
    }

    /// Tạo `NSImage` từ chuỗi SVG data URI.
    static func image(from uri: String) -> NSImage? {
        guard let data = decodeDataURI(uri) else { return nil }
        return NSImage(data: data)
    }
}
