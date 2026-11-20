import AppKit
import Foundation
import PBIXKit
import UniformTypeIdentifiers

// MARK: - Xuất PDF / PNG / CSV (US1, FR-001..FR-005)

extension DocumentState {
    var selectedVisual: ReportVisual? {
        guard let page, let visualID else { return nil }
        return page.visuals.first { $0.id == visualID }
    }

    /// Lý do mục "Dữ liệu visual ra CSV…" bị vô hiệu hoá; `nil` khi sẵn sàng xuất.
    var exportCSVDisabledReason: String? {
        guard let visual = selectedVisual else {
            return tr(.exportCSVDisabledNoSelection)
        }
        guard VisualContentView.liveTypes.contains(visual.type), interaction.isAvailable else {
            return tr(.exportCSVDisabledNoData)
        }
        if case .empty = interaction.loadedDataViews[visual.id] {
            return tr(.exportCSVDisabledNoData)
        }
        return nil
    }

    func openExportSheet(_ kind: ExportSheetKind) {
        exportError = nil
        exportProgress = ""
        isExporting = false
        exportSheetKind = kind
    }

    func closeExportSheet() {
        guard !isExporting else { return }
        exportSheetKind = nil
        exportError = nil
        exportProgress = ""
    }

    private func defaultExportName(suffix: String, ext: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let safeSuffix = suffix.replacingOccurrences(of: "/", with: "-")
        return safeSuffix.isEmpty ? "\(base).\(ext)" : "\(base) - \(safeSuffix).\(ext)"
    }

    func runExportPDF(scope: ExportPDFScope) {
        let targetPages: [ReportPage]
        switch scope {
        case .allVisiblePages:
            targetPages = pages.filter { !$0.isHidden }
        case .currentPage:
            targetPages = page.map { [$0] } ?? []
        }
        guard !targetPages.isEmpty else {
            exportError = tr(.exportNoVisiblePages)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportName(suffix: scope == .currentPage ? (page?.displayName ?? "") : "", ext: "pdf")
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isExporting = true
        exportError = nil
        exportProgress = tr(.exportProgressPreparing)

        Task { @MainActor in
            defer { isExporting = false }
            var preloadedByPage: [String: [String: LiveVisualData]] = [:]
            for (idx, p) in targetPages.enumerated() {
                exportProgress = trf(.exportProgressRenderingPageFormat, idx + 1, targetPages.count)
                preloadedByPage[p.id] = await ReportPageExporter.preload(page: p, interaction: interaction)
            }
            do {
                let data = try ReportPageExporter.renderPDF(
                    pages: targetPages,
                    workspace: workspace,
                    preloadedByPage: preloadedByPage,
                    interaction: interaction
                )
                try data.write(to: destination, options: .atomic)
                exportSheetKind = nil
                AccessibilityAnnouncer.announce(trf(.a11yAnnouncementExportedFormat, destination.lastPathComponent))
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    func runExportPNG(scale: ExportPNGScale) {
        guard let currentPage = page else {
            exportError = tr(.exportNoVisiblePages)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportName(suffix: currentPage.displayName, ext: "png")
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isExporting = true
        exportError = nil
        exportProgress = tr(.exportProgressPreparing)

        Task { @MainActor in
            defer { isExporting = false }
            let preloaded = await ReportPageExporter.preload(page: currentPage, interaction: interaction)
            do {
                let data = try ReportPageExporter.renderPNG(
                    page: currentPage,
                    workspace: workspace,
                    preloaded: preloaded,
                    interaction: interaction,
                    scale: scale
                )
                try data.write(to: destination, options: .atomic)
                exportSheetKind = nil
                AccessibilityAnnouncer.announce(trf(.a11yAnnouncementExportedFormat, destination.lastPathComponent))
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    func exportSelectedVisualToCSV() {
        guard let currentPage = page, let visual = selectedVisual else { return }
        if let cached = interaction.loadedDataViews[visual.id] {
            exportVisualToCSV(visual: visual, view: cached)
            return
        }
        Task { @MainActor in
            do {
                let loaded = try await interaction.load(page: currentPage, visual: visual, state: interaction.state(for: currentPage))
                exportVisualToCSV(visual: visual, view: loaded.view)
            } catch {
                _ = Alerts.ask(tr(.exportErrorTitle), error.localizedDescription, buttons: [tr(.close)], style: .critical)
            }
        }
    }

    func exportVisualToCSV(visual: ReportVisual, view: DataView) {
        do {
            let csvData = try VisualCSVExporter.export(view)
            let title = visual.containerObjects.string("title", "text")
                ?? visual.fields.first?.label
                ?? visual.type
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = defaultExportName(suffix: title, ext: "csv")
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try csvData.write(to: destination, options: .atomic)
            AccessibilityAnnouncer.announce(trf(.a11yAnnouncementExportedFormat, destination.lastPathComponent))
        } catch {
            _ = Alerts.ask(tr(.exportErrorTitle), error.localizedDescription, buttons: [tr(.close)], style: .critical)
        }
    }
}
