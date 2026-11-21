import Foundation
import Connectors

enum ConnectorCategory: CaseIterable {
    case all, file, database
}

struct ConnectorEntry: Identifiable {
    let kind: SourceKind
    let title: String
    let detail: String
    let category: ConnectorCategory
    let isDefault: Bool

    var id: SourceKind { kind }
    var isAvailable: Bool {
        ConnectorCatalog.availableKinds.contains(kind)
    }

    @MainActor var localizedTitle: String {
        switch kind {
        case .excel: bi(title, "Excel Workbook")
        case .csv: bi(title, "Text / CSV")
        case .json: bi(title, "JSON File")
        case .parquet: bi(title, "Apache Parquet")
        case .sqlite: bi(title, "SQLite Database")
        case .postgres: bi(title, "PostgreSQL Database")
        }
    }

    @MainActor var localizedDetail: String {
        switch kind {
        case .excel: bi(detail, "Microsoft Excel spreadsheet (.xlsx)")
        case .csv: bi(detail, "Comma- or tab-separated text files (.csv, .tsv, .txt)")
        case .json: bi(detail, "JavaScript Object Notation structured document (.json)")
        case .parquet: bi(detail, "Columnar binary storage format (.parquet)")
        case .sqlite: bi(detail, "Local embedded relational database (.sqlite, .db)")
        case .postgres: bi(detail, "Open-source relational database server")
        }
    }
}

enum ConnectorCatalog {
    static var availableKinds: Set<SourceKind> = [.excel, .csv, .json, .parquet, .sqlite, .postgres]

    static let entries: [ConnectorEntry] = [
        ConnectorEntry(
            kind: .excel,
            title: "Sổ làm việc Excel",
            detail: "Bảng tính Microsoft Excel (.xlsx)",
            category: .file,
            isDefault: true
        ),
        ConnectorEntry(
            kind: .csv,
            title: "Văn bản / CSV",
            detail: "Tệp văn bản phân cách bằng dấu phẩy hoặc tab (.csv, .tsv, .txt)",
            category: .file,
            isDefault: false
        ),
        ConnectorEntry(
            kind: .json,
            title: "Tệp JSON",
            detail: "Tài liệu cấu trúc JavaScript Object Notation (.json)",
            category: .file,
            isDefault: false
        ),
        ConnectorEntry(
            kind: .parquet,
            title: "Apache Parquet",
            detail: "Định dạng lưu trữ nhị phân dạng cột tối ưu (.parquet)",
            category: .file,
            isDefault: false
        ),
        ConnectorEntry(
            kind: .sqlite,
            title: "Cơ sở dữ liệu SQLite",
            detail: "Cơ sở dữ liệu quan hệ nhúng cục bộ (.sqlite, .db)",
            category: .database,
            isDefault: false
        ),
        ConnectorEntry(
            kind: .postgres,
            title: "Cơ sở dữ liệu PostgreSQL",
            detail: "Hệ quản trị cơ sở dữ liệu quan hệ mã nguồn mở",
            category: .database,
            isDefault: false
        )
    ]

    static func visible(category: ConnectorCategory, query: String) -> [ConnectorEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            if category != .all && entry.category != category {
                return false
            }
            if trimmed.isEmpty {
                return true
            }
            let searchTarget = "\(entry.title) \(entry.detail) \(entry.kind.rawValue)"
            return searchTarget.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func count(for category: ConnectorCategory, query: String) -> Int {
        visible(category: category, query: query).count
    }
}
