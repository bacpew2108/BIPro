import Foundation
import MEngine

/// Logic thuần của hộp thoại Append Queries (Nối truy vấn).
public struct AppendDialogModel: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case twoTables
        case threeOrMore
    }

    public var primaryQueryName: String
    public var candidates: [String]
    public var mode: Mode {
        didSet {
            if mode == .twoTables && selectedQueries.count > 1 {
                selectedQueries = Array(selectedQueries.prefix(1))
            }
        }
    }
    public var selectedQueries: [String]

    public init(
        primaryQueryName: String,
        candidates: [String] = [],
        mode: Mode = .twoTables,
        selectedQueries: [String] = []
    ) {
        self.primaryQueryName = primaryQueryName
        self.candidates = candidates
        self.mode = mode
        if mode == .twoTables {
            self.selectedQueries = Array(selectedQueries.prefix(1))
        } else {
            self.selectedQueries = selectedQueries
        }
    }

    /// Chọn một bảng thứ hai trong chế độ "Hai bảng".
    public mutating func selectTwoTablesQuery(_ query: String) {
        selectedQueries = [query]
    }

    /// Chọn/bỏ chọn trong chế độ "Từ ba bảng"; thứ tự chọn là thứ tự nối.
    public mutating func toggleSelection(_ query: String) {
        if let idx = selectedQueries.firstIndex(of: query) {
            selectedQueries.remove(at: idx)
        } else {
            selectedQueries.append(query)
        }
    }

    /// Thứ tự 1-based của truy vấn đã chọn, hoặc nil nếu chưa chọn.
    public func order(of query: String) -> Int? {
        guard let idx = selectedQueries.firstIndex(of: query) else { return nil }
        return idx + 1
    }

    public var isValid: Bool {
        !selectedQueries.isEmpty
    }

    public func command() -> StepCommand? {
        guard isValid else { return nil }
        return .append(queries: selectedQueries)
    }

    /// So sánh danh sách cột giữa bảng chính và bảng phụ để báo số cột chung và số cột chỉ có ở bảng phụ.
    public static func columnComparison(
        primaryColumns: [String],
        secondaryColumns: [String]
    ) -> (commonCount: Int, secondaryOnlyCount: Int) {
        let primarySet = Set(primaryColumns)
        let secondarySet = Set(secondaryColumns)
        let common = primarySet.intersection(secondarySet).count
        let secondaryOnly = secondarySet.subtracting(primarySet).count
        return (commonCount: common, secondaryOnlyCount: secondaryOnly)
    }
}
