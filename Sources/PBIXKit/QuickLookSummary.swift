import Foundation

/// Cấu trúc tóm tắt đọc nhanh từ tệp `.pbix` phục vụ Quick Look Preview và Thumbnail (US4, FR-030..FR-032).
/// Chỉ đọc ZIP `Report/` + `metadata.sqlitedb` (tuyệt đối không giải mã các cột dữ liệu VertiPaq).
public struct PBIXQuickLookSummary: Sendable, Equatable {
    public struct VisualBox: Sendable, Equatable {
        public let type: String
        public let title: String?
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(type: String, title: String?, x: Double, y: Double, width: Double, height: Double) {
            self.type = type
            self.title = title
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct PageOutline: Sendable, Equatable {
        public let name: String
        public let isHidden: Bool
        public let width: Double
        public let height: Double
        public let visuals: [VisualBox]

        public init(name: String, isHidden: Bool, width: Double, height: Double, visuals: [VisualBox]) {
            self.name = name
            self.isHidden = isHidden
            self.width = width
            self.height = height
            self.visuals = visuals
        }
    }

    public let fileName: String
    public let formatLabel: String
    public let pages: [PageOutline]
    public let activePageIndex: Int
    public let tableCount: Int
    public let columnCount: Int
    public let measureCount: Int
    public let relationshipCount: Int
    public let hasDataModel: Bool
    public let modelError: String?

    public init(
        fileName: String,
        formatLabel: String,
        pages: [PageOutline],
        activePageIndex: Int,
        tableCount: Int,
        columnCount: Int,
        measureCount: Int,
        relationshipCount: Int,
        hasDataModel: Bool,
        modelError: String? = nil
    ) {
        self.fileName = fileName
        self.formatLabel = formatLabel
        self.pages = pages
        self.activePageIndex = activePageIndex
        self.tableCount = tableCount
        self.columnCount = columnCount
        self.measureCount = measureCount
        self.relationshipCount = relationshipCount
        self.hasDataModel = hasDataModel
        self.modelError = modelError
    }

    public var visiblePageCount: Int { pages.filter { !$0.isHidden }.count }

    public var previewPage: PageOutline? {
        guard !pages.isEmpty else { return nil }
        if pages.indices.contains(activePageIndex) && !pages[activePageIndex].isHidden {
            return pages[activePageIndex]
        }
        return pages.first(where: { !$0.isHidden }) ?? pages.first
    }

    /// Đọc chỉ-đọc và an toàn từ URL tệp `.pbix` trên đĩa.
    public static func load(from url: URL) throws -> PBIXQuickLookSummary {
        let pbix = try PBIXFile(url: url)
        return try load(from: pbix, fileName: url.lastPathComponent)
    }

    /// Đọc từ `PBIXFile` đã mở (tiện cho test bằng dữ liệu bộ nhớ).
    public static func load(from pbix: PBIXFile, fileName: String) throws -> PBIXQuickLookSummary {
        let formatLabel: String = switch pbix.reportFormat {
        case .pbir: "PBIR"
        case .legacyLayout: lt("Layout (cũ)", "Layout (legacy)")
        case .none: lt("Không có báo cáo", "No report")
        }

        let report = (try? pbix.loadReport()) ?? ReportDefinition(pages: [])
        let outlines: [PageOutline] = report.pages.map { page in
            let boxes = page.visuals.filter { !$0.isHidden }.map { v in
                let explicitTitle = v.containerObjects.string("title", "text")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = v.fields.first?.label
                let title = (explicitTitle?.isEmpty == false ? explicitTitle : fallback)
                return VisualBox(type: v.type, title: title, x: v.x, y: v.y, width: v.width, height: v.height)
            }
            return PageOutline(
                name: page.displayName,
                isHidden: page.isHidden,
                width: max(1, page.width),
                height: max(1, page.height),
                visuals: boxes
            )
        }

        let activeIndex = outlines.firstIndex(where: { !$0.isHidden }) ?? 0

        var tableCount = 0
        var columnCount = 0
        var measureCount = 0
        var relationshipCount = 0
        var modelError: String?

        if pbix.hasDataModel {
            do {
                let (abf, _) = try pbix.loadDataModel()
                let sqliteData = try abf.contents(named: "metadata.sqlitedb")
                let meta = try ModelMetadata(sqlite: sqliteData)
                let userTables = meta.tables.filter(\.isUserTable)
                let userTableIDs = Set(userTables.map(\.id))
                let userTableNames = Set(userTables.map(\.name))
                tableCount = userTableIDs.count
                columnCount = meta.columns.filter { userTableIDs.contains($0.tableID) && $0.kind != .rowNumber }.count
                measureCount = meta.measures.filter { userTableNames.contains($0.tableName) }.count
                relationshipCount = meta.relationships.count
            } catch {
                modelError = error.localizedDescription
            }
        }

        return PBIXQuickLookSummary(
            fileName: fileName,
            formatLabel: formatLabel,
            pages: outlines,
            activePageIndex: activeIndex,
            tableCount: tableCount,
            columnCount: columnCount,
            measureCount: measureCount,
            relationshipCount: relationshipCount,
            hasDataModel: pbix.hasDataModel,
            modelError: modelError
        )
    }
}
