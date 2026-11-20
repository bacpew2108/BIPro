import AppKit
import PBIXKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Hộp thoại

enum Alerts {
    /// Hiện hộp thoại và trả về chỉ số nút bấm (0 là nút đầu).
    @MainActor
    static func ask(_ title: String, _ detail: String, buttons: [String], style: NSAlert.Style = .warning) -> Int {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = detail
        for button in buttons { alert.addButton(withTitle: button) }
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}

// MARK: - Lưu

extension DocumentState {
    /// Lưu vào file đang mở. File dưới `~/Downloads` (bản gốc chỉ đọc) hoặc không có đường dẫn thì chuyển sang
    /// Lưu thành. Trả `true` khi không còn thay đổi chưa lưu (đã lưu, hoặc không có gì để lưu).
    @discardableResult
    func save() -> Bool {
        // Tài liệu mới (T077): lần lưu đầu luôn hỏi nơi lưu, kể cả khi chưa sửa gì; không ghi vào bản tạm.
        if isUntitled { return saveAs() }
        guard layout.isDirty else { return true }
        guard let url = fileURL else { return saveAs() }
        if DocumentSaver.isReadOnlyOriginal(url, roots: DocumentSaver.defaultReadOnlyRoots()) {
            let choice = Alerts.ask("File trong Downloads là bản gốc, chỉ đọc",
                                    "BI Pro không ghi vào file gốc ở Downloads. Hãy lưu thành bản mới ở nơi khác (ví dụ Desktop hoặc Documents).",
                                    buttons: ["Lưu thành…", "Huỷ"], style: .informational)
            return choice == 0 ? saveAs() : false
        }
        return write(to: url, expectedStamp: openedStamp)
    }

    /// Hộp thoại Lưu thành rồi ghi bản mới, mở nó trong cửa sổ mới và đóng cửa sổ này.
    @discardableResult
    func saveAs() -> Bool {
        guard let source = fileURL else {
            _ = Alerts.ask("Không lưu được", "Báo cáo này không có file nguồn để lưu thành bản mới.", buttons: ["Đóng"], style: .critical)
            return false
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pbix]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = source.lastPathComponent
        let readOnly = DocumentSaver.isReadOnlyOriginal(source, roots: DocumentSaver.defaultReadOnlyRoots())
        panel.directoryURL = readOnly || isUntitled
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            : source.deletingLastPathComponent()
        panel.message = isUntitled ? "Lưu báo cáo mới" : "Lưu bản sao đã sửa của báo cáo"
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        if isUntitled {
            // Hộp thoại hệ thống đã hỏi khi trùng tên file có sẵn; không bao giờ ghi vào chính bản tạm.
            guard !UntitledDocuments.isUntitled(destination) else {
                _ = Alerts.ask("Không lưu được", "Hãy chọn một thư mục khác thư mục tạm của tài liệu mới.", buttons: ["Đóng"], style: .critical)
                return false
            }
            do {
                try DocumentSaver.saveUntitled(editor: layout, source: source, to: destination)
            } catch {
                _ = Alerts.ask("Không lưu được", "\(error)", buttons: ["Đóng"], style: .critical)
                return false
            }
            NSDocumentController.shared.openDocument(withContentsOf: destination, display: true) { _, _, _ in }
            window?.close()
            UntitledDocuments.discard(source)
            return true
        }
        let sameFile = destination.standardizedFileURL == source.standardizedFileURL
        guard write(to: destination, expectedStamp: openedStamp) else { return false }
        if !sameFile {
            NSDocumentController.shared.openDocument(withContentsOf: destination, display: true) { _, _, _ in }
            window?.close()
        }
        return true
    }

    /// Tài liệu tạo bằng "File → Mới" chưa lưu lần nào.
    var isUntitled: Bool { UntitledDocuments.isUntitled(fileURL) }

    private func write(to destination: URL, expectedStamp: FileStamp?) -> Bool {
        guard let source = fileURL else { return false }
        do {
            let outcome = try DocumentSaver.save(editor: layout, source: source, to: destination, expectedStamp: expectedStamp)
            if destination.standardizedFileURL == source.standardizedFileURL { openedStamp = outcome.newStamp }
            AccessibilityAnnouncer.announce(trf(.a11yAnnouncementSavedFormat, destination.lastPathComponent))
            return true
        } catch SaveError.modifiedExternally {
            // File đã bị chương trình khác đổi: cho chọn.
            switch Alerts.ask("File đã bị thay đổi bởi chương trình khác",
                              "Nếu ghi, các thay đổi bố cục của bạn được áp lên file hiện tại trên đĩa (phần khác của file giữ nguyên như đang có).",
                              buttons: ["Ghi", "Lưu thành…", "Huỷ"]) {
            case 0:
                return write(to: destination, expectedStamp: nil)
            case 1:
                return saveAs()
            default:
                return false
            }
        } catch let error as SaveError {
            if case .readOnlyOriginal = error {
                let choice = Alerts.ask("File trong Downloads là bản gốc, chỉ đọc", "\(error)", buttons: ["Lưu thành…", "Huỷ"], style: .informational)
                return choice == 0 ? saveAs() : false
            }
            if case .writeFailed = error {
                // Không ghi được vào vị trí này (chỉ đọc, hết chỗ…): cho lưu thành bản mới ở nơi khác.
                let choice = Alerts.ask("Không ghi được vào vị trí này", "\(error)", buttons: ["Lưu thành…", "Đóng"], style: .critical)
                return choice == 0 ? saveAs() : false
            }
            _ = Alerts.ask("Không lưu được", "\(error)", buttons: ["Đóng"], style: .critical)
            return false
        } catch {
            _ = Alerts.ask("Không lưu được", error.localizedDescription, buttons: ["Đóng"], style: .critical)
            return false
        }
    }

    /// Hỏi lưu khi còn thay đổi chưa lưu. Trả `true` nếu được phép đóng (đã lưu hoặc người dùng chọn không lưu).
    func confirmClose() -> Bool {
        guard layout.isDirty else { return true }
        switch Alerts.ask("Lưu thay đổi trong “\(fileName)”?",
                          "Bố cục đã sửa sẽ mất nếu bạn không lưu.", buttons: ["Lưu", "Không lưu", "Huỷ"]) {
        case 0: return save()
        case 1: return true
        default: return false
        }
    }
}

// MARK: - Danh sách tài liệu đang mở (để hỏi lưu khi thoát)

@MainActor
final class DocumentRegistry {
    static let shared = DocumentRegistry()
    private var boxes: [WeakBox] = []

    private struct WeakBox { weak var state: DocumentState? }

    func add(_ state: DocumentState) {
        boxes.removeAll { $0.state == nil }
        boxes.append(WeakBox(state: state))
    }

    var dirtyDocuments: [DocumentState] { boxes.compactMap(\.state).filter { $0.layout.isDirty } }
}

// MARK: - Uỷ quyền ứng dụng: hỏi lưu khi thoát

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppPreferences.shared.applyAppearance()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            for document in DocumentRegistry.shared.dirtyDocuments {
                document.window?.makeKeyAndOrderFront(nil)
                if !document.confirmClose() { return .terminateCancel }
            }
            return .terminateNow
        }
    }
}

// MARK: - Cửa sổ

/// Chặn đóng cửa sổ khi còn thay đổi chưa lưu. Mọi selector khác chuyển cho uỷ quyền gốc của SwiftUI.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    weak var state: DocumentState?
    private var closing = false

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closing { return original?.windowShouldClose?(sender) ?? true }
        guard let state else { return original?.windowShouldClose?(sender) ?? true }
        let allowed = MainActor.assumeIsolated { state.confirmClose() }
        if allowed {
            closing = true
            return original?.windowShouldClose?(sender) ?? true
        }
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }
}

/// Nối tài liệu với cửa sổ của nó: chấm "chưa lưu", hỏi khi đóng, và giữ tham chiếu cửa sổ.
struct DocumentWindowBridge: NSViewRepresentable {
    let state: DocumentState
    let isDirty: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let state = state, isDirty = isDirty
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.isDocumentEdited = isDirty
            state.window = window
            if !(window.delegate is WindowCloseGuard) {
                let guardian = WindowCloseGuard()
                guardian.original = window.delegate
                guardian.state = state
                window.delegate = guardian
                objc_setAssociatedObject(window, &DocumentWindowBridge.guardKey, guardian, .OBJC_ASSOCIATION_RETAIN)
            }
        }
    }

    nonisolated(unsafe) private static var guardKey: UInt8 = 0
}

// MARK: - Lệnh menu Lưu

struct SaveCommands: Commands {
    @FocusedValue(\.documentState) private var state

    var body: some Commands {
        // Thay nhóm `.saveItem` làm mất mục "Mở gần đây" của hệ thống, nên dựng lại bằng danh sách riêng.
        // Không được chạm `NSDocumentController.shared` ở đây: nó chạy trước khi SwiftUI dựng bộ điều khiển tài liệu
        // của nó và làm app sập lúc khởi động.
        // Nhóm "New/Open" mặc định của DocumentGroup chỉ xem có mục "New" không dùng được: thay bằng "Mới" (tài liệu trống, T077) và "Mở…".
        CommandGroup(replacing: .newItem) {
            Button(tr(.menuNew)) { UntitledDocuments.openNew() }
                .keyboardShortcut("n", modifiers: .command)
            Button(tr(.menuOpen)) { NSDocumentController.shared.openDocument(nil) }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Menu(tr(.menuOpenRecent)) {
                ForEach(RecentFiles.urls, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    }
                }
                Divider()
                Button(tr(.menuClearRecent)) { RecentFiles.clear() }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button(tr(.menuClose)) { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button(tr(.menuSave)) { state?.save() }
                .keyboardShortcut("s", modifiers: .command)
            Button(tr(.menuSaveAs)) { state?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Menu(tr(.menuExport)) {
                Button(tr(.exportPDFItem)) { state?.openExportSheet(.pdf) }
                    .disabled(state?.pages.isEmpty ?? true)
                Button(tr(.exportPNGItem)) { state?.openExportSheet(.png) }
                    .disabled(state?.page == nil)
                Divider()
                Button(tr(.exportCSVItem)) { state?.exportSelectedVisualToCSV() }
                    .disabled(state?.exportCSVDisabledReason != nil)
            }
            .disabled(state == nil)
            Divider()
            Button(tr(.menuFileOptions)) { state?.showFileOptionsDialog() }
                .disabled(state == nil)
        }
    }
}

/// Danh sách file mở gần đây (tối đa 10), lưu trong UserDefaults.
enum RecentFiles {
    private static let key = "recentFiles"
    private static let limit = 10

    static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func record(_ url: URL) {
        var paths = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
