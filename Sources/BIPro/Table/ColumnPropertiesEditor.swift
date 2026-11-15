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

    static let summarizeOptions: [(value: Int, title: String)] = [
        (1, "Mặc định"), (2, "Không tổng hợp"), (3, "Tổng"), (7, "Trung bình"), (4, "Nhỏ nhất"), (5, "Lớn nhất"), (6, "Đếm"), (8, "Đếm phân biệt"),
    ]
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
            Text("SỬA THUỘC TÍNH").font(DS.Typeface.labelSmall).tracking(0.5).foregroundStyle(DS.Palette.tertiaryLabel)
            field("Tên", text: $name, placeholder: "Tên cột") { commit(ColumnPatch(name: name), key: nil) }
            field("Mô tả", text: $description, placeholder: "Mô tả") { commit(ColumnPatch(description: description.isEmpty ? .clear : .set(description)), key: "description") }
            field("Thư mục", text: $folder, placeholder: "Thư mục hiển thị") { commit(ColumnPatch(displayFolder: folder.isEmpty ? .clear : .set(folder)), key: "folder") }
            HStack(spacing: 6) {
                field("Định dạng", text: $format, placeholder: "Chuỗi định dạng") { commit(ColumnPatch(formatString: format.isEmpty ? .clear : .set(format)), key: "format") }
                Menu {
                    ForEach(Self.formatPresets, id: \.self) { preset in
                        Button(preset) { format = preset; commit(ColumnPatch(formatString: .set(preset)), key: "format") }
                    }
                    Divider()
                    Button("Bỏ định dạng") { format = ""; commit(ColumnPatch(formatString: .clear), key: "format") }
                } label: { Image(systemName: "chevron.down.circle") }
                    .menuStyle(.borderlessButton).frame(width: 22).disabled(blocker != nil)
            }
            if column.dataType.isNumeric {
                picker("Tổng hợp", selection: Binding(get: { column.summarizeBy },
                                                      set: { commit(ColumnPatch(summarizeBy: $0), key: nil) })) {
                    ForEach(Self.summarizeOptions, id: \.value) { Text($0.title).tag($0.value) }
                }
            }
            picker("Loại dữ liệu", selection: Binding(get: { column.dataCategory ?? "" },
                                                      set: { commit(ColumnPatch(dataCategory: $0.isEmpty ? .clear : .set($0)), key: nil) })) {
                Text("Chưa phân loại").tag("")
                ForEach(Self.categories + (column.dataCategory.map { Self.categories.contains($0) ? [] : [$0] } ?? []), id: \.self) { Text($0).tag($0) }
            }
            picker("Sắp xếp theo", selection: Binding(get: { sortName ?? "" },
                                                      set: { commit(ColumnPatch(sortBy: $0.isEmpty ? .clear : .set($0)), key: nil) })) {
                Text("Chính nó").tag("")
                ForEach(siblings.map(\.name), id: \.self) { Text($0).tag($0) }
            }
            Toggle("Ẩn trong chế độ báo cáo", isOn: Binding(get: { column.isHidden }, set: { commit(ColumnPatch(isHidden: $0), key: nil) }))
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
