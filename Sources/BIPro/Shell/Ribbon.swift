import PBIXKit
import SwiftUI

/// Tab strip + command groups. Commands for later phases are shown disabled with the phase in their tooltip.
struct RibbonView: View {
    @Bindable var state: DocumentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(state.tabs) { tab in
                    let selected = state.ribbonTab == tab
                    if tab.isContextual && !(state.tabs.first?.isContextual ?? false) && tab == state.tabs.first(where: \.isContextual) {
                        Rectangle().fill(DS.Palette.separator).frame(width: 1, height: 16).padding(.horizontal, 6)
                    }
                    Button { state.ribbonTab = tab } label: {
                        Text(tab.title)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(tab.isContextual ? DS.Palette.accent : (selected ? DS.Palette.label : DS.Palette.secondaryLabel))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(selected ? Color.white : .clear)
                                .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 1, y: 0.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) { commands }
                    .padding(.horizontal, 8)
            }
            .frame(height: 88)
            .background(Color.white)
            .hairline(.top)
            .hairline(.bottom)
        }
        .background(DS.Palette.chrome)
    }

    @ViewBuilder private var commands: some View {
        switch (state.mode, state.ribbonTab) {
        case (.report, .home): ReportHomeCommands(state: state)
        case (.report, .insert): InsertCommands()
        case (_, .modeling): ModelingCommands(state: state)
        case (.report, .view): ReportViewCommands(state: state)
        case (.report, .format): FormatCommands()
        case (.report, .dataDrill): DataDrillCommands()
        case (.table, .home): DataSourceCommands()
        case (.table, .tableTools): TableToolsCommands(state: state)
        case (.table, .columnTools): ColumnToolsCommands(state: state)
        case (.model, .home): ModelHomeCommands(state: state)
        case (.model, .view): ModelViewCommands(state: state)
        case (.daxQuery, .home): DAXHomeCommands(state: state)
        case (.tmdl, .home): TMDLHomeCommands(state: state)
        case (_, .view): GenericViewCommands(state: state)
        case (_, .help): HelpCommands()
        default: EmptyView()
        }
    }
}

// MARK: - Shared groups

private struct DataSourceCommands: View {
    var body: some View {
        RibbonGroup(title: "Dữ liệu") {
            RibbonButton(title: "Lấy dữ liệu", symbol: "cylinder.split.1x2", tint: DS.Palette.accent, phase: "Phase F")
            RibbonButton(title: "Excel", symbol: "tablecells.badge.ellipsis", tint: DS.Palette.success, phase: "Phase F")
            RibbonButton(title: "SQL", symbol: "server.rack", tint: DS.Palette.indigo, phase: "Phase F")
            RibbonButton(title: "Nhập dữ liệu", symbol: "square.and.pencil", phase: "Phase F")
        }
        RibbonDivider()
        RibbonGroup(title: "Truy vấn") {
            RibbonButton(title: "Biến đổi dữ liệu", symbol: "slider.horizontal.3", phase: "Phase F")
            RibbonButton(title: "Làm mới", symbol: "arrow.clockwise", phase: "Phase F")
        }
    }
}

private struct CalculationCommands: View {
    var body: some View {
        RibbonGroup(title: "Tính toán") {
            RibbonButton(title: "Measure mới", symbol: "function", tint: DS.Palette.measure, phase: "Phase E")
            RibbonButton(title: "Measure nhanh", symbol: "bolt", tint: DS.Palette.measure, phase: "Phase E")
        }
    }
}

private struct ReportHomeCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: "Bảng nhớ tạm") {
            RibbonButton(title: "Dán", symbol: "doc.on.clipboard", phase: "Phase D")
            RibbonStack {
                RibbonButton(title: "Cắt", symbol: "scissors", size: .small, phase: "Phase D")
                RibbonButton(title: "Sao chép", symbol: "doc.on.doc", size: .small, phase: "Phase D")
                RibbonButton(title: "Sao định dạng", symbol: "paintbrush", size: .small, phase: "Phase D")
            }
        }
        RibbonDivider()
        DataSourceCommands()
        RibbonDivider()
        RibbonGroup(title: "Chèn") {
            RibbonButton(title: "Visual mới", symbol: "chart.bar.doc.horizontal", tint: DS.Palette.accent, phase: "Phase D")
            RibbonButton(title: "Hộp văn bản", symbol: "textformat", phase: "Phase D")
        }
        RibbonDivider()
        CalculationCommands()
    }
}

private struct InsertCommands: View {
    var body: some View {
        RibbonGroup(title: "Trang") {
            RibbonButton(title: "Trang mới", symbol: "doc.badge.plus", phase: "Phase D")
        }
        RibbonDivider()
        RibbonGroup(title: "Visual") {
            RibbonButton(title: "Visual mới", symbol: "chart.bar.doc.horizontal", tint: DS.Palette.accent, phase: "Phase D")
            RibbonButton(title: "Thêm visual", symbol: "square.grid.3x3", phase: "Phase D")
        }
        RibbonDivider()
        RibbonGroup(title: "Thành phần") {
            RibbonButton(title: "Hộp văn bản", symbol: "textformat", phase: "Phase D")
            RibbonButton(title: "Nút", symbol: "rectangle.and.hand.point.up.left", phase: "Phase D")
            RibbonButton(title: "Hình", symbol: "square.on.circle", phase: "Phase D")
            RibbonButton(title: "Ảnh", symbol: "photo", phase: "Phase D")
        }
    }
}

private struct ModelingCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: "Quan hệ") {
            RibbonButton(title: "Quản lý quan hệ", symbol: "point.3.connected.trianglepath.dotted", tint: DS.Palette.accent,
                         isOn: state.mode == .model) { state.mode = .model }
        }
        RibbonDivider()
        RibbonGroup(title: "Tính toán") {
            RibbonButton(title: "Measure mới", symbol: "function", tint: DS.Palette.measure, phase: "Phase E")
            RibbonButton(title: "Cột mới", symbol: "rectangle.split.3x1", phase: "Phase E")
            RibbonButton(title: "Bảng mới", symbol: "tablecells.badge.ellipsis", phase: "Phase E")
        }
        RibbonDivider()
        RibbonGroup(title: "Bảo mật") {
            RibbonButton(title: "Quản lý vai trò", symbol: "person.badge.shield.checkmark", phase: "sau v1")
            RibbonButton(title: "Xem dưới vai trò", symbol: "eye", phase: "sau v1")
        }
    }
}

private struct HelpCommands: View {
    @State private var showAbout = false
    var body: some View {
        RibbonGroup(title: "Trợ giúp") {
            RibbonButton(title: "Giới thiệu", symbol: "info.circle", tint: DS.Palette.accent) { showAbout = true }
        }
        .popover(isPresented: $showAbout) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BI Pro").font(DS.Typeface.headlineLarge)
                Text("Phiên bản 0.2 · Phase A (shell và design system)").font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel)
                Text("Mở .pbix (PBIR và Layout cũ), giải mã VertiPaq trên macOS.").font(DS.Typeface.bodySmall)
            }
            .padding(16)
        }
    }
}

private struct GenericViewCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: "Không gian làm việc") {
            ForEach(WorkspaceMode.allCases) { mode in
                RibbonButton(title: mode.title, symbol: mode.symbol, isOn: state.mode == mode) { state.mode = mode }
            }
        }
    }
}

// MARK: - Report

private struct ReportViewCommands: View {
    @Bindable var state: DocumentState
    var body: some View {
        RibbonGroup(title: "Ngăn") {
            RibbonButton(title: "Bộ lọc", symbol: "line.3.horizontal.decrease", isOn: state.showFilters) { state.showFilters.toggle() }
            RibbonButton(title: "Trực quan hóa", symbol: "chart.bar", isOn: state.showVisualizations) { state.showVisualizations.toggle() }
            RibbonButton(title: "Dữ liệu", symbol: "cylinder", isOn: state.showData) { state.showData.toggle() }
            RibbonButton(title: "Lựa chọn", symbol: "square.3.layers.3d", isOn: state.showSelection) { state.showSelection.toggle() }
            RibbonButton(title: "Bookmark", symbol: "bookmark", isOn: state.showBookmarks) { state.showBookmarks.toggle() }
        }
        RibbonDivider()
        RibbonGroup(title: "Thu phóng") {
            RibbonButton(title: "Vừa trang", symbol: "arrow.up.left.and.arrow.down.right", isOn: state.zoom == nil) { state.zoom = nil }
            RibbonButton(title: "100%", symbol: "1.magnifyingglass", isOn: state.zoom == 1) { state.zoom = 1 }
            RibbonStack {
                RibbonButton(title: "Phóng to", symbol: "plus.magnifyingglass", size: .small) { state.zoomIn() }
                RibbonButton(title: "Thu nhỏ", symbol: "minus.magnifyingglass", size: .small) { state.zoomOut() }
            }
        }
    }
}

private struct FormatCommands: View {
    var body: some View {
        RibbonGroup(title: "Tương tác") {
            RibbonButton(title: "Sửa tương tác", symbol: "arrow.triangle.branch", phase: "Phase C")
        }
        RibbonDivider()
        RibbonGroup(title: "Sắp xếp") {
            RibbonButton(title: "Đưa lên trước", symbol: "square.2.layers.3d.top.filled", phase: "Phase D")
            RibbonButton(title: "Đưa ra sau", symbol: "square.2.layers.3d.bottom.filled", phase: "Phase D")
            RibbonButton(title: "Căn chỉnh", symbol: "align.horizontal.left", phase: "Phase D")
        }
    }
}

private struct DataDrillCommands: View {
    var body: some View {
        RibbonGroup(title: "Truy sâu") {
            RibbonButton(title: "Lên một cấp", symbol: "arrow.up", phase: "Phase C")
            RibbonButton(title: "Xuống một cấp", symbol: "arrow.down", phase: "Phase C")
            RibbonButton(title: "Mở rộng cấp", symbol: "arrow.down.right.and.arrow.up.left", phase: "Phase C")
        }
        RibbonDivider()
        RibbonGroup(title: "Dữ liệu") {
            RibbonButton(title: "Xem dữ liệu", symbol: "tablecells", phase: "Phase C")
        }
    }
}

// MARK: - Table

private struct TableToolsCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: "Cấu trúc") {
            VStack(alignment: .leading, spacing: 3) {
                Text("TÊN").font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                Text(state.table ?? "—").font(DS.Typeface.body).padding(.horizontal, 8).frame(width: 160, height: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
            }
        }
        RibbonDivider()
        RibbonGroup(title: "Lịch") {
            RibbonButton(title: "Đánh dấu bảng ngày", symbol: "calendar", phase: "Phase E")
        }
        RibbonDivider()
        RibbonGroup(title: "Quan hệ") {
            RibbonButton(title: "Quản lý quan hệ", symbol: "point.3.connected.trianglepath.dotted", tint: DS.Palette.accent) { state.mode = .model }
        }
        RibbonDivider()
        RibbonGroup(title: "Tính toán") {
            RibbonButton(title: "Measure mới", symbol: "function", tint: DS.Palette.measure, phase: "Phase E")
            RibbonButton(title: "Cột mới", symbol: "rectangle.split.3x1", phase: "Phase E")
            RibbonButton(title: "Bảng mới", symbol: "tablecells.badge.ellipsis", phase: "Phase E")
        }
    }
}

private struct ColumnToolsCommands: View {
    let state: DocumentState

    var body: some View {
        let column = state.table.flatMap { t in state.column.flatMap { state.workspace.column(table: t, name: $0) } }
        RibbonGroup(title: "Cấu trúc") {
            field("TÊN", column?.name ?? "Chọn một cột", width: 150)
            field("KIỂU DỮ LIỆU", column.map { dataTypeName($0.dataType) } ?? "—", width: 110)
        }
        RibbonDivider()
        RibbonGroup(title: "Định dạng") {
            field("ĐỊNH DẠNG", column?.formatString ?? "Chung", width: 130)
            HStack(spacing: 2) {
                ForEach(["$", "%", ",", ".00"], id: \.self) { symbol in
                    Text(symbol).font(DS.Typeface.label).frame(width: 26, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(DS.Palette.chrome))
                }
            }
            .opacity(0.45)
            .help("Đổi định dạng: Phase E")
        }
        RibbonDivider()
        RibbonGroup(title: "Thuộc tính") {
            field("TÓM TẮT", column.map { summarizeName($0) } ?? "—", width: 110)
            field("DANH MỤC", column?.dataCategory ?? "Chưa phân loại", width: 120)
        }
        RibbonDivider()
        RibbonGroup(title: "Sắp xếp") {
            let sortBy = column?.sortByColumnID.flatMap { state.workspace.metadata?.column(id: $0)?.name }
            field("SẮP XẾP THEO CỘT", sortBy ?? column?.name ?? "—", width: 140)
        }
        RibbonDivider()
        RibbonGroup(title: "Quan hệ") {
            RibbonButton(title: "Quản lý quan hệ", symbol: "point.3.connected.trianglepath.dotted", tint: DS.Palette.accent) { state.mode = .model }
        }
        RibbonDivider()
        RibbonGroup(title: "Tính toán") {
            RibbonButton(title: "Measure mới", symbol: "function", tint: DS.Palette.measure, phase: "Phase E")
            RibbonButton(title: "Cột mới", symbol: "rectangle.split.3x1", phase: "Phase E")
        }
    }

    private func field(_ label: String, _ value: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
            HStack {
                Text(value).font(DS.Typeface.bodySmall).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: 24)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.chrome))
        }
        .help("Chỉnh sửa có ở Phase E")
    }
}

func dataTypeName(_ type: ModelMetadata.DataType) -> String {
    switch type {
    case .string: "Văn bản"
    case .int64: "Số nguyên"
    case .double: "Số thập phân"
    case .decimal: "Số thập phân cố định"
    case .dateTime: "Ngày/giờ"
    case .boolean: "True/False"
    case .binary: "Nhị phân"
    default: "Tự động"
    }
}

func summarizeName(_ column: ModelMetadata.Column) -> String {
    switch column.summarizeBy {
    case 2: "Không tóm tắt"
    case 3: "Tổng"
    case 4: "Nhỏ nhất"
    case 5: "Lớn nhất"
    case 6: "Đếm"
    case 7: "Trung bình"
    case 8: "Đếm phân biệt"
    default: "Mặc định"
    }
}

// MARK: - Model

private struct ModelHomeCommands: View {
    let state: DocumentState
    var body: some View {
        DataSourceCommands()
        RibbonDivider()
        ModelingCommands(state: state)
    }
}

private struct ModelViewCommands: View {
    @Bindable var state: DocumentState
    var body: some View {
        RibbonGroup(title: "Bố cục") {
            RibbonButton(title: "Sắp xếp lại", symbol: "wand.and.stars") { state.layoutRevision += 1 }
            RibbonButton(title: "Vừa màn hình", symbol: "arrow.up.left.and.arrow.down.right") { state.modelZoom = 0.6 }
        }
        RibbonDivider()
        RibbonGroup(title: "Thu phóng") {
            RibbonButton(title: "Phóng to", symbol: "plus.magnifyingglass") { state.modelZoom = min(2, state.modelZoom + 0.1) }
            RibbonButton(title: "Thu nhỏ", symbol: "minus.magnifyingglass") { state.modelZoom = max(0.3, state.modelZoom - 0.1) }
        }
    }
}

// MARK: - DAX / TMDL

private struct DAXHomeCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: "Truy vấn") {
            if state.isRunningDAX {
                RibbonButton(title: "Huỷ", symbol: "stop.fill", tint: DS.Palette.danger) { state.cancelDAXQuery() }
            } else if state.canRunDAX {
                RibbonButton(title: "Chạy", symbol: "play.fill", tint: DS.Palette.accent) { state.runDAXQuery() }
            } else {
                RibbonButton(title: "Chạy", symbol: "play.fill", tint: DS.Palette.accent, phase: "cần mô hình dữ liệu")
            }
            RibbonButton(title: "Định dạng", symbol: "text.alignleft", phase: "UI4")
            RibbonButton(title: "Truy vấn mới", symbol: "plus.rectangle.on.rectangle", tint: DS.Palette.accent) {
                state.daxQueries.append(DAXQueryTab(title: "Truy vấn \(state.daxQueries.count + 1)", text: "EVALUATE\n"))
                state.daxSelection = state.daxQueries.count - 1
            }
        }
        RibbonDivider()
        RibbonGroup(title: "Mô hình") {
            RibbonButton(title: "Cập nhật mô hình", symbol: "arrow.triangle.2.circlepath", phase: "Phase E")
        }
    }
}

private struct TMDLHomeCommands: View {
    let state: DocumentState
    var body: some View {
        RibbonGroup(title: "Tài liệu") {
            RibbonButton(title: "Sao chép", symbol: "doc.on.doc", tint: DS.Palette.accent) {
                if let doc = state.workspace.tmdlDocuments.first(where: { $0.path == state.tmdlPath }) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(doc.text, forType: .string)
                }
            }
            RibbonButton(title: "Xuất thư mục TMDL…", symbol: "folder.badge.plus", tint: DS.Palette.accent) { exportTMDL() }
        }
        RibbonDivider()
        RibbonGroup(title: "Áp dụng") {
            RibbonButton(title: "Áp dụng thay đổi", symbol: "checkmark.circle", phase: "Phase E")
        }
    }

    private func exportTMDL() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Xuất vào đây"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let root = folder.appendingPathComponent("definition", isDirectory: true)
        for doc in state.workspace.tmdlDocuments {
            let url = root.appendingPathComponent(doc.path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? doc.text.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}
