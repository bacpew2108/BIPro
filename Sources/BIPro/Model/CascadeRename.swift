// Wave 3C (T020): Cascade Rename — đổi tên bảng / cột / measure đang được dùng kèm cập nhật đồng bộ
// công thức DAX (qua DAXLexer token) và JSON PBIR (visual / page / report / bookmark) trong một bước ⌘Z.
import DAXEngine
import Foundation
import PBIXKit

enum CascadeRenameTarget: Equatable, Sendable {
    case table(old: String, new: String)
    case column(table: String, old: String, new: String)
    case measure(table: String, old: String, new: String)

    var oldDisplay: String {
        switch self {
        case .table(let old, _): old
        case .column(let t, let old, _): "\(t)[\(old)]"
        case .measure(let t, let old, _): "\(t)[\(old)]"
        }
    }

    var newName: String {
        switch self {
        case .table(_, let new): new
        case .column(_, _, let new): new
        case .measure(_, _, let new): new
        }
    }

    var oldName: String {
        switch self {
        case .table(let old, _): old
        case .column(_, let old, _): old
        case .measure(_, let old, _): old
        }
    }

    func withNewName(_ name: String) -> CascadeRenameTarget {
        switch self {
        case .table(let old, _): .table(old: old, new: name)
        case .column(let t, let old, _): .column(table: t, old: old, new: name)
        case .measure(let t, let old, _): .measure(table: t, old: old, new: name)
        }
    }
}

struct CascadeRenamePlan: Identifiable {
    let id = UUID()
    var target: CascadeRenameTarget
    /// Các thay đổi mô hình sẽ áp dụng (đổi tên + viết lại công thức DAX bị ảnh hưởng).
    let modelEdits: [ModelEdit]
    /// Các mục DAX bị viết lại (để hiện danh sách xem trước cho người dùng).
    let affectedDAXItems: [String]
    /// Các visual PBIR bị viết lại (pageID, visualID, bytes mới).
    let visualUpdates: [(pageID: String, visualID: String, label: String, data: Data)]
    /// Các phần PBIR khác (`page.json`, `report.json`, `*.bookmark.json`) bị viết lại.
    let partOverrides: [String: Data]
    let affectedPBIRLabels: [String]
    /// Lỗi kiểm tra hợp lệ (nếu tên mới rỗng / trùng); nil khi hợp lệ.
    let validationError: String?

    var totalAffectedCount: Int { affectedDAXItems.count + affectedPBIRLabels.count }
}

/// Viết lại tham chiếu bảng / cột / measure trong JSON PBIR (`SourceRef.Entity`, `Property`, `queryRef`, `nativeQueryRef`, `selector.metadata`).
enum PBIRReferenceRewriter {
    static func rewrite(data: Data, target: CascadeRenameTarget) -> (data: Data, changed: Bool) {
        let stripped = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        guard let obj = try? JSONSerialization.jsonObject(with: stripped, options: [.fragmentsAllowed]) else {
            return (data, false)
        }
        var changed = false
        let updated = rewriteNode(obj, target: target, changed: &changed)
        guard changed, let encoded = try? JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys]) else {
            return (data, false)
        }
        return (encoded, true)
    }

    private static func rewriteNode(_ node: Any, target: CascadeRenameTarget, changed: inout Bool) -> Any {
        if let arr = node as? [Any] {
            return arr.map { rewriteNode($0, target: target, changed: &changed) }
        }
        guard var dict = node as? [String: Any] else { return node }

        // 1. Trường hợp đổi tên BẢNG
        switch target {
        case .table(let oldTable, let newTable):
            // `SourceRef: { Entity: oldTable }`
            if var sr = dict["SourceRef"] as? [String: Any],
               let ent = sr["Entity"] as? String,
               ent.caseInsensitiveCompare(oldTable) == .orderedSame {
                sr["Entity"] = newTable
                dict["SourceRef"] = sr
                changed = true
            }
            // `queryRef` / `metadata` / `ExpressionName` dạng `OldTable.Prop` hoặc `Agg(OldTable.Prop)`
            for key in ["queryRef", "metadata", "ExpressionName"] {
                if let s = dict[key] as? String {
                    let rewritten = rewriteTableInQueryRef(s, oldTable: oldTable, newTable: newTable)
                    if rewritten != s { dict[key] = rewritten; changed = true }
                }
            }
            if let qRefs = dict["queryRefs"] as? [String] {
                let rewritten = qRefs.map { rewriteTableInQueryRef($0, oldTable: oldTable, newTable: newTable) }
                if rewritten != qRefs { dict["queryRefs"] = rewritten; changed = true }
            }

        case .column(let table, let oldCol, let newCol):
            if var colObj = dict["Column"] as? [String: Any],
               let prop = colObj["Property"] as? String,
               prop.caseInsensitiveCompare(oldCol) == .orderedSame,
               let expr = colObj["Expression"] as? [String: Any],
               let sr = expr["SourceRef"] as? [String: Any],
               let ent = sr["Entity"] as? String,
               ent.caseInsensitiveCompare(table) == .orderedSame {
                colObj["Property"] = newCol
                dict["Column"] = colObj
                changed = true
            }
            // Cập nhật `queryRef` / `metadata` / `ExpressionName` & `nativeQueryRef`
            let hadMatchingQueryRef = (dict["queryRef"] as? String).map { matchesFieldRef($0, table: table, field: oldCol) } ?? false
            for key in ["queryRef", "metadata", "ExpressionName"] {
                if let s = dict[key] as? String {
                    let rewritten = rewriteFieldInQueryRef(s, table: table, oldField: oldCol, newField: newCol)
                    if rewritten != s { dict[key] = rewritten; changed = true }
                }
            }
            if hadMatchingQueryRef, let native = dict["nativeQueryRef"] as? String,
               native.caseInsensitiveCompare(oldCol) == .orderedSame {
                dict["nativeQueryRef"] = newCol
                changed = true
            }
            if let qRefs = dict["queryRefs"] as? [String] {
                let rewritten = qRefs.map { rewriteFieldInQueryRef($0, table: table, oldField: oldCol, newField: newCol) }
                if rewritten != qRefs { dict["queryRefs"] = rewritten; changed = true }
            }

        case .measure(let table, let oldM, let newM):
            if var mObj = dict["Measure"] as? [String: Any],
               let prop = mObj["Property"] as? String,
               prop.caseInsensitiveCompare(oldM) == .orderedSame,
               let expr = mObj["Expression"] as? [String: Any],
               let sr = expr["SourceRef"] as? [String: Any],
               let ent = sr["Entity"] as? String,
               ent.caseInsensitiveCompare(table) == .orderedSame {
                mObj["Property"] = newM
                dict["Measure"] = mObj
                changed = true
            }
            let hadMatchingQueryRef = (dict["queryRef"] as? String).map { matchesFieldRef($0, table: table, field: oldM) } ?? false
            for key in ["queryRef", "metadata", "ExpressionName"] {
                if let s = dict[key] as? String {
                    let rewritten = rewriteFieldInQueryRef(s, table: table, oldField: oldM, newField: newM)
                    if rewritten != s { dict[key] = rewritten; changed = true }
                }
            }
            if hadMatchingQueryRef, let native = dict["nativeQueryRef"] as? String,
               native.caseInsensitiveCompare(oldM) == .orderedSame {
                dict["nativeQueryRef"] = newM
                changed = true
            }
            if let qRefs = dict["queryRefs"] as? [String] {
                let rewritten = qRefs.map { rewriteFieldInQueryRef($0, table: table, oldField: oldM, newField: newM) }
                if rewritten != qRefs { dict["queryRefs"] = rewritten; changed = true }
            }
        }

        for (k, v) in dict {
            dict[k] = rewriteNode(v, target: target, changed: &changed)
        }
        return dict
    }

    private static func rewriteTableInQueryRef(_ ref: String, oldTable: String, newTable: String) -> String {
        // Dạng `OldTable.Field...` hoặc `Sum(OldTable.Field)`
        if let openParen = ref.firstIndex(of: "("), ref.hasSuffix(")") {
            let prefix = String(ref[...openParen])
            let inner = String(ref[ref.index(after: openParen)..<ref.index(before: ref.endIndex)])
            let replaced = rewritePlainTableRef(inner, oldTable: oldTable, newTable: newTable)
            return replaced == inner ? ref : "\(prefix)\(replaced))"
        }
        return rewritePlainTableRef(ref, oldTable: oldTable, newTable: newTable)
    }

    private static func rewritePlainTableRef(_ ref: String, oldTable: String, newTable: String) -> String {
        guard let dot = ref.firstIndex(of: ".") else { return ref }
        let tablePart = String(ref[..<dot])
        guard tablePart.caseInsensitiveCompare(oldTable) == .orderedSame else { return ref }
        return newTable + String(ref[dot...])
    }

    private static func matchesFieldRef(_ ref: String, table: String, field: String) -> Bool {
        rewriteFieldInQueryRef(ref, table: table, oldField: field, newField: field + "__probe__") != ref
    }

    private static func rewriteFieldInQueryRef(_ ref: String, table: String, oldField: String, newField: String) -> String {
        if let openParen = ref.firstIndex(of: "("), ref.hasSuffix(")") {
            let prefix = String(ref[...openParen])
            let inner = String(ref[ref.index(after: openParen)..<ref.index(before: ref.endIndex)])
            let replaced = rewritePlainFieldRef(inner, table: table, oldField: oldField, newField: newField)
            return replaced == inner ? ref : "\(prefix)\(replaced))"
        }
        return rewritePlainFieldRef(ref, table: table, oldField: oldField, newField: newField)
    }

    private static func rewritePlainFieldRef(_ ref: String, table: String, oldField: String, newField: String) -> String {
        let parts = ref.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2,
              parts[0].caseInsensitiveCompare(table) == .orderedSame,
              parts[1].caseInsensitiveCompare(oldField) == .orderedSame else { return ref }
        var copy = parts
        copy[1] = newField
        return copy.joined(separator: ".")
    }
}

enum CascadeRenamePlanner {
    @MainActor
    static func buildPlan(target: CascadeRenameTarget, model: ModelMetadata, layout: LayoutEditor, workspace: Workspace) -> CascadeRenamePlan {
        let trimmedNew = target.newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = target.withNewName(trimmedNew)

        // Kiểm tra hợp lệ tên mới
        if trimmedNew.isEmpty || trimmedNew.contains("\0") {
            return CascadeRenamePlan(target: normalizedTarget, modelEdits: [], affectedDAXItems: [], visualUpdates: [],
                                     partOverrides: [:], affectedPBIRLabels: [],
                                     validationError: bi("Tên mới không hợp lệ hoặc đang trống.", "New name is empty or invalid."))
        }
        if trimmedNew == target.oldName {
            return CascadeRenamePlan(target: normalizedTarget, modelEdits: [], affectedDAXItems: [], visualUpdates: [],
                                     partOverrides: [:], affectedPBIRLabels: [],
                                     validationError: bi("Tên mới trùng với tên hiện tại.", "New name is identical to the current name."))
        }

        // 1. Tạo danh sách ModelEdit: đổi tên mục đích + viết lại toàn bộ DAX bị ảnh hưởng
        var edits: [ModelEdit] = []
        var affectedDAX: [String] = []
        let hasMeasureWithOldColName: Bool
        switch normalizedTarget {
        case .table(let old, let new):
            hasMeasureWithOldColName = false
            edits.append(.updateTable(name: old, patch: TablePatch(name: new)))
        case .column(let table, let old, let new):
            hasMeasureWithOldColName = model.measures.contains { $0.name.caseInsensitiveCompare(old) == .orderedSame }
            edits.append(.updateColumn(table: table, name: old, patch: ColumnPatch(name: new, cascade: true)))
        case .measure(let table, let old, let new):
            hasMeasureWithOldColName = false
            edits.append(.updateMeasure(table: table, name: old, patch: MeasurePatch(name: new)))
        }

        // Viết lại công thức của mọi measure
        for m in model.measures {
            let daxTarget: DAXRenameTarget
            switch normalizedTarget {
            case .table(let old, let new):
                daxTarget = .table(old: old, new: new)
            case .column(let t, let old, let new):
                daxTarget = .column(table: t, old: old, new: new, ownerTable: m.tableName, hasMeasureWithOldName: hasMeasureWithOldColName)
            case .measure(let t, let old, let new):
                if m.tableName == t && m.name == old { continue }
                daxTarget = .measure(table: t, old: old, new: new)
            }
            let newExpr = DAXEngine.rewriteReferences(in: m.expression, target: daxTarget)
            if newExpr != m.expression {
                let effectiveTable: String
                if case .table(let old, let new) = normalizedTarget, m.tableName == old {
                    effectiveTable = new
                } else {
                    effectiveTable = m.tableName
                }
                let effectiveName: String
                if case .measure(let t, let old, let new) = normalizedTarget, m.tableName == t, m.name == old {
                    effectiveName = new
                } else {
                    effectiveName = m.name
                }
                edits.append(.updateMeasure(table: effectiveTable, name: effectiveName, patch: MeasurePatch(expression: newExpr)))
                affectedDAX.append("Measure \(m.tableName)[\(m.name)]")
            }
        }

        // Viết lại công thức của mọi cột tính toán
        for c in model.columns where c.kind == .calculated {
            guard let expr = c.expression else { continue }
            let daxTarget: DAXRenameTarget
            switch normalizedTarget {
            case .table(let old, let new):
                daxTarget = .table(old: old, new: new)
            case .column(let t, let old, let new):
                if c.tableName == t && c.name == old { continue }
                daxTarget = .column(table: t, old: old, new: new, ownerTable: c.tableName, hasMeasureWithOldName: hasMeasureWithOldColName)
            case .measure(let t, let old, let new):
                daxTarget = .measure(table: t, old: old, new: new)
            }
            let newExpr = DAXEngine.rewriteReferences(in: expr, target: daxTarget)
            if newExpr != expr {
                let effectiveTable: String
                if case .table(let old, let new) = normalizedTarget, c.tableName == old {
                    effectiveTable = new
                } else {
                    effectiveTable = c.tableName
                }
                edits.append(.updateCalculatedColumn(table: effectiveTable, name: c.name, expression: newExpr, dataType: c.dataType))
                affectedDAX.append(bi("Cột tính toán \(c.tableName)[\(c.name)]", "Calculated column \(c.tableName)[\(c.name)]"))
            }
        }

        // Viết lại công thức của mọi bảng tính toán DAX
        for (calcTableName, expr) in model.calculatedTableExpressions.sorted(by: { $0.key < $1.key }) {
            let daxTarget: DAXRenameTarget
            switch normalizedTarget {
            case .table(let old, let new):
                if calcTableName == old { continue }
                daxTarget = .table(old: old, new: new)
            case .column(let t, let old, let new):
                daxTarget = .column(table: t, old: old, new: new, ownerTable: calcTableName, hasMeasureWithOldName: hasMeasureWithOldColName)
            case .measure(let t, let old, let new):
                daxTarget = .measure(table: t, old: old, new: new)
            }
            let newExpr = DAXEngine.rewriteReferences(in: expr, target: daxTarget)
            if newExpr != expr {
                let cols = model.columns
                    .filter { $0.tableName == calcTableName && $0.kind == .calculatedTableColumn }
                    .map { ColumnSignature(name: $0.name, dataType: $0.dataType) }
                edits.append(.updateCalculatedTable(name: calcTableName, expression: newExpr, columns: cols))
                affectedDAX.append(bi("Bảng tính toán \(calcTableName)", "Calculated table \(calcTableName)"))
            }
        }

        // Thử validate tổ hợp edits trên mô hình hiệu lực để bắt lỗi trùng tên sớm
        var validationError: String? = nil
        do {
            var proposed = layout.modelEdits
            for e in edits { proposed = proposed.appending(e) }
            if let runtime = workspace.runtime {
                try runtime.validate(proposed)
            }
        } catch let err as ModelEditError {
            validationError = err.reason
        } catch {
            validationError = String(describing: error)
        }

        // 2. Quét và viết lại PBIR: mọi visual trên mọi trang + page.json + report.json + bookmark.json
        var visualUpdates: [(pageID: String, visualID: String, label: String, data: Data)] = []
        var partOverrides: [String: Data] = [:]
        var affectedPBIR: [String] = []

        if workspace.pbix.reportFormat == .pbir {
            for page in layout.pages {
                for visual in layout.visuals(of: page.id) {
                    guard let currentBytes = layout.visualJSONBytes(pageID: page.id, visualID: visual.id) else { continue }
                    let (rewritten, changed) = PBIRReferenceRewriter.rewrite(data: currentBytes, target: normalizedTarget)
                    if changed {
                        let label = bi("Visual \(visual.id) (trang \(page.displayName))", "Visual \(visual.id) (page \(page.displayName))")
                        visualUpdates.append((pageID: page.id, visualID: visual.id, label: label, data: rewritten))
                        affectedPBIR.append(label)
                    }
                }
            }
            let archive = workspace.pbix.archive
            for entry in archive.entries {
                let path = entry.path
                let label: String
                if path.hasSuffix("/page.json"), path.hasPrefix("Report/definition/pages/") {
                    label = bi("Bộ lọc trang \(path.split(separator: "/").dropLast().last.map(String.init) ?? path)",
                               "Page filter \(path.split(separator: "/").dropLast().last.map(String.init) ?? path)")
                } else if path == "Report/definition/report.json" {
                    label = bi("Bộ lọc cấp báo cáo", "Report-level filters")
                } else if path.hasPrefix("Report/definition/bookmarks/"), path.hasSuffix(".bookmark.json") {
                    label = "Bookmark \(path.split(separator: "/").last.map(String.init) ?? path)"
                } else {
                    continue
                }
                let currentBytes = layout.pbirPartOverrides[path] ?? (try? archive.read(entry))
                guard let currentBytes else { continue }
                let (rewritten, changed) = PBIRReferenceRewriter.rewrite(data: currentBytes, target: normalizedTarget)
                if changed {
                    partOverrides[path] = rewritten
                    affectedPBIR.append(label)
                }
            }
        }

        return CascadeRenamePlan(
            target: normalizedTarget,
            modelEdits: edits,
            affectedDAXItems: affectedDAX,
            visualUpdates: visualUpdates,
            partOverrides: partOverrides,
            affectedPBIRLabels: affectedPBIR,
            validationError: validationError
        )
    }
}
