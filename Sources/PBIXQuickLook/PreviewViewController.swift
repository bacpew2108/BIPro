import AppKit
import PBIXKit
import QuickLookUI

/// Quick Look Preview Extension cho tệp `.pbix` (`com.microsoft.powerbi.pbix`, US4, FR-030..FR-032).
@objc(PBIXPreviewViewController)
final class PBIXPreviewViewController: NSViewController, QLPreviewingController {
    private let imageView = NSImageView()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: root.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root
        self.preferredContentSize = NSSize(width: 900, height: 640)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let isDark = await MainActor.run {
            self.view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let cgImage: CGImage?
        do {
            let summary = try PBIXQuickLookSummary.load(from: url)
            cgImage = PBIXQuickLookRenderer.renderPreview(summary: summary, size: CGSize(width: 900, height: 640), dark: isDark)
        } catch {
            cgImage = PBIXQuickLookRenderer.renderError(fileName: url.lastPathComponent, message: error.localizedDescription, dark: isDark)
        }
        await MainActor.run {
            if let cgImage {
                self.imageView.image = NSImage(cgImage: cgImage, size: NSSize(width: 900, height: 640))
            }
        }
    }
}
