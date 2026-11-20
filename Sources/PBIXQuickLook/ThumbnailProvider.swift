import CoreGraphics
import Foundation
import PBIXKit
import QuickLookThumbnailing

/// Quick Look Thumbnail Extension cho tệp `.pbix` (`com.microsoft.powerbi.pbix`, US4, FR-030..FR-032).
@objc(PBIXThumbnailProvider)
final class PBIXThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let scale = max(1, request.scale)
        let maxSize = request.maximumSize
        let pixelSize = CGSize(width: max(128, maxSize.width * scale), height: max(128, maxSize.height * scale))

        let cgImage: CGImage?
        do {
            let summary = try PBIXQuickLookSummary.load(from: url)
            cgImage = PBIXQuickLookRenderer.renderThumbnail(summary: summary, size: pixelSize, dark: false)
        } catch {
            cgImage = PBIXQuickLookRenderer.renderError(fileName: url.lastPathComponent, message: error.localizedDescription, size: pixelSize, dark: false)
        }

        guard let cgImage else {
            handler(nil, nil)
            return
        }

        let contextSize = maxSize
        let reply = QLThumbnailReply(contextSize: contextSize) { context -> Bool in
            context.draw(cgImage, in: CGRect(origin: .zero, size: contextSize))
            return true
        }
        handler(reply, nil)
    }
}
