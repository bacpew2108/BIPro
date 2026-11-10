import Foundation
import PBIXKit

/// Dấu vết của một file trên đĩa (ngày sửa và cỡ), để biết file có bị chương trình khác đổi sau lúc mở không.
struct FileStamp: Equatable, Sendable {
    var modified: Date
    var size: Int

    static func of(_ url: URL) throws -> FileStamp {
        // `attributesOfItem` đọc lại từ đĩa; `URL.resourceValues` có thể trả giá trị đã nhớ.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileStamp(modified: attributes[.modificationDate] as? Date ?? .distantPast,
                         size: (attributes[.size] as? NSNumber)?.intValue ?? 0)
    }
}

enum SaveError: Error, Equatable, CustomStringConvertible {
    /// Đích nằm dưới thư mục gốc chỉ đọc (mặc định `~/Downloads`).
    case readOnlyOriginal(URL)
    /// File nguồn đã bị đổi ngoài app kể từ lúc mở.
    case modifiedExternally
    /// File dựng xong không khớp trạng thái cần lưu; file đích còn nguyên.
    case verificationFailed(String)
    case backupFailed(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .readOnlyOriginal: "File trong Downloads là bản gốc, chỉ đọc. Hãy lưu thành bản mới."
        case .modifiedExternally: "File đã bị thay đổi bởi chương trình khác."
        case .verificationFailed(let why): "File mới không qua kiểm tra, file cũ được giữ nguyên. (\(why))"
        case .backupFailed: "Không tạo được bản sao lưu, chưa ghi gì."
        case .writeFailed(let why): "Không ghi được file. (\(why))"
        }
    }
}

struct SaveOutcome: Equatable {
    /// `false` khi không có thay đổi nào để ghi.
    var didWrite: Bool
    var newStamp: FileStamp?
}

/// Đường lưu T1 theo `specs/002-d1-canvas-luu-t1/contracts/save-pipeline.md`.
@MainActor
enum DocumentSaver {
    /// File dưới các thư mục này là bản gốc chỉ đọc (Hiến pháp IV): `~/Downloads`.
    nonisolated static func defaultReadOnlyRoots() -> [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)]
    }

    /// Bản sao lưu nằm ngoài thư mục của người dùng: `~/Library/Application Support/BI Pro/Backups`.
    nonisolated static func defaultBackupDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BI Pro/Backups", isDirectory: true)
    }

    nonisolated private static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    nonisolated static func isReadOnlyOriginal(_ url: URL, roots: [URL]) -> Bool {
        let path = normalized(url)
        return roots.contains { root in
            let base = normalized(root)
            return path == base || path.hasPrefix(base + "/")
        }
    }

    /// Lưu bố cục đã sửa của `editor`. `source` là file đang mở, `destination` có thể là chính nó hoặc một file mới.
    /// Không có thay đổi thì không ghi gì. Mỗi bước lỗi đều dừng và để file đích nguyên vẹn.
    @discardableResult
    static func save(editor: LayoutEditor, source: URL, to destination: URL, expectedStamp: FileStamp?,
                     readOnlyRoots: [URL] = defaultReadOnlyRoots(),
                     backupDirectory: URL = defaultBackupDirectory()) throws -> SaveOutcome {
        guard editor.isDirty else { return SaveOutcome(didWrite: false, newStamp: expectedStamp) }

        // 1. Chặn ghi vào bản gốc chỉ đọc.
        if isReadOnlyOriginal(destination, roots: readOnlyRoots) { throw SaveError.readOnlyOriginal(destination) }

        // 2. File nguồn không được đổi ngoài app (dùng nó làm nền cho phần giữ nguyên).
        if let expectedStamp, (try? FileStamp.of(source)) != expectedStamp { throw SaveError.modifiedExternally }

        // 3. Dựng, kiểm trong bộ nhớ.
        let archive: ZipArchive
        let result: PBIXWriter.Result
        do {
            archive = try ZipArchive(url: source)
            let changes = try editor.makeChanges(archive: archive)
            result = try PBIXWriter.build(source: source, changes: changes)
        } catch let error as WriteError {
            throw SaveError.verificationFailed("\(error)")
        }
        try verifyLayout(result.data, editor: editor)

        // 4. Ghi tạm, mở lại, sao lưu, thay.
        do {
            try PBIXWriter.write(result.data, to: destination, backup: .directory(backupDirectory))
        } catch let error as WriteError {
            switch error {
            case .backupFailed(let why): throw SaveError.backupFailed(why)
            case .verificationFailed(let why): throw SaveError.verificationFailed(why)
            default: throw SaveError.writeFailed("\(error)")
            }
        } catch {
            throw SaveError.writeFailed(error.localizedDescription)
        }

        // 5. Sau lưu.
        editor.markSaved()
        return SaveOutcome(didWrite: true, newStamp: try? FileStamp.of(destination))
    }

    /// Đọc lại bytes đã dựng: bố cục của mọi trang phải khớp với `editor` (cùng tập visual, cùng khung và `z`).
    static func verifyLayout(_ data: Data, editor: LayoutEditor) throws {
        let report: ReportDefinition
        do {
            report = try PBIXFile(data: data).loadReport()
        } catch {
            throw SaveError.verificationFailed("không đọc lại được: \(error)")
        }
        for page in editor.baseline.pages {
            guard let written = report.pages.first(where: { $0.id == page.id }) else {
                throw SaveError.verificationFailed("thiếu trang \(page.id)")
            }
            let expected = editor.visuals(of: page.id)
            guard Set(expected.map(\.id)) == Set(written.visuals.map(\.id)) else {
                throw SaveError.verificationFailed("tập visual của trang \(page.id) khác trạng thái đang sửa")
            }
            for visual in expected {
                guard let actual = written.visuals.first(where: { $0.id == visual.id }),
                      Frame(actual) == Frame(visual), Int(actual.z) == Int(visual.z) else {
                    throw SaveError.verificationFailed("vị trí của \(visual.id) trong trang \(page.id) khác trạng thái đang sửa")
                }
                guard actual.type == visual.type else {
                    throw SaveError.verificationFailed("loại của \(visual.id) trong trang \(page.id) khác trạng thái đang sửa")
                }
                if visual.type == "textbox", LayoutEditor.paragraphTexts(of: actual.raw) != LayoutEditor.paragraphTexts(of: visual.raw) {
                    throw SaveError.verificationFailed("nội dung hộp văn bản \(visual.id) trong trang \(page.id) khác trạng thái đang sửa")
                }
                guard actual.fields == visual.fields else {
                    throw SaveError.verificationFailed("các ô và trường của \(visual.id) trong trang \(page.id) khác trạng thái đang sửa")
                }
            }
        }
    }
}
