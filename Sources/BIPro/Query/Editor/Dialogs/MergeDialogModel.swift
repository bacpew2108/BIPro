import Foundation
import ColumnStore
import MEngine

/// Logic thuần của hộp thoại Merge Queries (Gộp truy vấn).
public struct MergeDialogModel: Sendable, Equatable {
    public enum StatusLevel: Sendable, Equatable {
        case info
        case warning
        case ok
    }

    public var primaryQueryName: String
    public var leftColumns: [QueryColumnInfo]
    public var rightColumns: [QueryColumnInfo]
    public var leftKeys: [String]
    public var rightKeys: [String]
    public var kind: JoinChoice
    public var secondQuery: String?

    public init(
        primaryQueryName: String,
        leftColumns: [QueryColumnInfo] = [],
        rightColumns: [QueryColumnInfo] = [],
        leftKeys: [String] = [],
        rightKeys: [String] = [],
        kind: JoinChoice = .leftOuter,
        secondQuery: String? = nil
    ) {
        self.primaryQueryName = primaryQueryName
        self.leftColumns = leftColumns
        self.rightColumns = rightColumns
        self.leftKeys = leftKeys
        self.rightKeys = rightKeys
        self.kind = kind
        self.secondQuery = secondQuery
    }

    /// Chọn hoặc bỏ chọn cột khoá bảng trái; thứ tự chọn là thứ tự khoá.
    public mutating func toggleLeft(_ column: String) {
        if let idx = leftKeys.firstIndex(of: column) {
            leftKeys.remove(at: idx)
        } else {
            leftKeys.append(column)
        }
    }

    /// Chọn hoặc bỏ chọn cột khoá bảng phải; thứ tự chọn là thứ tự khoá.
    public mutating func toggleRight(_ column: String) {
        if let idx = rightKeys.firstIndex(of: column) {
            rightKeys.remove(at: idx)
        } else {
            rightKeys.append(column)
        }
    }

    public var isValid: Bool {
        guard let secondQuery, !secondQuery.isEmpty else { return false }
        guard !leftKeys.isEmpty else { return false }
        return leftKeys.count == rightKeys.count
    }

    public var statusLevel: StatusLevel {
        guard let secondQuery, !secondQuery.isEmpty, !(leftKeys.isEmpty && rightKeys.isEmpty) else {
            return .info
        }
        if leftKeys.count != rightKeys.count {
            return .info
        }
        if firstTypeMismatch() != nil {
            return .warning
        }
        return .ok
    }

    public var statusMessage: String {
        guard let secondQuery, !secondQuery.isEmpty, !(leftKeys.isEmpty && rightKeys.isEmpty) else {
            return "Chọn bảng thứ hai và cột khớp ở cả hai bảng."
        }
        if leftKeys.count != rightKeys.count {
            return "Số cột khoá hai bên phải bằng nhau (trái \(leftKeys.count), phải \(rightKeys.count))."
        }
        if let mismatch = firstTypeMismatch() {
            return "Cột khoá \"\(mismatch.leftName)\" (\(mismatch.leftType)) và \"\(mismatch.rightName)\" (\(mismatch.rightType)) khác kiểu nên sẽ không khớp dòng nào."
        }
        return "Đã chọn \(leftKeys.count) cặp cột khoá."
    }

    public func command() -> StepCommand? {
        guard isValid, let second = secondQuery else { return nil }
        return .merge(
            otherQuery: second,
            leftKeys: leftKeys,
            rightKeys: rightKeys,
            kind: kind,
            newColumn: second
        )
    }

    private struct TypeMismatch {
        let leftName: String
        let leftType: String
        let rightName: String
        let rightType: String
    }

    private func firstTypeMismatch() -> TypeMismatch? {
        let count = min(leftKeys.count, rightKeys.count)
        for i in 0..<count {
            let leftName = leftKeys[i]
            let rightName = rightKeys[i]
            let leftType = leftColumns.first(where: { $0.name == leftName })?.type
            let rightType = rightColumns.first(where: { $0.name == rightName })?.type
            if let leftType, let rightType, !typesCompatible(leftType, rightType) {
                return TypeMismatch(
                    leftName: leftName,
                    leftType: typeDescription(leftType),
                    rightName: rightName,
                    rightType: typeDescription(rightType)
                )
            }
        }
        return nil
    }

    private func typesCompatible(_ a: DAXType, _ b: DAXType) -> Bool {
        if isNumeric(a) && isNumeric(b) { return true }
        return a == b
    }

    private func isNumeric(_ type: DAXType) -> Bool {
        switch type {
        case .integer, .double, .currency: return true
        default: return false
        }
    }

    private func typeDescription(_ type: DAXType) -> String {
        switch type {
        case .integer, .double, .currency: return "số"
        case .string: return "văn bản"
        case .dateTime: return "ngày giờ"
        case .boolean: return "đúng/sai"
        }
    }
}
