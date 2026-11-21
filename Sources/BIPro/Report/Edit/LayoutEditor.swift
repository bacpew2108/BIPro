import Foundation
import Observation
import PBIXKit

/// Phần sửa của một trang: bố cục hiện tại, mã đã xoá khỏi bản gốc, và `visual.json` của các bản sao chưa lưu.
struct PageEdit: Equatable {
    var visuals: [ReportVisual]
    /// Nhóm visual của trang (D7): khung tuyệt đối. `visual.json` của nhóm mới nằm trong `added` như visual mới.
    var groups: [ReportVisual] = []
    /// Mã visual có trong file gốc mà đã bị xoá (khi lưu thì bỏ phần của chúng).
    var deleted: Set<String> = []
    /// `visual.json` của bản sao mới (khoá là mã bản sao), chưa có trong file.
    var added: [String: Data] = [:]
    /// Cấu hình trường đã sửa của visual (mã visual → các ô theo thứ tự), D2. Chỉ có khoá cho visual đã sửa trường.
    var queries: [String: [PBIRQueryPatch.Well]] = [:]
    /// Công thức đổi loại của visual có trong file (D3). Visual mới nằm trong `added` nên không cần khoá ở đây.
    var retyped: [String: Retype] = [:]
    /// Các dòng văn bản của hộp văn bản có trong file (D3). Hộp văn bản mới nằm trong `added`.
    var texts: [String: [String]] = [:]
    /// `visual.json` của container không phải visual (nhóm visual, `visualGroup`) đã sao sang trang nhân bản (D5):
    /// mã mới → byte. Trang của file không có khoá này (chúng nằm sẵn trong file).
    var extraParts: [String: Data] = [:]
    /// Phần sửa định dạng đã gộp của visual có trong file (mã visual → danh sách `FormatEdit`), D4. Visual mới nằm trong `added`
    /// (định dạng đã nằm trong byte), nên không có khoá ở đây.
    var formats: [String: [FormatEdit]] = [:]
    /// Tương tác chéo tuỳ chỉnh trên trang (`page.json` `visualInteractions`, Wave 3A / VM-V11B). nil = chưa sửa.
    var visualInteractions: [PageVisualInteraction]? = nil
    /// Sửa mảng đối tượng định dạng phức tạp trong `visual.objects` (Wave 3B: `values` CF, `columnFormatting` dataBars,
    /// `y1AxisReferenceLine`, `referenceLine`, `trend`, `forecast`). visualID → objectKey → arrayJSON (nil = xoá khoá).
    var rawObjectEdits: [String: [String: String?]] = [:]
}

struct CustomThemeEdit: Equatable {
    var name: String
    var data: Data
}

/// Công thức đổi loại một visual đã có trong file: loại mới và các khoá `visual.objects` cần bỏ (tích luỹ qua các lần đổi).
struct Retype: Equatable {
    var type: String
    var dropObjectKeys: Set<String>
    /// Đổi sang cột/thanh với cột ngày ở `Category`: lúc ghi thêm sắp xếp mặc định tăng dần theo cột đó (VM-D9 mục 1).
    var sortsByDateCategory = false
}

/// Một bước hoàn tác: toàn bộ trạng thái sửa (các trang đã sửa và cấu trúc trang) cùng trang đang mở và vùng chọn,
/// tại một thời điểm (D5: thêm hay xoá cả trang là một bước như mọi bước khác; lịch sử là một dòng nên tương đương
/// ảnh chụp từng trang của D1). Từ điển và mảng là giá trị copy-on-write nên chụp rẻ.
struct LayoutSnapshot {
    /// Trang đưa người dùng tới khi khôi phục (trang đang mở lúc chụp).
    var pageID: String
    var edited: [String: PageEdit]
    var structure: PageStructure
    var selection: Set<String>
    var primary: String?
    /// Bookmark và bộ lọc người dùng sửa ở lớp tài liệu (D6).
    var edits = ReportEdits()
    /// Sửa mô hình (Phase E).
    var model = ModelEdits()
    /// Vị trí thẻ bảng và thu phóng ở Model view (Phase E).
    var diagram = DiagramEdits()
    /// Ảnh nhúng mới thêm trong phiên (US4): tên tài nguyên RegisteredResources → dữ liệu ảnh gốc.
    var addedImages: [String: Data] = [:]
    /// Chủ đề tuỳ chỉnh áp dụng trong phiên (Wave 3B).
    var customTheme: CustomThemeEdit? = nil
    /// Ghi đè byte PBIR cấp trang/báo cáo/bookmark (Wave 3C Cascade Rename).
    var pbirPartOverrides: [String: Data] = [:]
}

/// Bố cục có thể sửa của báo cáo. `Workspace` giữ bản gốc bất biến; mọi thay đổi nằm ở đây
/// và chỉ cho các trang đã bị đụng tới. Xem `specs/002-d1-canvas-luu-t1/data-model.md`.
@MainActor
@Observable
final class LayoutEditor {
    /// Cột kiểu số thực của mô hình (`Bảng[Cột]`): toán hạng số của thẻ Advanced ghi `…D` thay vì `…L` (Desktop làm vậy; D6).
    var decimalColumns: Set<String> = []
    /// Cột tiền tệ (Fixed decimal number, `Bảng[Cột]`): toán hạng của thẻ Advanced ghi `…M` (VM-D10).
    var currencyColumns: Set<String> = []
    /// Cột kiểu ngày giờ của mô hình (`Bảng[Cột]`): đổi sang biểu đồ cột/thanh thì sắp tăng dần theo cột này (VM-D9).
    var dateColumns: Set<String> = []
    /// Cột của mô hình hiệu lực (gồm bảng vừa nạp, chưa có trong `modelBase`): kiểu cột cho phép gộp ngầm.
    @ObservationIgnored var modelColumns: [ModelMetadata.Column] = []
    /// Giá trị (dạng literal, ví dụ `'Female'`) của cột ở ô Chú giải của visual, theo thứ tự đang hiện; rỗng khi chưa nạp dữ liệu.
    var legendValuesProvider: (String) -> [String] = { _ in [] }
    /// Bản gốc lúc mở (hoặc lúc lưu gần nhất).
    private(set) var baseline: ReportDefinition
    /// Trang đã sửa → phần sửa. Trang chưa đụng tới không có mục.
    private(set) var edited: [String: PageEdit] = [:]
    /// Thứ tự tab, tên đổi, trang tạo và trang xoá (D5).
    private(set) var structure: PageStructure
    /// Bookmark và thẻ lọc người dùng sửa (D6); lưu so với file trên đĩa.
    private(set) var reportEdits = ReportEdits()
    /// `reportEdits` ở lần lưu thành công gần nhất: để hoàn tác sau khi lưu đưa được bookmark và thẻ lọc đã ghi về như cũ (D6).
    var savedEdits = ReportEdits()
    /// Sửa mô hình chưa lưu (Phase E): thêm, sửa, xoá measure; sửa quan hệ và cột. Chung ngăn xếp hoàn tác với báo cáo.
    private(set) var modelEdits = ModelEdits()
    /// `modelEdits` ở lần lưu thành công gần nhất.
    private(set) var savedModelEdits = ModelEdits()
    /// Ảnh nhúng mới thêm trong phiên (US4): tên trong `RegisteredResources` → dữ liệu ảnh (hoàn tác cùng visual).
    private(set) var addedImages: [String: Data] = [:]
    /// Chủ đề tuỳ chỉnh áp dụng trong phiên (Wave 3B, hoàn tác cùng lịch sử tài liệu).
    private(set) var customTheme: CustomThemeEdit? = nil
    /// Gọi khi đổi hoặc hoàn tác chủ đề để `DocumentState`/`Workspace` cập nhật bảng màu ngay.
    @ObservationIgnored var customThemeChanged: (CustomThemeEdit?) -> Void = { _ in }
    /// Ghi đè byte PBIR (`page.json`, `report.json`, `bookmark.json`) từ Cascade Rename (Wave 3C).
    private(set) var pbirPartOverrides: [String: Data] = [:]
    /// Vị trí thẻ bảng và thu phóng Model view chưa lưu (Phase E). Chung ngăn xếp hoàn tác.
    private(set) var diagramEdits = DiagramEdits()
    /// `diagramEdits` ở lần lưu thành công gần nhất (giữ cả vị trí gốc, để hoàn tác sau lưu ghi lại được vị trí cũ).
    private(set) var savedDiagramEdits = DiagramEdits()
    /// Byte phần `DiagramLayout` của file đã mở (nil nếu file không có).
    @ObservationIgnored var diagramSource: () -> Data? = { nil }
    /// `LineageTag` của bảng, dùng khi thêm nút cho thẻ chưa có trong tab.
    @ObservationIgnored var diagramLineageTag: (String) -> String? = { _ in nil }
    /// Tab bố cục đang xem ở Model view (ghi vào `selectedDiagram` khi lưu có đổi cấu trúc tab).
    @ObservationIgnored var diagramSelected: () -> String? = { nil }
    /// Tên các tab bố cục trong file lúc mở (theo thứ tự): để biết tab nào của lần lưu trước còn là tab đó sau khi đổi tên hoặc xoá.
    @ObservationIgnored var diagramFileNames: () -> [String] = { [] }
    /// Mô hình gốc của file lúc mở: để tính phần đổi khi lưu lần thứ hai (file trên đĩa đã chứa phần đã lưu).
    @ObservationIgnored var modelBase: ModelMetadata?
    /// Giá trị đã tính của cột/bảng tính toán trong các thao tác sắp lưu, khoá `Bảng[Cột]` (T084). `DocumentState` gắn vào engine của phiên.
    @ObservationIgnored var calculatedValues: (ModelEdits) throws -> [String: VertiPaqWriter.Values] = { _ in [:] }
    /// T116: thao tác ghi lại cột/bảng tính toán có sẵn trong file phụ thuộc phần đổi của lần lưu (`CalculationPlan.recalculationEdits`).
    @ObservationIgnored var recalculationEdits: (ModelEdits) -> [ModelEdit] = { _ in [] }
    /// Gọi mỗi khi `modelEdits` đổi (sửa, hoàn tác, làm lại) để nơi giữ mô hình hiệu lực và engine cập nhật theo.
    @ObservationIgnored var modelEditsChanged: (ModelEdits) -> Void = { _ in }
    /// Phần bookmark và bộ lọc bị bỏ qua ở lần dựng gói lưu gần nhất vì chưa lưu được vào file (kèm lý do).
    var saveNotes: [String] = []
    private(set) var selection: Set<String> = []
    private(set) var primary: String?
    private(set) var currentPageID: String?
    /// Lý do gần nhất thao tác bị bỏ qua (ví dụ visual trong nhóm), để giao diện hiện cho người dùng.
    var lockedReason: String?
    /// Thông báo sau một thao tác (trường hoặc định dạng bị bỏ khi đổi loại, D3); xoá ở thao tác kế.
    private(set) var notice: String?
    /// Lý do gần nhất một thao tác sửa trường bị từ chối (D2); nil khi thao tác gần nhất được chấp nhận.
    private(set) var fieldRefusal: String?
    /// Chế độ Sửa tương tác chéo trên canvas (Wave 3A): hiện huy hiệu Lọc/Tô sáng/Không trên từng visual đích.
    var isEditingInteractions = false
    /// Sao định dạng (Format Painter — Wave 4A): nguồn đang giữ để áp lên visual đích kế tiếp.
    struct FormatPainterPayload: Equatable {
        let sourceID: String
        let containerObjects: [String: JSONValue]
        let compatibleObjects: [String: JSONValue]
    }
    var formatPainter: FormatPainterPayload? = nil
    var isFormatPainterActive: Bool { formatPainter != nil }

    // Hoàn tác
    private var undoStack: [LayoutSnapshot] = []
    private var redoStack: [LayoutSnapshot] = []
    /// Độ sâu `undoStack` tại lần lưu gần nhất. -1: không còn quay về được trạng thái đã lưu.
    private var cleanMark = 0
    static let historyLimit = 200
    static let coalesceWindow: TimeInterval = 0.5
    @ObservationIgnored var now: () -> Date = Date.init
    private var lastCoalesce: (pageID: String, ids: Set<String>, at: Date)?

    /// `visual.json` của một visual có trong file đã mở: `(mã trang, mã visual)` → byte. Dùng khi nhân bản.
    @ObservationIgnored private let sourceJSON: (String, String) -> Data?
    /// Mọi mã visual đã có hoặc đã được sinh trong phiên (không bao giờ dùng lại, kể cả sau hoàn tác).
    @ObservationIgnored private(set) var usedIDs: Set<String>
    /// Mọi mã trang đã có hoặc đã sinh trong phiên (không bao giờ dùng lại, kể cả sau hoàn tác).
    @ObservationIgnored var usedPageIDs: Set<String>
    /// Mã bản sao đã tạo, theo trang (không hoàn tác được): để biết phần nào có thể đã nằm trong file khi xoá.
    @ObservationIgnored var createdIDs: [String: Set<String>] = [:]
    /// Bộ nhớ tạm cho Chép/Dán trong cùng tài liệu.
    private var clipboard: [(visual: ReportVisual, json: Data)] = []
    private var pasteCount = 0

    /// `page.json` của một trang có trong file đã mở (mã trang → byte). Dùng khi nhân bản trang và lấy `$schema`.
    @ObservationIgnored let pageSource: (String) -> Data?
    /// Các bookmark của file đã mở: tên và byte của từng `*.bookmark.json`. Dùng khi xoá trang để biết bookmark nào bị ảnh hưởng.
    @ObservationIgnored let bookmarkSource: () -> [(name: String, json: Data)]
    /// Container không phải visual (nhóm visual) của một trang có trong file: mã và byte `visual.json`.
    @ObservationIgnored let containerSource: (String) -> [(id: String, json: Data)]
    /// Các part của file lúc mở có đường dẫn bắt đầu bằng tiền tố cho trước (đường dẫn và byte). Dùng để dựng lại phần
    /// đã bị một lần lưu trước bỏ khỏi file khi người dùng hoàn tác qua lần lưu đó (trang đã xoá).
    @ObservationIgnored let openedParts: (String) -> [(path: String, data: Data)]

    /// Báo cáo định dạng cũ (`Report/Layout`, D7): chỉ sửa bố cục; `sourceJSON` trả byte của container, không phải `visual.json`.
    let isLegacy: Bool
    static let legacyMessage = "Báo cáo định dạng cũ (Report/Layout) mới sửa được bố cục: di chuyển, đổi cỡ, căn, xoá, nhân bản, chép dán."

    init(report: ReportDefinition, sourceJSON: @escaping (String, String) -> Data? = { _, _ in nil },
         pageSource: @escaping (String) -> Data? = { _ in nil },
         bookmarkSource: @escaping () -> [(name: String, json: Data)] = { [] },
         containerSource: @escaping (String) -> [(id: String, json: Data)] = { _ in [] },
         openedParts: @escaping (String) -> [(path: String, data: Data)] = { _ in [] },
         isLegacy: Bool = false) {
        self.isLegacy = isLegacy
        baseline = report
        self.containerSource = containerSource
        self.openedParts = openedParts
        self.sourceJSON = sourceJSON
        self.pageSource = pageSource
        self.bookmarkSource = bookmarkSource
        usedIDs = Set(report.pages.flatMap { $0.visuals.map(\.id) })
        structure = PageStructure(order: report.pages.map(\.id))
        usedPageIDs = Set(report.pages.map(\.id))
    }

    /// Editor đọc `visual.json`, `page.json` và bookmark từ `archive` (file đang mở).
    static func reading(archive: ZipArchive, report: ReportDefinition) -> LayoutEditor {
        LayoutEditor(report: report,
                     sourceJSON: { page, id in try? archive.read(LayoutEditor.visualPath(page: page, id: id)) },
                     pageSource: { page in try? archive.read(LayoutEditor.pagePath(page)) },
                     bookmarkSource: {
                         archive.entries.compactMap { entry in
                             guard entry.path.hasPrefix(LayoutEditor.bookmarksFolder), entry.path.hasSuffix(".bookmark.json"),
                                   let data = try? archive.read(entry), let info = BookmarkInfo(json: data) else { return nil }
                             return (info.name, data)
                         }
                     },
                     containerSource: { page in
                         let prefix = "\(LayoutEditor.pagesFolder)\(page)/visuals/"
                         return archive.entries.compactMap { entry in
                             guard entry.path.hasPrefix(prefix), entry.path.hasSuffix("/visual.json"),
                                   let data = try? archive.read(entry), let value = try? JSONValue.parse(data),
                                   value["visual"] == nil, let name = value["name"]?.string else { return nil }
                             return (name, data)
                         }
                     },
                     openedParts: { prefix in
                         archive.entries.compactMap { entry in
                             guard entry.path.hasPrefix(prefix), let data = try? archive.read(entry) else { return nil }
                             return (entry.path, data)
                         }
                     })
    }

    // MARK: Đọc

    var undoDepth: Int { undoStack.count }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isDirty: Bool { undoStack.count != cleanMark }

    func visuals(of pageID: String) -> [ReportVisual] {
        edited[pageID]?.visuals ?? basePage(pageID)?.visuals ?? []
    }

    /// Nhóm visual của trang (D7), đã sửa.
    func groups(of pageID: String) -> [ReportVisual] {
        edited[pageID]?.groups ?? basePage(pageID)?.groups ?? []
    }

    /// Mọi phần tử chọn được trên trang: visual và nhóm (D7), theo thứ tự `z` tăng dần.
    func items(of pageID: String) -> [ReportVisual] {
        (visuals(of: pageID) + groups(of: pageID)).sorted { $0.z < $1.z }
    }

    /// Visual hoặc nhóm theo mã (D7).
    func item(_ id: String, page pageID: String? = nil) -> ReportVisual? {
        guard let pageID = pageID ?? currentPageID else { return nil }
        return visuals(of: pageID).first { $0.id == id } ?? groups(of: pageID).first { $0.id == id }
    }

    /// Mã các visual con của nhóm `groupID` trên trang hiện tại.
    func children(ofGroup groupID: String, page pageID: String? = nil) -> [ReportVisual] {
        guard let pageID = pageID ?? currentPageID else { return [] }
        return visuals(of: pageID).filter { $0.parentGroup == groupID }
    }

    /// Thành viên trực tiếp của nhóm: visual con và nhóm con (nhóm lồng nhau, VM-D8).
    func members(ofGroup groupID: String, page pageID: String? = nil) -> [ReportVisual] {
        guard let pageID = pageID ?? currentPageID else { return [] }
        return items(of: pageID).filter { $0.parentGroup == groupID }
    }

    /// Mọi hậu duệ của nhóm (visual và nhóm ở mọi cấp).
    func descendants(ofGroup groupID: String, page pageID: String? = nil) -> [ReportVisual] {
        guard let pageID = pageID ?? currentPageID else { return [] }
        let inside = Self.descendantIDs(of: groupID, in: visuals(of: pageID) + groups(of: pageID))
        return items(of: pageID).filter { inside.contains($0.id) }
    }

    /// Mã mọi hậu duệ của nhóm `groupID` trong `items` (không gồm chính nhóm).
    nonisolated static func descendantIDs(of groupID: String, in items: [ReportVisual]) -> Set<String> {
        var inside: Set<String> = []
        var frontier: Set<String> = [groupID]
        while !frontier.isEmpty {
            let next = Set(items.filter { item in item.parentGroup.map(frontier.contains) ?? false && !inside.contains(item.id) && item.id != groupID }.map(\.id))
            inside.formUnion(next)
            frontier = next
        }
        return inside
    }

    /// Mã các nhóm tổ tiên của `item`, từ cha trực tiếp ra ngoài cùng. Dừng ở nhóm không có trong `groups` hoặc khi gặp vòng.
    nonisolated static func ancestorIDs(of item: ReportVisual, in groups: [ReportVisual]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = [item.id]
        var parent = item.parentGroup
        while let id = parent, seen.insert(id).inserted, let group = groups.first(where: { $0.id == id }) {
            out.append(id)
            parent = group.parentGroup
        }
        return out
    }

    /// Mã các nhóm tổ tiên của phần tử `id` trên trang hiện tại, từ cha trực tiếp ra ngoài cùng.
    func ancestorIDs(of id: String) -> [String] {
        guard let pageID = currentPageID, let item = item(id) else { return [] }
        return Self.ancestorIDs(of: item, in: groups(of: pageID))
    }

    /// Trang cơ sở: trang của file (bản gốc lúc mở) hoặc trang tạo trong phiên (trống, chỉ có tên và cỡ).
    func basePage(_ pageID: String) -> ReportPage? {
        if let page = baseline.pages.first(where: { $0.id == pageID }) { return page }
        return structure.created[pageID].map {
            ReportPage(id: $0.id, displayName: $0.displayName, width: $0.width, height: $0.height, isHidden: false, visuals: [])
        }
    }

    /// Trang với tên và bố cục đã sửa.
    func page(_ pageID: String) -> ReportPage? {
        guard var page = basePage(pageID) else { return nil }
        if let name = structure.renamed[pageID] { page.displayName = name }
        if let edit = edited[pageID] {
            page.visuals = edit.visuals
            page.groups = edit.groups
            if let interactions = edit.visualInteractions { page.visualInteractions = interactions }
        }
        return page
    }

    /// Danh sách tương tác chéo hiệu lực trên trang `pageID`.
    func visualInteractions(on pageID: String) -> [PageVisualInteraction] {
        edited[pageID]?.visualInteractions ?? basePage(pageID)?.visualInteractions ?? []
    }

    /// Đặt hiệu ứng tương tác từ `source` tới `target` trên trang `pageID` (có hoàn tác ⌘Z, lưu vào `page.json`).
    func setVisualInteraction(source: String, target: String, type: PBIRInteractionType, on pageID: String) {
        guard source != target, let base = page(pageID) else { return }
        var list = visualInteractions(on: pageID)
        if let idx = list.firstIndex(where: { $0.source == source && $0.target == target }) {
            if list[idx].type == type { return }
            list[idx].type = type
        } else {
            list.append(PageVisualInteraction(source: source, target: target, type: type))
        }
        if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
        undoStack.append(snapshot(of: pageID))
        if undoStack.count > Self.historyLimit {
            undoStack.removeFirst()
            cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
        }
        redoStack.removeAll()
        lastCoalesce = nil
        var edit = edited[pageID] ?? PageEdit(visuals: base.visuals, groups: base.groups)
        edit.visualInteractions = list
        edited[pageID] = edit
    }

    /// Đặt nguyên mảng đối tượng định dạng `visual.objects.<object>` cho visual `id` (Wave 3B: CF Rules/Gradient, Data Bars, Analytics lines).
    func setRawObjectArray(object: String, arrayJSON: String?, visual id: String) {
        guard let pageID = currentPageID, let base = page(pageID),
              let idx = base.visuals.firstIndex(where: { $0.id == id }) else { return }
        if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
        undoStack.append(snapshot(of: pageID))
        if undoStack.count > Self.historyLimit {
            undoStack.removeFirst()
            cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
        }
        redoStack.removeAll()
        lastCoalesce = nil

        var edit = edited[pageID] ?? PageEdit(visuals: base.visuals, groups: base.groups)
        var visual = edit.visuals[idx]
        // Cập nhật ngay trên `visual.objects` và `visual.raw` trong bộ nhớ để canvas vẽ tức thời
        var objDict = visual.objects.json.object
        if let arrayJSON, let parsed = try? JSONValue.parse(Data(arrayJSON.utf8)) {
            objDict[object] = parsed
        } else {
            objDict[object] = nil
        }
        visual.objects = ObjectProperties(.object(objDict))
        edit.visuals[idx] = visual
        if let addedBytes = edit.added[id],
           let patched = try? PBIRFormatPatch.replacingObject(object, scope: .objects, arrayJSON: arrayJSON, in: addedBytes) {
            edit.added[id] = patched
        } else {
            var map = edit.rawObjectEdits[id] ?? [:]
            map[object] = arrayJSON
            edit.rawObjectEdits[id] = map
        }
        edited[pageID] = edit
    }

    /// Đổi chủ đề toàn báo cáo (Wave 3B): ghi vào `RegisteredResources/<name>` và `report.json`, hỗ trợ Undo/Redo.
    func setCustomTheme(name: String, data: Data) {
        let pageID = currentPageID ?? structure.order.first ?? ""
        if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
        undoStack.append(snapshot(of: pageID))
        if undoStack.count > Self.historyLimit {
            undoStack.removeFirst()
            cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
        }
        redoStack.removeAll()
        lastCoalesce = nil
        let next = CustomThemeEdit(name: name, data: data)
        customTheme = next
        customThemeChanged(next)
    }

    /// Byte JSON hiện hành của một visual (ưu tiên bản đã sửa/thêm trong phiên).
    func visualJSONBytes(pageID: String, visualID: String) -> Data? {
        if let added = edited[pageID]?.added[visualID] { return added }
        return sourceJSON(pageID, visualID)
    }

    /// Ghi nguyên khối Cascade Rename (Wave 3C): cập nhật `modelEdits`, JSON các visual và các phần PBIR khác trong một bước hoàn tác ⌘Z.
    func commitCascadeRename(
        model: ModelEdits,
        visualUpdates: [(pageID: String, visualID: String, data: Data)],
        partOverrides: [String: Data]
    ) {
        let pageID = currentPageID ?? structure.order.first ?? ""
        undoStack.append(snapshot(of: pageID))
        if undoStack.count > Self.historyLimit {
            undoStack.removeFirst()
            cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
        }
        redoStack.removeAll()
        lastCoalesce = nil

        modelEdits = model
        modelEditsChanged(modelEdits)

        for update in visualUpdates {
            let baseVisuals = basePage(update.pageID)?.visuals ?? []
            let baseGroups = basePage(update.pageID)?.groups ?? []
            var pageEdit = edited[update.pageID] ?? PageEdit(visuals: baseVisuals, groups: baseGroups)
            pageEdit.added[update.visualID] = update.data
            if let vIdx = pageEdit.visuals.firstIndex(where: { $0.id == update.visualID }),
               let parsed = try? JSONValue.parse(update.data),
               let vNode = parsed["visual"] {
                let old = pageEdit.visuals[vIdx]
                pageEdit.visuals[vIdx] = ReportVisual(
                    id: old.id, type: vNode["visualType"]?.string ?? old.type,
                    x: old.x, y: old.y, z: old.z, width: old.width, height: old.height,
                    isHidden: old.isHidden,
                    objects: ObjectProperties(vNode["objects"]),
                    containerObjects: ObjectProperties(vNode["visualContainerObjects"]),
                    fields: PBIXFile.pbirFields(vNode["query"]?["queryState"]),
                    raw: parsed,
                    parentGroup: old.parentGroup
                )
            }
            edited[update.pageID] = pageEdit
        }
        for (path, bytes) in partOverrides {
            pbirPartOverrides[path] = bytes
        }
    }

    /// Các trang theo thứ tự tab, đã sửa (thêm, xoá, đổi tên, đổi thứ tự, bố cục).
    var pages: [ReportPage] { structure.order.compactMap(page(_:)) }

    func visual(_ id: String, page pageID: String? = nil) -> ReportVisual? {
        guard let pageID = pageID ?? currentPageID else { return nil }
        return visuals(of: pageID).first { $0.id == id }
    }

    /// Khoá khi không biết khung nhóm để quy toạ độ: phần tử có `parentGroupName` mà chuỗi nhóm cha (qua mọi cấp lồng nhau)
    /// có nhóm trang không có, hoặc quay vòng.
    func isLockedByGroup(_ id: String) -> Bool {
        guard let item = item(id), let pageID = currentPageID else { return false }
        let groups = groups(of: pageID)
        var seen: Set<String> = [id]
        var parent = item.parentGroup
        while let next = parent {
            guard seen.insert(next).inserted, let group = groups.first(where: { $0.id == next }) else { return true }
            parent = group.parentGroup
        }
        return false
    }

    static let groupLockedMessage = "Nằm trong nhóm không đọc được, chưa sửa được."

    // MARK: Chọn

    func showPage(_ pageID: String?) {
        guard pageID != currentPageID else { return }
        currentPageID = pageID
        selection = []
        primary = nil
        lockedReason = nil
    }

    func select(_ id: String, extend: Bool = false) {
        guard item(id) != nil else { return }
        lockedReason = nil
        if extend {
            if selection.contains(id) {
                selection.remove(id)
                if primary == id { primary = selection.first }
            } else {
                selection.insert(id)
                primary = id
            }
        } else {
            selection = [id]
            primary = id
        }
        if selection.isEmpty { primary = nil }
    }

    func setSelection(_ ids: [String], extend: Bool) {
        guard let pageID = currentPageID else { return }
        let valid = Set(items(of: pageID).map(\.id))
        let chosen = ids.filter(valid.contains)
        if extend { selection.formUnion(chosen) } else { selection = Set(chosen) }
        if let last = chosen.last { primary = last } else if !extend { primary = nil }
        lockedReason = nil
    }

    func clearSelection() {
        selection = []
        primary = nil
        lockedReason = nil
    }

    // MARK: Di chuyển, đổi cỡ

    /// Dời các phần tử (visual và nhóm; bỏ qua phần tử bị khoá). `dx`, `dy` tính theo điểm của trang. Nhóm dời cùng các con.
    func move(_ ids: Set<String>, dx: Int, dy: Int, snap: Bool, coalescing: Bool = false) {
        guard let pageID = currentPageID, let bounds = pageBounds(pageID) else { return }
        let movable = unlocked(ids)
        guard !movable.isEmpty else { return }
        // Phần tử có nhóm tổ tiên cùng được dời thì đi theo nhóm đó.
        let groups = groups(of: pageID)
        let ordered = items(of: pageID).filter { item in
            movable.contains(item.id) && !Self.ancestorIDs(of: item, in: groups).contains(where: movable.contains)
        }
        guard !ordered.isEmpty else { return }
        let moved = LayoutGeometry.move(ordered.map(Frame.init), dx: dx, dy: dy, page: bounds, snap: snap)
        var frames: [String: Frame] = [:]
        for (visual, frame) in zip(ordered, moved) { frames[visual.id] = frame }
        apply(frames: frames, coalescing: coalescing)
    }

    /// Kéo một tay nắm của một phần tử (visual hoặc nhóm).
    func resize(_ id: String, handle: ResizeHandle, dx: Int, dy: Int, snap: Bool) {
        guard let pageID = currentPageID, let bounds = pageBounds(pageID), let visual = item(id) else { return }
        guard !unlocked([id]).isEmpty else { return }
        let frame = LayoutGeometry.resize(Frame(visual), handle: handle, dx: dx, dy: dy, page: bounds, snap: snap)
        apply(frames: [id: frame])
    }

    /// Đặt khung cho nhiều phần tử cùng lúc (cuối một lần kéo) thành đúng một bước hoàn tác.
    /// Nhóm: mọi hậu duệ (kể cả nhóm lồng và con của nó) dời theo khi chỉ đổi vị trí, co theo cùng tỷ lệ khi đổi cỡ
    /// (`ScaleMode`, VM-D7, VM-D8); khung của phần tử có nhóm tổ tiên cùng được đặt thì bị bỏ qua (nhóm đó quyết định).
    /// Thành viên của nhóm bị kẹp trong khung nhóm cha. Phần tử bị khoá bị bỏ qua; không có gì đổi thì không tạo bước.
    func apply(frames: [String: Frame], coalescing: Bool = false) {
        guard let pageID = currentPageID else { return }
        let allowed = unlocked(Set(frames.keys))
        guard !allowed.isEmpty else { return }
        commit(pageID: pageID, coalesceIDs: coalescing ? allowed : nil) { edit in
            // Cây nhóm không đổi trong lúc đặt khung: tính tổ tiên một lần trên trạng thái đầu.
            let tree = edit.groups
            func followsAnAncestor(_ item: ReportVisual) -> Bool {
                Self.ancestorIDs(of: item, in: tree).contains { allowed.contains($0) && frames[$0] != nil }
            }
            for id in tree.map(\.id) where allowed.contains(id) {
                guard var frame = frames[id], let index = edit.groups.firstIndex(where: { $0.id == id }) else { continue }
                let old = edit.groups[index]
                if followsAnAncestor(old) { continue }
                if let parent = old.parentGroup, let outer = edit.groups.first(where: { $0.id == parent }) { frame = Self.clamp(frame, inside: outer) }
                let nx = Double(frame.x), ny = Double(frame.y), nw = Double(frame.width), nh = Double(frame.height)
                guard old.x != nx || old.y != ny || old.width != nw || old.height != nh else { continue }
                let sx = old.width > 0 ? nw / old.width : 1, sy = old.height > 0 ? nh / old.height : 1
                let inside = Self.descendantIDs(of: old.id, in: edit.visuals + edit.groups)
                func scaled(_ item: ReportVisual) -> ReportVisual {
                    var c = item
                    c.x = nx + (c.x - old.x) * sx
                    c.y = ny + (c.y - old.y) * sy
                    c.width = max(1, c.width * sx)
                    c.height = max(1, c.height * sy)
                    return c
                }
                for child in edit.visuals.indices where inside.contains(edit.visuals[child].id) { edit.visuals[child] = scaled(edit.visuals[child]) }
                for child in edit.groups.indices where inside.contains(edit.groups[child].id) { edit.groups[child] = scaled(edit.groups[child]) }
                edit.groups[index].x = nx
                edit.groups[index].y = ny
                edit.groups[index].width = nw
                edit.groups[index].height = nh
            }
            for index in edit.visuals.indices where allowed.contains(edit.visuals[index].id) {
                let visual = edit.visuals[index]
                if followsAnAncestor(visual) { continue }
                guard var frame = frames[visual.id] else { continue }
                if let parent = visual.parentGroup, let group = edit.groups.first(where: { $0.id == parent }) {
                    frame = Self.clamp(frame, inside: group)
                }
                edit.visuals[index].x = Double(frame.x)
                edit.visuals[index].y = Double(frame.y)
                edit.visuals[index].width = Double(frame.width)
                edit.visuals[index].height = Double(frame.height)
            }
        }
    }

    /// `frame` kẹp trong khung của nhóm (con không ra khỏi nhóm; D7 R4).
    static func clamp(_ frame: Frame, inside group: ReportVisual) -> Frame {
        let gx = Int(group.x.rounded(.up)), gy = Int(group.y.rounded(.up))
        let gr = Int((group.x + group.width).rounded(.down)), gb = Int((group.y + group.height).rounded(.down))
        let width = min(frame.width, max(1, gr - gx)), height = min(frame.height, max(1, gb - gy))
        let x = min(max(frame.x, gx), max(gx, gr - width)), y = min(max(frame.y, gy), max(gy, gb - height))
        return Frame(x: x, y: y, width: width, height: height)
    }

    // MARK: Xoá, nhân bản, chép, dán

    /// Xoá các phần tử (visual hoặc nhóm; bỏ qua phần tử bị khoá). Xoá nhóm xoá cả các con; xoá con cuối của một nhóm xoá luôn
    /// nhóm (nhóm rỗng không hợp lệ, D7 R4). Vùng chọn trống sau khi xoá.
    func delete(_ ids: Set<String>) {
        guard let pageID = currentPageID, let base = basePage(pageID) else { return }
        var target = unlocked(ids).intersection(Set(items(of: pageID).map(\.id)))
        guard !target.isEmpty else { return }
        let baselineIDs = Set(base.visuals.map(\.id)).union(base.groups.map(\.id))
        let changed = commit(pageID: pageID) { edit in
            // Xoá nhóm xoá mọi hậu duệ, kể cả nhóm lồng bên trong (VM-D8).
            let everything = edit.visuals + edit.groups
            for group in edit.groups where target.contains(group.id) {
                target.formUnion(Self.descendantIDs(of: group.id, in: everything))
            }
            // Nhóm hết thành viên thì xoá luôn nhóm, lặp lên các cấp ngoài.
            var grew = true
            while grew {
                grew = false
                for group in edit.groups where !target.contains(group.id) {
                    let kids = everything.filter { $0.parentGroup == group.id }.map(\.id)
                    if !kids.isEmpty, kids.allSatisfy(target.contains) { target.insert(group.id); grew = true }
                }
            }
            edit.visuals.removeAll { target.contains($0.id) }
            edit.groups.removeAll { target.contains($0.id) }
            for id in target {
                if edit.added[id] != nil { edit.added[id] = nil } else if baselineIDs.contains(id) { edit.deleted.insert(id) }
            }
        }
        if changed { clearSelection(keepingMessage: true) }
    }

    /// Nhân bản các phần tử: mã mới, lệch `duplicateOffset`, nằm trên cùng, được chọn. Trả mã các bản sao.
    @discardableResult
    func duplicate(_ ids: Set<String>) -> [String] {
        guard let pageID = currentPageID else { return [] }
        let chosen = unlocked(ids)
        let sources = items(of: pageID).filter { chosen.contains($0.id) }
        return makeCopies(copyEntries(sources, page: pageID), shift: LayoutGeometry.duplicateOffset, zStep: LayoutGeometry.zStep)
    }

    /// Cắt các phần tử đang chọn (chép vào clipboard rồi xoá trong 1 bước ⌘Z — Wave 4A).
    func cut() {
        guard !selection.isEmpty else { return }
        copy()
        delete(selection)
    }

    /// Chép các phần tử đang chọn (không có tác dụng lên bố cục).
    func copy() {
        guard let pageID = currentPageID else { return }
        let chosen = items(of: pageID).filter { selection.contains($0.id) && !isLockedByGroup($0.id) }
        clipboard = copyEntries(chosen, page: pageID)
        pasteCount = 0
    }

    private static let paintableObjectKeys: Set<String> = [
        "dataPoint", "labels", "legend", "categoryAxis", "valueAxis",
        "values", "columnHeaders", "grid", "general", "total", "categoryLabels",
    ]

    /// Bắt đầu chế độ Sao định dạng (Format Painter — Wave 4A) từ visual đang chọn duy nhất.
    func beginFormatPainter() {
        guard let pageID = currentPageID, selection.count == 1, let sourceID = selection.first,
              let sourceVisual = visual(sourceID, page: pageID),
              let rawBytes = currentVisualJSON(sourceVisual, page: pageID),
              let parsed = try? JSONValue.parse(rawBytes),
              let vNode = parsed["visual"] else {
            formatPainter = nil
            return
        }
        let container = vNode["visualContainerObjects"]?.object ?? [:]
        let rawObjects = vNode["objects"]?.object ?? [:]
        var compatible: [String: JSONValue] = [:]
        for (k, v) in rawObjects where Self.paintableObjectKeys.contains(k) {
            compatible[k] = v
        }
        formatPainter = FormatPainterPayload(sourceID: sourceID, containerObjects: container, compatibleObjects: compatible)
    }

    func cancelFormatPainter() {
        formatPainter = nil
    }

    /// Áp định dạng từ `formatPainter` lên visual đích trên trang hiện tại (1 bước hoàn tác ⌘Z).
    @discardableResult
    func applyFormatPainter(to targetID: String) -> Bool {
        guard let payload = formatPainter,
              let pageID = currentPageID,
              targetID != payload.sourceID,
              let targetVisual = visual(targetID, page: pageID),
              let rawBytes = currentVisualJSON(targetVisual, page: pageID),
              var root = (try? JSONSerialization.jsonObject(with: rawBytes)) as? [String: Any],
              var vDict = root["visual"] as? [String: Any] else {
            formatPainter = nil
            return false
        }

        func toFoundation(_ value: JSONValue) -> Any {
            switch value {
            case .null: return NSNull()
            case .bool(let b): return b
            case .number(let n): return n
            case .string(let s): return s
            case .array(let arr): return arr.map(toFoundation)
            case .object(let obj): return obj.mapValues(toFoundation)
            }
        }

        if !payload.containerObjects.isEmpty {
            var destContainer = (vDict["visualContainerObjects"] as? [String: Any]) ?? [:]
            for (k, v) in payload.containerObjects { destContainer[k] = toFoundation(v) }
            vDict["visualContainerObjects"] = destContainer
        }
        if !payload.compatibleObjects.isEmpty {
            var destObjects = (vDict["objects"] as? [String: Any]) ?? [:]
            for (k, v) in payload.compatibleObjects { destObjects[k] = toFoundation(v) }
            vDict["objects"] = destObjects
        }
        root["visual"] = vDict
        guard let encoded = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let parsed = try? JSONValue.parse(encoded),
              let vNode = parsed["visual"] else {
            formatPainter = nil
            return false
        }

        let changed = commit(pageID: pageID) { pageEdit in
            pageEdit.added[targetID] = encoded
            pageEdit.formats[targetID] = nil
            if let idx = pageEdit.visuals.firstIndex(where: { $0.id == targetID }) {
                let old = pageEdit.visuals[idx]
                pageEdit.visuals[idx] = ReportVisual(
                    id: old.id, type: old.type, x: old.x, y: old.y, z: old.z,
                    width: old.width, height: old.height, isHidden: old.isHidden,
                    objects: ObjectProperties(vNode["objects"]),
                    containerObjects: ObjectProperties(vNode["visualContainerObjects"]),
                    fields: old.fields, raw: parsed, parentGroup: old.parentGroup
                )
            }
        }
        formatPainter = nil
        return changed
    }

    /// Dán vào trang hiện tại (cùng trang hoặc trang khác): theo Power BI Desktop (VM-D7), vị trí nguồn lệch thêm
    /// `LayoutGeometry.pasteOffset` mỗi lần dán và `z` bằng `z` lớn nhất của trang cộng 1.
    @discardableResult
    func paste() -> [String] {
        guard !clipboard.isEmpty else { return [] }
        pasteCount += 1
        return makeCopies(clipboard, shift: LayoutGeometry.pasteOffset * pasteCount, zStep: 1)
    }

    var hasClipboard: Bool { !clipboard.isEmpty }

    /// `visual.json` hiện tại của visual (đã áp phần sửa trường, văn bản và định dạng, chưa áp vị trí): dùng khi nhân bản và dán.
    private func json(of visual: ReportVisual, page pageID: String) -> Data? {
        guard let json = jsonBeforeFormats(of: visual.id, page: pageID) else { return nil }
        // Lỗi áp định dạng không được nuốt: bản sao thiếu định dạng lặng lẽ là sai (D4, review).
        return try? withFormats(json, page: pageID, id: visual.id)
    }

    /// Như `json(of:page:)` nhưng chưa áp định dạng đang chờ (D4): nền để áp lại cả danh sách `FormatEdit`.
    func jsonBeforeFormats(of id: String, page pageID: String) -> Data? {
        guard var json = baseJSON(of: id, page: pageID) else { return nil }
        guard edited[pageID]?.added[id] == nil else { return json }
        if let lines = edited[pageID]?.texts[id], let applied = try? PBIRVisualPatch.setText(in: json, lines: lines) { json = applied }
        if let wells = edited[pageID]?.queries[id], let applied = try? applyQuery(wells, to: json, retype: edited[pageID]?.retyped[id]) { json = applied }
        return json
    }

    /// `data` với phần sửa định dạng đang chờ của visual có trong file (visual mới đã mang định dạng trong byte).
    func withFormats(_ data: Data, page pageID: String, id: String, formats override: [FormatEdit]? = nil) throws -> Data {
        guard edited[pageID]?.added[id] == nil, let formats = override ?? edited[pageID]?.formats[id], !formats.isEmpty else { return data }
        return try PBIRFormatPatch.apply(formats, to: data)
    }

    /// `visual.json` hiện tại của visual với vị trí đã sửa (D5: nhân bản trang).
    func currentVisualJSON(_ visual: ReportVisual, page pageID: String) -> Data? {
        guard let json = json(of: visual, page: pageID) else { return nil }
        let group = visual.parentGroup.flatMap { id in groups(of: pageID).first { $0.id == id } }
        return (try? Self.patch(json, to: visual, group: group)).flatMap { $0 } ?? json
    }

    /// Container không phải visual đã sao sang trang `pageID` trong phiên (D5); nil nếu trang không có.
    func pageExtraParts(_ pageID: String) -> [String: Data]? { edited[pageID]?.extraParts }

    /// Mã visual mới chưa dùng (và đánh dấu đã dùng).
    func reserveVisualID(avoiding extra: Set<String> = []) -> String {
        let id = PBIRLayoutPatch.makeVisualName(avoiding: usedIDs.union(extra))
        usedIDs.insert(id)
        return id
    }

    /// Ghi nhớ các visual đã tạo trong phiên cho trang (để biết phần nào có thể đã nằm trong file khi xoá).
    func registerCreatedVisuals(_ ids: Set<String>, page pageID: String) { createdIDs[pageID, default: []].formUnion(ids) }

    /// Các phần tử cần sao cho `sources`: nhóm kéo theo mọi con; con chọn riêng (không kèm nhóm) sao thành visual ngoài nhóm.
    private func copyEntries(_ sources: [ReportVisual], page pageID: String) -> [(visual: ReportVisual, json: Data)] {
        var wanted: [ReportVisual] = []
        var seen = Set<String>()
        func add(_ v: ReportVisual) { if seen.insert(v.id).inserted { wanted.append(v) } }
        for source in sources {
            add(source)
            if source.isGroup { for child in descendants(ofGroup: source.id, page: pageID) { add(child) } }
        }
        return wanted.compactMap { visual in json(of: visual, page: pageID).map { (visual: visual, json: $0) } }
    }

    private func makeCopies(_ entries: [(visual: ReportVisual, json: Data)], shift: Int, zStep: Int) -> [String] {
        guard let pageID = currentPageID, let bounds = pageBounds(pageID), !entries.isEmpty else { return [] }
        // Con của nhóm đã sao cùng nhóm: giữ nhóm; con riêng lẻ: ra ngoài nhóm.
        let groupIDs = Set(entries.filter(\.visual.isGroup).map(\.visual.id))
        let frames = LayoutGeometry.move(entries.map { Frame($0.visual) }, dx: shift, dy: shift, page: bounds, snap: false)
        var idMap: [String: String] = [:]
        for entry in entries { idMap[entry.visual.id] = PBIRLayoutPatch.makeVisualName(avoiding: usedIDs.union(idMap.values)) }
        var z = items(of: pageID).map(\.z).max() ?? 0
        var copies: [ReportVisual] = []
        var groupCopies: [ReportVisual] = []
        var data: [String: Data] = [:]
        // Visual trước (z tăng dần), nhóm sau, nhóm trong trước nhóm ngoài: nhóm có `z` lớn hơn thành viên của nó.
        let sourceGroups = entries.filter(\.visual.isGroup).map(\.visual)
        func depth(_ index: Int) -> Int { Self.ancestorIDs(of: entries[index].visual, in: sourceGroups).count }
        let ordered = entries.indices.sorted { a, b in
            let ga = entries[a].visual.isGroup, gb = entries[b].visual.isGroup
            if ga != gb { return !ga }
            if ga, depth(a) != depth(b) { return depth(a) > depth(b) }
            return a < b
        }
        var lastChildZ: [String: Double] = [:]
        for index in ordered {
            let entry = entries[index], source = entry.visual
            guard let id = idMap[source.id] else { continue }
            let frame = frames[index]
            // Thành viên của nhóm đã sao cùng nhóm: giữ nhóm (theo mã mới); còn lại ra ngoài nhóm.
            let parent = source.parentGroup.flatMap { groupIDs.contains($0) ? idMap[$0] : nil }
            let itemZ: Double
            if source.isGroup {
                itemZ = max(z + Double(zStep), (lastChildZ[id] ?? z) + 1)
                z = max(z, itemZ)
                if let parent { lastChildZ[parent] = max(lastChildZ[parent] ?? 0, itemZ) }
            } else {
                z += Double(zStep)
                itemZ = z
                if let parent { lastChildZ[parent] = max(lastChildZ[parent] ?? 0, itemZ) }
            }
            let made = isLegacy
                ? try? LegacyLayoutPatch.duplicated(entry.json, newName: id, x: Double(frame.x), y: Double(frame.y),
                                                    width: Double(frame.width), height: Double(frame.height), z: itemZ)
                : try? PBIRLayoutPatch.duplicated(entry.json, newName: id, x: frame.x, y: frame.y,
                                                  width: frame.width, height: frame.height, z: Int(itemZ))
            guard let patched = made else {
                if !source.isGroup { z -= Double(zStep) }
                continue
            }
            usedIDs.insert(id)
            let raw = isLegacy ? source.raw : ((try? JSONValue.parse(patched)) ?? source.raw)
            if source.isGroup {
                groupCopies.append(ReportVisual(id: id, type: source.type, x: Double(frame.x), y: Double(frame.y), z: itemZ,
                                                width: Double(frame.width), height: Double(frame.height), isHidden: source.isHidden, raw: raw,
                                                parentGroup: parent))
            } else {
                copies.append(ReportVisual(id: id, type: source.type, x: Double(frame.x), y: Double(frame.y), z: itemZ,
                                           width: Double(frame.width), height: Double(frame.height), isHidden: source.isHidden,
                                           objects: source.objects, containerObjects: source.containerObjects, fields: source.fields,
                                           raw: raw, parentGroup: parent))
            }
            data[id] = patched
        }
        guard !copies.isEmpty || !groupCopies.isEmpty else {
            lockedReason = "Không đọc được dữ liệu của visual nguồn để nhân bản."
            return []
        }
        commit(pageID: pageID) { edit in
            edit.visuals.append(contentsOf: copies)
            edit.groups.append(contentsOf: groupCopies)
            edit.added.merge(data) { _, new in new }
        }
        createdIDs[pageID, default: []].formUnion(data.keys)
        let top = (groupCopies + copies).filter { $0.parentGroup == nil }.map(\.id)
        selection = Set(top)
        primary = top.last
        return top
    }

    private func clearSelection(keepingMessage: Bool) {
        selection = []
        primary = nil
        if !keepingMessage { lockedReason = nil }
    }

    // MARK: Sửa trường (D2)

    /// Các ô và trường hiện tại của visual (đã áp phần sửa), theo thứ tự trong file. Rỗng khi không đọc được.
    func fieldWells(of id: String) -> [PBIRQueryPatch.Well] {
        guard let pageID = currentPageID else { return [] }
        if let wells = edited[pageID]?.queries[id] { return wells }
        guard let base = baseJSON(of: id, page: pageID) else { return [] }
        return (try? PBIRQueryPatch.wells(in: base)) ?? []
    }

    /// Lý do visual này chưa sửa được trường, hoặc nil nếu sửa được.
    func fieldEditingBlocker(for id: String) -> String? {
        guard let pageID = currentPageID, visual(id) != nil else { return "Chọn một visual để sửa trường." }
        if isLegacy { return Self.legacyMessage }
        if isLockedByGroup(id) { return "Visual nằm trong nhóm, chưa sửa trường được." }
        guard let base = baseJSON(of: id, page: pageID) else { return "Không đọc được visual.json của visual này (báo cáo định dạng cũ chưa sửa được)." }
        // Visual dữ liệu mới thêm trong phiên chưa có query: được tạo khi thả trường đầu tiên (D3).
        let isNewHere = createdIDs[pageID]?.contains(id) == true
        guard (try? PBIRQueryPatch.wells(in: base)) != nil, hasQueryState(base) || (isNewHere && !WellRules.rules(for: visual(id)!).isEmpty) else {
            return "Visual này chưa có cấu hình trường, chưa tạo mới được."
        }
        return nil
    }

    /// `visual.json` gốc của visual (bản mới thêm: bản hiện tại) đã áp công thức đổi loại, chưa áp trường và vị trí.
    func baseJSON(of id: String, page pageID: String) -> Data? {
        if let added = edited[pageID]?.added[id] { return added }
        guard let source = sourceJSON(pageID, id) else { return nil }
        if let retype = edited[pageID]?.retyped[id], let applied = try? PBIRVisualPatch.setVisualType(in: source, to: retype.type, dropObjectKeys: retype.dropObjectKeys) {
            return applied
        }
        return source
    }

    /// Xoá thông báo và lý do từ chối cũ trước một thao tác mới (D5); đặt thông báo sau thao tác.
    func resetMessages() { fieldRefusal = nil; notice = nil }
    func setNotice(_ message: String?) { notice = message }

    func clearFieldRefusal() { fieldRefusal = nil }
    func noteFieldRefusal(_ message: String?) { fieldRefusal = message }

    /// Thêm `field` vào ô `role`. Trả lý do nếu bị từ chối (và ghi vào `fieldRefusal`), nil nếu thành công.
    @discardableResult
    func addField(_ field: FieldRef, to role: String, visual id: String) -> String? {
        let implicit = allowsImplicitMeasures
        return editFields(id) { wells, visual, _ in FieldEditor.add(field, to: role, wells: wells, visual: visual, implicitMeasures: implicit) }
    }

    /// Mô hình cho phép gộp ngầm: không đặt "discourage implicit measures" (US1; Nhom6 đặt nên vẫn chặn). Không biết mô hình thì chặn.
    var allowsImplicitMeasures: Bool { modelBase.map { !$0.discourageImplicitMeasures } ?? false }

    /// Nhóm kiểu của cột `entity[property]` cho danh sách phép gộp và nhãn.
    func aggregationKind(entity: String, property: String) -> AggregateFunction.ColumnKind {
        VisualQuerySpecReader.kind(of: modelColumn(entity: entity, property: property)?.dataType)
    }

    /// Cột theo mô hình hiệu lực; chưa có thì theo mô hình gốc của file.
    func modelColumn(entity: String, property: String) -> ModelMetadata.Column? {
        modelColumns.first { $0.tableName == entity && $0.name == property }
            ?? modelBase?.columns.first { $0.tableName == entity && $0.name == property }
    }

    /// Nhãn trường hiện ở Build pane và pane Bộ lọc: tên đổi riêng, hoặc nhãn tiếng Việt của phép gộp theo kiểu cột
    /// ("Đầu tiên của Region"), hoặc nhãn thường.
    func label(of field: ReportField) -> String {
        if field.kind == .aggregation, field.displayName?.isEmpty ?? true, let code = field.aggregationFunction,
           let function = AggregateFunction(rawValue: code) {
            return function.label(column: field.property, kind: aggregationKind(entity: field.entity, property: field.property))
        }
        return field.label
    }

    /// Đổi phép gộp của trường gộp (menu của trường ở Build pane), một bước hoàn tác.
    @discardableResult
    func setAggregation(role: String, index: Int, to function: AggregateFunction, visual id: String) -> String? {
        editFields(id) { wells, _, _ in
            guard let elements = wells.first(where: { $0.role == role })?.elements, elements.indices.contains(index) else {
                return .refused("Không có trường để đổi phép gộp.")
            }
            let field = elements[index].field
            return FieldEditor.setAggregation(role: role, index: index, to: function,
                                              kind: self.aggregationKind(entity: field.entity, property: field.property), wells: wells)
        }
    }

    @discardableResult
    func removeField(role: String, index: Int, visual id: String) -> String? {
        editFields(id) { wells, visual, base in
            FieldEditor.remove(role: role, index: index, wells: wells, visual: visual) { field in
                FieldReferences.blocking(in: base, entity: field.entity, property: field.property, queryRef: field.queryRef)
            }
        }
    }

    /// Bỏ mọi cấp của phân cấp `field` khỏi visual trong một bước (Desktop: bỏ tick hàng phân cấp gỡ cả các cấp, VM-D11).
    @discardableResult
    func removeHierarchy(_ field: FieldRef, visual id: String) -> String? {
        editFields(id) { wells, visual, base in
            var current = wells
            let prefix = field.queryRef + "."
            for well in wells {
                for index in well.elements.indices.reversed() where well.elements[index].field.kind == .hierarchyLevel
                    && well.elements[index].field.queryRef.hasPrefix(prefix) {
                    switch FieldEditor.remove(role: well.role, index: index, wells: current, visual: visual, references: { f in
                        FieldReferences.blocking(in: base, entity: f.entity, property: f.property, queryRef: f.queryRef)
                    }) {
                    case .changed(let next): current = next
                    case .refused(let reason): return .refused(reason)
                    case .unchanged: break
                    }
                }
            }
            return current == wells ? .unchanged : .changed(current)
        }
    }

    @discardableResult
    func moveField(role: String, index: Int, to target: String, visual id: String) -> String? {
        let implicit = allowsImplicitMeasures
        return editFields(id) { wells, visual, _ in
            let element = wells.first(where: { $0.role == role })?.elements.dropFirst(index).first
            let column = element.flatMap { e in
                self.modelColumn(entity: e.field.entity, property: e.field.property).map(FieldRef.init(column:))
            }
            return FieldEditor.move(role: role, index: index, to: target, wells: wells, visual: visual, implicitMeasures: implicit, column: column)
        }
    }

    @discardableResult
    func reorderField(role: String, from: Int, to: Int, visual id: String) -> String? {
        editFields(id) { wells, _, _ in FieldEditor.reorder(role: role, from: from, to: to, wells: wells) }
    }

    @discardableResult
    func renameField(role: String, index: Int, to name: String, visual id: String) -> String? {
        editFields(id) { wells, _, _ in FieldEditor.rename(role: role, index: index, to: name, wells: wells) }
    }

    /// Chạy một thao tác sửa trường như đúng một `commit`: dựng `visual.json` mới từ bản gốc, rồi cập nhật `raw` và
    /// `fields` của visual từ chính chuỗi byte đó (cái vẽ chính là cái sẽ lưu).
    private func editFields(_ id: String, _ body: ([PBIRQueryPatch.Well], ReportVisual, Data) -> FieldEditor.Result) -> String? {
        fieldRefusal = nil
        notice = nil
        func refuse(_ message: String) -> String { fieldRefusal = message; return message }
        guard let pageID = currentPageID else { return refuse("Chưa mở trang nào.") }
        if let blocker = fieldEditingBlocker(for: id) { return refuse(blocker) }
        guard let visual = visual(id), let base = baseJSON(of: id, page: pageID) else { return refuse("Không tìm thấy visual.") }
        let wells = edited[pageID]?.queries[id] ?? ((try? PBIRQueryPatch.wells(in: base)) ?? [])
        switch body(wells, visual, base) {
        case .refused(let message):
            return refuse(message)
        case .unchanged:
            return nil
        case .changed(let next):
            let bytes: Data, raw: JSONValue, fields: [ReportField]
            do {
                bytes = try withFormats(try applyQuery(next, to: base, retype: edited[pageID]?.retyped[id]), page: pageID, id: id)
                raw = try JSONValue.parse(bytes)
                fields = try PBIRQueryPatch.fields(in: bytes)
            } catch {
                return refuse("Không ghi được cấu hình trường: \(error)")
            }
            commit(pageID: pageID) { edit in
                guard let index = edit.visuals.firstIndex(where: { $0.id == id }) else { return }
                edit.visuals[index].raw = raw
                edit.visuals[index].fields = fields
                // Sửa trường có thể bỏ định dạng riêng của trường (selector); `objects` theo cùng byte (D4 kiểm khi lưu).
                edit.visuals[index].objects = ObjectProperties(raw["visual"]?["objects"])
                edit.visuals[index].containerObjects = ObjectProperties(raw["visual"]?["visualContainerObjects"])
                edit.queries[id] = next
                if edit.added[id] != nil { edit.added[id] = bytes }
            }
            return nil
        }
    }

    // MARK: Thêm visual mới (D3)

    /// Thêm một visual trống của `type` vào trang hiện tại, ở giữa `visibleRect` (toạ độ trang; nil = cả trang), trên cùng,
    /// và chọn nó. Trả mã visual mới, hoặc nil kèm lý do ở `fieldRefusal`.
    @discardableResult
    func insertVisual(type: String, visibleRect: CGRect?, shapeKind: String? = nil, imageItemName: String? = nil, imageCaption: String? = nil) -> String? {
        fieldRefusal = nil
        notice = nil
        if isLegacy { fieldRefusal = Self.legacyMessage; return nil }
        guard let pageID = currentPageID, let bounds = pageBounds(pageID) else {
            fieldRefusal = "Chưa mở trang nào."
            return nil
        }
        guard let info = VisualTypes.info(for: type) else {
            fieldRefusal = VisualTypes.refusal(for: type)
            return nil
        }
        let width = min(info.defaultSize.width, bounds.width), height = min(info.defaultSize.height, bounds.height)
        let area = visibleRect ?? CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        var frame = Frame(x: Int((area.midX - Double(width) / 2).rounded()), y: Int((area.midY - Double(height) / 2).rounded()),
                          width: width, height: height)
        frame = LayoutGeometry.move(frame, dx: 0, dy: 0, page: bounds, snap: true)
        // Khung bị một visual đã có che từ 90% trở lên (ví dụ vừa thêm lần trước): lệch một bậc, tối đa 10 lần.
        let others = visuals(of: pageID).map(Frame.init)
        var steps = 0
        while steps < 10, others.contains(where: { Self.coverage(of: frame, by: $0) >= 0.9 }) {
            let next = LayoutGeometry.move(frame, dx: LayoutGeometry.duplicateOffset, dy: LayoutGeometry.duplicateOffset, page: bounds, snap: false)
            if next == frame { break }
            frame = next
            steps += 1
        }

        let id = PBIRLayoutPatch.makeVisualName(avoiding: usedIDs)
        let z = (visuals(of: pageID).map(\.z).max() ?? 0) + Double(LayoutGeometry.zStep)
        let siblings = basePage(pageID)?.visuals.prefix(5).compactMap { sourceJSON(pageID, $0.id) } ?? []
        guard let json = try? PBIRNewVisual.makeJSON(name: id, type: type, x: frame.x, y: frame.y, width: frame.width, height: frame.height,
                                                    z: Int(z), schema: PBIRNewVisual.schemaURL(from: Array(siblings)),
                                                    shapeKind: shapeKind ?? "rectangle", imageItemName: imageItemName, imageCaption: imageCaption),
              let raw = try? JSONValue.parse(json) else {
            fieldRefusal = "Không dựng được visual mới."
            return nil
        }
        usedIDs.insert(id)
        let visual = ReportVisual(id: id, type: type, x: Double(frame.x), y: Double(frame.y), z: z,
                                  width: Double(frame.width), height: Double(frame.height),
                                  objects: ObjectProperties(raw["visual"]?["objects"]),
                                  containerObjects: ObjectProperties(raw["visual"]?["visualContainerObjects"]),
                                  fields: [], raw: raw)
        commit(pageID: pageID) { edit in
            edit.visuals.append(visual)
            edit.added[id] = json
        }
        createdIDs[pageID, default: []].insert(id)
        selection = [id]
        primary = id
        return id
    }

    /// Chèn visual `image` kèm dữ liệu ảnh nhúng vào `RegisteredResources` (US4), gộp trong đúng một bước hoàn tác.
    @discardableResult
    func insertImage(data: Data, filename: String, visibleRect: CGRect?) -> (id: String, itemName: String)? {
        guard !data.isEmpty else { fieldRefusal = "Tệp ảnh rỗng."; return nil }
        let baseName = URL(fileURLWithPath: filename).lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let clean = baseName.isEmpty ? "image.png" : baseName
        var existingNames = Set(addedImages.keys)
        if let report = openedParts(Self.reportJSONPath).first(where: { $0.path == Self.reportJSONPath })?.data {
            existingNames.formUnion(PBIRResourcePatch.items(in: report).map(\.name))
        }
        let stem = URL(fileURLWithPath: clean).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: clean).pathExtension
        var itemName = clean
        var suffix = 2
        while existingNames.contains(itemName) {
            itemName = ext.isEmpty ? "\(stem)_\(suffix)" : "\(stem)_\(suffix).\(ext)"
            suffix += 1
        }
        guard let id = insertVisual(type: "image", visibleRect: visibleRect, imageItemName: itemName, imageCaption: clean) else {
            return nil
        }
        addedImages[itemName] = data
        return (id, itemName)
    }

    /// Đổi loại visual `id` sang `type`, giữ vị trí, cỡ, `z`; chuyển trường sang ô tương ứng (R7), tỉa định dạng (R8).
    /// Trả lý do từ chối (cũng ghi ở `fieldRefusal`) hoặc nil. Trường hoặc định dạng bị bỏ được báo ở `notice`.
    @discardableResult
    func changeType(of id: String, to type: String) -> String? {
        fieldRefusal = nil
        notice = nil
        func refuse(_ message: String) -> String { fieldRefusal = message; return message }
        if isLegacy { return refuse(Self.legacyMessage) }
        guard let pageID = currentPageID, let visual = visual(id) else { return refuse("Chọn một visual để đổi loại.") }
        if type == "shapeMap", visual.type != "shapeMap", !hasShapeMapResource {
            return refuse("Báo cáo chưa có bản đồ hình (usa.states.topo); Power BI Desktop tự thêm, BI Pro thì chưa.")
        }
        if isLockedByGroup(id) { return refuse("Visual nằm trong nhóm, chưa đổi loại được.") }
        guard let base = baseJSON(of: id, page: pageID) else { return refuse("Không đọc được visual.json của visual này (báo cáo định dạng cũ chưa sửa được).") }
        let isNew = edited[pageID]?.added[id] != nil
        let wells = edited[pageID]?.queries[id] ?? ((try? PBIRQueryPatch.wells(in: base)) ?? [])
        let currentKeys = Array((visual.raw["visual"]?["objects"]?.object.keys).map { Array($0) } ?? []).sorted()
        var seen = Set<String>()
        for page in baseline.pages {
            for other in page.visuals where other.type == type { seen.formUnion(other.raw["visual"]?["objects"]?.object.keys.map { $0 } ?? []) }
        }
        let plan = TypeChange.plan(visual: visual, wells: wells, to: type, objectKeys: currentKeys, seenObjectKeys: seen) { field in
            FieldReferences.blocking(in: base, entity: field.entity, property: field.property, queryRef: field.queryRef)
        }
        if let blocked = plan.blocked { return refuse(blocked) }
        if plan.isNoOp { return nil }

        let drop = Set(plan.droppedObjectKeys)
        let keptFormats = (edited[pageID]?.formats[id] ?? []).filter { !($0.scope == .objects && drop.contains($0.object)) }
        let bytes: Data, raw: JSONValue, fields: [ReportField]
        var sortsByDate = false
        do {
            let retyped = try Self.applyingTypeDefaults(PBIRVisualPatch.setVisualType(in: base, to: type, dropObjectKeys: drop), type: type)
            // Định dạng chờ của khoá bị bỏ cũng bỏ, nếu không áp lại sẽ tạo lại khoá vừa bỏ (D4, R8).
            // Desktop thêm sắp xếp mặc định tăng dần theo cột ngày khi đổi đường sang cột/thanh (VM-D9 mục 1), vùng, combo,
            // ruy-băng, thác nước, donut, phễu và slicer (VM-D12).
            sortsByDate = Self.defaultSortRole(type).map { isDateColumn(in: plan.wells, role: $0) } ?? false
            let patched = try applyQuery(plan.wells, to: retyped, retype: Retype(type: type, dropObjectKeys: drop, sortsByDateCategory: sortsByDate))
            bytes = try withFormats(patched, page: pageID, id: id, formats: keptFormats)
            raw = try JSONValue.parse(bytes)
            fields = try PBIRQueryPatch.fields(in: bytes)
        } catch {
            return refuse("Không đổi loại được: \(error)")
        }
        commit(pageID: pageID) { edit in
            guard let index = edit.visuals.firstIndex(where: { $0.id == id }) else { return }
            edit.visuals[index].type = type
            edit.visuals[index].raw = raw
            edit.visuals[index].fields = fields
            edit.visuals[index].objects = ObjectProperties(raw["visual"]?["objects"])
            edit.visuals[index].containerObjects = ObjectProperties(raw["visual"]?["visualContainerObjects"])
            // Công thức luôn được ghi (kể cả visual mới thêm: sau lần lưu đầu nó đã nằm trong file và lần lưu sau áp công thức);
            // visual mới còn cập nhật byte hiện tại ở `added`.
            edit.queries[id] = plan.wells
            edit.formats[id] = keptFormats.isEmpty ? nil : keptFormats
            edit.retyped[id] = Retype(type: type, dropObjectKeys: (edit.retyped[id]?.dropObjectKeys ?? []).union(drop), sortsByDateCategory: sortsByDate)
            if isNew { edit.added[id] = bytes }
        }
        notice = plan.notice
        return nil
    }

    /// Khoá và mục Desktop tự thêm khi visual thành `type` (VM-D12): bản đồ hình có `objects.shape` và mục tô màu chuyển sắc.
    nonisolated static func applyingTypeDefaults(_ json: Data, type: String) throws -> Data {
        switch type {
        case "shapeMap": return try PBIRVisualPatch.addingShapeMapDefaults(to: json)
        // Thác nước và phễu không có trục liên tục: Desktop bỏ `axisType` khỏi `categoryAxis` (VM-D12).
        case "waterfallChart", "funnel": return try PBIRVisualPatch.removingCategoryAxisType(from: json)
        default: return json
        }
    }

    /// Báo cáo có tài nguyên bản đồ `usa.states.topo` (Desktop tự thêm nó vào file nếu thiếu; BI Pro không có nguồn của nó).
    var hasShapeMapResource: Bool {
        guard let report = openedParts(Self.reportJSONPath).first(where: { $0.path == Self.reportJSONPath })?.data else { return false }
        return PBIRResourcePatch.items(in: report).contains { $0.type == "ShapeMap" && $0.name == "usa.states.topo" }
    }

    /// Cột đầu của ô `role` là cột kiểu ngày giờ của mô hình.
    func isDateColumn(in wells: [PBIRQueryPatch.Well], role: String) -> Bool {
        guard let field = wells.first(where: { $0.role == role })?.elements.first?.field, field.kind == .column else { return false }
        return dateColumns.contains("\(field.entity)[\(field.property)]")
    }

    /// Cột đầu của ô `role` là cột kiểu số hoặc ngày giờ của mô hình.
    func isNumericOrDateColumn(in wells: [PBIRQueryPatch.Well], role: String) -> Bool {
        guard let field = wells.first(where: { $0.role == role })?.elements.first?.field, field.kind == .column else { return false }
        let key = "\(field.entity)[\(field.property)]"
        if dateColumns.contains(key) || decimalColumns.contains(key) || currencyColumns.contains(key) { return true }
        if let col = modelColumn(entity: field.entity, property: field.property) {
            switch col.dataType {
            case .int64, .double, .decimal, .dateTime: return true
            default: return false
            }
        }
        return false
    }

    /// `PBIRQueryPatch.apply`, đặt `mode = 'Between'` cho `slicer` cổ điển khi nhận cột số/ngày chưa có `objects.data`
    /// (VM-V11A `pop-slicer.visual.json`), rồi thêm sắp xếp mặc định tăng dần theo cột ngày nếu lần đổi loại của visual đòi (VM-D9 mục 1).
    func applyQuery(_ wells: [PBIRQueryPatch.Well], to json: Data, retype: Retype?) throws -> Data {
        var out = try PBIRQueryPatch.apply(wells, to: json)
        if isNumericOrDateColumn(in: wells, role: "Values") {
            out = try PBIRQueryPatch.settingSlicerModeIfUnset("Between", in: out)
        }
        guard retype?.sortsByDateCategory == true, let type = retype?.type, let role = Self.defaultSortRole(type),
              isDateColumn(in: wells, role: role) else { return out }
        return try PBIRQueryPatch.addingDefaultCategorySort(out, role: role)
    }

    /// Ô mà Desktop sắp tăng dần theo cột ngày sau khi đổi loại (VM-D9 mục 1, VM-D12): `Category` của cột, thanh, vùng
    /// (cả xếp chồng và 100%), hai loại combo, ruy-băng, thác nước, donut, phễu; `Values` của slicer. Không có ở treemap,
    /// bảng, matrix, KPI và bản đồ hình (đều quan sát được là không thêm).
    static func defaultSortRole(_ type: String) -> String? {
        if type == "slicer" { return "Values" }
        let withCategory = type.hasSuffix("ColumnChart") || type.hasSuffix("BarChart") || type == "columnChart" || type == "barChart"
            || type.hasSuffix("AreaChart") || type == "areaChart" || type.hasSuffix("ComboChart")
            || ["ribbonChart", "waterfallChart", "donutChart", "pieChart", "funnel"].contains(type)
        return withCategory ? "Category" : nil
    }

    /// Phần diện tích của `frame` bị `other` che (0...1).
    private static func coverage(of frame: Frame, by other: Frame) -> Double {
        let width = min(frame.right, other.right) - max(frame.x, other.x)
        let height = min(frame.bottom, other.bottom) - max(frame.y, other.y)
        guard width > 0, height > 0, frame.width > 0, frame.height > 0 else { return 0 }
        return Double(width * height) / Double(frame.width * frame.height)
    }

    // MARK: Hộp văn bản (D3)

    /// Văn bản mỗi đoạn của một hộp văn bản (các lượt của một đoạn ghép lại), đọc từ JSON của visual.
    static func paragraphTexts(of raw: JSONValue) -> [String] {
        let paragraphs = raw["visual"]?["objects"]?["general"]?[0]?["properties"]?["paragraphs"]?.array ?? []
        return paragraphs.map { paragraph in (paragraph["textRuns"]?.array ?? []).map { $0["value"]?.string ?? "" }.joined() }
    }

    /// Đặt nội dung hộp văn bản `id`: mỗi dòng là một đoạn (R9). Trả lý do từ chối hoặc nil. Không đổi gì thì không tạo bước.
    @discardableResult
    func setText(_ text: String, visual id: String) -> String? {
        fieldRefusal = nil
        notice = nil
        func refuse(_ message: String) -> String { fieldRefusal = message; return message }
        if isLegacy { return refuse(Self.legacyMessage) }
        guard let pageID = currentPageID, let visual = visual(id) else { return refuse("Chọn một hộp văn bản để sửa.") }
        guard visual.type == "textbox" else { return refuse("Chỉ hộp văn bản mới sửa được nội dung.") }
        if isLockedByGroup(id) { return refuse("Visual nằm trong nhóm, chưa sửa được.") }
        guard let base = baseJSON(of: id, page: pageID) else { return refuse("Không đọc được visual.json của visual này.") }
        let lines = text.components(separatedBy: "\n")
        let bytes: Data, raw: JSONValue
        do {
            bytes = try withFormats(try PBIRVisualPatch.setText(in: base, lines: lines), page: pageID, id: id)
            raw = try JSONValue.parse(bytes)
        } catch {
            return refuse("Không ghi được nội dung: \(error)")
        }
        commit(pageID: pageID) { edit in
            guard let index = edit.visuals.firstIndex(where: { $0.id == id }) else { return }
            edit.visuals[index].raw = raw
            edit.visuals[index].objects = ObjectProperties(raw["visual"]?["objects"])
            edit.texts[id] = lines
            if edit.added[id] != nil { edit.added[id] = bytes }
        }
        return nil
    }

    // MARK: Hoàn tác

    func undo() {
        guard let step = undoStack.popLast() else { return }
        redoStack.append(snapshot(of: currentPageID ?? step.pageID))
        restore(step)
        resetMessages()
        lastCoalesce = nil
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        undoStack.append(snapshot(of: currentPageID ?? step.pageID))
        restore(step)
        resetMessages()
        lastCoalesce = nil
    }

    /// Gọi sau khi lưu thành công: trạng thái hiện tại là trạng thái sạch.
    func markSaved() {
        savedEdits = reportEdits
        savedModelEdits = modelEdits
        if !diagramEdits.isEmpty || !savedDiagramEdits.isEmpty { savedDiagramEdits = mergedDiagramBaseline() }
        cleanMark = undoStack.count
        lastCoalesce = nil
    }

    // MARK: Nội bộ

    private func pageBounds(_ pageID: String) -> PageBounds? {
        basePage(pageID).map(PageBounds.init)
    }

    /// Bỏ visual trong nhóm; nếu có bỏ thì ghi lý do.
    private func unlocked(_ ids: Set<String>) -> Set<String> {
        let allowed = ids.filter { !isLockedByGroup($0) }
        lockedReason = allowed.count < ids.count ? Self.groupLockedMessage : nil
        return allowed
    }

    private func snapshot(of pageID: String) -> LayoutSnapshot {
        LayoutSnapshot(pageID: pageID, edited: edited, structure: structure, selection: selection, primary: primary, edits: reportEdits,
                       model: modelEdits, diagram: diagramEdits, addedImages: addedImages, customTheme: customTheme,
                       pbirPartOverrides: pbirPartOverrides)
    }

    private func restore(_ step: LayoutSnapshot) {
        edited = step.edited
        structure = step.structure
        reportEdits = step.edits
        addedImages = step.addedImages
        pbirPartOverrides = step.pbirPartOverrides
        if customTheme != step.customTheme {
            customTheme = step.customTheme
            customThemeChanged(customTheme)
        }
        if modelEdits != step.model {
            modelEdits = step.model
            modelEditsChanged(modelEdits)
        }
        diagramEdits = step.diagram
        // Trang của bước có thể không còn trong dãy (hoàn tác thêm trang): về trang đầu.
        let target = structure.order.contains(step.pageID) ? step.pageID : structure.order.first
        if currentPageID != target { currentPageID = target }
        selection = step.selection
        primary = step.primary
    }

    /// Chạy `body` trên bản sao sửa được của trang. Không đổi gì thì không tạo bước và không tạo bản sao trang.
    /// `coalesceIDs` khác nil: nhiều lần gọi liên tiếp trong 0,5 s cho cùng nhóm chọn gộp thành một bước.
    @discardableResult
    func commit(pageID: String, coalesceIDs: Set<String>? = nil, _ body: (inout PageEdit) -> Void) -> Bool {
        let before = edited[pageID]
        let initial = PageEdit(visuals: basePage(pageID)?.visuals ?? [], groups: basePage(pageID)?.groups ?? [])
        var working = before ?? initial
        body(&working)
        guard working != (before ?? initial) else { return false }

        let time = now()
        var merged = false
        if let key = coalesceIDs, let last = lastCoalesce, last.pageID == pageID, last.ids == key,
           time.timeIntervalSince(last.at) < Self.coalesceWindow, !undoStack.isEmpty {
            merged = true
        }
        if !merged {
            // Quay lại trạng thái "sạch" nằm trong nhánh làm lại đã bị xoá: không còn là sạch.
            if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
            undoStack.append(snapshot(of: pageID))
            if undoStack.count > Self.historyLimit {
                undoStack.removeFirst()
                cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
            }
        }
        redoStack.removeAll()
        edited[pageID] = working
        lastCoalesce = coalesceIDs.map { (pageID, $0, time) }
        return true
    }

    /// Một thao tác cấp báo cáo (D5): sửa `structure` và các `PageEdit` cùng lúc, đúng một bước hoàn tác, không gộp theo
    /// thời gian. Không đổi gì thì không tạo bước. Người gọi tự đặt trang đang mở sau khi xong.
    @discardableResult
    func commitStructure(_ body: (inout PageStructure, inout [String: PageEdit]) -> Void) -> Bool {
        var newStructure = structure, newEdited = edited
        body(&newStructure, &newEdited)
        guard newStructure != structure || newEdited != edited else { return false }
        if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
        undoStack.append(snapshot(of: currentPageID ?? structure.order.first ?? ""))
        if undoStack.count > Self.historyLimit {
            undoStack.removeFirst()
            cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
        }
        redoStack.removeAll()
        structure = newStructure
        edited = newEdited
        lastCoalesce = nil
        return true
    }

    /// Một thao tác bookmark hoặc bộ lọc (D6): sửa `reportEdits`, đúng một bước hoàn tác. `coalesceKey`: các lần gọi liên tiếp
    /// trong 0,5 s với cùng khoá (gõ, chọn giá trị trong một thẻ lọc) gộp thành một bước. Không đổi gì thì không tạo bước.
    @discardableResult
    func commitReport(coalesceKey: String? = nil, _ body: (inout ReportEdits) -> Void) -> Bool {
        var working = reportEdits
        body(&working)
        guard working != reportEdits else { return false }
        let time = now()
        var merged = false
        if let key = coalesceKey, let last = lastCoalesce, last.pageID == Self.reportCoalesceScope, last.ids == [key],
           time.timeIntervalSince(last.at) < Self.coalesceWindow, !undoStack.isEmpty {
            merged = true
        }
        if !merged {
            if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
            undoStack.append(snapshot(of: currentPageID ?? structure.order.first ?? ""))
            if undoStack.count > Self.historyLimit {
                undoStack.removeFirst()
                cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
            }
        }
        redoStack.removeAll()
        reportEdits = working
        lastCoalesce = coalesceKey.map { (Self.reportCoalesceScope, [$0], time) }
        return true
    }

    static let reportCoalesceScope = "\u{0}report"
    static let modelCoalesceScope = "\u{0}model"
    static let diagramCoalesceScope = "\u{0}diagram"

    /// Một thao tác ở Model view (kéo thẻ, thu phóng): đặt `diagramEdits`, đúng một bước hoàn tác. `coalesceKey`: các lần gọi liên
    /// tiếp trong 0,5 s với cùng khoá (đang kéo một thẻ, đang trượt thu phóng) gộp thành một bước.
    @discardableResult
    func commitDiagram(_ edits: DiagramEdits, coalesceKey: String? = nil) -> Bool {
        guard edits != diagramEdits else { return false }
        let time = now()
        var merged = false
        if let key = coalesceKey, let last = lastCoalesce, last.pageID == Self.diagramCoalesceScope, last.ids == [key],
           time.timeIntervalSince(last.at) < Self.coalesceWindow, !undoStack.isEmpty {
            merged = true
        }
        if !merged {
            if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
            undoStack.append(snapshot(of: currentPageID ?? structure.order.first ?? ""))
            if undoStack.count > Self.historyLimit {
                undoStack.removeFirst()
                cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
            }
        }
        redoStack.removeAll()
        diagramEdits = edits
        lastCoalesce = coalesceKey.map { (Self.diagramCoalesceScope, [$0], time) }
        return true
    }

    /// Vị trí gốc đã biết (hiện tại và của lần lưu trước): cần để ghi lại vị trí cũ khi hoàn tác sau khi đã lưu.
    private func mergedDiagramBaseline() -> DiagramEdits {
        var result = diagramEdits
        for (diagram, tables) in savedDiagramEdits.baseline {
            for (table, point) in tables where result.baseline[diagram]?[table] == nil { result.baseline[diagram, default: [:]][table] = point }
        }
        for (diagram, percent) in savedDiagramEdits.zoomBaseline where result.zoomBaseline[diagram] == nil { result.zoomBaseline[diagram] = percent }
        return result
    }

    /// Thao tác ghi vào `DiagramLayout` ở lần lưu này: vị trí hiện tại của mọi thẻ đã kéo, và vị trí gốc của thẻ đã kéo ở lần lưu
    /// trước nhưng nay đã về chỗ cũ. Rỗng khi không có gì cần ghi.
    func diagramMoves() -> (moves: [DiagramLayoutPatch.Move], zoom: [String: Double]) {
        let baselines = mergedDiagramBaseline().baseline
        var moves: [DiagramLayoutPatch.Move] = []
        // Mục của lần lưu trước chỉ còn dùng cho tab vẫn là tab đó (cùng tên, cùng tab nguồn trong file): tab đã đổi tên, xoá hoặc
        // trùng tên một tab mới thì bỏ (patch dựng lại từ file gốc, vị trí gốc đã có sẵn trong đó).
        let file = diagramFileNames()
        func sources(_ edits: DiagramEdits) -> [String: Int] {
            var result: [String: Int] = [:]
            for tab in edits.entries ?? file.enumerated().map({ DiagramEdits.Tab(name: $0.element, source: $0.offset) }) {
                if let source = tab.source { result[tab.name] = source }
            }
            return result
        }
        let currentSources = sources(diagramEdits), savedSources = sources(savedDiagramEdits)
        let liveTabs = diagramEdits.tabs
        let liveNow: (String) -> Bool = { diagram in liveTabs.map { $0.contains(diagram) } ?? true }
        let liveSaved: (String) -> Bool = { diagram in currentSources[diagram] != nil && currentSources[diagram] == savedSources[diagram] }
        let removed = diagramEdits.removed
        let currentDiagrams = Set(diagramEdits.positions.keys).filter(liveNow)
        let savedDiagrams = Set(savedDiagramEdits.positions.keys).filter(liveSaved)
        for diagram in currentDiagrams.union(savedDiagrams).sorted() {
            var tables = Set(diagramEdits.positions[diagram]?.keys ?? [:].keys)
            if savedDiagrams.contains(diagram) { tables.formUnion(savedDiagramEdits.positions[diagram]?.keys ?? [:].keys) }
            for table in tables.sorted() where removed[diagram]?.contains(table) != true {
                guard let point = diagramEdits.positions[diagram]?[table] ?? (savedDiagrams.contains(diagram) ? baselines[diagram]?[table] : nil) else { continue }
                moves.append(.init(diagram: diagram, table: table, x: Double(point.x), y: Double(point.y)))
            }
        }
        // Thu phóng: mọi tab đã sửa (hiện tại hoặc ở lần lưu trước); tab đã về thu phóng gốc thì ghi lại giá trị gốc.
        var zoom: [String: Double] = [:]
        let zoomBaselines = savedDiagramEdits.zoomBaseline.merging(diagramEdits.zoomBaseline) { _, current in current }
        for diagram in Set(diagramEdits.zoom.keys).filter(liveNow).union(Set(savedDiagramEdits.zoom.keys).filter(liveSaved)) {
            if let percent = diagramEdits.zoom[diagram] ?? zoomBaselines[diagram] { zoom[diagram] = percent }
        }
        return (moves, zoom)
    }

    /// Tab theo thứ tự mong muốn cho `DiagramLayoutPatch` (nil = như trong file).
    func diagramTabsForPatch() -> [DiagramLayoutPatch.Tab]? {
        diagramEdits.entries?.map { DiagramLayoutPatch.Tab(name: $0.name, source: $0.source) }
    }

    /// Nút cần gỡ khỏi tab ở lần lưu này (chỉ nút có trong file; tab đã xoá thì không cần).
    func diagramRemovals() -> [DiagramLayoutPatch.Removal] {
        let live = diagramEdits.tabs.map(Set.init)
        return diagramEdits.removed.filter { live?.contains($0.key) ?? true }
            .flatMap { diagram, tables in tables.sorted().map { DiagramLayoutPatch.Removal(diagram: diagram, table: $0) } }
            .sorted { ($0.diagram, $0.table) < ($1.diagram, $1.table) }
    }

    /// Một thao tác sửa mô hình (Phase E): đặt `modelEdits`, đúng một bước hoàn tác. `coalesceKey`: các lần gọi liên tiếp
    /// trong 0,5 s với cùng khoá (gõ biểu thức, đổi thuộc tính) gộp thành một bước. Không đổi gì thì không tạo bước.
    @discardableResult
    func commitModel(_ edits: ModelEdits, coalesceKey: String? = nil) -> Bool {
        guard edits != modelEdits else { return false }
        let time = now()
        var merged = false
        if let key = coalesceKey, let last = lastCoalesce, last.pageID == Self.modelCoalesceScope, last.ids == [key],
           time.timeIntervalSince(last.at) < Self.coalesceWindow, !undoStack.isEmpty {
            merged = true
        }
        if !merged {
            if !redoStack.isEmpty, cleanMark > undoStack.count { cleanMark = -1 }
            undoStack.append(snapshot(of: currentPageID ?? structure.order.first ?? ""))
            if undoStack.count > Self.historyLimit {
                undoStack.removeFirst()
                cleanMark = cleanMark > 0 ? cleanMark - 1 : -1
            }
        }
        redoStack.removeAll()
        modelEdits = edits
        lastCoalesce = coalesceKey.map { (Self.modelCoalesceScope, [$0], time) }
        modelEditsChanged(edits)
        return true
    }

    /// Chuyển trang đang mở không tạo bước hoàn tác; trang phải có trong dãy.
    func openPage(_ pageID: String) {
        guard structure.order.contains(pageID) else { return }
        showPage(pageID)
    }

    // MARK: Gói thay đổi để lưu

    /// Tuỳ chọn "Tự phát hiện quan hệ" của file lúc mở (part `Settings`); file không có part thì bật.
    var openedAutodetectRelationships: Bool {
        openedParts(FileSettings.path).first { $0.path == FileSettings.path }.map { FileSettings.autodetectRelationships(in: $0.data) } ?? true
    }

    /// Tuỳ chọn hiệu lực: phần đã đặt trong phiên, hoặc như lúc mở.
    var autodetectRelationships: Bool { reportEdits.autodetectRelationships ?? openedAutodetectRelationships }

    /// Đặt tuỳ chọn "Tự phát hiện quan hệ" (một bước hoàn tác). Về giá trị lúc mở thì bỏ phần đặt.
    @discardableResult
    func setAutodetectRelationships(_ enabled: Bool) -> Bool {
        guard enabled != autodetectRelationships else { return false }
        return commitReport { $0.autodetectRelationships = enabled == openedAutodetectRelationships ? nil : enabled }
    }

    /// Ghi `Settings` khi tuỳ chọn hiệu lực khác file trên đĩa (cả khi hoàn tác sau lần lưu trước).
    private func addSettingsChanges(to changes: inout PBIXChanges, archive: ZipArchive) throws {
        guard let entry = archive.entry(FileSettings.path) else { return }
        let onDisk = try archive.read(entry)
        guard FileSettings.autodetectRelationships(in: onDisk) != autodetectRelationships else { return }
        changes.reportParts[FileSettings.path] = try FileSettings.setting(autodetectRelationships: autodetectRelationships, in: onDisk)
    }

    nonisolated static func visualPath(page: String, id: String) -> String {
        "Report/definition/pages/\(page)/visuals/\(id)/visual.json"
    }

    nonisolated static func pagePath(_ page: String) -> String { "Report/definition/pages/\(page)/page.json" }
    nonisolated static let pagesFolder = "Report/definition/pages/"
    nonisolated static let pagesJSONPath = "Report/definition/pages/pages.json"
    nonisolated static let bookmarksFolder = "Report/definition/bookmarks/"
    nonisolated static let bookmarksJSONPath = "Report/definition/bookmarks/bookmarks.json"

    /// Mã trang của các thư mục trang có trong `archive`, và các part của từng trang.
    private static func pageParts(in archive: ZipArchive) -> [String: [String]] {
        var parts: [String: [String]] = [:]
        for entry in archive.entries where entry.path.hasPrefix(pagesFolder) {
            let rest = entry.path.dropFirst(pagesFolder.count).split(separator: "/", omittingEmptySubsequences: false)
            guard rest.count >= 2 else { continue }      // `pages.json`
            parts[String(rest[0]), default: []].append(entry.path)
        }
        return parts
    }

    /// Các thay đổi cần ghi vào file `archive` (file đang có trên đĩa, không nhất thiết bản lúc mở): `visual.json` ghép
    /// byte cho visual đổi vị trí, phần mới cho bản sao, bỏ phần của visual đã xoá, dọn tham chiếu tới visual đã xoá trong
    /// bookmark và `page.json`; và (D5) trang mới, tên trang, thứ tự trang, trang bị xoá cùng bookmark trỏ tới chúng.
    /// Mọi thay đổi trang so với file trên đĩa nên lưu lần hai không ghi lại gì.
    /// Thao tác mô hình cần ghi vào file trên đĩa: lần lưu đầu là cả `modelEdits`; các lần sau là phần đưa mô hình đã lưu
    /// (`savedModelEdits`, đang nằm trong file) tới mô hình hiện tại.
    /// `modelDelta` đã gộp (thêm rồi sửa/xoá trong cùng đợt) và kèm thao tác ghi lại cột/bảng tính toán phụ thuộc có sẵn trong file (T116).
    func writableModelDelta() throws -> ModelEdits {
        var edits = try modelDelta().collapsingTableEdits()
        for edit in recalculationEdits(edits) { edits.append(edit) }
        return edits
    }

    func modelDelta() throws -> ModelEdits {
        if savedModelEdits.isEmpty { return try TableLoader.writable(modelEdits) }
        guard let base = modelBase else { throw ModelEditError("Thiếu mô hình gốc để tính phần đổi của lần lưu này") }
        // Thứ tự: (1) phần so mô hình xoá measure/quan hệ: chỉ nhắm vào đối tượng đã có trong file, phải đi trước khi xoá bảng chứa
        // chúng (bộ ghi từ chối xoá bảng còn measure/quan hệ; lỗi T096); (2) thao tác bảng sau lần lưu trước, giữ thứ tự (xoá A rồi nạp
        // A mới vẫn đúng); (3) phần so mô hình còn lại (measure và quan hệ trên bảng mới đứng sau bảng).
        let saved = Set(savedModelEdits.items)
        let diff = ModelMetadata.edits(from: try base.applying(savedModelEdits), to: try base.applying(modelEdits)).items
        func isDeletion(_ edit: ModelEdit) -> Bool {
            switch edit {
            case .deleteMeasure, .deleteRelationship: true
            default: false
            }
        }
        var delta = ModelEdits(diff.filter(isDeletion))
        // Auto date/time (T032): phép so mô hình không thấy variation, phân cấp, chú thích, cột và quan hệ của bảng ngày nên các thao tác
        // này lấy thẳng từ danh sách, giữ thứ tự cùng thao tác bảng.
        let savedModel = try base.applying(savedModelEdits)
        var dateRelationships = Set(savedModel.dateTableRelationships.map(\.name))
        func isAutoDate(_ table: String) -> Bool { AutoDateTime.isLocalTable(table) || AutoDateTime.isTemplateTable(table) }
        for edit in modelEdits.items {
            switch edit {
            case .addTable, .replaceTable, .dropTable, .addCalculatedColumn, .addCalculatedTable,
                 .updateCalculatedColumn, .deleteCalculatedColumn, .updateCalculatedTable,
                 .addHierarchy, .dropHierarchy, .addVariation, .dropVariation:
                if !saved.contains(edit) { delta.append(edit) }
            case .updateColumn(let table, _, _), .updateTable(let table, _):
                if isAutoDate(table), !saved.contains(edit) { delta.append(edit) }
            case .addRelationship(let r):
                guard isAutoDate(r.toTable) || isAutoDate(r.fromTable) else { break }
                dateRelationships.insert(r.name)
                if !saved.contains(edit) { delta.append(edit) }
            case .deleteRelationship(let name):
                if dateRelationships.contains(name), !saved.contains(edit) { delta.append(edit) }
            default: break
            }
        }
        for edit in diff where !isDeletion(edit) { delta.append(edit) }
        // Chú thích mô hình: giá trị cuối khác lần lưu trước (bật rồi tắt rồi bật lại vẫn đúng).
        let current = try base.applying(modelEdits).modelAnnotations
        var names: [String] = []
        for case .setModelAnnotation(let name, _) in modelEdits.items where !names.contains(name) { names.append(name) }
        for name in names where current[name] != savedModel.modelAnnotations[name] {
            if let value = current[name] { delta.append(.setModelAnnotation(name: name, value: value)) }
        }
        return try TableLoader.writable(delta)
    }

    func makeChanges(archive: ZipArchive) throws -> PBIXChanges {
        if isLegacy {
            var legacy = try makeLegacyChanges(archive: archive)
            try addSettingsChanges(to: &legacy, archive: archive)
            legacy.modelEdits = try writableModelDelta()
            if legacy.modelEdits.hasCalculatedEdits { legacy.calculatedData = try calculatedValues(legacy.modelEdits) }
            if diagramEdits != savedDiagramEdits, let source = diagramSource() {
                let (moves, zoom) = diagramMoves()
                legacy.diagramLayout = try DiagramLayoutPatch.applying(tabs: diagramTabsForPatch(), selected: diagramSelected(), removals: diagramRemovals(), moves: moves, zoom: zoom,
                                                                       to: source, lineageTag: diagramLineageTag)
            }
            return legacy
        }
        var changes = PBIXChanges()
        var removedIDs = Set<String>()
        let diskPages = Self.pageParts(in: archive)
        let order = structure.order
        // Chỉ trang người dùng đã xoá trong phiên; thư mục trang lạ trong file (không có trong pageOrder) giữ nguyên (review).
        let known = structure.removed.union(usedPageIDs)   // trang của báo cáo lúc mở hoặc tạo trong phiên
        let removedPages = Set(diskPages.keys).subtracting(order).intersection(known)

        // Hoàn tác sau khi đã lưu việc xoá trang: trang của file lúc mở có trong dãy mà file trên đĩa không còn thư mục
        // của nó. Dựng lại từ byte lúc mở: coi các part đó như đang có trên đĩa (`exists`, `bytes`) để phần sửa trong phiên
        // áp lên như thường, cuối cùng chuyển chúng sang `addedParts`.
        var restored: [String: Data] = [:]
        var revivedPages = Set<String>()
        for pageID in order where structure.created[pageID] == nil && diskPages[pageID] == nil {
            for part in openedParts("\(Self.pagesFolder)\(pageID)/") { restored[part.path] = part.data }
            revivedPages.insert(pageID)
        }
        // Bookmark lúc mở có nhắc trang được dựng lại: lần lưu việc xoá đã gỡ nó hoặc bỏ mục của trang. Lấy lại byte lúc mở
        // (trừ bookmark người dùng tự xoá); phần dọn bên dưới bỏ khỏi đó những trang và visual hiện vẫn đang bị xoá.
        var revivedBookmarks: [String: String] = [:]      // đường dẫn → tên
        if !revivedPages.isEmpty {
            for part in openedParts(Self.bookmarksFolder) where part.path.hasSuffix(".bookmark.json") {
                guard let info = BookmarkInfo(json: part.data), !reportEdits.bookmarks.deleted.contains(info.name),
                      info.activeSection.map(revivedPages.contains) == true || !revivedPages.isDisjoint(with: info.sections) else { continue }
                restored[part.path] = part.data
                revivedBookmarks[part.path] = info.name
            }
        }
        func exists(_ path: String) -> Bool { restored[path] != nil || archive.entry(path) != nil }
        func bytes(_ path: String) throws -> Data { try restored[path] ?? archive.read(path) }

        for pageID in edited.keys.sorted() where order.contains(pageID) {
            guard let edit = edited[pageID], let base = basePage(pageID) else { continue }
            for (id, data) in edit.extraParts where archive.entry(Self.visualPath(page: pageID, id: id)) == nil {
                changes.addedParts[Self.visualPath(page: pageID, id: id)] = data
            }
            for visual in edit.visuals + edit.groups {
                let path = Self.visualPath(page: pageID, id: visual.id)
                let group = visual.parentGroup.flatMap { id in edit.groups.first { $0.id == id } }
                if exists(path) {
                    let onDisk = try bytes(path)
                    var json = onDisk
                    if let retype = edit.retyped[visual.id] {
                        json = try Self.applyingTypeDefaults(PBIRVisualPatch.setVisualType(in: json, to: retype.type, dropObjectKeys: retype.dropObjectKeys), type: retype.type)
                    }
                    if let lines = edit.texts[visual.id] { json = try PBIRVisualPatch.setText(in: json, lines: lines) }
                    if let wells = edit.queries[visual.id] { json = try applyQuery(wells, to: json, retype: edit.retyped[visual.id]) }
                    if let formats = edit.formats[visual.id] { json = try PBIRFormatPatch.apply(formats, to: json) }
                    if let rawMap = edit.rawObjectEdits[visual.id] {
                        for (objKey, arrayJSON) in rawMap.sorted(by: { $0.key < $1.key }) {
                            json = try PBIRFormatPatch.replacingObject(objKey, scope: .objects, arrayJSON: arrayJSON, in: json)
                        }
                    }
                    if let patched = try Self.patch(json, to: visual, group: group) { json = patched }
                    if json != onDisk { changes.reportParts[path] = json }
                } else if let data = edit.added[visual.id] {
                    changes.addedParts[path] = try Self.patch(data, to: visual, group: group) ?? data
                }
            }
            // Bị xoá: visual của file gốc hoặc bản sao đã tạo trong phiên mà không còn trong bố cục, và có trong file.
            let current = Set(edit.visuals.map(\.id)).union(edit.groups.map(\.id))
            let candidates = Set(base.visuals.map(\.id)).union(base.groups.map(\.id)).union(createdIDs[pageID] ?? [])
            for id in candidates.sorted() where !current.contains(id) {
                let path = Self.visualPath(page: pageID, id: id)
                if exists(path) {
                    changes.removedParts.insert(path)
                    removedIDs.insert(id)
                }
            }
        }

        // Trang (D5 + Wave 3A): tên, trang mới và `visualInteractions`, so với file trên đĩa.
        for pageID in order {
            let path = Self.pagePath(pageID)
            let editedInteractions = edited[pageID]?.visualInteractions
            if let created = structure.created[pageID] {
                var targetJSON = created.pageJSON
                if let interactions = editedInteractions {
                    targetJSON = try PBIRPagePatch.settingVisualInteractions(interactions, in: targetJSON)
                }
                if archive.entry(path) == nil {
                    changes.addedParts[path] = targetJSON
                } else {
                    let onDisk = try archive.read(path)
                    if onDisk != targetJSON { changes.reportParts[path] = targetJSON }
                }
            } else if exists(path), let name = page(pageID)?.displayName {
                let onDisk = try bytes(path)
                var updated = onDisk
                if (try? JSONValue.parse(updated))?["displayName"]?.string != name {
                    updated = try PBIRPagePatch.setPageDisplayName(name, in: updated)
                }
                if let interactions = editedInteractions {
                    updated = try PBIRPagePatch.settingVisualInteractions(interactions, in: updated)
                }
                if updated != onDisk { changes.reportParts[path] = updated }
            }
        }
        // Trang bị xoá: mọi part của nó; visual của nó tính là visual bị xoá (dọn bookmark như D1).
        for pageID in removedPages.sorted() {
            for path in diskPages[pageID] ?? [] {
                changes.removedParts.insert(path)
                let parts = path.split(separator: "/")
                if parts.count >= 6, parts[4] == "visuals" { removedIDs.insert(String(parts[5])) }
            }
        }
        // Thứ tự: chỉ ghi khi khác file; `activePageName` = trang đang mở (như Desktop).
        if archive.entry(Self.pagesJSONPath) != nil {
            let onDisk = try archive.read(Self.pagesJSONPath)
            let diskOrder = (try? JSONValue.parse(onDisk))?["pageOrder"]?.array.compactMap(\.string) ?? []
            if diskOrder != order {
                let active = currentPageID.flatMap { order.contains($0) ? $0 : nil } ?? order.first
                changes.reportParts[Self.pagesJSONPath] = try PBIRPagePatch.setPageOrder(order, activePage: active, in: onDisk)
            }
        }

        // Bookmark và page.json còn lại: dọn tham chiếu tới trang và visual đã xoá.
        if !removedIDs.isEmpty || !removedPages.isEmpty || !restored.isEmpty {
            var removedBookmarks = Set<String>()
            // Bookmark lấy lại từ byte lúc mở còn nhắc mọi thứ đã xoá kể từ lúc mở, kể cả phần các lần lưu trước đã dọn.
            let gonePages = removedPages.union(structure.removed)
            var goneIDs = removedIDs
            if !revivedBookmarks.isEmpty {
                for page in baseline.pages {
                    let before = Set(page.visuals.map(\.id)).union(page.groups.map(\.id))
                    if !order.contains(page.id) { goneIDs.formUnion(before) }
                    else if let edit = edited[page.id] { goneIDs.formUnion(before.subtracting(edit.visuals.map(\.id)).subtracting(edit.groups.map(\.id))) }
                }
            }
            for path in archive.entries.map(\.path) + restored.keys.filter({ archive.entry($0) == nil }).sorted() {
                let isBookmark = path.hasSuffix(".bookmark.json")
                let isPage = path.hasSuffix("/page.json") && path.hasPrefix(Self.pagesFolder)
                guard isBookmark || isPage, !changes.removedParts.contains(path) else { continue }
                let original = try bytes(path)
                var data = changes.reportParts[path] ?? original
                let revived = revivedBookmarks[path] != nil
                if isBookmark, !removedPages.isEmpty || revived {
                    switch try PBIRPagePatch.removingPageReferences(revived ? gonePages : removedPages, fromBookmark: data) {
                    case .remove:
                        changes.removedParts.insert(path)
                        changes.reportParts[path] = nil
                        if let name = BookmarkInfo(json: original)?.name { removedBookmarks.insert(name) }
                        continue
                    case .trimmed(let trimmed): data = trimmed
                    case .unchanged: break
                    }
                }
                let cleaned = isBookmark
                    ? try PBIRLayoutPatch.removingVisualReferences(revived ? goneIDs : removedIDs, fromBookmark: data)
                    : try PBIRLayoutPatch.removingVisualReferences(removedIDs, fromPage: data)
                if cleaned != original { changes.reportParts[path] = cleaned }
            }
            let indexPath = Self.bookmarksJSONPath
            let onDisk = archive.entry(indexPath) != nil ? try archive.read(indexPath) : nil
            // Bookmark có lại trong file: cần lại mục của nó trong `bookmarks.json`.
            let returning = Set(revivedBookmarks.filter { archive.entry($0.key) == nil && !changes.removedParts.contains($0.key) }.values)
            if !returning.isEmpty {
                // Lấy `bookmarks.json` lúc mở làm gốc để mục về đúng chỗ và đúng nhóm cũ: bỏ mục của bookmark không còn,
                // thêm vào cuối bookmark tạo trong phiên đã có trên đĩa.
                let diskNames = (onDisk.map(PBIRBookmarkPatch.itemNames) ?? []).filter { !removedBookmarks.contains($0) }
                let present = returning.union(diskNames)
                var index = openedParts(indexPath).first?.data
                if let opened = index {
                    index = try PBIRPagePatch.bookmarkItemsRemoving(Set(PBIRBookmarkPatch.itemNames(in: opened)).subtracting(present), from: opened)
                }
                for name in diskNames + returning.sorted() where !(index.map(PBIRBookmarkPatch.itemNames) ?? []).contains(name) {
                    index = try PBIRBookmarkPatch.addingItem(name, to: index)
                }
                if let index, index != onDisk {
                    if onDisk == nil { changes.addedParts[indexPath] = index } else { changes.reportParts[indexPath] = index }
                }
            } else if !removedBookmarks.isEmpty, let onDisk {
                let items = try PBIRPagePatch.bookmarkItemsRemoving(removedBookmarks, from: onDisk)
                if items != onDisk { changes.reportParts[indexPath] = items }
            }
        }
        // Part dựng lại: không có trên đĩa thì bản đã sửa (hoặc byte lúc mở) là part mới, bị bỏ thì không ghi gì; đang có
        // trên đĩa (bookmark đã mất mục của trang) thì ghi khi khác byte trên đĩa.
        for (path, original) in restored {
            let wanted = changes.reportParts.removeValue(forKey: path) ?? original
            if archive.entry(path) == nil {
                if changes.removedParts.remove(path) == nil { changes.addedParts[path] = wanted }
            } else if !changes.removedParts.contains(path), try archive.read(path) != wanted {
                changes.reportParts[path] = wanted
            }
        }
        saveNotes = try addReportChanges(to: &changes, archive: archive)
        for (path, bytes) in pbirPartOverrides where !changes.removedParts.contains(path) {
            if archive.entry(path) != nil {
                changes.reportParts[path] = bytes
            } else {
                changes.addedParts[path] = bytes
            }
        }
        try addSettingsChanges(to: &changes, archive: archive)
        changes.modelEdits = try writableModelDelta()
        if changes.modelEdits.hasCalculatedEdits { changes.calculatedData = try calculatedValues(changes.modelEdits) }
        if diagramEdits != savedDiagramEdits, let source = diagramSource() {
            let (moves, zoom) = diagramMoves()
            changes.diagramLayout = try DiagramLayoutPatch.applying(tabs: diagramTabsForPatch(), selected: diagramSelected(), removals: diagramRemovals(), moves: moves, zoom: zoom,
                                                                    to: source, lineageTag: diagramLineageTag)
        }
        return changes
    }

    /// `visual.json` với vị trí và nhóm của `visual`, hoặc nil khi file đã đúng. Visual trong nhóm: file ghi toạ độ tương đối
    /// so với nhóm (`group`), mô hình dùng toạ độ tuyệt đối (D7); so sánh có dung sai để số thập phân của Desktop không tạo
    /// ghi thừa. Visual có nhóm mà không tìm thấy nhóm (khoá) giữ nguyên.
    private static func patch(_ json: Data, to visual: ReportVisual, group: ReportVisual? = nil) throws -> Data? {
        if visual.parentGroup != nil, group == nil { return nil }
        let current = try PBIRLayoutPatch.position(in: json)
        let ox = group?.x ?? 0, oy = group?.y ?? 0
        func differs(_ a: Double, _ b: Double) -> Bool { abs(a - b) > 1e-6 }
        func near(_ v: Double) -> Double { v < 0 && v > -1e-6 ? 0 : v }
        let x = near(visual.x - ox), y = near(visual.y - oy)
        var out = json
        if differs(current.x, x) || differs(current.y, y) || differs(current.width, visual.width) || differs(current.height, visual.height) {
            out = try PBIRLayoutPatch.setPosition(
                in: out, x: differs(current.x, x) ? x : nil, y: differs(current.y, y) ? y : nil,
                width: differs(current.width, visual.width) ? visual.width : nil,
                height: differs(current.height, visual.height) ? visual.height : nil)
        }
        out = try PBIRGroupPatch.settingParentGroup(group?.id, in: out)
        return out == json ? nil : out
    }
}

/// `visual.json` có `visual.query.queryState` là đối tượng (D2 chỉ sửa visual đã có cấu hình trường).
private func hasQueryState(_ json: Data) -> Bool {
    guard let value = try? JSONValue.parse(json) else { return false }
    if case .object = value["visual"]?["query"]?["queryState"] ?? .null { return true }
    return false
}
