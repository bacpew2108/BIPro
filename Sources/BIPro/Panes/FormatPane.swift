import PBIXKit
import SwiftUI

/// Format pane sửa được (D4): `specs/006-d4-format-pane/`. Thẻ và thuộc tính lấy từ `FormatCatalog`; mỗi lần sửa đi qua
/// `DocumentState.setFormat/resetFormat` thành một bước hoàn tác.
struct FormatPane: View {
    @Bindable var state: DocumentState
    @State private var scope: FormatScope = .objects

    var body: some View {
        if let visual = state.visual, let format = state.formatState {
            let blocker = state.formatEditingBlocker
            VStack(spacing: 8) {
                SegmentedPill(selection: $scope, options: [
                    .init(value: .objects, title: "Visual"),
                    .init(value: .container, title: "Chung"),
                ], fill: true)
                FieldMessages(layout: state.layout)
                if let blocker {
                    Text(blocker).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let cards = (scope == .objects ? format.objects : format.container)
                if scope == .objects, cards.isEmpty {
                    Text("Loại visual này chưa có thẻ định dạng đã quan sát.")
                        .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).padding(.top, 4)
                } else if scope == .objects, needsFields(visual) {
                    Text("Thêm trường vào visual để bắt đầu định dạng.")
                        .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).padding(.top, 4)
                } else {
                    ForEach(cards, id: \.card.objectKey) { cardState in
                        FormatCardView(state: state, cardState: cardState, blocker: blocker)
                    }
                }
                let readOnly = format.readOnly.filter { $0.scope == scope }
                if !readOnly.isEmpty { ReadOnlySection(items: readOnly) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        } else {
            Text("Chọn một visual để xem định dạng của nó.")
                .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel).padding(12)
        }
    }

    /// Visual loại có ô trường mà chưa có trường nào: Desktop không hiện thẻ nào (VM-D4 mục 5).
    private func needsFields(_ visual: ReportVisual) -> Bool {
        !WellRules.rules(for: visual).isEmpty && visual.fields.isEmpty
    }
}

/// Một thẻ: tiêu đề (kèm công tắc đầu thẻ), các hàng thuộc tính, nút Đặt lại.
private struct FormatCardView: View {
    @Bindable var state: DocumentState
    let cardState: FormatCardState
    let blocker: String?
    @State private var open = false
    /// `queryRef` của chuỗi đang chọn ở "Áp dụng cho"; nil là Tất cả (mục chung).
    @State private var series: String?

    private var card: FormatCard { cardState.card }
    private var disabled: Bool { blocker != nil || !cardState.isEditable }
    private var selectedSeries: FormatSeriesState? { series.flatMap { ref in cardState.series.first { $0.queryRef == ref } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { open.toggle() } label: {
                    HStack {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Palette.tertiaryLabel).frame(width: 10)
                        Text(card.title).font(DS.Typeface.headlineSmall).foregroundStyle(DS.Palette.label)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let toggle = card.cardSwitch { switchView(toggle) }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            if open {
                VStack(spacing: 0) {
                    if !card.seriesProperties.isEmpty { seriesPicker }
                    if let selected = selectedSeries {
                        // Mục riêng của một chuỗi (`selector.metadata`, VM-D8 mục 6).
                        ForEach(card.seriesProperties, id: \.key) { property in
                            FormatRow(state: state, card: card, property: property, value: selected.values[property.key],
                                      disabled: blocker != nil || selected.blocker != nil, help: blocker ?? selected.blocker, series: selected.queryRef)
                        }
                        if let reason = selected.blocker {
                            Text(reason).font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                        }
                    } else {
                        ForEach(card.properties.filter { !$0.isCardSwitch }, id: \.key) { property in
                            FormatRow(state: state, card: card, property: property, value: cardState.values[property.key], disabled: disabled, help: rowHelp)
                                .opacity(switchIsOff ? 0.5 : 1)   // công tắc thẻ tắt: mờ nhưng giữ nguyên giá trị (US2/AC4)
                        }
                    }
                    if cardState.isPresent {
                        HStack {
                            Button { state.resetFormat(scope: card.scope, object: card.objectKey) } label: {
                                Label("Đặt lại", systemImage: "arrow.counterclockwise").font(DS.Typeface.bodySmall)
                            }
                            .buttonStyle(.plain).foregroundStyle(disabled ? DS.Palette.tertiaryLabel : DS.Palette.accent)
                            .disabled(disabled)
                            .help(blocker ?? "Bỏ định dạng riêng của thẻ này, về mặc định")
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    if !cardState.isEditable {
                        Text("Thẻ này có định dạng riêng theo trường hoặc điểm dữ liệu, chưa sửa được.")
                            .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(DS.Palette.separator))
    }

    /// "Áp dụng cho": Tất cả hoặc một chuỗi, như ô "Apply settings to" của Desktop. Màu chỉ đặt được khi chọn một chuỗi.
    @ViewBuilder private var seriesPicker: some View {
        if cardState.series.isEmpty {
            Text("Màu theo chuỗi: chưa có measure để chọn, hoặc biểu đồ có trường ở ô Chú giải mà file chưa có màu riêng cho giá trị nào (chưa thêm được).")
                .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
        } else {
            HStack {
                Text("Áp dụng cho").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                Spacer(minLength: 8)
                Picker("", selection: Binding(get: { selectedSeries?.queryRef ?? "" }, set: { series = $0.isEmpty ? nil : $0 })) {
                    Text("Tất cả").tag("")
                    ForEach(cardState.series, id: \.queryRef) { Text($0.title).tag($0.queryRef) }
                }
                .labelsHidden().frame(maxWidth: 150)
            }
            .frame(minHeight: 26)
            if selectedSeries == nil {
                Text("Chọn một chuỗi để đổi màu.").font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Công tắc đầu thẻ đang tắt (theo file, hoặc theo mặc định đã quan sát khi file chưa có).
    private var switchIsOff: Bool {
        guard let toggle = card.cardSwitch else { return false }
        if case .bool(let on)? = cardState.values[toggle.key] { return !on }
        return toggle.defaultOn == false
    }

    private var rowHelp: String? { blocker ?? (cardState.isEditable ? nil : "Thẻ này có định dạng riêng theo trường") }

    @ViewBuilder private func switchView(_ property: FormatProperty) -> some View {
        let current = cardState.values[property.key]
        let on: Bool = { if case .bool(let v)? = current { return v } else { return property.defaultOn ?? false } }()
        Toggle("", isOn: Binding(get: { on }, set: { state.setFormat(.bool($0), scope: card.scope, object: card.objectKey, property: property.key) }))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            .disabled(disabled)
            .help(blocker ?? (current == nil && property.defaultOn == nil ? "Chưa biết giá trị mặc định của Power BI" : property.title))
    }
}

/// Một hàng thuộc tính với điều khiển hợp kiểu.
private struct FormatRow: View {
    @Bindable var state: DocumentState
    let card: FormatCard
    let property: FormatProperty
    let value: FormatValue?
    let disabled: Bool
    let help: String?
    /// `queryRef` của chuỗi khi hàng này sửa mục riêng của một chuỗi.
    var series: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(property.title).font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                Spacer(minLength: 8)
                control.disabled(disabled || isUnsupported)
            }
            .frame(minHeight: 26)
            if case .unsupported(let reason)? = value {
                Text("Chỉ đọc: \(reason).").font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
            }
            if !property.rendered {
                Text("BI Pro chưa vẽ thuộc tính này; Power BI Desktop vẫn vẽ.")
                    .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
            }
        }
        .help(unsupportedReason.map { "Chỉ đọc: \($0)" } ?? help ?? property.title)
    }

    private var unsupportedReason: String? { if case .unsupported(let reason)? = value { return reason } else { return nil } }

    private var isUnsupported: Bool { if case .unsupported? = value { return true } else { return false } }

    @discardableResult
    private func commit(_ new: FormatValue) -> String? {
        state.setFormat(new, scope: card.scope, object: card.objectKey, property: property.key, series: series)
    }

    @ViewBuilder private var control: some View {
        switch property.kind {
        case .bool:
            let on: Bool = { if case .bool(let v)? = value { return v } else { return property.defaultOn ?? false } }()
            Toggle("", isOn: Binding(get: { on }, set: { commit(.bool($0)) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
        case .number(let min, let max, let step, let tail):
            NumberControl(value: { if case .number(let n, _)? = value { return n } else { return nil } }(),
                          min: min, max: max, step: step, unsupported: isUnsupported) { commit(.number($0, tail: tail)) }
        case .choice(let options):
            let current: String? = { if case .choice(let c)? = value { return c } else { return nil } }()
            Picker("", selection: Binding(get: { current ?? "" }, set: { if !$0.isEmpty { commit(.choice($0)) } })) {
                if current == nil || !options.contains(where: { $0.literal == current }) {
                    Text(current == nil ? "Mặc định" : "Giá trị khác").tag(current ?? "")
                }
                ForEach(options, id: \.literal) { Text($0.title).tag($0.literal) }
            }
            .labelsHidden().frame(maxWidth: 130)
        case .color:
            ColorControl(theme: state.workspace.theme, value: value, onSet: { commit(.color($0)) },
                         onReset: { state.resetFormat(scope: card.scope, object: card.objectKey, property: property.key, series: series) })
        case .text(let maxLength, let allowsEmpty):
            TextControl(value: { if case .text(let t)? = value { return t } else { return nil } }(), maxLength: maxLength, allowsEmpty: allowsEmpty) {
                commit(.text($0))
            }
        }
    }
}

/// Ô số: gõ rồi Enter, hoặc mũi tên. Giá trị sai được đẩy lên `setFormat` để hiện đúng lý do.
private struct NumberControl: View {
    let value: Double?
    let min: Double
    let max: Double
    let step: Double
    let unsupported: Bool
    /// Trả lý do từ chối hoặc nil.
    let commit: (Double) -> String?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField(unsupported ? "—" : "Mặc định", text: $text)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 70)
                .focused($focused)
                .onSubmit { submit() }
                .onChange(of: focused) { _, isFocused in if !isFocused { submit() } }
            Stepper("", onIncrement: { bump(step) }, onDecrement: { bump(-step) }).labelsHidden()
        }
        .onAppear { sync() }
        .onChange(of: value) { _, _ in sync() }
    }

    private func sync() { text = value.map(FormatValue.format) ?? "" }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty { sync(); return }
        let typed = Double(trimmed)
        // Giá trị mới về tới ô qua `onChange(of: value)`; chỉ trả lại giá trị cũ khi bị từ chối hoặc không đổi.
        if commit(typed ?? .nan) != nil || typed == value { sync() }
    }

    private func bump(_ delta: Double) {
        let base = value ?? Swift.max(min, 0)
        _ = commit(Swift.min(max, Swift.max(min, base + delta)))
    }
}

private struct TextControl: View {
    let value: String?
    let maxLength: Int
    let allowsEmpty: Bool
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Mặc định", text: $text)
            .textFieldStyle(.roundedBorder).frame(width: 130)
            .focused($focused)
            .onSubmit { commit(text) }
            .onChange(of: focused) { _, isFocused in if !isFocused, text != (value ?? "") { commit(text) } }
            .onAppear { text = value ?? "" }
            .onChange(of: value) { _, new in if !focused { text = new ?? "" } }
    }
}

/// Ô màu: swatch mở popover có hàng màu theme gốc, ô hex và "Đặt lại" (R11).
private struct ColorControl: View {
    let theme: ReportTheme
    let value: FormatValue?
    let onSet: (FormatColor) -> Void
    let onReset: () -> Void
    @State private var open = false
    @State private var hex = ""
    /// `Percent` của từng hàng lưới màu theme của Desktop (VM-D4 vòng 2).
    private static let percents: [Double] = [0, 0.6, 0.4, 0.2, -0.25, -0.5]

    private var swatch: Color? {
        guard case .color(let color)? = value else { return nil }
        switch color {
        case .hex(let text): return Color(hex: text)
        case .theme(let id, let percent): return theme.color(.themeColor(id: id, percent: percent))
        }
    }

    private var label: String {
        switch value {
        case .color(.hex(let text))?: text.uppercased()
        case .color(.theme(let id, let percent))?: "Theme \(id)" + (percent == 0 ? "" : " \(Int(percent * 100))%")
        case .unsupported?: "Theo công thức"
        default: "Mặc định"
        }
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(swatch ?? Color.clear).frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.15)))
                Text(label).font(DS.Typeface.mono).foregroundStyle(DS.Palette.secondaryLabel)
            }
            .padding(.horizontal, 6).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.chrome))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { picker }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Màu theme").font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
            // Lưới như Desktop: hàng gốc rồi 5 biến thể sáng đến tối (`Percent` đo ở VM-D4 vòng 2).
            VStack(spacing: 3) {
                ForEach(Self.percents, id: \.self) { percent in
                    HStack(spacing: 3) {
                        ForEach(0..<10, id: \.self) { id in
                            Button { onSet(.theme(id: id, percent: percent)); open = false } label: {
                                RoundedRectangle(cornerRadius: 3).fill(theme.color(.themeColor(id: id, percent: percent)) ?? .gray)
                                    .frame(width: 18, height: 18)
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .help("Theme \(id)" + (percent == 0 ? "" : " \(Int(percent * 100))%"))
                        }
                    }
                }
            }
            Text("Màu tự chọn (#RRGGBB)").font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
            HStack {
                TextField("#RRGGBB", text: $hex).textFieldStyle(.roundedBorder).frame(width: 100).font(DS.Typeface.mono)
                    .onSubmit { apply() }
                Button("Áp dụng") { apply() }.disabled(FormatValue.normalisedHex(hex) == nil)
            }
            Divider()
            Button { onReset(); open = false } label: { Label("Đặt lại về mặc định", systemImage: "arrow.counterclockwise") }
                .buttonStyle(.plain).foregroundStyle(DS.Palette.accent)
        }
        .padding(12)
        .onAppear { if case .color(.hex(let text))? = value { hex = text } }
    }

    private func apply() {
        guard FormatValue.normalisedHex(hex) != nil else { return }
        onSet(.hex(hex)); open = false
    }
}

/// Khoá và thuộc tính ngoài danh mục hoặc có định dạng riêng theo trường: hiện để người dùng biết, không sửa.
private struct ReadOnlySection: View {
    let items: [FormatReadOnlyItem]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { open.toggle() } label: {
                HStack {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    Text("Khác (chỉ đọc, \(items.count))").font(DS.Typeface.headlineSmall)
                    Spacer()
                }
                .foregroundStyle(DS.Palette.secondaryLabel)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(FormatNames.object(item.object) + (item.property.map { " · " + FormatNames.property($0) } ?? ""))
                            .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                        Text(item.reason).font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(DS.Palette.chrome))
    }
}
