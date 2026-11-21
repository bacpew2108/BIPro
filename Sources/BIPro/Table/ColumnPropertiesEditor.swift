import PBIXKit
import SwiftUI

/// Phase E (T028): sửa thuộc tính cột không đụng dữ liệu ở Table view: tên, mô tả, thư mục hiển thị, định dạng, tổng hợp mặc định,
/// loại dữ liệu hiển thị, sắp xếp theo cột, ẩn. Mọi thay đổi đi qua `DocumentState.updateColumn` (hoàn tác chung).
struct ColumnPropertiesEditor: View {
    let state: DocumentState
    let column: ModelMetadata.Column

    @State private var name: String
    @State private var description: String
    @State private var folder: String
    @State private var format: String
    @State private var message: String?

    @MainActor
    static var summarizeOptions: [(value: Int, title: String)] {
        [
            (1, bi("Mặc định", "Default")), (2, bi("Không tổng hợp", "Don't summarize")),
            (3, bi("Tổng", "Sum")), (7, bi("Trung bình", "Average")),
            (4, bi("Nhỏ nhất", "Minimum")), (5, bi("Lớn nhất", "Maximum")),
            (6, bi("Đếm", "Count")), (8, bi("Đếm phân biệt", "Count (Distinct)")),
        ]
    }
    static let categories = ["Address", "Barcode", "City", "Continent", "Country", "County", "ImageUrl", "Latitude", "Longitude",
                             "Place", "PostalCode", "StateOrProvince", "WebUrl"]
    static let formatPresets = ["0", "#,0", "#,0.00", "0%", "0.0%", "\\$#,0", "\\$#,0.00", "General Date", "dd/MM/yyyy"]

    init(state: DocumentState, column: ModelMetadata.Column) {
        self.state = state
        self.column = column
        _name = State(initialValue: column.name)
        _description = State(initialValue: column.description ?? "")
        _folder = State(initialValue: column.displayFolder ?? "")
        _format = State(initialValue: column.formatString ?? "")
    }

    var body: some View {
        let blocker = state.modelEditingBlocker
        let siblings = state.workspace.columns(of: column.tableName).filter { $0.id != column.id && $0.kind != .rowNumber }
        let sortName = column.sortByColumnID.flatMap { id in siblings.first { $0.id == id }?.name }
        VStack(alignment: .leading, spacing: 6) {
            Text(bi("SỬA THUỘC TÍNH", "EDIT PROPERTIES")).font(DS.Typeface.labelSmall).tracking(0.5).foregroundStyle(DS.Palette.tertiaryLabel)
            field(bi("Tên", "Name"), text: $name, placeholder: bi("Tên cột", "Column name")) { commit(ColumnPatch(name: name), key: nil) }
            field(bi("Mô tả", "Description"), text: $description, placeholder: bi("Mô tả", "Description")) { commit(ColumnPatch(description: description.isEmpty ? .clear : .set(description)), key: "description") }
            field(bi("Thư mục", "Folder"), text: $folder, placeholder: bi("Thư mục hiển thị", "Display folder")) { commit(ColumnPatch(displayFolder: folder.isEmpty ? .clear : .set(folder)), key: "folder") }
            HStack(spacing: 6) {
                field(bi("Định dạng", "Format"), text: $format, placeholder: bi("Chuỗi định dạng", "Format string")) { commit(ColumnPatch(formatString: format.isEmpty ? .clear : .set(format)), key: "format") }
                Menu {
                    ForEach(Self.formatPresets, id: \.self) { preset in
                        Button(preset) { format = preset; commit(ColumnPatch(formatString: .set(preset)), key: "format") }
                    }
                    Divider()
                    Button(bi("Bỏ định dạng", "Clear format")) { format = ""; commit(ColumnPatch(formatString: .clear), key: "format") }
                } label: { Image(systemName: "chevron.down.circle") }
                    .menuStyle(.borderlessButton).frame(width: 22).disabled(blocker != nil)
            }
            if column.dataType.isNumeric {
                picker(bi("Tổng hợp", "Summarize"), selection: Binding(get: { column.summarizeBy },
                                                      set: { commit(ColumnPatch(summarizeBy: $0), key: nil) })) {
                    ForEach(Self.summarizeOptions, id: \.value) { Text($0.title).tag($0.value) }
                }
            }
            picker(bi("Loại dữ liệu", "Data category"), selection: Binding(get: { column.dataCategory ?? "" },
                                                      set: { commit(ColumnPatch(dataCategory: $0.isEmpty ? .clear : .set($0)), key: nil) })) {
                Text(bi("Chưa phân loại", "Uncategorized")).tag("")
                ForEach(Self.categories + (column.dataCategory.map { Self.categories.contains($0) ? [] : [$0] } ?? []), id: \.self) { Text($0).tag($0) }
            }
            picker(bi("Sắp xếp theo", "Sort by"), selection: Binding(get: { sortName ?? "" },
                                                      set: { commit(ColumnPatch(sortBy: $0.isEmpty ? .clear : .set($0)), key: nil) })) {
                Text(bi("Chính nó", "Itself")).tag("")
                ForEach(siblings.map(\.name), id: \.self) { Text($0).tag($0) }
            }
            Toggle(bi("Ẩn trong chế độ báo cáo", "Hide in report view"), isOn: Binding(get: { column.isHidden }, set: { commit(ColumnPatch(isHidden: $0), key: nil) }))
                .font(DS.Typeface.bodySmall).disabled(blocker != nil)
            if let text = message ?? blocker {
                Text(text).font(DS.Typeface.bodySmall).foregroundStyle(message != nil ? Color.red : DS.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

    @ViewBuilder
    private func picker<T: Hashable, Content: View>(_ label: String, selection: Binding<T>, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).frame(width: 64, alignment: .leading)
            Picker("", selection: selection, content: content).labelsHidden().disabled(state.modelEditingBlocker != nil)
        }
    }

    private func commit(_ patch: ColumnPatch, key: String?) {
        message = state.updateColumn(table: column.tableName, name: column.name, patch: patch,
                                     coalesceKey: key.map { "column-\(column.id)-\($0)" })
        if message != nil { name = column.name }
    }
}
