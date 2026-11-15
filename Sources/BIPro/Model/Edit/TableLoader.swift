// Phase F (T039): nạp các mục đã chọn trong Navigator thành `LoadedTable` (chưa đụng mô hình).
// Áp vào mô hình (hoàn tác, ModelEditor) là việc của T021, cùng file này. Hợp đồng: specs/010-f-get-data-power-query-t3/data-model.md.

import Foundation
import ColumnStore
import Connectors

/// Bảng đã nạp từ nguồn, đang chờ đưa vào mô hình. `data` giữ trong bộ nhớ đến khi lưu.
public struct LoadedTable: Identifiable, Sendable {
    public enum Status: Sendable, Equatable { case new, replaced, unchanged }

    public let id: UUID
    /// Tên bảng trong mô hình (đã khử trùng).
    public let name: String
    /// Tên truy vấn Power Query nạp bảng này (cùng tên bảng khi tạo mới).
    public let queryName: String
    public let data: TableData
    public let status: Status

    public init(id: UUID = UUID(), name: String, queryName: String? = nil, data: TableData, status: Status = .new) {
        self.id = id
        self.name = name
        self.queryName = queryName ?? name
        self.data = data
        self.status = status
    }
}

/// Đặt tên bảng khi nạp.
public enum TableNaming {
    /// Tên chưa dùng: `base`, nếu trùng (không phân biệt hoa thường, như tên bảng tabular) thì `base (2)`, `base (3)`…
    /// [SUY ĐOÁN] hậu tố " (n)" bắt đầu từ 2, chưa quan sát Desktop (chờ VM-F2, T032).
    public static func uniqueName(_ base: String, taken: Set<String>) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        let root = trimmed.isEmpty ? "Table" : trimmed
        let lowered = Set(taken.map { $0.lowercased() })
        if !lowered.contains(root.lowercased()) { return root }
        var n = 2
        while lowered.contains("\(root) (\(n))".lowercased()) { n += 1 }
        return "\(root) (\(n))"
    }
}

/// Tạo nguồn từ loại và địa chỉ người dùng chọn.
public enum SourceFactory {
    public static func make(kind: SourceKind, location: String) throws -> any DataSource {
        let url = URL(fileURLWithPath: location)
        switch kind {
        case .csv: return CSVSource(url: url)
        case .excel: return ExcelSource(url: url)
        case .json: return JSONSource(url: url)
        case .sqlite: return SQLiteSource(url: url)
        case .parquet: throw SourceError.unsupported("Parquet (đợt P3)")
        case .postgres: throw SourceError.unsupported("PostgreSQL (đợt P3)")
        }
    }
}

/// Thông điệp tiếng Việt cho người dùng từ lỗi đọc nguồn. Không bao giờ chứa mật khẩu (contract data-source, bất biến 5).
public enum SourceMessage {
    public static func text(for error: Error) -> String {
        guard let source = error as? SourceError else {
            return "Không đọc được nguồn: \(error.localizedDescription)"
        }
        switch source {
        case .unreadable(let reason), .encoding(let reason): return reason
        case .empty: return "Nguồn không có dữ liệu để nạp."
        case .unsupported(let what): return "Chưa hỗ trợ: \(what)."
        case .cancelled: return "Đã huỷ."
        }
    }
}

public enum TableLoader {
    /// Nạp tuần tự từng mục. Tiến độ chung 0...1 (mục i đóng góp 1/n). Huỷ (`Task.cancel()`) ném `SourceError.cancelled`
    /// và không trả bảng nào. Tên bảng khử trùng với `existingNames` và với nhau.
    public static func load(
        _ items: [any SourceItem],
        existingNames: Set<String>,
        progress: SourceProgress? = nil
    ) async throws -> [LoadedTable] {
        var taken = existingNames
        var result: [LoadedTable] = []
        let count = Double(items.count)
        for (index, item) in items.enumerated() {
            if Task.isCancelled { throw SourceError.cancelled }
            let base = Double(index)
            let data = try await item.load(progress: { fraction in
                progress?((base + min(max(fraction, 0), 1)) / count)
            })
            if Task.isCancelled { throw SourceError.cancelled }
            let name = TableNaming.uniqueName(item.name, taken: taken)
            taken.insert(name)
            result.append(LoadedTable(name: name, data: data))
        }
        progress?(1)
        return result
    }
}
