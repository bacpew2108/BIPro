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
        let pbix: PBIXFile
        do {
            pbix = try PBIXFile(data: data)
            report = try pbix.loadReport()
        } catch {
            throw SaveError.verificationFailed("không đọc lại được: \(error)")
        }
        try verifyPages(report: report, pbix: pbix, editor: editor)
        try verifyReportEdits(pbix: pbix, editor: editor)
        for page in editor.pages {
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
                guard actual.objects.json == visual.objects.json, actual.containerObjects.json == visual.containerObjects.json else {
                    throw SaveError.verificationFailed("định dạng của \(visual.id) trong trang \(page.id) khác trạng thái đang sửa")
                }
                guard actual.fields == visual.fields else {
                    throw SaveError.verificationFailed("các ô và trường của \(visual.id) trong trang \(page.id) khác trạng thái đang sửa")
                }
            }
            try verifyGroups(written: written, editor: editor, expected: expected)
        }
    }

    /// Nhóm visual (D7, `contracts/group-editing.md`): cùng tập nhóm với `editor`, khung và `z` khớp; con đọc lại có đúng nhóm cha
    /// và vị trí tuyệt đối khớp (đã kiểm ở `verifyLayout`); nhóm mới tạo có ít nhất một con; con nằm trong khung nhóm (sai số 1 điểm).
    private static func verifyGroups(written: ReportPage, editor: LayoutEditor, expected: [ReportVisual]) throws {
        let groups = editor.groups(of: written.id)
        guard Set(groups.map(\.id)) == Set(written.groups.map(\.id)) else {
            throw SaveError.verificationFailed("tập nhóm của trang \(written.id) khác trạng thái đang sửa")
        }
        let preexisting = Set(editor.basePage(written.id)?.groups.map(\.id) ?? [])
        for group in groups {
            guard let actual = written.groups.first(where: { $0.id == group.id }), Frame(actual) == Frame(group), Int(actual.z) == Int(group.z) else {
                throw SaveError.verificationFailed("khung của nhóm \(group.id) trong trang \(written.id) khác trạng thái đang sửa")
            }
            guard actual.parentGroup == group.parentGroup else {
                throw SaveError.verificationFailed("nhóm cha của nhóm \(group.id) trong trang \(written.id) khác trạng thái đang sửa")
            }
            // Thành viên: visual con và nhóm lồng bên trong (VM-D8).
            let kids = (written.visuals + written.groups).filter { $0.parentGroup == group.id }
            if kids.isEmpty, !preexisting.contains(group.id) {
                throw SaveError.verificationFailed("nhóm \(group.id) trong trang \(written.id) không có visual con")
            }
            // Chỉ kiểm phần editor đã đổi hoặc tạo: nhóm của Desktop có thể sẵn có con nằm ngoài khung.
            let baseGroup = editor.basePage(written.id)?.groups.first { $0.id == group.id }
            let basePage = editor.basePage(written.id)
            let baseKids = Dictionary(((basePage?.visuals ?? []) + (basePage?.groups ?? [])).map { ($0.id, Frame($0)) }, uniquingKeysWith: { first, _ in first })
            let groupChanged = baseGroup.map { Frame($0) != Frame(group) } ?? true
            for kid in kids where (groupChanged || baseKids[kid.id] != Frame(kid)) && (kid.x < actual.x - 1 || kid.y < actual.y - 1
                || kid.x + kid.width > actual.x + actual.width + 1 || kid.y + kid.height > actual.y + actual.height + 1) {
                throw SaveError.verificationFailed("visual \(kid.id) nằm ngoài khung nhóm \(group.id)")
            }
        }
        let known = Set(groups.map(\.id))
        for visual in expected {
            guard let actual = written.visuals.first(where: { $0.id == visual.id }) else { continue }
            if let parent = visual.parentGroup, known.contains(parent), actual.parentGroup != parent {
                throw SaveError.verificationFailed("nhóm cha của \(visual.id) trong trang \(written.id) khác trạng thái đang sửa")
            }
            if visual.parentGroup == nil, actual.parentGroup != nil {
                throw SaveError.verificationFailed("\(visual.id) trong trang \(written.id) còn nằm trong nhóm sau khi bỏ nhóm")
            }
        }
    }

    /// Bookmark và bộ lọc người dùng sửa (D6, `contracts/bookmark-filter-save.md`): bookmark đã ghi chỉ trỏ visual và trang có thật,
    /// tên hiển thị khớp; thẻ lọc đã ghi nằm đúng part, đúng loại, đọc lại được; thẻ đã bỏ không còn.
    private static func verifyReportEdits(pbix: PBIXFile, editor: LayoutEditor) throws {
        let edits = editor.reportEdits
        guard !edits.isEmpty else { return }
        let alive = Set(editor.pages.map(\.id))
        // Bookmark.
        var wanted: [String: String] = [:]   // mã → tên hiển thị
        for added in edits.bookmarks.added where !edits.bookmarks.deleted.contains(added.id) { wanted[added.id] = added.name }
        for (id, fresh) in edits.bookmarks.updated where !edits.bookmarks.deleted.contains(id) { wanted[id] = edits.bookmarks.renamed[id] ?? fresh.name }
        for (id, name) in edits.bookmarks.renamed where wanted[id] == nil && !edits.bookmarks.deleted.contains(id) { wanted[id] = name }
        for entry in pbix.archive.entries where entry.path.hasPrefix(LayoutEditor.bookmarksFolder) && entry.path.hasSuffix(".bookmark.json") {
            let data = try pbix.archive.read(entry)
            guard let value = try? JSONValue.parse(data), let name = value["name"]?.string else {
                throw SaveError.verificationFailed("\(entry.path) không đọc lại được")
            }
            if edits.bookmarks.deleted.contains(name) { throw SaveError.verificationFailed("bookmark \(name) đã xoá vẫn còn trong file") }
            guard let display = wanted[name] else { continue }
            if let shown = value["displayName"]?.string, shown != display {
                throw SaveError.verificationFailed("tên bookmark \(name) trong file khác trạng thái đang sửa")
            }
            let isWritten = edits.bookmarks.added.contains { $0.id == name } || edits.bookmarks.updated[name] != nil
            guard isWritten else { continue }
            for (pageID, section) in value["explorationState"]?["sections"]?.object ?? [:] {
                guard alive.contains(pageID) else { throw SaveError.verificationFailed("bookmark \(name) trỏ tới trang \(pageID) không còn") }
                let ids = Set(editor.visuals(of: pageID).map(\.id))
                for visualID in (section["visualContainers"]?.object ?? [:]).keys where !ids.contains(visualID) {
                    throw SaveError.verificationFailed("bookmark \(name) trỏ tới visual \(visualID) không có trong trang \(pageID)")
                }
            }
        }
        // Bộ lọc.
        func cards(at path: String) -> [JSONValue] {
            guard let data = try? pbix.archive.read(path), let value = try? JSONValue.parse(data) else { return [] }
            return value["filterConfig"]?["filters"]?.array ?? []
        }
        for (key, change) in edits.filters {
            let path: String
            switch key.level {
            case .report: path = LayoutEditor.reportJSONPath
            case .page:
                guard alive.contains(key.scope) else { continue }
                path = LayoutEditor.pagePath(key.scope)
            case .visual:
                guard let page = editor.pages.first(where: { p in editor.visuals(of: p.id).contains { $0.id == key.scope } }) else { continue }
                path = LayoutEditor.visualPath(page: page.id, id: key.scope)
            }
            let found = cards(at: path)
            switch change {
            case .remove(let name):
                if let name, found.contains(where: { $0["name"]?.string == name }) {
                    throw SaveError.verificationFailed("thẻ lọc \(name) đã bỏ vẫn còn trong \(path)")
                }
            case .set(let filter):
                guard case .writable(let spec) = FilterExport.card(for: filter, key: key, decimal: editor.decimalColumns.contains("\(filter.column.table)[\(filter.column.column)]")) else { continue }
                guard let card = found.first(where: { $0["name"]?.string == spec.name }) else {
                    throw SaveError.verificationFailed("thiếu thẻ lọc \(spec.name) trong \(path)")
                }
                guard card["type"]?.string == spec.type else { throw SaveError.verificationFailed("loại thẻ lọc \(spec.name) trong \(path) khác trạng thái đang sửa") }
                if spec.type == "Categorical" {
                    let parsed = PBIXFile.filters(.array([card]), level: key.level).first.flatMap(UserFilter.from)
                    guard let parsed, Set(parsed.values) == Set(filter.values), parsed.exclude == filter.exclude || filter.values.isEmpty else {
                        throw SaveError.verificationFailed("thẻ lọc \(spec.name) trong \(path) không khớp trạng thái đang sửa")
                    }
                }
            }
        }
    }

    /// Cấu trúc trang (D5): thứ tự và tên khớp `editor.pages`; bookmark không trỏ trang không còn và khớp `bookmarks.json`;
    /// không còn tham chiếu tới trang đã xoá (`contracts/page-save.md`).
    private static func verifyPages(report: ReportDefinition, pbix: PBIXFile, editor: LayoutEditor) throws {
        let expected = editor.pages
        guard report.pages.map(\.id) == expected.map(\.id) else {
            throw SaveError.verificationFailed("thứ tự trang trong file khác trạng thái đang sửa")
        }
        for (written, wanted) in zip(report.pages, expected) where written.displayName != wanted.displayName {
            throw SaveError.verificationFailed("tên trang \(wanted.id) trong file khác trạng thái đang sửa")
        }
        let alive = Set(expected.map(\.id))
        var bookmarkNames = Set<String>()
        for entry in pbix.archive.entries where entry.path.hasPrefix(LayoutEditor.bookmarksFolder) && entry.path.hasSuffix(".bookmark.json") {
            guard let info = BookmarkInfo(json: try pbix.archive.read(entry)) else { continue }
            bookmarkNames.insert(info.name)
            if let active = info.activeSection, !alive.contains(active) {
                throw SaveError.verificationFailed("bookmark \(info.name) trỏ tới trang \(active) không còn")
            }
            if !info.sections.isSubset(of: alive) {
                throw SaveError.verificationFailed("bookmark \(info.name) còn phần của trang không còn")
            }
        }
        if pbix.archive.entry(LayoutEditor.bookmarksJSONPath) != nil,
           let items = (try? JSONValue.parse(try pbix.archive.read(LayoutEditor.bookmarksJSONPath)))?["items"]?.array {
            // Nhóm bookmark (VM-D8 mục 5): mục có `children` đại diện cho các bookmark con, không phải một file.
            var listed = Set<String>()
            for item in items {
                // Con của nhóm là chuỗi mã, hoặc `{"name": …}` như bộ đọc `loadBookmarks` chấp nhận.
                if let children = item["children"]?.array { listed.formUnion(children.compactMap { $0.string ?? $0["name"]?.string }) }
                else if let name = item["name"]?.string { listed.insert(name) }
            }
            guard listed == bookmarkNames else {
                throw SaveError.verificationFailed("bookmarks.json không khớp các file bookmark")
            }
        }
        // Tham chiếu treo tới trang đã xoá, chỉ ở những chỗ là tham chiếu: thư mục trang, `activePageName` (bookmark đã kiểm
        // ở trên, `pageOrder` qua thứ tự trang). Chuỗi trùng mã trang ở chỗ khác (tên hiển thị, chữ trong visual) không phải
        // tham chiếu và không chặn lưu. Nút điều hướng trỏ trang đã xoá cũng không chặn: Desktop để nguyên nút (VM-D8).
        let gone = editor.usedPageIDs.subtracting(alive)
        guard !gone.isEmpty else { return }
        if pbix.archive.entry(LayoutEditor.pagesJSONPath) != nil,
           let active = (try? JSONValue.parse(try pbix.archive.read(LayoutEditor.pagesJSONPath)))?["activePageName"]?.string, gone.contains(active) {
            throw SaveError.verificationFailed("pages.json còn mở trang đã xoá \(active)")
        }
        for entry in pbix.archive.entries where entry.path.hasPrefix(LayoutEditor.pagesFolder) {
            if let id = gone.first(where: { entry.path.hasPrefix("\(LayoutEditor.pagesFolder)\($0)/") }) {
                throw SaveError.verificationFailed("\(entry.path) còn là phần của trang đã xoá \(id)")
            }
        }
    }
}

