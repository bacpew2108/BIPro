// Catalog nhiều lớp (LANG, đợt 1a): lớp model, rồi lớp DEFINE của truy vấn che lên trên.
// - Lớp model: bảng và cột lấy từ ModelSchema; measure lấy từ ModelMetadata.measures (hoặc danh sách tay).
// - Lớp DEFINE: MEASURE, COLUMN, VAR, TABLE khai báo trong DEFINE của một truy vấn. Tên trùng với
//   model thì DEFINE thắng.
// Tra cứu không phân biệt hoa thường, vì tên DAX không phân biệt hoa thường.
// Measure có ID là chỉ số trong `measures`: model trước, DEFINE nối sau.

import ColumnStore
import PBIXKit

/// Một measure hoặc cột tính toán trong catalog.
public struct CatalogMeasure: Sendable {
    public enum Origin: Sendable, Hashable {
        /// Measure của model.
        case model
        /// MEASURE khai báo trong DEFINE.
        case define
        /// COLUMN khai báo trong DEFINE (cột tính toán, dùng dạng T[c]).
        case defineColumn
    }

    public let id: MeasureID
    public let table: String
    public let name: String
    public let origin: Origin
    /// Văn bản biểu thức gốc, không kèm dấu bằng. Rỗng với mục DEFINE đã có AST sẵn.
    public let text: String
    /// AST sau parse. nil khi parse lỗi (xem `parseError`).
    public let body: Expr?
    /// Lỗi parse của measure model. Lỗi của một measure không làm hỏng catalog.
    public let parseError: DAXError?
    public let formatString: String?
}

/// Dữ liệu một measure của model, đưa vào catalog khi không dùng ModelMetadata.
public struct ModelMeasureInput: Sendable, Hashable {
    public let table: String
    public let name: String
    public let expression: String
    public let formatString: String?
    /// Biểu thức định dạng động (`FormatStringDefinition`), nếu có. Catalog sinh thêm measure ẩn
    /// `_<tên> FormatString` cùng bảng, như Power BI dùng trong truy vấn visual (C1.md §2.1, PA-D2-2).
    public let formatStringDefinition: String?

    public init(table: String, name: String, expression: String, formatString: String? = nil,
                formatStringDefinition: String? = nil) {
        self.table = table
        self.name = name
        self.expression = expression
        self.formatString = formatString
        self.formatStringDefinition = formatStringDefinition
    }

    /// Tên measure ẩn chứa định dạng động của measure `name`.
    public static func formatStringMeasureName(_ name: String) -> String { "_\(name) FormatString" }
}

public struct Catalog: Sendable {
    public let schema: ModelSchema
    /// Mọi measure và cột tính toán. ID của một measure là chỉ số trong mảng này.
    public private(set) var measures: [CatalogMeasure]
    /// Biến DEFINE VAR: tên thường → slot trong frame của truy vấn.
    public private(set) var defineVariables: [String: Int]
    /// Bảng DEFINE TABLE: tên thường → slot trong frame của truy vấn.
    public private(set) var defineTables: [String: Int]

    /// Tên thường → ID measure. Mục DEFINE ghi đè mục model cùng tên.
    private var measureByName: [String: Int]
    /// "bảng\0tên" thường → ID, cho cả measure và cột DEFINE.
    private var measureByQualifiedName: [String: Int]

    /// Catalog chỉ có lược đồ, không có measure.
    public init(schema: ModelSchema) {
        self.init(schema: schema, measures: [])
    }

    /// Catalog với lược đồ và danh sách measure của model.
    public init(schema: ModelSchema, measures inputs: [ModelMeasureInput]) {
        self.schema = schema
        self.measures = []
        self.defineVariables = [:]
        self.defineTables = [:]
        self.measureByName = [:]
        self.measureByQualifiedName = [:]
        for input in inputs {
            let (body, error) = Catalog.parse(input.expression)
            appendMeasure(table: input.table, name: input.name, origin: .model, text: input.expression,
                          body: body, parseError: error, formatString: input.formatString)
        }
        // Measure ẩn `_<tên> FormatString` (sau mọi measure thật để không đổi ID của chúng).
        // [SUY ĐOÁN] Bỏ qua nếu model đã có measure trùng tên.
        for input in inputs {
            guard let definition = input.formatStringDefinition, !definition.isEmpty else { continue }
            let name = ModelMeasureInput.formatStringMeasureName(input.name)
            guard measureByQualifiedName[Catalog.qualifiedKey(input.table, name)] == nil else { continue }
            let (body, error) = Catalog.parse(definition)
            // SELECTEDMEASURE() trong biểu thức định dạng là chính measure M.
            let bound = body.map { Catalog.replacingSelectedMeasure($0, table: input.table, name: input.name) }
            appendMeasure(table: input.table, name: name, origin: .model, text: definition,
                          body: bound, parseError: error, formatString: nil)
        }
    }

    /// Thay `SELECTEDMEASURE()` bằng tham chiếu `'table'[name]` (dùng cho biểu thức định dạng động).
    /// [SUY ĐOÁN] SELECTEDMEASURENAME/SELECTEDMEASUREFORMATSTRING chưa gặp trong Nhom6 nên chưa thay.
    static func replacingSelectedMeasure(_ e: Expr, table: String, name: String) -> Expr {
        func go(_ e: Expr) -> Expr { replacingSelectedMeasure(e, table: table, name: name) }
        switch e {
        case .call(let fn, let args, let range):
            if fn.uppercased() == "SELECTEDMEASURE", args.allSatisfy({ $0 == nil }) {
                return .columnRef(table: table, column: name, range)
            }
            return .call(name: fn, args: args.map { $0.map(go) }, range)
        case .unary(let op, let x, let r): return .unary(op, go(x), r)
        case .binary(let op, let a, let b, let r): return .binary(op, go(a), go(b), r)
        case .varBlock(let vars, let body, let r):
            return .varBlock(vars: vars.map { VarBinding(name: $0.name, value: go($0.value)) }, body: go(body), r)
        case .tableConstructor(let rows, let r): return .tableConstructor(rows: rows.map { $0.map(go) }, r)
        default: return e
        }
    }

    /// Catalog dựng từ metadata của một file .pbix (đã đọc ABF).
    public init(metadata: ModelMetadata) {
        let inputs = metadata.measures.map {
            ModelMeasureInput(table: $0.tableName, name: $0.name, expression: $0.expression,
                              formatString: $0.formatString, formatStringDefinition: $0.formatStringDefinition)
        }
        self.init(schema: ModelSchema(metadata: metadata), measures: inputs)
    }

    // MARK: - Lớp DEFINE

    /// MEASURE khai báo trong DEFINE. Thân giữ nguyên AST, bind khi cần qua Binder.bindMeasure.
    public mutating func defineMeasure(table: String, name: String, body: Expr) {
        appendMeasure(table: table, name: name, origin: .define, text: "", body: body,
                      parseError: nil, formatString: nil)
    }

    /// COLUMN khai báo trong DEFINE (cột tính toán). Chỉ truy cập được qua T[c].
    public mutating func defineColumn(table: String, name: String, body: Expr) {
        appendMeasure(table: table, name: name, origin: .defineColumn, text: "", body: body,
                      parseError: nil, formatString: nil)
    }

    /// VAR khai báo trong DEFINE, có slot do Binder cấp.
    public mutating func defineVariable(name: String, slot: Int) {
        defineVariables[name.lowercased()] = slot
    }

    /// TABLE khai báo trong DEFINE, có slot do Binder cấp.
    public mutating func defineTable(name: String, slot: Int) {
        defineTables[name.lowercased()] = slot
    }

    // MARK: - Tra cứu

    /// Bảng của model theo tên (không phân biệt hoa thường).
    public func modelTable(named name: String) -> ModelSchema.Table? {
        schema.table(named: name)
    }

    /// Cột của model theo bảng và tên.
    public func modelColumn(table: String, name: String) -> ModelSchema.Column? {
        schema.column(table: table, name: name)
    }

    /// Measure theo ID.
    public func measure(_ id: MeasureID) -> CatalogMeasure? {
        let i = Int(id.raw)
        return i >= 0 && i < measures.count ? measures[i] : nil
    }

    /// Measure hoặc cột DEFINE theo tên. Khi có `table`, thử khớp cả bảng trước, rồi mới khớp theo tên.
    /// Cột DEFINE chỉ khớp khi có `table`.
    public func measure(named name: String, table: String? = nil) -> CatalogMeasure? {
        if let table {
            let qualified = Catalog.qualifiedKey(table, name)
            if let i = measureByQualifiedName[qualified] {
                return measures[i]
            }
        }
        if let i = measureByName[name.lowercased()] {
            return measures[i]
        }
        return nil
    }

    /// Cột tính toán DEFINE COLUMN theo bảng và tên.
    public func definedColumn(table: String, name: String) -> CatalogMeasure? {
        guard let i = measureByQualifiedName[Catalog.qualifiedKey(table, name)] else { return nil }
        let m = measures[i]
        return m.origin == .defineColumn ? m : nil
    }

    // MARK: - Nội bộ

    private mutating func appendMeasure(table: String, name: String, origin: CatalogMeasure.Origin,
                                        text: String, body: Expr?, parseError: DAXError?,
                                        formatString: String?) {
        let index = measures.count
        measures.append(CatalogMeasure(id: MeasureID(raw: Int32(index)), table: table, name: name,
                                       origin: origin, text: text, body: body, parseError: parseError,
                                       formatString: formatString))
        measureByQualifiedName[Catalog.qualifiedKey(table, name)] = index
        if origin != .defineColumn {
            measureByName[name.lowercased()] = index
        }
    }

    private static func qualifiedKey(_ table: String, _ name: String) -> String {
        table.lowercased() + "\u{0}" + name.lowercased()
    }

    private static func parse(_ text: String) -> (Expr?, DAXError?) {
        do {
            return (try parseExpression(text), nil)
        } catch {
            return (nil, error)
        }
    }
}
