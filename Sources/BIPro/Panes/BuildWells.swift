import AppKit
import PBIXKit
import SwiftUI

/// Các ô trường của Build pane cho visual đang chọn (D2). Chế độ Sửa: nhận thả trường từ pane Dữ liệu, kéo đổi thứ tự
/// và chuyển ô, nút bỏ, menu "Thêm trường", đổi tên hiển thị. Chế độ Xem hoặc không sửa được: chỉ hiển thị, kèm lý do.
/// Hợp đồng: `specs/003-d2-build-pane-field-well/contracts/field-editing.md`.
struct BuildWells: View {
    @Bindable var state: DocumentState
    let visual: ReportVisual
    @Environment(\.isSnapshotRender) private var isSnapshotRender

    private struct Renaming: Identifiable {
        let role: String
        let index: Int
        var text: String
        var id: String { "\(role)#\(index)" }
    }

    @State private var renaming: Renaming?
    @State private var targeted: String?

    private var layout: LayoutEditor { state.layout }

    /// Lý do không sửa được trường (nil: sửa được).
    private var blocker: String? {
        if !state.editMode { return bi("Bật chế độ Sửa (⌘E) để sửa trường.", "Turn on Edit mode (⌘E) to edit fields.") }
        if layout.selection.count > 1 { return bi("Đang chọn nhiều visual: chọn đúng một visual để sửa trường.", "Multiple visuals selected: select a single visual to edit fields.") }
        return layout.fieldEditingBlocker(for: visual.id)
    }

    var body: some View {
        let blocker = blocker
        let rules = WellRules.rules(for: visual)
        VStack(alignment: .leading, spacing: 0) {
            if let blocker, visual.type != "textbox" {
                Text(blocker)
                    .font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.secondaryLabel)
                    .padding(.horizontal, 10).padding(.top, 8)
            }
            if visual.type == "textbox" {
                TextboxContentEditor(layout: layout, visual: visual, editable: state.editMode && layout.selection.count <= 1)
                    .id(visual.id)
            }
            ForEach(rules, id: \.role) { rule in
                well(rule, editable: blocker == nil, rules: rules)
            }
        }
        .alert(bi("Đổi tên trường trong visual này", "Rename field for this visual"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(bi("Tên hiển thị (để trống = tên gốc)", "Display name (empty = original)"), text: Binding(get: { renaming?.text ?? "" }, set: { renaming?.text = $0 }))
            Button(bi("Đổi tên", "Rename")) {
                if let r = renaming { layout.renameField(role: r.role, index: r.index, to: r.text, visual: visual.id) }
                renaming = nil
            }
            Button(bi("Huỷ", "Cancel"), role: .cancel) { renaming = nil }
        }
    }

    private func localizedWellLabel(_ rule: WellRule) -> String {
        guard AppPreferences.shared.effectiveLanguage == .en else { return rule.label }
        switch rule.label {
        case "Trục X": return "X-axis"
        case "Trục Y": return "Y-axis"
        case "Trục Y phụ": return "Secondary y-axis"
        case "Trục Y cột": return "Column y-axis"
        case "Trục Y đường": return "Line y-axis"
        case "Chú giải": return "Legend"
        case "Chú thích công cụ": return "Tooltips"
        case "Giá trị": return "Values"
        case "Hàng": return "Rows"
        case "Cột": return "Columns"
        case "Trường": return "Field"
        case "Trường hiển thị": return "Fields"
        case "Kích thước": return "Size"
        case "Chi tiết": return "Details"
        case "Nhóm": return "Category"
        case "Đích": return "Target"
        case "Mục tiêu": return "Target"
        case "Xu hướng": return "Trend axis"
        case "Vị trí": return "Location"
        case "Vĩ độ": return "Latitude"
        case "Kinh độ": return "Longitude"
        case "Tối thiểu": return "Minimum value"
        case "Tối đa": return "Maximum value"
        case "Tâm": return "Small multiples"
        default: return rule.label
        }
    }

    // MARK: Một ô

    @ViewBuilder
    private func well(_ rule: WellRule, editable: Bool, rules: [WellRule]) -> some View {
        let fields = visual.fields.filter { $0.role == rule.role }
        let canAdd = editable && rule.status == .observed
        SectionLabel(text: localizedWellLabel(rule) + (rule.status == .unverified ? bi(" (chưa kiểm)", " (unverified)") : ""))
        VStack(spacing: 4) {
            if fields.isEmpty {
                emptySlot(rule, canAdd: canAdd)
            }
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                row(field, index: index, count: fields.count, rule: rule, editable: editable, rules: rules)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, targeted == rule.role ? 2 : 0)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(targeted == rule.role ? DS.Palette.accent.opacity(0.10) : .clear))
        .contentShape(Rectangle())
        .snapshotSafeDrop(isSnapshot: isSnapshotRender, isTargeted: Binding(get: { targeted == rule.role }, set: { targeted = $0 ? rule.role : (targeted == rule.role ? nil : targeted) })) { providers in
            handle(providers, role: rule.role, index: nil, editable: editable)
        }
    }

    @ViewBuilder
    private func emptySlot(_ rule: WellRule, canAdd: Bool) -> some View {
        let text = Text(bi("Thêm trường dữ liệu vào đây", "Add data fields here"))
            .font(.system(size: 11))
            .foregroundStyle(DS.Palette.tertiaryLabel)
            .lineLimit(1)
        Group {
            if canAdd { addMenu(rule) { text.frame(maxWidth: .infinity) } } else { text }
        }
        .frame(maxWidth: .infinity).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.canvas.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(DS.Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(Rectangle())
    }

    private func row(_ field: ReportField, index: Int, count: Int, rule: WellRule, editable: Bool, rules: [WellRule]) -> some View {
        HStack(spacing: 4) {
            Image(systemName: fieldSymbol(field))
                .font(.system(size: 10))
                .foregroundStyle(field.kind == .measure ? DS.Palette.measure : DS.Palette.secondaryLabel)
                .frame(width: 12)
            Text(title(field))
                .font(.system(size: 11.5))
                .foregroundStyle(DS.Palette.label)
                .lineLimit(1)
            Spacer(minLength: 2)
            if editable {
                if isSnapshotRender {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .frame(width: 16, height: 18)
                } else {
                    Menu {
                        fieldContextMenuItems(field: field, index: index, count: count, rule: rule, rules: rules)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                            .frame(width: 16, height: 18)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .help(bi("Tuỳ chọn trường", "Field options"))
                }

                Button { layout.removeField(role: rule.role, index: index, visual: visual.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .frame(width: 16, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(bi("Bỏ khỏi ô", "Remove from well"))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 3).fill(DS.Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(DS.Palette.separator))
        .help(field.variationColumn.map { "\(field.entity)[\($0)]" } ?? "\(field.entity)[\(field.property)]")
        .contextMenu {
            if editable {
                fieldContextMenuItems(field: field, index: index, count: count, rule: rule, rules: rules)
            }
        }
        .onDrag { NSItemProvider(object: BuildDrop.wellString(role: rule.role, index: index) as NSString) }
        .snapshotSafeDrop(isSnapshot: isSnapshotRender, isTargeted: nil) { providers in
            handle(providers, role: rule.role, index: index, editable: editable)
        }
    }

    @ViewBuilder
    private func fieldContextMenuItems(field: ReportField, index: Int, count: Int, rule: WellRule, rules: [WellRule]) -> some View {
        Button(bi("Đổi tên cho visual này…", "Rename for this visual…")) { renaming = Renaming(role: rule.role, index: index, text: field.displayName ?? "") }
        if field.kind == .aggregation {
            // Danh sách phép gộp như menu của trường trong Desktop (VM-F10), dấu tích ở phép đang dùng.
            let kind = layout.aggregationKind(entity: field.entity, property: field.property)
            Divider()
            ForEach(AggregateFunction.menu(for: kind), id: \.self) { function in
                let name = function.name(kind: kind)
                Button {
                    layout.setAggregation(role: rule.role, index: index, to: function, visual: visual.id)
                } label: {
                    if field.aggregationFunction == function.rawValue { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
        }
        if index > 0 { Button(bi("Lên", "Move up")) { layout.reorderField(role: rule.role, from: index, to: index - 1, visual: visual.id) } }
        if index < count - 1 { Button(bi("Xuống", "Move down")) { layout.reorderField(role: rule.role, from: index, to: index + 1, visual: visual.id) } }
        let targets = rules.filter { $0.role != rule.role && $0.status == .observed && WellKind(field.kind).map($0.accepts.contains) == true }
        if !targets.isEmpty {
            Menu(bi("Chuyển sang ô", "Move to well")) {
                ForEach(targets, id: \.role) { target in
                    Button(target.label) { layout.moveField(role: rule.role, index: index, to: target.role, visual: visual.id) }
                }
            }
        }
        Divider()
        Button(bi("Bỏ khỏi ô", "Remove from well"), role: .destructive) { layout.removeField(role: rule.role, index: index, visual: visual.id) }
    }

    // MARK: Thả

    /// Xử lý thứ được thả vào ô `role` (hoặc vào đúng chỗ `index` của một trường trong ô đó).
    private func handle(_ providers: [NSItemProvider], role: String, index: Int?, editable: Bool) -> Bool {
        guard editable else { layout.noteFieldRefusal(blocker ?? "Chưa sửa được trường."); return false }
        BuildDrop.load(from: providers) { drops in
            for drop in drops {
                switch drop {
                case .field(let field):
                    layout.addField(field, to: role, visual: visual.id)
                case .well(let from, let fromIndex):
                    if from == role {
                        let count = visual.fields.filter { $0.role == role }.count
                        layout.reorderField(role: role, from: fromIndex, to: min(index ?? count - 1, count - 1), visual: visual.id)
                    } else {
                        layout.moveField(role: from, index: fromIndex, to: role, visual: visual.id)
                    }
                }
            }
        }
        return true
    }

    // MARK: Menu "Thêm trường"

    @ViewBuilder
    private func addMenu<Label: View>(_ rule: WellRule, @ViewBuilder label: () -> Label) -> some View {
        if isSnapshotRender {
            label()
        } else {
            let model = state.workspace.metadata
            Menu {
                if let model {
                    ForEach(model.tables.filter { $0.isUserTable && !$0.isHidden }, id: \.name) { table in
                        let columns = rule.accepts.contains(.column) ? model.columns.filter { $0.tableName == table.name && !$0.isHidden } : []
                        let measures = rule.accepts.contains(.measure) ? model.measures.filter { $0.tableName == table.name && !$0.isHidden } : []
                        if !columns.isEmpty || !measures.isEmpty {
                            Menu(table.name) {
                                ForEach(measures, id: \.name) { m in
                                    Button(m.name) { layout.addField(FieldRef(measure: m), to: rule.role, visual: visual.id) }
                                }
                                ForEach(columns, id: \.name) { c in
                                    Button(c.name) { layout.addField(FieldRef(column: c), to: rule.role, visual: visual.id) }
                                }
                            }
                        }
                    }
                }
            } label: {
                label()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
    }

    private func title(_ field: ReportField) -> String { layout.label(of: field) }

    private func fieldSymbol(_ field: ReportField) -> String {
        switch field.kind {
        case .measure: return "function"
        case .aggregation: return "sum"
        case .hierarchyLevel: return "list.bullet.indent"
        case .column, .other:
            return state.workspace.column(table: field.entity, name: field.property).map(columnSymbol) ?? "textformat.abc"
        }
    }
}

/// Ô "Nội dung" của hộp văn bản ở Build pane (D3): mỗi dòng là một đoạn; xong chỉnh (mất tiêu điểm hoặc bấm Áp dụng) là một
/// bước hoàn tác. Chỉ sửa chữ: kiểu chữ là việc của Format pane.
struct TextboxContentEditor: View {
    let layout: LayoutEditor
    let visual: ReportVisual
    let editable: Bool

    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var current: String { LayoutEditor.paragraphTexts(of: visual.raw).joined(separator: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: bi("Nội dung", "Content"))
            TextEditor(text: $text)
                .font(DS.Typeface.bodySmall)
                .focused($focused)
                .disabled(!editable)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 160)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.canvas))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(focused ? DS.Palette.accent : DS.Palette.separator))
                .padding(.horizontal, 10)
            HStack {
                Text(editable ? bi("Mỗi dòng là một đoạn.", "Each line is a paragraph.") : bi("Bật chế độ Sửa (⌘E) để sửa nội dung.", "Turn on Edit mode (⌘E) to edit text."))
                    .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer()
                if editable && text != current { Button(bi("Áp dụng", "Apply")) { commit() }.controlSize(.small) }
            }
            .padding(.horizontal, 10)
        }
        .onAppear { if !loaded { text = current; loaded = true } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        // Bấm ra ngoài làm bỏ chọn visual: ô biến mất mà chưa kịp mất tiêu điểm thì vẫn áp nội dung đang gõ.
        .onDisappear { commit() }
        // Hoàn tác, làm lại hoặc đổi từ nơi khác: nội dung trong visual đổi thì ô theo (khi không đang gõ).
        .onChange(of: current) { _, value in if !focused { text = value } }
    }

    private func commit() {
        guard editable, text != current else { return }
        layout.setText(text, visual: visual.id)
    }
}

private extension View {
    @ViewBuilder
    func snapshotSafeDrop(isSnapshot: Bool, isTargeted: Binding<Bool>?, perform: @escaping ([NSItemProvider]) -> Bool) -> some View {
        if isSnapshot {
            self
        } else {
            self.onDrop(of: [.plainText], isTargeted: isTargeted) { providers, _ in perform(providers) }
        }
    }
}

