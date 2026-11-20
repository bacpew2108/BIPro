import AppKit
import PBIXKit
import SwiftUI

/// Các ô trường của Build pane cho visual đang chọn (D2). Chế độ Sửa: nhận thả trường từ pane Dữ liệu, kéo đổi thứ tự
/// và chuyển ô, nút bỏ, menu "Thêm trường", đổi tên hiển thị. Chế độ Xem hoặc không sửa được: chỉ hiển thị, kèm lý do.
/// Hợp đồng: `specs/003-d2-build-pane-field-well/contracts/field-editing.md`.
struct BuildWells: View {
    @Bindable var state: DocumentState
    let visual: ReportVisual

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
        if !state.editMode { return "Bật chế độ Sửa (⌘E) để sửa trường." }
        if layout.selection.count > 1 { return "Đang chọn nhiều visual: chọn đúng một visual để sửa trường." }
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
        .alert("Đổi tên trường trong visual này", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên hiển thị (để trống = tên gốc)", text: Binding(get: { renaming?.text ?? "" }, set: { renaming?.text = $0 }))
            Button("Đổi tên") {
                if let r = renaming { layout.renameField(role: r.role, index: r.index, to: r.text, visual: visual.id) }
                renaming = nil
            }
            Button("Huỷ", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Một ô

    @ViewBuilder
    private func well(_ rule: WellRule, editable: Bool, rules: [WellRule]) -> some View {
        let fields = visual.fields.filter { $0.role == rule.role }
        let canAdd = editable && rule.status == .observed
        SectionLabel(text: rule.label + (rule.status == .unverified ? " (chưa kiểm)" : ""))
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
        .onDrop(of: [.plainText], isTargeted: Binding(get: { targeted == rule.role }, set: { targeted = $0 ? rule.role : (targeted == rule.role ? nil : targeted) })) { providers, _ in
            handle(providers, role: rule.role, index: nil, editable: editable)
        }
    }

    @ViewBuilder
    private func emptySlot(_ rule: WellRule, canAdd: Bool) -> some View {
        let text = Text("+ Thêm field").font(DS.Typeface.bodySmall).foregroundStyle(DS.Palette.tertiaryLabel)
        Group {
            if canAdd { addMenu(rule) { text.frame(maxWidth: .infinity) } } else { text }
        }
        .frame(maxWidth: .infinity).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(Rectangle())
    }

    private func row(_ field: ReportField, index: Int, count: Int, rule: WellRule, editable: Bool, rules: [WellRule]) -> some View {
        ZStack(alignment: .trailing) {
            FieldChip(symbol: fieldSymbol(field), tint: field.kind == .measure ? DS.Palette.measure : DS.Palette.secondaryLabel,
                      title: title(field), subtitle: field.variationColumn.map { "\(field.entity)[\($0)]" }
                          ?? (title(field) == field.property ? field.entity : "\(field.entity)[\(field.property)]"))
            if editable {
                Button { layout.removeField(role: rule.role, index: index, visual: visual.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Palette.tertiaryLabel)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .help("Bỏ khỏi ô")
            }
        }
        .contextMenu {
            if editable {
                Button("Đổi tên cho visual này…") { renaming = Renaming(role: rule.role, index: index, text: field.displayName ?? "") }
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
                if index > 0 { Button("Lên") { layout.reorderField(role: rule.role, from: index, to: index - 1, visual: visual.id) } }
                if index < count - 1 { Button("Xuống") { layout.reorderField(role: rule.role, from: index, to: index + 1, visual: visual.id) } }
                let targets = rules.filter { $0.role != rule.role && $0.status == .observed && WellKind(field.kind).map($0.accepts.contains) == true }
                if !targets.isEmpty {
                    Menu("Chuyển sang ô") {
                        ForEach(targets, id: \.role) { target in
                            Button(target.label) { layout.moveField(role: rule.role, index: index, to: target.role, visual: visual.id) }
                        }
                    }
                }
                Divider()
                Button("Bỏ khỏi ô", role: .destructive) { layout.removeField(role: rule.role, index: index, visual: visual.id) }
            }
        }
        .onDrag { NSItemProvider(object: BuildDrop.wellString(role: rule.role, index: index) as NSString) }
        .onDrop(of: [.plainText], isTargeted: nil) { providers, _ in
            handle(providers, role: rule.role, index: index, editable: editable)
        }
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

    private func addMenu<Label: View>(_ rule: WellRule, @ViewBuilder label: () -> Label) -> some View {
        let model = state.workspace.metadata
        return Menu {
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
            SectionLabel(text: "Nội dung")
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
                Text(editable ? "Mỗi dòng là một đoạn." : "Bật chế độ Sửa (⌘E) để sửa nội dung.")
                    .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                Spacer()
                if editable && text != current { Button("Áp dụng") { commit() }.controlSize(.small) }
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

