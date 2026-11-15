// Phase F (T006): trạng thái của hộp thoại Get Data và Navigator, để giao diện (gói F-UI) vẽ từ đây.
// Hợp đồng cố định ở T006; hành vi (mở nguồn, xem trước, nạp, huỷ) cài ở T039. Trạng thái này không đụng mô hình:
// `load` chỉ trả `[LoadedTable]`, việc đưa vào mô hình là T021.

import Foundation
import Observation
import ColumnStore
import Connectors

public struct NavigatorItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let kind: SourceItemKind
    public let rowCountHint: Int?

    public init(id: String, name: String, kind: SourceItemKind, rowCountHint: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rowCountHint = rowCountHint
    }
}

@MainActor
@Observable
public final class NavigatorState {
    public enum Phase: Equatable, Sendable {
        case choosingSource
        case listingItems
        case ready
        case loading
        case failed(String)
    }

    public var phase: Phase = .choosingSource
    public var sourceKind: SourceKind?
    /// Đường dẫn file hoặc địa chỉ nguồn người dùng chọn.
    public var location: String = ""
    public var items: [NavigatorItem] = []
    public var checkedItemIDs: Set<String> = []
    /// Mục đang xem trước (một mục tại một thời điểm).
    public var previewItemID: String?
    public var preview: TableData?
    /// 0...1 khi `phase == .loading`.
    public var progress: Double = 0

    /// Lý do xem trước hỏng (một mục lỗi không làm hỏng cả Navigator). `nil` khi xem trước được.
    public var previewError: String?
    /// Kết quả của lần `load` gần nhất (rỗng khi lỗi hoặc huỷ).
    public private(set) var loaded: [LoadedTable] = []

    @ObservationIgnored private var sourceItems: [String: any SourceItem] = [:]
    @ObservationIgnored private var loadTask: Task<[LoadedTable], Error>?
    @ObservationIgnored private let makeSource: (SourceKind, String) throws -> any DataSource

    public init(makeSource: @escaping (SourceKind, String) throws -> any DataSource = SourceFactory.make) {
        self.makeSource = makeSource
    }

    public var canLoad: Bool { !checkedItemIDs.isEmpty && phase == .ready }

    /// Mở nguồn và liệt kê mục. Xoá danh sách, đánh dấu và xem trước của nguồn trước. Lỗi → `.failed(thông điệp tiếng Việt)`.
    public func openSource(kind: SourceKind, location: String) async {
        loadTask?.cancel()
        sourceKind = kind
        self.location = location
        items = []
        sourceItems = [:]
        checkedItemIDs = []
        previewItemID = nil
        preview = nil
        previewError = nil
        loaded = []
        progress = 0
        phase = .listingItems
        do {
            let found = try await makeSource(kind, location).items()
            var listed: [NavigatorItem] = []
            for (index, item) in found.enumerated() {
                let id = "item-\(index)"
                sourceItems[id] = item
                listed.append(NavigatorItem(id: id, name: item.name, kind: item.kind, rowCountHint: item.rowCountHint))
            }
            items = listed
            phase = .ready
        } catch {
            phase = .failed(SourceMessage.text(for: error))
        }
    }

    /// Xem trước một mục (tối đa 200 dòng). Mục không có trong danh sách bị bỏ qua. Lỗi ghi vào `previewError`.
    public func showPreview(_ id: String) async {
        guard let item = sourceItems[id] else { return }
        previewItemID = id
        preview = nil
        previewError = nil
        do {
            let table = try await item.preview(limit: 200)
            guard previewItemID == id else { return }   // người dùng đã chọn mục khác trong lúc chờ
            preview = table
        } catch {
            guard previewItemID == id else { return }
            previewError = SourceMessage.text(for: error)
        }
    }

    /// Nạp các mục đã đánh dấu (theo thứ tự danh sách). Trả `nil` khi lỗi (`.failed`) hoặc huỷ (về `.ready`).
    /// Tên bảng khử trùng với `existingNames`. Không đổi mô hình.
    public func load(existingNames: Set<String> = []) async -> [LoadedTable]? {
        guard canLoad else { return nil }
        let chosen = items.filter { checkedItemIDs.contains($0.id) }.compactMap { sourceItems[$0.id] }
        let origin = sourceKind.map { (kind: $0, location: location) }
        phase = .loading
        progress = 0
        loaded = []
        let task = Task<[LoadedTable], Error> { [weak self] in
            try await TableLoader.load(chosen, existingNames: existingNames, source: origin, progress: { fraction in
                Task { @MainActor in self?.advance(to: fraction) }
            })
        }
        loadTask = task
        defer { loadTask = nil }
        do {
            let tables = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            loaded = tables
            progress = 1
            phase = .ready
            return tables
        } catch SourceError.cancelled {
            progress = 0
            phase = .ready
            return nil
        } catch is CancellationError {
            progress = 0
            phase = .ready
            return nil
        } catch {
            progress = 0
            phase = .failed(SourceMessage.text(for: error))
            return nil
        }
    }

    /// Huỷ lần `load` đang chạy (nếu có). `load` trả `nil` và phase về `.ready`.
    public func cancelLoad() { loadTask?.cancel() }

    private func advance(to fraction: Double) {
        guard phase == .loading else { return }
        progress = max(progress, min(max(fraction, 0), 1))
    }

    /// Đánh dấu hoặc bỏ đánh dấu một mục; mục không có trong danh sách bị bỏ qua.
    public func toggle(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        if checkedItemIDs.contains(id) { checkedItemIDs.remove(id) } else { checkedItemIDs.insert(id) }
    }
}
