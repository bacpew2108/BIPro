// specs/011, US6 (T042): Parquet lược đồ lồng. `build/f2-out/samples/nested.parquet` (`scripts/f2-samples/make_f2_samples.py`, pyarrow,
// 6 dòng): struct `s`, list `l`, list of struct `ls`, struct lồng struct và list `d` (độ sâu 2), có NULL, danh sách rỗng, phần tử NULL.
// Đáp án là giá trị pyarrow đọc ra từ cùng tệp. Cột phẳng của tệp cũ không đổi (`ParquetSourceTests`, `ParquetGoldenTests`).
import Foundation
import Testing
import ColumnStore
@testable import Connectors

@Suite struct ParquetNestedTests {
    static let file: URL? = {
        let url = FFixtures.root.appendingPathComponent("build/f2-out/samples/nested.parquet")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    private func rec(_ fields: [(String, ParquetValue)]) -> ParquetValue { .record(fields.map { ParquetField(name: $0.0, value: $0.1) }) }
    private func i(_ v: Int64) -> ParquetValue { .scalar(.integer(v)) }
    private func s(_ v: String) -> ParquetValue { .scalar(.string(v)) }
    private func d(_ v: Double) -> ParquetValue { .scalar(.double(v)) }

    @Test(.enabled(if: file != nil)) func dungLaiStructVaList() throws {
        let table = try ParquetFile(url: try #require(Self.file)).read(rowLimit: nil, progress: nil)
        #expect(table.columns.map(\.name) == ["id", "s", "l", "ls", "d"])
        #expect(table.rowCount == 6)
        func cells(_ column: Int) -> [ParquetValue] {
            (0..<6).map { table.structured[column]?[$0] as? ParquetValue ?? .null }
        }
        #expect(cells(1) == [rec([("a", i(1)), ("b", s("một"))]), rec([("a", .null), ("b", s("hai"))]), .null,
                             rec([("a", i(4)), ("b", .null)]), rec([("a", i(5)), ("b", s("năm"))]), rec([("a", i(6)), ("b", s(""))])])
        #expect(cells(2) == [.list([i(1), i(2), i(3)]), .list([]), .null, .list([.null, i(5)]), .list([i(7)]), .list([i(8), i(9)])])
        #expect(cells(3) == [.list([rec([("x", i(1)), ("y", s("a"))]), rec([("x", i(2)), ("y", s("b"))])]), .list([]), .null,
                             .list([rec([("x", .null), ("y", s("c"))])]), .list([.null]), .list([rec([("x", i(6)), ("y", s("Đà Nẵng"))])])])
        #expect(cells(4) == [rec([("inner", rec([("v", d(1.5))])), ("tags", .list([s("x"), s("y")]))]),
                             rec([("inner", .null), ("tags", .list([]))]), .null,
                             rec([("inner", rec([("v", .null)])), ("tags", .null)]),
                             rec([("inner", rec([("v", d(-2.25))])), ("tags", .list([s("z")]))]),
                             rec([("inner", rec([("v", d(0))])), ("tags", .list([.null]))])])
        // Cột giữ chỗ: "Record"/"List", ô null là null.
        #expect(table.columns[1].data.value(at: 0) == .string("Record") && table.columns[1].data.value(at: 2) == .blank)
        #expect(table.columns[2].data.value(at: 1) == .string("List"))
        #expect(table.columns[0].data.value(at: 5) == .integer(6))
        #expect(table.columns.map(\.sourceType) == [nil, .record, .list, .list, .record])
        // Xem trước 2 dòng.
        let preview = try ParquetFile(url: try #require(Self.file)).read(rowLimit: 2, progress: nil)
        #expect(preview.rowCount == 2 && (preview.structured[2]?[0] as? ParquetValue) == .list([i(1), i(2), i(3)]))
    }

    @Test func doSauVaMapBaoChuaHoTro() throws {
        // Lược đồ: id, m (MAP), deep (struct struct struct struct v): ném "Chưa hỗ trợ" kèm tên cột.
        func element(_ name: String, physical: Int? = nil, repetition: Int = 1, children: Int = 0, converted: Int? = nil) -> ParquetSchemaElement {
            var e = ParquetSchemaElement([:])
            e.name = name; e.physical = physical; e.repetition = repetition; e.children = children; e.converted = converted
            return e
        }
        var index = 0
        let deep = [element("deep", children: 1), element("a", children: 1), element("b", children: 1), element("c", children: 1),
                    element("v", physical: 2)]
        let node = ParquetNode.build(deep, &index, parentDefinition: 0, parentRepetition: 0, parentPath: [])
        #expect(node.nesting == 4 && node.nesting > ParquetFile.maxNesting)
        index = 0
        let map = [element("m", children: 1, converted: 1), element("key_value", repetition: 2, children: 2),
                   element("key", physical: 6, repetition: 0), element("value", physical: 2)]
        #expect(ParquetNode.build(map, &index, parentDefinition: 0, parentRepetition: 0, parentPath: []).unsupportedReason()?.contains("MAP") == true)
    }
}
