import AppKit
import CoreGraphics
import Foundation
import PBIXKit
import PDFKit
import SwiftUI

/// Phạm vi xuất PDF (FR-002).
enum ExportPDFScope: String, CaseIterable, Sendable, Equatable {
    /// Mặc định như Power BI Desktop: mọi trang không ẩn.
    case allVisiblePages
    /// Chỉ trang đang đứng (kể cả khi người dùng đang xem một trang ẩn).
    case currentPage
}

/// Tỉ lệ xuất ảnh PNG (FR-003).
enum ExportPNGScale: Double, CaseIterable, Sendable, Equatable {
    case x1 = 1.0
    case x2 = 2.0
}

/// Bề mặt trang báo cáo thuần SwiftUI dành riêng cho kết xuất tĩnh (PNG / PDF):
/// không dính khung chọn, tay nắm Sửa, lớp hover AppKit hay visual bị ẩn.
struct ExportableReportPageView: View {
    let workspace: Workspace
    let page: ReportPage
    let interaction: ReportInteraction
    let preloaded: [String: LiveVisualData]

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageBackground
            ForEach(page.visuals.filter { !interaction.isHidden($0) }) { visual in
                VisualContainerView(
                    workspace: workspace,
                    page: page,
                    visual: visual,
                    interaction: interaction,
                    navigate: { _ in },
                    preloaded: preloaded[visual.id],
                    isExporting: true
                )
                .frame(width: visual.width, height: visual.height)
                .offset(x: visual.x, y: visual.y)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }

    private var pageBackground: some View {
        let color = workspace.theme.color(page.objects.color("background", "color"))
            ?? workspace.theme.background.flatMap(Color.init(hex:)) ?? .white
        return Rectangle()
            .fill(DS.Palette.documentPaper)
            .overlay(Rectangle().fill(color.opacity(page.objects.opacity("background"))))
    }
}

/// Bộ kết xuất trang báo cáo ra PNG (1×/2×) và PDF nhiều trang (US1, FR-002, FR-003).
@MainActor
enum ReportPageExporter {
    /// Nạp sẵn dữ liệu cho tất cả visual hiển thị của một trang (song song, bỏ qua visual không có query).
    static func preload(page: ReportPage, interaction: ReportInteraction) async -> [String: LiveVisualData] {
        guard interaction.isAvailable else { return [:] }
        let state = interaction.state(for: page)
        let visuals = page.visuals.filter { !interaction.isHidden($0) && VisualContentView.liveTypes.contains($0.type) }
        var out: [String: LiveVisualData] = [:]
        // Chạy tuần tự qua actor/interaction hoặc song song an toàn qua TaskGroup
        await withTaskGroup(of: (String, LiveVisualData?).self) { group in
            for visual in visuals {
                group.addTask { @MainActor in
                    let loaded = try? await interaction.load(page: page, visual: visual, state: state)
                    return (visual.id, loaded)
                }
            }
            for await (id, data) in group {
                if let data { out[id] = data }
            }
        }
        return out
    }

    /// Kết xuất một trang báo cáo ra PNG sắc nét theo đúng tỉ lệ `scale` (1× hoặc 2×).
    static func renderPNG(
        page: ReportPage,
        workspace: Workspace,
        preloaded: [String: LiveVisualData],
        interaction: ReportInteraction,
        scale: ExportPNGScale
    ) throws -> Data {
        let view = ExportableReportPageView(workspace: workspace, page: page, interaction: interaction, preloaded: preloaded)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: page.width, height: page.height)
        renderer.scale = scale.rawValue
        guard let cgImage = renderer.cgImage else {
            throw ExportError.renderFailed(biN("Không thể kết xuất ảnh PNG cho trang \(page.displayName).", "Couldn't render a PNG image for page \(page.displayName)."))
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.renderFailed(biN("Không thể mã hoá dữ liệu PNG cho trang \(page.displayName).", "Couldn't encode PNG data for page \(page.displayName)."))
        }
        return pngData
    }

    /// Kết xuất danh sách trang báo cáo ra một tệp PDF nhiều trang (đúng kích thước từng trang, vectơ sắc nét).
    static func renderPDF(
        pages: [ReportPage],
        workspace: Workspace,
        preloadedByPage: [String: [String: LiveVisualData]],
        interaction: ReportInteraction,
        onPageProgress: ((Int, Int) -> Void)? = nil
    ) throws -> Data {
        guard !pages.isEmpty else { throw ExportError.noVisiblePages }
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw ExportError.renderFailed(biN("Không thể khởi tạo bộ ghi PDF.", "Couldn't create the PDF writer."))
        }
        var initialBox = CGRect(x: 0, y: 0, width: pages[0].width, height: pages[0].height)
        guard let context = CGContext(consumer: consumer, mediaBox: &initialBox, nil) else {
            throw ExportError.renderFailed(biN("Không thể tạo ngữ cảnh vẽ PDF.", "Couldn't create the PDF drawing context."))
        }

        for (index, page) in pages.enumerated() {
            onPageProgress?(index + 1, pages.count)
            let preloaded = preloadedByPage[page.id] ?? [:]
            let view = ExportableReportPageView(workspace: workspace, page: page, interaction: interaction, preloaded: preloaded)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: page.width, height: page.height)
            renderer.scale = 2.0

            var pageBox = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            let pageInfo: [CFString: Any] = [
                kCGPDFContextMediaBox: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)
            ]
            context.beginPDFPage(pageInfo as CFDictionary)
            renderer.render { _, draw in
                draw(context)
            }
            context.endPDFPage()
        }
        context.closePDF()

        let result = pdfData as Data
        guard PDFDocument(data: result)?.pageCount == pages.count else {
            throw ExportError.renderFailed(biN("Tệp PDF xuất ra không hợp lệ.", "The exported PDF file is not valid."))
        }
        return result
    }
}
