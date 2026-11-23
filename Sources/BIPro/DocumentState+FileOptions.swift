// Đợt tồn đọng sau Phase F, T033: Tệp ▸ "Tuỳ chọn tệp", như Options ▸ Current File ▸ Data Load của Desktop 2.159 (VM-F11b, VM-F11c, ảnh b4):
// "Auto date/time" (chú thích mô hình `__PBI_TimeIntelligenceEnabled`, bật hay tắt sinh lệnh `AutoDateTime.toggle`) và
// "Tự phát hiện quan hệ mới sau khi nạp" (part `Settings`). Mỗi tuỳ chọn đổi là một bước ⌘Z.

import Foundation
import PBIXKit

/// Giá trị của hộp "Tuỳ chọn tệp".
struct FileOptions: Equatable {
    var autoDateTime: Bool
    var autodetectRelationships: Bool
}

extension DocumentState {
    var fileOptions: FileOptions {
        FileOptions(autoDateTime: workspace.metadata.map(AutoDateTime.isEnabled) ?? false,
                    autodetectRelationships: layout.autodetectRelationships)
    }

    /// Lý do chưa đổi được Auto date/time (cần mô hình sửa được), nil khi đổi được.
    var autoDateTimeBlocker: String? {
        if workspace.runtime == nil { return workspace.modelError ?? biN("File không có mô hình dữ liệu.", "The file has no data model.") }
        if workspace.pbix.reportFormat == .none { return biN("File này không có báo cáo đọc được; chưa lưu được thay đổi mô hình.", "This file has no readable report; model changes can't be saved yet.") }
        return nil
    }

    func showFileOptionsDialog() { showFileOptions = true }

    /// "OK": áp phần đổi. Trả lý do bị từ chối (hộp ở lại) hoặc nil.
    @discardableResult
    func applyFileOptions(_ options: FileOptions) -> String? {
        let current = fileOptions
        if options.autoDateTime != current.autoDateTime {
            if let blocker = autoDateTimeBlocker { return blocker }
            guard let model = workspace.metadata else { return biN("File không có mô hình dữ liệu.", "The file has no data model.") }
            if !options.autoDateTime, let users = variationUsers.nilIfEmpty {
                return biN("Chưa tắt được Tự động ngày/giờ: visual vẫn dùng phân cấp ngày (\(users.joined(separator: ", "))). ", "Can't turn off Auto date/time yet: visuals still use the date hierarchy (\(users.joined(separator: ", "))). ")
                    + biN("Bỏ phân cấp ngày khỏi các visual đó rồi tắt lại.", "Remove the date hierarchy from those visuals, then turn it off again.")
            }
            if let refusal = modelEditor.apply(AutoDateTime.toggle(enabled: options.autoDateTime, model: model)) { return refusal }
        }
        if options.autodetectRelationships != current.autodetectRelationships {
            layout.setAutodetectRelationships(options.autodetectRelationships)
        }
        return nil
    }

    /// Visual còn dùng cấp phân cấp ngày Auto date/time ("Trang: loại visual"). Desktop khi tắt viết lại chúng thành cột ngày thường
    /// (VM-F11b step4); BI Pro chưa làm nên chặn (T038: không chặn thì visual ra một cột "Blank" mang tổng, sai mà không báo).
    var variationUsers: [String] {
        layout.pages.flatMap { page in
            page.visuals.filter { $0.fields.contains { $0.variationColumn != nil } }.map { "\(page.displayName): \(VisualCatalog.name($0.type))" }
        }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
