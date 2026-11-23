import AppKit
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

extension UIParity {
@Suite("UIParity — ParityRenderTests")
@MainActor
struct ParityRenderTests {
    static var isRenderEnabled: Bool {
        ProcessInfo.processInfo.environment["BIPRO_H_RENDER"] == "1"
    }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // UIParity
            .deletingLastPathComponent() // BIProTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    static func renderPNG<V: View>(_ view: V, size: CGSize, dark: Bool) -> Data? {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var result: Data?
        appearance.performAsCurrentDrawingAppearance {
            let content = view
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(size)
            renderer.scale = 2
            if let cgImage = renderer.cgImage {
                result = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
            }
        }
        return result
    }

    static func makeSampleState() async throws -> DocumentState {
        let blank = try NewDocument.blank()
        let workspace = try Workspace(data: blank)
        let state = DocumentState(workspace: workspace, fileName: "Nhom6.pbix")
        var enter = EnterDataTable(name: "Sales")
        _ = try enter.paste("Region\tAmount\nNorth\t1000\nSouth\t2500")
        _ = await state.loadEnterData(enter)
        state.mode = .report
        state.editMode = true
        _ = state.insertVisual("clusteredColumnChart")
        state.visualID = nil
        return state
    }

    @Test func homeRibbonExceedsMinimumWindowWidthAndSupportsHorizontalScroll() async throws {
        let width = RibbonView.estimatedContentWidth(for: RibbonCatalog.reportHome)
        #expect(width > 1000, "Home Report Ribbon (\(width) pt) phải lớn hơn 1000 pt để kiểm cuộn ngang ở cửa sổ nhỏ nhất")

        let state = try await Self.makeSampleState()
        let host = NSHostingView(rootView: RibbonView(state: state, scrollable: true).frame(width: 1000, height: 140))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(host.fittingSize.height >= UIMetrics.tabRow + UIMetrics.ribbonPanel)
    }

    @Test func renderUS1HomeRibbonLightAndDark() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us1", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        let savedCollapsed = AppPreferences.shared.ribbonCollapsed
        defer {
            AppPreferences.shared.language = savedLang
            AppPreferences.shared.ribbonCollapsed = savedCollapsed
        }
        AppPreferences.shared.ribbonCollapsed = false

        let state = try await Self.makeSampleState()
        let size = CGSize(width: 1600, height: 140)

        var sizes: [Int] = []

        AppPreferences.shared.language = .en
        state.visualID = nil
        state.ribbonTab = .home
        let lightEN = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: false))
        try lightEN.write(to: outDir.appendingPathComponent("home-light-en.png"))
        sizes.append(lightEN.count)

        let darkEN = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: true))
        try darkEN.write(to: outDir.appendingPathComponent("home-dark-en.png"))
        sizes.append(darkEN.count)

        AppPreferences.shared.language = .vi
        let lightVI = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: false))
        try lightVI.write(to: outDir.appendingPathComponent("home-light-vi.png"))
        sizes.append(lightVI.count)

        AppPreferences.shared.language = .en
        state.visualID = state.page?.visuals.first?.id
        let selectedEN = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: false))
        try selectedEN.write(to: outDir.appendingPathComponent("home-selected-en.png"))
        sizes.append(selectedEN.count)

        for byteCount in sizes {
            #expect(byteCount > 8000, "Ảnh Ribbon xuất ra quá nhỏ (\(byteCount) bytes), nghi vẽ trống")
        }
        #expect(Set(sizes).count == sizes.count, "Các ảnh khác nội dung không được có kích thước byte giống hệt nhau")
    }

    @Test func renderUS2ReportSixTabs() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us2", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        let savedCollapsed = AppPreferences.shared.ribbonCollapsed
        defer {
            AppPreferences.shared.language = savedLang
            AppPreferences.shared.ribbonCollapsed = savedCollapsed
        }
        AppPreferences.shared.ribbonCollapsed = false
        AppPreferences.shared.language = .en

        let state = try await Self.makeSampleState()
        let size = CGSize(width: 1600, height: 140)
        let tabs: [(RibbonTab, String)] = [
            (.insert, "insert"),
            (.modeling, "modeling"),
            (.design, "design"),
            (.view, "view"),
            (.optimize, "optimize"),
            (.help, "help"),
        ]

        var sizes: [Int] = []
        for (tab, fileName) in tabs {
            state.ribbonTab = tab
            let data = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: false))
            try data.write(to: outDir.appendingPathComponent("\(fileName)-light-en.png"))
            #expect(data.count > 8000, "Ảnh \(fileName) quá nhỏ (\(data.count) bytes)")
            sizes.append(data.count)
        }
        #expect(Set(sizes).count == sizes.count, "6 ảnh tab Report không được có kích thước byte giống hệt nhau")
    }

    @Test func renderUS3ContextualAndCodeViewRibbons() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us3", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        let savedCollapsed = AppPreferences.shared.ribbonCollapsed
        defer {
            AppPreferences.shared.language = savedLang
            AppPreferences.shared.ribbonCollapsed = savedCollapsed
        }
        AppPreferences.shared.ribbonCollapsed = false
        AppPreferences.shared.language = .en

        let state = try await Self.makeSampleState()
        let size = CGSize(width: 1600, height: 140)

        var sizes: [Int] = []

        // 1. Format + Data/Drill (Report contextual)
        state.mode = .report
        state.visualID = state.page?.visuals.first?.id
        for (tab, fileName) in [(RibbonTab.format, "format"), (.dataDrill, "data-drill")] {
            state.ribbonTab = tab
            let data = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: false))
            try data.write(to: outDir.appendingPathComponent("\(fileName)-light-en.png"))
            #expect(data.count > 8000)
            sizes.append(data.count)
        }

        // 2. Table view: Home, Table tools, Column tools
        state.mode = .table
        state.select(table: "Sales", column: "Amount")
        for (tab, fileName) in [(RibbonTab.home, "table-home"), (.tableTools, "table-tools"), (.columnTools, "column-tools")] {
            state.ribbonTab = tab
            let data = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: false))
            try data.write(to: outDir.appendingPathComponent("\(fileName)-light-en.png"))
            #expect(data.count > 8000)
            sizes.append(data.count)
        }

        // 3. Model / DAX / TMDL Home
        for (mode, fileName) in [(WorkspaceMode.model, "model-home"), (.daxQuery, "dax-home"), (.tmdl, "tmdl-home")] {
            state.mode = mode
            state.ribbonTab = .home
            let data = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: size, dark: false))
            try data.write(to: outDir.appendingPathComponent("\(fileName)-light-en.png"))
            #expect(data.count > 8000)
            sizes.append(data.count)
        }

        #expect(Set(sizes).count == sizes.count, "8 ảnh US3 không được có kích thước byte giống hệt nhau")
    }

    @Test func us3RibbonActionsAndCodeActionsWorkWithoutRegression() async throws {
        let state = try await Self.makeSampleState()
        state.mode = .report
        state.editMode = true
        let v1 = try #require(state.page?.visuals.first?.id)
        let v2 = try #require(state.insertVisual("cardVisual"))

        // Edit interactions toggle
        state.visualID = v1
        #expect(state.layout.isEditingInteractions == false)
        RibbonActions.perform(.editInteractions, state: state)
        #expect(state.layout.isEditingInteractions == true)
        RibbonActions.perform(.editInteractions, state: state)
        #expect(state.layout.isEditingInteractions == false)

        // Align / Group with 2 visuals selected
        state.layout.select(v1)
        state.layout.select(v2, extend: true)
        #expect(state.layout.selection.count == 2)
        state.align(.left)
        state.groupSelection()
        #expect(state.ungroupBlocker == nil)
        state.ungroupSelection()

        // Column tools quick format & undo
        state.mode = .table
        state.select(table: "Sales", column: "Amount")
        RibbonActions.perform(.currencyFormat, state: state)
        #expect(state.workspace.column(table: "Sales", name: "Amount")?.formatString == "\\$#,0.00")
        state.layout.undo()

        // DAX Format + Comment + Uncomment
        state.mode = .daxQuery
        state.daxQueries[0].text = "EVALUATE 'Sales'"
        RibbonActions.perform(.daxFormat, state: state)
        #expect(state.daxQueries[0].text.contains("EVALUATE"))
        RibbonActions.perform(.comment, state: state)
        #expect(state.daxQueries[0].text.hasPrefix("// "))
        RibbonActions.perform(.uncomment, state: state)
        #expect(!state.daxQueries[0].text.hasPrefix("// "))

        // TMDL Copy action
        state.mode = .tmdl
        if let firstDoc = state.workspace.tmdlDocuments.first {
            state.tmdlPath = firstDoc.path
            let result = RibbonActions.perform(.copy, state: state)
            #expect(result == .performed)
        }
    }

    @Test func renderUS4ShellLightAndDark() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us4", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        let savedCollapsed = AppPreferences.shared.ribbonCollapsed
        defer {
            AppPreferences.shared.language = savedLang
            AppPreferences.shared.ribbonCollapsed = savedCollapsed
        }
        AppPreferences.shared.ribbonCollapsed = false
        AppPreferences.shared.language = .en

        let state = try await Self.makeSampleState()
        let size = CGSize(width: 1440, height: 860)

        @ViewBuilder
        func shellSnapshot(state: DocumentState, mode: WorkspaceMode) -> some View {
            VStack(spacing: 0) {
                TitleBar(state: state)
                RibbonView(state: state, scrollable: false)
                HStack(spacing: 0) {
                    Rail(state: state)
                    Group {
                        if mode != .report && state.workspace.metadata == nil {
                            EmptyViewState(state: state)
                        } else if mode == .report {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(DS.Palette.documentPaper)
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .padding(24)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(DS.Palette.canvasWell)
                            }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: mode.symbol).font(.system(size: 28)).foregroundStyle(DS.Palette.accent)
                                Text(Rail.tooltip(for: mode, language: .en)).font(DS.Typeface.headlineMedium).foregroundStyle(DS.Palette.label)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(DS.Palette.canvasWell)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(DS.Palette.chrome)
            .environment(\.isSnapshotRender, true)
        }

        var sizes: [Int] = []
        state.mode = .report
        state.ribbonTab = .home
        let reportLight = try #require(Self.renderPNG(shellSnapshot(state: state, mode: .report), size: size, dark: false))
        try reportLight.write(to: outDir.appendingPathComponent("shell-report-light.png"))
        sizes.append(reportLight.count)

        let reportDark = try #require(Self.renderPNG(shellSnapshot(state: state, mode: .report), size: size, dark: true))
        try reportDark.write(to: outDir.appendingPathComponent("shell-report-dark.png"))
        sizes.append(reportDark.count)

        // Trạng thái trống khi chọn Table view trên tệp chưa có mô hình (FR-016)
        let dir = SyntheticReport.temporaryDirectory("us4-empty")
        let url = try SyntheticReport.make(in: dir)
        let emptyState = DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: "BlankReport.pbix")
        emptyState.mode = .table
        let emptyLight = try #require(Self.renderPNG(shellSnapshot(state: emptyState, mode: .table), size: size, dark: false))
        try emptyLight.write(to: outDir.appendingPathComponent("shell-empty-table-light.png"))
        sizes.append(emptyLight.count)

        let emptyDark = try #require(Self.renderPNG(shellSnapshot(state: emptyState, mode: .table), size: size, dark: true))
        try emptyDark.write(to: outDir.appendingPathComponent("shell-empty-table-dark.png"))
        sizes.append(emptyDark.count)

        for byteCount in sizes {
            #expect(byteCount > 10000)
        }
        #expect(Set(sizes).count == sizes.count)
    }

    @Test func renderUS5PanesLightAndDark() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us5", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        defer { AppPreferences.shared.language = savedLang }
        AppPreferences.shared.language = .en

        let state = try await Self.makeSampleState()
        state.mode = .report
        state.visualID = state.page?.visuals.first?.id
        let size = CGSize(width: 440, height: 760)

        @ViewBuilder
        func reportPanesSnapshot(state: DocumentState) -> some View {
            HStack(spacing: 0) {
                CollapsedPaneStrip(title: tr(.paneFilters), symbol: "line.3.horizontal.decrease") {}
                    .hairline(.leading)
                VisualizationsPane(state: state) {}
                    .frame(width: UIMetrics.pane)
                    .hairline(.leading)
                DataPane(state: state, purpose: .report) {}
                    .frame(width: UIMetrics.pane)
                    .hairline(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .background(DS.Palette.canvasWell)
            .environment(\.isSnapshotRender, true)
        }

        var sizes: [Int] = []
        state.visualizationsTab = .build
        let buildLight = try #require(Self.renderPNG(reportPanesSnapshot(state: state), size: size, dark: false))
        try buildLight.write(to: outDir.appendingPathComponent("panes-build-light.png"))
        sizes.append(buildLight.count)

        let buildDark = try #require(Self.renderPNG(reportPanesSnapshot(state: state), size: size, dark: true))
        try buildDark.write(to: outDir.appendingPathComponent("panes-build-dark.png"))
        sizes.append(buildDark.count)

        state.visualizationsTab = .format
        let formatLight = try #require(Self.renderPNG(reportPanesSnapshot(state: state), size: size, dark: false))
        try formatLight.write(to: outDir.appendingPathComponent("panes-format-light.png"))
        sizes.append(formatLight.count)

        // Data pane Model tree (TMDL/Model view)
        state.mode = .tmdl
        let modelTreeView = DataPane(state: state, purpose: .query, collapse: {}, initialTab: .model)
            .frame(width: 240, height: 600)
            .environment(\.isSnapshotRender, true)
        let modelLight = try #require(Self.renderPNG(modelTreeView, size: CGSize(width: 240, height: 600), dark: false))
        try modelLight.write(to: outDir.appendingPathComponent("pane-data-model-light.png"))
        sizes.append(modelLight.count)

        for byteCount in sizes {
            #expect(byteCount > 8000)
        }
        #expect(Set(sizes).count == sizes.count)
    }

    @Test func renderUS6PageTabsAndStatusBar() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us6", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        defer { AppPreferences.shared.language = savedLang }
        AppPreferences.shared.language = .en

        let state = try await Self.makeSampleState()
        state.mode = .report
        state.editMode = true
        state.addPage()
        state.addPage()
        state.zoom = 0.69

        let reportBottom = VStack(spacing: 0) {
            PageTabs(state: state, scale: 0.69)
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)

        let size = CGSize(width: 1200, height: UIMetrics.pageTabs + UIMetrics.statusBar)
        var sizes: [Int] = []

        let reportLight = try #require(Self.renderPNG(reportBottom, size: size, dark: false))
        try reportLight.write(to: outDir.appendingPathComponent("report-bottom-light.png"))
        sizes.append(reportLight.count)

        let reportDark = try #require(Self.renderPNG(reportBottom, size: size, dark: true))
        try reportDark.write(to: outDir.appendingPathComponent("report-bottom-dark.png"))
        sizes.append(reportDark.count)

        state.mode = .table
        state.select(table: "Sales", column: "Amount")
        let tableBar = WindowStatusBar(state: state).environment(\.isSnapshotRender, true)
        let tableLight = try #require(Self.renderPNG(tableBar, size: CGSize(width: 1200, height: UIMetrics.statusBar), dark: false))
        try tableLight.write(to: outDir.appendingPathComponent("table-status-light.png"))
        sizes.append(tableLight.count)

        state.mode = .model
        state.modelZoom = 0.85
        let modelBar = WindowStatusBar(state: state).environment(\.isSnapshotRender, true)
        let modelLight = try #require(Self.renderPNG(modelBar, size: CGSize(width: 1200, height: UIMetrics.statusBar), dark: false))
        try modelLight.write(to: outDir.appendingPathComponent("model-status-light.png"))
        sizes.append(modelLight.count)

        for byteCount in sizes {
            #expect(byteCount > 2000)
        }
        #expect(Set(sizes).count == sizes.count)
    }

    @Test func renderUS7StartBackstageOptionsAddData() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us7", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        defer { AppPreferences.shared.language = savedLang }
        AppPreferences.shared.language = .en

        let state = try await Self.makeSampleState()
        let sampleRecents = [
            RecentFileEntry(url: URL(fileURLWithPath: "/Users/demo/Reports/Sales2026.pbix"), openedAt: Date().addingTimeInterval(-3600)),
            RecentFileEntry(url: URL(fileURLWithPath: "/Users/demo/Reports/Nhom6_d15.pbix"), openedAt: Date().addingTimeInterval(-86400)),
        ]

        var sizes: [Int] = []

        // 1. StartScreen
        let startView = StartScreen(recentEntries: sampleRecents)
            .environment(\.isSnapshotRender, true)
        let startData = try #require(Self.renderPNG(startView, size: CGSize(width: 1280, height: 760), dark: false))
        try startData.write(to: outDir.appendingPathComponent("start-screen-light.png"))
        sizes.append(startData.count)

        // 2. Backstage Home
        let backstageHome = VStack(spacing: 0) {
            TitleBar(state: state)
            BackstageView(state: state, initialSection: "home", recentEntries: sampleRecents)
        }
        .environment(\.isSnapshotRender, true)
        let bsHomeData = try #require(Self.renderPNG(backstageHome, size: CGSize(width: 1280, height: 760), dark: false))
        try bsHomeData.write(to: outDir.appendingPathComponent("backstage-home-light.png"))
        sizes.append(bsHomeData.count)

        // 3. Backstage Export
        let backstageExport = VStack(spacing: 0) {
            TitleBar(state: state)
            BackstageView(state: state, initialSection: "export", recentEntries: sampleRecents)
        }
        .environment(\.isSnapshotRender, true)
        let bsExportData = try #require(Self.renderPNG(backstageExport, size: CGSize(width: 1280, height: 760), dark: false))
        try bsExportData.write(to: outDir.appendingPathComponent("backstage-export-light.png"))
        sizes.append(bsExportData.count)

        // 4. OptionsDialog
        let optionsView = OptionsDialog(
            options: state.fileOptions,
            autoDateTimeBlocker: nil,
            onCommit: { _ in nil },
            onCancel: {}
        )
        .environment(\.isSnapshotRender, true)
        let optionsData = try #require(Self.renderPNG(optionsView, size: CGSize(width: 770, height: 600), dark: false))
        try optionsData.write(to: outDir.appendingPathComponent("options-dialog-light.png"))
        sizes.append(optionsData.count)

        // 5. AddDataPanel (blank report)
        let blankState = DocumentState(workspace: try Workspace(data: try NewDocument.blank()), fileName: "Blank.pbix")
        let addDataView = AddDataPanel(state: blankState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Palette.documentPaper)
            .environment(\.isSnapshotRender, true)
        let addDataBytes = try #require(Self.renderPNG(addDataView, size: CGSize(width: 1180, height: 520), dark: false))
        try addDataBytes.write(to: outDir.appendingPathComponent("add-data-panel-light.png"))
        sizes.append(addDataBytes.count)

        for byteCount in sizes {
            #expect(byteCount > 8000)
        }
        #expect(Set(sizes).count == sizes.count)
    }

    @Test func renderUS8CodeModelTableViews() async throws {
        guard Self.isRenderEnabled else { return }
        let outDir = Self.repoRoot.appendingPathComponent("build/h-out/us8", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        defer { AppPreferences.shared.language = savedLang }
        AppPreferences.shared.language = .en

        let state = try await Self.makeSampleState()
        let size = CGSize(width: 1280, height: 700)
        var sizes: [Int] = []

        // 1. DAX query view chrome (banner + Run/Update + editor placeholder + Results empty + Query 1 tab + Data pane)
        state.mode = .daxQuery
        let daxSnapshot = VStack(spacing: 0) {
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                VStack(spacing: 0) {
                    DAXInfoBanner {}
                    DAXCodeActionBar(state: state)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1   // Welcome to DAX query view!")
                            .foregroundStyle(DS.Palette.accentBrand)
                        Text("2   EVALUATE")
                            .foregroundStyle(DS.Palette.accent)
                        Text("3       TOPN(100, 'Sales')")
                            .foregroundStyle(DS.Palette.label)
                    }
                    .font(DS.Typeface.monoMedium)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(DS.Palette.canvas)
                    .hairline(.bottom)
                    DAXEmptyResultsIllustration()
                        .frame(height: 220)
                }
                DataPane(state: state, purpose: .query, collapse: {}, initialTab: .tables)
                    .frame(width: 220)
                    .hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        let daxData = try #require(Self.renderPNG(daxSnapshot, size: size, dark: false))
        try daxData.write(to: outDir.appendingPathComponent("dax-view-light.png"))
        sizes.append(daxData.count)

        // 2. TMDL view chrome (Apply/Preview + editor + Problems (0)/Output + Data Model tree)
        state.mode = .tmdl
        let tmdlSnapshot = VStack(spacing: 0) {
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                VStack(spacing: 0) {
                    TMDLCodeActionBar(state: state, path: "tables/Sales.tmdl", changed: false, onDiscard: {}, onApply: {})
                    Text("createOrReplace\n    table Sales\n        column Region\n        column Amount")
                        .font(DS.Typeface.monoMedium)
                        .foregroundStyle(DS.Palette.label)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(DS.Palette.canvas)
                        .hairline(.bottom)
                    HStack(spacing: 16) {
                        Text("Problems (0)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(DS.Palette.label)
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.accentBrand).frame(height: 2) }
                        Text("Output").font(.system(size: 11.5)).foregroundStyle(DS.Palette.secondaryLabel)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .background(DS.Palette.canvas)
                }
                DataPane(state: state, purpose: .query, collapse: {}, initialTab: .model)
                    .frame(width: 220)
                    .hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        let tmdlData = try #require(Self.renderPNG(tmdlSnapshot, size: size, dark: false))
        try tmdlData.write(to: outDir.appendingPathComponent("tmdl-view-light.png"))
        sizes.append(tmdlData.count)

        // 3. Model view chrome (canvas + ModelPropertiesPanel Cards No/Yes/No + Data pane + status bar)
        state.mode = .model
        let modelSnapshot = VStack(spacing: 0) {
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                ZStack {
                    DotGrid()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "tablecells").foregroundStyle(DS.Palette.table)
                            Text("Sales").font(DS.Typeface.headlineSmall)
                            Spacer()
                        }
                        .padding(8)
                        .hairline(.bottom)
                        Text("Region").font(DS.Typeface.bodySmall).padding(.horizontal, 10)
                        Text("Amount").font(DS.Typeface.bodySmall).padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    .frame(width: 210)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.canvas))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Palette.canvasWell)
                ModelPropertiesPanel(settings: .constant(ModelCardsSettings())) {}
                    .frame(width: UIMetrics.pane)
                    .hairline(.leading)
                DataPane(state: state, purpose: .query, collapse: {}, initialTab: .tables)
                    .frame(width: 210)
                    .hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        let modelData = try #require(Self.renderPNG(modelSnapshot, size: size, dark: false))
        try modelData.write(to: outDir.appendingPathComponent("model-view-light.png"))
        sizes.append(modelData.count)

        // 4. Table view chrome (Column tools Ribbon + FormulaBar + column header ▾ + Data pane + StatusLine)
        state.mode = .table
        state.select(table: "Sales", column: "Amount")
        let tableSnapshot = VStack(spacing: 0) {
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                VStack(spacing: 0) {
                    FormulaBar(state: state)
                    HStack(spacing: 0) {
                        Text("Region ▾").font(.system(size: 12, weight: .semibold)).frame(width: 180, height: 28, alignment: .leading).padding(.horizontal, 10).hairline(.trailing)
                        Text("Amount ▾").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 180, height: 28, alignment: .leading).padding(.horizontal, 10).background(DS.Palette.accentBrand)
                        Spacer()
                    }
                    .background(DS.Palette.chrome)
                    .hairline(.bottom)
                    Spacer()
                }
                .background(DS.Palette.canvas)
                DataPane(state: state, purpose: .table)
                    .frame(width: 220)
                    .hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        let tableData = try #require(Self.renderPNG(tableSnapshot, size: size, dark: false))
        try tableData.write(to: outDir.appendingPathComponent("table-view-light.png"))
        sizes.append(tableData.count)

        for byteCount in sizes {
            #expect(byteCount > 10000)
        }
        #expect(Set(sizes).count == sizes.count)
    }

    @Test func renderH6DarkModeAuditAndDesktopGateBundle() async throws {
        guard Self.isRenderEnabled else { return }
        let darkDir = Self.repoRoot.appendingPathComponent("build/h-out/h6/dark", isDirectory: true)
        let gateDir = Self.repoRoot.appendingPathComponent("build/h-out/gate/bipro", isDirectory: true)
        try FileManager.default.createDirectory(at: darkDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gateDir, withIntermediateDirectories: true)

        let savedLang = AppPreferences.shared.language
        let savedCollapsed = AppPreferences.shared.ribbonCollapsed
        defer {
            AppPreferences.shared.language = savedLang
            AppPreferences.shared.ribbonCollapsed = savedCollapsed
        }
        AppPreferences.shared.language = .en
        AppPreferences.shared.ribbonCollapsed = false

        let state = try await Self.makeSampleState()
        let ribbonSize = CGSize(width: 1600, height: 140)
        let firstVisualID = state.page?.visuals.first?.id

        let fifteenRibbons: [(name: String, mode: WorkspaceMode, tab: RibbonTab, selectVisual: Bool, selectColumn: Bool)] = [
            ("01-report-home", .report, .home, false, false),
            ("02-report-insert", .report, .insert, false, false),
            ("03-report-modeling", .report, .modeling, false, false),
            ("04-report-design", .report, .design, false, false),
            ("05-report-view", .report, .view, false, false),
            ("06-report-optimize", .report, .optimize, false, false),
            ("07-report-help", .report, .help, false, false),
            ("08-report-format", .report, .format, true, false),
            ("09-report-data-drill", .report, .dataDrill, true, false),
            ("10-table-home", .table, .home, false, true),
            ("11-table-tools", .table, .tableTools, false, false),
            ("12-column-tools", .table, .columnTools, false, true),
            ("13-model-home", .model, .home, false, false),
            ("14-dax-home", .daxQuery, .home, false, false),
            ("15-tmdl-home", .tmdl, .home, false, false),
        ]

        var lightSizes: [Int] = []
        var darkSizes: [Int] = []
        for entry in fifteenRibbons {
            state.mode = entry.mode
            if entry.mode == .report {
                state.visualID = entry.selectVisual ? firstVisualID : nil
            } else if entry.mode == .table {
                state.select(table: "Sales", column: entry.selectColumn ? "Amount" : nil)
            }
            state.ribbonTab = entry.tab

            let lightPNG = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: ribbonSize, dark: false))
            try lightPNG.write(to: gateDir.appendingPathComponent("ribbon-\(entry.name).png"))
            lightSizes.append(lightPNG.count)

            let darkPNG = try #require(Self.renderPNG(RibbonView(state: state, scrollable: false), size: ribbonSize, dark: true))
            try darkPNG.write(to: darkDir.appendingPathComponent("ribbon-\(entry.name)-dark.png"))
            darkSizes.append(darkPNG.count)
        }

        // 6 full views (Start, Report, Table, Model, DAX, TMDL) in Gate Light & Dark audit
        let viewSize = CGSize(width: 1440, height: 860)
        let recents = [
            RecentFileEntry(url: URL(fileURLWithPath: "/Users/demo/Nhom6_d15.pbix"), openedAt: Date().addingTimeInterval(-600))
        ]
        let startLight = try #require(Self.renderPNG(StartScreen(recentEntries: recents).environment(\.isSnapshotRender, true), size: viewSize, dark: false))
        try startLight.write(to: gateDir.appendingPathComponent("view-01-start.png"))
        let startDark = try #require(Self.renderPNG(StartScreen(recentEntries: recents).environment(\.isSnapshotRender, true), size: viewSize, dark: true))
        try startDark.write(to: darkDir.appendingPathComponent("view-01-start-dark.png"))

        state.mode = .report
        state.visualID = firstVisualID
        state.ribbonTab = .home
        state.visualizationsTab = .build
        let reportView = VStack(spacing: 0) {
            TitleBar(state: state)
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                VStack(spacing: 0) {
                    Rectangle().fill(DS.Palette.documentPaper).aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Palette.canvasWell)
                    PageTabs(state: state, scale: 0.7)
                }
                CollapsedPaneStrip(title: tr(.paneFilters), symbol: "line.3.horizontal.decrease") {}.hairline(.leading)
                VisualizationsPane(state: state) {}.frame(width: UIMetrics.pane).hairline(.leading)
                DataPane(state: state, purpose: .report) {}.frame(width: UIMetrics.pane).hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .background(DS.Palette.chrome)
        .environment(\.isSnapshotRender, true)

        let reportLight = try #require(Self.renderPNG(reportView, size: viewSize, dark: false))
        try reportLight.write(to: gateDir.appendingPathComponent("view-02-report.png"))
        let reportDark = try #require(Self.renderPNG(reportView, size: viewSize, dark: true))
        try reportDark.write(to: darkDir.appendingPathComponent("view-02-report-dark.png"))

        // File Backstage view in gate & dark
        let backstageView = VStack(spacing: 0) {
            TitleBar(state: state)
            BackstageView(state: state, initialSection: "home", recentEntries: recents)
        }
        .environment(\.isSnapshotRender, true)
        let bsLight = try #require(Self.renderPNG(backstageView, size: viewSize, dark: false))
        try bsLight.write(to: gateDir.appendingPathComponent("view-03-file-backstage.png"))
        let bsDark = try #require(Self.renderPNG(backstageView, size: viewSize, dark: true))
        try bsDark.write(to: darkDir.appendingPathComponent("view-03-file-backstage-dark.png"))

        // Table / Model / DAX / TMDL views
        state.mode = .table
        state.select(table: "Sales", column: "Amount")
        state.ribbonTab = .columnTools
        let tableFull = VStack(spacing: 0) {
            TitleBar(state: state)
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                VStack(spacing: 0) {
                    FormulaBar(state: state)
                    HStack(spacing: 0) {
                        Text("Region ▾").font(.system(size: 12, weight: .semibold)).frame(width: 180, height: 28, alignment: .leading).padding(.horizontal, 10).hairline(.trailing)
                        Text("Amount ▾").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 180, height: 28, alignment: .leading).padding(.horizontal, 10).background(DS.Palette.accentBrand)
                        Spacer()
                    }
                    .background(DS.Palette.chrome)
                    .hairline(.bottom)
                    Spacer()
                }
                .background(DS.Palette.canvas)
                DataPane(state: state, purpose: .table).frame(width: 220).hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        try #require(Self.renderPNG(tableFull, size: viewSize, dark: false)).write(to: gateDir.appendingPathComponent("view-04-table.png"))
        try #require(Self.renderPNG(tableFull, size: viewSize, dark: true)).write(to: darkDir.appendingPathComponent("view-04-table-dark.png"))

        state.mode = .model
        state.ribbonTab = .home
        let modelFull = VStack(spacing: 0) {
            TitleBar(state: state)
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                ZStack {
                    DotGrid()
                    Text("Sales").font(DS.Typeface.headlineSmall).padding(16)
                        .background(RoundedRectangle(cornerRadius: 6).fill(DS.Palette.canvas))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Palette.canvasWell)
                ModelPropertiesPanel(settings: .constant(ModelCardsSettings())) {}.frame(width: UIMetrics.pane).hairline(.leading)
                DataPane(state: state, purpose: .query, collapse: {}, initialTab: .tables).frame(width: 210).hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        try #require(Self.renderPNG(modelFull, size: viewSize, dark: false)).write(to: gateDir.appendingPathComponent("view-05-model.png"))
        try #require(Self.renderPNG(modelFull, size: viewSize, dark: true)).write(to: darkDir.appendingPathComponent("view-05-model-dark.png"))

        state.mode = .daxQuery
        state.ribbonTab = .home
        let daxFull = VStack(spacing: 0) {
            TitleBar(state: state)
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                VStack(spacing: 0) {
                    DAXInfoBanner {}
                    DAXCodeActionBar(state: state)
                    Text("EVALUATE TOPN(100, 'Sales')").font(DS.Typeface.monoMedium).padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(DS.Palette.canvas).hairline(.bottom)
                    DAXEmptyResultsIllustration().frame(height: 240)
                }
                DataPane(state: state, purpose: .query, collapse: {}, initialTab: .tables).frame(width: 220).hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        try #require(Self.renderPNG(daxFull, size: viewSize, dark: false)).write(to: gateDir.appendingPathComponent("view-06-dax.png"))
        try #require(Self.renderPNG(daxFull, size: viewSize, dark: true)).write(to: darkDir.appendingPathComponent("view-06-dax-dark.png"))

        state.mode = .tmdl
        state.ribbonTab = .home
        let tmdlFull = VStack(spacing: 0) {
            TitleBar(state: state)
            RibbonView(state: state, scrollable: false)
            HStack(spacing: 0) {
                Rail(state: state)
                VStack(spacing: 0) {
                    TMDLCodeActionBar(state: state, path: "tables/Sales.tmdl", changed: false, onDiscard: {}, onApply: {})
                    Text("createOrReplace\n    table Sales").font(DS.Typeface.monoMedium).padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(DS.Palette.canvas).hairline(.bottom)
                    HStack {
                        Text("Problems (0)").font(.system(size: 11.5, weight: .semibold)).padding(.vertical, 6)
                            .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.accentBrand).frame(height: 2) }
                        Text("Output").font(.system(size: 11.5)).foregroundStyle(DS.Palette.secondaryLabel)
                        Spacer()
                    }
                    .padding(.horizontal, 12).background(DS.Palette.canvas)
                }
                DataPane(state: state, purpose: .query, collapse: {}, initialTab: .model).frame(width: 220).hairline(.leading)
            }
            WindowStatusBar(state: state)
        }
        .environment(\.isSnapshotRender, true)
        try #require(Self.renderPNG(tmdlFull, size: viewSize, dark: false)).write(to: gateDir.appendingPathComponent("view-07-tmdl.png"))
        try #require(Self.renderPNG(tmdlFull, size: viewSize, dark: true)).write(to: darkDir.appendingPathComponent("view-07-tmdl-dark.png"))

        #expect(lightSizes.allSatisfy { $0 > 8000 })
        #expect(darkSizes.allSatisfy { $0 > 8000 })
        #expect(Set(lightSizes).count == lightSizes.count)
        #expect(Set(darkSizes).count == darkSizes.count)
    }
}
}
