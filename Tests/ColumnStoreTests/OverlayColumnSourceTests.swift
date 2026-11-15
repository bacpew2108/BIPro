// Phase F, T020: nguồn cột chồng (bảng nạp mới/thay thế chồng lên kho cột gốc). Seam: ColumnStore(source: OverlayColumnSource).
import Testing
@testable import ColumnStore

@Suite struct OverlayColumnSourceTests {
    private let dimID = TableID(raw: 1), factID = TableID(raw: 2), newID = TableID(raw: 3)

    private func column(_ table: TableID, _ index: Int, _ name: String, _ type: DAXType) -> ModelSchema.Column {
        ModelSchema.Column(id: ColumnID(table: table, index: index), name: name, type: type, isCalculated: false,
                           isHidden: false, isKey: false, sortByColumn: nil, formatString: nil)
    }

    /// Gốc: Dim(Key) 3 dòng, Fact(Key, Amount) 4 dòng.
    private func base() -> ColumnStore {
        let dim = ModelSchema.Table(id: dimID, name: "Dim", isHidden: false, isUserTable: true, isDateTable: false,
                                    columns: [column(dimID, 10, "Key", .integer)])
        let fact = ModelSchema.Table(id: factID, name: "Fact", isHidden: false, isUserTable: true, isDateTable: false,
                                     columns: [column(factID, 20, "Key", .integer), column(factID, 21, "Amount", .double)])
        let schema = ModelSchema(culture: "en-US", tables: [dim, fact], relationships: [])
        let source = InMemoryColumnSource(
            schema: schema, rowCounts: [dimID: 3, factID: 4],
            columns: [ColumnID(table: dimID, index: 10): ColumnBuilder.integers([1, 2, 3]),
                      ColumnID(table: factID, index: 20): ColumnBuilder.integers([1, 1, 2, 3]),
                      ColumnID(table: factID, index: 21): ColumnBuilder.doubles([10, 20, 30, 40])])
        return ColumnStore(source: source)
    }

    private func newData() throws -> TableData {
        try TableData(columns: [TableColumn(name: "Key", data: ColumnBuilder.integers([3, 3, 1])),
                                TableColumn(name: "Qty", data: ColumnBuilder.integers([5, nil, 7])),
                                TableColumn(name: "Region", data: ColumnBuilder.strings(["x", "y", nil]))])
    }

    private func newSchema(includingFact: Bool = true) -> ModelSchema {
        let existing = base().schema
        let added = ModelSchema.Table(
            id: newID, name: "Sales", isHidden: false, isUserTable: true, isDateTable: false,
            columns: [column(newID, 30, "Key", .integer), column(newID, 31, "Qty", .integer), column(newID, 32, "Region", .string)])
        return ModelSchema(culture: "en-US", tables: existing.tables.filter { includingFact || $0.id != factID } + [added],
                           relationships: [])
    }

    @Test func bangMoiDocTuTableDataVaBangGocQuaKhoGoc() throws {
        let overlay = OverlayColumnSource(base: base(), schema: newSchema(), tables: [newID: try newData()])
        #expect(try overlay.rowCount(newID) == 3)
        #expect(try overlay.rowCount(dimID) == 3)
        #expect(try overlay.rowCount(factID) == 4)
        let qty = try overlay.loadColumn(ColumnID(table: newID, index: 31))
        #expect([qty.value(at: 0), qty.value(at: 1), qty.value(at: 2)] == [.integer(5), .blank, .integer(7)])
        let region = try overlay.loadColumn(ColumnID(table: newID, index: 32))
        #expect(region.value(at: 0) == .string("x"))
        #expect(region.value(at: 2) == .blank)
        let amount = try overlay.loadColumn(ColumnID(table: factID, index: 21))
        #expect(amount.value(at: 3) == .double(40))
    }

    @Test func bangThayTheDungDuLieuMoiGiuID() throws {
        let replacement = try TableData(columns: [TableColumn(name: "Key", data: ColumnBuilder.integers([9])),
                                                  TableColumn(name: "Amount", data: ColumnBuilder.doubles([1.5]))])
        let overlay = OverlayColumnSource(base: base(), schema: base().schema, tables: [factID: replacement])
        #expect(try overlay.rowCount(factID) == 1)
        #expect(try overlay.loadColumn(ColumnID(table: factID, index: 20)).value(at: 0) == .integer(9))
        #expect(try overlay.loadColumn(ColumnID(table: factID, index: 21)).value(at: 0) == .double(1.5))
        // Bảng không chồng vẫn là dữ liệu gốc.
        #expect(try overlay.rowCount(dimID) == 3)
    }

    @Test func khoCotChayDuocTrenNguonChong() throws {
        let store = ColumnStore(source: OverlayColumnSource(base: base(), schema: newSchema(), tables: [newID: try newData()]))
        #expect(try store.rowCount(newID) == 3)
        #expect(try store.column(ColumnID(table: newID, index: 31)).rowCount == 3)
        // Dùng chung cột đã giải mã của kho gốc: không đọc lại từ nguồn.
        let first = try store.column(ColumnID(table: dimID, index: 10))
        #expect(first.value(at: 2) == .integer(3))
    }

    @Test func tenCotKhongPhanBietKhoangTrang() throws {
        let data = try TableData(columns: [TableColumn(name: " Key ", data: ColumnBuilder.integers([1]))])
        let table = ModelSchema.Table(id: newID, name: "T", isHidden: false, isUserTable: true, isDateTable: false,
                                      columns: [column(newID, 40, "Key", .integer)])
        let overlay = OverlayColumnSource(base: base(), schema: ModelSchema(culture: "en-US", tables: [table], relationships: []),
                                          tables: [newID: data])
        #expect(try overlay.loadColumn(ColumnID(table: newID, index: 40)).value(at: 0) == .integer(1))
    }

    @Test func cotKhongCoDuLieuHoacSaiKieuBaoLoi() throws {
        let overlay = OverlayColumnSource(base: base(), schema: newSchema(), tables: [newID: try newData()])
        // Lược đồ có cột mà TableData không có.
        let extra = ModelSchema.Table(id: newID, name: "Sales", isHidden: false, isUserTable: true, isDateTable: false,
                                      columns: [column(newID, 30, "Key", .integer), column(newID, 99, "Thieu", .integer),
                                                column(newID, 31, "Qty", .string)])
        let broken = OverlayColumnSource(base: base(), schema: ModelSchema(culture: "en-US", tables: [extra], relationships: []),
                                         tables: [newID: try newData()])
        #expect(throws: ColumnStoreError.self) { try broken.loadColumn(ColumnID(table: newID, index: 99)) }
        #expect(throws: ColumnStoreError.self) { try broken.loadColumn(ColumnID(table: newID, index: 31)) }   // Qty là số, lược đồ nói chuỗi
        #expect(throws: ColumnStoreError.self) { try overlay.loadColumn(ColumnID(table: newID, index: 777)) }
    }

    @Test func bangGocKhongCoTrongKhoGocBaoLoi() throws {
        let overlay = OverlayColumnSource(base: base(), schema: newSchema(), tables: [:])
        // `Sales` có trong lược đồ nhưng không có TableData lẫn kho gốc.
        #expect(throws: ColumnStoreError.self) { try overlay.rowCount(newID) }
        #expect(throws: ColumnStoreError.self) { try overlay.loadColumn(ColumnID(table: newID, index: 31)) }
    }

    @Test func bangBiXoaKhoiLuocDoKhongTruyCapDuoc() throws {
        let overlay = OverlayColumnSource(base: base(), schema: newSchema(includingFact: false), tables: [newID: try newData()])
        #expect(overlay.schema.table(named: "Fact") == nil)
        #expect(try overlay.rowCount(dimID) == 3)
    }
}
