import AppKit
import PBIXKit
import SwiftUI

struct ReportWorkspace: View {
    @Bindable var state: DocumentState
    @State private var currentScale: Double = 1

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if !state.interaction.activeRLSRoles.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "eye.fill")
                            .foregroundStyle(Color.black.opacity(0.8))
                        Text(bi("Đang xem báo cáo dưới vai trò: \(state.interaction.activeRLSRoles.sorted().joined(separator: ", "))",
                                "Now viewing report as: \(state.interaction.activeRLSRoles.sorted().joined(separator: ", "))"))
                            .font(DS.Typeface.bodySmall.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.88))
                        Spacer()
                        Button(bi("Dừng xem", "Stop viewing")) {
                            state.setActiveRLSRoles([])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(red: 1.0, green: 0.87, blue: 0.45))
                    .hairline(.bottom)
                }
                if state.layout.isFormatPainterActive {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush.fill").foregroundStyle(DS.Palette.accent)
                        Text(bi("Chế độ Sao định dạng: bấm vào một visual đích để áp định dạng (hoặc bấm vùng trống để huỷ).",
                                "Format Painter active: click a target visual to apply formatting (or click empty canvas to cancel)."))
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.label)
                        Spacer()
                        Button(bi("Huỷ", "Cancel")) { state.layout.cancelFormatPainter() }
                            .buttonStyle(.plain)
                            .font(DS.Typeface.labelSmall.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(DS.Palette.accent.opacity(0.10))
                    .hairline(.bottom)
                }
                if let page = state.page {
                    ReportPageView(workspace: state.workspace, page: page, interaction: state.interaction, selectedVisual: $state.visualID,
                                   zoom: state.zoom, fitsWidth: state.fitsWidth, onScale: { currentScale = $0; state.renderedScale = $0 }, onViewport: { state.visibleRect = $0 },
                                   navigate: { target in
                                       // Nút điều hướng trỏ tới trang đã xoá (Desktop để nút treo, VM-D8): bấm không làm gì.
                                       guard state.pages.contains(where: { $0.id == target }) else { return }
                                       state.pageID = target; state.visualID = nil
                                   },
                                   editor: state.layout, editMode: state.editMode,
                                   onExportCSV: { visual, view in state.exportVisualToCSV(visual: visual, view: view) })
                        .id(page.id)
                        .overlay {
                            // T029: tài liệu chưa có bảng thì giữa khung trang là màn "Thêm dữ liệu vào báo cáo" (VM-F11a).
                            if AddDataPanel.isShown(for: state) { AddDataPanel(state: state) }
                            else if CanvasHint.isShown(for: state) { CanvasHint() }
                        }
                        .background {
                            Button("") { if state.canEditCanvas { state.editMode.toggle() } }
                                .keyboardShortcut("e", modifiers: .command)
                                .opacity(0)
                                .allowsHitTesting(false)
                        }
                } else {
                    ContentUnavailableView("Báo cáo không có trang", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Palette.canvasWell)
                }
                PageTabs(state: state, scale: currentScale)
            }
            panes
        }
        .onChange(of: state.visualID) { oldID, newID in
            if oldID == nil && newID != nil && state.showFilters && !state.hasSidePane {
                state.filtersCollapsed = false
            }
        }
    }

    @ViewBuilder private var panes: some View {
        if state.showPerformanceAnalyzer {
            PerformanceAnalyzerPane(state: state) { state.showPerformanceAnalyzer = false }
                .frame(width: 380).hairline(.leading)
        }
        if state.showSelection {
            SelectionPane(state: state) { state.showSelection = false }
                .frame(width: 220).hairline(.leading)
        }
        if state.showBookmarks {
            BookmarksPane(state: state) { state.showBookmarks = false }
                .frame(width: 200).hairline(.leading)
        }
        if state.showFilters {
            pane(collapsed: $state.filtersCollapsed, kind: .filters, title: tr(.paneFilters), symbol: "line.3.horizontal.decrease") {
                FiltersPane(state: state) { state.filtersCollapsed = true }
            }
        }
        if state.showVisualizations {
            pane(collapsed: $state.visualizationsCollapsed, kind: .visualizations, title: tr(.paneVisualizations), symbol: "chart.bar.xaxis") {
                VisualizationsPane(state: state) { state.visualizationsCollapsed = true }
            }
        }
        if state.showData {
            pane(collapsed: $state.dataCollapsed, kind: .data, title: tr(.paneData), symbol: "cylinder.split.1x2") {
                DataPane(state: state, purpose: .report) { state.dataCollapsed = true }
            }
        }
    }

    @ViewBuilder private func pane<Content: View>(collapsed: Binding<Bool>, kind: DocumentState.PaneKind, title: String, symbol: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        Group {
            if collapsed.wrappedValue {
                CollapsedPaneStrip(title: title, symbol: symbol) { collapsed.wrappedValue = false }
            } else {
                let width = state.paneWidth(for: kind)
                content()
                    .frame(width: width)
                    .overlay(alignment: .leading) {
                        Color.clear
                            .frame(width: 5)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        state.setPaneWidth(width - value.translation.width, for: kind)
                                    }
                            )
                    }
            }
        }
        .hairline(.leading)
    }
}

/// Thanh tab trang phía dưới canvas theo Power BI Desktop 2.159 (`UIMetrics.pageTabs` = 35 pt):
/// Desktop / Phone (vô hiệu) · ◂ ▸ · các tab trang (chữ thường, nền trắng + gạch chân `accentBrand` khi chọn, mắt gạch khi ẩn) · nút `+` vuông `accentBrand`.
struct PageTabs: View {
    @Bindable var state: DocumentState
    let scale: Double
    @Environment(\.isSnapshotRender) private var isSnapshotRender

    private struct Renaming: Identifiable {
        let id: String
        var text: String
    }

    @State private var renaming: Renaming?
    @State private var dropTarget: String?
    /// Dấu của thanh tab này: tab chỉ thả được vào chính thanh tab đã kéo nó đi.
    @State private var dragToken = UUID()
    @State private var deleting: ReportPage?

    private var blocker: String? { state.pageEditingBlocker }

    var body: some View {
        let pages = state.pages
        let currentIndex = pages.firstIndex(where: { $0.id == state.pageID }) ?? 0
        HStack(spacing: 0) {
            // Chuyển bố cục Desktop / Phone (Phone vô hiệu theo FR-008)
            HStack(spacing: 2) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.Palette.accentBrand)
                    .frame(width: 28, height: UIMetrics.pageTabs)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DS.Palette.accentBrand).frame(height: 2.5)
                    }
                    .help(bi("Bố cục máy tính", "Desktop layout"))
                    .accessibilityLabel(bi("Bố cục máy tính", "Desktop layout"))

                Button {} label: {
                    Image(systemName: "iphone")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.Palette.tertiaryLabel.opacity(0.65))
                        .frame(width: 26, height: UIMetrics.pageTabs)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help(bi("Bố cục di động: chưa hỗ trợ trên BI Pro.", "Mobile layout: not supported in BI Pro yet."))
                .accessibilityLabel(bi("Bố cục di động", "Mobile layout"))
            }
            .padding(.leading, 6)

            Rectangle().fill(DS.Palette.separator).frame(width: 1, height: 18).padding(.horizontal, 4)

            // Mũi tên chuyển trang ◂ ▸
            HStack(spacing: 0) {
                Button {
                    if currentIndex > 0 {
                        state.pageID = pages[currentIndex - 1].id
                        state.visualID = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(currentIndex > 0 ? DS.Palette.secondaryLabel : DS.Palette.tertiaryLabel.opacity(0.5))
                        .frame(width: 20, height: UIMetrics.pageTabs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentIndex <= 0)
                .help(bi("Trang trước", "Previous page"))
                .accessibilityLabel(bi("Trang trước", "Previous page"))

                Button {
                    if currentIndex + 1 < pages.count {
                        state.pageID = pages[currentIndex + 1].id
                        state.visualID = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(currentIndex + 1 < pages.count ? DS.Palette.secondaryLabel : DS.Palette.tertiaryLabel.opacity(0.5))
                        .frame(width: 20, height: UIMetrics.pageTabs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentIndex + 1 >= pages.count)
                .help(bi("Trang sau", "Next page"))
                .accessibilityLabel(bi("Trang sau", "Next page"))
            }

            if isSnapshotRender {
                tabStrip(pages: pages)
                    .clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabStrip(pages: pages)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(height: UIMetrics.pageTabs)
        .background(DS.Palette.chrome)
        .hairline(.top)
        .alert("Đổi tên trang", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(bi("Tên trang", "Page name"), text: Binding(get: { renaming?.text ?? "" }, set: { renaming?.text = $0 }))
            Button(bi("Đổi tên", "Rename")) {
                if let r = renaming { state.renamePage(r.id, to: r.text) }
                renaming = nil
            }
            Button(bi("Huỷ", "Cancel"), role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Xoá trang \"\(deleting?.displayName ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(bi("Xoá", "Delete"), role: .destructive) {
                if let page = deleting { state.removePage(page.id) }
                deleting = nil
            }
            Button(bi("Huỷ", "Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(bi("Trang và mọi visual của nó sẽ bị bỏ khi lưu. Có thể hoàn tác bằng ⌘Z.", "The page and all its visuals are removed when you save. You can undo with ⌘Z."))
        }
    }

    private func tabStrip(pages: [ReportPage]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                tab(page, index: index, count: pages.count)
            }
            Button { state.addPage() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 3).fill(blocker == nil ? DS.Palette.accentBrand : DS.Palette.tertiaryLabel.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .disabled(blocker != nil)
            .help(blocker ?? bi("Thêm trang mới", "New page"))
            .accessibilityLabel(bi("Thêm trang mới", "New page"))
        }
        .padding(.horizontal, 4)
    }

    private func tabLabel(_ page: ReportPage, selected: Bool, targeted: Bool) -> some View {
        let fill: Color = selected ? DS.Palette.canvas : (targeted ? DS.Palette.selectionSoft : .clear)
        let weight: Font.Weight = selected ? .semibold : .regular
        return HStack(spacing: 5) {
            if page.isHidden {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            Text(page.displayName)
                .font(.system(size: 12, weight: weight))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(selected ? DS.Palette.label : DS.Palette.secondaryLabel)
        .padding(.horizontal, 12)
        .frame(height: UIMetrics.pageTabs)
        .background(fill)
        .overlay(alignment: .bottom) {
            if selected {
                Rectangle().fill(DS.Palette.accentBrand).frame(height: 2.5)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(DS.Palette.separator.opacity(0.6)).frame(width: 1, height: 16)
        }
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
            guard let text = object as? NSString as String? else { return }
            Task { @MainActor in
                guard let moved = PageTabDrag.page(from: text, document: dragToken, pages: state.pages.map(\.id)),
                      let target = state.pages.firstIndex(where: { $0.id == id }) else { return }
                state.movePage(moved, to: target)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(trf(.a11yPageTabFormat, page.displayName))
            .accessibilityValue(page.isHidden ? tr(.a11yHidden) : (state.pageID == page.id ? tr(.a11ySelected) : ""))
            .accessibilityAddTraits(state.pageID == page.id ? [.isButton, .isSelected] : .isButton)
            .contextMenu {
                Button(bi("Đổi tên…", "Rename…")) { startRename(page) }.disabled(blocker != nil)
                Button(bi("Nhân bản", "Duplicate")) { state.duplicatePage(page.id) }.disabled(blocker != nil)
                Divider()
                Button(bi("Sang trái", "Move left")) { state.movePage(page.id, to: index - 1) }.disabled(blocker != nil || index == 0)
                Button(bi("Sang phải", "Move right")) { state.movePage(page.id, to: index + 1) }.disabled(blocker != nil || index == count - 1)
                Divider()
                Button(bi("Xoá…", "Delete…"), role: .destructive) { deleting = page }.disabled(blocker != nil || count <= 1)
            }
            .onDrag { NSItemProvider(object: PageTabDrag.payload(page: page.id, document: dragToken) as NSString) }
            .snapshotSafePageDrop(isSnapshot: isSnapshotRender, isTargeted: isTargeted(page.id)) { providers in drop(providers, onto: page.id) }
    }
}

private extension View {
    @ViewBuilder
    func snapshotSafePageDrop(isSnapshot: Bool, isTargeted: Binding<Bool>, perform: @escaping ([NSItemProvider]) -> Bool) -> some View {
        if isSnapshot {
            self
        } else {
            self.onDrop(of: [.plainText], isTargeted: isTargeted) { providers, _ in perform(providers) }
        }
    }
}

/// Nút Xem / Sửa ở góc trên phải canvas (⌘E đổi qua lại).
struct EditModeSwitch: View {
    @Bindable var state: DocumentState

    var body: some View {
        Picker(bi("Chế độ", "Mode"), selection: $state.editMode) {
            Text(tr(.editModeSwitchView)).tag(false)
            Text(tr(.editModeSwitchEdit)).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 120)
        .padding(10)
        .disabled(!state.canEditCanvas)
        .accessibilityLabel(tr(.menuEditMode))
        .help(state.canEditCanvas ? "Sửa bố cục: kéo, đổi cỡ visual (⌘E). Xem: lọc chéo và drill như trong Power BI."
              : "Báo cáo này chưa sửa được bố cục.")
        .background {
            Button("") { if state.canEditCanvas { state.editMode.toggle() } }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}
