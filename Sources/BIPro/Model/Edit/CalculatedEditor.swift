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
        let result: ResultTable
        do { result = try engine.calculatedTable(expression: expression) } catch {
            throw ModelEditError("Biểu thức của bảng \(name) lỗi: \(error.message)")
        }
        guard !result.columns.isEmpty else { throw ModelEditError("Bảng \(name) không có cột nào") }
        var columns: [ColumnSignature] = []
        for (index, column) in result.columns.enumerated() {
            let type: DAXType
            do { type = try CalculatedData.inferType(result.rows.map { $0[index] }) } catch {
                throw ModelEditError("Bảng \(name), cột \(column): \(error.message)")
            }
            columns.append(ColumnSignature(name: column, dataType: dataType(type)))
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
            case .addCalculatedColumn(let table, let name, _, _): try add(table, name)
            case .addCalculatedTable(let name, _, let columns): for column in columns { try add(name, column.name) }
            default: continue
            }
        }
        return out
    }
}
