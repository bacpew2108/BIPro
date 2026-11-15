// Phase F (T006): trạng thái của hộp thoại Get Data và Navigator, để giao diện (gói F-UI) vẽ từ đây.
// Khung hợp đồng: thuộc tính cố định; hành vi thật (đọc nguồn, tải, huỷ) cài ở T039.

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

    public init() {}

    public var canLoad: Bool { !checkedItemIDs.isEmpty && phase == .ready }

    /// Đánh dấu hoặc bỏ đánh dấu một mục; mục không có trong danh sách bị bỏ qua.
    public func toggle(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        if checkedItemIDs.contains(id) { checkedItemIDs.remove(id) } else { checkedItemIDs.insert(id) }
    }
}
