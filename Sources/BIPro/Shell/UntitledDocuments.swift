import AppKit
import Foundation
import PBIXKit
import SwiftUI

/// "File → Mới" (Phase F, T077, FR-053). Tài liệu mới là file `.pbix` trống (`NewDocument.blank()`) ghi vào thư mục tạm riêng của
/// BI Pro rồi mở như mọi file khác, nên mọi luồng sửa và lưu dùng chung. File ở thư mục này coi là "chưa có tên": lần lưu đầu luôn
/// hỏi nơi lưu (không bao giờ ghi vào bản tạm), xong thì mở bản đã lưu và bỏ bản tạm.
enum UntitledDocuments {
    static let fileName = "Không tên.pbix"

    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("BIPro-TaiLieuMoi", isDirectory: true)
    }

    /// Ghi tài liệu trống vào một thư mục con mới của `root`, trả đường dẫn. Bản tạm cũ hơn một ngày bị dọn.
    static func create(root: URL = root) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        purgeStale(root: root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent(fileName)
        try NewDocument.blank().write(to: url, options: .withoutOverwriting)
        return url
    }

    /// File nằm trong thư mục tài liệu mới (chưa lưu lần nào).
    static func isUntitled(_ url: URL?, root: URL = root) -> Bool {
        guard let url else { return false }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(base + "/")
    }

    /// Bỏ bản tạm sau khi đã lưu ra nơi khác.
    static func discard(_ url: URL, root: URL = root) {
        guard isUntitled(url, root: root) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func purgeStale(root: URL, olderThan age: TimeInterval = 86_400) {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for folder in folders {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > age { try? fm.removeItem(at: folder) }
        }
    }

    /// Kiểm tra có mở cửa sổ màn hình Khởi động khi khởi động app trực tiếp không kèm tệp `.pbix` hay không (T067/T073).
    static func shouldShowStartScreenOnLaunch(
        isDefaultLaunch: Bool,
        hasStartedOpening: Bool,
        openDocumentsCount: Int,
        hasVisibleWindow: Bool,
        isRunningTests: Bool = AppLaunchPolicy.isRunningTests
    ) -> Bool {
        AppLaunchPolicy.shouldOpenUntitledOnLaunch(
            isDefaultLaunch: isDefaultLaunch,
            hasStartedOpening: hasStartedOpening,
            openDocumentsCount: openDocumentsCount,
            hasVisibleWindow: hasVisibleWindow,
            isRunningTests: isRunningTests
        )
    }

    @MainActor private static var startWindow: NSWindow?

    /// Mở cửa sổ Màn hình Khởi động (`StartScreen`) khi chưa có tài liệu nào.
    @MainActor static func showStartScreen() {
        if let existing = startWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 960, height: 620)
        window.isReleasedWhenClosed = false
        window.center()
        let root = StartScreen(onDismiss: { [weak window] in
            window?.close()
        })
        .preferredColorScheme(AppPreferences.shared.preferredColorScheme)
        window.contentViewController = NSHostingController(rootView: root)
        startWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Lệnh "Mới" (⌘N) hoặc mở cửa sổ mặc định lúc khởi động: tạo tài liệu trống và đưa cửa sổ lên trước.
    @MainActor static func openNew() {
        startWindow?.close()
        DocumentOpenTracker.markOpened()
        do {
            let url = try create()
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
                if let error {
                    _ = Alerts.ask("Không mở được tài liệu mới", error.localizedDescription, buttons: ["Đóng"], style: .critical)
                    return
                }
                NSApp.activate(ignoringOtherApps: true)
                document?.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            }
        } catch {
            _ = Alerts.ask("Không tạo được tài liệu mới", "\(error)", buttons: ["Đóng"], style: .critical)
        }
    }
}
