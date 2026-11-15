import Foundation
import PBIXKit

/// Phase E: cổng duy nhất sửa mô hình từ giao diện. Mỗi thao tác được kiểm trên mô hình hiệu lực (`validate`) rồi vào
/// ngăn xếp hoàn tác chung của `LayoutEditor`; thao tác sai trả lý do và không đổi gì.
@MainActor
final class ModelEditor {
    private let layout: LayoutEditor
    private let validate: (ModelEdits) throws -> Void
    /// Lý do gần nhất một thao tác bị từ chối; nil khi thao tác gần nhất được chấp nhận.
    private(set) var refusal: String?

    init(layout: LayoutEditor, validate: @escaping (ModelEdits) throws -> Void) {
        self.layout = layout
        self.validate = validate
    }

    var edits: ModelEdits { layout.modelEdits }

    /// Áp một thao tác. Trả lý do bị từ chối (tiếng Việt) hoặc nil khi chấp nhận. `coalesceKey` gộp các lần gõ liên tiếp.
    @discardableResult
    func apply(_ edit: ModelEdit, coalesceKey: String? = nil) -> String? {
        let proposed = layout.modelEdits.appending(edit)
        do {
            try validate(proposed)
        } catch let error as ModelEditError {
            refusal = error.reason
            return error.reason
        } catch {
            refusal = "\(error)"
            return refusal
        }
        refusal = nil
        layout.commitModel(proposed, coalesceKey: coalesceKey)
        return nil
    }

    /// Áp nhiều thao tác như một bước hoàn tác (nạp nhiều bảng cùng lúc). Tất cả hoặc không: thao tác nào bị từ chối thì không
    /// thao tác nào vào. Trả lý do (tiếng Việt) hoặc nil khi chấp nhận (cả khi `edits` rỗng).
    @discardableResult
    func apply(_ edits: [ModelEdit]) -> String? {
        guard !edits.isEmpty else { return nil }
        var proposed = layout.modelEdits
        for edit in edits { proposed = proposed.appending(edit) }
        do {
            try validate(proposed)
        } catch let error as ModelEditError {
            refusal = error.reason
            return error.reason
        } catch {
            refusal = "\(error)"
            return refusal
        }
        refusal = nil
        layout.commitModel(proposed)
        return nil
    }
}
