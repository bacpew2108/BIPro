// Phase F (T006, T057): trạng thái của Query Editor, để giao diện (gói F-UI) vẽ từ đây.
//
// Mỗi truy vấn là danh sách bước M (`MEngine.MQuery`). Các bước đầu (`lockedStepCount`) do nguồn tạo hoặc đọc từ file: kết quả của chúng
// là bảng gốc (`base`, nạp bằng Connectors hoặc lấy từ mô hình), nên không sửa, xoá hay chèn vào giữa được; bước người dùng thêm
// phía sau được đánh giá bằng engine M. Xem trước tính một lần mỗi bước (`MPreviewCache`).

import ColumnStore
import Foundation
import MEngine
import Observation
import PBIXKit

public struct QueryStep: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Tên bước, duy nhất trong truy vấn ("Source", "Promoted Headers", ...).
    public var name: String
    /// Biểu thức M của bước.
    public var expression: String
    /// `nil` cho bước tuỳ ý (Advanced Editor); xem `StepKind`.
    public var kind: String?

    public init(id: UUID = UUID(), name: String, expression: String, kind: String? = nil) {
        self.id = id
        self.name = name
        self.expression = expression
        self.kind = kind
    }
}

public struct QueryModel: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var steps: [QueryStep]
    /// Cờ "Enable load".
    public var enableLoad: Bool
    /// Số bước đầu không sửa được (kết quả là bảng gốc).
    public var lockedStepCount: Int
    /// Bảng mô hình đã nạp từ truy vấn này; `nil` khi chưa Close & Apply.
    public var loadedTableName: String?
    /// Văn bản M ở lần Close & Apply gần nhất (để biết truy vấn đã sửa chưa).
    public var appliedSource: String?

    public init(id: UUID = UUID(), name: String, steps: [QueryStep] = [], enableLoad: Bool = true, lockedStepCount: Int = 0,
                loadedTableName: String? = nil, appliedSource: String? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.enableLoad = enableLoad
        self.lockedStepCount = lockedStepCount
        self.loadedTableName = loadedTableName
        self.appliedSource = appliedSource
    }

    /// Truy vấn dạng `MQuery` (kết quả là bước cuối).
    public var mquery: MQuery {
        MQuery(steps: steps.map { MStep(name: $0.name, expression: $0.expression) }, resultName: steps.last?.name ?? "")
    }

    /// Văn bản M đầy đủ (Advanced Editor, `Partition.QueryDefinition`).
    public var source: String { mquery.source }

    /// Chưa nạp, hoặc đã sửa sau lần Close & Apply gần nhất.
    public var isModified: Bool { appliedSource != source }
}

/// Một cột của biểu đồ phân bố trong column profile.
public struct ProfileBucket: Sendable, Equatable {
    public let label: String
    public let count: Int

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }
}

/// Số liệu một cột trên 1000 dòng đầu (column profile).
public struct ColumnProfile: Sendable, Equatable {
    public let columnName: String
    public let valid: Int
    public let error: Int
    public let empty: Int
    public let distinct: Int
    public let unique: Int
    /// Giá trị nhỏ nhất, lớn nhất, trung bình đã định dạng (cột số, ngày); `nil` khi không có.
    public let min: String?
    public let max: String?
    public let average: String?
    public let distribution: [ProfileBucket]

    public init(columnName: String, valid: Int, error: Int, empty: Int, distinct: Int, unique: Int,
                min: String? = nil, max: String? = nil, average: String? = nil, distribution: [ProfileBucket] = []) {
        self.columnName = columnName
        self.valid = valid
        self.error = error
        self.empty = empty
        self.distinct = distinct
        self.unique = unique
        self.min = min
        self.max = max
        self.average = average
        self.distribution = distribution
    }
}

/// Kết quả của một lệnh Ribbon (`QueryEditorState.perform`).
public enum StepCommandOutcome: Equatable, Sendable {
    case applied
    /// Bước đang chọn không phải bước cuối: Desktop hỏi "Insert Step" trước khi chèn. Gọi lại với `confirmInsert: true` nếu đồng ý.
    case needsInsertConfirmation
    case rejected(String)
}

@MainActor
@Observable
public final class QueryEditorState {
    public var queries: [QueryModel] = []
    public var selectedQueryID: UUID?
    /// Chỉ số bước đang chọn trong truy vấn đang chọn; `nil` khi chưa có bước.
    public private(set) var selectedStepIndex: Int?
    /// Bảng xem trước tại bước đang chọn (tối đa 1000 dòng).
    public var preview: TableData?
    public var profiles: [ColumnProfile] = []
    /// Lỗi của bước đang chọn (hiện ở lưới); `nil` khi bước tính được.
    public var errorMessage: String?
    /// Tên bước → thông điệp lỗi của lần xem trước gần nhất (dấu cảnh báo cạnh bước).
    public private(set) var stepErrors: [String: String] = [:]
    /// Có thay đổi chưa "Close & Apply".
    public var hasPendingChanges = false
    /// Lý do Close & Apply bị từ chối (hiện ở thanh dưới); `nil` khi chưa áp dụng hoặc đã xong. Lead gán sau khi gọi `closeAndApply`.
    public var applyMessage: String?
    /// Đang áp dụng (nút Close & Apply tắt, hiện vòng quay).
    public var isApplying = false

    @ObservationIgnored private var bases: [UUID: TableData] = [:]
    /// Bảng nền nạp lười (bảng lớn trong file): chỉ dựng khi truy vấn được xem trước hoặc áp dụng, ngoài luồng chính.
    @ObservationIgnored private var baseLoaders: [UUID: @Sendable () -> TableData?] = [:]
    /// Lần dựng đang chạy: xem trước và Close & Apply cùng chờ một lần, không dựng hai lần và không chạy khi chưa có nền.
    @ObservationIgnored private var baseTasks: [UUID: Task<TableData?, Never>] = [:]
    @ObservationIgnored private var caches: [UUID: MPreviewCache] = [:]
    @ObservationIgnored private var cacheSignatures: [UUID: String] = [:]
    @ObservationIgnored private var dependencyResults: [UUID: (signature: String, table: TableData)] = [:]
    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    private struct Snapshot {
        let queries: [QueryModel]
        let selectedQueryID: UUID?
        let selectedStepIndex: Int?
        let pending: Bool
    }

    public init() {}

    public var selectedQuery: QueryModel? { queries.first { $0.id == selectedQueryID } }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Chọn

    /// Chọn truy vấn; bước đang chọn chuyển sang bước cuối của truy vấn đó (như Desktop).
    public func selectQuery(_ id: UUID) {
        guard let query = queries.first(where: { $0.id == id }) else { return }
        selectedQueryID = id
        selectedStepIndex = query.steps.isEmpty ? nil : query.steps.count - 1
        scheduleRefresh()
    }

    /// Chọn bước; chỉ số ngoài phạm vi bị bỏ qua.
    public func selectStep(_ index: Int) {
        guard let query = selectedQuery, query.steps.indices.contains(index) else { return }
        selectedStepIndex = index
        scheduleRefresh()
    }

    // MARK: Nạp truy vấn

    /// Thêm truy vấn (từ Get Data hoặc đọc từ file). `base` là bảng kết quả của các bước khoá; `nil` thì xem trước các bước khoá báo thiếu dữ liệu.
    /// Không vào ngăn xếp hoàn tác và không đánh dấu thay đổi chưa áp dụng (truy vấn chưa nạp vẫn `isModified`).
    public func addQuery(_ query: QueryModel, base: TableData?) {
        queries.append(query)
        if let base { bases[query.id] = base }
        if selectedQueryID == nil { selectQuery(query.id) }
    }

    /// Như `addQuery(_:base:)` nhưng bảng nền dựng lười bằng `baseLoader` (chạy ngoài luồng chính, một lần, khi cần).
    public func addQuery(_ query: QueryModel, baseLoader: @escaping @Sendable () -> TableData?) {
        queries.append(query)
        baseLoaders[query.id] = baseLoader
        if selectedQueryID == nil { selectQuery(query.id) }
    }

    /// Dựng bảng nền lười của truy vấn nếu chưa dựng (không thử lại khi `baseLoader` trả `nil`).
    private func ensureBase(_ query: QueryModel) async {
        guard bases[query.id] == nil else { return }
        if baseTasks[query.id] == nil, let loader = baseLoaders.removeValue(forKey: query.id) {
            baseTasks[query.id] = Task.detached(priority: .userInitiated) { loader() }
        }
        guard let task = baseTasks[query.id] else { return }
        let base = await task.value
        if let base, bases[query.id] == nil { bases[query.id] = base }
        baseTasks[query.id] = nil
    }

    /// Truy vấn từ bảng vừa nạp bằng Get Data: các bước đầu do nguồn tạo, khoá, kết quả là chính bảng đã nạp.
    public func addQuery(from loaded: LoadedTable) {
        let steps = loaded.initialSteps
        let query = QueryModel(name: loaded.queryName, steps: steps.isEmpty ? [QueryStep(name: "Source", expression: "#table({}, {})", kind: StepKind.source)] : steps,
                               lockedStepCount: max(steps.count, 1), loadedTableName: loaded.status == .new ? nil : loaded.name)
        addQuery(query, base: loaded.data)
    }

    /// Tách văn bản M thành truy vấn. Không phân tích được thì giữ nguyên văn làm một bước tuỳ ý (data-model.md).
    static func model(name: String, source: String, tableName: String?, locked: Bool) -> QueryModel {
        let steps: [QueryStep]
        if let parsed = try? MQuery.parse(source) {
            steps = parsed.steps.map { QueryStep(name: $0.name, expression: $0.expression, kind: StepKind.file) }
        } else {
            steps = [QueryStep(name: "Source", expression: source, kind: StepKind.custom)]
        }
        var query = QueryModel(name: name, steps: steps, lockedStepCount: locked ? steps.count : 0, loadedTableName: tableName)
        query.appliedSource = query.source
        return query
    }

    // MARK: Lệnh Ribbon

    /// Thêm bước cho lệnh Ribbon ngay sau bước đang chọn. Bước đang chọn không phải bước cuối thì cần `confirmInsert` (hộp "Insert Step").
    @discardableResult
    public func perform(_ command: StepCommand, confirmInsert: Bool = false) -> StepCommandOutcome {
        guard let queryIndex = selectedQueryIndex, let index = selectedStepIndex else { return .rejected("Chưa có truy vấn nào được chọn.") }
        var query = queries[queryIndex]
        if index < query.lockedStepCount - 1 {
            return .rejected("Bước nguồn do BI Pro tạo (\(query.lockedStepCount) bước đầu): chỉ thêm bước sau bước \"\(query.steps[query.lockedStepCount - 1].name)\".")
        }
        if index < query.steps.count - 1, !confirmInsert { return .needsInsertConfirmation }
        var mquery = query.mquery
        let new = StepFactory.steps(for: command, after: query.steps[index].name, existingNames: Set(query.steps.map(\.name)),
                                      currentQuery: query.name)
        mquery.insert(new, afterStepAt: index)
        let kinds = Dictionary(new.map { ($0.name, StepKind.custom) }, uniquingKeysWith: { a, _ in a })
        query = reshaped(query, from: mquery, newKinds: kinds)
        commit(query, at: queryIndex, select: index + new.count)
        return .applied
    }

    // MARK: Sửa bước

    /// Xoá bước. Từ chối với bước khoá. Bước đứng sau trỏ vào bước bị xoá được nối về bước đứng trước ([SUY ĐOÁN], xem `MQuery.removeStep`).
    @discardableResult
    public func deleteStep(at index: Int) -> String? {
        guard let queryIndex = selectedQueryIndex, queries[queryIndex].steps.indices.contains(index) else { return "Không có bước này." }
        let query = queries[queryIndex]
        if let reason = lockedReason(query, index) { return reason }
        if query.steps.count == 1 { return "Truy vấn phải có ít nhất một bước." }
        var mquery = query.mquery
        mquery.removeStep(at: index)
        commit(reshaped(query, from: mquery), at: queryIndex, select: min(index, mquery.steps.count - 1))
        return nil
    }

    /// Đổi tên bước (và các tham chiếu ở bước sau). Tên rỗng hoặc trùng bị từ chối.
    @discardableResult
    public func renameStep(at index: Int, to newName: String) -> String? {
        guard let queryIndex = selectedQueryIndex, queries[queryIndex].steps.indices.contains(index) else { return "Không có bước này." }
        let query = queries[queryIndex]
        if let reason = lockedReason(query, index) { return reason }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Tên bước không được để trống." }
        if query.steps.enumerated().contains(where: { $0.offset != index && $0.element.name == name }) { return "Đã có bước tên \"\(name)\"." }
        var mquery = query.mquery
        mquery.renameStep(at: index, to: name)
        commit(reshaped(query, from: mquery, keepingIDsByIndex: true), at: queryIndex, select: index)
        return nil
    }

    /// Sửa biểu thức M của bước (thanh công thức). Lỗi cú pháp bị từ chối kèm dòng và cột.
    @discardableResult
    public func setExpression(at index: Int, _ expression: String) -> String? {
        guard let queryIndex = selectedQueryIndex, queries[queryIndex].steps.indices.contains(index) else { return "Không có bước này." }
        var query = queries[queryIndex]
        if let reason = lockedReason(query, index) { return reason }
        let text = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        do { _ = try MParser.parse(text) } catch let error as MSyntaxError {
            return "Dòng \(error.line), cột \(error.column): \(error.message)"
        } catch { return "\(error)" }
        query.steps[index].expression = text
        query.steps[index].kind = StepKind.custom
        commit(query, at: queryIndex, select: index)
        return nil
    }

    /// Đổi chỗ bước với bước kế (`offset` -1 lên, +1 xuống). Không kiểm phụ thuộc: bước hỏng hiện lỗi ở Applied Steps.
    @discardableResult
    public func moveStep(at index: Int, by offset: Int) -> String? {
        guard let queryIndex = selectedQueryIndex else { return "Chưa có truy vấn nào được chọn." }
        var query = queries[queryIndex]
        let target = index + offset
        guard query.steps.indices.contains(index), query.steps.indices.contains(target) else { return "Không di chuyển được bước này." }
        if let reason = lockedReason(query, index) ?? lockedReason(query, target) { return reason }
        query.steps.swapAt(index, target)
        commit(query, at: queryIndex, select: target)
        return nil
    }

    /// Advanced Editor: văn bản M đầy đủ của truy vấn đang chọn.
    public var advancedSource: String { selectedQuery?.source ?? "" }

    /// Áp văn bản M đã sửa ở Advanced Editor: phân tích lại thành bước. Các bước khoá phải giữ nguyên; kết quả phải là bước cuối.
    @discardableResult
    public func applyAdvancedSource(_ text: String) -> String? {
        guard let queryIndex = selectedQueryIndex else { return "Chưa có truy vấn nào được chọn." }
        var query = queries[queryIndex]
        let parsed: MQuery
        do { parsed = try MQuery.parse(text) } catch let error as MSyntaxError {
            return "Dòng \(error.line), cột \(error.column): \(error.message)"
        } catch { return "\(error)" }
        let locked = query.steps.prefix(query.lockedStepCount).map { MStep(name: $0.name, expression: $0.expression) }
        guard Array(parsed.steps.prefix(locked.count)) == locked else {
            return "Không sửa được \(locked.count) bước đầu do nguồn tạo (BI Pro chưa nạp lại nguồn từ M)."
        }
        guard parsed.resultName == parsed.steps.last?.name else { return "Kết quả sau \"in\" phải là bước cuối cùng." }
        let byName = Dictionary(query.steps.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        query.steps = parsed.steps.map { step in
            if var old = byName[step.name] {
                if old.expression != step.expression { old.kind = StepKind.custom }
                old.expression = step.expression
                return old
            }
            return QueryStep(name: step.name, expression: step.expression, kind: StepKind.custom)
        }
        commit(query, at: queryIndex, select: query.steps.count - 1)
        return nil
    }

    // MARK: Truy vấn

    /// Đổi tên truy vấn chưa nạp (tên bảng sẽ là tên truy vấn). Tên rỗng, trùng truy vấn khác hoặc trùng bảng đã có bị từ chối.
    @discardableResult
    public func renameQuery(_ id: UUID, to newName: String, existingTableNames: Set<String> = []) -> String? {
        guard let queryIndex = queries.firstIndex(where: { $0.id == id }) else { return "Không có truy vấn này." }
        var query = queries[queryIndex]
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Tên truy vấn không được để trống." }
        if query.loadedTableName != nil { return "Truy vấn đã nạp thành bảng \"\(query.loadedTableName!)\": đổi tên bảng ở khung Dữ liệu." }
        let others = Set(queries.filter { $0.id != id }.map { $0.name.lowercased() })
        if others.contains(name.lowercased()) || existingTableNames.contains(where: { $0.lowercased() == name.lowercased() }) {
            return "Đã có truy vấn hoặc bảng tên \"\(name)\"."
        }
        let oldName = query.name
        query.name = name
        // Truy vấn khác đang tham chiếu tên cũ (Merge, Append, tham chiếu) được đổi theo; cùng một bước hoàn tác.
        var renamedOthers: [(Int, QueryModel)] = []
        for (index, other) in queries.enumerated() where index != queryIndex {
            let ownSteps = Set(other.steps.map(\.name))
            guard !ownSteps.contains(oldName) else { continue }
            var updated = other
            for k in updated.steps.indices {
                updated.steps[k].expression = MQuery.renameReference(in: updated.steps[k].expression, from: oldName, to: name)
            }
            if updated.steps.map(\.expression) != other.steps.map(\.expression) { renamedOthers.append((index, updated)) }
        }
        commit(query, at: queryIndex, select: selectedStepIndex)
        for (index, updated) in renamedOthers { queries[index] = updated }
        return nil
    }

    /// Bật hoặc tắt "Enable load". Tắt cho truy vấn đã nạp thì Close & Apply gỡ bảng khỏi mô hình.
    public func setEnableLoad(_ id: UUID, _ value: Bool) {
        guard let queryIndex = queries.firstIndex(where: { $0.id == id }), queries[queryIndex].enableLoad != value else { return }
        var query = queries[queryIndex]
        query.enableLoad = value
        commit(query, at: queryIndex, select: selectedStepIndex)
    }

    // MARK: Hoàn tác

    /// Hoàn tác thay đổi gần nhất của Applied Steps (từng thao tác một).
    public func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(last)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(next)
    }

    // MARK: Xem trước

    /// Tính lại xem trước và profile của bước đang chọn. Lần gọi cũ đang chạy bị bỏ kết quả.
    public func refresh() async {
        refreshTask?.cancel()
        await recompute()
    }

    private func recompute() async {
        generation += 1
        let mine = generation
        guard let query = selectedQuery, let index = selectedStepIndex, query.steps.indices.contains(index) else {
            preview = nil; profiles = []; errorMessage = nil
            return
        }
        let name = query.steps[index].name
        let effective = effectiveQuery(query)
        do {
            await ensureBase(query)
            guard mine == generation else { return }
            let cache = try await preparedCache(for: query)
            guard mine == generation else { return }
            let value = try await cache.preview(effective, stepIndex: index, rowLimit: ColumnProfiler.defaultRowLimit)
            guard mine == generation else { return }
            guard case .table(let table) = value else {
                preview = nil; profiles = []
                errorMessage = "Bước \"\(name)\" không trả về bảng (\(value.kindName))."
                stepErrors[name] = errorMessage
                return
            }
            preview = table
            profiles = ColumnProfiler.profile(table).map(Self.profile)
            errorMessage = nil
            stepErrors[name] = nil
        } catch {
            guard mine == generation else { return }
            preview = nil; profiles = []
            let message = Self.message(error, hasBase: bases[query.id] != nil, locked: index < query.lockedStepCount)
            errorMessage = message
            stepErrors[name] = message
        }
    }

    /// Đánh giá đủ (không cắt dòng) kết quả của truy vấn, cho Close & Apply.
    func evaluateFull(_ query: QueryModel, rowLimit: Int? = nil) async throws -> TableData {
        guard !query.steps.isEmpty else { throw MError.expression("Truy vấn không có bước nào.") }
        let value = try await preparedCache(for: query).preview(effectiveQuery(query), stepIndex: query.steps.count - 1, rowLimit: rowLimit)
        guard case .table(let table) = value else { throw MError.expression("Kết quả không phải bảng (\(value.kindName)).") }
        return table
    }

    func message(for error: Error, in query: QueryModel) -> String {
        Self.message(error, hasBase: bases[query.id] != nil, locked: false)
    }

    // MARK: Nội bộ

    private var selectedQueryIndex: Int? { queries.firstIndex { $0.id == selectedQueryID } }

    private func lockedReason(_ query: QueryModel, _ index: Int) -> String? {
        index < query.lockedStepCount
            ? "Bước \"\(query.steps[index].name)\" do nguồn tạo hoặc đọc từ file: chưa sửa được (BI Pro chưa nạp lại nguồn từ M)."
            : nil
    }

    /// Truy vấn đã sửa bằng `MQuery` về lại mô hình: giữ id và loại của bước cùng tên.
    private func reshaped(_ query: QueryModel, from mquery: MQuery, newKinds: [String: String] = [:], keepingIDsByIndex: Bool = false) -> QueryModel {
        var result = query
        let byName = Dictionary(query.steps.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        result.steps = mquery.steps.enumerated().map { offset, step in
            if keepingIDsByIndex, query.steps.indices.contains(offset) {
                var old = query.steps[offset]
                old.name = step.name
                old.expression = step.expression
                return old
            }
            if var old = byName[step.name] {
                old.expression = step.expression
                return old
            }
            return QueryStep(name: step.name, expression: step.expression, kind: newKinds[step.name] ?? StepKind.custom)
        }
        return result
    }

    private func snapshot() -> Snapshot {
        Snapshot(queries: queries, selectedQueryID: selectedQueryID, selectedStepIndex: selectedStepIndex, pending: hasPendingChanges)
    }

    private func restore(_ snapshot: Snapshot) {
        queries = snapshot.queries
        selectedQueryID = snapshot.selectedQueryID
        selectedStepIndex = snapshot.selectedStepIndex
        hasPendingChanges = snapshot.pending
        scheduleRefresh()
    }

    private func commit(_ query: QueryModel, at queryIndex: Int, select step: Int?) {
        undoStack.append(snapshot())
        redoStack.removeAll()
        queries[queryIndex] = query
        selectedStepIndex = step.map { min(max($0, 0), max(query.steps.count - 1, 0)) }
        hasPendingChanges = true
        scheduleRefresh()
    }

    /// Gọi sau khi Close & Apply thành công: đánh dấu các truy vấn đã áp dụng.
    func markApplied(_ updates: [UUID: (tableName: String?, source: String)]) {
        for index in queries.indices {
            guard let update = updates[queries[index].id] else { continue }
            queries[index].loadedTableName = update.tableName
            queries[index].appliedSource = update.source
        }
        hasPendingChanges = false
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.recompute()
        }
    }

    /// Bước khoá có biểu thức `__BaseTable` (kết quả là bảng gốc); bước người dùng giữ nguyên.
    private func effectiveQuery(_ query: QueryModel) -> MQuery {
        MQuery(steps: query.steps.enumerated().map { index, step in
            MStep(name: step.name, expression: index < query.lockedStepCount ? Self.baseBinding : step.expression)
        }, resultName: query.steps.last?.name ?? "")
    }

    /// Bộ nhớ đệm xem trước của truy vấn, môi trường có bảng nền và kết quả của các truy vấn khác mà nó tham chiếu (Merge, Append, tham chiếu).
    /// Truy vấn phụ thuộc đổi thì dựng lại bộ nhớ đệm. Vòng tham chiếu ném lỗi nêu đường vòng.
    private func preparedCache(for query: QueryModel) async throws -> MPreviewCache {
        await ensureBase(query)
        var byName: [String: MQuery] = [:]
        for other in queries where byName[other.name] == nil { byName[other.name] = effectiveQuery(other) }
        let graph = QueryDependencies.graph(byName)
        let order = try QueryDependencies.evaluationOrder(for: query.name, in: graph)
        var bindings: [String: MValue] = [:]
        var signature = ""
        for name in order {
            guard let dependency = queries.first(where: { $0.name == name }) else { continue }
            await ensureBase(dependency)
            let key = dependency.steps.map { "\($0.name)\u{2}\($0.expression)" }.joined(separator: "\u{1}")
            signature += "\(name)\u{3}\(key)\u{4}"
            if let cached = dependencyResults[dependency.id], cached.signature == signature {
                bindings[name] = .table(cached.table)
                continue
            }
            var environment = MEnvironment(bindings: bindings)
            if let base = bases[dependency.id] { environment.bindings[Self.baseBinding] = .table(base) }
            let value = try await MPreviewCache(environment: environment)
                .preview(effectiveQuery(dependency), stepIndex: dependency.steps.count - 1, rowLimit: nil)
            guard case .table(let table) = value else {
                throw MError.expression("Truy vấn \"\(name)\" không trả về bảng (\(value.kindName)).")
            }
            dependencyResults[dependency.id] = (signature, table)
            bindings[name] = .table(table)
        }
        if let cache = caches[query.id], cacheSignatures[query.id] == signature { return cache }
        var environment = MEnvironment(bindings: bindings)
        if let base = bases[query.id] { environment.bindings[Self.baseBinding] = .table(base) }
        let cache = MPreviewCache(environment: environment)
        caches[query.id] = cache
        cacheSignatures[query.id] = signature
        return cache
    }

    private static let baseBinding = "__BaseTable"

    private static func message(_ error: Error, hasBase: Bool, locked: Bool) -> String {
        if let m = error as? MError {
            if m.message.contains(baseBinding) { return "Chưa có dữ liệu nguồn của truy vấn này." }
            return m.reason == "Expression.Unsupported" ? m.message : "\(m.reason): \(m.message)"
        }
        if let s = error as? MSyntaxError { return "Dòng \(s.line), cột \(s.column): \(s.message)" }
        return "\(error)"
    }

    private static func profile(_ stats: ColumnStats) -> ColumnProfile {
        func label(_ value: MValue) -> String {
            switch value {
            case .number(let d): NavigatorFormat.cell(.double(d))
            case .currency(let c): NavigatorFormat.cell(.currency(c))
            case .text(let s): NavigatorFormat.cell(.string(s))
            case .logical(let b): NavigatorFormat.cell(.boolean(b))
            case .date(let d), .dateTime(let d): NavigatorFormat.cell(.dateTime(d))
            default: value.kindName
            }
        }
        return ColumnProfile(columnName: stats.name, valid: stats.valid, error: stats.error, empty: stats.empty, distinct: stats.distinct,
                             unique: stats.unique, min: stats.min.map(label), max: stats.max.map(label),
                             average: stats.average.map { NavigatorFormat.cell(.double($0)) },
                             distribution: stats.distribution.map { ProfileBucket(label: label($0.value), count: $0.count) })
    }
}

extension QueryEditorState {
    /// Liệt kê truy vấn đã có trong file (`Partition.QueryDefinition` của mỗi bảng, FR-014). Bước đọc từ file bị khoá: kết quả của chúng
    /// là bảng đang có trong mô hình (`tableData`), nên bước người dùng thêm phía sau tính từ dữ liệu đó. `tableData` trả `nil` khi
    /// chưa có dữ liệu (xem trước báo thiếu nguồn).
    func addQueries(from metadata: ModelMetadata, tableData: @escaping @Sendable (String) -> TableData?) {
        for table in metadata.userTables {
            guard let text = metadata.partitionQueries[table.name], !text.isEmpty else { continue }
            let query = Self.model(name: table.name, source: text, tableName: table.name, locked: true)
            let name = table.name
            addQuery(query, baseLoader: { tableData(name) })
        }
    }
}
