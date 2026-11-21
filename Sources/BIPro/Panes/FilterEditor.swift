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
        // Thẻ của measure (field giá trị của visual): sửa được bằng Advanced, lọc các dòng kết quả (xem `valueFilters`).
        if let field = filter.field, field.kind == .measure { return QueryColumn(table: field.entity, column: field.property) }
        if let user = UserFilter.from(filter) { return user.column }
        guard filter.raw == .null, let field = filter.field, field.kind == .column else { return nil }
        return QueryColumn(table: field.entity, column: field.property)
    }

    /// Trạng thái hiện tại của thẻ: phần người dùng sửa, nếu không thì phần trong file.
    static func current(of filter: ReportFilter, key: UserFilterKey, interaction: ReportInteraction) -> UserFilter? {
        interaction.effectiveUserFilters[key] ?? UserFilter.from(filter)
            ?? column(of: filter).map { UserFilter(column: $0, values: [], exclude: false) }
    }

    static func isActive(_ filter: ReportFilter, key: UserFilterKey, interaction: ReportInteraction) -> Bool {
        if let edit = interaction.effectiveUserFilters[key] { return edit.isActive }
        return filter.isActive
    }

    static func summary(of filter: ReportFilter, key: UserFilterKey, interaction: ReportInteraction) -> String {
        guard let edit = interaction.effectiveUserFilters[key] ?? UserFilter.from(filter) else { return filter.summary }
        return edit.summary(format: interaction.formatString(of: edit.column))
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
    static func matching(_ values: [Value], search: String, format: String? = nil) -> [Value] {
        search.isEmpty ? values : values.filter { UserFilter.display($0, format: format).localizedCaseInsensitiveContains(search) }
    }

    /// Tập giá trị đang được đánh dấu, như Basic filtering của Power BI: không lọc = đánh dấu hết; "là" = đúng các giá trị
    /// đó; "không phải" = đánh dấu phần bù (xem VM-TODO-P.md, P1).
    static func checked(_ filter: UserFilter?, all: [Value]) -> Set<Value> {
        guard let filter, filter.isActive else { return Set(all) }
        return filter.exclude ? Set(all).subtracting(filter.values) : Set(filter.values)
    }

    /// Bộ lọc ứng với tập đánh dấu: đủ hết = không lọc; ít hơn một nửa = "là"; còn lại = "không phải" phần bỏ đánh dấu
    /// (cách Power BI lưu `year is not 9999`).
    static func filter(column: QueryColumn, checked: Set<Value>, all: [Value]) -> UserFilter {
        let universe = Set(all)
        let on = checked.intersection(universe)
        if on.count == universe.count || on.isEmpty { return UserFilter(column: column, values: [], exclude: false) }
        let off = universe.subtracting(on)
        if on.count <= off.count { return UserFilter(column: column, values: Array(on).sorted(by: FilterTranslator.valuePrecedes), exclude: false) }
        return UserFilter(column: column, values: Array(off).sorted(by: FilterTranslator.valuePrecedes), exclude: true)
    }
}

/// Thân thẻ khi mở, theo Power BI: Filter type, ô tìm kiếm, "Select all" ba trạng thái, danh sách đánh dấu, "Require single selection".
struct BasicFilterEditor: View {
    let interaction: ReportInteraction
    let key: UserFilterKey
    let filter: ReportFilter
    let column: QueryColumn

    private enum Load { case loading, failed(String), loaded([Value]) }
    @State private var load: Load = .loading
    @State private var search = ""
    /// Người dùng bỏ đánh dấu hết: không lọc gì nhưng danh sách phải hiện trống.
    @State private var cleared = false
    @State private var single = false
    private static let limit = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch load {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).frame(height: 40)
            case .failed(let message):
                Text(message).font(DS.Typeface.bodySmall).foregroundStyle(.red).lineLimit(3)
            case .loaded(let values):
                content(values)
            }
        }
        .padding(.top, 8)
        .task(id: column) { await fetch() }
    }

    @ViewBuilder private func content(_ values: [Value]) -> some View {
        let current = interaction.effectiveUserFilters[key] ?? UserFilter.from(filter)
        let format = interaction.formatString(of: column)
        let truncated = values.count >= Self.limit
        let on: Set<Value> = cleared ? [] : truncated ? Self.legacyChecked(current, values: values) : FilterEditing.checked(current, all: values)
        SearchField(text: $search, prompt: bi("Tìm kiếm", "Search"))
        let shown = FilterEditing.matching(values, search: search, format: format)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !single, search.isEmpty {
                    row(title: bi("Chọn tất cả", "Select all"), symbol: on.count == values.count ? "checkmark.square.fill" : on.isEmpty ? "square" : "minus.square.fill",
                        lit: !on.isEmpty) { toggleAll(values, on: on, truncated: truncated) }
                }
                ForEach(shown, id: \.self) { value in
                    row(title: UserFilter.display(value, format: format), symbol: on.contains(value) ? "checkmark.square.fill" : "square", lit: on.contains(value)) {
                        pick(value, values: values, on: on, current: current, truncated: truncated)
                    }
                }
                if truncated {
                    Text(bi("Chỉ hiện \(Self.limit) giá trị đầu", "Showing first \(Self.limit) values")).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel).padding(.top, 4)
                }
            }
        }
        .frame(maxHeight: 190)
        Button { single.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: single ? "checkmark.square.fill" : "square").foregroundStyle(single ? DS.Palette.accent : DS.Palette.tertiaryLabel)
                Text(bi("Chỉ cho chọn một giá trị", "Require single selection")).font(.system(size: 12))
            }
        }
        .buttonStyle(.plain)
    }

    private func row(title: String, symbol: String, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(lit ? DS.Palette.accent : DS.Palette.tertiaryLabel)
                Text(title).font(.system(size: 12)).foregroundStyle(DS.Palette.label).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleAll(_ values: [Value], on: Set<Value>, truncated: Bool) {
        if on.count == values.count {
            cleared = true
            write(UserFilter(column: column, values: [], exclude: false))
        } else {
            cleared = false
            write(UserFilter(column: column, values: [], exclude: false))
        }
    }

    private func pick(_ value: Value, values: [Value], on: Set<Value>, current: UserFilter?, truncated: Bool) {
        cleared = false
        if truncated {
            // Danh sách bị cắt nên không tính được phần bù: sửa trực tiếp tập giá trị của bộ lọc.
            write(FilterEditing.toggle(value, in: current ?? UserFilter(column: column, values: [], exclude: false)))
            return
        }
        var next = single ? [value] : on
        if !single { if next.contains(value) { next.remove(value) } else { next.insert(value) } }
        write(FilterEditing.filter(column: column, checked: next, all: values))
    }

    private static func legacyChecked(_ filter: UserFilter?, values: [Value]) -> Set<Value> {
        guard let filter, filter.isActive else { return Set(values) }
        return filter.exclude ? Set(values).subtracting(filter.values) : Set(filter.values)
    }

    private func write(_ filter: UserFilter) { interaction.setUserFilter(filter, for: key) }

    private func fetch() async {
        load = .loading
        do { load = .loaded(try await interaction.distinctValues(of: column, limit: Self.limit)) } catch { load = .failed(String(describing: error)) }
    }
}

// MARK: - Thân thẻ: chọn loại bộ lọc

/// Thân thẻ khi mở: ô "Loại bộ lọc" rồi trình sửa theo loại (Basic, Advanced, Top N).
struct FilterEditorBody: View {
    enum Mode: String, Hashable { case basic = "Basic filtering", advanced = "Advanced filtering", topN = "Top N" }

    let interaction: ReportInteraction
    let key: UserFilterKey
    let filter: ReportFilter
    let column: QueryColumn
    /// Thẻ của measure: chỉ có Advanced, so sánh số.
    var measure = false
    @State private var mode: Mode?

    private var current: UserFilter? { interaction.effectiveUserFilters[key] ?? UserFilter.from(filter) }

    private var effectiveMode: Mode {
        if measure { return .advanced }
        if let mode { return mode }
        switch current?.rule {
        case .advanced: return .advanced
        case .topN: return .topN
        case nil: return .basic
        }
    }

    /// Top N chỉ có ở bộ lọc cấp visual, như Power BI.
    private var modes: [Mode] { measure ? [.advanced] : key.level == .visual ? [.basic, .advanced, .topN] : [.basic, .advanced] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(bi("Loại bộ lọc", "Filter type")).font(.system(size: 12))
                Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryLabel)
                    .help(bi("Basic: chọn giá trị. Advanced: điều kiện chữ hoặc số. Top N: N mục đầu hoặc cuối theo một measure (chỉ cấp visual).",
                             "Basic: pick values. Advanced: text or numeric rules. Top N: top/bottom N items by a measure (visual level only)."))
            }
            Menu {
                ForEach(modes, id: \.self) { item in Button(item.rawValue) { choose(item) } }
            } label: {
                HStack { Text(effectiveMode.rawValue).font(.system(size: 12)); Spacer(); Image(systemName: "chevron.down").font(.system(size: 9)) }
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.canvas))
            }
            .menuStyle(.button).buttonStyle(.plain)
            switch effectiveMode {
            case .basic: BasicFilterEditor(interaction: interaction, key: key, filter: filter, column: column)
            case .advanced: AdvancedFilterEditor(interaction: interaction, key: key, column: column, existing: current?.rule, measure: measure)
            case .topN: TopNFilterEditor(interaction: interaction, key: key, column: column, existing: current?.rule)
            }
        }
        .padding(.top, 8)
    }

    private func choose(_ next: Mode) {
        mode = next
        // Về Basic thì bỏ điều kiện Advanced/Top N đang áp (chuyển loại không tự lọc gì khi chưa bấm Áp dụng).
        if next == .basic, current?.rule != nil { interaction.setUserFilter(UserFilter(column: column), for: key) }
    }
}

struct AdvancedFilterEditor: View {
    let interaction: ReportInteraction
    let key: UserFilterKey
    let column: QueryColumn
    let existing: FilterRule?
    var measure = false

    @State private var first = FilterCondition(kind: .contains, operand: "")
    @State private var second = FilterCondition(kind: .contains, operand: "")
    @State private var useOr = false
    @State private var loaded = false

    private var numeric: Bool { measure || interaction.isNumeric(column) }
    private var unsupported: Bool { !measure && interaction.isDate(column) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if unsupported {
                Text(bi("Advanced filter cho cột ngày chưa hỗ trợ.", "Advanced filtering for date columns is not supported yet.")).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
            } else {
                Text(bi("Hiện các mục khi giá trị", "Show items when the value")).font(.system(size: 12))
                conditionRow($first)
                HStack(spacing: 12) {
                    radio(bi("Và", "And"), on: !useOr) { useOr = false }
                    radio(bi("Hoặc", "Or"), on: useOr) { useOr = true }
                }
                conditionRow($second)
                HStack {
                    Button(bi("Áp dụng bộ lọc", "Apply filter"), action: apply)
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    if interaction.effectiveUserFilters[key]?.rule != nil {
                        Button(bi("Bỏ lọc", "Clear filter")) { interaction.setUserFilter(UserFilter(column: column, isMeasure: measure), for: key) }
                            .buttonStyle(.plain).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.accent)
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let kinds = ComparisonKind.available(numeric: numeric)
        first.kind = kinds[0]; second.kind = kinds[0]
        if case .advanced(let a, let b, let or, _)? = existing {
            first = a
            if let b { second = b }
            useOr = or
        }
    }

    private func apply() {
        guard !first.kind.needsOperand || !first.operand.isEmpty else { return }
        // Điều kiện thứ hai để trống (phép cần toán hạng mà chưa nhập) thì bỏ qua.
        let secondUsed = !second.kind.needsOperand || !second.operand.isEmpty
        let rule = FilterRule.advanced(first: first, second: secondUsed ? second : nil, useOr: useOr, numeric: numeric)
        interaction.setUserFilter(UserFilter(column: column, rule: rule, isMeasure: measure), for: key)
    }

    private func conditionRow(_ condition: Binding<FilterCondition>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(ComparisonKind.available(numeric: numeric), id: \.self) { kind in
                    Button(kind.title) { condition.wrappedValue.kind = kind }
                }
            } label: {
                HStack { Text(condition.wrappedValue.kind.title).font(.system(size: 12)); Spacer(); Image(systemName: "chevron.down").font(.system(size: 9)) }
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.canvas))
            }
            .menuStyle(.button).buttonStyle(.plain)
            if condition.wrappedValue.kind.needsOperand {
                TextField(numeric ? bi("Nhập số", "Enter number") : bi("Nhập giá trị", "Enter value"), text: condition.operand)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .onSubmit(apply)
            }
        }
    }

    private func radio(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? DS.Palette.accent : DS.Palette.tertiaryLabel)
                Text(title).font(.system(size: 12))
            }
        }
        .buttonStyle(.plain)
    }
}

struct TopNFilterEditor: View {
    let interaction: ReportInteraction
    let key: UserFilterKey
    let column: QueryColumn
    let existing: FilterRule?

    @State private var top = true
    @State private var countText = "10"
    @State private var measure: ReportInteraction.MeasureRef?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bi("Hiện các mục", "Show items")).font(.system(size: 12))
            SegmentedPill(selection: $top, options: [.init(value: true, title: "Top"), .init(value: false, title: "Bottom")], fill: true)
            TextField(bi("Số mục", "Count"), text: $countText).textFieldStyle(.roundedBorder).font(.system(size: 12))
            Text(bi("Theo giá trị", "By value")).font(.system(size: 12))
            Menu {
                ForEach(interaction.measureRefs(), id: \.self) { ref in Button("\(ref.name)  ·  \(ref.table)") { measure = ref } }
            } label: {
                HStack {
                    Text(measure?.name ?? bi("Chọn measure", "Select measure")).font(.system(size: 12)).lineLimit(1)
                    Spacer(); Image(systemName: "chevron.down").font(.system(size: 9))
                }
                .padding(.horizontal, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.canvas))
            }
            .menuStyle(.button).buttonStyle(.plain)
            HStack {
                Button(bi("Áp dụng bộ lọc", "Apply filter"), action: apply)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(measure == nil || Int(countText) == nil)
                if interaction.effectiveUserFilters[key]?.rule != nil {
                    Button(bi("Bỏ lọc", "Clear filter")) { interaction.setUserFilter(UserFilter(column: column), for: key) }
                        .buttonStyle(.plain).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.accent)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if case .topN(let rule)? = existing {
                top = rule.top; countText = String(rule.count)
                measure = .init(table: rule.measureTable, name: rule.measureName)
            }
        }
    }

    private func apply() {
        guard let measure, let count = Int(countText), count > 0 else { return }
        let rule = TopNRule(count: count, top: top, measureTable: measure.table, measureName: measure.name)
        interaction.setUserFilter(UserFilter(column: column, rule: .topN(rule)), for: key)
    }
}
