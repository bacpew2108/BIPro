// Gói P (Phase C đợt 3): sửa bộ lọc Basic trong Filters pane.
//
// [QUAN SÁT] Bộ lọc của Nhom6 là Categorical `In` / `Not In` trên một cột. Editor liệt kê giá trị của cột (truy vấn qua engine),
// người dùng chọn tập giá trị và chế độ "là" / "không phải"; mỗi thay đổi ghi ngay vào `ReportInteraction.userFilters`
// nên mọi visual nạp lại. [SUY ĐOÁN] Cách Power BI hiện `Not In` trong Basic filtering (đánh dấu phần còn lại) chưa quan sát:
// docs/phase-c-oracle/VM-TODO-P.md.
import DAXEngine
import PBIXKit
import SwiftUI

@MainActor
enum FilterEditing {
    /// Cột sửa được của một thẻ: bộ lọc `In`/`Not In` đơn giản trong file, hoặc thẻ ngầm của một field cột. nil = chỉ xem.
    static func column(of filter: ReportFilter) -> QueryColumn? {
        if let user = UserFilter.from(filter) { return user.column }
        guard filter.raw == .null, let field = filter.field, field.kind == .column else { return nil }
        return QueryColumn(table: field.entity, column: field.property)
    }

    /// Trạng thái hiện tại của thẻ: phần người dùng sửa, nếu không thì phần trong file.
    static func current(of filter: ReportFilter, key: UserFilterKey, interaction: ReportInteraction) -> UserFilter? {
        interaction.userFilters[key] ?? UserFilter.from(filter)
            ?? column(of: filter).map { UserFilter(column: $0, values: [], exclude: false) }
    }

    static func isActive(_ filter: ReportFilter, key: UserFilterKey, interaction: ReportInteraction) -> Bool {
        if let edit = interaction.userFilters[key] { return edit.isActive }
        return filter.isActive
    }

    static func summary(of filter: ReportFilter, key: UserFilterKey, interaction: ReportInteraction) -> String {
        interaction.userFilters[key]?.summary ?? filter.summary
    }

    /// Thêm hoặc bớt một giá trị. Trả bộ lọc mới.
    static func toggle(_ value: Value, in filter: UserFilter) -> UserFilter {
        var next = filter
        if let at = next.values.firstIndex(of: value) { next.values.remove(at: at) } else { next.values.append(value) }
        return next
    }

    /// "Chọn tất cả" = bỏ hết lựa chọn cho chế độ "là" (không lọc) — Power BI coi tập rỗng và tập đủ đều là "Tất cả".
    static func selectAll(in filter: UserFilter) -> UserFilter {
        var next = filter
        next.values = []
        next.exclude = false
        return next
    }

    /// Giá trị còn khớp ô tìm kiếm.
    static func matching(_ values: [Value], search: String) -> [Value] {
        search.isEmpty ? values : values.filter { UserFilter.display($0).localizedCaseInsensitiveContains(search) }
    }
}

struct BasicFilterEditor: View {
    let interaction: ReportInteraction
    let key: UserFilterKey
    let filter: ReportFilter
    let column: QueryColumn

    private enum Load { case loading, failed(String), loaded([Value]) }
    @State private var load: Load = .loading
    @State private var search = ""
    private static let limit = 1000

    var body: some View {
        let current = FilterEditing.current(of: filter, key: key, interaction: interaction)
            ?? UserFilter(column: column, values: [], exclude: false)
        VStack(alignment: .leading, spacing: 6) {
            SegmentedPill(selection: modeBinding(current), options: [
                .init(value: false, title: "là"), .init(value: true, title: "không phải"),
            ], fill: true)
            SearchField(text: $search, prompt: "Tìm giá trị")
            switch load {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).frame(height: 40)
            case .failed(let message):
                Text(message).font(DS.Typeface.bodySmall).foregroundStyle(.red).lineLimit(3)
            case .loaded(let values):
                list(values, current: current)
            }
            HStack {
                Button("Chọn tất cả") { write(FilterEditing.selectAll(in: current)) }
                Spacer()
                Button("Đặt lại") { interaction.setUserFilter(nil, for: key) }
                    .disabled(interaction.userFilters[key] == nil)
            }
            .buttonStyle(.plain).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.accent)
        }
        .padding(.top, 6)
        .task(id: column) { await fetch() }
    }

    @ViewBuilder private func list(_ values: [Value], current: UserFilter) -> some View {
        let shown = FilterEditing.matching(values, search: search)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown, id: \.self) { value in
                    let on = current.values.contains(value)
                    Button { write(FilterEditing.toggle(value, in: current)) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .foregroundStyle(on ? DS.Palette.accent : DS.Palette.tertiaryLabel)
                            Text(UserFilter.display(value)).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.label).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if values.count >= Self.limit {
                    Text("Chỉ hiện \(Self.limit) giá trị đầu").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel).padding(.top, 4)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    private func modeBinding(_ current: UserFilter) -> Binding<Bool> {
        Binding(get: { current.exclude }, set: { var next = current; next.exclude = $0; write(next) })
    }

    private func write(_ filter: UserFilter) { interaction.setUserFilter(filter, for: key) }

    private func fetch() async {
        load = .loading
        do { load = .loaded(try await interaction.distinctValues(of: column, limit: Self.limit)) } catch { load = .failed(String(describing: error)) }
    }
}
