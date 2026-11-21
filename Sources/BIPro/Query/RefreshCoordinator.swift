// Wave 3C (T019): One-Click Refresh — chạy lại truy vấn M của mọi bảng có nguồn bên ngoài,
// giữ nguyên quan hệ, measure, định dạng, visual; bảng lỗi giữ nguyên dữ liệu cũ.
import ColumnStore
import Foundation
import MEngine
import Observation
import PBIXKit

enum TableRefreshStatus: Equatable, Sendable {
    case pending
    case running
    case succeeded(rowCount: Int, changed: Bool)
    case skipped(reason: String)
    case failed(reason: String)
}

struct TableRefreshItem: Identifiable, Equatable, Sendable {
    let id: String
    let tableName: String
    var status: TableRefreshStatus
}

struct RefreshSummary: Equatable, Sendable {
    var succeeded: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var changedTables: [String] = []
    var applyError: String? = nil
    var items: [TableRefreshItem] = []
}

@MainActor
@Observable
final class RefreshProgressState {
    var items: [TableRefreshItem] = []
    var isRunning: Bool = false
    var isCancelled: Bool = false
    var applyError: String? = nil

    var completedCount: Int {
        items.filter {
            switch $0.status {
            case .pending, .running: false
            case .succeeded, .skipped, .failed: true
            }
        }.count
    }

    var progressFraction: Double {
        guard !items.isEmpty else { return 1 }
        return Double(completedCount) / Double(items.count)
    }

    func updateStatus(table: String, _ status: TableRefreshStatus) {
        if let idx = items.firstIndex(where: { $0.tableName == table }) {
            items[idx].status = status
        }
    }
}

enum RefreshCoordinator {
    /// Kiểm tra xem biểu thức M có phải bảng Enter Data nội tuyến (`Table.FromRows(Json.Document(Binary.Decompress(...)))`) không.
    static func isEnterDataExpression(_ source: String) -> Bool {
        source.contains("Table.FromRows(Json.Document(Binary.Decompress(")
    }

    /// Đánh giá lại tất cả bảng M-backed của mô hình; trả về danh sách `LoadedTable` đã nạp thành công kèm tóm tắt trạng thái từng bảng.
    @MainActor
    static func evaluateAll(
        metadata: ModelMetadata,
        existingTable: @escaping @Sendable (String) -> TableData?,
        progress: RefreshProgressState? = nil
    ) async -> (refreshed: [LoadedTable], summary: RefreshSummary) {
        let userTables = metadata.userTables
        let initialItems = userTables.map { TableRefreshItem(id: $0.name, tableName: $0.name, status: .pending) }
        progress?.items = initialItems
        progress?.isRunning = true
        progress?.isCancelled = false
        progress?.applyError = nil

        var items = initialItems
        var refreshed: [LoadedTable] = []
        var summary = RefreshSummary()

        // Chuẩn bị trước các truy vấn không nạp (shared expressions) để bảng có thể tham chiếu chéo.
        var sharedBindings = SourceFunctions.bindings
        if !metadata.expressionBodies.isEmpty {
            let sharedEnv = MEnvironment(bindings: sharedBindings)
            let sharedEval = MEvaluator(environment: sharedEnv)
            for (exprName, exprSource) in metadata.expressionBodies.sorted(by: { $0.key < $1.key }) {
                if let val = try? await sharedEval.evaluate(source: exprSource) {
                    sharedBindings[exprName] = val
                }
            }
        }

        for idx in userTables.indices {
            if progress?.isCancelled == true {
                let reason = bi("Đã huỷ bởi người dùng", "Cancelled by user")
                items[idx].status = .skipped(reason: reason)
                progress?.updateStatus(table: items[idx].tableName, .skipped(reason: reason))
                summary.skipped += 1
                continue
            }
            let table = userTables[idx]
            let tableName = table.name

            // 1. Bỏ qua bảng tính toán DAX (ModelRuntime sẽ tự tính lại sau khi áp dụng bảng mới).
            if metadata.calculatedTableExpressions[tableName] != nil {
                let reason = bi("Bảng tính toán DAX (tự tính lại)", "DAX calculated table (auto-recomputed)")
                items[idx].status = .skipped(reason: reason)
                progress?.updateStatus(table: tableName, .skipped(reason: reason))
                summary.skipped += 1
                continue
            }

            // 2. Bỏ qua bảng không có truy vấn M.
            guard let mSource = metadata.partitionQueries[tableName]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !mSource.isEmpty else {
                let reason = bi("Không có truy vấn nguồn M", "No Power Query M source")
                items[idx].status = .skipped(reason: reason)
                progress?.updateStatus(table: tableName, .skipped(reason: reason))
                summary.skipped += 1
                continue
            }

            // 3. Bỏ qua bảng Enter Data nội tuyến.
            if isEnterDataExpression(mSource) {
                let reason = bi("Bảng nhập thủ công (Enter Data)", "Manual Enter Data table")
                items[idx].status = .skipped(reason: reason)
                progress?.updateStatus(table: tableName, .skipped(reason: reason))
                summary.skipped += 1
                continue
            }

            items[idx].status = .running
            progress?.updateStatus(table: tableName, .running)

            let bindingsSnapshot = sharedBindings
            let result: Result<TableData, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let env = MEnvironment(bindings: bindingsSnapshot)
                    let value = try await MEvaluator(environment: env).evaluate(source: mSource)
                    guard case .table(let fresh) = value else {
                        throw MError.expression("Truy vấn trả về \(value.kindName), không phải bảng")
                    }
                    return .success(fresh)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let fresh):
                let currentData = await Task.detached(priority: .userInitiated) { existingTable(tableName) }.value
                let unchanged = currentData.map { MTables.identical($0, fresh) } ?? false
                let changed = !unchanged
                if changed {
                    refreshed.append(LoadedTable(name: tableName, queryName: tableName, data: fresh, status: .replaced, queryText: mSource))
                    summary.changedTables.append(tableName)
                }
                sharedBindings[tableName] = .table(fresh)
                items[idx].status = .succeeded(rowCount: fresh.rowCount, changed: changed)
                progress?.updateStatus(table: tableName, .succeeded(rowCount: fresh.rowCount, changed: changed))
                summary.succeeded += 1

            case .failure(let error):
                let detail = (error as? MError)?.localizedDescription ?? String(describing: error)
                items[idx].status = .failed(reason: detail)
                progress?.updateStatus(table: tableName, .failed(reason: detail))
                summary.failed += 1
            }
        }

        summary.items = items
        progress?.isRunning = false
        return (refreshed, summary)
    }
}
