// Phase F (T006): trạng thái của Query Editor, để giao diện (gói F-UI) vẽ từ đây.
// Khung hợp đồng: thuộc tính và thao tác bước cơ bản; chạy M, xem trước và profile cài ở T055 đến T057.

import Foundation
import Observation
import ColumnStore

public struct QueryStep: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Tên bước, duy nhất trong truy vấn ("Source", "Promoted Headers", ...).
    public var name: String
    /// Biểu thức M của bước.
    public var expression: String
    /// `nil` cho bước tuỳ ý (Advanced Editor).
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

    public init(id: UUID = UUID(), name: String, steps: [QueryStep] = [], enableLoad: Bool = true) {
        self.id = id
        self.name = name
        self.steps = steps
        self.enableLoad = enableLoad
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

    public init(columnName: String, valid: Int, error: Int, empty: Int, distinct: Int, unique: Int) {
        self.columnName = columnName
        self.valid = valid
        self.error = error
        self.empty = empty
        self.distinct = distinct
        self.unique = unique
    }
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
    public var errorMessage: String?
    /// Có thay đổi chưa "Close & Apply".
    public var hasPendingChanges = false

    public init() {}

    public var selectedQuery: QueryModel? { queries.first { $0.id == selectedQueryID } }

    /// Chọn truy vấn; bước đang chọn chuyển sang bước cuối của truy vấn đó (như Desktop).
    public func selectQuery(_ id: UUID) {
        guard let query = queries.first(where: { $0.id == id }) else { return }
        selectedQueryID = id
        selectedStepIndex = query.steps.isEmpty ? nil : query.steps.count - 1
    }

    /// Chọn bước; chỉ số ngoài phạm vi bị bỏ qua.
    public func selectStep(_ index: Int) {
        guard let query = selectedQuery, query.steps.indices.contains(index) else { return }
        selectedStepIndex = index
    }
}
