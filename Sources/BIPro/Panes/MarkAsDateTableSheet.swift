// Wave 4B (T008): Hộp thoại "Đánh dấu bảng ngày" (Mark as Date Table) chuẩn Power BI Desktop 2.159.
import ColumnStore
import PBIXKit
import SwiftUI

enum DateTableValidator {
    /// Kiểm tra cột ngày có đủ điều kiện làm khoá bảng ngày không: kiểu `.dateTime`, có ít nhất 1 dòng, không trống, không trùng.
    static func validate(table: String, column: String, workspace: Workspace) -> String? {
        guard let meta = workspace.metadata,
              let colMeta = meta.columns.first(where: { $0.tableName == table && $0.name == column }) else {
            return "Không tìm thấy cột \(table)[\(column)]."
        }
        guard colMeta.dataType == .dateTime else {
            return "Cột khoá bảng ngày phải có kiểu Ngày/Giờ (Date/DateTime)."
        }
        guard let decoded = try? workspace.table(table),
              let col = decoded.first(where: { $0.name == column }) else {
            return "Không đọc được dữ liệu của bảng \(table)."
        }
        guard col.count > 0 else {
            return "Bảng ngày phải có ít nhất một dòng dữ liệu."
        }
        var seen = Set<Int>()
        for i in 0..<col.count {
            switch col[i] {
            case .null:
                return "Cột \(column) chứa giá trị trống (null) — không thể làm cột khoá bảng ngày."
            case .dateTime(let serial):
                let dayKey = Int(floor(serial))
                if !seen.insert(dayKey).inserted {
                    return "Cột \(column) chứa ngày bị trùng — cột bảng ngày phải có các ngày duy nhất."
                }
            default:
                return "Cột \(column) có giá trị không phải kiểu ngày."
            }
        }
        return nil
    }
}

struct MarkAsDateTableSheet: View {
    @Bindable var state: DocumentState
    let tableName: String
    let onDismiss: () -> Void

    @State private var isMarked: Bool = false
    @State private var selectedColumn: String = ""
    @State private var errorMessage: String? = nil

    private var dateColumns: [ModelMetadata.Column] {
        state.workspace.columns(of: tableName).filter { $0.dataType == .dateTime }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.accent)
                Text(bi("Đánh dấu là bảng ngày", "Mark as date table"))
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
            }

            Text(bi("Bảng: \(tableName)", "Table: \(tableName)"))
                .font(DS.Typeface.bodySmall)
                .foregroundStyle(DS.Palette.secondaryLabel)

            Toggle(bi("Đánh dấu bảng này là bảng ngày (DataCategory = Time)", "Mark as a date table (DataCategory = Time)"),
                   isOn: $isMarked)
                .font(DS.Typeface.body)

            if isMarked {
                if dateColumns.isEmpty {
                    Text(bi("Bảng này không có cột kiểu Ngày/Giờ nào.", "This table has no Date/DateTime columns."))
                        .font(DS.Typeface.bodySmall)
                        .foregroundStyle(DS.Palette.danger)
                } else {
                    Picker(bi("Chọn cột ngày duy nhất:", "Choose a date column:"), selection: $selectedColumn) {
                        ForEach(dateColumns, id: \.name) { col in
                            Text(col.name).tag(col.name)
                        }
                    }
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.danger)
            }

            HStack {
                Spacer()
                Button(bi("Huỷ", "Cancel")) { onDismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(bi("Lưu", "Save")) { apply() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isMarked && selectedColumn.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(DS.Palette.canvas)
        .onAppear {
            let meta = state.workspace.metadata
            let tbl = meta?.tables.first { $0.name == tableName }
            isMarked = tbl?.dataCategory?.caseInsensitiveCompare("Time") == .orderedSame
            selectedColumn = dateColumns.first(where: \.isKey)?.name ?? dateColumns.first?.name ?? ""
        }
    }

    private func apply() {
        errorMessage = nil
        if let reason = state.markAsDateTable(table: tableName, enabled: isMarked, dateColumn: isMarked ? selectedColumn : nil) {
            errorMessage = reason
            return
        }
        onDismiss()
    }
}
