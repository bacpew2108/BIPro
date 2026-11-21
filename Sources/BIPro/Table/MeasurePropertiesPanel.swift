import PBIXKit
import SwiftUI

/// Phase E (T015): thuộc tính của measure đang chọn ở Table view: mô tả, thư mục hiển thị, định dạng, ẩn, xoá.
/// Tên và biểu thức sửa ở thanh công thức. Mọi thay đổi đi qua `DocumentState.updateMeasure` (hoàn tác chung).
struct MeasurePropertiesPanel: View {
    let state: DocumentState
    let measure: ModelMetadata.Measure

    @State private var description: String
    @State private var folder: String
    @State private var format: String
    @State private var message: String?

    static let formatPresets = ["0", "#,0", "#,0.00", "0%", "0.0%", "\\$#,0", "\\$#,0.00", "General Date"]

    init(state: DocumentState, measure: ModelMetadata.Measure) {
        self.state = state
        self.measure = measure
        _description = State(initialValue: measure.description ?? "")
        _folder = State(initialValue: measure.displayFolder ?? "")
        _format = State(initialValue: measure.formatString ?? "")
    }

    var body: some View {
        let blocker = state.modelEditingBlocker
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bi("THÔNG TIN MEASURE", "MEASURE PROPERTIES")).font(DS.Typeface.labelSmall).tracking(0.5).foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer()
                Circle().fill(DS.Palette.measure).frame(width: 6, height: 6)
            }
            PropertyRow(label: bi("Tên", "Name"), value: measure.name)
            PropertyRow(label: bi("Bảng", "Table"), value: measure.tableName)
            PropertyRow(label: bi("Kiểu", "Type"), value: Self.typeName(measure.dataType))
            if measure.state != 1 { PropertyRow(label: bi("Trạng thái", "State"), value: bi("Có lỗi (state \(measure.state))", "Error (state \(measure.state))")) }
            field(bi("Mô tả", "Description"), text: $description, placeholder: bi("Mô tả", "Description")) { commit(MeasurePatch(description: description.isEmpty ? .clear : .set(description)), key: "description") }
            field(bi("Thư mục", "Folder"), text: $folder, placeholder: bi("Thư mục hiển thị (dùng \\ cho cấp con)", "Display folder (use \\ for subfolders)")) { commit(MeasurePatch(displayFolder: folder.isEmpty ? .clear : .set(folder)), key: "folder") }
            HStack(spacing: 6) {
                field(bi("Định dạng", "Format"), text: $format, placeholder: bi("Chuỗi định dạng", "Format string")) { commit(MeasurePatch(formatString: format.isEmpty ? .clear : .set(format)), key: "format") }
                Menu {
                    ForEach(Self.formatPresets, id: \.self) { preset in
                        Button(preset) { format = preset; commit(MeasurePatch(formatString: .set(preset)), key: "format") }
                    }
                    Divider()
                    Button(bi("Bỏ định dạng", "Clear format")) { format = ""; commit(MeasurePatch(formatString: .clear), key: "format") }
                } label: { Image(systemName: "chevron.down.circle") }
                    .menuStyle(.borderlessButton).frame(width: 22).disabled(blocker != nil)
            }
            Toggle(bi("Ẩn trong chế độ báo cáo", "Hide in report view"), isOn: Binding(get: { measure.isHidden },
                                                           set: { commit(MeasurePatch(isHidden: $0), key: nil) }))
                .font(DS.Typeface.bodySmall).disabled(blocker != nil)
            HStack {
                Button(bi("Xoá khỏi mô hình", "Delete from model"), role: .destructive) {
                    message = state.deleteMeasure(table: measure.tableName, name: measure.name)
                }
                .disabled(blocker != nil)
                Spacer()
            }
            if let text = message ?? blocker {
                Text(text).font(DS.Typeface.bodySmall).foregroundStyle(message != nil ? Color.red : DS.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
        .padding(10)
        .background(DS.Palette.chrome)
        .disabled(false)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, placeholder: String, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).font(DS.Typeface.bodySmall)
                .onSubmit(onSubmit)
                .disabled(state.modelEditingBlocker != nil)
        }
    }

    private func commit(_ patch: MeasurePatch, key: String?) {
        message = state.updateMeasure(table: measure.tableName, name: measure.name, patch: patch,
                                      coalesceKey: key.map { "measure-\(measure.name)-\($0)" })
    }

    @MainActor
    static func typeName(_ type: ModelMetadata.DataType) -> String {
        switch type {
        case .int64: bi("Số nguyên", "Whole number")
        case .double: bi("Số thực", "Decimal number")
        case .decimal: bi("Tiền tệ", "Currency")
        case .string: bi("Văn bản", "Text")
        case .boolean: bi("Đúng/Sai", "True/False")
        case .dateTime: bi("Ngày giờ", "Date/time")
        case .variant: bi("Hỗn hợp", "Variant")
        default: bi("Chưa rõ", "Unknown")
        }
    }
}

/// Phase E (T015): ngăn thuộc tính measure ở Model view: công thức sửa được và các thuộc tính, trong một thẻ nổi cạnh sơ đồ.
struct MeasureInspector: View {
    let state: DocumentState
    let measure: ModelMetadata.Measure
    @Bindable var draft: MeasureDraft

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "function").foregroundStyle(DS.Palette.measure)
                Text(bi("Thuộc tính measure", "Measure properties")).font(DS.Typeface.headlineSmall)
                Spacer()
                Button { state.measure = nil; state.measureDraft = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(GhostIconButtonStyle())
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            MeasureFormulaBar(state: state, draft: draft)
            MeasurePropertiesPanel(state: state, measure: measure)
                .id("\(measure.tableName)/\(measure.name)/\(state.modelVersion)")
        }
        .background(DS.Palette.canvas)
        .popoverElevation()
    }
}
