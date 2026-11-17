import ColumnStore
import DAXEngine
import Foundation
import PBIXKit

/// Phase F (T082): thêm cột và bảng tính toán. Biểu thức được tính thử trên engine của mô hình hiệu lực để bắt lỗi (cú pháp, tên, kiểu
/// lẫn) và suy kiểu dữ liệu trước khi thành thao tác `ModelEdit`; sau đó engine của phiên tự tính lại khi mô hình đổi (`ModelRuntime`).
/// Thứ tự tạo cũng là thứ tự phụ thuộc: biểu thức chỉ tham chiếu được cột đã có, nên cột mới không thể tham chiếu chính nó hay cột tạo sau.
enum CalculatedEditor {
    /// Tách "Tên = biểu thức" của thanh công thức (dấu `=` đầu tiên). Nil khi thiếu tên hoặc biểu thức.
    static func split(_ formula: String) -> (name: String, expression: String)? {
        guard let equals = formula.firstIndex(of: "=") else { return nil }
        var name = formula[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("[") && name.hasSuffix("]") && name.count >= 2 { name = String(name.dropFirst().dropLast()) }
        let expression = formula[formula.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !expression.isEmpty else { return nil }
        return (name, expression)
    }

    /// Thao tác thêm cột tính toán sau khi tính thử. Ném lỗi (tiếng Việt) khi biểu thức sai hoặc trả nhiều kiểu.
    static func columnEdit(table: String, name: String, expression: String, engine: DAXEngine) throws -> ModelEdit {
        let values: [Value]
        do { values = try engine.calculatedColumn(table: table, expression: expression) } catch {
            throw ModelEditError("Biểu thức của cột \(name) lỗi: \(error.message)")
        }
        let type: DAXType
        do { type = try CalculatedData.inferType(values) } catch { throw ModelEditError("Cột \(name): \(error.message)") }
        return .addCalculatedColumn(table: table, name: name, expression: expression, dataType: dataType(type))
    }

    /// Thao tác thêm bảng tính toán sau khi tính thử: tên và kiểu từng cột kết quả.
    static func tableEdit(name: String, expression: String, engine: DAXEngine) throws -> ModelEdit {
        let result: ResultTable, sources: [String]
        do { (result, sources) = try engine.calculatedTableWithSources(expression: expression) } catch {
            throw ModelEditError("Biểu thức của bảng \(name) lỗi: \(error.message)")
        }
        guard !result.columns.isEmpty else { throw ModelEditError("Bảng \(name) không có cột nào") }
        var columns: [ColumnSignature] = []
        for (index, column) in result.columns.enumerated() {
            let type: DAXType
            do { type = try CalculatedData.inferType(result.rows.map { $0[index] }) } catch {
                throw ModelEditError("Bảng \(name), cột \(column): \(error.message)")
            }
            columns.append(ColumnSignature(name: column, dataType: dataType(type), sourceColumn: sources[index]))
        }
        return .addCalculatedTable(name: name, expression: expression, columns: columns)
    }

    static func dataType(_ type: DAXType) -> ModelMetadata.DataType {
        switch type {
        case .integer: .int64
        case .double: .double
        case .currency: .decimal
        case .string: .string
        case .boolean: .boolean
        case .dateTime: .dateTime
        }
    }
}

extension DocumentState {
    /// "Cột mới": thêm cột tính toán vào `table`. Trả lý do bị từ chối hoặc nil. Một bước hoàn tác.
    func addCalculatedColumn(table: String, formula: String) async -> String? {
        guard let (name, expression) = CalculatedEditor.split(formula) else { return "Công thức cần dạng Tên = biểu thức DAX" }
        let workspace = self.workspace
        let built: Result<ModelEdit, Error> = await Task.detached {
            Result { try CalculatedEditor.columnEdit(table: table, name: name, expression: expression, engine: try workspace.daxEngine()) }
        }.value
        switch built {
        case .success(let edit): return modelEditor.apply(edit)
        case .failure(let error): return (error as? ModelEditError)?.reason ?? (error as? DAXError)?.message ?? "\(error)"
        }
    }

    /// "Bảng mới": thêm bảng tính toán. Trả lý do bị từ chối hoặc nil. Một bước hoàn tác.
    func addCalculatedTable(formula: String) async -> String? {
        guard let (name, expression) = CalculatedEditor.split(formula) else { return "Công thức cần dạng Tên = biểu thức DAX" }
        let workspace = self.workspace
        let built: Result<ModelEdit, Error> = await Task.detached {
            Result { try CalculatedEditor.tableEdit(name: name, expression: expression, engine: try workspace.daxEngine()) }
        }.value
        switch built {
        case .success(let edit): return modelEditor.apply(edit)
        case .failure(let error): return (error as? ModelEditError)?.reason ?? (error as? DAXError)?.message ?? "\(error)"
        }
    }
}

extension DocumentState {
    /// Sửa công thức cột tính toán `table[name]` (T116) từ văn bản thanh công thức `Tên = biểu thức`. Tên khác thì đổi tên cột cùng bước
    /// (chặn khi còn được dùng). Giá trị và kiểu tính lại; cột/bảng tính toán phụ thuộc cũng tính lại. Trả lý do bị từ chối hoặc nil.
    func updateCalculatedColumn(table: String, name: String, formula: String) async -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard let (newName, expression) = CalculatedEditor.split(formula) else { return "Công thức cần dạng Tên = biểu thức DAX" }
        guard let model = workspace.metadata,
              model.columns.contains(where: { $0.tableName == table && $0.name == name && $0.kind == .calculated }) else {
            return "Không có cột tính toán \(table)[\(name)]"
        }
        if DAXEngine.references(in: expression).contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && ($0.table == nil || $0.table?.caseInsensitiveCompare(table) == .orderedSame)
        }) {
            return "Cột \(name) không thể tham chiếu chính nó (phụ thuộc vòng)"
        }
        if newName != name {
            let usages = ModelReferences.usages(ofColumn: table, name: name, in: model,
                                                documents: ModelReferences.documents(layout: layout, workspace: workspace))
            if !usages.isEmpty { return "Không đổi tên được: " + ModelReferences.message(usages, what: "cột \(table)[\(name)]") }
        }
        let workspace = self.workspace
        let built: Result<ModelEdit, Error> = await Task.detached {
            Result { try CalculatedEditor.columnEdit(table: table, name: name, expression: expression, engine: try workspace.daxEngine()) }
        }.value
        switch built {
        case .success(.addCalculatedColumn(_, _, let body, let dataType)):
            var edits: [ModelEdit] = [.updateCalculatedColumn(table: table, name: name, expression: body, dataType: dataType)]
            if newName != name { edits.append(.updateColumn(table: table, name: name, patch: ColumnPatch(name: newName))) }
            return modelEditor.apply(edits)
        case .success: return "Không dựng được thao tác sửa cột"
        case .failure(let error): return (error as? ModelEditError)?.reason ?? (error as? DAXError)?.message ?? "\(error)"
        }
    }

    /// Sửa công thức bảng tính toán `name` (T116). Đổi tên bảng ở thanh công thức chưa hỗ trợ. Trả lý do bị từ chối hoặc nil.
    func updateCalculatedTable(name: String, formula: String) async -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard let (newName, expression) = CalculatedEditor.split(formula) else { return "Công thức cần dạng Tên = biểu thức DAX" }
        guard workspace.userTables.contains(where: { $0.name == name && $0.isCalculatedUserTable }) else {
            return "Không có bảng tính toán \(name)"
        }
        guard newName == name else { return "Chưa đổi tên được bảng tính toán ở thanh công thức; giữ tên \(name)" }
        if DAXEngine.tableNames(in: expression)?.contains(name.lowercased()) == true
            || DAXEngine.references(in: expression).contains(where: { $0.table?.caseInsensitiveCompare(name) == .orderedSame }) {
            return "Bảng \(name) không thể tham chiếu chính nó (phụ thuộc vòng)"
        }
        let workspace = self.workspace
        let built: Result<ModelEdit, Error> = await Task.detached {
            Result { try CalculatedEditor.tableEdit(name: name, expression: expression, engine: try workspace.daxEngine()) }
        }.value
        switch built {
        case .success(.addCalculatedTable(_, let body, let columns)):
            return modelEditor.apply(.updateCalculatedTable(name: name, expression: body, columns: columns))
        case .success: return "Không dựng được thao tác sửa bảng"
        case .failure(let error): return (error as? ModelEditError)?.reason ?? (error as? DAXError)?.message ?? "\(error)"
        }
    }

    /// Xoá cột tính toán (T116, "Xoá khỏi mô hình" sau khi xác nhận). Chặn kèm nơi dùng (báo cáo, measure, cột, quan hệ…).
    @discardableResult
    func deleteCalculatedColumn(table: String, name: String) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard let model = workspace.metadata else { return "File không có mô hình dữ liệu." }
        let usages = ModelReferences.usages(ofColumn: table, name: name, in: model,
                                            documents: ModelReferences.documents(layout: layout, workspace: workspace))
        if !usages.isEmpty { return "Không xoá được: " + ModelReferences.message(usages, what: "cột \(table)[\(name)]") }
        if let reason = modelEditor.apply(.deleteCalculatedColumn(table: table, name: name)) { return reason }
        if self.table == table, column == name { column = nil; measureDraft = nil }
        return nil
    }

    /// Xoá bảng tính toán (T116): như gỡ bảng (`dropTable`), chặn khi measure, quan hệ, cột/bảng tính toán khác hay báo cáo còn dùng.
    @discardableResult
    func deleteCalculatedTable(name: String) -> String? {
        if let blocker = modelEditingBlocker { return blocker }
        guard workspace.userTables.contains(where: { $0.name == name && $0.isCalculatedUserTable }) else {
            return "Bảng \(name) không phải bảng tính toán; chỉ xoá được bảng tính toán"
        }
        if let reason = modelEditor.apply(.dropTable(name: name)) { return reason }
        if table == name { table = nil; column = nil; measureDraft = nil }
        return nil
    }
}

extension ModelRuntime {
    /// Giá trị đã tính (engine của phiên) của cột/bảng tính toán trong `edits`, dạng bộ ghi cần (T084). Mục đang lỗi thì không lưu.
    func calculatedValues(for edits: ModelEdits) throws -> [String: VertiPaqWriter.Values] {
        let engine = try engine()
        let errors = calculationErrors
        var out: [String: VertiPaqWriter.Values] = [:]
        func add(_ table: String, _ column: String) throws {
            if let error = errors["\(table)[\(column)]"] ?? errors[table] {
                throw ModelEditError("Chưa lưu được: \(table)[\(column)] đang lỗi (\(error))")
            }
            guard let id = engine.store.schema.column(table: table, name: column)?.id else {
                throw ModelEditError("Không tìm thấy cột tính toán \(table)[\(column)] để lưu")
            }
            let data = try engine.store.column(id)
            out["\(table)[\(column)]"] = try TableLoader.values(of: TableColumn(name: column, data: data), rows: try engine.store.rowCount(id.table))
        }
        for edit in edits.items {
            switch edit {
            case .addCalculatedColumn(let table, let name, _, _), .updateCalculatedColumn(let table, let name, _, _): try add(table, name)
            case .addCalculatedTable(let name, _, let columns), .updateCalculatedTable(let name, _, let columns):
                for column in columns { try add(name, column.name) }
            default: continue
            }
        }
        return out
    }
}
