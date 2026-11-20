import CoreGraphics
import Foundation
import ImageIO
import PBIXKit
import Testing
import UniformTypeIdentifiers

@Suite("PhaseG — PBIXQuickLookSummary & Renderer")
struct QuickLookSummaryTests {
    private static let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/g-out/ql", isDirectory: true)

    @Test("Đọc nhanh tài liệu trống và vẽ ảnh Thumbnail + Preview hợp lệ (Sáng & Tối)")
    func summaryAndRendererOnEmptyDocument() throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        let pbix = try PBIXFile(data: try NewDocument.blank())
        let summary = try PBIXQuickLookSummary.load(from: pbix, fileName: "Empty.pbix")
        #expect(summary.fileName == "Empty.pbix")
        #expect(summary.hasDataModel == true)
        #expect(summary.pages.count >= 1)

        let thumb = try #require(PBIXQuickLookRenderer.renderThumbnail(summary: summary, size: CGSize(width: 256, height: 256), dark: false))
        #expect(thumb.width == 256 && thumb.height == 256)

        let previewLight = try #require(PBIXQuickLookRenderer.renderPreview(summary: summary, size: CGSize(width: 900, height: 640), dark: false))
        let previewDark = try #require(PBIXQuickLookRenderer.renderPreview(summary: summary, size: CGSize(width: 900, height: 640), dark: true))
        #expect(previewLight.width == 900 && previewDark.height == 640)

        let errImg = try #require(PBIXQuickLookRenderer.renderError(fileName: "Broken.pbix", message: "ZIP hỏng"))
        #expect(errImg.width == 640)
    }

    @Test("File .pbix hỏng báo lỗi an toàn, không sập")
    func corruptFileThrowsSafely() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).pbix")
        try Data("not a valid zip file".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(throws: Error.self) {
            _ = try PBIXQuickLookSummary.load(from: tmp)
        }
    }

    @Test("Nặng (SC-004): Đọc Nhom6_work.pbix dưới 1 giây (release) và xuất ảnh thumbnail/preview")
    func heavyNhom6QuickLookUnderOneSecond() throws {
        guard ProcessInfo.processInfo.environment["BIPRO_HEAVY"] == "1" else { return }
        guard let url = Self.findSample("Nhom6_work.pbix") else { return }
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)

        let clock = ContinuousClock()
        var loaded: PBIXQuickLookSummary?
        let elapsed = try clock.measure {
            loaded = try PBIXQuickLookSummary.load(from: url)
        }
        let summary = try #require(loaded)
        #expect(summary.formatLabel == "PBIR")
        #expect(summary.visiblePageCount >= 3)
        #expect(summary.tableCount >= 5)
        #expect(summary.measureCount >= 20)
        #expect(summary.relationshipCount >= 5)

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        // Release phải < 1.0 s (SC-004); debug cho phép chậm hơn
        #if !DEBUG
        #expect(seconds < 1.0, "PBIXQuickLookSummary.load(Nhom6) mất \(seconds)s >= 1.0s")
        #endif

        let thumb = try #require(PBIXQuickLookRenderer.renderThumbnail(summary: summary, size: CGSize(width: 512, height: 512), dark: false))
        let previewLight = try #require(PBIXQuickLookRenderer.renderPreview(summary: summary, dark: false))
        let previewDark = try #require(PBIXQuickLookRenderer.renderPreview(summary: summary, dark: true))
        try Self.writePNG(thumb, to: Self.outputDir.appendingPathComponent("nhom6-thumb.png"))
        try Self.writePNG(previewLight, to: Self.outputDir.appendingPathComponent("nhom6-preview-light.png"))
        try Self.writePNG(previewDark, to: Self.outputDir.appendingPathComponent("nhom6-preview-dark.png"))

        // Kiểm thêm file định dạng cũ (nếu có) và w8.3
        if let legacy = Self.findSample("tuan6.2.pbix") {
            let legacySum = try PBIXQuickLookSummary.load(from: legacy)
            #expect(legacySum.pages.count >= 1)
            let img = try #require(PBIXQuickLookRenderer.renderThumbnail(summary: legacySum, size: CGSize(width: 256, height: 256)))
            try Self.writePNG(img, to: Self.outputDir.appendingPathComponent("legacy-thumb.png"))
        }
        if let w83 = Self.findSample("w8.3.pbix") {
            let wSum = try PBIXQuickLookSummary.load(from: w83)
            #expect(wSum.pages.count >= 1)
        }
    }

    private static func findSample(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for rel in ["Downloads/bipro-golden/\(name)", "Downloads/\(name)"] {
            let u = home.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
