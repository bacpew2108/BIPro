import AppKit
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

/// Everything decoded from one `.pbix`. Immutable after load except for lazy caches.
final class Workspace: @unchecked Sendable {
    let pbix: PBIXFile
    let report: ReportDefinition
    let baseTheme: ReportTheme
    var theme: ReportTheme
    var sessionCustomThemeName: String? = nil
    let abf: ABFBackup?
    /// Mô hình hiệu lực (gốc cộng `ModelEdits` của phiên); nil khi file không có mô hình.
    var metadata: ModelMetadata? { runtime?.metadata }
    /// Giữ mô hình hiệu lực và engine (Phase E). nil khi file không có mô hình đọc được.
    let runtime: ModelRuntime?
    let modelError: String?
    let reportFilters: [ReportFilter]
    let pageFilters: [String: [ReportFilter]]
    let visualFilters: [String: [ReportFilter]]
    let bookmarks: [ReportBookmark]
    let diagramLayout: DiagramLayout?
    /// Page that was active when the file was saved (Power BI reopens on it).
    let activePageID: String?

    private let lock = NSLock()
    private var tableCache: [String: [DecodedColumn]] = [:]
    private var imageCache: [String: NSImage] = [:]
    private var rowCountCache: [String: Int] = [:]
    private var overlayTableCache: [String: (version: Int, columns: [DecodedColumn])] = [:]

    init(data: Data) throws {
        pbix = try PBIXFile(data: data)
        report = (try? pbix.loadReport()) ?? ReportDefinition(pages: [])
        let loadedTheme = pbix.loadTheme(for: report)
        baseTheme = loadedTheme
        theme = loadedTheme
        (reportFilters, pageFilters, visualFilters) = pbix.loadFilters(report: report)
        bookmarks = pbix.loadBookmarks()
        diagramLayout = pbix.loadDiagramLayout()
        activePageID = pbix.activePageID
        if pbix.hasDataModel {
            do {
                let (abf, _) = try pbix.loadDataModel()
                let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
                (self.abf, runtime, modelError) = (abf, ModelRuntime(metadata: metadata, abf: abf), nil)
            } catch {
                (abf, runtime, modelError) = (nil, nil, String(describing: error))
            }
        } else {
            (abf, runtime, modelError) = (nil, nil, biN("File không có data model nhúng (có thể là báo cáo live connection).", "The file has no embedded data model (it may be a live-connection report)."))
        }
    }

    /// Trang drillthrough và các cột tham số của nó (đọc từ `pageBinding` của page.json, chỉ định dạng PBIR).
    lazy var drillthroughPages: [(page: ReportPage, columns: [QueryColumn])] = {
        guard pbix.reportFormat == .pbir else { return [] }
        return report.pages.compactMap { page in
            let path = "Report/definition/pages/\(page.id)/page.json"
            guard pbix.archive.entry(path) != nil, var data = try? pbix.archive.read(path) else { return nil }
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
            guard let json = try? JSONValue.parse(data), json["pageBinding"]?["type"]?.string == "Drillthrough" else { return nil }
            let columns = (json["pageBinding"]?["parameters"]?.array ?? []).compactMap { p -> QueryColumn? in
                let c = p["fieldExpr"]?["Column"]
                guard let table = c?["Expression"]?["SourceRef"]?["Entity"]?.string, let name = c?["Property"]?.string else { return nil }
                return QueryColumn(table: table, column: name)
            }
            return columns.isEmpty ? nil : (page, columns)
        }
    }()

    var visiblePages: [ReportPage] { report.pages.filter { !$0.isHidden } }

    /// Áp dụng chủ đề JSON ngay trong phiên (Wave 3B: đổi theme tức thời trên canvas).
    @discardableResult
    func applySessionTheme(name: String, data: Data) -> Bool {
        guard let updated = baseTheme.applying(jsonData: data) else { return false }
        theme = updated
        sessionCustomThemeName = name
        return true
    }

    /// Khôi phục chủ đề gốc của tài liệu (khi Undo về trạng thái ban đầu).
    func resetSessionTheme() {
        theme = baseTheme
        sessionCustomThemeName = nil
    }

    func page(id: String) -> ReportPage? { report.pages.first { $0.id == id } }

    var userTables: [ModelMetadata.Table] { metadata?.userTables ?? [] }

    func columns(of table: String) -> [ModelMetadata.Column] {
        metadata?.columns.filter { $0.tableName == table && $0.kind != .rowNumber } ?? []
    }

    func measures(of table: String) -> [ModelMetadata.Measure] {
        metadata?.measures.filter { $0.tableName == table } ?? []
    }

    func hierarchies(of table: String) -> [ModelMetadata.Hierarchy] {
        metadata?.hierarchies.filter { $0.tableName == table } ?? []
    }

    /// Phân cấp ngày Auto date/time của cột (T034): cột có `Variation` thì có "Date Hierarchy" với các cấp của bảng ngày cục bộ.
    /// `hierarchies` chỉ có bảng người dùng, nên cấp lấy theo mẫu `AutoDateTime.hierarchyLevels` (mọi bảng ngày cục bộ giống nhau).
    func dateHierarchy(table: String, column: String) -> FieldRef? {
        guard let variation = metadata?.variations.first(where: { $0.table == table && $0.column == column }) else { return nil }
        let levels = metadata?.hierarchies.first { $0.tableName == variation.hierarchy.table && $0.name == variation.hierarchy.name }?
            .levels.map(\.name) ?? AutoDateTime.hierarchyLevels
        return FieldRef(variation: variation, levels: levels)
    }

    /// Cột của một cấp phân cấp trong visual: phân cấp thường (cột của cấp trong bảng), hay phân cấp ngày (cột cùng tên cấp của bảng
    /// ngày cục bộ qua `Variation`).
    func levelColumn(_ field: ReportField) -> QueryColumn? {
        guard field.kind == .hierarchyLevel, let metadata else { return nil }
        if let column = field.variationColumn {
            guard let variation = metadata.variations.first(where: {
                $0.table == field.entity && $0.column == column && $0.name == (field.variationName ?? $0.name)
            }) else { return nil }
            return QueryColumn(table: variation.hierarchy.table, column: field.property)
        }
        let level = metadata.hierarchies.lazy.filter { $0.tableName == field.entity }
            .compactMap { $0.levels.first { $0.name == field.property }?.columnName }.first
        return level.map { QueryColumn(table: field.entity, column: $0) }
    }

    func measure(table: String, name: String) -> ModelMetadata.Measure? {
        metadata?.measures.first { $0.name == name && ($0.tableName == table || table.isEmpty) }
            ?? metadata?.measures.first { $0.name == name }
    }

    func column(table: String, name: String) -> ModelMetadata.Column? {
        metadata?.columns.first { $0.tableName == table && $0.name == name }
    }

    var tmdlDocuments: [TMDLWriter.Document] { runtime?.tmdlDocuments ?? [] }

    /// Engine DAX của mô hình này, tạo lần đầu khi cần rồi dùng chung cho mọi tab truy vấn.
    /// Chỉ đọc lược đồ và metadata; cột được nạp lười khi truy vấn cần. Gọi ngoài main thread.
    func daxEngine() throws -> DAXEngine {
        guard let runtime else {
            throw DAXError(.runtime, modelError ?? biN("File không có mô hình dữ liệu để chạy truy vấn", "The file has no data model to run queries on"))
        }
        return try runtime.engine()
    }

    /// Tên hiệu lực (sau khi đổi tên cột trong phiên) của các cột lưu trữ `baseNames` của bảng `table`, cùng thứ tự. Cột vẫn là cột
    /// cũ (cùng ID); tên chưa đổi thì giữ nguyên.
    func displayNames(table: String, baseNames: [String]) -> [String] {
        guard let runtime else { return baseNames }
        let base = runtime.base.columns, effective = runtime.metadata.columns
        let byID = Dictionary(effective.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return baseNames.map { name in
            guard let id = base.first(where: { $0.tableName == table && $0.name == name })?.id else { return name }
            return byID[id] ?? name
        }
    }

    /// Bảng có cột hoặc là bảng tính toán thêm, sửa hay phải tính lại trong phiên (T083, T116): dữ liệu đọc từ kho cột của engine, nơi giá trị đã được tính.
    func hasSessionCalculation(_ table: String) -> Bool {
        guard let runtime else { return false }
        return runtime.calculationPlan.all.contains { $0.table == table }
    }

    /// Cột của bảng `name` lấy từ kho cột của engine (mô hình hiệu lực), theo thứ tự cột của mô hình.
    private func computedTable(_ name: String) throws -> [DecodedColumn] {
        guard let runtime else { throw CocoaError(.fileReadUnknown) }
        let version = runtime.version
        if let cached = lock.withLock({ overlayTableCache[name] }), cached.version == version { return cached.columns }
        let engine = try runtime.engine()
        let columns = runtime.metadata.columns.filter { $0.tableName == name && $0.kind != .rowNumber }
        var tableColumns: [TableColumn] = []
        for column in columns {
            guard let id = engine.store.schema.column(table: name, name: column.name)?.id else { continue }
            tableColumns.append(TableColumn(name: column.name, data: try engine.store.column(id)))
        }
        let data = try TableData(columns: tableColumns)
        let decoded = TableDataDecoding.decode(data, names: tableColumns.map(\.name),
                                               types: tableColumns.map { n in columns.first { $0.name == n.name }?.dataType ?? .string })
        lock.withLock { overlayTableCache[name] = (version, decoded) }
        return decoded
    }

    /// Khoá nạp lại dữ liệu của bảng ở lưới Table view: đổi khi tập cột đổi, hoặc khi bảng có dữ liệu trong bộ nhớ (nạp hay tính trong
    /// phiên) và mô hình đổi. Bảng của file không đổi khi chỉ thêm measure.
    func dataKey(_ table: String) -> String {
        let names = columns(of: table).map(\.name).joined(separator: "|")
        let live = hasSessionCalculation(table) || runtime?.overlay(named: table) != nil
        return "\(table)#\(names)#\(live ? runtime?.version ?? 0 : 0)"
    }

    /// Row count from segment metadata only (no column decoding).
    func rowCount(_ table: String) -> Int {
        if hasSessionCalculation(table), let runtime, let engine = try? runtime.engine(),
           let id = engine.store.schema.table(named: table)?.id, let count = try? engine.store.rowCount(id) {
            return count
        }
        if let loaded = runtime?.overlay(named: table) { return loaded.rowCount }
        if let cached = lock.withLock({ rowCountCache[table] }) { return cached }
        guard let metadata = runtime?.base, let abf, let storage = metadata.storage(table: table).first else { return 0 }
        let count = (try? VertiPaq.rowCount(storage, abf: abf)) ?? 0
        lock.withLock { rowCountCache[table] = count }
        return count
    }

    var totalRows: Int { userTables.reduce(0) { $0 + rowCount($1.name) } }

    /// Decodes a table (cached). Columns follow the model's column order.
    func table(_ name: String) throws -> [DecodedColumn] {
        if hasSessionCalculation(name) { return try computedTable(name) }
        if let loaded = runtime?.overlay(named: name), let runtime {
            // Bảng nạp trong bộ nhớ (Phase F): cache theo phiên bản mô hình, vì thay bảng đổi dữ liệu cùng tên.
            let version = runtime.version
            if let cached = lock.withLock({ overlayTableCache[name] }), cached.version == version { return cached.columns }
            let columns = runtime.metadata.columns.filter { $0.tableName == name && $0.kind != .rowNumber }
            let decoded = TableDataDecoding.decode(loaded, names: columns.map(\.name), types: columns.map(\.dataType))
            lock.withLock { overlayTableCache[name] = (version, decoded) }
            return decoded
        }
        if let cached = lock.withLock({ tableCache[name] }) { return cached }
        guard let metadata = runtime?.base, let abf else { throw CocoaError(.fileReadUnknown) }
        let decoded = try VertiPaq.decodeTable(name, metadata: metadata, abf: abf)
        let order = metadata.columns.filter { $0.tableName == name }.map(\.name)
        let sorted = decoded.sorted { (order.firstIndex(of: $0.name) ?? .max) < (order.firstIndex(of: $1.name) ?? .max) }
        lock.withLock { tableCache[name] = sorted }
        return sorted
    }

    func image(named name: String) -> NSImage? {
        if let cached = lock.withLock({ imageCache[name] }) { return cached }
        guard let data = pbix.resource(named: name), let image = NSImage(data: data) else { return nil }
        lock.withLock { imageCache[name] = image }
        return image
    }

    /// Đăng ký ảnh vừa chèn trong phiên (US4) để `ImageVisual` vẽ ngay trên canvas trước khi lưu file.
    func registerSessionImage(_ data: Data, named name: String) {
        guard let image = NSImage(data: data) else { return }
        lock.withLock { imageCache[name] = image }
    }
}
