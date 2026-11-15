import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

/// Phase E (R1, R4): mô hình hiệu lực (mô hình gốc + `ModelEdits`) và engine DAX chạy trên nó.
///
/// `ColumnStore` (cột đã giải mã) được dùng chung khi chỉ measure đổi; engine mới chỉ khác `Catalog`, nên bộ nhớ đệm
/// của engine cũ (`MeasureCache`) không dính sang. Đổi quan hệ hoặc cột dựng `ColumnStore` mới từ mô hình hiệu lực
/// (chi phí đo ở spike S2, `measurements.md`).
final class ModelRuntime: @unchecked Sendable {
    /// Mô hình gốc (đúng như file); phần lưu trữ cột (`storage`) luôn đọc theo mô hình này.
    let base: ModelMetadata
    private let abf: ABFBackup
    private let lock = NSLock()
    private var currentEdits = ModelEdits()
    private var effective: ModelMetadata
    private var baseStore: ColumnStore?
    private var cachedEngine: DAXEngine?
    private var tmdl: [TMDLWriter.Document]?
    private var versionValue = 0
    private var overlayCache: [TableID: TableData] = [:]
    private var overlayVersion = -1

    init(metadata: ModelMetadata, abf: ABFBackup) {
        base = metadata
        self.abf = abf
        effective = metadata
    }

    /// Mô hình hiệu lực.
    var metadata: ModelMetadata { lock.withLock { effective } }

    var edits: ModelEdits { lock.withLock { currentEdits } }

    /// Tăng mỗi khi mô hình hiệu lực đổi (khoá nạp lại của visual).
    var version: Int { lock.withLock { versionValue } }

    /// Dữ liệu ô của bảng nạp trong bộ nhớ (mới hoặc thay thế) có tên `name` trong mô hình hiệu lực; nil với bảng của file.
    func overlay(named name: String) -> TableData? {
        lock.withLock {
            if overlayVersion != versionValue {
                overlayCache = currentEdits.hasTableEdits ? currentEdits.tableData(in: effective) : [:]
                overlayVersion = versionValue
            }
            guard let table = effective.userTables.first(where: { $0.name == name }) else { return nil }
            return overlayCache[TableID(raw: table.id)]
        }
    }

    /// Văn bản TMDL sinh từ mô hình hiệu lực.
    var tmdlDocuments: [TMDLWriter.Document] {
        lock.withLock {
            if let tmdl { return tmdl }
            let documents = TMDLWriter.documents(for: effective)
            tmdl = documents
            return documents
        }
    }

    /// Kiểm `edits` trên mô hình gốc mà không đổi gì; ném `ModelEditError` khi sai.
    func validate(_ edits: ModelEdits) throws {
        _ = try base.applying(edits)
    }

    /// Đặt danh sách thao tác (đầy đủ, không cộng dồn). Ném `ModelEditError` thì mô hình giữ nguyên.
    func setEdits(_ edits: ModelEdits) throws {
        let isSame = lock.withLock { edits == currentEdits }
        if isSame { return }
        let result = try base.applying(edits)
        lock.withLock {
            currentEdits = edits
            effective = result
            cachedEngine = nil
            tmdl = nil
            versionValue += 1
        }
    }

    /// Engine cho mô hình hiệu lực. Tạo lười; gọi ngoài luồng chính. Nếu mô hình đổi trong lúc dựng thì bỏ engine cũ và dựng lại,
    /// để không bao giờ cất engine của phiên bản đã lỗi thời.
    func engine() throws -> DAXEngine {
        while true {
            let (cached, metadata, edits, builtVersion) = lock.withLock { (cachedEngine, effective, currentEdits, versionValue) }
            if let cached { return cached }
            let store: ColumnStore
            if edits.hasTableEdits {
                // Bảng nạp mới/thay thế chồng lên kho gốc; bảng còn lại dùng lại cột đã giải mã.
                let overlays = edits.tableData(in: metadata)
                store = ColumnStore(source: OverlayColumnSource(base: try rootStore(), schema: ModelSchema(metadata: metadata), tables: overlays))
            } else if edits.touchesSchema {
                // Lược đồ mới (quan hệ, cột) nhưng cột đã giải mã dùng lại từ kho gốc; không được thì dựng từ file.
                let root = try rootStore()
                if let source = ReschematedColumnSource(base: root, schema: ModelSchema(metadata: metadata)) {
                    store = ColumnStore(source: source)
                } else {
                    store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: metadata))
                }
            } else {
                store = try rootStore()
            }
            let engine = DAXEngine(store: store, catalog: Catalog(metadata: metadata))
            let stored: DAXEngine? = lock.withLock {
                if let cached = cachedEngine, versionValue == builtVersion { return cached }
                guard versionValue == builtVersion else { return nil }
                cachedEngine = engine
                return engine
            }
            if let stored { return stored }
        }
    }

    /// Kho cột gốc (lược đồ của file), dựng một lần; mọi engine dùng lại cột đã giải mã của nó.
    private func rootStore() throws -> ColumnStore {
        if let shared = lock.withLock({ baseStore }) { return shared }
        let store = ColumnStore(source: try PBIXColumnSource(abf: abf, metadata: base))
        return lock.withLock {
            if let shared = baseStore { return shared }
            baseStore = store
            return store
        }
    }
}

extension ModelEdits {
    /// Có thao tác đổi lược đồ mà `ColumnStore` dựng từ (quan hệ, cột), không chỉ measure.
    var touchesSchema: Bool {
        items.contains {
            switch $0 {
            case .updateRelationship, .updateColumn, .addRelationship, .deleteRelationship, .updateTable,
                 .addTable, .replaceTable, .dropTable, .addCalculatedColumn, .addCalculatedTable: true
            case .addMeasure, .updateMeasure, .deleteMeasure: false
            }
        }
    }
}

extension ModelEdits {
    /// Có thao tác thêm, thay hoặc xoá bảng (nguồn cột phải chồng dữ liệu trong bộ nhớ).
    var hasTableEdits: Bool {
        items.contains {
            switch $0 {
            case .addTable, .replaceTable, .dropTable: true
            default: false
            }
        }
    }

    /// Dữ liệu ô của các bảng đang có hiệu lực, theo `Table.ID` của mô hình hiệu lực `metadata`. Duyệt theo thứ tự thao tác:
    /// thêm/thay đặt dữ liệu theo tên bảng mới (`NewTable.attachment`), xoá bỏ.
    func tableData(in metadata: ModelMetadata) -> [TableID: TableData] {
        var byName: [String: TableData] = [:]
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for item in items {
            switch item {
            case .addTable(let table):
                if table.enableLoad, let data = table.attachment as? TableData { byName[key(table.name)] = data }
            case .replaceTable(let old, let table):
                byName[key(old)] = nil
                if table.enableLoad, let data = table.attachment as? TableData { byName[key(table.name)] = data }
            case .dropTable(let name):
                byName[key(name)] = nil
            default:
                break
            }
        }
        var result: [TableID: TableData] = [:]
        for table in metadata.userTables {
            if let data = byName[key(table.name)] { result[TableID(raw: table.id)] = data }
        }
        return result
    }
}
