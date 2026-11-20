import AppKit
import Foundation
import PBIXKit
import PDFKit
import Testing
@testable import BIPro

@Suite("PhaseG — ReportPageExporter (PNG & PDF)")
@MainActor
struct ExportRenderTests {
    private static let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/g-out/export", isDirectory: true)

    @Test("PNG 1× và 2× đúng kích thước pixel và PDF nhiều trang đúng số trang và kích thước")
    func syntheticPNGAndMultiPagePDF() throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        let workspace = try Workspace(data: try Self.minimalPBIXData())
        let interaction = ReportInteraction(workspace: workspace)

        let page1 = ReportPage(id: "p1", displayName: "Trang 1", width: 640, height: 360, isHidden: false, objects: ObjectProperties(.object([:])), visuals: [])
        let page2 = ReportPage(id: "p2", displayName: "Trang 2", width: 800, height: 600, isHidden: false, objects: ObjectProperties(.object([:])), visuals: [])

        let png1 = try ReportPageExporter.renderPNG(page: page1, workspace: workspace, preloaded: [:], interaction: interaction, scale: .x1)
        #expect(png1.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        let rep1 = try #require(NSBitmapImageRep(data: png1))
        #expect(rep1.pixelsWide == 640)
        #expect(rep1.pixelsHigh == 360)

        let png2 = try ReportPageExporter.renderPNG(page: page1, workspace: workspace, preloaded: [:], interaction: interaction, scale: .x2)
        let rep2 = try #require(NSBitmapImageRep(data: png2))
        #expect(rep2.pixelsWide == 1280)
        #expect(rep2.pixelsHigh == 720)

        let pdfData = try ReportPageExporter.renderPDF(pages: [page1, page2], workspace: workspace, preloadedByPage: [:], interaction: interaction)
        #expect(String(data: pdfData.prefix(5), encoding: .ascii) == "%PDF-")
        let doc = try #require(PDFDocument(data: pdfData))
        #expect(doc.pageCount == 2)
        let b0 = try #require(doc.page(at: 0)).bounds(for: PDFDisplayBox.mediaBox)
        let b1 = try #require(doc.page(at: 1)).bounds(for: PDFDisplayBox.mediaBox)
        #expect(Int(b0.width.rounded()) == 640 && Int(b0.height.rounded()) == 360)
        #expect(Int(b1.width.rounded()) == 800 && Int(b1.height.rounded()) == 600)

        #expect(throws: ExportError.noVisiblePages) {
            _ = try ReportPageExporter.renderPDF(pages: [], workspace: workspace, preloadedByPage: [:], interaction: interaction)
        }
    }

    @Test("Nặng (SC-001): Xuất PNG 2× trang D1 và PDF tất cả trang hiển thị trên Nhom6_work.pbix")
    func heavyNhom6ExportPNGAndPDF() async throws {
        guard ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1" else { return }
        guard let url = Self.nhom6URL() else { return }
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)

        let workspace = try Workspace(data: try Data(contentsOf: url))
        let interaction = ReportInteraction(workspace: workspace)
        let visiblePages = workspace.visiblePages
        #expect(!visiblePages.isEmpty)

        var preloadedByPage: [String: [String: LiveVisualData]] = [:]
        for page in visiblePages {
            preloadedByPage[page.id] = await ReportPageExporter.preload(page: page, interaction: interaction)
        }

        // PNG 2× cho trang đầu (D1)
        let first = visiblePages[0]
        let pngData = try ReportPageExporter.renderPNG(
            page: first, workspace: workspace, preloaded: preloadedByPage[first.id] ?? [:], interaction: interaction, scale: .x2
        )
        let pngURL = Self.outputDir.appendingPathComponent("nhom6-d1-2x.png")
        try pngData.write(to: pngURL)
        let rep = try #require(NSBitmapImageRep(data: pngData))
        #expect(rep.pixelsWide == Int((first.width * 2).rounded()))
        #expect(rep.pixelsHigh == Int((first.height * 2).rounded()))
        #expect(pngData.count > 50_000, "Ảnh PNG 2× của Nhom6 không được trống")

        // PDF tất cả trang hiển thị
        let pdfData = try ReportPageExporter.renderPDF(
            pages: visiblePages, workspace: workspace, preloadedByPage: preloadedByPage, interaction: interaction
        )
        let pdfURL = Self.outputDir.appendingPathComponent("nhom6-all-visible.pdf")
        try pdfData.write(to: pdfURL)
        let doc = try #require(PDFDocument(data: pdfData))
        #expect(doc.pageCount == visiblePages.count)
        for (i, page) in visiblePages.enumerated() {
            let box = try #require(doc.page(at: i)).bounds(for: PDFDisplayBox.mediaBox)
            #expect(Int(box.width.rounded()) == Int(page.width.rounded()))
            #expect(Int(box.height.rounded()) == Int(page.height.rounded()))
        }
    }

    private static func minimalPBIXData() throws -> Data {
        try NewDocument.blank()
    }

    private static func nhom6URL() -> URL? {
        if let env = ProcessInfo.processInfo.environment["BIPRO_NHOM6"], FileManager.default.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for rel in ["Downloads/bipro-golden/Nhom6_work.pbix", "Downloads/Nhom6_work.pbix"] {
            let u = home.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}
