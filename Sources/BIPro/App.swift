import PBIXKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pbix = UTType(importedAs: "com.microsoft.powerbi.pbix")
}

@main
struct BIProApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        DocumentGroup(viewing: PBIXDocument.self) { file in
            ShellView(state: DocumentState(workspace: file.document.workspace,
                                           fileName: file.fileURL?.lastPathComponent ?? tr(.untitledDocument),
                                           fileURL: file.fileURL))
                .frame(minWidth: 1100, minHeight: 680)
        }
        .commands {
            SaveCommands()
            EditCommands()
            AppHelpCommands()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1600, height: 1000)

        Settings {
            SettingsView(preferences: AppPreferences.shared)
        }

        Window("BI Pro", id: "start-screen") {
            StartScreen()
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(AppPreferences.shared.preferredColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 780)
    }
}

struct AppHelpCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Button(tr(.menuShowOnboarding)) {
                AppPreferences.shared.requestShowOnboarding()
            }
        }
    }
}

/// Tài liệu cho SwiftUI chỉ để đọc. SwiftUI không được ghi file (nó tự lưu nền vào chính file đang mở, trái Hiến pháp IV):
/// việc lưu do `DocumentSaver` làm, qua lệnh ⌘S và ⇧⌘S ở `SaveCommands`. Mọi trạng thái nằm ở `Workspace` và `LayoutEditor`.
struct PBIXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pbix] }
    static var writableContentTypes: [UTType] { [] }

    let workspace: Workspace

    init(configuration: ReadConfiguration) throws {
        DocumentOpenTracker.markOpened()
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        workspace = try Workspace(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
