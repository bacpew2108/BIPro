import CoreGraphics
import DAXEngine
import Foundation
import PBIXKit

/// Phase E: lệnh sửa mô hình từ Table, Model và TMDL view (đi qua `ModelEditor`, hoàn tác chung).
extension DocumentState {
    /// Lý do chưa sửa mô hình được, hoặc nil. Ở Table, Model, TMDL view sửa được khi file có mô hình; ở Báo cáo phải bật Sửa.
    var modelEditingBlocker: String? {
        if workspace.runtime == nil { return workspace.modelError ?? bi("File không có mô hình dữ liệu để sửa.", "The file has no data model to edit.") }
        if mode == .report && !editMode { return bi("Bật chế độ Sửa (⌘E) để sửa mô hình.", "Turn on Edit mode (⌘E) to edit the model.") }
        if workspace.pbix.reportFormat == .none { return bi("File này không có báo cáo đọc được; chưa lưu được thay đổi mô hình.", "This file has no readable report; model changes can't be saved yet.") }
        return nil
    }

    func selectMeasure(table: String, name: String) {
        self.table = table
        column = nil
        measure = name
        if let m = workspace.measure(table: table, name: name) {
            measureDraft = MeasureDraft(mode: .edit(table: table, name: name),
                                        text: MeasureFormula.format(name: m.name, expression: m.expression))
        }
        if mode == .table { ribbonTab = .tableTools }
    }

    /// Từ chế độ Báo cáo (đang Sửa): chuyển sang Table view và mở measure để sửa công thức.
    func editMeasureInTableView(table: String, name: String) {
        if let blocker = modelEditingBlocker { layout.noteFieldRefusal(blocker); return }
        mode = .table
        selectMeasure(table: table, name: name)
    }

    /// Từ chế độ Báo cáo (đang Sửa): chuyển sang Table view và mở measure mới ở bảng `table`.
    func newMeasureInTableView(table: String) {
        if let blocker = modelEditingBlocker { layout.noteFieldRefusal(blocker); return }
        mode = .table
        beginNewMeasure(table: table)
    }

    /// Mở bản nháp measure mới ở bảng `table` (tên mặc định "Measure", "Measure 2"...).
    func beginNewMeasure(table: String) {
        if let blocker = modelEditingBlocker {
            layout.noteFieldRefusal(blocker)
            return
        }
        self.table = table
        column = nil
        measure = nil
        let taken = Set(workspace.measures(of: table).map { $0.name.lowercased() }
                        + workspace.columns(of: table).map { $0.name.lowercased() })
        var name = "Measure", number = 2
        while taken.contains(name.lowercased()) { name = "Measure \(number)"; number += 1 }
        measureDraft = MeasureDraft(mode: .new(table: table), text: "\(name) = ")
    }

    /// Bỏ bản nháp (nút ✗): về văn bản của measure đang chọn, hoặc đóng bản nháp mới.
    func cancelMeasureDraft() {
        guard let draft = measureDraft else { return }
        if draft.mode.isNew { measureDraft = nil } else { draft.revert() }
    }

    /// Lý do nút "Cột mới" chưa dùng được (chưa chọn bảng, không sửa được mô hình), nil khi dùng được.
    var newColumnBlocker: String? {
        if let blocker = modelEditingBlocker { return blocker }
        return table == nil ? bi("Chọn một bảng ở pane Dữ liệu trước", "Select a table in the Data pane first") : nil
    }

    /// "Cột mới" (T083): bản nháp `Cột = ` cho cột tính toán của `table` ở thanh công thức.
    func beginNewColumn(table: String) {
        if let blocker = modelEditingBlocker { layout.noteFieldRefusal(blocker); return }
        mode = .table
        self.table = table
        column = nil
        measure = nil
        let taken = Set(workspace.measures(of: table).map { $0.name.lowercased() } + workspace.columns(of: table).map { $0.name.lowercased() })
        var name = bi("Cột", "Column"), number = 2
        while taken.contains(name.lowercased()) { name = biN("Cột \(number)", "Column \(number)"); number += 1 }
        measureDraft = MeasureDraft(mode: .newColumn(table: table), text: "\(name) = ")
    }

    /// "Bảng mới" (T083): bản nháp `Bảng = ` cho bảng tính toán.
    func beginNewTable() {
        if let blocker = modelEditingBlocker { layout.noteFieldRefusal(blocker); return }
        mode = .table
        let taken = Set((workspace.metadata?.tables ?? []).map { $0.name.lowercased() })
        var name = bi("Bảng", "Table"), number = 2
        while taken.contains(name.lowercased()) { name = biN("Bảng \(number)", "Table \(number)"); number += 1 }
        measureDraft = MeasureDraft(mode: .newTable, text: "\(name) = ")
    }

    /// Áp dụng bản nháp cột/bảng tính toán. Thành công thì đóng bản nháp và chọn cột/bảng mới.
    private func applyCalculatedDraft(_ draft: MeasureDraft) async {
        draft.isApplying = true
        draft.message = nil
        defer { draft.isApplying = false }
        let name = CalculatedEditor.split(draft.text)?.name
        let reason: String?
        switch draft.mode {
        case .newColumn(let table): reason = await addCalculatedColumn(table: table, formula: draft.text)
        case .newTable: reason = await addCalculatedTable(formula: draft.text)
        case .editColumn(let table, let old): reason = await updateCalculatedColumn(table: table, name: old, formula: draft.text)
        case .editTable(let old): reason = await updateCalculatedTable(name: old, formula: draft.text)
        default: return
        }
        if let reason { draft.message = reason; return }
        switch draft.mode {
        case .editColumn(let table, _):
            // Sửa xong vẫn ở cột đó (tên có thể đã đổi), như Desktop giữ thanh công thức của cột đang chọn.
            if let name { draft.didApply(mode: .editColumn(table: table, name: name)); column = name }
            return
        case .editTable:
            draft.didApply(mode: draft.mode)
            return
        default: break
        }
        measureDraft = nil
        if case .newTable = draft.mode, let name { table = name; column = nil } else { column = name }
    }

    /// Áp dụng công thức đang gõ (nút ✓): kiểm bằng engine, suy kiểu, rồi thêm hoặc sửa measure qua `ModelEditor`.
    func applyMeasureDraft() async {
        guard let draft = measureDraft, !draft.isApplying else { return }
        if let blocker = modelEditingBlocker { draft.message = blocker; return }
        if draft.mode.isCalculated { return await applyCalculatedDraft(draft) }
        guard let parts = MeasureFormula.parse(draft.text), !parts.name.isEmpty else {
            draft.message = bi("Nhập công thức theo dạng Tên = biểu thức.", "Enter a formula in the form Name = expression.")
            return
        }
        guard !parts.expression.isEmpty else { draft.message = bi("Biểu thức đang trống.", "The expression is empty."); return }
        // Đổi tên chỉ khi không còn nơi dùng (FR-020); nếu còn nơi dùng mở hộp xác nhận Cascade Rename (Wave 3C / T020).
        if case .edit(let table, let old) = draft.mode, parts.name != old, let model = workspace.metadata {
            let usages = ModelReferences.usages(ofMeasure: table, name: old, in: model, documents: ModelReferences.documents(layout: layout, workspace: workspace))
            if !usages.isEmpty {
                draft.message = bi("Không đổi tên được: ", "Couldn't rename: ") + ModelReferences.message(usages, what: "measure \(old)")
                pendingCascadeRename = .measure(table: table, old: old, new: parts.name)
                return
            }
        }
        draft.isApplying = true
        draft.message = nil
        defer { draft.isApplying = false }
        let workspace = self.workspace
        let check = await Task.detached(priority: .userInitiated) { () -> MeasureCheck in
            guard let engine = try? workspace.daxEngine() else {
                return .failed(MeasureProblem(message: workspace.modelError ?? biN("Không có engine để kiểm biểu thức", "No engine available to check the expression")))
            }
            return await MeasureTyping.check(parts.expression, using: engine)
        }.value
        guard case .ok(let info) = check else {
            if case .failed(let problem) = check {
                let place = problem.line.map { biN(" (dòng \($0), cột \(problem.column ?? 1))", " (line \($0), column \(problem.column ?? 1))") } ?? ""
                draft.message = problem.message + place
            }
            return
        }
        let table = draft.mode.table
        let edit: ModelEdit
        switch draft.mode {
        case .new, .newColumn, .newTable, .editColumn, .editTable:
            edit = .addMeasure(NewMeasure(table: table, name: parts.name, expression: parts.expression,
                                          formatString: info.formatString, dataType: info.dataType.rawValue))
        case .edit(_, let old):
            edit = .updateMeasure(table: table, name: old, patch: MeasurePatch(
                name: parts.name != old ? parts.name : nil, expression: parts.expression, dataType: info.dataType))
        }
        if let reason = modelEditor.apply(edit, coalesceKey: "measure-formula") {
            draft.message = reason
            return
        }
        draft.didApply(table: table, name: parts.name)
        draft.preview = Self.describe(info.value)
        measure = parts.name
    }

    /// Xoá measure khỏi mô hình; chặn kèm danh sách nơi dùng. Trả lý do bị từ chối hoặc nil.
    @discardableResult
    func deleteMeasure(table: String, name: String) -> String? {
        if let blocker = modelEditingBlocker { layout.noteFieldRefusal(blocker); return blocker }
        guard let model = workspace.metadata else { return bi("File không có mô hình dữ liệu.", "The file has no data model.") }
        let usages = ModelReferences.usages(ofMeasure: table, name: name, in: model,
                                            documents: ModelReferences.documents(layout: layout, workspace: workspace))
        if !usages.isEmpty {
            let reason = bi("Không xoá được: ", "Couldn't delete: ") + ModelReferences.message(usages, what: "measure \(name)")
            layout.noteFieldRefusal(reason)
            return reason
        }
        if let reason = modelEditor.apply(.deleteMeasure(table: table, name: name)) {
            layout.noteFieldRefusal(reason)
            return reason
        }
        if measure == name { measure = nil; measureDraft = nil }
        return nil
    }

    /// Sửa thuộc tính của measure (mô tả, thư mục, định dạng, ẩn). Trả lý do bị từ chối hoặc nil.
    @discardableResult
    func updateMeasure(table: String, name: String, patch: MeasurePatch, coalesceKey: String? = nil) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        return modelEditor.apply(.updateMeasure(table: table, name: name, patch: patch), coalesceKey: coalesceKey)
    }

    /// Sửa thuộc tính của cột (không đụng dữ liệu): tên, ẩn, định dạng, tổng hợp mặc định, loại dữ liệu hiển thị, sắp xếp theo cột,
    /// thư mục, mô tả. Đổi tên bị chặn khi cột còn được dùng (FR-020). Trả lý do bị từ chối hoặc nil.
    @discardableResult
    func updateColumn(table: String, name: String, patch: ColumnPatch, coalesceKey: String? = nil) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard let model = workspace.metadata else { return bi("File không có mô hình dữ liệu.", "The file has no data model.") }
        if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != name {
            let usages = ModelReferences.usages(ofColumn: table, name: name, in: model,
                                                documents: ModelReferences.documents(layout: layout, workspace: workspace))
            if !usages.isEmpty {
                pendingCascadeRename = .column(table: table, old: name, new: renamed)
                return bi("Không đổi tên được: ", "Couldn't rename: ") + ModelReferences.message(usages, what: bi("cột \(table)[\(name)]", "column \(table)[\(name)]"))
            }
        }
        if let reason = modelEditor.apply(.updateColumn(table: table, name: name, patch: patch), coalesceKey: coalesceKey) { return reason }
        if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != name, self.table == table, column == name {
            column = renamed
        }
        return nil
    }

    /// Ẩn hoặc hiện bảng khỏi chế độ báo cáo (không đổi dữ liệu). Trả lý do bị từ chối hoặc nil.
    @discardableResult
    func setTableHidden(_ name: String, hidden: Bool) -> String? {
        if let blocker = modelEditingBlocker { relationshipNotice = blocker; return blocker }
        if let reason = modelEditor.apply(.updateTable(name: name, patch: TablePatch(isHidden: hidden))) {
            relationshipNotice = reason
            return reason
        }
        return nil
    }

    /// Mở hộp xác nhận Đổi tên lan truyền (Wave 3C / T020) cho bảng, cột hoặc measure.
    func requestCascadeRename(_ target: CascadeRenameTarget) {
        guard modelEditingBlocker == nil else {
            if let blocker = modelEditingBlocker { layout.noteFieldRefusal(blocker) }
            return
        }
        pendingCascadeRename = target
    }

    /// Thực thi Đổi tên lan truyền nguyên khối (mô hình + công thức DAX + PBIR visual/filter/bookmark) trong 1 bước ⌘Z.
    @discardableResult
    func executeCascadeRename(_ plan: CascadeRenamePlan) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        if let err = plan.validationError { return err }
        guard let runtime = workspace.runtime else { return bi("File không có mô hình dữ liệu.", "File has no data model.") }
        var proposed = layout.modelEdits
        for edit in plan.modelEdits { proposed = proposed.appending(edit) }
        do {
            try runtime.validate(proposed)
            try runtime.validateCalculations(proposed)
        } catch let error as ModelEditError {
            return error.reason
        } catch {
            return String(describing: error)
        }
        let visualPayload = plan.visualUpdates.map { (pageID: $0.pageID, visualID: $0.visualID, data: $0.data) }
        layout.commitCascadeRename(model: proposed, visualUpdates: visualPayload, partOverrides: plan.partOverrides)
        switch plan.target {
        case .table(let old, let new):
            if self.table == old { self.table = new }
        case .column(let t, let old, let new):
            if self.table == t && self.column == old { self.column = new }
        case .measure(let t, let old, let new):
            if self.table == t && self.measure == old { self.measure = new }
            if let draft = measureDraft, case .edit(let dt, let dn) = draft.mode, dt == t, dn == old {
                draft.didApply(table: t, name: new)
                draft.message = nil
            }
        }
        interaction.modelVersion += 1
        return nil
    }

    // MARK: - Wave 4B & 4C (v1.2): Mark as Date Table, RLS, Unhide All & DAX Query Sync

    /// Đánh dấu hoặc bỏ đánh dấu bảng ngày (`Table.DataCategory = "Time"`, `Column.IsKey = true`) trong 1 bước ⌘Z.
    @discardableResult
    func markAsDateTable(table: String, enabled: Bool, dateColumn: String?) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard let meta = workspace.metadata else { return bi("File không có mô hình dữ liệu.", "File has no data model.") }
        var edits: [ModelEdit] = []
        if enabled {
            guard let dateColumn, !dateColumn.isEmpty else {
                return bi("Hãy chọn cột ngày duy nhất.", "Please choose a unique date column.")
            }
            if let err = DateTableValidator.validate(table: table, column: dateColumn, workspace: workspace) {
                return err
            }
            edits.append(.updateTable(name: table, patch: TablePatch(dataCategory: .set("Time"))))
            for col in meta.columns where col.tableName == table && col.kind != .rowNumber {
                if col.name == dateColumn && !col.isKey {
                    edits.append(.updateColumn(table: table, name: col.name, patch: ColumnPatch(isKey: true)))
                } else if col.name != dateColumn && col.isKey {
                    edits.append(.updateColumn(table: table, name: col.name, patch: ColumnPatch(isKey: false)))
                }
            }
        } else {
            edits.append(.updateTable(name: table, patch: TablePatch(dataCategory: .clear)))
            for col in meta.columns where col.tableName == table && col.isKey {
                edits.append(.updateColumn(table: table, name: col.name, patch: ColumnPatch(isKey: false)))
            }
        }
        guard !edits.isEmpty else { return nil }
        return modelEditor.apply(edits)
    }

    /// Lưu toàn bộ danh sách vai trò bảo mật cấp dòng (RLS) trong 1 bước hoàn tác ⌘Z.
    @discardableResult
    func saveRLSRoles(_ roles: [(previous: String?, role: ModelMetadata.RoleDefinition)]) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard let meta = workspace.metadata else { return bi("File không có mô hình dữ liệu.", "File has no data model.") }
        let existingNames = Set(meta.roleDefinitions.map(\.name))
        let keptOriginals = Set(roles.compactMap(\.previous))
        var edits: [ModelEdit] = []
        for removed in existingNames.subtracting(keptOriginals).sorted() {
            edits.append(.deleteRole(name: removed))
        }
        for entry in roles {
            edits.append(.upsertRole(previousName: entry.previous, role: entry.role))
        }
        if let err = modelEditor.apply(edits) { return err }
        let validAfter = Set((workspace.metadata?.roleDefinitions ?? []).map(\.name))
        interaction.setActiveRLSRoles(interaction.activeRLSRoles.intersection(validAfter))
        return nil
    }

    /// Bật/tắt mô phỏng xem báo cáo dưới vai trò RLS (chỉ ở phiên hiện tại, không làm bẩn file).
    func setActiveRLSRoles(_ roles: Set<String>) {
        interaction.setActiveRLSRoles(roles)
    }

    /// Bỏ ẩn toàn bộ bảng, cột và measure đang ẩn trong mô hình (1 bước ⌘Z — menu chuột phải DataPane).
    @discardableResult
    func unhideAllModelItems() -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard let meta = workspace.metadata else { return nil }
        var edits: [ModelEdit] = []
        for t in meta.userTables where t.isHidden {
            edits.append(.updateTable(name: t.name, patch: TablePatch(isHidden: false)))
        }
        for c in meta.columns where c.isHidden && c.kind != .rowNumber {
            edits.append(.updateColumn(table: c.tableName, name: c.name, patch: ColumnPatch(isHidden: false)))
        }
        for m in meta.measures where m.isHidden {
            edits.append(.updateMeasure(table: m.tableName, name: m.name, patch: MeasurePatch(isHidden: false)))
        }
        guard !edits.isEmpty else { return nil }
        return modelEditor.apply(edits)
    }

    /// Định dạng văn bản DAX của tab DAX Query đang mở (Wave 4C).
    func formatActiveDAXQuery() {
        guard daxQueries.indices.contains(daxSelection) else { return }
        daxQueries[daxSelection].text = DAXEngine.format(daxQueries[daxSelection].text)
    }

    /// Quét `DEFINE MEASURE ...` trong tab DAX Query đang mở và mở hộp xác nhận Cập nhật mô hình.
    func prepareDAXUpdateModel() {
        guard modelEditingBlocker == nil, let meta = workspace.metadata, daxQueries.indices.contains(daxSelection) else { return }
        let items = DAXModelSync.extractMeasures(from: daxQueries[daxSelection].text, existingModel: meta)
        pendingDAXModelUpdates = items
    }

    /// Kiểm engine và áp dụng danh sách measure từ DAX Query View vào mô hình trong 1 bước ⌘Z.
    func applyDAXDefinedMeasures(_ items: [DAXDefinedMeasure]) async -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard !items.isEmpty else { return nil }
        var edits: [ModelEdit] = []
        let ws = self.workspace
        let defineLines = items.map { item -> String in
            let safeTable = item.table.replacingOccurrences(of: "'", with: "''")
            return "MEASURE '\(safeTable)'[\(item.name)] = \(item.expression)"
        }
        let definePrefix = "DEFINE\n" + defineLines.joined(separator: "\n")
        for item in items {
            let check = await Task.detached(priority: .userInitiated) { () -> MeasureCheck in
                guard let engine = try? ws.daxEngine() else {
                    return .failed(MeasureProblem(message: ws.modelError ?? biN("Không có engine DAX", "No DAX engine")))
                }
                return await MeasureTyping.check(item.expression, definePrefix: definePrefix, using: engine)
            }.value
            guard case .ok(let info) = check else {
                if case .failed(let problem) = check {
                    return "\(item.id): \(problem.message)"
                }
                return bi("Biểu thức không hợp lệ cho \(item.id).", "Invalid expression for \(item.id).")
            }
            switch item.kind {
            case .create:
                edits.append(.addMeasure(NewMeasure(table: item.table, name: item.name, expression: item.expression,
                                                    formatString: info.formatString, dataType: info.dataType.rawValue)))
            case .update:
                edits.append(.updateMeasure(table: item.table, name: item.name,
                                            patch: MeasurePatch(expression: item.expression, dataType: info.dataType)))
            }
        }
        return modelEditor.apply(edits)
    }

    /// Áp dụng văn bản TMDL đã sửa (`drafts`: đường dẫn → văn bản mới; tài liệu không có trong `drafts` giữ nguyên). Nguyên khối:
    /// có lỗi cú pháp, mục ngoài phạm vi hoặc thao tác không hợp lệ thì không đổi gì và trả danh sách lý do; thành công thì mọi
    /// thay đổi là một bước hoàn tác chung. Trả rỗng khi thành công.
    func applyTMDL(drafts: [String: String]) -> [TMDLIssue] {
        if let blocker = modelEditingBlocker { return [TMDLIssue(path: "", line: nil, message: blocker)] }
        guard let runtime = workspace.runtime else { return [TMDLIssue(path: "", line: nil, message: bi("File không có mô hình dữ liệu để sửa.", "The file has no data model to edit."))] }
        let current = workspace.tmdlDocuments
        let old = current.map { (path: $0.path, text: $0.text) }
        var new = old.map { (path: $0.path, text: drafts[$0.path] ?? $0.text) }
        for (path, text) in drafts.sorted(by: { $0.key < $1.key }) where !current.contains(where: { $0.path == path }) { new.append((path, text)) }
        let result = TMDLParser.edits(old: old, new: new)
        guard result.issues.isEmpty else { return result.issues }
        guard !result.edits.isEmpty else { return [] }
        var proposed = layout.modelEdits
        for edit in result.edits.items { proposed = proposed.appending(edit) }
        do { try runtime.validate(proposed) } catch let error as ModelEditError {
            return [TMDLIssue(path: "", line: nil, message: error.reason)]
        } catch { return [TMDLIssue(path: "", line: nil, message: "\(error)")] }
        layout.commitModel(proposed)
        return []
    }

    /// Tên các tab bố cục trong file (theo thứ tự).
    private var fileDiagramNames: [String] { workspace.diagramLayout?.diagrams.map(\.name) ?? [] }

    /// Tên các tab bố cục hiện có, đã tính thêm và đổi tên chưa lưu.
    var diagramTabs: [String] { layout.diagramEdits.tabs ?? fileDiagramNames }

    /// Tab bố cục đang xem (mặc định "All tables"; tab đã bị hoàn tác mất thì về tab đầu).
    var currentDiagram: String {
        let tabs = diagramTabs
        if let name = diagramName, tabs.isEmpty || tabs.contains(name) { return name }
        return tabs.first ?? "All tables"
    }

    /// Tab trong file ứng với tên tab hiện tại (theo chỉ số nguồn, vì tab đổi tên vẫn là tab đó); nil với tab mới thêm.
    func fileDiagram(for tab: String) -> DiagramLayout.Diagram? {
        guard let diagrams = workspace.diagramLayout?.diagrams else { return nil }
        guard let entries = layout.diagramEdits.entries else { return diagrams.first { $0.name == tab } }
        guard let source = entries.first(where: { $0.name == tab })?.source, source < diagrams.count else { return nil }
        return diagrams[source]
    }

    /// Bảng hiện trong tab: nil = mọi bảng (tab đầu "All tables", hoặc file chưa có `DiagramLayout`); tab khác chỉ hiện các bảng
    /// đã có nút trong file (trừ nút đã gỡ) hoặc đã được đặt vào.
    func diagramTables(_ tab: String) -> Set<String>? {
        guard workspace.diagramLayout != nil, let index = diagramTabs.firstIndex(of: tab), index > 0 else { return nil }
        let inFile = Set(fileDiagram(for: tab)?.nodes.map(\.table) ?? []).subtracting(layout.diagramEdits.removed[tab] ?? [])
        return inFile.union(layout.diagramEdits.positions[tab]?.keys.map { $0 } ?? [])
    }

    /// Vị trí thẻ bảng hiệu lực (đã kéo hoặc trong file); nil khi chưa có (bố cục tự động).
    func cardPosition(table: String) -> CGPoint? {
        if let moved = layout.diagramEdits.positions[currentDiagram]?[table] { return moved }
        return fileDiagram(for: currentDiagram)?.nodes.first { $0.table == table }.map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// Chọn tab bố cục: kèm thu phóng của tab đó (Desktop nhớ thu phóng theo tab).
    func selectDiagram(_ name: String) {
        diagramName = name
        let percent = layout.diagramEdits.zoom[name] ?? fileDiagram(for: name)?.zoom ?? 100
        if percent > 0 { modelZoom = min(2, max(0.3, percent / 100)) }
    }

    /// Thêm tab bố cục trống "Layout N" và chuyển sang nó (như nút "+" của Desktop).
    func addDiagramTab() {
        relationshipNotice = nil
        guard workspace.diagramLayout != nil else { relationshipNotice = bi("File không có DiagramLayout nên chưa thêm được bố cục.", "The file has no DiagramLayout, so a layout can't be added yet."); return }
        var edits = layout.diagramEdits
        let name = edits.addTab(existing: fileDiagramNames)
        layout.commitDiagram(edits)
        selectDiagram(name)
    }

    /// Đổi tên tab bố cục; trả lý do bị từ chối (cũng hiện ở thanh báo).
    @discardableResult
    func renameDiagramTab(_ old: String, to name: String) -> String? {
        relationshipNotice = nil
        var edits = layout.diagramEdits
        if let reason = edits.renameTab(from: old, to: name, existing: fileDiagramNames) {
            relationshipNotice = reason
            return reason
        }
        layout.commitDiagram(edits)
        if diagramName == old { diagramName = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    /// Xoá tab bố cục (các bảng vẫn ở trong mô hình). Hoàn tác được. Tab đầu không xoá được. Tab đang xem bị xoá thì chuyển sang tab
    /// liền trước.
    @discardableResult
    func deleteDiagramTab(_ name: String) -> String? {
        relationshipNotice = nil
        var edits = layout.diagramEdits
        let before = diagramTabs
        if let reason = edits.deleteTab(name, existing: fileDiagramNames) {
            relationshipNotice = reason
            return reason
        }
        layout.commitDiagram(edits)
        if diagramName == name, let index = before.firstIndex(of: name) { selectDiagram(before[max(0, index - 1)]) }
        return nil
    }

    /// Gỡ thẻ bảng khỏi tab đang xem ("Remove from diagram" của Desktop): bảng, cột và quan hệ trong mô hình không đổi.
    func removeTableFromCurrentDiagram(_ table: String) {
        let tab = currentDiagram
        guard diagramTables(tab)?.contains(table) == true else { return }
        var edits = layout.diagramEdits
        edits.removeTable(table, from: tab, inFile: fileDiagram(for: tab)?.nodes.contains { $0.table == table } == true)
        layout.commitDiagram(edits)
        if self.table == table { relationship = nil }
    }

    /// Đặt bảng vào tab đang xem ở chỗ trống (nút mới như Desktop khi kéo bảng vào).
    func addTableToCurrentDiagram(_ table: String, frames: [String: CGRect]) {
        let tab = currentDiagram
        guard diagramTables(tab) != nil, !frames.keys.contains(table) else { return }
        let placed = autoLayout([table], avoiding: frames)
        guard let frame = placed[table] else { return }
        var edits = layout.diagramEdits
        edits.place(table: table, in: tab, at: frame.origin)
        layout.commitDiagram(edits)
    }

    /// "Auto layout": đặt mọi bảng chưa có trong tab đang xem theo bố cục sao.
    func autoLayoutCurrentDiagram(frames: [String: CGRect]) {
        let tab = currentDiagram
        guard diagramTables(tab) != nil else { return }
        let missing = workspace.userTables.map(\.name).filter { !frames.keys.contains($0) }
        guard !missing.isEmpty else { return }
        var edits = layout.diagramEdits
        for (table, frame) in autoLayout(missing, avoiding: frames).sorted(by: { $0.key < $1.key }) { edits.place(table: table, in: tab, at: frame.origin) }
        layout.commitDiagram(edits)
    }

    func cardHeight(_ table: String) -> CGFloat {
        let rows = workspace.columns(of: table).count + workspace.measures(of: table).count
        return min(300, 46 + CGFloat(min(rows, 11)) * 22)
    }

    /// Bố cục sao cho các bảng chưa có vị trí: bảng chiều ở trên và dưới, bảng sự kiện ở giữa.
    func autoLayout(_ tables: [String], avoiding existing: [String: CGRect]) -> [String: CGRect] {
        let relationships = workspace.metadata?.relationships ?? []
        let facts = tables.filter { t in relationships.contains { $0.fromTable == t } }
        let dims = tables.filter { !facts.contains($0) }
        let width: CGFloat = 234, gapX: CGFloat = 90, gapY: CGFloat = 140
        let originY = (existing.values.map(\.maxY).max() ?? 0) + (existing.isEmpty ? 40 : 80)
        var frames: [String: CGRect] = [:]
        let top = Array(dims.prefix((dims.count + 1) / 2)), bottom = Array(dims.dropFirst((dims.count + 1) / 2))
        let columns = max(top.count, bottom.count, facts.count)
        func row(_ items: [String], y: CGFloat) {
            let offset = CGFloat(columns - items.count) * (width + gapX) / 2
            for (i, t) in items.enumerated() {
                frames[t] = CGRect(x: 40 + offset + CGFloat(i) * (width + gapX), y: y, width: width, height: cardHeight(t))
            }
        }
        row(top, y: originY)
        let factY = originY + (top.map(cardHeight).max() ?? 0) + gapY
        row(facts, y: factY)
        row(bottom, y: factY + (facts.map(cardHeight).max() ?? 0) + gapY)
        return frames
    }

    /// Thả thẻ bảng ở `point`: một bước hoàn tác (các lần kéo liên tiếp cùng thẻ gộp lại). `original` mặc định là vị trí hiện tại.
    func moveCard(table: String, to point: CGPoint, original: CGPoint? = nil, coalesce: Bool = false) {
        var edits = layout.diagramEdits
        edits.move(table: table, in: currentDiagram, to: point, original: original ?? cardPosition(table: table) ?? point)
        layout.commitDiagram(edits, coalesceKey: coalesce ? "drag-\(table)" : nil)
    }

    /// Về vị trí thẻ trong file cho tab đang xem.
    func resetDiagramPositions() {
        var edits = layout.diagramEdits
        edits.resetPositions(in: currentDiagram)
        layout.commitDiagram(edits)
    }

    /// Ghi thu phóng của tab đang xem (phần trăm) để lưu vào file.
    func commitDiagramZoom() {
        var edits = layout.diagramEdits
        let original = fileDiagram(for: currentDiagram)?.zoom ?? 100
        edits.setZoom((modelZoom * 100).rounded(), in: currentDiagram, original: original)
        layout.commitDiagram(edits, coalesceKey: "zoom")
    }

    /// Sửa thuộc tính của quan hệ (hướng lọc, hoạt động). Trả lý do bị từ chối hoặc nil.
    @discardableResult
    func updateRelationship(name: String, patch: RelationshipPatch) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        return modelEditor.apply(.updateRelationship(name: name, patch: patch))
    }

    /// Kéo `drag` thả lên `drop` ở Model view: đề xuất quan hệ (chờ xác nhận) hoặc báo lý do không tạo được.
    func proposeRelationship(drag: RelationshipDraft.ColumnRef, drop: RelationshipDraft.ColumnRef) {
        relationshipNotice = nil
        if let blocker = modelEditingBlocker { relationshipNotice = blocker; return }
        guard let model = workspace.metadata, workspace.abf != nil else { relationshipNotice = bi("File không có mô hình dữ liệu để sửa.", "The file has no data model to edit."); return }
        let workspace = self.workspace
        // Phía một là cột có giá trị duy nhất: số giá trị phân biệt bằng số dòng của bảng.
        let isUnique: (RelationshipDraft.ColumnRef) -> Bool = { ref in
            guard let storage = workspace.runtime?.base.storage(table: ref.table, column: ref.column) else { return false }
            return storage.cardinality >= workspace.rowCount(ref.table)
        }
        switch RelationshipDraft.propose(model: model, drag: drag, drop: drop, isUnique: isUnique) {
        case .success(let draft):
            relationship = nil
            measure = nil
            measureDraft = nil
            relationshipDraft = draft
        case .failure(let refusal):
            relationshipDraft = nil
            relationshipNotice = refusal.reason
        }
    }

    /// Xác nhận đề xuất (hộp xác nhận): `crossFiltering` 1 hoặc 2, `isActive` chỉ bật được khi đề xuất không bị buộc không hoạt động.
    func confirmRelationshipDraft(crossFiltering: Int, isActive: Bool) {
        guard var draft = relationshipDraft else { return }
        if let blocker = modelEditingBlocker { relationshipNotice = blocker; return }
        draft.relationship.crossFilteringBehavior = crossFiltering
        draft.relationship.isActive = draft.forcedInactive ? false : isActive
        if let reason = modelEditor.apply(.addRelationship(draft.relationship)) {
            relationshipNotice = reason
            return
        }
        relationshipDraft = nil
        relationshipNotice = nil
        relationship = draft.relationship.name
    }

    func cancelRelationshipDraft() {
        relationshipDraft = nil
    }

    /// Xoá quan hệ (⌘Z đưa lại). Trả lý do bị từ chối hoặc nil.
    @discardableResult
    func deleteRelationship(name: String) -> String? {
        if let blocker = modelEditingBlocker { relationshipNotice = blocker; return blocker }
        if let reason = modelEditor.apply(.deleteRelationship(name: name)) {
            relationshipNotice = reason
            return reason
        }
        relationshipNotice = nil
        if relationship == name { relationship = nil }
        return nil
    }

    private static func describe(_ value: Value) -> String {
        switch value {
        case .blank: bi("(trống)", "(empty)")
        case .integer(let v): v.formatted()
        case .double(let v): v.formatted()
        case .currency(let v): (Double(v) / 10_000).formatted()
        case .string(let v): "\"\(v)\""
        case .boolean(let v): v ? "TRUE" : "FALSE"
        case .dateTime(let v): biN("ngày \(v)", "date \(v)")
        }
    }
}
