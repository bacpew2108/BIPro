import AppKit
import PBIXKit
import SwiftUI

struct ReportWorkspace: View {
    @Bindable var state: DocumentState
    @State private var currentScale: Double = 1
    @State private var filtersCollapsed = false
    @State private var visualsCollapsed = false
    @State private var dataCollapsed = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let page = state.page {
                    ReportPageView(workspace: state.workspace, page: page, interaction: state.interaction, selectedVisual: $state.visualID,
                                   zoom: state.zoom, onScale: { currentScale = $0 }, onViewport: { state.visibleRect = $0 },
                                   navigate: { state.pageID = $0; state.visualID = nil },
                                   editor: state.layout, editMode: state.editMode)
                        .id(page.id)
                        .overlay(alignment: .topTrailing) { EditModeSwitch(state: state) }
                } else {
                    ContentUnavailableView("Báo cáo không có trang", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Palette.backdrop)
                }
                PageTabs(state: state, scale: currentScale)
            }
            panes
        }
    }

    @ViewBuilder private var panes: some View {
        if state.showSelection {
            SelectionPane(state: state) { state.showSelection = false }
                .frame(width: 220).hairline(.leading)
        }
        if state.showBookmarks {
            BookmarksPane(state: state) { state.showBookmarks = false }
                .frame(width: 200).hairline(.leading)
        }
        if state.showFilters {
            pane(collapsed: $filtersCollapsed, title: "Bộ lọc", symbol: "line.3.horizontal.decrease", width: 230) {
                FiltersPane(state: state) { filtersCollapsed = true }
            }
        }
        if state.showVisualizations {
            pane(collapsed: $visualsCollapsed, title: "Trực quan hóa", symbol: "chart.bar.xaxis", width: 250) {
                VisualizationsPane(state: state) { visualsCollapsed = true }
            }
        }
        if state.showData {
            pane(collapsed: $dataCollapsed, title: "Dữ liệu", symbol: "cylinder.split.1x2", width: 250) {
                DataPane(state: state, purpose: .report) { dataCollapsed = true }
            }
        }
    }

    @ViewBuilder private func pane<Content: View>(collapsed: Binding<Bool>, title: String, symbol: String, width: CGFloat,
                                                  @ViewBuilder content: () -> Content) -> some View {
        Group {
            if collapsed.wrappedValue {
                CollapsedPaneStrip(title: title, symbol: symbol) { collapsed.wrappedValue = false }
            } else {
                content().frame(width: width)
            }
        }
        .hairline(.leading)
    }
}

/// Bottom bar: page tabs (hidden pages marked), page counter, zoom. D5: trong chế độ Sửa thêm, đổi tên, đổi thứ tự
/// (kéo tab hoặc menu), `specs/005-d5-quan-ly-trang/contracts/page-operations.md`.
struct PageTabs: View {
    @Bindable var state: DocumentState
    let scale: Double

    private struct Renaming: Identifiable {
        let id: String
        var text: String
    }

    @State private var renaming: Renaming?
    @State private var dropTarget: String?
    @State private var deleting: ReportPage?

    private var blocker: String? { state.pageEditingBlocker }

    var body: some View {
        let pages = state.pages
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        tab(page, index: index, count: pages.count)
                    }
                    Button { state.addPage() } label: { Image(systemName: "plus") }
                        .buttonStyle(GhostIconButtonStyle())
                        .disabled(blocker != nil)
                        .help(blocker ?? "Thêm trang")
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 8)
            if let message = state.layout.fieldRefusal ?? state.layout.notice {
                Text(message).font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel).lineLimit(1).help(message)
            }
            if let index = pages.firstIndex(where: { $0.id == state.pageID }) {
                Text("Trang \(index + 1) / \(pages.count)").font(DS.Typeface.label).foregroundStyle(DS.Palette.secondaryLabel)
            }
            ZoomControl(percent: Int((scale * 100).rounded()),
                        zoomOut: { state.zoom = max(0.25, (state.zoom ?? scale) - 0.1) },
                        zoomIn: { state.zoom = min(4, (state.zoom ?? scale) + 0.1) },
                        fit: { state.zoom = nil })
                .padding(.trailing, 8)
        }
        .frame(height: DS.Metrics.pageTabs)
        .background(DS.Palette.chrome)
        .hairline(.top)
        .alert("Đổi tên trang", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên trang", text: Binding(get: { renaming?.text ?? "" }, set: { renaming?.text = $0 }))
            Button("Đổi tên") {
                if let r = renaming { state.renamePage(r.id, to: r.text) }
                renaming = nil
            }
            Button("Huỷ", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Xoá trang \"\(deleting?.displayName ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                if let page = deleting { state.removePage(page.id) }
                deleting = nil
            }
            Button("Huỷ", role: .cancel) { deleting = nil }
        } message: {
            Text("Trang và mọi visual của nó sẽ bị bỏ khi lưu. Có thể hoàn tác bằng ⌘Z.")
        }
    }

    private func tabLabel(_ page: ReportPage, selected: Bool, targeted: Bool) -> some View {
        let fill: Color = selected ? .white : (targeted ? DS.Palette.accent.opacity(0.12) : .clear)
        let weight: Font.Weight = selected ? .semibold : .regular
        let shadow = Color.black.opacity(selected ? 0.08 : 0)
        return HStack(spacing: 4) {
            if page.isHidden { Image(systemName: "eye.slash").font(.system(size: 10)) }
            Text(page.displayName).font(.system(size: 12, weight: weight))
        }
        .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(fill).shadow(color: shadow, radius: 1, y: 0.5))
        .contentShape(Rectangle())
    }

    private func startRename(_ page: ReportPage) {
        if let blocker { state.layout.noteFieldRefusal(blocker) } else { renaming = Renaming(id: page.id, text: page.displayName) }
    }

    private func isTargeted(_ id: String) -> Binding<Bool> {
        Binding(get: { dropTarget == id }, set: { on in
            if on { dropTarget = id } else if dropTarget == id { dropTarget = nil }
        })
    }

    private func drop(_ providers: [NSItemProvider], onto id: String) -> Bool {
        if let blocker { state.layout.noteFieldRefusal(blocker); return false }
        _ = providers.first?.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString as String?, text.hasPrefix("page:") else { return }
            let moved = String(text.dropFirst(5))
            Task { @MainActor in
                if let target = state.pages.firstIndex(where: { $0.id == id }) { state.movePage(moved, to: target) }
            }
        }
        return true
    }

    private func tab(_ page: ReportPage, index: Int, count: Int) -> some View {
        // Không dùng Button: Button nuốt thao tác kéo (D2 R9), nên chọn bằng cử chỉ chạm.
        tabLabel(page, selected: state.pageID == page.id, targeted: dropTarget == page.id)
            .onTapGesture(count: 2) { startRename(page) }
            .onTapGesture {
                state.pageID = page.id
                state.visualID = nil
            }
            .help(page.isHidden ? "Trang ẩn khi xem báo cáo" : page.displayName)
            .contextMenu {
                Button("Đổi tên…") { startRename(page) }.disabled(blocker != nil)
                Button("Nhân bản") { state.duplicatePage(page.id) }.disabled(blocker != nil)
                Divider()
                Button("Sang trái") { state.movePage(page.id, to: index - 1) }.disabled(blocker != nil || index == 0)
                Button("Sang phải") { state.movePage(page.id, to: index + 1) }.disabled(blocker != nil || index == count - 1)
                Divider()
                Button("Xoá…", role: .destructive) { deleting = page }.disabled(blocker != nil || count <= 1)
            }
            .onDrag { NSItemProvider(object: "page:\(page.id)" as NSString) }
            .onDrop(of: [.plainText], isTargeted: isTargeted(page.id)) { providers, _ in drop(providers, onto: page.id) }
    }
}

/// Nút Xem / Sửa ở góc trên phải canvas (⌘E đổi qua lại).
struct EditModeSwitch: View {
    @Bindable var state: DocumentState

    var body: some View {
        Picker("Chế độ", selection: $state.editMode) {
            Text("Xem").tag(false)
            Text("Sửa").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 120)
        .padding(10)
        .disabled(!state.canEditLayout)
        .help(state.canEditLayout ? "Sửa bố cục: kéo, đổi cỡ visual (⌘E). Xem: lọc chéo và drill như trong Power BI."
              : "Báo cáo định dạng cũ (Report/Layout) chưa sửa được bố cục; chỉ báo cáo PBIR.")
        .background {
            Button("") { if state.canEditLayout { state.editMode.toggle() } }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}
