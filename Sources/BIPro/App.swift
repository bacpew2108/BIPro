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
                                           fileName: file.fileURL?.lastPathComponent ?? "Không tên.pbix",
                                           fileURL: file.fileURL))
                .frame(minWidth: 1100, minHeight: 680)
        }
        .commands {
            SaveCommands()
            EditCommands()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1600, height: 1000)
    }
}

/// Tài liệu cho SwiftUI chỉ để đọc. SwiftUI không được ghi file (nó tự lưu nền vào chính file đang mở, trái Hiến pháp IV):
/// việc lưu do `DocumentSaver` làm, qua lệnh ⌘S và ⇧⌘S ở `SaveCommands`. Mọi trạng thái nằm ở `Workspace` và `LayoutEditor`.
struct PBIXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pbix] }
    static var writableContentTypes: [UTType] { [] }

    let workspace: Workspace

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        workspace = try Workspace(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
