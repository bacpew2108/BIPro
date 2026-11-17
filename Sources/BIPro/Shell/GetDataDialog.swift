import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ColumnStore
import Connectors

enum GetDataFilePicker {
    static func pick(_ kind: SourceKind) -> String? {
        MainActor.assumeIsolated {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            switch kind {
            case .excel:
                panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
            case .csv:
                panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
            case .json:
                panel.allowedContentTypes = [.json]
            case .parquet:
                if let ct = UTType(filenameExtension: "parquet") {
                    panel.allowedContentTypes = [ct]
                }
            case .sqlite:
                panel.allowedContentTypes = [
                    UTType(filenameExtension: "sqlite"),
                    UTType(filenameExtension: "db")
                ].compactMap { $0 }
            case .postgres:
                break
            }
            let response = panel.runModal()
            return response == .OK ? panel.url?.path : nil
        }
    }
}

struct GetDataDialogView: View {
    let state: NavigatorState
    var pickFile: (SourceKind) -> String? = GetDataFilePicker.pick
    var onClose: () -> Void = {}
    var scrollable: Bool = true

    @State private var selectedCategory: ConnectorCategory = .all
    @State private var searchText: String = ""
    @State private var selectedKind: SourceKind = .excel

    private var visibleEntries: [ConnectorEntry] {
        ConnectorCatalog.visible(category: selectedCategory, query: searchText)
    }

    private var isConnectEnabled: Bool {
        guard let entry = ConnectorCatalog.entries.first(where: { $0.kind == selectedKind }) else {
            return false
        }
        return entry.isAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .hairline(.bottom)

            HStack(spacing: 0) {
                categorySidebar
                    .frame(width: 200)
                    .hairline(.trailing)

                catalogContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 480)

            footerBar
                .hairline(.top)
        }
        .frame(width: 840, height: 580)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Palette.separator, lineWidth: 1))
    }

    // MARK: - Header (52 pt)

    private var headerBar: some View {
        HStack(spacing: 12) {
            // macOS traffic lights
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#FF5F57")!).frame(width: 12, height: 12)
                Circle().fill(Color(hex: "#FEBC2E")!).frame(width: 12, height: 12)
                Circle().fill(Color(hex: "#28C840")!).frame(width: 12, height: 12)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Lấy dữ liệu")
                    .font(DS.Typeface.headlineMedium)
                    .foregroundStyle(DS.Palette.label)

                Text("Chọn nguồn dữ liệu")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .padding(.leading, 4)

            Spacer()

            if scrollable {
                SearchField(text: $searchText, prompt: "Tìm trình kết nối", shortcut: "⌘F")
                    .frame(width: 240)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(DS.Palette.tertiaryLabel)
                    Text("Tìm trình kết nối")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                    Spacer()
                    Text("⌘F").font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.tertiaryLabel)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.badge).fill(Color.white.opacity(0.8)))
                }
                .padding(.horizontal, 8)
                .frame(width: 240, height: 28)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.searchFill))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(DS.Palette.chrome)
    }

    // MARK: - Left Categories Sidebar (200 pt)

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DANH MỤC")
                .font(DS.Typeface.labelSmall)
                .tracking(0.5)
                .foregroundStyle(DS.Palette.tertiaryLabel)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(ConnectorCategory.allCases, id: \.self) { category in
                categoryRow(category)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .background(DS.Palette.chrome.opacity(0.6))
    }

    private func categoryRow(_ category: ConnectorCategory) -> some View {
        let isSelected = category == selectedCategory
        let count = ConnectorCatalog.count(for: category, query: searchText)

        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 8) {
                categoryIcon(category)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : DS.Palette.secondaryLabel)
                    .frame(width: 18)

                Text(categoryTitle(category))
                    .font(DS.Typeface.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : DS.Palette.label)

                Spacer()

                Text("\(count)")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(isSelected ? .white : DS.Palette.tertiaryLabel)
                    .padding(.horizontal, isSelected ? 6 : 0)
                    .padding(.vertical, isSelected ? 1 : 0)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.white.opacity(0.25))
                        }
                    }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .fill(DS.Palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryTitle(_ category: ConnectorCategory) -> String {
        switch category {
        case .all: return "Tất cả"
        case .file: return "Tệp"
        case .database: return "Cơ sở dữ liệu"
        }
    }

    @ViewBuilder
    private func categoryIcon(_ category: ConnectorCategory) -> some View {
        switch category {
        case .all: Image(systemName: "square.grid.2x2")
        case .file: Image(systemName: "folder")
        case .database: Image(systemName: "cylinder.split.1x2")
        }
    }


    // MARK: - Right Catalog Content (640 pt)

    private var catalogContent: some View {
        VStack(spacing: 0) {
            catalogSubheader
                .hairline(.bottom)

            if scrollable {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(visibleEntries) { entry in
                            connectorRow(entry)
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(visibleEntries) { entry in
                        connectorRow(entry)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .clipped()
            }
        }
        .background(Color.white)
    }

    private var catalogSubheader: some View {
        HStack {
            HStack(spacing: 4) {
                Text(categoryTitle(selectedCategory))
                    .font(DS.Typeface.headlineSmall)
                    .foregroundStyle(DS.Palette.label)
                Text("/")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                Text("Hiển thị \(visibleEntries.count) nguồn")
                    .font(DS.Typeface.labelSmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color.white)
    }

    private func connectorRow(_ entry: ConnectorEntry) -> some View {
        let isSelected = entry.kind == selectedKind

        return HStack(spacing: 12) {
            connectorIcon(for: entry.kind)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(DS.Typeface.headlineSmall)
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)

                    if entry.isDefault {
                        Badge(text: "Mặc định", color: DS.Palette.accent)
                    }

                    if !entry.isAvailable {
                        Badge(text: "Sắp có", color: DS.Palette.tertiaryLabel)
                    }
                }

                Text(entry.detail)
                    .font(DS.Typeface.bodySmall)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.accent)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile)
                .fill(isSelected ? DS.Palette.selectionSoft : DS.Palette.chrome.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.tile)
                .strokeBorder(isSelected ? DS.Palette.accent : Color.clear, lineWidth: 1.5)
        )
        .opacity(entry.isAvailable ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if entry.isAvailable {
                selectedKind = entry.kind
                connect()
            }
        }
        .onTapGesture {
            if entry.isAvailable {
                selectedKind = entry.kind
            }
        }
    }

    @ViewBuilder
    private func connectorIcon(for kind: SourceKind) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(iconBackgroundColor(for: kind))
                .frame(width: 36, height: 36)
            iconSymbol(for: kind)
                .font(.system(size: 18))
                .foregroundStyle(iconForegroundColor(for: kind))
        }
    }

    private func iconBackgroundColor(for kind: SourceKind) -> Color {
        switch kind {
        case .excel: return Color(hex: "#107C41") ?? Color.green
        case .csv: return DS.Palette.controlFill
        case .json: return Color.orange.opacity(0.15)
        case .parquet: return DS.Palette.indigo.opacity(0.15)
        case .sqlite: return DS.Palette.danger.opacity(0.12)
        case .postgres: return DS.Palette.accent.opacity(0.15)
        }
    }

    private func iconForegroundColor(for kind: SourceKind) -> Color {
        switch kind {
        case .excel: return .white
        case .csv: return DS.Palette.secondaryLabel
        case .json: return Color.orange
        case .parquet: return DS.Palette.indigo
        case .sqlite: return DS.Palette.danger
        case .postgres: return DS.Palette.accent
        }
    }

    @ViewBuilder
    private func iconSymbol(for kind: SourceKind) -> some View {
        switch kind {
        case .excel: Image(systemName: "tablecells.fill")
        case .csv: Image(systemName: "doc.text.fill")
        case .json: Image(systemName: "curlybraces")
        case .parquet: Image(systemName: "square.stack.3d.down.right.fill")
        case .sqlite: Image(systemName: "cylinder.split.1x2.fill")
        case .postgres: Image(systemName: "server.rack")
        }
    }

    // MARK: - Footer (48 pt)

    private var footerBar: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                Button("Hủy") {
                    onClose()
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button {
                    connect()
                } label: {
                    HStack(spacing: 4) {
                        Text("Kết nối")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!isConnectEnabled)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(DS.Palette.chrome)
    }

    private func connect() {
        guard let entry = ConnectorCatalog.entries.first(where: { $0.kind == selectedKind }),
              entry.isAvailable else { return }
        guard let path = pickFile(selectedKind) else { return }
        Task {
            await state.openSource(kind: selectedKind, location: path)
        }
    }
}

struct GetDataFlowView: View {
    let state: NavigatorState
    private var isFailed: Bool { if case .failed = state.phase { true } else { false } }
    let existingTableNames: Set<String>
    let pickFile: (SourceKind) -> String?
    let onLoad: ([LoadedTable]) -> String?
    let onTransform: (([LoadedTable]) -> Void)?
    let onClose: () -> Void
    var scrollable: Bool

    init(state: NavigatorState,
         existingTableNames: Set<String>,
         pickFile: @escaping (SourceKind) -> String? = GetDataFilePicker.pick,
         onLoad: @escaping ([LoadedTable]) -> String?,
         onTransform: (([LoadedTable]) -> Void)? = nil,
         onClose: @escaping () -> Void,
         scrollable: Bool = true) {
        self.state = state
        self.existingTableNames = existingTableNames
        self.pickFile = pickFile
        self.onLoad = onLoad
        self.onTransform = onTransform
        self.onClose = onClose
        self.scrollable = scrollable
    }

    var body: some View {
        Group {
            if state.opensEditorDirectly && state.phase != .choosingSource && !isFailed {
                // JSON: Desktop mở thẳng Power Query Editor (VM-F7a), chỉ hiện tiến độ trong lúc dựng các bước.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Đang đọc \(URL(fileURLWithPath: state.location).lastPathComponent)…")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                .frame(width: 420, height: 160)
                .task(id: state.phase) {
                    guard state.phase == .ready, let onTransform else { return }
                    if let tables = await state.loadDirectly(existingNames: existingTableNames) { onTransform(tables) }
                }
            } else if state.phase == .choosingSource {
                GetDataDialogView(
                    state: state,
                    pickFile: pickFile,
                    onClose: onClose,
                    scrollable: scrollable
                )
            } else {
                NavigatorView(
                    state: state,
                    existingTableNames: existingTableNames,
                    onLoad: onLoad,
                    onTransform: onTransform,
                    onClose: onClose,
                    scrollable: scrollable
                )
            }
        }
    }
}
