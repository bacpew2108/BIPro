// Phase F (T004): hợp đồng nguồn dữ liệu. Xem specs/010-f-get-data-power-query-t3/contracts/data-source.md.
// Chưa có nguồn cụ thể: CSV, Excel, JSON, SQLite (gói F-CONN1), Parquet và PostgreSQL (P3) cài ở các task sau.

import ColumnStore

public enum SourceKind: String, Sendable, CaseIterable {
    case csv, excel, json, sqlite, parquet, postgres
}

public enum SourceItemKind: String, Sendable {
    case file, sheet, table, namedTable, view, record
}

/// Lỗi đọc nguồn. Thông điệp tiếng Việt, hiển thị trực tiếp cho người dùng. Không bao giờ chứa mật khẩu.
public enum SourceError: Error, Equatable, Sendable {
    case unreadable(String)
    case encoding(String)
    case empty
    case unsupported(String)
    case cancelled
}

public struct SourceColumn: Sendable, Equatable {
    public let name: String
    public let type: DAXType

    public init(name: String, type: DAXType) {
        self.name = name
        self.type = type
    }
}

/// Báo tiến độ trong khoảng 0...1.
public typealias SourceProgress = @Sendable (Double) -> Void

/// Một mục có thể nạp: trang tính, bảng đặt tên, bảng, khung nhìn, hoặc cả file (CSV).
public protocol SourceItem: Sendable {
    var name: String { get }
    var kind: SourceItemKind { get }
    /// Cột dò được mà không đọc hết mục; `nil` nếu chưa biết.
    var columns: [SourceColumn]? { get }
    var rowCountHint: Int? { get }

    /// Tối đa `limit` dòng, không đọc quá phần cần.
    func preview(limit: Int) async throws -> TableData
    /// Đọc đủ. Hỗ trợ huỷ qua `Task.cancel()` (ném `SourceError.cancelled`).
    func load(progress: SourceProgress?) async throws -> TableData
}

extension SourceItem {
    public func preview() async throws -> TableData { try await preview(limit: 200) }
}

public protocol DataSource: Sendable {
    var kind: SourceKind { get }
    /// Liệt kê các mục có thể nạp. Danh sách rỗng khi nguồn không có gì để nạp (khác với lỗi).
    func items() async throws -> [any SourceItem]
}
