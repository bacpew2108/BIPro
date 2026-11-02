import PBIXKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pbix = UTType(importedAs: "com.microsoft.powerbi.pbix")
}

@main
struct BIProApp: App {
    var body: some Scene {
        DocumentGroup(viewing: PBIXDocument.self) { file in
            ShellView(state: DocumentState(workspace: file.document.workspace,
                                           fileName: file.fileURL?.lastPathComponent ?? "Không tên.pbix"))
                .frame(minWidth: 1100, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1600, height: 1000)
    }
}

/// Read-only document wrapper until saving lands (Phase D); all state lives in `Workspace`.
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
