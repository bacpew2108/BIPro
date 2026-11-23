import CoreGraphics
import CoreText
import Foundation

/// Bộ vẽ thuần CoreGraphics/CoreText cho Quick Look Thumbnail và Preview của tệp `.pbix` (US4, FR-031).
/// Nằm trong `PBIXKit` để `PBIXKitTests` kiểm chứng trực tiếp không cần Finder, và dùng chung với `.appex`.
public enum PBIXQuickLookRenderer {
    /// Vẽ ảnh thu nhỏ (Thumbnail) gồm sơ đồ bố cục trang đầu kèm huy hiệu `PBIX`.
    public static func renderThumbnail(summary: PBIXQuickLookSummary, size: CGSize, dark: Bool = false) -> CGImage? {
        let w = max(64, Int(size.width.rounded()))
        let h = max(64, Int(size.height.rounded()))
        guard let ctx = makeContext(width: w, height: h) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        let bg = dark ? rgb(0.11, 0.11, 0.12) : rgb(0.95, 0.95, 0.97)
        ctx.setFillColor(bg)
        ctx.fill(bounds)

        // Giấy trang báo cáo ở giữa
        let pad = CGFloat(min(w, h)) * 0.08
        let footerH = max(24, CGFloat(h) * 0.18)
        let cardRect = CGRect(x: pad, y: footerH + pad * 0.5, width: CGFloat(w) - pad * 2, height: CGFloat(h) - footerH - pad * 1.5)
        drawRoundedRect(ctx, rect: cardRect, radius: max(4, CGFloat(min(w, h)) * 0.03), fill: rgb(1, 1, 1), stroke: rgb(0, 0, 0, 0.12))

        if let page = summary.previewPage {
            drawPageWireframe(ctx, page: page, in: cardRect.insetBy(dx: 6, dy: 6), showTitles: w >= 240)
        }

        // Dải đáy với huy hiệu PBIX và thống kê ngắn
        let badgeW = max(38, CGFloat(w) * 0.24)
        let badgeH = max(18, footerH * 0.62)
        let badgeRect = CGRect(x: pad, y: (footerH - badgeH) / 2, width: badgeW, height: badgeH)
        drawRoundedRect(ctx, rect: badgeRect, radius: 5, fill: rgb(0.04, 0.52, 1.0), stroke: nil)
        drawText(ctx, "PBIX", in: badgeRect, fontSize: max(9, badgeH * 0.52), bold: true, color: rgb(1, 1, 1), alignment: .center)

        if w >= 180 {
            let infoRect = CGRect(x: badgeRect.maxX + 8, y: badgeRect.minY, width: CGFloat(w) - badgeRect.maxX - pad - 8, height: badgeH)
            let stats = "\(summary.visiblePageCount)p · \(summary.tableCount)t · \(summary.measureCount)m"
            let labelColor = dark ? rgb(0.75, 0.75, 0.78) : rgb(0.35, 0.35, 0.38)
            drawText(ctx, stats, in: infoRect, fontSize: max(9, badgeH * 0.48), bold: false, color: labelColor, alignment: .right)
        }

        return ctx.makeImage()
    }

    /// Vẽ trang xem trước (Preview) chi tiết: tiêu đề, thống kê mô hình, danh sách trang và sơ đồ trang đầu.
    public static func renderPreview(summary: PBIXQuickLookSummary, size: CGSize = CGSize(width: 900, height: 640), dark: Bool = false) -> CGImage? {
        let w = max(360, Int(size.width.rounded()))
        let h = max(260, Int(size.height.rounded()))
        guard let ctx = makeContext(width: w, height: h) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        let bg = dark ? rgb(0.11, 0.11, 0.12) : rgb(0.95, 0.95, 0.97)
        let cardBg = dark ? rgb(0.17, 0.17, 0.18) : rgb(1, 1, 1)
        let stroke = dark ? rgb(1, 1, 1, 0.12) : rgb(0, 0, 0, 0.10)
        let fg = dark ? rgb(0.96, 0.96, 0.97) : rgb(0.11, 0.11, 0.12)
        let fg2 = dark ? rgb(0.68, 0.68, 0.70) : rgb(0.39, 0.39, 0.40)

        ctx.setFillColor(bg)
        ctx.fill(bounds)

        let m: CGFloat = 24
        // CoreGraphics gốc toạ độ ở góc dưới-trái
        let headerH: CGFloat = 58
        let headerY = CGFloat(h) - m - headerH

        // Huy hiệu PBIX + Tên tệp
        let badgeRect = CGRect(x: m, y: headerY + 14, width: 54, height: 28)
        drawRoundedRect(ctx, rect: badgeRect, radius: 6, fill: rgb(0.04, 0.52, 1.0), stroke: nil)
        drawText(ctx, "PBIX", in: badgeRect, fontSize: 13, bold: true, color: rgb(1, 1, 1), alignment: .center)

        drawText(ctx, summary.fileName,
                 in: CGRect(x: badgeRect.maxX + 12, y: headerY + 24, width: CGFloat(w) - badgeRect.maxX - m - 12, height: 26),
                 fontSize: 19, bold: true, color: fg, alignment: .left)
        let sub = lt("\(summary.formatLabel) · \(summary.visiblePageCount) trang hiển thị / \(summary.pages.count) trang", "\(summary.formatLabel) · \(summary.visiblePageCount) visible pages / \(summary.pages.count) pages")
        drawText(ctx, sub,
                 in: CGRect(x: badgeRect.maxX + 12, y: headerY + 4, width: CGFloat(w) - badgeRect.maxX - m - 12, height: 18),
                 fontSize: 12, bold: false, color: fg2, alignment: .left)

        // 4 thẻ thống kê mô hình
        let statsH: CGFloat = 62
        let statsY = headerY - 12 - statsH
        let statGap: CGFloat = 12
        let statW = (CGFloat(w) - m * 2 - statGap * 3) / 4
        let stats: [(String, String)] = [
            ("\(summary.tableCount)", lt("Bảng", "Tables")),
            ("\(summary.columnCount)", lt("Cột", "Columns")),
            ("\(summary.measureCount)", "Measure"),
            ("\(summary.relationshipCount)", lt("Quan hệ", "Relationships")),
        ]
        for (i, item) in stats.enumerated() {
            let r = CGRect(x: m + CGFloat(i) * (statW + statGap), y: statsY, width: statW, height: statsH)
            drawRoundedRect(ctx, rect: r, radius: 8, fill: cardBg, stroke: stroke)
            drawText(ctx, item.0, in: CGRect(x: r.minX + 12, y: r.minY + 24, width: r.width - 24, height: 26),
                     fontSize: 20, bold: true, color: rgb(0.04, 0.52, 1.0), alignment: .left)
            drawText(ctx, item.1, in: CGRect(x: r.minX + 12, y: r.minY + 8, width: r.width - 24, height: 16),
                     fontSize: 11, bold: false, color: fg2, alignment: .left)
        }

        // Phần dưới: trái = danh sách trang, phải = sơ đồ bố cục trang đầu
        let bodyY = m
        let bodyH = max(120, statsY - 16 - m)
        let sidebarW: CGFloat = min(210, CGFloat(w) * 0.25)
        let sidebarRect = CGRect(x: m, y: bodyY, width: sidebarW, height: bodyH)
        drawRoundedRect(ctx, rect: sidebarRect, radius: 8, fill: cardBg, stroke: stroke)
        drawText(ctx, "TRANG BÁO CÁO", in: CGRect(x: sidebarRect.minX + 12, y: sidebarRect.maxY - 28, width: sidebarW - 24, height: 16),
                 fontSize: 10, bold: true, color: fg2, alignment: .left)

        var rowY = sidebarRect.maxY - 54
        for (idx, p) in summary.pages.prefix(12).enumerated() where rowY > sidebarRect.minY + 8 {
            let isFirst = (idx == summary.activePageIndex)
            let rowRect = CGRect(x: sidebarRect.minX + 8, y: rowY, width: sidebarW - 16, height: 24)
            if isFirst {
                drawRoundedRect(ctx, rect: rowRect, radius: 5, fill: rgb(0.04, 0.52, 1.0, 0.14), stroke: nil)
            }
            let prefix = p.isHidden ? "◌ " : "• "
            drawText(ctx, "\(prefix)\(p.name)", in: rowRect.insetBy(dx: 8, dy: 3),
                     fontSize: 12, bold: isFirst, color: p.isHidden ? fg2 : fg, alignment: .left)
            rowY -= 26
        }

        let canvasRect = CGRect(x: sidebarRect.maxX + 14, y: bodyY, width: CGFloat(w) - sidebarRect.maxX - 14 - m, height: bodyH)
        drawRoundedRect(ctx, rect: canvasRect, radius: 8, fill: cardBg, stroke: stroke)
        if let page = summary.previewPage {
            drawText(ctx, lt("Bố cục trang: \(page.name) (\(Int(page.width))×\(Int(page.height)))", "Page layout: \(page.name) (\(Int(page.width))×\(Int(page.height)))"),
                     in: CGRect(x: canvasRect.minX + 14, y: canvasRect.maxY - 28, width: canvasRect.width - 28, height: 16),
                     fontSize: 11, bold: true, color: fg2, alignment: .left)
            let wireArea = CGRect(x: canvasRect.minX + 14, y: canvasRect.minY + 14, width: canvasRect.width - 28, height: canvasRect.height - 48)
            // Giữ tỉ lệ khung hình của trang báo cáo
            let aspect = CGFloat(page.width / max(1, page.height))
            let fitted: CGRect
            if wireArea.width / wireArea.height > aspect {
                let fw = wireArea.height * aspect
                fitted = CGRect(x: wireArea.midX - fw / 2, y: wireArea.minY, width: fw, height: wireArea.height)
            } else {
                let fh = wireArea.width / aspect
                fitted = CGRect(x: wireArea.minX, y: wireArea.midY - fh / 2, width: wireArea.width, height: fh)
            }
            drawRoundedRect(ctx, rect: fitted, radius: 4, fill: rgb(1, 1, 1), stroke: rgb(0, 0, 0, 0.15))
            drawPageWireframe(ctx, page: page, in: fitted.insetBy(dx: 4, dy: 4), showTitles: true)
        } else {
            drawText(ctx, summary.modelError ?? lt("Tệp chưa có trang báo cáo.", "The file has no report pages yet."),
                     in: canvasRect.insetBy(dx: 16, dy: 16), fontSize: 13, bold: false, color: fg2, alignment: .center)
        }

        return ctx.makeImage()
    }

    /// Vẽ thẻ thông báo lỗi an toàn khi tệp `.pbix` hỏng (FR-032).
    public static func renderError(fileName: String, message: String, size: CGSize = CGSize(width: 640, height: 360), dark: Bool = false) -> CGImage? {
        let w = max(200, Int(size.width.rounded()))
        let h = max(140, Int(size.height.rounded()))
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        ctx.setFillColor(dark ? rgb(0.11, 0.11, 0.12) : rgb(0.95, 0.95, 0.97))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

        let card = CGRect(x: 24, y: 24, width: CGFloat(w - 48), height: CGFloat(h - 48))
        drawRoundedRect(ctx, rect: card, radius: 10, fill: dark ? rgb(0.17, 0.17, 0.18) : rgb(1, 1, 1), stroke: rgb(1, 0.27, 0.23, 0.45))
        drawText(ctx, fileName, in: CGRect(x: card.minX + 16, y: card.midY + 10, width: card.width - 32, height: 26),
                 fontSize: 16, bold: true, color: dark ? rgb(0.96, 0.96, 0.97) : rgb(0.11, 0.11, 0.12), alignment: .center)
        drawText(ctx, lt("Không thể xem trước tệp .pbix: \(message)", "Couldn't preview the .pbix file: \(message)"),
                 in: CGRect(x: card.minX + 16, y: card.midY - 30, width: card.width - 32, height: 32),
                 fontSize: 12, bold: false, color: rgb(0.9, 0.25, 0.22), alignment: .center)
        return ctx.makeImage()
    }

    // MARK: - Helpers

    private static func drawPageWireframe(_ ctx: CGContext, page: PBIXQuickLookSummary.PageOutline, in rect: CGRect, showTitles: Bool) {
        let sx = rect.width / CGFloat(max(1, page.width))
        let sy = rect.height / CGFloat(max(1, page.height))
        for box in page.visuals {
            let vx = rect.minX + CGFloat(box.x) * sx
            // Lật trục Y (PBIR gốc trên-trái, CoreGraphics gốc dưới-trái)
            let vw = max(2, CGFloat(box.width) * sx)
            let vh = max(2, CGFloat(box.height) * sy)
            let vy = rect.maxY - (CGFloat(box.y) * sy) - vh
            let r = CGRect(x: vx, y: vy, width: vw, height: vh).intersection(rect)
            guard !r.isNull && r.width > 1 && r.height > 1 else { continue }

            let (fill, stroke) = visualColors(for: box.type)
            drawRoundedRect(ctx, rect: r, radius: min(3, min(r.width, r.height) * 0.15), fill: fill, stroke: stroke)

            if showTitles, r.width > 42, r.height > 16, let title = box.title, !title.isEmpty {
                drawText(ctx, title, in: r.insetBy(dx: 3, dy: 2), fontSize: min(9, max(6.5, r.height * 0.28)),
                         bold: false, color: rgb(0.18, 0.18, 0.22), alignment: .left)
            }
        }
    }

    private static func visualColors(for type: String) -> (fill: CGColor, stroke: CGColor) {
        switch type {
        case "card", "cardVisual", "kpi", "multiRowCard":
            return (rgb(0.04, 0.52, 1.0, 0.14), rgb(0.04, 0.52, 1.0, 0.55))
        case "slicer", "advancedSlicerVisual", "listSlicer":
            return (rgb(0.37, 0.36, 0.90, 0.13), rgb(0.37, 0.36, 0.90, 0.45))
        case "pivotTable", "matrix", "tableEx", "table":
            return (rgb(0.19, 0.69, 0.78, 0.14), rgb(0.19, 0.69, 0.78, 0.50))
        case "textbox", "shape", "basicShape", "image", "actionButton":
            return (rgb(0.55, 0.55, 0.58, 0.08), rgb(0.55, 0.55, 0.58, 0.25))
        default:
            return (rgb(0.20, 0.78, 0.35, 0.14), rgb(0.20, 0.78, 0.35, 0.50))
        }
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
    }

    private static func drawRoundedRect(_ ctx: CGContext, rect: CGRect, radius: CGFloat, fill: CGColor?, stroke: CGColor?) {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        if let fill {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }
        if let stroke {
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
    }

    private enum Align { case left, center, right }

    private static func drawText(_ ctx: CGContext, _ text: String, in rect: CGRect, fontSize: CGFloat, bold: Bool, color: CGColor, alignment: Align) {
        let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        guard let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(attrStr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        let x: CGFloat
        switch alignment {
        case .left: x = rect.minX
        case .center: x = rect.midX - min(width, rect.width) / 2
        case .right: x = max(rect.minX, rect.maxX - width)
        }
        let y = rect.midY - (ascent - descent) / 2

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
