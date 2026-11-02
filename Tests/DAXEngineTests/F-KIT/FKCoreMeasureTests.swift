// Measure Trans Count và Trans Amount của MiniBank chạy qua DAXEngine.evaluate (F-KIT lõi, đợt 2).
// Đáp án: MiniBankExpected (sinh bởi Python stdlib). Mỗi dòng đáp án là một bộ lọc theo quy ước của file đó.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct FKCoreMeasureTests {

    /// Đổi chuỗi bộ lọc "Bảng[cột]=giá trị && …" thành mục bộ lọc. "(BLANK)" là BLANK.
    private func parseFilters(_ text: String) throws -> [FilterItem] {
        guard !text.isEmpty else { return [] }
        var items: [FilterItem] = []
        for part in text.components(separatedBy: " && ") {
            let pieces = part.components(separatedBy: "=")
            guard pieces.count == 2, let open = pieces[0].firstIndex(of: "["), pieces[0].hasSuffix("]") else {
                throw DAXError(.syntax, "bộ lọc không đọc được: \(part)")
            }
            let table = String(pieces[0][..<open])
            let column = String(pieces[0][pieces[0].index(after: open)..<pieces[0].index(before: pieces[0].endIndex)])
            guard let meta = MiniBank.schema.column(table: table, name: column) else {
                throw DAXError(.unknownName, "không có cột \(table)[\(column)]")
            }
            let raw = pieces[1]
            let value: Value
            if raw == "(BLANK)" {
                value = .blank
            } else if meta.type == .integer, let n = Int64(raw) {
                value = .integer(n)
            } else {
                value = .string(raw)
            }
            items.append(FilterItem(column: meta.id, values: [value]))
        }
        return items
    }

    private func expectedValue(_ value: MiniBankExpectedValue) -> Value {
        switch value {
        case .integer(let n): return .integer(n)
        case .currency(let n): return .currency(n)
        case .double(let d): return .double(d)
        case .blank: return .blank
        }
    }

    @Test func measureMiniBankKhopDapAn() async throws {
        let engine = DAXEngine(store: MiniBank.makeStore(), catalog: Catalog(
            schema: MiniBank.schema,
            measures: MiniBank.measures.map { ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression) }))
        let dapAn = MiniBankExpected.all.filter { ["Trans Count", "Trans Amount"].contains($0.measure) }
        #expect(dapAn.count == 12)
        for item in dapAn {
            let filters = try parseFilters(item.filter)
            let value = try await engine.evaluate(measure: item.measure, table: "Fact_Trans", filters: filters)
            #expect(value == expectedValue(item.value), "\(item.measure) với bộ lọc \"\(item.filter)\": \(item.note)")
        }
    }

    @Test func measureTransCountTrongEngineCoThuVien() async throws {
        let engine = DAXEngine(store: MiniBank.makeStore(), catalog: Catalog(
            schema: MiniBank.schema,
            measures: MiniBank.measures.map { ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression) }))
        #expect(try await engine.evaluate(measure: "Trans Count", table: nil, filters: []) == .integer(40))
        #expect(try await engine.evaluate(measure: "Trans Amount", table: nil, filters: []) == .currency(1_254_298_000))
    }
}
